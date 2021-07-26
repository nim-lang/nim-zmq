import std/[strformat]
import std/asyncdispatch

import ../zmq

const N_TASK = 5

proc pusher(nTask: int): Future[void] {.async.} =
  var pusher = listen("tcp://*:5555", PUSH)
  defer: pusher.close()

  for i in 1..nTask:
    let task = fmt"task-{i}"
    echo fmt"pusher: pushing {task}"
    # unlilke `pusher.send(task)`
    # this allow other async tasks to run
    await pusher.sendAsync(task)

proc puller(id: int): Future[void] {.async.} =
  const connStr = "tcp://localhost:5555"

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
  asyncCheck pusher(N_TASK)

  for i in 1..1:
    asyncCheck puller(i)

  while hasPendingOperations():
    poll()

