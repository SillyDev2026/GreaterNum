# GreaterNum

<p align="center">
  <strong>A fast layered-number library for Roblox/Luau.</strong><br>
  Built for clicker games, simulators, incremental economies, prestige systems, and any project that needs numbers far beyond normal Lua limits.
</p>

<p align="center">
  <img alt="Version" src="https://img.shields.io/badge/version-1.1.0-blue">
  <img alt="Luau" src="https://img.shields.io/badge/language-Luau-blueviolet">
  <img alt="Roblox" src="https://img.shields.io/badge/platform-Roblox-00A2FF">
  <img alt="Buffer Size" src="https://img.shields.io/badge/value%20size-17%20bytes-green">
</p>

GreaterNum stores each value in a compact **17-byte Roblox buffer** using a **Sign + Layer + Exponent** representation. It is designed to stay easy to use at the gameplay level while still exposing lower-allocation APIs for hot loops.

```lua
local GreaterNum = require(path.to.GreaterNum)

local coins = GreaterNum.fromNumber(1_250_000)
local reward = GreaterNum.fromScientific(5, 12)

coins = GreaterNum.add(coins, reward)

print(GreaterNum.toSuffix(coins))
```

---

## Features

- Numbers far beyond native floating-point range
- Compact 17-byte buffer representation
- Normal arithmetic and in-place arithmetic
- Fast buffer-only API for hot paths
- Scientific, engineering, suffix, layered, and custom formatting
- Parsing from strings and scientific notation
- Comparison and validation helpers
- Economy helpers for geometric prices and affordability
- Percent, interpolation, remapping, clamping, and scaling helpers
- Statistics and combinatorics
- Factorial, gamma, logarithms, roots, powers, and tetration
- Trigonometric and hyperbolic helpers for native-range inputs
- Table, raw-buffer, and binary-string serialization
- Built-in microbenchmark utility
- `--!native` and `--!optimize 2`

---

## Installation

Create a `ModuleScript` named `GreaterNum` and paste the module into it.

A common layout is:

```text
ReplicatedStorage
└── Packages
    └── GreaterNum
```

Then require it:

```lua
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GreaterNum = require(ReplicatedStorage.Packages.GreaterNum)
```

GreaterNum v1.1 reports its version and representation directly:

```lua
print(GreaterNum.version())
print(GreaterNum.bytes())
print(GreaterNum.REPRESENTATION)
```

Expected metadata:

```text
1.1.0
17
Sign + Layer + Exponent
```

---

# Five-Minute Quick Start

## Create values

```lua
local GreaterNum = require(path.to.GreaterNum)

local a = GreaterNum.fromNumber(500)
local b = GreaterNum.fromScientific(2.5, 12)
local c = GreaterNum.fromString("1e100")
local d = GreaterNum.fromString("L2:50")

print(GreaterNum.toString(a))
print(GreaterNum.toScientific(b))
print(GreaterNum.toLayered(c))
print(GreaterNum.toLayered(d))
```

You can also create a value directly from its raw representation:

```lua
local value = GreaterNum.new(1, 1, 500)
```

The three parts are:

```text
sign, layer, exponent
```

Direct construction is useful when you understand GreaterNum's representation. For normal game code, `fromNumber`, `fromScientific`, and `fromString` are usually easier to read.

---

## Arithmetic

```lua
local a = GreaterNum.fromNumber(1000)
local b = GreaterNum.fromNumber(250)

local added = GreaterNum.add(a, b)
local subtracted = GreaterNum.sub(a, b)
local multiplied = GreaterNum.mul(a, b)
local divided = GreaterNum.div(a, b)
local powered = GreaterNum.pow(a, 2)

print(GreaterNum.toString(added))
print(GreaterNum.toString(subtracted))
print(GreaterNum.toString(multiplied))
print(GreaterNum.toString(divided))
print(GreaterNum.toScientific(powered))
```

Most normal arithmetic functions accept GreaterNum buffers and also support native numbers through the regular API.

---

## Compare values

Do not compare GreaterNum buffers with normal numeric operators. Use the comparison API:

```lua
local coins = GreaterNum.fromNumber(5000)
local price = GreaterNum.fromNumber(2500)

if GreaterNum.gte(coins, price) then
    print("Player can afford the item")
end
```

Available helpers:

```lua
GreaterNum.eq(a, b)
GreaterNum.ne(a, b)
GreaterNum.lt(a, b)
GreaterNum.lte(a, b)
GreaterNum.gt(a, b)
GreaterNum.gte(a, b)
GreaterNum.compare(a, b)
```

`compare` returns:

```text
-1  a < b
 0  a == b
 1  a > b
```

---

## Format values

```lua
local value = GreaterNum.fromScientific(1.2345, 15)

print(GreaterNum.toString(value, 2))
print(GreaterNum.toSuffix(value, 2))
print(GreaterNum.toScientific(value, 2))
print(GreaterNum.toEngineer(value, 2))
print(GreaterNum.toLayered(value, 2))
```

For full control, use `format`:

```lua
local text = GreaterNum.format(value, {
    notation = "suffix",
    digits = 2,
    trim = true,
    separators = true,
    forceSign = false,
})

print(text)
```

Supported notation names include:

| Notation | Example purpose |
| --- | --- |
| `auto` | General game UI |
| `suffix` / `short` | `K`, `M`, `B`, `T`, ... |
| `scientific` / `sci` | Scientific notation |
| `engineering` / `eng` | Exponents in multiples of 3 |
| `layer` / `raw` | GreaterNum layer notation |
| `full` | Full native number when possible |

Custom text can also be supplied for zero, NaN, and infinity:

```lua
local text = GreaterNum.format(value, {
    zeroText = "Free",
    nanText = "Invalid",
    infinityText = "∞",
    negativeInfinityText = "-∞",
})
```

---

# Core API

## Constructors

```lua
GreaterNum.new(sign, layer, exponent)
GreaterNum.fromParts(sign, layer, exponent)
GreaterNum.createCheckless(sign, layer, exponent)
GreaterNum.fromNumber(number)
GreaterNum.fromScientific(mantissa, exponent)
GreaterNum.fromString(text)
GreaterNum.parse(text)
GreaterNum.fromTuple({sign, layer, exponent})
GreaterNum.zero()
GreaterNum.one()
GreaterNum.nan()
GreaterNum.infinity(sign?)
GreaterNum.clone(value)
GreaterNum.coerce(value)
```

### `createCheckless`

`createCheckless` writes the raw representation without normalizing it.

```lua
local raw = GreaterNum.createCheckless(1, 1, 100)
```

Use it only when the input is already valid and normalized. For user input and normal gameplay logic, prefer `new` or one of the conversion functions.

---

## Raw value access

```lua
local value = GreaterNum.fromNumber(12345)

local sign, layer, exponent = GreaterNum.tuple(value)
local raw = GreaterNum.raw(value)

print(sign, layer, exponent)
print(raw.sign, raw.layer, raw.exponent)
```

Individual getters are also available:

```lua
GreaterNum.sign(value)
GreaterNum.layer(value)
GreaterNum.exponent(value)
```

---

## Arithmetic

```lua
GreaterNum.add(a, b)
GreaterNum.sub(a, b)
GreaterNum.mul(a, b)
GreaterNum.div(a, b)
GreaterNum.pow(a, b)
GreaterNum.mod(a, b)
GreaterNum.intdiv(a, b)
GreaterNum.neg(value)
GreaterNum.abs(value)
GreaterNum.recip(value)
```

Power/root helpers:

```lua
GreaterNum.root(value, n)
GreaterNum.sqrt(value)
GreaterNum.cbrt(value)
GreaterNum.sqr(value)
GreaterNum.cube(value)
GreaterNum.pow2(value)
GreaterNum.pow10(value)
GreaterNum.exp(value)
```

---

## In-place arithmetic

The `*eq` family mutates the first buffer instead of allocating a replacement buffer.

```lua
local coins = GreaterNum.fromNumber(100)

GreaterNum.addeq(coins, 50)
GreaterNum.muleq(coins, 2)
GreaterNum.subeq(coins, 25)

print(GreaterNum.toString(coins))
```

Available mutating helpers include:

```lua
GreaterNum.addeq(value, other)
GreaterNum.subeq(value, other)
GreaterNum.muleq(value, other)
GreaterNum.diveq(value, other)
GreaterNum.poweq(value, other)
GreaterNum.modeq(value, other)
GreaterNum.recipeq(value)
GreaterNum.rooteq(value, root)
GreaterNum.sqrteq(value)
GreaterNum.flooreq(value)
GreaterNum.ceileq(value)
GreaterNum.roundeq(value)
GreaterNum.roundtoeq(value, step)
GreaterNum.negeq(value)
GreaterNum.abseq(value)
```

### Important: mutation

This:

```lua
GreaterNum.addeq(coins, reward)
```

changes `coins` itself.

This:

```lua
local newCoins = GreaterNum.add(coins, reward)
```

returns a new GreaterNum buffer and leaves `coins` unchanged.

That distinction is useful when choosing between simple code and lower-allocation code.

---

# Fast API

`GreaterNum.Fast` is intended for code paths where both operands are already valid GreaterNum buffers.

```lua
local Fast = GreaterNum.Fast

local a = Fast.fromNumber(100)
local b = Fast.fromNumber(25)
local result = Fast.add(a, b)
```

Use the normal API unless you have a reason to optimize a hot loop. The normal API is more flexible and easier to use safely.

## Fast constructors

```lua
Fast.alloc()
Fast.zero()
Fast.one()
Fast.new(sign, layer, exponent)
Fast.checkless(sign, layer, exponent)
Fast.fromNumber(number)
Fast.fromNumberInto(out, number)
Fast.copyInto(out, source)
```

## Fast arithmetic

```lua
Fast.add(a, b)
Fast.sub(a, b)
Fast.mul(a, b)
Fast.div(a, b)
Fast.pow(a, b)
```

## Fast comparisons

```lua
Fast.eq(a, b)
Fast.ne(a, b)
Fast.lt(a, b)
Fast.lte(a, b)
Fast.gt(a, b)
Fast.gte(a, b)
Fast.compare(a, b)
Fast.isZero(value)
Fast.isOne(value)
```

---

## Reuse output buffers with `*Into`

For loops that run very frequently, reuse an output buffer:

```lua
local Fast = GreaterNum.Fast

local a = Fast.fromNumber(10)
local b = Fast.fromNumber(20)
local out = Fast.alloc()

for _ = 1, 1000 do
    Fast.addInto(out, a, b)
end
```

Available functions:

```lua
Fast.addInto(out, a, b)
Fast.subInto(out, a, b)
Fast.mulInto(out, a, b)
Fast.divInto(out, a, b)
Fast.powInto(out, a, b)
Fast.powIntoWithScratch(out, scratch, a, b)
```

`powIntoWithScratch` requires `out` and `scratch` to be different buffers.

You can use the same pattern through the normal API when operands may be native numbers:

```lua
local out = GreaterNum.zero()

GreaterNum.addInto(out, 100, 250)
GreaterNum.mulInto(out, out, 10)
```

---

## Fast in-place mutation

```lua
local Fast = GreaterNum.Fast
local coins = Fast.fromNumber(100)
local reward = Fast.fromNumber(25)

Fast.addeq(coins, reward)
Fast.muleq(coins, Fast.fromNumber(2))
```

Available functions:

```lua
Fast.addeq(a, b)
Fast.subeq(a, b)
Fast.muleq(a, b)
Fast.diveq(a, b)
Fast.poweq(a, b)
```

---

# Economy Examples

## Clicker / simulator currency

```lua
local GreaterNum = require(path.to.GreaterNum)

local Data = {
    Coins = GreaterNum.zero(),
    ClickPower = GreaterNum.fromNumber(1),
}

local function click()
    GreaterNum.addeq(Data.Coins, Data.ClickPower)
end

local function buyClickUpgrade(cost, multiplier)
    if not GreaterNum.canAfford(Data.Coins, cost) then
        return false
    end

    GreaterNum.subeq(Data.Coins, cost)
    GreaterNum.muleq(Data.ClickPower, multiplier)
    return true
end

click()

local bought = buyClickUpgrade(
    GreaterNum.fromNumber(1),
    GreaterNum.fromNumber(2)
)

print("Bought:", bought)
print("Coins:", GreaterNum.toSuffix(Data.Coins))
print("Power:", GreaterNum.toSuffix(Data.ClickPower))
```

---

## Geometric upgrade cost

A common simulator price model is:

```text
price = base × multiplier ^ owned
```

GreaterNum includes helpers for this pattern.

```lua
local basePrice = GreaterNum.fromNumber(100)
local multiplier = GreaterNum.fromNumber(1.15)
local owned = 25
local buying = 10

local totalCost = GreaterNum.geometricCost(
    basePrice,
    multiplier,
    owned,
    buying
)

print(GreaterNum.toSuffix(totalCost))
```

Find the maximum affordable amount:

```lua
local amount = GreaterNum.affordGeometric(
    playerCoins,
    basePrice,
    multiplier,
    owned,
    1_000_000
)

print("Can buy:", amount)
```

This is useful for `Buy Max` buttons because the helper uses a search instead of checking every amount one-by-one.

---

## Percentage bonuses

```lua
local baseDamage = GreaterNum.fromNumber(1000)

local buffed = GreaterNum.addPercent(baseDamage, 25)
local nerfed = GreaterNum.subPercent(baseDamage, 10)

print(GreaterNum.toString(buffed))
print(GreaterNum.toString(nerfed))
```

More helpers:

```lua
GreaterNum.percent(value, amount)
GreaterNum.percentOf(part, total)
GreaterNum.percentChange(oldValue, newValue)
```

Example:

```lua
local gain = GreaterNum.percentChange(100, 150)
print(GreaterNum.format(gain, { digits = 2 }))
```

---

## Softcaps and scaling

```lua
local value = GreaterNum.fromScientific(1, 20)
local start = GreaterNum.fromScientific(1, 10)

local capped = GreaterNum.softcap(value, start, 0.5)
print(GreaterNum.toScientific(capped))
```

Related helpers:

```lua
GreaterNum.softcap(value, start, power)
GreaterNum.scale(value, start, power)
GreaterNum.unscale(value, start, power)
```

---

# Formatting Examples

## Currency

```lua
local money = GreaterNum.fromNumber(1250000)
print(GreaterNum.formatCurrency(money, "$", {
    notation = "suffix",
    digits = 2,
}))
```

## Rate

```lua
local income = GreaterNum.fromScientific(5, 9)
print(GreaterNum.formatRate(income, "s", 2))
```

## Percent

`formatPercent` treats the input as a ratio:

```lua
local chance = GreaterNum.fromNumber(0.125)
print(GreaterNum.formatPercent(chance, 2))
```

---

# Parsing and Validation

## Parse strings

```lua
local a = GreaterNum.fromString("1500")
local b = GreaterNum.fromString("1e100")
local c = GreaterNum.fromString("L2:500")
local d = GreaterNum.fromString("2;500")
```

Special values are supported:

```lua
GreaterNum.fromString("NaN")
GreaterNum.fromString("Infinity")
GreaterNum.fromString("-Infinity")
```

For user input, use the non-throwing helpers:

```lua
local value, err = GreaterNum.tryFromString(text)

if not value then
    warn(err)
    return
end

print(GreaterNum.toString(value))
```

Other safe conversion helpers:

```lua
GreaterNum.tryCoerce(value)
GreaterNum.tryToNumber(value)
GreaterNum.tryDecode(data)
```

---

## Coercion

`coerce` accepts several convenient forms:

```lua
GreaterNum.coerce(100)
GreaterNum.coerce("1e50")
GreaterNum.coerce(existingBuffer)
GreaterNum.coerce({1, 1, 100})
GreaterNum.coerce({
    sign = 1,
    layer = 1,
    exponent = 100,
})
```

---

## Validation

```lua
GreaterNum.isGreaterNum(value)
GreaterNum.isValid(value)
GreaterNum.assertValid(value, "Coins")
GreaterNum.isFinite(value)
GreaterNum.isNaN(value)
GreaterNum.isInf(value)
GreaterNum.isNumber(value)
GreaterNum.isZero(value)
GreaterNum.isOne(value)
GreaterNum.isPositive(value)
GreaterNum.isNegative(value)
GreaterNum.isInteger(value)
GreaterNum.isEven(value)
GreaterNum.isOdd(value)
```

---

# Serialization

GreaterNum values are buffers internally, but the module includes several serialization formats depending on what your system needs.

## Table representation

```lua
local value = GreaterNum.fromScientific(2.5, 100)
local saved = GreaterNum.serialize(value)

-- saved = {sign, layer, exponent}

local restored = GreaterNum.deserialize(saved)
```

This is the easiest representation when saving inside a larger table.

### DataStore-style example

```lua
local playerData = {
    Coins = GreaterNum.serialize(coins),
    Gems = GreaterNum.serialize(gems),
}
```

When loading:

```lua
local coins = GreaterNum.deserialize(playerData.Coins)
local gems = GreaterNum.deserialize(playerData.Gems)
```

---

## Buffer representation

```lua
local packed = GreaterNum.serializeBuffer(value)
local restored = GreaterNum.deserializeBuffer(packed)
```

`deserializeBuffer` validates that the input is a 17-byte buffer.

---

## Binary string representation

```lua
local encoded = GreaterNum.encode(value)
local restored = GreaterNum.decode(encoded)
```

For untrusted input:

```lua
local restored, err = GreaterNum.tryDecode(encoded)

if not restored then
    warn(err)
end
```

---

# Rounding and Range Helpers

```lua
GreaterNum.floor(value)
GreaterNum.ceil(value)
GreaterNum.round(value)
GreaterNum.trunc(value)
GreaterNum.roundTo(value, step)
GreaterNum.floorTo(value, step)
GreaterNum.ceilTo(value, step)
GreaterNum.quantize(value, step)
GreaterNum.clamp(value, low, high)
GreaterNum.clamp01(value)
GreaterNum.inRange(value, low, high, inclusive?)
GreaterNum.between(value, low, high, inclusive?)
```

Example:

```lua
local value = GreaterNum.fromNumber(127.6)

print(GreaterNum.toString(GreaterNum.floorTo(value, 10)))
print(GreaterNum.toString(GreaterNum.ceilTo(value, 10)))
print(GreaterNum.toString(GreaterNum.roundTo(value, 10)))
```

---

# Interpolation and Movement

```lua
local a = GreaterNum.fromNumber(0)
local b = GreaterNum.fromScientific(1, 50)

local middle = GreaterNum.lerp(a, b, 0.5)
local clamped = GreaterNum.lerpClamped(a, b, 1.5)
```

Additional helpers:

```lua
GreaterNum.inverseLerp(a, b, value)
GreaterNum.remap(value, inMin, inMax, outMin, outMax)
GreaterNum.moveTowards(current, target, maxDelta)
GreaterNum.smoothstep(edge0, edge1, value)
GreaterNum.smootherstep(edge0, edge1, value)
```

---

# Statistics

```lua
local values = {
    GreaterNum.fromNumber(10),
    GreaterNum.fromNumber(20),
    GreaterNum.fromNumber(30),
}

print(GreaterNum.toString(GreaterNum.sum(values)))
print(GreaterNum.toString(GreaterNum.product(values)))
print(GreaterNum.toString(GreaterNum.mean(values)))
print(GreaterNum.toString(GreaterNum.geometricMean(values)))
print(GreaterNum.toString(GreaterNum.harmonicMean(values)))
```

Weighted mean:

```lua
local average = GreaterNum.weightedMean(
    {10, 20, 30},
    {1, 2, 3}
)
```

For lower-allocation aggregation:

```lua
local out = GreaterNum.zero()

GreaterNum.sumInto(out, values)
print(GreaterNum.toString(out))

GreaterNum.productInto(out, values)
print(GreaterNum.toString(out))
```

---

# Advanced Math

## Logarithms

```lua
GreaterNum.log10(value)
GreaterNum.log2(value)
GreaterNum.ln(value)
GreaterNum.log(value, base)
GreaterNum.abslog10(value)
```

## Factorial and gamma

```lua
local factorial = GreaterNum.factorial(100)
local gamma = GreaterNum.gamma(10)
local logGamma = GreaterNum.logGamma(10)
```

Aliases:

```lua
GreaterNum.fact(value)
```

## Combinatorics

```lua
local permutations = GreaterNum.permutation(100, 10)
local combinations = GreaterNum.combination(100, 10)
```

Aliases:

```lua
GreaterNum.perm(n, r)
GreaterNum.choose(n, r)
GreaterNum.comb(n, r)
```

## Tetration

```lua
local value = GreaterNum.tetrate(10, 4)
print(GreaterNum.toLayered(value))
```

Alias:

```lua
GreaterNum.tetr(base, height)
```

---

# Trigonometry

GreaterNum exposes familiar trigonometric helpers:

```lua
GreaterNum.sin(value)
GreaterNum.cos(value)
GreaterNum.tan(value)
GreaterNum.asin(value)
GreaterNum.acos(value)
GreaterNum.atan(value)
GreaterNum.atan2(y, x)

GreaterNum.sinh(value)
GreaterNum.cosh(value)
GreaterNum.tanh(value)

GreaterNum.rad(value)
GreaterNum.deg(value)
```

These helpers convert through native numeric math, so they are intended for values that fit within normal Lua numeric range.

---

# Utility Helpers

```lua
GreaterNum.max(...)
GreaterNum.min(...)
GreaterNum.maxabs(...)
GreaterNum.minabs(...)
GreaterNum.distance(a, b)
GreaterNum.approxEq(a, b, relativeTolerance?, absoluteTolerance?)
GreaterNum.copySign(magnitude, signSource)
GreaterNum.signum(value)
GreaterNum.random(a, b, rng?)
GreaterNum.hypot(a, b)
```

---

# Complete Common API Reference

| Category | Functions |
| --- | --- |
| Create | `new`, `fromNumber`, `fromScientific`, `fromString`, `fromTuple`, `zero`, `one`, `nan`, `infinity`, `clone`, `coerce` |
| Arithmetic | `add`, `sub`, `mul`, `div`, `pow`, `mod`, `intdiv`, `neg`, `abs`, `recip` |
| Roots/Powers | `root`, `sqrt`, `cbrt`, `sqr`, `cube`, `pow2`, `pow10`, `exp`, `tetrate` |
| Comparison | `compare`, `eq`, `ne`, `lt`, `lte`, `gt`, `gte`, `approxEq` |
| Rounding | `floor`, `ceil`, `round`, `trunc`, `roundTo`, `floorTo`, `ceilTo`, `quantize` |
| State | `isZero`, `isOne`, `isPositive`, `isNegative`, `isNaN`, `isInf`, `isFinite`, `isNumber`, `isInteger`, `isEven`, `isOdd` |
| Formatting | `format`, `toString`, `toSuffix`, `toScientific`, `toEngineer`, `toLayered`, `formatCurrency`, `formatPercent`, `formatRate` |
| Economy | `geometricSum`, `geometricCost`, `affordGeometric`, `canAfford`, `softcap`, `scale`, `unscale`, `percent`, `addPercent`, `subPercent`, `percentOf`, `percentChange` |
| Interpolation | `lerp`, `lerpClamped`, `inverseLerp`, `remap`, `moveTowards`, `smoothstep`, `smootherstep` |
| Aggregation | `sum`, `sumInto`, `product`, `productInto`, `mean`, `weightedMean`, `geometricMean`, `harmonicMean` |
| Advanced math | `log10`, `log2`, `ln`, `log`, `factorial`, `gamma`, `logGamma`, `permutation`, `combination`, `hypot` |
| Serialization | `serialize`, `deserialize`, `serializeBuffer`, `deserializeBuffer`, `encode`, `decode`, `tryDecode` |
| Inspection | `tuple`, `raw`, `sign`, `layer`, `exponent`, `toNumber`, `tryToNumber`, `isGreaterNum`, `isValid`, `assertValid`, `bytes`, `version` |

---

# Performance Guide

GreaterNum provides three main styles of arithmetic.

## 1. Normal API

Best default for normal gameplay code:

```lua
coins = GreaterNum.add(coins, reward)
```

Advantages:

- Easy to read
- Accepts flexible operands
- Safest default

Tradeoff:

- Returning a result normally allocates a new 17-byte buffer

---

## 2. In-place API

Useful for long-lived values such as player currency:

```lua
GreaterNum.addeq(coins, reward)
```

Advantages:

- Reuses the existing buffer
- Avoids replacing the value reference
- Good fit for repeated currency updates

---

## 3. Fast + `Into`

Useful for very hot loops where operands are already GreaterNum buffers:

```lua
local Fast = GreaterNum.Fast
local out = Fast.alloc()

Fast.mulInto(out, a, b)
```

Advantages:

- Buffer-only hot path
- Reusable result buffers
- Lower allocation pressure

Tradeoff:

- Less forgiving
- Inputs should already be valid GreaterNum buffers

Do not rewrite every piece of game logic around `Fast` just because it exists. Use it where profiling shows the extra control is useful.

---

# Benchmark

GreaterNum includes a small built-in microbenchmark:

```lua
local results = GreaterNum.benchmark(100000)

print("GreaterNum", results.version)
print("Iterations", results.iterations)
print("Add", results.add, "ns/op")
print("Fast Add", results.fastAdd, "ns/op")
print("Fast Compare", results.fastCompare, "ns/op")
print("Into Add", results.intoAdd, "ns/op")
```

The benchmark currently measures operations including:

```text
add
sub
mul
div
pow
log
compare
addeqNumber
fastAdd
fastSub
fastMul
fastDiv
fastPow
fastCompare
intoAdd
intoSub
intoMul
intoDiv
intoPow
scratchPow
```

Benchmark results depend on device, Studio/runtime conditions, iteration count, and what else Roblox is doing. Use the benchmark for relative testing on the same environment rather than treating one number as a universal result.

---

# Practical Player Data Pattern

A clean pattern is to keep GreaterNum buffers in the live session and convert them only at your persistence boundary.

```lua
local GreaterNum = require(path.to.GreaterNum)

local Session = {
    Coins = GreaterNum.zero(),
    Gems = GreaterNum.zero(),
}

local function addCoins(amount)
    GreaterNum.addeq(Session.Coins, amount)
end

local function buildSaveData()
    return {
        Coins = GreaterNum.serialize(Session.Coins),
        Gems = GreaterNum.serialize(Session.Gems),
    }
end

local function loadSaveData(data)
    Session.Coins = GreaterNum.deserialize(data.Coins)
    Session.Gems = GreaterNum.deserialize(data.Gems)
end
```

That keeps arithmetic code simple while making the saved representation explicit.

---

# Leaderstats Example

Roblox `NumberValue` cannot represent the full GreaterNum range, so a common approach is to display a formatted string.

```lua
local Players = game:GetService("Players")
local GreaterNum = require(path.to.GreaterNum)

Players.PlayerAdded:Connect(function(player)
    local leaderstats = Instance.new("Folder")
    leaderstats.Name = "leaderstats"
    leaderstats.Parent = player

    local coinsLabel = Instance.new("StringValue")
    coinsLabel.Name = "Coins"
    coinsLabel.Parent = leaderstats

    local coins = GreaterNum.fromScientific(1, 100)
    coinsLabel.Value = GreaterNum.toSuffix(coins, 2)
end)
```

Keep the real GreaterNum value in your data/session system. Treat the `StringValue` as presentation only.

---

# Handling Player Input

Do not call `fromString` directly on arbitrary text unless you want invalid input to throw.

Use:

```lua
local value, err = GreaterNum.tryFromString(playerText)

if not value then
    warn("Invalid GreaterNum:", err)
    return
end
```

The same idea applies to binary data:

```lua
local value, err = GreaterNum.tryDecode(encoded)
```

---

# Native Number Conversion

```lua
local native = GreaterNum.toNumber(value)
```

GreaterNum values can be much larger than a native number. If the value cannot fit, `toNumber` may resolve to infinity.

For code that needs a finite native value, use:

```lua
local native, err = GreaterNum.tryToNumber(value)

if native == nil then
    warn(err)
    return
end
```

---

# Special Values

## Zero

```lua
local zero = GreaterNum.zero()
print(GreaterNum.isZero(zero))
```

## Infinity

```lua
local positive = GreaterNum.infinity()
local negative = GreaterNum.infinity(-1)
```

## NaN

```lua
local invalid = GreaterNum.nan()

if GreaterNum.isNaN(invalid) then
    warn("Invalid GreaterNum result")
end
```

Operations such as division by zero, invalid roots/powers, or invalid mathematical domains can produce NaN depending on the operation.

---

# v1.1 QoL Update

v1.1 is intentionally a compatibility-focused update. The underlying 17-byte representation remains unchanged.

Highlights include:

- `Fast.compare`
- `Fast.ne`
- `Fast.lte`
- `Fast.gte`
- `Fast.isZero`
- `Fast.isOne`
- `Fast.alloc`
- `Fast.zero`
- `Fast.one`
- `GreaterNum.ne`
- `GreaterNum.equals`
- `GreaterNum.sumInto`
- `GreaterNum.productInto`
- `GreaterNum.inRange` / `between`
- `GreaterNum.lerpClamped`
- `GreaterNum.moveTowards`
- `GreaterNum.addPercent`
- `GreaterNum.subPercent`
- `GreaterNum.percentOf`
- `GreaterNum.percentChange`
- `GreaterNum.canAfford`
- `GreaterNum.fromTuple`
- `GreaterNum.tryToNumber`
- `GreaterNum.tryDecode`
- Lower-overhead mutating arithmetic dispatch
- Lower-allocation absolute comparisons
- Scratch-buffer reuse in selected aggregation helpers
- Expanded benchmark coverage

Existing v1.0-style APIs remain available, making v1.1 suitable as a drop-in update for code that already uses GreaterNum's public API.

---

# Recommended Usage

For most games:

```lua
GreaterNum.fromNumber(...)
GreaterNum.add(...)
GreaterNum.mul(...)
GreaterNum.gte(...)
GreaterNum.toSuffix(...)
```

For persistent live values that update frequently:

```lua
GreaterNum.addeq(...)
GreaterNum.muleq(...)
```

For carefully optimized hot loops:

```lua
GreaterNum.Fast.addInto(...)
GreaterNum.Fast.mulInto(...)
GreaterNum.Fast.compare(...)
```

For saving:

```lua
GreaterNum.serialize(...)
GreaterNum.deserialize(...)
```

For player-entered strings:

```lua
GreaterNum.tryFromString(...)
```

---

# Common Mistakes

## Comparing buffers directly

Avoid:

```lua
if coins >= price then
end
```

Use:

```lua
if GreaterNum.gte(coins, price) then
end
```

---

## Converting huge values to native numbers unnecessarily

Avoid using `toNumber` just to compare or perform GreaterNum arithmetic.

Instead of:

```lua
if GreaterNum.toNumber(coins) >= GreaterNum.toNumber(price) then
end
```

use:

```lua
if GreaterNum.gte(coins, price) then
end
```

---

## Using `Fast` with arbitrary input

Avoid:

```lua
GreaterNum.Fast.add(bufferValue, 100)
```

`Fast` arithmetic expects GreaterNum buffers.

Use either:

```lua
GreaterNum.add(bufferValue, 100)
```

or preconvert:

```lua
local hundred = GreaterNum.Fast.fromNumber(100)
GreaterNum.Fast.add(bufferValue, hundred)
```

---

## Accidentally mutating shared data

Remember that `addeq`, `muleq`, and other `*eq` methods mutate their first buffer.

If you need an independent value:

```lua
local copied = GreaterNum.clone(original)
GreaterNum.addeq(copied, 10)
```

---

# FAQ

### Why not just use normal Lua numbers?

Normal numbers are excellent for ordinary gameplay values, but incremental and simulator economies can quickly exceed native numeric range. GreaterNum switches to a layered representation so values can continue growing.

### Why is a GreaterNum a buffer?

The module uses a compact fixed-size representation. Each value occupies 17 bytes for Sign + Layer + Exponent data.

### Should I always use `GreaterNum.Fast`?

No. Start with the normal API. Use `Fast` and `*Into` when you have a real hot path and already know your operands are GreaterNum buffers.

### Should I use `addeq` for player currency?

It is a good fit when you intentionally keep one live currency buffer and update it repeatedly. Use normal `add` when immutable-style code is clearer for your system.

### Can GreaterNum format values for UI?

Yes. `toSuffix`, `toScientific`, `toEngineer`, `toLayered`, and `format` cover the most common display styles.

### Can I save GreaterNum values?

Yes. The module exposes table, buffer, and binary-string serialization helpers. `serialize` / `deserialize` are convenient when the value is part of a larger saved table.

### Are benchmark numbers universal?

No. Compare benchmark results on the same machine/runtime and under similar conditions.

---

# Version

```lua
GreaterNum.VERSION
GreaterNum.version()
```

Current version:

```text
1.1
```

Buffer size:

```text
17 bytes
```

Representation:

```text
Sign + Layer + Exponent
```

---

## Minimal Example

```lua
local GreaterNum = require(path.to.GreaterNum)

local coins = GreaterNum.fromNumber(100)
local reward = GreaterNum.fromScientific(5, 6)

GreaterNum.addeq(coins, reward)

if GreaterNum.gte(coins, 1_000_000) then
    print("Millionaire")
end

print(GreaterNum.toSuffix(coins, 2))
```

GreaterNum is designed so you can start with the simple API, then move specific hot paths to buffer reuse and `GreaterNum.Fast` without rewriting the rest of your game.
