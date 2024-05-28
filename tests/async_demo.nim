import ../zmq
import std/[asyncdispatch]

proc asyncpoll() =
  # test "asyncZPoller":
  block:
    const zaddr = "tcp://127.0.0.1:15571"
    const zaddr2 = "tcp://127.0.0.1:15572"
    var pusher = listen(zaddr, PUSH)
    var puller = connect(zaddr, PULL)

    var pusher2 = listen(zaddr2, PUSH)
    var puller2 = connect(zaddr2, PULL)
    var poller: AsyncZPoller

    var i = 0
    # Register the callback
    # assert message received are correct (should be even integer in string format)
    var msglist = @["0", "2", "4", "6", "8"]
    var msgCount = 0
    poller.register(
      puller2,
      ZMQ_POLLIN,
      proc(x: ZSocket) =
        let
          # Avoid using indefinitly blocking proc in async context
          res = x.waitForReceive(timeout=10)
        if res.msgAvailable:
          let
            msg = res.msg
          inc(msgCount)
          if msglist.contains(msg):
            msglist.delete(0)
            assert true
          else:
            assert false
    )
    # assert message received are correct (should be even integer in string format)
    var msglist2 = @["0", "2", "4", "6", "8"]
    var msgCount2 = 0
    poller.register(
      puller,
      ZMQ_POLLIN,
      proc(x: ZSocket) =
        let
          # Avoid using indefinitly blocking proc in async context
          res = x.waitForReceive(timeout=10)
        if res.msgAvailable:
          let
            msg = res.msg
          inc(msgCount2)
          if msglist2.contains(msg):
            msglist2.delete(0)
            assert true
          else:
            assert false
    )

    let
      N = 10
      N_MAX_TIMEOUT = 5

    var sndCount = 0
    # A client send some message
    for i in 0..<N:
      if (i mod 2) == 0:
        # Can periodically send stuff
        pusher.send($i)
        pusher2.send($i)
        inc(sndCount)

    # N_MAX_TIMEOUT is the number of time the poller can timeout before exiting the loop
    while i < N_MAX_TIMEOUT:

      # I don't recommend a high timeout because it's going to poll for the duration if there is no message in queue
      var fut = poller.pollAsync(1)
      let r = waitFor fut
      if r < 0:
        break # error case
      elif r == 0:
        inc(i)

    # No longer polling but some callback may not have finished
    while hasPendingOperations():
      drain()

    assert msgCount == msgCount2
    assert msgCount == sndCount

    pusher.close()
    puller.close()
    pusher2.close()
    puller2.close()

when isMainModule:
  asyncpoll()
