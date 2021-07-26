import std/[strutils]

import ../zmq

const num_elem = 12
# An example of serialization using SNDMORE
proc requester() =
  var input: seq[float] = newSeq[float](num_elem)
  for i, elem in input.mpairs:
    elem = i/10

  echo "listen"
  var req_conn = listen("tcp://127.0.0.1:15555", mode = REQ)
  defer: req_conn.close()

  for i, e in input:
    if i < input.len-1:
      req_conn.send($e, SNDMORE)
    else:
      req_conn.send($e)

  echo "sent: ", input

# An example receiving message until they are no more
proc responder() {.gcsafe.} =
  echo "connect"
  var rep_conn = connect("tcp://127.0.0.1:15555", mode = REP)
  defer: rep_conn.close()

  var data: seq[float]
  # Loop until there is no more message to receive
  while true:
    echo "recv"
    let rcvBuf = rep_conn.receive()
    data.add(rcvBuf.parseFloat)
    var hasMore: int = getsockopt[int](rep_conn, RCVMORE)
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
