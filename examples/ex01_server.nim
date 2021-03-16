import zmq

var requester = zmq.connect("tcp://localhost:5555")
echo("Connecting...")

for i in 0..10:
  echo("Sending hello... (" & $i & ")")
  send(requester, "Hello")
  var reply = receive(requester)
  echo("Received: ", reply)
close(requester)

