import ../zmq
import std/[unittest, os, times, monotimes]
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

proc curve() =
  test "curve":
    if not hasCurve():
      skip()
      return
    const sockaddr = "tcp://127.0.0.1:55009"
    let (serverPub, serverSec) = curveKeypair()
    let (clientPub, clientSec) = curveKeypair()
    let (roguePub, rogueSec) = curveKeypair()

    var server = listen(sockaddr, REP) do (s: ZSocket) -> void:
      s.setCurveServer(serverSec)
    defer: server.close()
    var client = connect(sockaddr, REQ) do (s: ZSocket) -> void:
      s.setCurveClient(serverPub, clientPub, clientSec)
    defer: client.close()

    client.send("hello, encrypted")
    check server.receive() == "hello, encrypted"

    # a client that does not know the server's real public key must not get a reply
    var badAddr = "tcp://127.0.0.1:55010"
    var badServer = listen(badAddr, REP) do (s: ZSocket) -> void:
      s.setCurveServer(serverSec)
    defer: badServer.close()
    var badClient = connect(badAddr, REQ) do (s: ZSocket) -> void:
      s.setCurveClient(roguePub, clientPub, clientSec)  # wrong server key
    defer: badClient.close()
    badClient.setsockopt(RCVTIMEO, 300.cint)
    badClient.send("should not be decrypted")
    let (msgAvailable, _, _) = badClient.waitForReceive(300)
    check not msgAvailable

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
    router.setsockopt(RCVTIMEO, 500.cint)

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
      let start = getMonoTime()
      # On receive return empty message
      let
        recv = router.receive()
        stop = getMonoTime()
        elapsed = stop - start
      check (elapsed - initDuration(milliseconds=500)) < initDuration(milliseconds=1)
      check recv == ""

    block:
      # On try receive, check flag is flase
      let
        start = getMonoTime()
        recv = router.waitForReceive(350)
        stop = getMonoTime()
        elapsed = stop - start
      check (elapsed - initDuration(milliseconds=350)) < initDuration(milliseconds=1)
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
      let content = pairs[1].waitForReceive()
      check content.msgAvailable
      check content.moreAvailable
      check content.msg == ping

    block:
      let content = pairs[1].waitForReceive()
      check content.msgAvailable
      check content.moreAvailable
      check content.msg == ping

    block:
      let content = pairs[1].waitForReceive()
      check content.msgAvailable
      check (not content.moreAvailable)
      check content.msg == ping

    block:
      let content = pairs[1].waitForReceive()
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
        let res= x.tryReceive()
        if res.msgAvailable:
          let msg = res.msg
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
        let res = x.tryReceive()
        if res.msgAvailable:
          let msg = res.msg
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

proc non_blocking_recv() =
  const sockaddr = "tcp://127.0.0.1:55001"
  test "non-blocking receive":
    var router = listen(sockaddr, mode = ROUTER)
    let res = router.tryReceive()
    check res == (false, false, "")

    var dealer = connect(sockaddr, mode = DEALER)
    let payload = "payload"
    block:
      # Dealer send a message to router
      dealer.send(payload)

    block:
      # Remove "envelope" of router / dealer
      let dealerSocketId = router.receive()
      let res = router.waitForReceive(250)
      check res.msgAvailable
      check not res.moreAvailable
      check res.msg == payload

    block:
      # Remove "envelope" of router / dealer
      let
        start = getMonoTime()
        res = router.waitForReceive(250)
        stop = getMonoTime()
        elapsed = stop - start
      check (elapsed - initDuration(milliseconds=250)) < initDuration(milliseconds=1)

      check not res.msgAvailable
      check not res.moreAvailable
      check res.msg == ""

    router.close(250)
    dealer.close(250)

proc sockopt_widths() =
  test "setsockopt takes the width from the option, not from the Nim literal":
    var c = connect("tcp://127.0.0.1:55020", REQ)
    defer: c.close()
    # C-int options given a bare (8-byte) Nim int literal used to fail with EINVAL
    c.setsockopt(REQ_RELAXED, 1)
    c.setsockopt(REQ_CORRELATE, 1)
    c.setsockopt(RCVTIMEO, 123)
    c.setsockopt(LINGER, 0)
    c.setsockopt(IMMEDIATE, true)
    check c.getsockopt[:cint](RCVTIMEO) == 123
    check c.getsockopt[:cint](LINGER) == 0
    check c.getsockopt[:cint](IMMEDIATE) == 1
    # the two options that are not C int
    c.setsockopt(MAXMSGSIZE, 4096)
    check c.getsockopt[:int64](MAXMSGSIZE) == 4096
    c.setsockopt(AFFINITY, 3)
    check c.getsockopt[:uint64](AFFINITY) == 3
    # explicit widths keep working
    c.setsockopt(SNDTIMEO, 77.cint)
    check c.getsockopt[:cint](SNDTIMEO) == 77

proc req_relaxed_after_timeout() =
  test "a REQ with REQ_RELAXED can send again after a receive timed out":
    var req = connect("tcp://127.0.0.1:55021", REQ)   # nobody listens: the reply never comes
    defer: req.close()
    req.setsockopt(RCVTIMEO, 50)
    req.send("one")
    check req.receive() == ""                          # EAGAIN, REQ now waits for a reply
    expect ZmqError:
      req.send("two")                                  # strict REQ: EFSM
    req.setsockopt(REQ_RELAXED, 1)
    req.setsockopt(REQ_CORRELATE, 1)
    req.send("three")                                  # relaxed: allowed

when isMainModule:
  reqrep()
  curve()
  pubsub()
  inproc_sharectx()
  routerdealer()
  pairpair()
  async_pub_sub()
  asyncpoll()
  non_blocking_recv()
  sockopt_widths()
  req_relaxed_after_timeout()
