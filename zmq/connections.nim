import bindings
# Unofficial easier-for-Nim API

#[
  Types definition
]#
type
  EZmq* = object of IOError ## exception that is raised if something fails
  ZConnection* {.pure, final.} = object
    ## A Zmq connection. Since ``ZContext`` and ``ZSocket`` are pointers, it is highly recommended to **not** copy ``ZConnection``.
    context*: ZContext                  ## Zmq context. Can be 'owned' by another connection (useful for inproc protocol).
    socket*: ZSocket                    ## Embedded socket.
    ownctx: bool                        ## Boolean indicating if the connection owns the Zmq context
    alive: bool                         ## Boolean indicating if the connections has been closed or not
    sockaddr: string                    ## Address of the embedded socket

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
  ## setsockopt on ``ZSocket``
  ##
  ## Careful, the ``sizeof`` of ``optval`` depends on the ``ZSockOptions`` passed.
  ## Check http://api.zeromq.org/4-2:zmq-setsockopt
  setsockopt_impl[T](s, option, optval)

proc setsockopt*[T: SomeOrdinal|string](c: ZConnection, option: ZSockOptions, optval: T) =
  ## setsockopt on ``ZConnection``
  ##
  ## Careful, the ``sizeof`` of ``optval`` depends on the ``ZSockOptions`` passed.
  ## Check http://api.zeromq.org/4-2:zmq-setsockopt
  setsockopt[T](c.socket, option, optval)

proc getsockopt*[T: SomeOrdinal|string](s: ZSocket, option: ZSockOptions): T =
  ## getsockopt on ``ZSocket``
  ##
  ## Careful, the ``sizeof`` of ``optval`` depends on the ``ZSockOptions`` passed.
  ## Check http://api.zeromq.org/4-2:zmq-setsockopt
  var optval: T
  getsockopt_impl(s, option, optval)
  optval

proc getsockopt*[T: SomeOrdinal|string](c: ZConnection, option: ZSockOptions): T =
  ## getsockopt on ``ZConnection``
  ##
  ## Careful, the ``sizeof`` of ``optval`` depends on the ``ZSockOptions`` passed.
  ## Check http://api.zeromq.org/4-2:zmq-setsockopt
  getsockopt[T](c.socket, option)


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
proc reconnect*(conn: ZConnection) =
  ## Reconnect a previously binded/connected address
  if connect(conn.socket, conn.sockaddr) != 0:
    zmqError()

proc reconnect*(conn: var ZConnection, address: string) =
  ## Reconnect a socket to a new address
  if connect(conn.socket, address) != 0:
    zmqError()
  conn.sockaddr = address

proc disconnect*(conn: ZConnection) =
  ## Disconnect the socket
  if disconnect(conn.socket, conn.sockaddr) != 0:
    zmqError()

proc unbind*(conn: ZConnection) =
  ## Unbind the socket
  if unbind(conn.socket, conn.sockaddr) != 0:
    zmqError()

proc bindAddr*(conn: var ZConnection, address: string) =
  ## Bind the socket to a new address
  ## The socket must disconnected / unbind beforehand
  if bindAddr(conn.socket, address) != 0:
    zmqError()
  conn.sockaddr = address

proc connect*(address: string, mode: ZSocketType, context: ZContext): ZConnection =
  ## Open a new connection on an external ``ZContext`` and connect the socket
  result.context = context
  result.ownctx = false
  result.sockaddr = address
  result.alive = true
  result.socket = socket(result.context, cint(mode))
  if result.socket == nil:
    zmqError()

  if connect(result.socket, address) != 0:
    zmqError()

proc connect*(address: string, mode: ZSocketType): ZConnection =
  ## Open a new connection on an internal (owned) ``ZContext`` and connects the socket
  runnableExamples:
    var pullcon = connect("tcp://127.0.0.1:34444", pull)
    var pushcon = listen("tcp://127.0.0.1:34444", push)

    let msgpayload = "hello world !"
    pushcon.send(msgpayload)
    assert pullcon.receive() == msgpayload

    pushcon.close()
    pullcon.close()

  let ctx = ctx_new()
  if ctx == nil:
    zmqError()

  result = connect(address, mode, ctx)
  result.ownctx = true

proc listen*(address: string, mode: ZSocketType, context: ZContext): ZConnection =
  ## Open a new connection on an external ``ZContext`` and binds on the socket
  runnableExamples:
    var monoserver = listen("tcp://127.0.0.1:34444", PAIR)
    var monoclient = connect("tcp://127.0.0.1:34444", PAIR)

    monoclient.send("ping")
    assert monoserver.receive() == "ping"
    monoserver.send("pong")
    assert monoclient.receive() == "pong"

    monoclient.close()
    monoserver.close()

  result.context = context
  result.ownctx = false
  result.sockaddr = address
  result.alive = true

  result.socket = socket(result.context, cint(mode))
  if result.socket == nil:
    zmqError()

  if bindAddr(result.socket, address) != 0:
    zmqError()

proc listen*(address: string, mode: ZSocketType): ZConnection =
  ## Open a new connection on an internal (owned) ``ZContext`` and binds the socket
  let ctx = ctx_new()
  if ctx == nil:
    zmqError()

  result = listen(address, mode, ctx)
  result.ownctx = true

proc close*(c: var ZConnection) =
  ## Closes the ``ZConnection``.
  ## Set socket linger to 0 to drop buffered message and avoid blocking, then close the socket.
  ##
  ## If the ``ZContext`` is owned by the connection, terminate the context as well.
  ##
  ## With --gc:arc/orc ``close`` must be called before ``ZConnection`` destruction or the``=destroy`` hook.
  setsockopt(c, LINGER, 0.cint)
  if close(c.socket) != 0:
    zmqError()
  c.alive = false

  # Do not destroy embedded socket if it does not own it
  if c.ownctx:
    # ctx_destroy is deprecated for ctx_term
    if ctx_term(c.context) != 0:
      zmqError()

# Send / Receive
# Send with ZSocket type
proc send*(s: ZSocket, msg: string, flags: ZSendRecvOptions = NOFLAGS) =
  ## Sends a message through the socket.
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
  ## Receives a message from a socket.
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

proc send*(c: ZConnection, msg: string, flags: ZSendRecvOptions = NOFLAGS) =
  ## Sends a message over the connection.
  send(c.socket, msg, flags)

proc receive*(c: ZConnection, flags: ZSendRecvOptions = NOFLAGS): string =
  ## Receive data over the connection
  receive(c.socket, flags)

