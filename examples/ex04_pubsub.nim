import std/os
import ../zmq

const max_msg = 12
const num_thread = 2
const topics: array[2, string] = ["even", "odd"]
const address = "tcp://127.0.0.1:5557"

# An example of serialization using SNDMORE
proc publisher() =
  var requester = listen(address, mode = PUB)

  # PUB / SUB is a slow joiner in ZMQ
  # You need to wait before sending message of those messages will be lost
  sleep(200)

  for i in 0..<max_msg:
    let topic = topics[i mod 2]
    echo "Sending..."
    requester.send(topic, SNDMORE)
    requester.send($i)

  close(requester)

# An example receiving message until they are no more
proc subscriber(args: tuple[thrid: int, topic: string]){.thread.} =
  var responder = connect(address, mode = SUB)
  echo "Subscribe to ", args.topic
  responder.setsockopt(SUBSCRIBE, args.topic)

  var numMsg: int
  # Loop until there is no more message to receive
  while numMsg < max_msg div num_thread:
    let topic = responder.receive()
    let msg = responder.receive()
    echo "thread id=", args.thrid, " received topic=", topic, " msg=", msg
    inc(numMsg)

  responder.close()


when isMainModule:
  var thr: array[num_thread, Thread[tuple[thrid: int, topic: string]]]
  for i in 0..<len(thr):
    createThread(thr[i], subscriber, (i, topics[i]))
  publisher()
  joinThreads(thr)
