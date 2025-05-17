-- float functionality wrapper for tcc luajit binding

ffi = require("ffi")

local tcc = require 'lib.tcc' ('/usr/local/lib/libtcc.so')



local state = tcc.new()

state:set_output_type('output_memory')


local compilationResult = state:compile_string [[
#define val(x) x.a[0]
#define deref(x) x->a[0]

#define arith(funcName,op) float_sandwich_t funcName(float_sandwich_t* a, float_sandwich_t* b) { float_sandwich_t c; val(c) = deref(a) op deref(b); return c; }
#define compar(funcName,op) int funcName(float_sandwich_t* a,float_sandwich_t* b) { return deref(a) op deref(b); }

  // metatypes only work for unique structs. float*->float also results in incorrect resolve (always returns 0 in downcast in lua)
  typedef struct {
    float a[1]; // direct access to float incorrectly dereferences
  } float_sandwich_t;

  // generic functionality and stability tests of LJ/TCC with floats
  void test() {}
  float test2() {
    float_sandwich_t b;
    val(b) = 2.5;
    return val(b);
  }
  float_sandwich_t test3() {
    float_sandwich_t b;
    val(b) = 3.5;
    return b;
  }
  float_sandwich_t test4(float_sandwich_t in) {
    val(in) = 4.5;
    return in;
  }
  float_sandwich_t test5(float_sandwich_t* in) {
    deref(in) = 5.5;
    return *in;
  }
  
  // arithmetic operators
  arith(if32add,+)
  arith(if32sub,-)
  arith(if32mul,*)
  arith(if32div,/)


  // compare operators
  compar(f32lt,<)
  compar(f32le,<=)
  compar(f32eq,==)

  int sizeofFloat() { return sizeof(float); }
  int sizeofStruct() { return sizeof(float_sandwich_t); }
]]
assert(compilationResult == 0)
state:relocate('relocate_auto')

-- immediate arithmetic functions
function get_symbol_arith(name)
  local cmp_symbol = "float_sandwich_t(*)(float_sandwich_t*,float_sandwich_t*)"
  return state:get_symbol(name, cmp_symbol,"float_sandwich_t")
end

function get_symbol_compare(name)
  local cmp_symbol = "int(*)(float_sandwich_t*,float_sandwich_t*)"
  return state:get_symbol(name, cmp_symbol,"int")
end


ffi.cdef [[
  typedef struct {
    float a[1];
  } float_sandwich_t;
]]




f32lt = get_symbol_compare("f32lt")
f32le = get_symbol_compare("f32le")
f32eq = get_symbol_compare("f32eq")

f32add = get_symbol_arith("if32add")
f32sub = get_symbol_arith("if32sub")
f32mul = get_symbol_arith("if32mul")
f32div = get_symbol_arith("if32div")


-- invokation works
state:get_symbol('test', 'void(*)()')()

-- float RETURN value is correct
local t2 = state:get_symbol('test2', 'float(*)()')()
--print(t2)

assert(t2 == 2.5)

--float sandwich return value also works
local t3 = state:get_symbol('test3', 'float_sandwich_t(*)()',"float_sandwich_t")()
--print(t3.a[0])
assert(t3.a[0] == 3.5)

-- pass and dont use
local t4 = state:get_symbol('test4', 'float_sandwich_t(*)(float_sandwich_t)',"float_sandwich_t")(t3)
--print(t4.a[0],"t3 should still be same as above",t3.a[0])
assert(t4.a[0] == 4.5)

-- pass and use, copy return value
local t5 = state:get_symbol('test5', 'float_sandwich_t(*)(float_sandwich_t*)',"float_sandwich_t")(t3)
--print(t5.a[0],"t3 should now also be",t3.a[0])
assert(t5.a[0] == 5.5 and t3.a[0] == 5.5)

-- simple addition test (more below)
local t6 = f32add(t3,t4)
--print(t6.a[0]," should be the sum of ",t3.a[0],t4.a[0])
assert(t6.a[0] == (t4.a[0] + t3.a[0]))


local t3addr = string.split(tostring(t3),":")[2]
local t4addr = string.split(tostring(t3),":")[2]
--print("also, t7 should just be the pointer to t6",tostring(t6),tostring(t7))
assert(t3addr == t4addr)

--print("Oh and also t3 should be bigger than t4? (this might be a double-check, but float->double is 1:1 mapping)",t3.a[0] > t4.a[0])
assert(t3.a[0] > t4.a[0])

--print("and t6 is normal",t6) -- original struct type -> normal struct type

-- assertions on struct type
local sizeofFloat = state:get_symbol('sizeofFloat','int(*)()','int)')
local sizeofStruct = state:get_symbol('sizeofFloat','int(*)()','int)')
local EXPECTED_FLOAT_SIZE = 4
assert(sizeofFloat() == EXPECTED_FLOAT_SIZE)
assert(sizeofStruct() == EXPECTED_FLOAT_SIZE)


local f32 = function(v)
  -- if its already of f32 type, just pass it through, else create f32 if type is numeric
  return ffi.istype("float_sandwich_t",v) and v or (type(v) == "number") and ffi.new("float_sandwich_t",{a={v}}) 
end

-- create new metatype for this shit
function generic_comp(compfunc)
      return function(a,b)
        if ffi.istype("float_sandwich_t",b) or type(b) == "number" then -- is f32 castable (nil is not, string is not, etc. etc.)
          local b = ffi.istype("float_sandwich_t",b) and b or f32(b)
          return compfunc(a,b) ~= 0 -- 0 == false and 1 (a rel op b = true) == true 
        else
          return false
        end
      end
end
function generic_arith(arithfunc)
    return function(a,b)
      local b = ffi.istype("float_sandwich_t",b) and b or f32(b)
      return arithfunc(a,b) -- if you're seeing this as an error message, you probably have used e.g. f32 + non-numeric type
    end
end
local floatMT = {
  __add = generic_arith(f32add),
  __sub = generic_arith(f32sub),
  __mul = generic_arith(f32mul),
  __div = generic_arith(f32div),
  
  __lt = generic_comp(f32lt),
  __le = generic_comp(f32le),
  __eq = generic_comp(f32eq),

  __tostring = function(self)
    return tostring(tonumber(self.a[0]))
  end
}

    
local float_sandwich_mt = ffi.metatype("float_sandwich_t", floatMT)
-- Test comparison functions

-- Equality (f32eq)
assert(0 ~= f32eq(f32(5), f32(5)), "f32eq: 5 == 5 should be true")
assert(0 == f32eq(f32(5), f32(5.1)), "f32eq: 5 != 5.1 should be false")
assert(0 ~= f32eq(f32(0), f32(0)), "f32eq: 0 == 0 should be true")
assert(0 ~= f32eq(f32(-3.5), f32(-3.5)), "f32eq: -3.5 == -3.5 should be true")

-- Less than (f32lt)
assert(0 ~= f32lt(f32(3), f32(5)), "f32lt: 3 < 5 should be true")
assert(0 == f32lt(f32(5), f32(3)), "f32lt: 5 < 3 should be false")
assert(0 == f32lt(f32(4), f32(4)), "f32lt: 4 < 4 should be false")

-- Less than or equal (f32le)
assert(0 ~= f32le(f32(3), f32(5)), "f32le: 3 <= 5 should be true")
assert(0 ~= f32le(f32(5), f32(5)), "f32le: 5 <= 5 should be true")
assert(0 == f32le(f32(5), f32(3)), "f32le: 5 <= 3 should be false")


-- Test arithmetic functions

-- Addition (f32add)
assert(0 ~= f32eq(f32add(f32(2), f32(3)), f32(5)), "f32add: 2 + 3 = 5")
assert(0 ~= f32eq(f32add(f32(-1), f32(2)), f32(1)), "f32add: -1 + 2 = 1")
assert(0 ~= f32eq(f32add(f32(0), f32(5)), f32(5)), "f32add: 0 + 5 = 5")

-- Subtraction (f32sub)
assert(0 ~= f32eq(f32sub(f32(5), f32(3)), f32(2)), "f32sub: 5 - 3 = 2")
assert(0 ~= f32eq(f32sub(f32(3), f32(5)), f32(-2)), "f32sub: 3 - 5 = -2")
assert(0 ~= f32eq(f32sub(f32(4), f32(4)), f32(0)), "f32sub: 4 - 4 = 0")

-- Multiplication (f32mul)
assert(0 ~= f32eq(f32mul(f32(2), f32(3)), f32(6)), "f32mul: 2 * 3 = 6")
assert(0 ~= f32eq(f32mul(f32(-2), f32(3)), f32(-6)), "f32mul: -2 * 3 = -6")
assert(0 ~= f32eq(f32mul(f32(0), f32(5)), f32(0)), "f32mul: 0 * 5 = 0")

-- Division (f32div)
assert(0 ~= f32eq(f32div(f32(6), f32(3)), f32(2)), "f32div: 6 / 3 = 2")
assert(0 ~= f32eq(f32div(f32(1), f32(2)), f32(0.5)), "f32div: 1 / 2 = 0.5")
assert(0 ~= f32eq(f32div(f32(-4), f32(2)), f32(-2)), "f32div: -4 / 2 = -2")
assert(0 ~= f32eq(f32div(f32(5), f32(1)), f32(5)), "f32div: 5 / 1 = 5")

-- Edge case: Adding numbers resulting in zero
assert(0 ~= f32eq(f32add(f32(5), f32(-5)), f32(0)), "f32add: 5 + (-5) = 0")

-- Edge case: Division by one
assert(0 ~= f32eq(f32div(f32(7.5), f32(1)), f32(7.5)), "f32div: 7.5 / 1 = 7.5")

-- Test comparison operators

-- Equality (==)
assert(f32(5) == f32(5), "5 == 5 (f32) should be true")
assert(not (f32(5) == f32(5.1)), "5 != 5.1 (f32) should be false")
assert(f32(0) == f32(0), "0 == 0 (f32) should be true")
assert(f32(-3.5) == f32(-3.5), "-3.5 == -3.5 (f32) should be true")

-- Less than (<)
assert(f32(3) < f32(5), "3 < 5 (f32) should be true")
assert(not (f32(5) < f32(3)), "5 < 3 (f32) should be false")
assert(not (f32(4) < f32(4)), "4 < 4 (f32) should be false")

-- Less than or equal (<=)
assert(f32(3) <= f32(5), "3 <= 5 (f32) should be true")
assert(f32(5) <= f32(5), "5 <= 5 (f32) should be true")
assert(not (f32(5) <= f32(3)), "5 <= 3 (f32) should be false")

-- Test arithmetic operators

-- Addition (+)
assert(f32(2) + f32(3) == f32(5), "2 + 3 should equal 5")
assert(f32(-1) + f32(2) == f32(1), "-1 + 2 should equal 1")
assert(f32(0) + f32(5) == f32(5), "0 + 5 should equal 5")

-- Subtraction (-)
assert(f32(5) - f32(3) == f32(2), "5 - 3 should equal 2")
assert(f32(3) - f32(5) == f32(-2), "3 - 5 should equal -2")
assert(f32(4) - f32(4) == f32(0), "4 - 4 should equal 0")

-- Multiplication (*)
assert(f32(2) * f32(3) == f32(6), "2 * 3 should equal 6")
assert(f32(-2) * f32(3) == f32(-6), "-2 * 3 should equal -6")
assert(f32(0) * f32(5) == f32(0), "0 * 5 should equal 0")

-- Division (/)
assert(f32(6) / f32(3) == f32(2), "6 / 3 should equal 2")
assert(f32(1) / f32(2) == f32(0.5), "1 / 2 should equal 0.5")
assert(f32(-4) / f32(2) == f32(-2), "-4 / 2 should equal -2")
assert(f32(5) / f32(1) == f32(5), "5 / 1 should equal 5")

-- Edge cases
assert(f32(5) + f32(-5) == f32(0), "5 + (-5) should equal 0")
assert(f32(7.5) / f32(1) == f32(7.5), "7.5 / 1 should preserve value")

-- functionality assertions
assert(f32(f32(4.0)) == 4.0, "Constructor f32(float_sandwich_t) doesnt work")

return f32
