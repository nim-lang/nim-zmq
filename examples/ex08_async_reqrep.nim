import asyncdispatch
import strformat
import zmq
import zmq_async

const N_REQUESTER = 2
const N_REQ_PER_REQUESTER = 3

proc requester(id: int): Future[void] {.async.} =
  const connStr = "tcp://localhost:5555"
  
  echo fmt"requester {id}: connecting to {connStr}"
  var requester = connect(connStr, REQ)
  defer: requester.close()

  for i in 1 .. N_REQ_PER_REQUESTER:
    # message to send to responder
    let msg = fmt"msg-{id}-{i}"
    echo fmt"requester {id}: sending {msg} to responder"

    # specifies that the operation should be performed in non-blocking mode. 
    # If the message cannot be queued on the socket, send() shall fail with errno set to EAGAIN.
    requester.send(msg)

    # wait for response asynchronously
    let reply = await requester.receiveAsync()
    echo fmt"requester {id}: received {reply} from responder"

proc responder(): Future[void] {.async.} =
  # listen on port 5555
  var responder = listen("tcp://*:5555", REP)
  defer: responder.close()

  for i in 1 .. N_REQ_PER_REQUESTER * N_REQUESTER:
    # wait for requests asynchronously
    var request = await responder.receiveAsync()
    echo fmt"responder: received {request} and echo back"
    responder.send(request)

when isMainModule:
  asyncCheck responder()
  
  for i in 1 .. N_REQUESTER:
    asyncCheck requester(i)
  
  while hasPendingOperations():
    poll()
