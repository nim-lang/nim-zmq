import std/[strformat]
import std/asyncdispatch

import ../zmq

const N_TASK = 5

proc pusher(nTask: int): Future[void] {.async.} =
  var pusher = listen("tcp://127.0.0.1:6309", PUSH)
  defer: pusher.close()

  for i in 1..nTask:
    let task = fmt"task-{i}"
    echo fmt"pusher: pushing {task}"
    # unlilke `pusher.send(task)`
    # this allow other async tasks to run
    await pusher.sendAsync(task)

proc puller(id: int): Future[void] {.async.} =
  const connStr = "tcp://localhost:6309"

  echo fmt"puller {id}: connecting to {connStr}"
  var puller = connect(connStr, PULL)
  defer: puller.close()

  for i in 1 .. N_TASK:
    let task = await puller.receiveAsync()
    echo fmt"puller {id}: received {task}"
    await sleepAsync(100)
    echo fmt"puller {id}: finished {task}"

when isMainModule:
  echo "ex10_async_pushpull.nim"
  var p = pusher(N_TASK)
  asyncCheck puller(1)
  waitFor p
  # Gives time to the asyncdispatch loop to execute
  while hasPendingOperations():
    drain()

