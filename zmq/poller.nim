import bindings
import connections

# Using a poller type
type
  Poller* = object
    items*: seq[TPollItem]


when defined(gcDestructors):
  # TODO
  proc `destroy=`(x: var Poller)

# Polling
# High level poll function using array of TPollItem
proc poll*(items: openArray[TPollItem], timeout: int64): int32 =
  poll(cast[ptr UncheckedArray[TPollItem]](unsafeAddr items[0]), cint(
      items.len), clong(timeout))

## Register socket function
proc register*(poller: var Poller, sock: PSocket, event: int) =
  poller.items.add(
    TPollItem(socket: sock, events: event.cshort)
  )

# Register connection function for ease of use
proc register*(poller: var Poller, conn: TConnection, event: int) =
  poller.register(conn.s, event)

# High level poll function using poller type
proc poll*(poller: Poller, timeout: int64): int32 =
  poll(poller.items, timeout)
