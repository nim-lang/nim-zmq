import ../zmq
import std/unittest

# A custom `=destroy` for ZConnectionImpl must still destroy the object's fields: the connection's address string was
# leaked once per connection. Connecting to an address nobody listens on is enough (connect is asynchronous); the
# main-thread heap is measured because Nim's own allocator is where the leaked string lives.
suite "connection destruction does not leak":
  test "creating and closing many connections does not grow the Nim heap":
    # a runtime string: a literal would be shared, not copied, and there would be nothing to leak
    let port = 55002
    let addr1 = "tcp://127.0.0.1:" & $port
    proc cycle(n: int) =
      for _ in 0 ..< n:
        var c = connect(addr1, REQ)
        c.close()
    cycle(500)                       # warm up (the first connections allocate the context machinery)
    let before = getOccupiedMem()
    cycle(20000)
    let grown = getOccupiedMem() - before
    # unfixed: ~30 bytes * 20000 = ~600 KB; fixed: only allocator noise
    check grown < 100 * 1024
