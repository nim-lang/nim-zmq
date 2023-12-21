import ./bindings
import ./connections
import std/bitops

# Unofficial easier-for-Nim API
# ZPoller type
type
  ZPoller* = object
    ## Poller type to simplify polling in ZMQ.
    ##
    ## While, ``ZPoller`` can access the underlying socket to send / receive message, it **must not close** any socket.
    ## It is mandatory to manage the lifetimes of the polled sockets independently of the ``ZPoller`` - either manually or by using a ``ZConnection``.
    items*: seq[ZPollItem]

proc `=destroy`*(poll: Zpoller) =
  `=destroy`(poll.items)

proc `[]`*(poller: ZPoller, idx: int): lent ZPollItem =
  ## Access registered element by index
  poller.items[idx]

proc len*(poller: ZPoller): int =
  ## Return the number of registered ZConnections
  poller.items.len

# Polling
proc poll*(items: openArray[ZPollItem], timeout: int64): int32 =
  ## High level poll function using array of ZPollItem
  poll(cast[ptr UncheckedArray[ZPollItem]](unsafeAddr items[0]), cint(items.len), clong(timeout))

proc register*(poller: var ZPoller, sock: ZSocket, event: int) =
  ## Register ZSocket function
  poller.items.add(
    ZPollItem(socket: sock, events: event.cshort)
  )

proc register*(poller: var ZPoller, conn: ZConnection, event: int) =
  ## Register ZConnection
  poller.register(conn.socket, event)

proc initZPoller*(items: openArray[ZConnection], event: cshort): ZPoller =
  ## Init a ZPoller with all items on the same event
  for c in items:
    result.register(c, event)

proc initZPoller*(items: openArray[ZSocket], event: cshort): ZPoller =
  ## Init a ZPoller with all items on the same event
  for s in items:
    result.register(s, event)

proc initZPoller*(items: openArray[tuple[sock: ZSocket, event: cshort]]): ZPoller =
  ## Init a ZPoller with each item its events flags
  for (s, e) in items:
    result.register(s, e)

proc initZPoller*(items: openArray[tuple[con: ZConnection, event: cshort]]): ZPoller =
  ## Init a ZPoller with each item its events flags
  for (c, e) in items:
    result.register(c, e)

proc poll*(poller: ZPoller, timeout: int64): int32 =
  ## High level poll function
  poll(poller.items, timeout)

proc events*(p: ZPollItem, events: int): bool =
  ## Evaluate the bitflag revents with events
  if bitand(p.revents, events.cshort) > 0:
    result = true
  else:
    result = false

proc events*(p: ZPollItem): bool =
  ## Evaluate the bitflag revents with the event flag passed at ``register``
  if bitand(p.revents, p.events) > 0:
    result = true
  else:
    result = false
