import strutils
import zmq
import os
import system
import bitops

const address = "tcp://127.0.0.1:44445"
const max_msg = 10

proc client()=
  var d1= connect(address, mode=DEALER)
  var d2= connect(address, mode=DEALER)

  # Send a dummy message withc each socket to obtain the identity on the ROUTER socket
  d1.send("dummy")
  d2.send("dummy")

  var p : Poller
  p.register(d1, ZMQ_POLLIN)
  p.register(d2, ZMQ_POLLIN)

  while true:
    let res : int = poll(p, 1_000)
    let p1 = p.items[0]
    let p2 = p.items[1]

    if res > 0 :
      let res1 = bitand(p1.revents, ZMQ_POLLIN.cshort)
      let res2 = bitand(p2.revents, ZMQ_POLLIN.cshort)

      if  res1 > 0:
        var buf = p1.socket.receive()
        echo "CLIENT> p1 received ", buf

      if res2 > 0:
        var buf = p2.socket.receive()
        echo "CLIENT> p2 received ", buf

    elif res == 0:
      echo "CLIENT> Timeout"
      break

    else:
      zmqError()

  echo "CLIENT -- END"
  d1.close()
  d2.close()

when isMainModule:
  # Create router connexion
  var router = listen(address, mode=ROUTER)

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


