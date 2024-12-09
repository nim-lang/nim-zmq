import std/asyncdispatch
import std/sequtils
import std/strutils
import ../zmq

const N_WORKER = 3
const host = "tcp://localhost:5572"

proc worker(): Future[void] {.async.} =
  let socket = zmq.connect(host, DEALER)
  socket.sendAll("READY")
  var isRunning = true
  while isRunning:
    let multiparts = await socket.receiveAllAsync()
    echo "worker receive ", multiparts
    let command = multiparts[0]
    case command:
    of "JOB":
      let x = multiparts[1]
      let y = parseInt(x)*2
      socket.sendAll("DONE", $x, $y)
    of "KILL":
      isRunning = false
      socket.sendAll("END")

proc router(): Future[void] {.async.} =
  let socket = zmq.listen(host, ROUTER)
  var jobs = toSeq(1..10)
  var nWorker = 0
  var isRunning = true
  while isRunning:
    let multiparts = await socket.receiveAllAsync()
    echo "router receive ", multiparts
    let workerId = multiparts[0]
    let command = multiparts[1]
    case command:
    of "READY":
      nWorker += 1
      if jobs.len > 0:
        socket.sendAll(workerId, "JOB", $jobs.pop())
      else:
        socket.sendAll(workerId, "KILL")
    of "END":
      nWorker -= 1
      if nWorker == 0:
        # stop router if no workers
        isRunning = false
    of "DONE":
      let x = multiparts[2]
      let y = multiparts[3]
      assert parseInt(x)*2 == parseInt(y)
      if jobs.len > 0:
        socket.sendAll(workerId, "JOB", $jobs.pop())
      else:
        socket.sendAll(workerId, "KILL")
    else:
      raise newException(CatchableError, "unknown command")

when isMainModule:
  echo "ex11_async_router_dealer.nim"
  asyncCheck router()
  for i in 1..N_WORKER:
    asyncCheck worker()
  while hasPendingOperations():
    poll()
