import strutils
import zmq
import os
import system
import bitops
import options
import strformat

const address = "tcp://127.0.0.1:44445"
const max_msg = 10

proc receiveMultipart(socket: PSocket, flags: TSendRecvOptions): seq[string] =
  var hasMore: int = 1
  while hasMore > 0:
    result.add(socket.receive())
    hasMore = getsockopt[int](socket, RCVMORE)


## Receive all available messages on the polling sockets
## Example on how to receive multipart message on all poller
proc receive(poller: Poller, flags: TSendRecvOptions = NOFLAGS): seq[Option[seq[string]]] =
  for i in 0..<len(poller.items):
    if bitand(poller.items[i].revents, ZMQ_POLLIN.cshort) > 0:
      result.add(
        some(
          receiveMultipart(poller.items[i].socket, flags)
        )
      )
    else:
      result.add(
        none(seq[string])
      )

proc client() =
  var d1 = connect(address, mode = DEALER)
  var d2 = connect(address, mode = DEALER)

  # Send a dummy message withc each socket to obtain the identity on the ROUTER socket
  d1.send("dummy")
  d2.send("dummy")

  var poller: Poller
  poller.register(d1, ZMQ_POLLIN)
  poller.register(d2, ZMQ_POLLIN)

  while true:
    let res: int = poll(poller, 1_000)
    if res > 0:
      var buf = poller.receive()
      for i, s in buf.pairs:
        if s.isSome:
          echo &"CLIENT> p{i+1} received ", s.get()
        else:
          echo &"CLIENT> p{i+1} received nothing"

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


