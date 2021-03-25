import asyncdispatch
import strformat
import zmq
import zmq_async
  
proc subscriber(id: int): Future[void] {.async.} =
  const connStr = "tcp://localhost:5555"
  
  # subscribe to port 5555
  echo fmt"subscriber {id}: connecting to {connStr}"
  var subscriber = zmq.connect(connStr, SUB)
  defer: subscriber.close()

  # no filter
  subscriber.setsockopt(SUBSCRIBE, "")

  while true:
    # NOTE: subscriber always miss the first messages that the publisher sends
    var data = await subscriber.receiveAsync()
    echo fmt"subscriber {id}: received ", data

proc publisher(): Future[void] {.async.} =
  # listen on port 5555
  var publisher = zmq.listen("tcp://*:5555", PUB)
  defer: publisher.close()

  var i = 0
  while true:
    i.inc
    let msg = fmt"msg-{i}"
    echo "publisher: publish ", msg
    publisher.send(msg)
    await sleepAsync(1000)

when isMainModule:
  asyncCheck publisher()
  for i in 1..2:
    asyncCheck subscriber(i)
  runForever()

