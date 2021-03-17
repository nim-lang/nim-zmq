import bindings
# Unofficial easier-for-Nim API

#[
  Types definition
]#
type
  EZmq* = object of IOError ## exception that is raised if something fails
  ZConnection* {.pure, final.} = object ## a connection
    c*: ZContext                        ## the embedded context
    s*: ZSocket                         ## the embedded socket
    ownctx: bool                        ## Does the Connection own the context ?
    alive: bool                         ## Is the connection alive ?
    sockaddr: string                    ## Address of the underlying socket

#[
  Error handler
]#
proc zmqError*() {.noinline, noreturn.} =
  ## raises EZmq with error message from `zmq.strerror`.
  var e: ref EZmq
  new(e)
  e.msg = $strerror(errno())
  raise e

#[
  get/set socket options
  Declare socket options first because it's used in =destroy hooks
]#
# Some option take cint, int64 or uint64
proc setsockopt_impl[T: SomeOrdinal](s: ZSocket, option: ZSockOptions, optval: T) =
  var val: T = optval
  if setsockopt(s, option, addr(val), sizeof(val)) != 0:
    zmqError()
# Some option take cstring
proc setsockopt_impl(s: ZSocket, option: ZSockOptions, optval: string) =
  var val: string = optval
  if setsockopt(s, option, cstring(val), val.len) != 0:
    zmqError()

# some sockopt returns integer values
proc getsockopt_impl[T: SomeOrdinal](s: ZSocket, option: ZSockOptions, optval: var T) =
  var optval_len: int = sizeof(optval)

  if bindings.getsockopt(s, option, addr(optval), addr(optval_len)) != 0:
    zmqError()

# Some sockopt returns a string
proc getsockopt_impl(s: ZSocket, option: ZSockOptions, optval: var string) =
  var optval_len: int = optval.len

  if bindings.getsockopt(s, option, cstring(optval), addr(optval_len)) != 0:
    zmqError()

#[
  Public set/get sockopt function on ZSocket / ZConnection
]#
proc setsockopt*[T: SomeOrdinal|string](s: ZSocket, option: ZSockOptions, optval: T) =
  setsockopt_impl[T](s, option, optval)

proc setsockopt*[T: SomeOrdinal|string](c: ZConnection, option: ZSockOptions, optval: T) =
  setsockopt[T](c.s, option, optval)

proc getsockopt*[T: SomeOrdinal|string](s: ZSocket, option: ZSockOptions): T =
  var optval: T
  getsockopt_impl(s, option, optval)
  optval

proc getsockopt*[T: SomeOrdinal|string](c: ZConnection, option: ZSockOptions): T =
  getsockopt[T](c.s, option)


#[
  Destructor
]#
when defined(gcDestructors):
  proc close*(c: var ZConnection)
  proc `=destroy`(x: var ZConnection) =
    if x.alive:
      raise newException(EZmq, "Connection destroyed but not closed")

#[
  Connect / Listen / Close
]#
# Reconnect a previously binded/connected address
proc reconnect*(conn: ZConnection) =
  if connect(conn.s, conn.sockaddr) != 0:
    zmqError()

proc reconnect*(conn: var ZConnection, address: string) =
  if connect(conn.s, address) != 0:
    zmqError()
  conn.sockaddr = address

proc disconnect*(conn: ZConnection) =
  if disconnect(conn.s, conn.sockaddr) != 0:
    zmqError()

proc unbind*(conn: ZConnection) =
  if unbind(conn.s, conn.sockaddr) != 0:
    zmqError()

proc connect*(address: string, mode: ZSocketType = REQ, context: ZContext): ZConnection =
  result.c = context
  result.ownctx = false
  result.sockaddr = address
  result.alive = true

  result.s = socket(result.c, cint(mode))
  if result.s == nil:
    zmqError()

  if connect(result.s, address) != 0:
    zmqError()

proc connect*(address: string, mode: ZSocketType = REQ): ZConnection =
  ## open a new connection and connects
  let ctx = ctx_new()
  if ctx == nil:
    zmqError()

  result = connect(address, mode, ctx)
  result.ownctx = true

proc listen*(address: string, mode: ZSocketType = REP, context: ZContext): ZConnection =
  result.c = context
  result.ownctx = false
  result.sockaddr = address
  result.alive = true

  result.s = socket(result.c, cint(mode))
  if result.s == nil:
    zmqError()

  if bindAddr(result.s, address) != 0:
    zmqError()

proc listen*(address: string, mode: ZSocketType = REP): ZConnection =
  ## open a new connection and binds on the socket
  let ctx = ctx_new()
  if ctx == nil:
    zmqError()

  result = listen(address, mode, ctx)
  result.ownctx = true

proc close*(c: var ZConnection) =
  ## closes the connection.
  # Set linger to 0 to properly drop buffered message otherwise closing socket can block indefinitly
  setsockopt(c, LINGER, 0.cint)
  if close(c.s) != 0:
    zmqError()
  c.alive = false

  # Do not destroy embedded socket if it does not own it
  if c.ownctx:
    # ctx_destroy is deprecated for ctx_term
    if ctx_term(c.c) != 0:
      zmqError()

# Send / Receive
# Send with ZSocket type
proc send*(s: ZSocket, msg: string, flags: ZSendRecvOptions = NOFLAGS) =
  ## sends a message over the connection.
  var m: ZMsg
  if msg_init(m, msg.len) != 0:
    zmqError()

  if msg.len > 0:
    # Using cstring will cause issue with XPUB / XSUB socket that can send a payload containing `\x00`
    # Copying the memory is safer
    copyMem(msg_data(m), unsafeAddr(msg[0]), msg.len)

  if msg_send(m, s, flags.cint) == -1:
    zmqError()
  # no close msg after a send

# receive with ZSocket type
proc receive*(s: ZSocket, flags: ZSendRecvOptions = NOFLAGS): string =
  ## receives a message from a connection.
  var m: ZMsg
  if msg_init(m) != 0:
    zmqError()

  if msg_recv(m, s, flags.cint) == -1:
    zmqError()

  result = newString(msg_size(m))
  if result.len > 0:
    copyMem(addr(result[0]), msg_data(m), result.len)

  if msg_close(m) != 0:
    zmqError()

# send & receive with ZConnection type
proc send*(c: ZConnection, msg: string, flags: ZSendRecvOptions = NOFLAGS) =
  send(c.s, msg, flags)

proc receive*(c: ZConnection, flags: ZSendRecvOptions = NOFLAGS): string =
  receive(c.s, flags)

