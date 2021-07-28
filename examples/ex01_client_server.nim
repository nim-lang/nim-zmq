import ../zmq

proc server() =
  var responder = zmq.listen("tcp://127.0.0.1:5555", REP)
  defer:responder.close()
  var num_msg = 0
  while num_msg <= 10:
    var request = receive(responder)
    echo("Received: ", request)
    send(responder, "World")
    inc(num_msg)

proc client() =
  var requester = zmq.connect("tcp://127.0.0.1:5555", REQ)
  defer: requester.close()

  for i in 0..10:
    echo("Sending hello... (" & $i & ")")
    send(requester, "Hello")
    var reply = receive(requester)
    echo("Received: ", reply)

when isMainModule:
  echo "ex01_client_server.nim"
  var thr: Thread[void]
  createThread(thr, server)
  client()
  joinThread(thr)

