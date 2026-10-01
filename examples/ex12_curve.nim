import zmq

doAssert hasCurve(), "this libzmq was not built with CURVE (libsodium) support"
let (serverPub, serverSec) = curveKeypair()
let (clientPub, clientSec) = curveKeypair()
var server = listen("tcp://127.0.0.1:34555", REP) do (s: ZSocket) -> void:
  s.setCurveServer(serverSec)
var client = connect("tcp://127.0.0.1:34555", REQ) do (s: ZSocket) -> void:
  s.setCurveClient(serverPub, clientPub, clientSec)
client.send("hello, encrypted")
doAssert server.receive() == "hello, encrypted"
echo "CURVE high-level connect/listen: ok"
client.close()
server.close()
