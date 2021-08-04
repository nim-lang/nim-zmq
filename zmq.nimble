# Package

version       = "1.2.0"
author        = "Andreas Rumpf"
description   = "ZeroMQ wrapper"
license       = "MIT"

# Dependencies
requires "nim >= 0.18.0"

task buildexamples, "Compile all examples":
  withDir "examples":
    for fstr in listFiles("."):
      echo fstr
      if fstr.endsWith(".nim") and fstr.startsWith("./ex"):
        echo "running ", fstr
        selfExec("cpp -d:release " & fstr)

task gendoc, "Generate documentation":
  exec("nimble doc --project zmq.nim --out:docs/")
