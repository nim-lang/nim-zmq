import marshal
import zmq

type
  Person = object
    name: string
    age: int

proc newPerson(n: string, a: int): Person =
  result = Person(name: n, age: a)

# An example of serialization using marshal module
proc requester(){.thread.} =
  let paul = newPerson("Paul", 34)
  var requester = connect("tcp://127.0.0.1:44444", mode = REQ)
  # Serialize Person object using `$$` operator defined in the marshal module
  requester.send($$paul)
  close(requester)

# An example using marshall deserialization and receiving message until they are no more
proc responder() =
  var responder = listen("tcp://127.0.0.1:44444", mode = REP)
  # Receive information
  var rcvBuf = responder.receive()
  # Un-marshall / deserialize information
  var person = to[Person](rcvBuf)
  assert person.name == "Paul"
  assert person.age == 34
  echo person
  close(responder)

when isMainModule:
  var thr: Thread[void]
  createThread(thr, requester)
  responder()
  joinThread(thr)
