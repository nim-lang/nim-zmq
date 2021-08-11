import std/strutils
import std/strformat
import std/os
import ../zmq

const address = "tcp://127.0.0.1:5559"
const max_msg = 10


proc client() =
  var d1 = connect(address, mode = DEALER)
  defer: d1.close()
  var d2 = connect(address, mode = DEALER)
  defer: d2.close()

  # Send a dummy message withc each socket to obtain the identity on the ROUTER socket
  d1.send("dummy")
  d2.send("dummy")

  # It is possible to manually register connection (for adding connection after ZPoller creation)
  # The connections are still managed independently
  var poller: ZPoller
  poller.register(d1, ZMQ_POLLIN)
  poller.register(d2, ZMQ_POLLIN)

  while true:
    let res = poll(poller, 1_000)
    if res > 0:
      for i in 0..<len(poller):
        if events(poller[i]):
          let buf = receiveAll(poller[i].socket, NOFLAGS)
          for j, msg in buf.pairs:
            echo &"CLIENT> Socket{i} received \"{msg}\""
        else:
          echo &"CLIENT> Socket{i} received nothing"

    elif res == 0:
      echo "CLIENT> Timeout"
      break

    else:
      zmqError()

  echo "CLIENT -- END"

when isMainModule:
  echo "ex06_pollermultipart.nim"
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
    router.send("Hello, socket#" & top.toHex, SNDMORE)
    router.send("Your message is:", SNDMORE)
    router.send("payload#" & $num_msg)
    echo "SERVER> Send: ", num_msg, " to topic:", ids[num_msg mod 2].toHex
    inc(num_msg)
    sleep(100)

  router.close()
  joinThread(thr)

