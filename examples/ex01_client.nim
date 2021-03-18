import zmq

var responder = zmq.connect("tcp://127.0.0.1:5555", REP)
var num_msg = 0
while num_msg <= 10:
  var request = receive(responder)
  echo("Received: ", request)
  send(responder, "World")
  inc(num_msg)

close(responder)
