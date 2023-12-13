import ../zmq
import std/unittest

proc sockHandler(req, rep: ZConnection, pong: string) =
    req.send(pong)
    let r = rep.receive()
    check r == pong
    # debugEcho "EndCB"

proc testDestroy() =
  const sockaddr = "tcp://127.0.0.1:55001"

  test "Destroy & Copy":
    let
      ping = "ping"
      pong = "pong"

    var rep = listen(sockaddr, REP)
    var req = connect(sockaddr, REQ)
    # unsafeRepPtr = addr(rep)
    # unsafeReqPtr = addr(req)

    sockHandler(req, rep, ping)
    sockHandler(rep, req, pong)

    block:
      var req2 = req
      req2.send(ping)
      let r = rep.receive()
      check r == ping
      # debugEcho "end block scope"

    rep.send(pong)
    block:
      var req2 = req
      let r = req2.receive()
      check r == pong
      # debugEcho "end test scope"

when isMainModule:
  testDestroy()

