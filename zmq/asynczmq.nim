import std/[asyncdispatch]
import ./connections
import ./bindings
import ./poller

type
  AsyncZPollCB* = proc(x: ZSocket) {.gcsafe.}
  AsyncZPoller* = object
    ## Experimental type to use zmq.poll() with Nim's async dispatch loop
    cb* : seq[AsyncZPollCB]
    zpoll*: ZPoller

proc len*(poller: AsyncZPoller): int =
  result = poller.zpoll.len()

proc `=destroy`*(obj: var AsyncZPoller) =
  if hasPendingOperations():
    raise newException(ZmqError, "AsyncZPoller closed with pending operation")

proc register*(poller: var AsyncZPoller, sock: ZSocket, event: int, cb: AsyncZPollCB) =
  ## Register ZSocket function
  poller.zpoll.register(sock, event)
  poller.cb.add(cb)

proc register*(poller: var AsyncZPoller, conn: ZConnection, event: int, cb: AsyncZPollCB) =
  ## Register ZConnection
  poller.register(conn.socket, event, cb)

proc register*(poller: var AsyncZPoller, item: ZPollItem, cb: AsyncZPollCB) =
  ## Register ZConnection
  poller.zpoll.items.add(item)
  poller.cb.add(cb)

proc initZPoller*(poller: sink ZPoller, cb: AsyncZPollCB) : AsyncZPoller =
  for p in poller.items:
    result.register(p, cb)

proc initZPoller*(args: openArray[tuple[item: ZConnection, cb: AsyncZPollCB]], event: cshort): AsyncZPoller =
  ## Init a ZPoller with all items on the same event
  for arg in args:
    result.register(arg.item, event, arg.cb)

proc pollAsync*(poller: AsyncZPoller, timeout: int = 1) : Future[int] =
  ## Experimental API. Poll all the ZConnection and execute an async CB when ``event`` occurs.
  result = newFuture[int]("pollAsync")
  var r = poller.zpoll.poll(timeout)
  # ZMQ can't have a timeout smaller than one
  if r > 0:
    for i in 0..<poller.len():
      if events(poller.zpoll[i]):
        let
          sock = poller.zpoll[i].socket
          localcb = poller.cb[i]
        callSoon proc () = localcb(sock)
  if hasPendingOperations():
    # poll vs drain ?
    drain(timeout)

  result.complete(r)

proc receiveAsync*(conn: ZConnection): Future[string] =
  ## Similar to `receive()`, but `receiveAsync()` allows other async tasks to run.
  ## `receiveAsync()` allows other async tasks to run in those cases.
  ##
  ## This will not work in some case because it depends on ZMQ_FD which is not necessarily the 'true' FD of the socket
  ##
  ## See https://github.com/zeromq/libzmq/issues/2941 and https://github.com/zeromq/pyzmq/issues/1411
  let fut = newFuture[string]("receiveAsync")
  result = fut
  let sock = conn.socket

  proc cb(fd: AsyncFD): bool {.closure, gcsafe.} =
    # the cb should work on the low level socket and not the ZConnection object
    result = true

    # ignore if already finished
    if fut.finished: return

    try:
      let status = getsockopt[cint](sock, ZSockOptions.EVENTS)
      if (status and ZMQ_POLLIN) == 0:
        # waiting for messages
        addRead(fd, cb)
      else:
        # ready to read
        unregister(fd)
        fut.complete sock.receive(DONTWAIT)
    except:
      unregister(fd)
      fut.fail getCurrentException()

  let fd = getsockopt[cint](conn, ZSockOptions.FD).AsyncFD
  register(fd)
  discard cb(fd)

proc sendAsync*(conn: ZConnection, msg: string, flags: ZSendRecvOptions = DONTWAIT): Future[void] =
  ## `send()` is blocking for some connection types (e.g. PUSH, DEALER).
  ## `sendAsync()` allows other async tasks to run in those cases.
  ##
  ## This will not work in some case because it depends on ZMQ_FD which is not necessarily the 'true' FD of the socket
  ##
  ## See https://github.com/zeromq/libzmq/issues/2941 and https://github.com/zeromq/pyzmq/issues/1411
  let fut = newFuture[void]("sendAsync")
  result = fut
  let sock = conn.socket

  let status = getsockopt[cint](conn, ZSockOptions.EVENTS)
  if (status and ZMQ_POLLOUT) == 0:
    # wait until queue available
    proc cb(fd: AsyncFD): bool {.closure, gcsafe.} =
      result = true

      # ignore if already finished
      if fut.finished: return

      try:
        let status = getsockopt[cint](sock, ZSockOptions.EVENTS)
        if (status and ZMQ_POLLOUT) == 0:
          # waiting for messages
          addWrite(fd, cb)
        else:
          sock.send(msg, flags)
          unregister(fd)
          fut.complete()
      except:
        unregister(fd)
        fut.fail getCurrentException()

    let fd = getsockopt[cint](conn, ZSockOptions.FD).AsyncFD
    register(fd)
    discard cb(fd)

  else:
    # can send without blocking
    conn.send(msg, flags)
    fut.complete()

