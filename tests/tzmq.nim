import zmq
import os

proc reqrep() =
  const sockaddr = "tcp://127.0.0.1:55001"
  let
    ping = "ping"
    pong = "pong"

  var
    rep = listen(sockaddr, REP)
    req = connect(sockaddr, REQ)

  req.send(ping)
  assert rep.receive() == ping
  rep.send(pong)
  assert req.receive() == pong

  rep.close()
  req.close()

proc pubsub() =
  const sockaddr = "tcp://127.0.0.1:55001"
  let
    topic1 = "topic1"
    topic2 = "topic2"

  var pub = listen(sockaddr, PUB)
  var
    broadcast = connect(sockaddr, SUB)
    sub1 = connect(sockaddr, SUB)
    sub2 = connect(sockaddr, SUB)
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
    assert  topic == topic1
    assert msg == "content1"
  block s1:
    let topic = sub1.receive()
    let msg = sub1.receive()
    assert topic == topic1
    assert msg == "content1"

  # Topic2
  pub.send(topic2, SNDMORE)
  pub.send("content2")
  block alltopic:
    let topic = broadcast.receive()
    let msg = broadcast.receive()
    assert  topic == topic2
    assert msg == "content2"
  block s2:
    let topic = sub2.receive()
    let msg = sub2.receive()
    assert topic == topic2
    assert msg == "content2"

  # Broadcast
  pub.send("", SNDMORE)
  pub.send("content3")
  block alltopic:
    let topic = broadcast.receive()
    let msg = broadcast.receive()
    assert  topic == ""
    assert msg == "content3"

  sub1.close()
  sub2.close()
  broadcast.close()
  pub.close()

proc inproc_sharectx() =
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
    assert server.receive() == "Hello"
    server.send("World")
    assert client.receive() == "World"

    client.close()
    server.close()

  else:
    discard

when isMainModule:
  block reqrep:
    reqrep()
  block pubsub:
    pubsub()
  block inproc:
    inproc_sharectx()
  block poller:
    discard

