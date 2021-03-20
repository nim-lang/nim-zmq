import asyncdispatch
import strformat
import zmq

proc sendAsync*(conn: TConnection, msg: string): Future[void] =
  let fut = newFuture[void]("sendAsync")
  result = fut
  
  proc cb(fd: AsyncFD): bool {.closure,gcsafe.} =
    result = true

    # ignore if already finished
    if fut.finished: return 

    let status = getsockopt[cint](conn, TSockOptions.EVENTS)
    if (status and ZMQ_POLLOUT) == 0:
      # no more messages
      unregister(fd)
      fut.complete()
    else:
      # writing messages
      addWrite(fd, cb)

  conn.send(msg, DONTWAIT)
  let fd = getsockopt[cint](conn, TSockOptions.FD).AsyncFD
  register(fd)
  discard cb(fd)

proc receiveAsync*(conn: TConnection): Future[string] =
  let fut = newFuture[string]("receiveAsync")
  result = fut

  proc cb(fd: AsyncFD): bool {.closure,gcsafe.} =
    result = true

    # ignore if already finished
    if fut.finished: return 

    let status = getsockopt[cint](conn, TSockOptions.EVENTS)
    if (status and ZMQ_POLLIN) == 0:
      # waiting for messages
      addRead(fd, cb)
    else:
      # ready to read
      unregister(fd)
      fut.complete conn.receive(DONTWAIT)

  let fd = getsockopt[cint](conn, TSockOptions.FD).AsyncFD
  register(fd)
  discard cb(fd)
  
proc client(id: int): Future[void] {.async.} =
  var client = zmq.connect("tcp://localhost:5555")
  defer: client.close()

  echo fmt"client {id} is connecting"
  var i = 0
  while true:
    i.inc
    echo fmt"client {id} sending {id}-{i}"
    await client.sendAsync fmt"{id}-{i}"
    var reply = await client.receiveAsync()
    echo fmt"client {id} received ", reply
    await sleepAsync(3000)

proc server(): Future[void] {.async.} =
  var server = zmq.listen("tcp://*:5555")
  defer: server.close()

  while true:
    var request = await server.receiveAsync()
    echo "server echo ", request
    await server.sendAsync request

when isMainModule:
  asyncCheck server()
  asyncCheck client(1)
  asyncCheck client(2)
  runForever()
