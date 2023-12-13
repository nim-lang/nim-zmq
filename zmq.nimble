# Package

version       = "1.5.0"
author        = "Andreas Rumpf"
description   = "ZeroMQ wrapper"
license       = "MIT"

# Dependencies
requires "nim >= 1.4.0"

task buildexamples, "Compile all examples":
  withDir "examples":
    for fstr in listFiles("."):
      echo fstr
      if fstr.endsWith(".nim") and fstr.startsWith("./ex"):
        echo "running ", fstr
        selfExec("cpp --mm:orc -d:release " & fstr)

task gendoc, "Generate documentation":
  exec("nim doc --mm:orc --project --out:docs/ zmq.nim")

