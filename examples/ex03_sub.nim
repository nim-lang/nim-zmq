import ../zmq

var relay = "tcp://relay-us-west-1.eve-emdr.com:8050"

echo("Connecting ...")
var connection = connect(relay, mode = SUB)
connection.setsockopt(SUBSCRIBE, "")

echo("Receiving ...")
for i in 0..10:
  echo i
  var reply = receive(connection)
  #TODO: decompress reply and do stuff with it

close(connection)
