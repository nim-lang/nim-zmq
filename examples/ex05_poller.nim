import std/strutils
import std/os
import ../zmq

const address = "tcp://127.0.0.1:5558"
const max_msg = 10

## Example of using ZPoller

proc client() =
  # Create connection
  var d1 = connect(address, mode = DEALER)
  var d2 = connect(address, mode = DEALER)

  # Send a dummy message with each socket to obtain the identity on the ROUTER socket
  # This is independent of the ZPoller usage but is necessary for using ROUTER / DEALER pattern in ZMQ
  d1.send("dummy")
  d2.send("dummy")

  # Create a poller from the connections
  # Notice how the connection are managed independtly of the ZPoller
  let p: ZPoller = initZPoller([d1, d2], ZMQ_POLLIN)

  while true:
    if poll(p, 1_000) > 0:
      # Check if the registered events "ZMQ_POLLIN" has occured
      if events(p[0]):
        var buf = p[0].socket.receive()
        echo "CLIENT> p1 received ", buf

      # Other events variation with explicit events flag to check
      if events(p[1], ZMQ_POLLIN):
        var buf = p[1].socket.receive()
        echo "CLIENT> p2 received ", buf

    else:
      echo "CLIENT> Timeout"
      break

  echo "CLIENT -- END"
  d1.close()
  d2.close()

when isMainModule:
  # Create router connexion
  var router = listen(address, mode = ROUTER)

  # Create client thread
  var thr: Thread[void]
  createThread(thr, client)

  # Use first message and store ids
  var ids: seq[string]
  ids.add(router.receive())
  discard router.receive()
  ids.add(router.receive())
  discard router.receive()
  for i in ids:
    echo "SERVER> Socket Known: ", i.toHex

  # Send message
  var num_msg = 0
  while num_msg < max_msg:
    let top = ids[num_msg mod 2]
    # Adress message to a DELAER Socket using its id
    router.send(top, SNDMORE)
    # Send data
    router.send("Hello to socket#" & top.toHex & " with message#" & $num_msg)
    echo "SERVER> Send: ", num_msg, " to topic:", ids[num_msg mod 2].toHex
    inc(num_msg)
    sleep(100)

  router.close()
  joinThread(thr)


