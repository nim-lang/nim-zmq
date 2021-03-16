import connections
import bindings

# Socket option for PSocket type
# Setsocket option for integer
# Some option take cint, int64 or uint64 so a template is needed
proc setsockopt[T: SomeOrdinal](s: PSocket, option: TSockOptions, optval: T) =
  var val: T = optval
  if setsockopt(s, option, addr(val), sizeof(val)) != 0:
    zmqError()

proc setsockopt(s: PSocket, option: TSockOptions, optval: string) =
  var val: string = optval
  if setsockopt(s, option, cstring(val), val.len) != 0:
    zmqError()

# some sockopt returns integer values
proc getsockopt[T: SomeOrdinal](s: PSocket, option: TSockOptions,
    optval: var T) =
  var optval_len: int = sizeof(optval)

  if getsockopt(s, option, addr(optval), addr(optval_len)) != 0:
    zmqError()

# Some sockopt returns a string
proc getsockopt(s: PSocket, option: TSockOptions, optval: var string) =
  var optval_len: int = optval.len

  if getsockopt(s, option, cstring(optval), addr(optval_len)) != 0:
    zmqError()

# Export generic function on PSocket
proc getsockopt*[T: SomeOrdinal|string](s: PSocket, option: TSockOptions): T =
  var optval: T
  getsockopt(s, option, optval)
  optval

proc setsockopt*[T: SomeOrdinal|string](s: PSocket, option: TSockOptions, optval: T) =
  setsockopt[T](s, option, optval)

# Export generic function on TConnection
proc setsockopt*[T: SomeOrdinal|string](c: TConnection, option: TSockOptions, optval: T) =
  setsockopt[T](c.s, option, optval)

proc getsockopt*[T: SomeOrdinal|string](c: TConnection, option: TSockOptions): T =
  getsockopt[T](c.s, option)

