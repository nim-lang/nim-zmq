import std/marshal # Marshall module is used as an example but is actually a very bad way of doing serialization
import ../zmq

type
  Person = object
    name: string
    age: int

proc newPerson(n: string, a: int): Person =
  result = Person(name: n, age: a)

# An example of serialization using marshal module
proc mainMarshal() =
  var responder = listen("tcp://127.0.0.1:5560", mode = REP)
  defer: close(responder)
  var requester = connect("tcp://127.0.0.1:5560", mode = REQ)
  defer: close(requester)

  block request:
    let paul = newPerson("Paul", 34)
    var requester = connect("tcp://127.0.0.1:5560", mode = REQ)
    # Serialize Person object using `$$` operator defined in the marshal module
    requester.send($$paul)

  block reply:
    # Receive information
    var rcvBuf = responder.receive()
    # Un-marshall / deserialize information
    var person = to[Person](rcvBuf)
    assert person.name == "Paul"
    assert person.age == 34
    echo person

when isMainModule:
  mainMarshal()
