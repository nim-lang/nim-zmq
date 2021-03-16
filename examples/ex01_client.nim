import zmq
var responder = zmq.listen("tcp://*:5555")

while true:
  var request = receive(responder)
  echo("Received: ", request)
  send(responder, "World")

close(responder)
