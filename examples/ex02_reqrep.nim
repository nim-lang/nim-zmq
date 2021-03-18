import strutils

import zmq

const num_elem = 12
# An example of serialization using SNDMORE
proc requester() =
  var input: seq[float] = newSeq[float](num_elem)

  for i, elem in input.mpairs:
    elem = i/10

  echo "sent: ", input

  var requester = listen("tcp://127.0.0.1:44444", mode = REQ)

  #var tt : int64 = getsockopt[int64](requester, TYPE)
  #echo tt.TSocketType

  for i, e in input:
    if i < input.len-1:
      requester.send($e, SNDMORE)
    else:
      requester.send($e)
  close(requester)

# An example receiving message until they are no more
proc responder(){.thread.} =
  var responder = connect("tcp://127.0.0.1:44444", mode = REP)

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
  var thr: Thread[void]
  createThread(thr, responder)
  requester()
  joinThreads(thr)
