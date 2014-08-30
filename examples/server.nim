import zmq

var responder = listen("tcp://*:5555")

while True:
  var request = receive(responder)
  echo("Received: ", request)
  send(responder, "World")

close(responder)
