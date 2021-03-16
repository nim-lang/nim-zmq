import bindings
# Unofficial easier-for-Nim API

# Error handling
type
  EZmq* = object of IOError ## exception that is raised if something fails
proc zmqError*() {.noinline, noreturn.} =
  ## raises EZmq with error message from `zmq.strerror`.
  var e: ref EZmq
  new(e)
  e.msg = $strerror(errno())
  raise e

# Connection handling
type
  TConnection* {.pure, final.} = object ## a connection
    c*: PContext                        ## the embedded context
    s*: PSocket                         ## the embedded socket

when defined(gcDestructors):
  proc `destroy=`(x: var TConnection)
  proc `destroy=`(x: var PSocket)
  proc `destroy=`(x: var PContext)


proc connect*(address: string, mode: TSocketType = REQ,
              context: PContext): TConnection =
  result.c = context

  result.s = socket(result.c, cint(mode))
  if result.s == nil:
    zmqError()

  if connect(result.s, address) != 0:
    zmqError()

proc connect*(address: string, mode: TSocketType = REQ): TConnection =
  ## open a new connection and connects
  let ctx = ctx_new()
  if ctx == nil:
    zmqError()

  return connect(address, mode, ctx)

proc listen*(address: string, mode: TSocketType = REP,
             context: PContext): TConnection =
  result.c = context

  result.s = socket(result.c, cint(mode))
  if result.s == nil:
    zmqError()

  if bindAddr(result.s, address) != 0:
    zmqError()

proc listen*(address: string, mode: TSocketType = REP): TConnection =
  ## open a new connection and binds on the socket
  let ctx = ctx_new()
  if ctx == nil:
    zmqError()

  return listen(address, mode, ctx)

proc close*(c: TConnection) =
  ## closes the connection.
  if close(c.s) != 0:
    zmqError()
  if ctx_destroy(c.c) != 0:
    zmqError()


# Send with PSocket type
proc send*(s: PSocket, msg: string, flags: TSendRecvOptions = NOFLAGS) =
  ## sends a message over the connection.
  var m: TMsg
  if msg_init(m, msg.len) != 0:
    zmqError()

  # Using cstring will cause issue with XPUB / XSUB socket that can send a payload containing `\x00`
  # Copying the memory is safer
  copyMem(msg_data(m), unsafeAddr(msg[0]), msg.len)

  if msg_send(m, s, flags.cint) == -1:
    zmqError()
  # no close msg after a send

# receive with PSocket type
proc receive*(s: PSocket, flags: TSendRecvOptions = NOFLAGS): string =
  ## receives a message from a connection.
  var m: TMsg
  if msg_init(m) != 0:
    zmqError()

  if msg_recv(m, s, flags.cint) == -1:
    zmqError()

  result = newString(msg_size(m))
  if result.len > 0:
    copyMem(addr(result[0]), msg_data(m), result.len)

  if msg_close(m) != 0:
    zmqError()

# send & receive with TConnection type
proc send*(c: TConnection, msg: string, flags: TSendRecvOptions = NOFLAGS) =
  send(c.s, msg, flags)

proc receive*(c: TConnection, flags: TSendRecvOptions = NOFLAGS): string =
  receive(c.s, flags)

