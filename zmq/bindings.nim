{.deadCodeElim: on.}
when defined(windows):
  const
    zmqdll* = "(lib|)zmq.dll"
elif defined(macosx):
  const
    zmqdll* = "libzmq.dylib"
else:
  const
    zmqdll* = "libzmq.so(.4|.5|)"

#  Version macros for compile-time API version detection
const
  ZMQ_VERSION_MAJOR* = 4
  ZMQ_VERSION_MINOR* = 2
  ZMQ_VERSION_PATCH* = 0

template ZMQ_MAKE_VERSION*(major, minor, patch: untyped): untyped =
  ((major) * 10000 + (minor) * 100 + (patch))

const
  ZMQ_VERSION* = ZMQ_MAKE_VERSION(ZMQ_VERSION_MAJOR, ZMQ_VERSION_MINOR,
                                    ZMQ_VERSION_PATCH)

#****************************************************************************
#  0MQ errors.
#****************************************************************************
#  A number random enough not to collide with different errno ranges on
#  different OSes. The assumption is that error_t is at least 32-bit type.
const
  ZMQ_HAUSNUMERO = 156384712
#  On Windows platform some of the standard POSIX errnos are not defined.
when not(defined(ENOTSUP)):
  const
    ENOTSUP* = (ZMQ_HAUSNUMERO + 1)
    EPROTONOSUPPORT* = (ZMQ_HAUSNUMERO + 2)
    ENOBUFS* = (ZMQ_HAUSNUMERO + 3)
    ENETDOWN* = (ZMQ_HAUSNUMERO + 4)
    EADDRINUSE* = (ZMQ_HAUSNUMERO + 5)
    EADDRNOTAVAIL* = (ZMQ_HAUSNUMERO + 6)
    ECONNREFUSED* = (ZMQ_HAUSNUMERO + 7)
    EINPROGRESS* = (ZMQ_HAUSNUMERO + 8)
    ENOTSOCK* = (ZMQ_HAUSNUMERO + 9)
    EMSGSIZE* = (ZMQ_HAUSNUMERO + 10)
    EAFNOSUPPORT* = (ZMQ_HAUSNUMERO + 11)
    ENETUNREACH* = (ZMQ_HAUSNUMERO + 12)
    ECONNABORTED* = (ZMQ_HAUSNUMERO + 13)
    ECONNRESET* = (ZMQ_HAUSNUMERO + 14)
    ENOTCONN* = (ZMQ_HAUSNUMERO + 15)
    ETIMEDOUT* = (ZMQ_HAUSNUMERO + 16)
    EHOSTUNREACH* = (ZMQ_HAUSNUMERO + 17)
    ENETRESET* = (ZMQ_HAUSNUMERO + 18)

#  Native 0MQ error codes.
const
  EFSM* = (ZMQ_HAUSNUMERO + 51)
  ENOCOMPATPROTO* = (ZMQ_HAUSNUMERO + 52)
  ETERM* = (ZMQ_HAUSNUMERO + 53)
  EMTHREAD* = (ZMQ_HAUSNUMERO + 54)

#  Run-time API version detection
proc version*(major: var cint, minor: var cint, patch: var cint){.cdecl,
  importc: "zmq_version", dynlib: zmqdll.}

#  This function retrieves the errno as it is known to 0MQ library. The goal
#  of this function is to make the code 100% portable, including where 0MQ
#  compiled with certain CRT library (on Windows) is linked to an
#  application that uses different CRT library.
proc errno*(): cint{.cdecl, importc: "zmq_errno", dynlib: zmqdll.}

#  Resolves system errors and 0MQ errors to human-readable string.
proc strerror*(errnum: cint): cstring {.cdecl, importc: "zmq_strerror",
  dynlib: zmqdll.}

# Socket Types
type
  TSocket {.final, pure.} = object
  ZSocket* = ptr TSocket

#****************************************************************************
#  0MQ infrastructure (a.k.a. context) initialisation & termination.
#****************************************************************************
#  New API
#  Context options
type
  TContext {.final, pure.} = object
  ZContext* = ptr TContext
const
  ZMQ_IO_THREADS* = 1
  ZMQ_MAX_SOCKETS* = 2
  ZMQ_SOCKET_LIMIT* = 3
  ZMQ_THREAD_PRIORITY* = 3
  ZMQ_THREAD_SCHED_POLICY* = 4


type ZContextOptions* = enum
  IO_THREADS = 1
  MAX_SOCKETS = 2
  #SOCKET_LIMIT = 3
  #THREAD_PRIORITY = 3
  ZMQ_IPV6 = 42

#  Default for new contexts
const
  ZMQ_IO_THREADS_DFLT* = 1
  ZMQ_MAX_SOCKETS_DFLT* = 1023
  ZMQ_THREAD_PRIORITY_DFLT* = - 1
  ZMQ_THREAD_SCHED_POLICY_DFLT* = - 1


proc ctx_new*(): ZContext {.cdecl, importc: "zmq_ctx_new", dynlib: zmqdll.}
proc ctx_term*(context: ZContext): cint {.cdecl, importc: "zmq_ctx_term",
  dynlib: zmqdll.}
proc ctx_shutdown*(ctx: ZContext): cint {.cdecl, importc: "zmq_ctx_shutdown",
  dynlib: zmqdll.}
proc ctx_set*(context: ZContext; option: cint; optval: cint): cint {.cdecl,
  importc: "zmq_ctx_set", dynlib: zmqdll.}
proc ctx_get*(context: ZContext; option: cint): cint {.cdecl,
  importc: "zmq_ctx_get", dynlib: zmqdll.}

#  Old (legacy) API
#proc zmq_init*(io_threads: cint): pointer
#proc zmq_term*(context: pointer): cint
#proc zmq_ctx_destroy*(context: pointer): cint

proc init*(io_threads: cint): ZContext {.cdecl, importc: "zmq_init",
                                         dynlib: zmqdll, deprecated: "Legacy API. Use ctx_new instead".}
proc term*(context: ZContext): cint {.cdecl, importc: "zmq_term",
                                      dynlib: zmqdll, deprecated: "Legacy API. Use ctx_term instead".}
proc ctx_destroy*(context: ZContext): cint {.cdecl, importc: "zmq_ctx_destroy",
                                             dynlib: zmqdll, deprecated: "Legacy API. Use ctx_term instead".}


#****************************************************************************
#  0MQ message definition.
#****************************************************************************
template make_dotted_version(major, minor, patch: untyped): string =
  $major & "." & $minor & "." & $patch

proc zmq_msg_t_size(dotted_version: string): int =
  # From the zeromq repository and versions,
  # cos there isn't an ffi way to get it direct from libzmq,
  # and anyway ffi doesn't work at compile time.
  case dotted_version
  of "4.2.0":
    64
  of "4.1.5", "4.1.4", "4.1.3", "4.1.2", "4.1.1":
    64
  of "4.1.0":
    48
  of "4.0.8", "4.0.7", "4.0.6", "4.0.5", "4.0.4", "4.0.3", "4.0.2", "4.0.1", "4.0.0":
    32
  of "3.2.5", "3.2.4", "3.2.3", "3.2.2", "3.2.1", "3.1.0":
    32
  else:
    # assuming this is for newer versions.
    # It will probably stay at 64 for a while https://github.com/zeromq/libzmq/issues/1295
    64

type
  ZMsg* {.pure, final.} = object
    priv*: array[zmq_msg_t_size(make_dotted_version(ZMQ_VERSION_MAJOR,
        ZMQ_VERSION_MINOR, ZMQ_VERSION_PATCH)), uint8]

  TFreeFn = proc (data, hint: pointer) {.noconv.}

# check that library version (from dynlib/dll/so) matches header version (from zmq.h)
# and that sizeof(zmq_msg_t) matches ZMsg
proc sanity_check_libzmq(): void =
  var actual_lib_major, actual_lib_minor, actual_lib_patch: cint
  version(actual_lib_major, actual_lib_minor, actual_lib_patch)

  let
    expected_lib_version = make_dotted_version(ZMQ_VERSION_MAJOR,
        ZMQ_VERSION_MINOR, ZMQ_VERSION_PATCH)
    actual_lib_version = make_dotted_version(actual_lib_major, actual_lib_minor, actual_lib_patch)

  # This is possibly over-particular about versioning
  # if not (ZMQ_VERSION_MAJOR == actual_lib_major and actual_lib_minor >= ZMQ_VERSION_MINOR):
  #   raise newException( LibraryError, "expecting libzmq-" & expected_lib_version & " but found libzmq-" & actual_lib_version )

  # This gives more flexibility wrt to versions, but set of API calls may differ
  if zmq_msg_t_size(actual_lib_version) != sizeof(ZMsg):
    raise newException(LibraryError, "expecting ZMsg size of " & $sizeof(ZMsg) &
        " but found " & $zmq_msg_t_size(actual_lib_version) & " from libzmq-" & actual_lib_version)

sanity_check_libzmq()

proc msg_init*(msg: var ZMsg): cint {.cdecl, importc: "zmq_msg_init",
  dynlib: zmqdll.}
proc msg_init*(msg: var ZMsg; size: int): cint {.cdecl,
  importc: "zmq_msg_init_size", dynlib: zmqdll.}
proc msg_init*(msg: var ZMsg; data: cstring; size: int;
                        ffn: TFreeFn; hint: pointer): cint {.cdecl,
                        importc: "zmq_msg_init_data", dynlib: zmqdll.}
proc msg_send*(msg: var ZMsg; s: ZSocket; flags: cint): cint {.cdecl,
  importc: "zmq_msg_send", dynlib: zmqdll.}
proc msg_recv*(msg: var ZMsg; s: ZSocket; flags: cint): cint {.cdecl,
  importc: "zmq_msg_recv", dynlib: zmqdll.}
proc msg_close*(msg: var ZMsg): cint {.cdecl, importc: "zmq_msg_close",
  dynlib: zmqdll.}
proc msg_move*(dest, src: var ZMsg): cint {.cdecl,
  importc: "zmq_msg_move", dynlib: zmqdll.}
proc msg_copy*(dest, src: var ZMsg): cint {.cdecl,
  importc: "zmq_msg_copy", dynlib: zmqdll.}
proc msg_data*(msg: var ZMsg): pointer {.cdecl, importc: "zmq_msg_data",
  dynlib: zmqdll.}
proc msg_size*(msg: var ZMsg): int {.cdecl, importc: "zmq_msg_size",
  dynlib: zmqdll.}
proc msg_more*(msg: var ZMsg): cint {.cdecl, importc: "zmq_msg_more",
  dynlib: zmqdll.}
proc msg_get*(msg: var ZMsg; option: cint): cint {.cdecl,
    importc: "zmq_msg_get",
  dynlib: zmqdll.}
proc msg_set*(msg: var ZMsg; option: cint; optval: cint): cint {.cdecl,
  importc: "zmq_msg_set", dynlib: zmqdll.}

#****************************************************************************
#  0MQ socket definition.
#****************************************************************************
#  Socket types.
const
  ZMQ_PAIR* = 0
  ZMQ_PUB* = 1
  ZMQ_SUB* = 2
  ZMQ_REQ* = 3
  ZMQ_REP* = 4
  ZMQ_DEALER* = 5
  ZMQ_ROUTER* = 6
  ZMQ_PULL* = 7
  ZMQ_PUSH* = 8
  ZMQ_XPUB* = 9
  ZMQ_XSUB* = 10
  ZMQ_STREAM* = 11
  ZMQ_SERVER* = 12
  ZMQ_CLIENT* = 13

type
  ZSocketType* = enum
    PAIR = 0,
    PUB = 1,
    SUB = 2,
    REQ = 3,
    REP = 4,
    DEALER = 5,
    ROUTER = 6,
    PULL = 7,
    PUSH = 8,
    XPUB = 9,
    XSUB = 10,
    STREAM = 11
    SERVER = 12
    CLIENT = 13

#  Deprecated aliases
const
  ZMQ_XREQ* = ZMQ_DEALER
  ZMQ_XREP* = ZMQ_ROUTER
#  Socket options.
const
  ZMQ_AFFINITY* = 4
  ZMQ_IDENTITY* = 5
  ZMQ_SUBSCRIBE* = 6
  ZMQ_UNSUBSCRIBE* = 7
  ZMQ_RATE* = 8
  ZMQ_RECOVERY_IVL* = 9
  ZMQ_SNDBUF* = 11
  ZMQ_RCVBUF* = 12
  ZMQ_RCVMORE* = 13
  ZMQ_FD* = 14
  ZMQ_EVENTS* = 15
  ZMQ_TYPE* = 16
  ZMQ_LINGER* = 17
  ZMQ_RECONNECT_IVL* = 18
  ZMQ_BACKLOG* = 19
  ZMQ_RECONNECT_IVL_MAX* = 21
  ZMQ_MAXMSGSIZE* = 22
  ZMQ_SNDHWM* = 23
  ZMQ_RCVHWM* = 24
  ZMQ_MULTICAST_HOPS* = 25
  ZMQ_RCVTIMEO* = 27
  ZMQ_SNDTIMEO* = 28
  ZMQ_LAST_ENDPOINT* = 32
  ZMQ_ROUTER_MANDATORY* = 33
  ZMQ_TCP_KEEPALIVE* = 34
  ZMQ_TCP_KEEPALIVE_CNT* = 35
  ZMQ_TCP_KEEPALIVE_IDLE* = 36
  ZMQ_TCP_KEEPALIVE_INTVL* = 37
  #ZMQ_TCP_ACCEPT_FILTER* = 38
  ZMQ_IMMEDIATE* = 39
  ZMQ_XPUB_VERBOSE* = 40
  ZMQ_ROUTER_RAW* = 41
  #ZMQ_IPV6* = 42
  ZMQ_MECHANISM* = 43
  ZMQ_PLAIN_SERVER* = 44
  ZMQ_PLAIN_USERNAME* = 45
  ZMQ_PLAIN_PASSWORD* = 46
  ZMQ_CURVE_SERVER* = 47
  ZMQ_CURVE_PUBLICKEY* = 48
  ZMQ_CURVE_SECRETKEY* = 49
  ZMQ_CURVE_SERVERKEY* = 50
  ZMQ_PROBE_ROUTER* = 51
  ZMQ_REQ_CORRELATE* = 52
  ZMQ_REQ_RELAXED* = 53
  ZMQ_CONFLATE* = 54
  ZMQ_ZAP_DOMAIN* = 55
  ZMQ_ROUTER_HANDOVER* = 56
  ZMQ_TOS* = 57
  #ZMQ_IPC_FILTER_PID* = 58
  #ZMQ_IPC_FILTER_UID* = 59
  #ZMQ_IPC_FILTER_GID* = 60
  ZMQ_CONNECT_RID* = 61
  ZMQ_GSSAPI_SERVER* = 62
  ZMQ_GSSAPI_PRINCIPAL* = 63
  ZMQ_GSSAPI_SERVICE_PRINCIPAL* = 64
  ZMQ_GSSAPI_PLAINTEXT* = 65
  ZMQ_HANDSHAKE_IVL* = 66
  ZMQ_SOCKS_PROXY* = 68
  ZMQ_XPUB_NODROP* = 69
  ZMQ_BLOCKY* = 70
  ZMQ_XPUB_MANUAL* = 71
  ZMQ_XPUB_WELCOME_MSG* = 72
  ZMQ_STREAM_NOTIFY* = 73
  ZMQ_INVERT_MATCHING* = 74
  ZMQ_HEARTBEAT_IVL* = 75
  ZMQ_HEARTBEAT_TTL* = 76
  ZMQ_HEARTBEAT_TIMEOUT* = 77
  ZMQ_XPUB_VERBOSE_UNSUBSCRIBE* = 78
  ZMQ_CONNECT_TIMEOUT* = 79
  ZMQ_TCP_RETRANSMIT_TIMEOUT* = 80
  ZMQ_THREAD_SAFE* = 81

type ZSockOptions* = enum
  AFFINITY = 4
  IDENTITY = 5
  SUBSCRIBE = 6
  UNSUBSCRIBE = 7
  RATE = 8
  RECOVERY_IVL = 9
  SNDBUF = 11
  RCVBUF = 12
  RCVMORE = 13
  FD = 14
  EVENTS = 15
  TYPE = 16
  LINGER = 17
  RECONNECT_IVL = 18
  BACKLOG = 19
  RECONNECT_IVL_MAX = 21
  MAXMSGSIZE = 22
  SNDHWM = 23
  RCVHWM = 24
  MULTICAST_HOPS = 25
  RCVTIMEO = 27
  SNDTIMEO = 28
  LAST_ENDPOINT = 32
  ROUTER_MANDATORY = 33
  TCP_KEEPALIVE = 34
  TCP_KEEPALIVE_CNT = 35
  TCP_KEEPALIVE_IDLE = 36
  TCP_KEEPALIVE_INTVL = 37
  TCP_ACCEPT_FILTER = 38
  IMMEDIATE = 39
  XPUB_VERBOSE = 40
  ROUTER_RAW = 41
  IPV6 = 42
  MECHANISM = 43
  PLAIN_SERVER = 44
  PLAIN_USERNAME = 45
  PLAIN_PASSWORD = 46
  CURVE_SERVER = 47
  CURVE_PUBLICKEY = 48
  CURVE_SECRETKEY = 49
  CURVE_SERVERKEY = 50
  PROBE_ROUTER = 51
  REQ_CORRELATE = 52
  REQ_RELAXED = 53
  CONFLATE = 54
  ZAP_DOMAIN = 55
  ROUTER_HANDOVER = 56
  TOS = 57
  CONNECT_RID = 61
  GSSAPI_SERVER = 62
  GSSAPI_PRINCIPAL = 63
  GSSAPI_SERVICE_PRINCIPAL = 64
  GSSAPI_PLAINTEXT = 65
  HANDSHAKE_IVL = 66
  SOCKS_PROXY = 68
  XPUB_NODROP = 69
  BLOCKY = 70
  XPUB_MANUAL = 71
  XPUB_WELCOME_MSG = 72
  STREAM_NOTIFY = 73
  INVERT_MATCHING = 74
  HEARTBEAT_IVL = 75
  HEARTBEAT_TTL = 76
  HEARTBEAT_TIMEOUT = 77
  XPUB_VERBOSE_UNSUBSCRIBE = 78
  CONNECT_TIMEOUT = 79
  TCP_RETRANSMIT_TIMEOUT = 80
  THREAD_SAFE = 81

#  Message options
const
  ZMQ_MORE* = 1
  ZMQ_SRCFD* = 2
  ZMQ_SHARED* = 3
type ZMsgOptions = enum
  MORE = 1
  SRCFD = 2
  SHARED = 3

#  Send/recv options.
#  Added NOFLAGS option for default argument in send / receive function
const
  ZMQ_DONTWAIT* = 1
  ZMQ_SNDMORE* = 2
type ZSendRecvOptions* = enum
  NOFLAGS = 0
  DONTWAIT = 1
  SNDMORE = 2

#  Security mechanisms
const
  ZMQ_NULL* = 0
  ZMQ_PLAIN* = 1
  ZMQ_CURVE* = 2
  ZMQ_GSSAPI* = 3
#  Deprecated options and aliases
const
  ZMQ_IPV4ONLY* = 31
  ZMQ_TCP_ACCEPT_FILTER* = 38
  ZMQ_IPC_FILTER_PID* = 58
  ZMQ_IPC_FILTER_UID* = 59
  ZMQ_IPC_FILTER_GID* = 60
  ZMQ_DELAY_ATTACH_ON_CONNECT* = ZMQ_IMMEDIATE
  ZMQ_NOBLOCK* = ZMQ_DONTWAIT
  ZMQ_FAIL_UNROUTABLE* = ZMQ_ROUTER_MANDATORY
  ZMQ_ROUTER_BEHAVIOR* = ZMQ_ROUTER_MANDATORY

#****************************************************************************
#  0MQ socket events and monitoring
#****************************************************************************
#  Socket transport events (tcp and ipc only)
const
  ZMQ_EVENT_CONNECTED* = 1
  ZMQ_EVENT_CONNECT_DELAYED* = 2
  ZMQ_EVENT_CONNECT_RETRIED* = 4
  ZMQ_EVENT_LISTENING* = 8
  ZMQ_EVENT_BIND_FAILED* = 16
  ZMQ_EVENT_ACCEPTED* = 32
  ZMQ_EVENT_ACCEPT_FAILED* = 64
  ZMQ_EVENT_CLOSED* = 128
  ZMQ_EVENT_CLOSE_FAILED* = 256
  ZMQ_EVENT_DISCONNECTED* = 512
  ZMQ_EVENT_MONITOR_STOPPED* = 1024
  ZMQ_EVENT_ALL* = (ZMQ_EVENT_CONNECTED or ZMQ_EVENT_CONNECT_DELAYED or
      ZMQ_EVENT_CONNECT_RETRIED or ZMQ_EVENT_LISTENING or
      ZMQ_EVENT_BIND_FAILED or ZMQ_EVENT_ACCEPTED or ZMQ_EVENT_ACCEPT_FAILED or
      ZMQ_EVENT_CLOSED or ZMQ_EVENT_CLOSE_FAILED or ZMQ_EVENT_DISCONNECTED or
      ZMQ_EVENT_MONITOR_STOPPED)
#  Socket event data
type
  zmq_event_t* {.pure, final.} = object
    event*: uint16 # id of the event as bitfield
    value*: int32  # value is either error code, fd or reconnect interval

proc socket*(context: ZContext, theType: cint): ZSocket {.cdecl,
      importc: "zmq_socket", dynlib: zmqdll.}
proc close*(s: ZSocket): cint{.cdecl, importc: "zmq_close", dynlib: zmqdll.}
proc setsockopt*(s: ZSocket, option: ZSockOptions, optval: pointer,
                       optvallen: int): cint {.cdecl, importc: "zmq_setsockopt",
      dynlib: zmqdll.}
proc getsockopt*(s: ZSocket, option: ZSockOptions, optval: pointer,
                   optvallen: ptr int): cint{.cdecl,
      importc: "zmq_getsockopt", dynlib: zmqdll.}
proc bindAddr*(s: ZSocket, address: cstring): cint{.cdecl, importc: "zmq_bind",
      dynlib: zmqdll.}
proc connect*(s: ZSocket, address: cstring): cint{.cdecl,
      importc: "zmq_connect", dynlib: zmqdll.}
proc unbind*(s: ZSocket; address: cstring): cint {.cdecl, importc: "zmq_unbind",
      dynlib: zmqdll.}
proc disconnect*(s: ZSocket; address: cstring): cint {.cdecl,
      importc: "zmq_disconnect", dynlib: zmqdll.}
proc send*(s: ZSocket; buf: pointer; len: int; flags: cint): cint {.cdecl,
      importc: "zmq_send", dynlib: zmqdll.}
proc send_const*(s: ZSocket; buf: pointer; len: int; flags: cint): cint {.cdecl,
      importc: "zmq_send_const", dynlib: zmqdll.}
proc recv*(s: ZSocket; buf: pointer; len: int; flags: cint): cint {.cdecl,
      importc: "zmq_recv", dynlib: zmqdll.}
proc socket_monitor*(s: ZSocket; address: pointer; events: cint): cint {.cdecl,
      importc: "zmq_socket_monitor", dynlib: zmqdll.}

proc sendmsg*(s: ZSocket, msg: var ZMsg, flags: cint): cint{.cdecl,
      importc: "zmq_sendmsg", dynlib: zmqdll.}
proc recvmsg*(s: ZSocket, msg: var ZMsg, flags: cint): cint{.cdecl,
      importc: "zmq_recvmsg", dynlib: zmqdll.}


#****************************************************************************
#  I/O multiplexing.
#****************************************************************************
const
  ZMQ_POLLIN* = 1
  ZMQ_POLLOUT* = 2
  ZMQ_POLLERR* = 4
  ZMQ_POLLPRI* = 8
type
  ZPollItem*{.pure, final.} = object
    socket*: ZSocket
    fd*: cint
    events*: cshort
    revents*: cshort

const
  ZMQ_POLLITEMS_DFLT* = 16

proc poll*(items: ptr UncheckedArray[ZPollItem], nitems: cint,
    timeout: clong): cint{.
  cdecl, importc: "zmq_poll", dynlib: zmqdll.}

#  Built-in message proxy (3-way)
proc proxy*(frontend: ZSocket; backend: ZSocket; capture: ZSocket): cint {.
  cdecl, importc: "zmq_proxy", dynlib: zmqdll.}
proc proxy_steerable*(frontend: ZSocket; backend: ZSocket; capture: ZSocket;
            control: ZSocket): cint {.cdecl, importc: "zmq_proxy_steerable",
    dynlib: zmqdll.}

#  Encode a binary key as printable text using ZMQ RFC 32
proc z85_encode*(dest: cstring; data: ptr uint8; size: int): cstring {.
  cdecl, importc: "zmq_z85_encode", dynlib: zmqdll.}

#  Encode a binary key from printable text per ZMQ RFC 32
proc z85_decode*(dest: ptr uint8; string: cstring): ptr uint8 {.
  cdecl, importc: "zmq_z85_decode", dynlib: zmqdll.}

#  Deprecated aliases
#const
#  ZMQ_STREAMER* = 1
#  ZMQ_FORWARDER* = 2
#  ZMQ_QUEUE* = 3
#  Deprecated method
#proc zmq_device*(type: cint; frontend: pointer; backend: pointer): cint

