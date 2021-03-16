import bindings
# Unofficial easier-for-Nim API

#[
  Types definition
]#
type
  EZmq* = object of IOError ## exception that is raised if something fails
  TConnection* {.pure, final.} = object ## a connection
    c*: PContext                        ## the embedded context
    s*: PSocket                         ## the embedded socket
    ownctx: bool                       ## Does the Connection own the context ?

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
proc setsockopt_impl[T: SomeOrdinal](s: PSocket, option: TSockOptions, optval: T) =
  var val: T = optval
  if setsockopt(s, option, addr(val), sizeof(val)) != 0:
    zmqError()
# Some option take cstring
proc setsockopt_impl(s: PSocket, option: TSockOptions, optval: string) =
  var val: string = optval
  if setsockopt(s, option, cstring(val), val.len) != 0:
    zmqError()

# some sockopt returns integer values
proc getsockopt_impl[T: SomeOrdinal](s: PSocket, option: TSockOptions, optval: var T) =
  var optval_len: int = sizeof(optval)

  if getsockopt(s, option, addr(optval), addr(optval_len)) != 0:
    zmqError()

# Some sockopt returns a string
proc getsockopt_impl(s: PSocket, option: TSockOptions, optval: var string) =
  var optval_len: int = optval.len

  if getsockopt(s, option, cstring(optval), addr(optval_len)) != 0:
    zmqError()

#[
  Public set/get sockopt function on PSocket / TConnection
]#
proc setsockopt*[T: SomeOrdinal|string](s: PSocket, option: TSockOptions, optval: T) =
  setsockopt_impl[T](s, option, optval)
proc setsockopt*[T: SomeOrdinal|string](c: TConnection, option: TSockOptions, optval: T) =
  setsockopt_impl[T](c.s, option, optval)
proc getsockopt*[T: SomeOrdinal|string](s: PSocket, option: TSockOptions): T =
  var optval: T
  getsockopt_impl(s, option, optval)
  optval
proc getsockopt*[T: SomeOrdinal|string](c: TConnection, option: TSockOptions): T =
  getsockopt_impl[T](c.s, option)


#[
  Destructor
]#
# TODO
when defined(gcDestructors):
  # Forward declaration for destructor
  # proc `=destroy`(x: var PSocket) =
  #   echo "destroy PSocket"
  #   # Set linger to 0 to properly drop message
  #   setsockopt(x, LINGER, 0.cint)
  #   if close(x) != 0:
  #     zmqError()

  # proc `=destroy`(x: var PContext) =
  #   echo "destroy PContext"
  #   if term(x) != 0:
  #     zmqError()

  proc close*(c: TConnection)
  proc `=destroy`(x: var TConnection) =
    echo "destroy TConn> ", x.ownctx
    # Set linger to 0 to properly drop message
    setsockopt(x, LINGER, 0.cint)
    close(x)

  #[
    Connect / Listen / Close
  ]#
proc connect*(address: string, mode: TSocketType = REQ, context: PContext): TConnection =
  result.c = context
  result.ownctx = false

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

  result = connect(address, mode, ctx)
  result.ownctx = true

proc listen*(address: string, mode: TSocketType = REP, context: PContext): TConnection =
  result.c = context
  result.ownctx = false

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

  result = listen(address, mode, ctx)
  result.ownctx = true

proc close*(c: TConnection) =
  ## closes the connection.
  if close(c.s) != 0:
    zmqError()

  # Do not destroy embedded socket if it does not own it
  if c.ownctx:
    # ctx_destroy is deprecated for ctx_term
    if ctx_term(c.c) != 0:
      zmqError()

# Send / Receive
# Send with PSocket type
proc send*(s: PSocket, msg: string, flags: TSendRecvOptions = NOFLAGS) =
  ## sends a message over the connection.
  var m: TMsg
  if msg_init(m, msg.len) != 0:
    zmqError()

  if msg.len > 0:
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

