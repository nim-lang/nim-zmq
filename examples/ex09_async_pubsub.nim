import std/asyncdispatch
import std/strformat
import ../zmq

const N_EVENT = 5

proc subscriber(id: int): Future[void] {.async.} =
  const connStr = "tcp://localhost:5555"

  # subscribe to port 5555
  echo fmt"subscriber {id}: connecting to {connStr}"
  var subscriber = zmq.connect(connStr, SUB)
  defer: subscriber.close()

  # no filter
  subscriber.setsockopt(SUBSCRIBE, "")

  # NOTE: subscriber always miss the first messages that the publisher sends
  # reference: https://zguide.zeromq.org/docs/chapter1/#Getting-the-Message-Out
  for i in 2 .. N_EVENT:
    var data = await subscriber.receiveAsync()
    echo fmt"subscriber {id}: received ", data

proc publisher(): Future[void] {.async.} =
  # listen on port 5555
  var publisher = zmq.listen("tcp://*:5555", PUB)
  defer: publisher.close()

  for i in 1 .. N_EVENT:
    let msg = fmt"msg-{i}"
    echo "publisher: publish ", msg
    publisher.send(msg)
    await sleepAsync(1000)

when isMainModule:
  asyncCheck publisher()
  for i in 1..3:
    asyncCheck subscriber(i)

  while hasPendingOperations():
    poll()

