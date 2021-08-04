import ../zmq
import std/[unittest, os]

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
      check  topic == topic1
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
      check  topic == topic2
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
      check  topic == ""
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

when isMainModule:
  reqrep()
  pubsub()
  inproc_sharectx()
  routerdealer()
  pairpair()

