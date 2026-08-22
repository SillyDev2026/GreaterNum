# GreaterNum v1

v1 is the QOL, handler, math, and correctness update for the v1.4 optimized core.

The representation stays unchanged:

```text
17 bytes
sign     i8
layer    f64
exponent f64
```

## Main fixes

- Canonical zero handling in `abs()` and `neg()`.
- Normal `addeq/subeq/muleq/diveq/poweq` no longer create a temporary GreaterNum buffer just because the second operand is a Lua number.
- Added `Fast.powIntoWithScratch()` for a reusable scratch buffer.
- Added buffer validation and safe coercion helpers.
- Added custom suffix-table support to `format()`.
- Added compatibility aliases and mutable QOL operations.
- Added more edge-case tests.

## Handler / conversion QOL

```lua
GreaterNum.isGreaterNum(value)
GreaterNum.isValid(value)
GreaterNum.assertValid(value)

GreaterNum.coerce(value)
GreaterNum.tryCoerce(value)
GreaterNum.tryFromString(text)

GreaterNum.parse(text)
GreaterNum.tuple(value)
GreaterNum.toBuffer(value)
```

`coerce` accepts:

```text
GreaterNum buffer
number
string
{sign, layer, exponent}
{Sign, Layer, Exponent}
```

## Fast API

```lua
local a = GreaterNum.fromNumber(100)
local b = GreaterNum.fromNumber(25)
local out = GreaterNum.zero()

GreaterNum.Fast.addInto(out, a, b)
GreaterNum.Fast.subInto(out, a, b)
GreaterNum.Fast.mulInto(out, a, b)
GreaterNum.Fast.divInto(out, a, b)
```

Reusable scratch power:

```lua
local out = GreaterNum.zero()
local scratch = GreaterNum.zero()

GreaterNum.Fast.powIntoWithScratch(
	out,
	scratch,
	base,
	exponent
)
```

## New predicates

```lua
GreaterNum.isOne(value)
GreaterNum.isInteger(value)
GreaterNum.isEven(value)
GreaterNum.isOdd(value)
GreaterNum.approxEq(a, b)
```

## New arithmetic / utility math

```lua
GreaterNum.sqr(x)
GreaterNum.cube(x)
GreaterNum.signum(x)
GreaterNum.copySign(value, signSource)
GreaterNum.distance(a, b)
GreaterNum.hypot(a, b)

GreaterNum.floorTo(value, step)
GreaterNum.ceilTo(value, step)
GreaterNum.quantize(value, step)

GreaterNum.clamp01(value)
GreaterNum.inverseLerp(a, b, value)
GreaterNum.remap(value, inMin, inMax, outMin, outMax)
GreaterNum.smoothstep(edge0, edge1, value)
GreaterNum.smootherstep(edge0, edge1, value)
```

## Statistics

```lua
GreaterNum.mean(values)
GreaterNum.weightedMean(values, weights)
GreaterNum.geometricMean(values)
GreaterNum.harmonicMean(values)
```

## Combinatorics

```lua
GreaterNum.factorial(n)
GreaterNum.gamma(n)
GreaterNum.logGamma(n)

GreaterNum.permutation(n, r)
GreaterNum.perm(n, r)

GreaterNum.combination(n, r)
GreaterNum.comb(n, r)
GreaterNum.choose(n, r)
```

## Trigonometry

For values representable as normal finite doubles:

```lua
GreaterNum.sin(x)
GreaterNum.cos(x)
GreaterNum.tan(x)

GreaterNum.asin(x)
GreaterNum.acos(x)
GreaterNum.atan(x)
GreaterNum.atan2(y, x)

GreaterNum.sinh(x)
GreaterNum.cosh(x)
GreaterNum.tanh(x)

GreaterNum.rad(degrees)
GreaterNum.deg(radians)
```

If a trig input cannot sensibly be converted to a native finite angle, the function returns GreaterNum NaN rather than pretending a huge layered angle has exact double precision.

## Formatting QOL

Existing:

```lua
GreaterNum.format(value, {
    notation = "suffix",
    digits = 2,
})
```

Custom suffixes:

```lua
GreaterNum.format(value, {
    notation = "suffix",
    digits = 2,
    suffixes = {
        "K",
        "M",
        "B",
        "T",
    },
})
```

New shortcuts:

```lua
GreaterNum.formatCurrency(value, "$", {
    notation = "suffix",
    digits = 2,
})

GreaterNum.formatPercent(0.125, 2)
GreaterNum.formatRate(value, "s", 2)
```

## Encoding

Table serialization:

```lua
local data = GreaterNum.serialize(value)
local restored = GreaterNum.deserialize(data)
```

17-byte binary string:

```lua
local data = GreaterNum.encode(value)
local restored = GreaterNum.decode(data)
```

## Mutable compatibility helpers

```lua
GreaterNum.modeq(value, other)
GreaterNum.rooteq(value, root)
GreaterNum.sqrteq(value)

GreaterNum.flooreq(value)
GreaterNum.ceileq(value)
GreaterNum.roundeq(value)
GreaterNum.roundtoeq(value, step)

GreaterNum.negeq(value)
GreaterNum.abseq(value)
GreaterNum.recipeq(value)
```

## Design rule

v1 adds functionality around the value rather than adding more fields to it.

```text
sign + layer + exponent
```

remains the entire stored number.
