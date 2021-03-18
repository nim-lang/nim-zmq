# Nim ZeroMQ wrapper

**Note:** This wrapper was written and tested with ZeroMQ version 4.2.0. Older
versions may not work.

ZeroMQ API Reference can be found here : http://api.zeromq.org/4-2:_start

## Installation

```
$ nimble install zmq
```

## Examples

### Example client/server
#### Server
```nim
import zmq

var requester = zmq.connect("tcp://localhost:5555")
echo("Connecting...")

for i in 0..10:
  echo("Sending hello... (" & $i & ")")
  send(requester, "Hello")
  var reply = receive(requester)
  echo("Received: ", reply)
close(requester)
```
#### Client
```nim
import zmq
var responder = zmq.listen("tcp://*:5555")

while true:
  var request = receive(responder)
  echo("Received: ", request)
  send(responder, "World")

close(responder)
```

### More examples

For more examples demonstrating many functionalities and patterns that ZMQ offers, see the ``tests/`` and ``examples/`` folder.

The examples are commented to better understand how zmq works.
