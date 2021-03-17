import bindings
import connections
import bitops

# Unofficial easier-for-Nim API
# Using a poller type
type
  ZPoller* = object
    items*: seq[ZPollItem]

proc `[]`*(poller: ZPoller, idx : int): lent ZPollItem =
  poller.items[idx]

proc len*(poller: ZPoller): int =
  poller.items.len

# Polling
# High level poll function using array of ZPollItem
proc poll*(items: openArray[ZPollItem], timeout: int64): int32 =
  poll(cast[ptr UncheckedArray[ZPollItem]](unsafeAddr items[0]), cint(items.len), clong(timeout))

## Register socket function
proc register*(poller: var ZPoller, sock: ZSocket, event: int) =
  poller.items.add(
    ZPollItem(socket: sock, events: event.cshort)
  )

# Register connection function for ease of use
proc register*(poller: var ZPoller, conn: ZConnection, event: int) =
  poller.register(conn.s, event)

# High level poll function using poller type
proc poll*(poller: ZPoller, timeout: int64): int32 =
  poll(poller.items, timeout)

proc events*(p: ZPollItem, events: int): bool =
  if bitand(p.revents, events.cshort) > 0:
    result = true
  else:
    result = false

proc events*(p: ZPollItem): bool =
  if bitand(p.revents, p.events) > 0:
    result = true
  else:
    result = false
