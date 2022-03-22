import ../zmq
import std/[unittest, os]
import std/[asyncdispatch, asyncfutures]

proc reqrep() =
  test "reqrep":
    const sockaddr = "tcp://127.0.0.1:55001"
    let
      ping = "ping"
      pong = "pong"

    var rep = listen(sockaddr, REP)
    defer: rep.close()
    var req = connect(sockaddr, REQ)
    defer: req.close()

    block:
      req.send(ping)
      let r = rep.receive()
      check r == ping
    block:
      rep.send(pong)
      let r = req.receive()
      check r == pong

proc pubsub() =
  test "pubsub":
    const sockaddr = "tcp://127.0.0.1:55001"
    let
      topic1 = "topic1"
      topic2 = "topic2"

    var pub = listen(sockaddr, PUB)
    defer: pub.close()
    var broadcast = connect(sockaddr, SUB)
    defer: broadcast.close()
    var sub1 = connect(sockaddr, SUB)
    defer: sub1.close()
    var sub2 = connect(sockaddr, SUB)
    defer: sub2.close()
    # Subscribe to all topic
    broadcast.setsockopt(SUBSCRIBE, "")
    # Subscribe to topic
    sub1.setsockopt(SUBSCRIBE, topic1)
    sub2.setsockopt(SUBSCRIBE, topic2)

    # Slow-joiner pattern -> PUB / SUB Pattern needs a bit of time to establish connection
    sleep(200)

    # Topic1
    pub.send(topic1, SNDMORE)
    pub.send("content1")
    block alltopic:
      let topic = broadcast.receive()
      let msg = broadcast.receive()
      check topic == topic1
      check msg == "content1"
    block s1:
      let topic = sub1.receive()
      let msg = sub1.receive()
      check topic == topic1
      check msg == "content1"

    # Topic2
    pub.send(topic2, SNDMORE)
    pub.send("content2")
    block alltopic:
      let topic = broadcast.receive()
      let msg = broadcast.receive()
      check topic == topic2
      check msg == "content2"
    block s2:
      let topic = sub2.receive()
      let msg = sub2.receive()
      check topic == topic2
      check msg == "content2"

    # Broadcast
    pub.send("", SNDMORE)
    pub.send("content3")
    block alltopic:
      let topic = broadcast.receive()
      let msg = broadcast.receive()
      check topic == ""
      check msg == "content3"

proc routerdealer() =
  test "routerdealer":
    const sockaddr = "tcp://127.0.0.1:55001"
    var router = listen(sockaddr, mode = ROUTER)
    router.setsockopt(RCVTIMEO, 350.cint)
    defer: router.close()
    var dealer = connect(sockaddr, mode = DEALER)
    defer: dealer.close()

    let payload = "payload"
    # Dealer send a message to router
    dealer.send(payload)
    # Remove "envelope" of router / dealer
    let dealerSocketId = router.receive()
    let msg = router.receive()
    check msg == payload
    # Reply to the Dealer
    router.send(dealerSocketId, SNDMORE)
    router.send(payload)
    check dealer.receive() == payload
    # Let receive timeout
    block:
      # On receive return empty message
      let recv = router.receive()
      check recv == ""
    block:
      # On try receive, check flag is flase
      let recv = router.tryReceive()
      check recv.msgAvailable == false

proc inproc_sharectx() =
  test "inproc":
    # AFAIK, inproc only works for Linux
    when defined(linux):
      # Check sharing context works for inproc
      let
        inprocpath = getTempDir() / "nimzmq"
        sockaddr = "inproc://" & inprocpath
      var
        server = listen(sockaddr, PAIR)
        client = connect(sockaddr, PAIR, server.context)

      client.send("Hello")
      check server.receive() == "Hello"
      server.send("World")
      check client.receive() == "World"

      client.close()
      server.close()

    else:
      discard

proc pairpair() =
  test "pairpair_sndmore":
    const sockaddr = "tcp://127.0.0.1:55001"
    let
      ping = "ping"
      pong = "pong"

    var pairs = @[listen(sockaddr, PAIR), connect(sockaddr, PAIR)]
    pairs[1].setsockopt(RCVTIMEO, 500.cint)
    block:
      pairs[0].send(ping, SNDMORE)
      pairs[0].send(ping, SNDMORE)
      pairs[0].send(ping)

    block:
      let content = pairs[1].tryReceive()
      check content.msgAvailable
      check content.moreAvailable
      check content.msg == ping

    block:
      let content = pairs[1].tryReceive()
      check content.msgAvailable
      check content.moreAvailable
      check content.msg == ping

    block:
      let content = pairs[1].tryReceive()
      check content.msgAvailable
      check (not content.moreAvailable)
      check content.msg == ping

    block:
      let content = pairs[1].tryReceive()
      check (not content.msgAvailable)

    block:
      let msgs = [pong, pong, pong]
      pairs[1].sendAll(msgs)
      let contents = pairs[0].receiveAll()
      check contents == msgs

    for p in pairs.mitems:
      p.close()

proc asyncDummy(i: int) {.async.} =
  # echo "asyncDummy=", i
  asyncCheck sleepAsync(2500)

proc asyncpoll() =
  test "asyncZPoller":
    const zaddr = "tcp://127.0.0.1:15571"
    const zaddr2 = "tcp://127.0.0.1:15572"
    var pusher = listen(zaddr, PUSH)
    var puller = connect(zaddr, PULL)

    var pusher2 = listen(zaddr2, PUSH)
    var puller2 = connect(zaddr2, PULL)
    var poller: AsyncZPoller

    var i = 0
    # Register the callback
    # Check message received are correct (should be even integer in string format)
    var msglist = @["0", "2", "4", "6", "8"]
    var msgCount = 0
    poller.register(
      puller2,
      ZMQ_POLLIN,
      proc(x: ZSocket) =
        let msg = x.receive()
        inc(msgCount)
        if msglist.contains(msg):
          msglist.delete(0)
          check true
        else:
          check false
    )
    # Check message received are correct (should be even integer in string format)
    var msglist2 = @["0", "2", "4", "6", "8"]
    var msgCount2 = 0
    poller.register(
      puller,
      ZMQ_POLLIN,
      proc(x: ZSocket) =
        let msg = x.receive()
        inc(msgCount2)
        if msglist2.contains(msg):
          msglist2.delete(0)
          check true
        else:
          check false
    )

    let
      N = 10
      N_MAX_TIMEOUT = 5

    var sndCount = 0
    # A client send some message
    for i in 0..<N:
      if (i mod 2) == 0:
        # Can periodically send stuff
        pusher.send($i)
        pusher2.send($i)
        inc(sndCount)

    # N_MAX_TIMEOUT is the number of time the poller can timeout before exiting the loop
    while i < N_MAX_TIMEOUT:

      # I don't recommend a high timeout because it's going to poll for the duration if there is no message in queue
      var fut = poller.pollAsync(1)
      let r = waitFor fut
      if r < 0:
        break # error case
      elif r == 0:
        inc(i)

    # No longer polling but some callback may not have finished
    while hasPendingOperations():
      drain()

    check msgCount == msgCount2
    check msgCount == sndCount

    pusher.close()
    puller.close()
    pusher2.close()
    puller2.close()

proc async_pub_sub() =
  const N_MSGS = 10

  proc publisher {.async.} =
    var publisher = zmq.listen("tcp://127.0.0.1:5571", PUB)
    defer: publisher.close()
    sleep(150) # Account for slow joiner pattern

    var n = 0
    while n < N_MSGS:
      publisher.send("topic", SNDMORE)
      publisher.send("test " & $n)
      await sleepAsync(100)
      inc n

  proc subscriber : Future[int] {.async.} =
    var subscriber = zmq.connect("tcp://127.0.0.1:5571", SUB)
    defer: subscriber.close()
    sleep(150) # Account for slow joiner pattern
    subscriber.setsockopt(SUBSCRIBE, "")
    var count = 0
    while count < N_MSGS:
      var msg = await subscriber.receiveAsync()
      # echo msg
      inc(count)
    result = count

  let p = publisher()
  let s = subscriber()
  waitFor p
  let count = waitFor s
  test "async pub_sub":
    check count == N_mSGS

when isMainModule:
  reqrep()
  pubsub()
  inproc_sharectx()
  routerdealer()
  pairpair()
  async_pub_sub()
  asyncpoll()
