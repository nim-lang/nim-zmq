import asyncdispatch
import strformat
import zmq

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
      fut.complete conn.receive(DONTWAIT)
      unregister(fd)

  let fd = getsockopt[cint](conn, TSockOptions.FD).AsyncFD
  register(fd)
  discard cb(fd)
  
proc client(id: int): Future[void] {.async.} =
  var client = zmq.connect("tcp://localhost:5555", SUB)
  client.setsockopt(SUBSCRIBE, "")
  defer: client.close()

  echo fmt"client {id} connecting"
  while true:
    var data = await client.receiveAsync()
    echo fmt"client {id} receive ", data

proc server(): Future[void] {.async.} =
  var server = zmq.listen("tcp://*:5555", PUB)
  defer: server.close()

  var i = 0
  while true:
    i += 1
    let data = fmt"hello {i}"
    echo "server publish ", data
    server.send(data, DONTWAIT)
    await sleepAsync(1000)

when isMainModule:
  asyncCheck server()
  asyncCheck client(1)
  asyncCheck client(2)
  runForever()

