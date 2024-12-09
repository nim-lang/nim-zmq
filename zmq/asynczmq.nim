import std/[asyncdispatch, selectors]
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

proc waitAll(obj: AsyncZPoller) {.raises: [].} =
  # Is there a more elegant to do this ?
  # We want a helper function that will not raises to avoid excpetion in =destroy hooks

  try:

    while hasPendingOperations():
      drain(500)

  except ValueError:
    discard

  except OSError:
    discard

  except ref IOSelectorsException:
    discard

  except Exception:
    discard

proc `=destroy`*(obj: AsyncZPoller) =
  obj.waitAll()
  `=destroy`(obj.cb)
  `=destroy`(obj.zpoll)

proc register*(poller: var AsyncZPoller, sock: ZSocket, event: int, cb: AsyncZPollCB) =
  ## Register ZSocket function
  ## The callback should ideally use non-blocking proc such ``waitForReceive`` or ``tryReceive`` or ``c.receive(DONTWAIT)``
  poller.zpoll.register(sock, event)
  poller.cb.add(cb)

proc register*(poller: var AsyncZPoller, conn: ZConnection, event: int, cb: AsyncZPollCB) =
  ## Register ZConnection
  ## The callback should ideally use non-blocking proc such ``waitForReceive`` or ``tryReceive`` or ``c.receive(DONTWAIT)``
  poller.register(conn.socket, event, cb)

proc register*(poller: var AsyncZPoller, item: ZPollItem, cb: AsyncZPollCB) =
  ## Register ZConnection.
  ## The callback should use non-blocking proc ``waitForReceive`` with strictly positive timeout or ``tryReceive`` or ``c.receive(DONTWAIT)``
  poller.zpoll.items.add(item)
  poller.cb.add(cb)

proc initZPoller*(poller: sink ZPoller, cb: AsyncZPollCB) : AsyncZPoller =
  ## The callback should use non-blocking proc such ``waitForReceive`` or ``tryReceive`` or ``c.receive(DONTWAIT)``
  for p in poller.items:
    result.register(p, cb)

proc initZPoller*(args: openArray[tuple[item: ZConnection, cb: AsyncZPollCB]], event: cshort): AsyncZPoller =
  ## Init a ZPoller with all items on the same event
  ## The callback should use non-blocking proc ``waitForReceive`` with strictly positive timeout or ``tryReceive`` or ``c.receive(DONTWAIT)``
  for arg in args:
    result.register(arg.item, event, arg.cb)

proc pollAsync*(poller: AsyncZPoller, timeout: int = 2) : Future[int] =
  ## Experimental API. Poll all the ZConnection and execute an async CB when ``event`` occurs.
  ## The callback should use non-blocking proc ``waitForReceive`` with strictly positive timeout or ``tryReceive`` or ``c.receive(DONTWAIT)``

  var timeout = max(2, timeout)
  result = newFuture[int]("pollAsync")
  var r = poller.zpoll.poll(timeout div 2)
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
    drain(timeout div 2)

  result.complete(r)

template receiveAsyncCallbackTemplate(fut: Future, sock: ZSocket, recv, cb) =
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
        fut.complete recv(sock, DONTWAIT)
    except:
      unregister(fd)
      fut.fail getCurrentException()

proc receiveAsync*(conn: ZConnection): Future[string] =
  ## Similar to `receive()`, but `receiveAsync()` allows other async tasks to run.
  ## `receiveAsync()` allows other async tasks to run in those cases.
  ##
  ## This will not work in some case because it depends on ZMQ_FD which is not necessarily the 'true' FD of the socket
  ##
  ## See https://github.com/zeromq/libzmq/issues/2941 and https://github.com/zeromq/pyzmq/issues/1411
  let fut = newFuture[string]("receiveAsync")
  result = fut
  receiveAsyncCallbackTemplate(fut, conn.socket, receive, cb)
  let fd = getsockopt[cint](conn, ZSockOptions.FD).AsyncFD
  register(fd)
  discard cb(fd)

proc tryReceiveAsync*(conn: ZConnection): Future[tuple[msgAvailable: bool, moreAvailable: bool, msg: string]] =
  ## Async version of `tryReceive()`
  let fut = newFuture[tuple[msgAvailable: bool, moreAvailable: bool, msg: string]]("tryReceiveAsync")
  result = fut
  receiveAsyncCallbackTemplate(fut, conn.socket, tryReceive, cb)
  let fd = getsockopt[cint](conn, ZSockOptions.FD).AsyncFD
  register(fd)
  discard cb(fd)

proc receiveAllAsync*(conn: ZConnection): Future[seq[string]] {.async.} =
  ## async version for `receiveAll()`
  var expectMessage = true
  while expectMessage:
    let (msgAvailable, moreAvailable, msg) = await tryReceiveAsync(conn)
    if msgAvailable:
      result.add msg
      expectMessage = moreAvailable
    else:
      expectMessage = false

proc sendAsync*(conn: ZConnection, msg: string, flags: ZSendRecvOptions = DONTWAIT): Future[void] =
  ## `send()` is blocking for some connection types (e.g. PUSH, DEALER).
  ## `sendAsync()` allows other async tasks to run in those cases.
  ##
  ## This will not work in some case because it depends on ZMQ_FD which is not necessarily the 'true' FD of the socket
  ##
  ## See https://github.com/zeromq/libzmq/issues/2941 and https://github.com/zeromq/pyzmq/issues/1411
  let fut = newFuture[void]("sendAsync")
  result = fut

  let status = getsockopt[cint](conn, ZSockOptions.EVENTS)
  if (status and ZMQ_POLLOUT) == 0:
    # wait until queue available
    let sock = conn.socket
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
