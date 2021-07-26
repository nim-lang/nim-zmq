# Package

version       = "1.1.0"
author        = "Andreas Rumpf"
description   = "ZeroMQ wrapper"
license       = "MIT"

# Dependencies
requires "nim >= 0.18.0"

task gendoc, "Generate documentation":
  nimble doc --project zmq.nim --out:docs/

task runexamples, "Run all examples":
  withDir "examples":
    for fstr in listFiles("."):
      if fstr.endsWith(".nim") and fstr.startsWith("ex"):
        echo "running ", fstr
        selfExec("cpp -r -d:release " & fstr)
