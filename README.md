# luajit-tcc-float
Luajit implementation of C float (32-bit). Ensuring no downcast (float -> number(lua double)) during operations with the use of JIT C compiled functions through the use of TCC with lua bindings from https://github.com/Playermet
Very helpful if you need to accurately represent floating point operations, where the accuracy changes from 32 to 64 bit may deliver different results.

# Requirements

* https://github.com/Playermet/luajit-tcc/blob/master/tcc.lua tcc library
* libtcc installed
* luajit supporting lua 5.1 (probably luajit 2.1)

# Set up
You probably need to set up the tcc lua lib path. For me it was lying in lib/tcc.lua and hence require inside of the function is 'lib.tcc'.
I have tested it with tcc 0.9.28 and the API doesn't seem to be changed ever since 0.9.26, even if the tcc lua library might rely it. For linux you might need to build the library yourself (with ./configure --disable-static), as libtcc-dev doesn't seem to contain the .so file.

# Example

```lua
f32 = require('tcc_float')

local a = f32(5.0)
local b = f32(1.5)

a = b + a
local isBigger = a > b
local isNil = a == nil

local primitiveOp = a + 5

--NOT FUNCTIONAL:
local primitiveFirstOp = 5 + a
```
