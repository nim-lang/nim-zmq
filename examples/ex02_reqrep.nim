import std/strutils

import ../zmq

const num_elem = 12
# An example of serialization using SNDMORE
proc requester() =
  var input: seq[float] = newSeq[float](num_elem)

  for i, elem in input.mpairs:
    elem = i/10

  var requester = connect("tcp://127.0.0.1:15555", mode = REQ)

  for i, e in input:
    if i < input.len-1:
      requester.send($e, SNDMORE)
    else:
      requester.send($e)

  echo "sent: ", input

  close(requester)

# An example receiving message until they are no more
proc responder(){.thread.} =
  var responder = listen("tcp://127.0.0.1:15555", mode = REP)

  var data: seq[float]
  # Loop until there is no more message to receive
  while true:
    let rcvBuf = responder.receive()
    data.add(rcvBuf.parseFloat)
    var hasMore: int = getsockopt[int](responder, RCVMORE)
    echo "hasMore: ", hasMore
    if hasMore == 0:
      break

  echo "received: ", data

when isMainModule:
  echo "ex02_reqrep.nim"
  var thr: Thread[void]
  createThread(thr, responder)
  requester()
  joinThreads(thr)
