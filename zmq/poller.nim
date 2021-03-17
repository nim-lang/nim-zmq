import bindings
import connections
import bitops

# Unofficial easier-for-Nim API
# Using a poller type
type
  Poller* = object
    items*: seq[TPollItem]

proc `[]`*(poller: Poller, idx : int): lent TPollItem =
  poller.items[idx]

proc len*(poller: Poller): int =
  poller.items.len

# Polling
# High level poll function using array of TPollItem
proc poll*(items: openArray[TPollItem], timeout: int64): int32 =
  poll(cast[ptr UncheckedArray[TPollItem]](unsafeAddr items[0]), cint(items.len), clong(timeout))

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

proc events*(p: TPollItem, events: int): bool =
  if bitand(p.revents, events.cshort) > 0:
    result = true
  else:
    result = false

proc events*(p: TPollItem): bool =
  if bitand(p.revents, p.events) > 0:
    result = true
  else:
    result = false

