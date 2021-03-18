import zmq

var requester = zmq.listen("tcp://127.0.0.1:5555", REQ)

for i in 0..10:
  echo("Sending hello... (" & $i & ")")
  send(requester, "Hello")
  var reply = receive(requester)
  echo("Received: ", reply)
close(requester)

