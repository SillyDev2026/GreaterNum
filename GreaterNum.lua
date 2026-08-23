--!native
--!optimize 2

local GreaterNum = {}

local Fast = {}
GreaterNum.Fast = Fast

local VERSION = "1.1.0"
local SIZE = 17

local S = 0
local L = 1
local E = 9

local HIGH = 1e10
local LOW = 1e-10
local OOM_CUTOFF = 16
local LN10 = math.log(10)
local LOG10_2 = math.log10(2)
local LOG10_E = math.log10(math.exp(1))
local EULER = math.exp(1)

local bcreate = buffer.create
local breadi8 = buffer.readi8
local breadf64 = buffer.readf64
local bwritei8 = buffer.writei8
local bwritef64 = buffer.writef64
local bcopy = buffer.copy
local blen = buffer.len

local abs = math.abs
local floor = math.floor
local ceil = math.ceil
local round = math.round
local log10 = math.log10
local pow = math.pow
local sign = math.sign
local min = math.min
local max = math.max

local function alloc(): buffer
	return bcreate(SIZE)
end

local function setRaw(out: buffer, s: number, l: number, e: number): buffer
	bwritei8(out, S, s)
	bwritef64(out, L, l)
	bwritef64(out, E, e)
	return out
end

local function setZero(out: buffer): buffer
	bwritei8(out, S, 0)
	bwritef64(out, L, 0)
	bwritef64(out, E, 0)
	return out
end

local function setNaN(out: buffer): buffer
	bwritei8(out, S, 1)
	bwritef64(out, L, -1)
	bwritef64(out, E, 1)
	return out
end

local function setInf(out: buffer, s: number): buffer
	bwritei8(out, S, s < 0 and -1 or 1)
	bwritef64(out, L, math.huge)
	bwritef64(out, E, 1)
	return out
end

local function normalizeInto(out: buffer, s: number, l: number, e: number): buffer
	if s ~= s or l ~= l or e ~= e then
		return setNaN(out)
	end

	if s == 0 or (l == 0 and e == 0) then
		return setZero(out)
	end

	s = s < 0 and -1 or 1
	l = floor(l)

	if l < 0 then
		return setNaN(out)
	end

	if l == math.huge or abs(e) == math.huge then
		return setInf(out, s)
	end

	if l == 0 then
		if e < 0 then
			e = -e
			s = -s
		end

		if e <= LOW or e >= HIGH then
			return setRaw(out, s, 1, log10(e))
		end

		return setRaw(out, s, 0, e)
	end

	local ae = abs(e)

	if ae >= HIGH then
		return setRaw(out, s, l + 1, sign(e) * log10(ae))
	end

	if l == 1 and ae < 10 then
		return normalizeInto(out, s, 0, pow(10, e))
	end

	if ae < 1 then
		if l >= 3 then
			local inner = sign(e) * pow(10, ae)
			return normalizeInto(out, s, l - 2, sign(inner) * pow(10, abs(inner)))
		end

		return normalizeInto(out, s, 0, pow(10, sign(e) * pow(10, ae)))
	end

	if ae < 10 then
		return normalizeInto(out, s, l - 1, sign(e) * pow(10, ae))
	end

	return setRaw(out, s, l, e)
end

local function numberParts(n: number): (number, number, number)
	if n ~= n then
		return 1, -1, 1
	end

	if n == 0 then
		return 0, 0, 0
	end

	if n == math.huge or n == -math.huge then
		return n < 0 and -1 or 1, math.huge, 1
	end

	local s = n < 0 and -1 or 1
	n = abs(n)

	if n >= HIGH or n <= LOW then
		return s, 1, log10(n)
	end

	return s, 0, n
end

local function parts(v): (number, number, number)
	local t = type(v)

	if t == "buffer" then
		return breadi8(v, S), breadf64(v, L), breadf64(v, E)
	end

	if t == "number" then
		return numberParts(v)
	end

	error("GreaterNum: expected number or GreaterNum buffer")
end

local function rawCompare(s1: number, l1: number, e1: number, s2: number, l2: number, e2: number): number
	if s1 ~= s2 then
		return s1 < s2 and -1 or 1
	end

	if s1 == 0 then
		return 0
	end

	local l1s = e1 >= 0 and l1 or -l1
	local l2s = e2 >= 0 and l2 or -l2

	if l1s ~= l2s then
		local r = l1s < l2s and -1 or 1
		return s1 < 0 and -r or r
	end

	if e1 ~= e2 then
		local r = e1 < e2 and -1 or 1
		return s1 < 0 and -r or r
	end

	return 0
end

local function signedAddPartsInto(
	out: buffer,
	s1: number, l1: number, e1: number,
	s2: number, l2: number, e2: number
): buffer
	if s1 == 0 then
		return setRaw(out, s2, l2, e2)
	end

	if s2 == 0 then
		return setRaw(out, s1, l1, e1)
	end

	if s1 == -s2 and l1 == l2 and e1 == e2 then
		return setZero(out)
	end

	if l1 == 0 and l2 == 0 then
		local n = s1 * e1 + s2 * e2

		if n == 0 then
			return setZero(out)
		end

		local an = abs(n)
		local sn = n < 0 and -1 or 1

		if an >= HIGH or an <= LOW then
			return setRaw(out, sn, 1, log10(an))
		end

		return setRaw(out, sn, 0, an)
	end

	if l1 >= 2 or l2 >= 2 then
		local l1s = e1 >= 0 and l1 or -l1
		local l2s = e2 >= 0 and l2 or -l2

		if l1s > l2s or (l1s == l2s and e1 > e2) then
			return setRaw(out, s1, l1, e1)
		end

		return setRaw(out, s2, l2, e2)
	end

	if l1 == 1 and l2 == 0 then
		local logSmall = log10(e2)
		local d = e1 - logSmall

		if abs(d) >= OOM_CUTOFF then
			if d > 0 then
				return setRaw(out, s1, 1, e1)
			end
			return setRaw(out, s2, 0, e2)
		end

		local n = s2 + s1 * pow(10, d)

		if n == 0 then
			return setZero(out)
		end

		return normalizeInto(out, sign(n), 1, logSmall + log10(abs(n)))
	end

	if l1 == 0 and l2 == 1 then
		local logSmall = log10(e1)
		local d = e2 - logSmall

		if abs(d) >= OOM_CUTOFF then
			if d > 0 then
				return setRaw(out, s2, 1, e2)
			end
			return setRaw(out, s1, 0, e1)
		end

		local n = s1 + s2 * pow(10, d)

		if n == 0 then
			return setZero(out)
		end

		return normalizeInto(out, sign(n), 1, logSmall + log10(abs(n)))
	end

	if e1 >= e2 then
		local d = e1 - e2

		if d >= OOM_CUTOFF then
			return setRaw(out, s1, l1, e1)
		end

		local n = s2 + s1 * pow(10, d)

		if n == 0 then
			return setZero(out)
		end

		return normalizeInto(out, sign(n), 1, e2 + log10(abs(n)))
	end

	local d = e2 - e1

	if d >= OOM_CUTOFF then
		return setRaw(out, s2, l2, e2)
	end

	local n = s1 + s2 * pow(10, d)

	if n == 0 then
		return setZero(out)
	end

	return normalizeInto(out, sign(n), 1, e1 + log10(abs(n)))
end

local function mulPartsInto(
	out: buffer,
	s1: number, l1: number, e1: number,
	s2: number, l2: number, e2: number
): buffer
	if s1 == 0 or s2 == 0 then
		return setZero(out)
	end

	local rs = s1 * s2

	if l1 == 0 and l2 == 0 then
		local n = e1 * e2
		local an = abs(n)

		if an >= HIGH or an <= LOW then
			return setRaw(out, rs, 1, log10(an))
		end

		return setRaw(out, rs, 0, an)
	end

	if l1 == l2 and e1 == -e2 then
		return setRaw(out, rs, 0, 1)
	end

	if l1 >= 3 or l2 >= 3 or (l1 == 2 and l2 == 0) or (l2 == 2 and l1 == 0) then
		if l1 > l2 then
			return setRaw(out, rs, l1, e1)
		elseif l2 > l1 then
			return setRaw(out, rs, l2, e2)
		elseif abs(e1) >= abs(e2) then
			return setRaw(out, rs, l1, e1)
		end
		return setRaw(out, rs, l2, e2)
	end

	if l1 == 1 and l2 == 1 then
		return normalizeInto(out, rs, 1, e1 + e2)
	end

	if l1 == 1 and l2 == 0 then
		return normalizeInto(out, rs, 1, e1 + log10(e2))
	end

	if l1 == 0 and l2 == 1 then
		return normalizeInto(out, rs, 1, log10(e1) + e2)
	end

	local fe1 = l1 == 1 and sign(e1) * log10(abs(e1)) or e1
	local fe2 = l2 == 1 and sign(e2) * log10(abs(e2)) or e2
	local a1 = abs(fe1)
	local a2 = abs(fe2)

	if a1 >= a2 then
		local d = a1 - a2

		if d >= OOM_CUTOFF then
			return setRaw(out, rs, l1, e1)
		end

		local v = abs(a2 + log10(abs(sign(fe2) + sign(fe1) * pow(10, d))))
		return normalizeInto(out, rs, 2, sign(fe1) * v)
	end

	local d = a2 - a1

	if d >= OOM_CUTOFF then
		return setRaw(out, rs, l2, e2)
	end

	local v = abs(a1 + log10(abs(sign(fe1) + sign(fe2) * pow(10, d))))
	return normalizeInto(out, rs, 2, sign(fe2) * v)
end

local function divPartsInto(
	out: buffer,
	s1: number, l1: number, e1: number,
	s2: number, l2: number, e2: number
): buffer
	if s2 == 0 then
		return setNaN(out)
	end

	if s1 == 0 then
		return setZero(out)
	end

	local rs = s1 * s2

	if l1 == 0 and l2 == 0 then
		local n = e1 / e2
		local an = abs(n)

		if an >= HIGH or an <= LOW then
			return setRaw(out, rs, 1, log10(an))
		end

		return setRaw(out, rs, 0, an)
	end

	if l1 == l2 and e1 == e2 then
		return setRaw(out, rs, 0, 1)
	end

	if l1 >= 3 or l2 >= 3 or (l1 == 2 and l2 == 0) or (l2 == 2 and l1 == 0) then
		if l1 > l2 then
			return setRaw(out, rs, l1, e1)
		elseif l2 > l1 then
			return setRaw(out, rs, l2, -e2)
		elseif abs(e1) >= abs(e2) then
			return setRaw(out, rs, l1, e1)
		end
		return setRaw(out, rs, l2, -e2)
	end

	if l1 == 1 and l2 == 1 then
		return normalizeInto(out, rs, 1, e1 - e2)
	end

	if l1 == 1 and l2 == 0 then
		return normalizeInto(out, rs, 1, e1 - log10(e2))
	end

	if l1 == 0 and l2 == 1 then
		return normalizeInto(out, rs, 1, log10(e1) - e2)
	end

	local fe1 = l1 == 1 and sign(e1) * log10(abs(e1)) or e1
	local fe2 = l2 == 1 and sign(e2) * log10(abs(e2)) or e2
	local a1 = abs(fe1)
	local a2 = abs(fe2)

	if a1 >= a2 then
		local d = a1 - a2

		if d >= OOM_CUTOFF then
			return setRaw(out, rs, l1, e1)
		end

		local v = abs(a2 + log10(abs(sign(fe2) - sign(fe1) * pow(10, d))))
		return normalizeInto(out, rs, 2, sign(fe1) * v)
	end

	local d = a2 - a1

	if d >= OOM_CUTOFF then
		return setRaw(out, rs, l2, -e2)
	end

	local v = abs(a1 + log10(abs(sign(fe1) - sign(fe2) * pow(10, d))))
	return normalizeInto(out, rs, 2, sign(fe2) * v)
end

local function powPartsInto(
	out: buffer,
	s1: number, l1: number, e1: number,
	s2: number, l2: number, e2: number,
	scratch: buffer?
): buffer
	if s1 == 0 then
		if s2 > 0 then
			return setZero(out)
		end
		return setNaN(out)
	end

	if s2 == 0 or (s1 == 1 and l1 == 0 and e1 == 1) then
		return setRaw(out, 1, 0, 1)
	end

	if s2 == 1 and l2 == 0 and e2 == 1 then
		return setRaw(out, s1, l1, e1)
	end

	if l1 == 0 and l2 == 0 then
		if s1 < 0 and e2 % 1 ~= 0 then
			return setNaN(out)
		end

		local native = pow(e1, s2 * e2)

		if native == native and native ~= math.huge and native ~= 0 then
			local rs = 1
			if s1 < 0 and e2 % 2 ~= 0 then
				rs = -1
			end
			return normalizeInto(out, rs, 0, native)
		end
	end

	local ls, ll, le

	if l1 == 0 then
		local v = log10(e1)

		if v == 0 then
			return setRaw(out, 1, 0, 1)
		end

		ls = v < 0 and -1 or 1
		ll = 0
		le = abs(v)
	else
		ls = e1 < 0 and -1 or 1
		ll = l1 - 1
		le = abs(e1)
	end

	local temp = scratch or alloc()
	mulPartsInto(temp, ls, ll, le, s2, l2, e2)

	local ms = breadi8(temp, S)
	local ml = breadf64(temp, L)
	local me = breadf64(temp, E)

	if ml == 0 and me < 10 then
		return normalizeInto(out, 1, 0, pow(10, ms * me))
	end

	if me < 0 then
		return setRaw(out, 1, 0, 1)
	end

	return normalizeInto(out, 1, ml + 1, ms * me)
end

function Fast.new(s: number, l: number, e: number): buffer
	local out = alloc()
	return normalizeInto(out, s, l, e)
end

function Fast.checkless(s: number, l: number, e: number): buffer
	return setRaw(alloc(), s, l, e)
end

function Fast.fromNumber(n: number): buffer
	local out = alloc()

	if n == 0 then
		return out
	end

	local s, l, e = numberParts(n)
	return setRaw(out, s, l, e)
end

function Fast.fromNumberInto(out: buffer, n: number): buffer
	if n == 0 then
		return setZero(out)
	end

	local s, l, e = numberParts(n)
	return setRaw(out, s, l, e)
end

function Fast.copyInto(out: buffer, value: buffer): buffer
	bcopy(out, 0, value, 0, SIZE)
	return out
end

function Fast.add(a: buffer, b: buffer): buffer
	local out = alloc()
	return signedAddPartsInto(
		out,
		breadi8(a, S), breadf64(a, L), breadf64(a, E),
		breadi8(b, S), breadf64(b, L), breadf64(b, E)
	)
end

function Fast.sub(a: buffer, b: buffer): buffer
	local out = alloc()
	return signedAddPartsInto(
		out,
		breadi8(a, S), breadf64(a, L), breadf64(a, E),
		-breadi8(b, S), breadf64(b, L), breadf64(b, E)
	)
end

function Fast.mul(a: buffer, b: buffer): buffer
	local out = alloc()
	return mulPartsInto(
		out,
		breadi8(a, S), breadf64(a, L), breadf64(a, E),
		breadi8(b, S), breadf64(b, L), breadf64(b, E)
	)
end

function Fast.div(a: buffer, b: buffer): buffer
	local out = alloc()
	return divPartsInto(
		out,
		breadi8(a, S), breadf64(a, L), breadf64(a, E),
		breadi8(b, S), breadf64(b, L), breadf64(b, E)
	)
end

function Fast.pow(a: buffer, b: buffer): buffer
	local out = alloc()
	return powPartsInto(
		out,
		breadi8(a, S), breadf64(a, L), breadf64(a, E),
		breadi8(b, S), breadf64(b, L), breadf64(b, E)
	)
end

function Fast.addInto(out: buffer, a: buffer, b: buffer): buffer
	return signedAddPartsInto(
		out,
		breadi8(a, S), breadf64(a, L), breadf64(a, E),
		breadi8(b, S), breadf64(b, L), breadf64(b, E)
	)
end

function Fast.subInto(out: buffer, a: buffer, b: buffer): buffer
	return signedAddPartsInto(
		out,
		breadi8(a, S), breadf64(a, L), breadf64(a, E),
		-breadi8(b, S), breadf64(b, L), breadf64(b, E)
	)
end

function Fast.mulInto(out: buffer, a: buffer, b: buffer): buffer
	return mulPartsInto(
		out,
		breadi8(a, S), breadf64(a, L), breadf64(a, E),
		breadi8(b, S), breadf64(b, L), breadf64(b, E)
	)
end

function Fast.divInto(out: buffer, a: buffer, b: buffer): buffer
	return divPartsInto(
		out,
		breadi8(a, S), breadf64(a, L), breadf64(a, E),
		breadi8(b, S), breadf64(b, L), breadf64(b, E)
	)
end

function Fast.powInto(out: buffer, a: buffer, b: buffer): buffer
	return powPartsInto(
		out,
		breadi8(a, S), breadf64(a, L), breadf64(a, E),
		breadi8(b, S), breadf64(b, L), breadf64(b, E)
	)
end

function Fast.powIntoWithScratch(out: buffer, scratch: buffer, a: buffer, b: buffer): buffer
	if out == scratch then
		error("GreaterNum.Fast.powIntoWithScratch: out and scratch must be different buffers")
	end

	return powPartsInto(
		out,
		breadi8(a, S), breadf64(a, L), breadf64(a, E),
		breadi8(b, S), breadf64(b, L), breadf64(b, E),
		scratch
	)
end

function Fast.addeq(a: buffer, b: buffer): buffer
	return signedAddPartsInto(
		a,
		breadi8(a, S), breadf64(a, L), breadf64(a, E),
		breadi8(b, S), breadf64(b, L), breadf64(b, E)
	)
end

function Fast.subeq(a: buffer, b: buffer): buffer
	return signedAddPartsInto(
		a,
		breadi8(a, S), breadf64(a, L), breadf64(a, E),
		-breadi8(b, S), breadf64(b, L), breadf64(b, E)
	)
end

function Fast.muleq(a: buffer, b: buffer): buffer
	return mulPartsInto(
		a,
		breadi8(a, S), breadf64(a, L), breadf64(a, E),
		breadi8(b, S), breadf64(b, L), breadf64(b, E)
	)
end

function Fast.diveq(a: buffer, b: buffer): buffer
	return divPartsInto(
		a,
		breadi8(a, S), breadf64(a, L), breadf64(a, E),
		breadi8(b, S), breadf64(b, L), breadf64(b, E)
	)
end

function Fast.poweq(a: buffer, b: buffer): buffer
	return powPartsInto(
		a,
		breadi8(a, S), breadf64(a, L), breadf64(a, E),
		breadi8(b, S), breadf64(b, L), breadf64(b, E)
	)
end

function Fast.eq(a: buffer, b: buffer): boolean
	return breadi8(a, S) == breadi8(b, S)
		and breadf64(a, L) == breadf64(b, L)
		and breadf64(a, E) == breadf64(b, E)
end

function Fast.lt(a: buffer, b: buffer): boolean
	return rawCompare(
		breadi8(a, S), breadf64(a, L), breadf64(a, E),
		breadi8(b, S), breadf64(b, L), breadf64(b, E)
	) < 0
end

function Fast.gt(a: buffer, b: buffer): boolean
	return rawCompare(
		breadi8(a, S), breadf64(a, L), breadf64(a, E),
		breadi8(b, S), breadf64(b, L), breadf64(b, E)
	) > 0
end

function Fast.compare(a: buffer, b: buffer): number
	return rawCompare(
		breadi8(a, S), breadf64(a, L), breadf64(a, E),
		breadi8(b, S), breadf64(b, L), breadf64(b, E)
	)
end

function Fast.ne(a: buffer, b: buffer): boolean
	return not Fast.eq(a, b)
end

function Fast.lte(a: buffer, b: buffer): boolean
	return Fast.compare(a, b) <= 0
end

function Fast.gte(a: buffer, b: buffer): boolean
	return Fast.compare(a, b) >= 0
end

function Fast.isZero(value: buffer): boolean
	return breadi8(value, S) == 0
end

function Fast.isOne(value: buffer): boolean
	return breadi8(value, S) == 1
		and breadf64(value, L) == 0
		and breadf64(value, E) == 1
end

function Fast.alloc(): buffer
	return alloc()
end

function Fast.zero(): buffer
	return alloc()
end

function Fast.one(): buffer
	return setRaw(alloc(), 1, 0, 1)
end

function GreaterNum.new(s: number, l: number, e: number): buffer
	local out = alloc()
	return normalizeInto(out, s, l, e)
end

GreaterNum.fromParts = GreaterNum.new

function GreaterNum.createCheckless(s: number, l: number, e: number): buffer
	return setRaw(alloc(), s, l, e)
end

function GreaterNum.fromNumber(n: number): buffer
	if type(n) ~= "number" then
		error("GreaterNum.fromNumber: expected number")
	end
	return Fast.fromNumber(n)
end

function GreaterNum.fromScientific(mantissa: number, exponent: number): buffer
	if mantissa == 0 then
		return alloc()
	end

	local s = mantissa < 0 and -1 or 1
	local scale = exponent + log10(abs(mantissa))
	local out = alloc()

	if abs(scale) < 10 then
		return normalizeInto(out, s, 0, pow(10, scale))
	end

	if abs(scale) >= HIGH then
		return setRaw(out, s, 2, sign(scale) * log10(abs(scale)))
	end

	return setRaw(out, s, 1, scale)
end

function GreaterNum.zero(): buffer
	return alloc()
end

function GreaterNum.one(): buffer
	return setRaw(alloc(), 1, 0, 1)
end

function GreaterNum.nan(): buffer
	return setNaN(alloc())
end

function GreaterNum.infinity(s: number?): buffer
	return setInf(alloc(), s or 1)
end

function GreaterNum.clone(v): buffer
	if type(v) == "buffer" then
		local out = alloc()
		bcopy(out, 0, v, 0, SIZE)
		return out
	end

	local s, l, e = parts(v)
	return setRaw(alloc(), s, l, e)
end

function GreaterNum.tuple(v): (number, number, number)
	return parts(v)
end

GreaterNum.totuple = GreaterNum.tuple

function GreaterNum.toBuffer(v): buffer
	if type(v) == "buffer" then
		return v
	end
	return GreaterNum.fromNumber(v)
end

GreaterNum.tobuffer = GreaterNum.toBuffer

function GreaterNum.set(out: buffer, s: number, l: number, e: number): buffer
	return normalizeInto(out, s, l, e)
end

function GreaterNum.setCheckless(out: buffer, s: number, l: number, e: number): buffer
	return setRaw(out, s, l, e)
end

function GreaterNum.setFromNumber(out: buffer, n: number): buffer
	return Fast.fromNumberInto(out, n)
end

function GreaterNum.copy(out: buffer, source: buffer): buffer
	bcopy(out, 0, source, 0, SIZE)
	return out
end

local function binary(op, a, b)
	if type(a) == "buffer" and type(b) == "buffer" then
		return op(a, b)
	end

	local s1, l1, e1 = parts(a)
	local s2, l2, e2 = parts(b)
	local out = alloc()

	if op == Fast.add then
		return signedAddPartsInto(out, s1, l1, e1, s2, l2, e2)
	elseif op == Fast.sub then
		return signedAddPartsInto(out, s1, l1, e1, -s2, l2, e2)
	elseif op == Fast.mul then
		return mulPartsInto(out, s1, l1, e1, s2, l2, e2)
	elseif op == Fast.div then
		return divPartsInto(out, s1, l1, e1, s2, l2, e2)
	end

	return powPartsInto(out, s1, l1, e1, s2, l2, e2)
end

function GreaterNum.add(a, b): buffer
	if type(a) == "buffer" and type(b) == "buffer" then
		return Fast.add(a, b)
	end
	local s1,l1,e1 = parts(a)
	local s2,l2,e2 = parts(b)
	return signedAddPartsInto(alloc(), s1,l1,e1,s2,l2,e2)
end

function GreaterNum.sub(a, b): buffer
	if type(a) == "buffer" and type(b) == "buffer" then
		return Fast.sub(a, b)
	end
	local s1,l1,e1 = parts(a)
	local s2,l2,e2 = parts(b)
	return signedAddPartsInto(alloc(), s1,l1,e1,-s2,l2,e2)
end

function GreaterNum.mul(a, b): buffer
	if type(a) == "buffer" and type(b) == "buffer" then
		return Fast.mul(a, b)
	end
	local s1,l1,e1 = parts(a)
	local s2,l2,e2 = parts(b)
	return mulPartsInto(alloc(), s1,l1,e1,s2,l2,e2)
end

function GreaterNum.div(a, b): buffer
	if type(a) == "buffer" and type(b) == "buffer" then
		return Fast.div(a, b)
	end
	local s1,l1,e1 = parts(a)
	local s2,l2,e2 = parts(b)
	return divPartsInto(alloc(), s1,l1,e1,s2,l2,e2)
end

function GreaterNum.pow(a, b): buffer
	if type(a) == "buffer" and type(b) == "buffer" then
		return Fast.pow(a, b)
	end
	local s1,l1,e1 = parts(a)
	local s2,l2,e2 = parts(b)
	return powPartsInto(alloc(), s1,l1,e1,s2,l2,e2)
end

function GreaterNum.addInto(out: buffer, a, b): buffer
	local s1,l1,e1 = parts(a)
	local s2,l2,e2 = parts(b)
	return signedAddPartsInto(out, s1,l1,e1,s2,l2,e2)
end

function GreaterNum.subInto(out: buffer, a, b): buffer
	local s1,l1,e1 = parts(a)
	local s2,l2,e2 = parts(b)
	return signedAddPartsInto(out, s1,l1,e1,-s2,l2,e2)
end

function GreaterNum.mulInto(out: buffer, a, b): buffer
	local s1,l1,e1 = parts(a)
	local s2,l2,e2 = parts(b)
	return mulPartsInto(out, s1,l1,e1,s2,l2,e2)
end

function GreaterNum.divInto(out: buffer, a, b): buffer
	local s1,l1,e1 = parts(a)
	local s2,l2,e2 = parts(b)
	return divPartsInto(out, s1,l1,e1,s2,l2,e2)
end

function GreaterNum.powInto(out: buffer, a, b): buffer
	local s1,l1,e1 = parts(a)
	local s2,l2,e2 = parts(b)
	return powPartsInto(out, s1,l1,e1,s2,l2,e2)
end

function GreaterNum.addeq(a: buffer, b): buffer
	local s2,l2,e2 = parts(b)
	return signedAddPartsInto(
		a,
		breadi8(a, S), breadf64(a, L), breadf64(a, E),
		s2, l2, e2
	)
end

function GreaterNum.subeq(a: buffer, b): buffer
	local s2,l2,e2 = parts(b)
	return signedAddPartsInto(
		a,
		breadi8(a, S), breadf64(a, L), breadf64(a, E),
		-s2, l2, e2
	)
end

function GreaterNum.muleq(a: buffer, b): buffer
	local s2,l2,e2 = parts(b)
	return mulPartsInto(
		a,
		breadi8(a, S), breadf64(a, L), breadf64(a, E),
		s2, l2, e2
	)
end

function GreaterNum.diveq(a: buffer, b): buffer
	local s2,l2,e2 = parts(b)
	return divPartsInto(
		a,
		breadi8(a, S), breadf64(a, L), breadf64(a, E),
		s2, l2, e2
	)
end

function GreaterNum.poweq(a: buffer, b): buffer
	local s2,l2,e2 = parts(b)
	return powPartsInto(
		a,
		breadi8(a, S), breadf64(a, L), breadf64(a, E),
		s2, l2, e2
	)
end

function GreaterNum.neg(v): buffer
	local s,l,e = parts(v)

	if s == 0 then
		return alloc()
	end

	return setRaw(alloc(), -s, l, e)
end

function GreaterNum.abs(v): buffer
	local s,l,e = parts(v)

	if s == 0 then
		return alloc()
	end

	return setRaw(alloc(), 1, l, e)
end

function GreaterNum.recip(v): buffer
	return GreaterNum.div(1, v)
end

GreaterNum.reciprocal = GreaterNum.recip

function GreaterNum.intdiv(a, b): buffer
	return GreaterNum.floor(GreaterNum.div(a, b))
end

function GreaterNum.mod(a, b): buffer
	local q = GreaterNum.intdiv(a, b)
	return GreaterNum.sub(a, GreaterNum.mul(q, b))
end

function GreaterNum.root(a, n): buffer
	return GreaterNum.pow(a, GreaterNum.div(1, n))
end

function GreaterNum.sqrt(a): buffer
	return GreaterNum.pow(a, 0.5)
end

function GreaterNum.cbrt(a): buffer
	return GreaterNum.pow(a, 1/3)
end

function GreaterNum.pow2(a): buffer
	return GreaterNum.pow(2, a)
end

function GreaterNum.pow10(a): buffer
	local s,l,e = parts(a)
	local out = alloc()

	if s == 0 then
		return setRaw(out, 1, 0, 1)
	end

	if l == 0 and e < 10 then
		return normalizeInto(out, 1, 0, pow(10, s * e))
	end

	if e < 0 then
		return setRaw(out, 1, 0, 1)
	end

	return normalizeInto(out, 1, l + 1, s * e)
end

function GreaterNum.exp(a): buffer
	return GreaterNum.pow(EULER, a)
end

function GreaterNum.abslog10(a): buffer
	local s,l,e = parts(a)

	if s == 0 then
		return GreaterNum.nan()
	end

	if l == 0 then
		local n = log10(e)
		return GreaterNum.fromNumber(n)
	end

	return normalizeInto(alloc(), sign(e), l - 1, abs(e))
end

function GreaterNum.log10(a): buffer
	local s,l,e = parts(a)

	if s <= 0 then
		return GreaterNum.nan()
	end

	if l == 0 then
		return GreaterNum.fromNumber(log10(e))
	end

	return normalizeInto(alloc(), sign(e), l - 1, abs(e))
end

function GreaterNum.log2(a): buffer
	return GreaterNum.div(GreaterNum.log10(a), LOG10_2)
end

function GreaterNum.ln(a): buffer
	return GreaterNum.div(GreaterNum.log10(a), LOG10_E)
end

function GreaterNum.log(a, base): buffer
	base = base or EULER
	return GreaterNum.div(GreaterNum.log10(a), GreaterNum.log10(base))
end

function GreaterNum.compare(a, b): number
	if type(a) == "buffer" and type(b) == "buffer" then
		return Fast.compare(a, b)
	end

	local s1,l1,e1 = parts(a)
	local s2,l2,e2 = parts(b)
	return rawCompare(s1,l1,e1,s2,l2,e2)
end

function GreaterNum.eq(a,b): boolean
	if type(a) == "buffer" and type(b) == "buffer" then
		return Fast.eq(a, b)
	end
	return GreaterNum.compare(a,b) == 0
end

function GreaterNum.ne(a,b): boolean
	return not GreaterNum.eq(a,b)
end

function GreaterNum.lt(a,b): boolean
	if type(a) == "buffer" and type(b) == "buffer" then
		return Fast.lt(a, b)
	end
	return GreaterNum.compare(a,b) < 0
end

function GreaterNum.lte(a,b): boolean
	if type(a) == "buffer" and type(b) == "buffer" then
		return Fast.lte(a, b)
	end
	return GreaterNum.compare(a,b) <= 0
end

function GreaterNum.gt(a,b): boolean
	if type(a) == "buffer" and type(b) == "buffer" then
		return Fast.gt(a, b)
	end
	return GreaterNum.compare(a,b) > 0
end

function GreaterNum.gte(a,b): boolean
	if type(a) == "buffer" and type(b) == "buffer" then
		return Fast.gte(a, b)
	end
	return GreaterNum.compare(a,b) >= 0
end

GreaterNum.equals = GreaterNum.eq

function GreaterNum.max(...)
	local args = table.pack(...)
	local result = args[1]

	for i = 2, args.n do
		if GreaterNum.gt(args[i], result) then
			result = args[i]
		end
	end

	return GreaterNum.clone(result)
end

function GreaterNum.min(...)
	local args = table.pack(...)
	local result = args[1]

	for i = 2, args.n do
		if GreaterNum.lt(args[i], result) then
			result = args[i]
		end
	end

	return GreaterNum.clone(result)
end

local function absCompare(a, b): number
	local s1,l1,e1 = parts(a)
	local s2,l2,e2 = parts(b)
	return rawCompare(abs(s1), l1, e1, abs(s2), l2, e2)
end

function GreaterNum.maxabs(...)
	local args = table.pack(...)
	local result = args[1]

	for i = 2, args.n do
		if absCompare(args[i], result) > 0 then
			result = args[i]
		end
	end

	return GreaterNum.clone(result)
end

function GreaterNum.minabs(...)
	local args = table.pack(...)
	local result = args[1]

	for i = 2, args.n do
		if absCompare(args[i], result) < 0 then
			result = args[i]
		end
	end

	return GreaterNum.clone(result)
end

function GreaterNum.floor(a): buffer
	local s,l,e = parts(a)

	if s == 0 then
		return alloc()
	end

	if l == 0 then
		return GreaterNum.fromNumber(floor(s * e))
	end

	if e < 0 then
		return s > 0 and alloc() or GreaterNum.fromNumber(-1)
	end

	return setRaw(alloc(), s, l, e)
end

function GreaterNum.ceil(a): buffer
	local s,l,e = parts(a)

	if s == 0 then
		return alloc()
	end

	if l == 0 then
		return GreaterNum.fromNumber(ceil(s * e))
	end

	if e < 0 then
		return s > 0 and GreaterNum.fromNumber(1) or alloc()
	end

	return setRaw(alloc(), s, l, e)
end

function GreaterNum.round(a): buffer
	local s,l,e = parts(a)

	if l == 0 then
		return GreaterNum.fromNumber(round(s * e))
	end

	if e < 0 then
		return alloc()
	end

	return setRaw(alloc(), s, l, e)
end

function GreaterNum.trunc(a): buffer
	local s,l,e = parts(a)

	if l == 0 then
		local n = s * e
		return GreaterNum.fromNumber(n < 0 and ceil(n) or floor(n))
	end

	if e < 0 then
		return alloc()
	end

	return setRaw(alloc(), s, l, e)
end

function GreaterNum.roundTo(a, step): buffer
	if GreaterNum.isZero(step) then
		return GreaterNum.clone(a)
	end

	return GreaterNum.mul(GreaterNum.round(GreaterNum.div(a, step)), step)
end

function GreaterNum.isPositive(v): boolean
	local s = parts(v)
	return s > 0
end

function GreaterNum.isNegative(v): boolean
	local s = parts(v)
	return s < 0
end

function GreaterNum.isZero(v): boolean
	local s = parts(v)
	return s == 0
end

function GreaterNum.isNaN(v): boolean
	local _,l = parts(v)
	return l < 0
end

function GreaterNum.isInf(v): boolean
	local _,l = parts(v)
	return l == math.huge
end

function GreaterNum.isFinite(v): boolean
	local _,l,e = parts(v)
	return l >= 0 and l ~= math.huge and e == e
end

function GreaterNum.isNumber(v): boolean
	local _,l,e = parts(v)
	return l == 0 or (l == 1 and e <= 308 and e >= -324)
end

function GreaterNum.sign(v): number
	local s = parts(v)
	return s
end

function GreaterNum.layer(v): number
	local _,l = parts(v)
	return l
end

function GreaterNum.exponent(v): number
	local _,_,e = parts(v)
	return e
end

function GreaterNum.toNumber(v): number
	local s,l,e = parts(v)

	if l < 0 then
		return 0/0
	end

	if l == math.huge then
		return s * math.huge
	end

	if s == 0 then
		return 0
	end

	if l == 0 then
		return s * e
	end

	if l == 1 and e <= 308 and e >= -324 then
		return s * pow(10, e)
	end

	return s * math.huge
end

function GreaterNum.random(a, b, rng: Random?): buffer
	rng = rng or Random.new()

	local an = GreaterNum.toNumber(a)
	local bn = GreaterNum.toNumber(b)

	if an ~= math.huge and an ~= -math.huge and bn ~= math.huge and bn ~= -math.huge then
		return GreaterNum.fromNumber(rng:NextNumber(an, bn))
	end

	local s1,l1,e1 = parts(a)
	local s2,l2,e2 = parts(b)

	if s1 ~= s2 or l1 ~= l2 then
		return GreaterNum.lerp(a, b, rng:NextNumber())
	end

	return GreaterNum.new(s1, l1, rng:NextNumber(e1, e2))
end

function GreaterNum.lerp(a, b, alpha: number): buffer
	if alpha <= 0 then
		return GreaterNum.clone(a)
	end
	if alpha >= 1 then
		return GreaterNum.clone(b)
	end
	return GreaterNum.add(a, GreaterNum.mul(GreaterNum.sub(b, a), alpha))
end

function GreaterNum.percent(value, amount): buffer
	return GreaterNum.mul(value, GreaterNum.div(amount, 100))
end

function GreaterNum.clamp(value, low, high): buffer
	if GreaterNum.lt(value, low) then
		return GreaterNum.clone(low)
	end
	if GreaterNum.gt(value, high) then
		return GreaterNum.clone(high)
	end
	return GreaterNum.clone(value)
end

function GreaterNum.sumInto(out: buffer, values: {any}): buffer
	setZero(out)

	for i = 1, #values do
		GreaterNum.addeq(out, values[i])
	end

	return out
end

function GreaterNum.sum(values: {any}): buffer
	return GreaterNum.sumInto(alloc(), values)
end

function GreaterNum.productInto(out: buffer, values: {any}): buffer
	setRaw(out, 1, 0, 1)

	for i = 1, #values do
		GreaterNum.muleq(out, values[i])
	end

	return out
end

function GreaterNum.product(values: {any}): buffer
	return GreaterNum.productInto(alloc(), values)
end

function GreaterNum.geometricSum(base, multiplier, startIndex: number, lastIndex: number): buffer
	if lastIndex < startIndex then
		return GreaterNum.zero()
	end

	local count = lastIndex - startIndex + 1

	if GreaterNum.eq(multiplier, 1) then
		return GreaterNum.mul(GreaterNum.mul(base, GreaterNum.pow(multiplier, startIndex)), count)
	end

	local first = GreaterNum.mul(base, GreaterNum.pow(multiplier, startIndex))
	local numerator = GreaterNum.sub(GreaterNum.pow(multiplier, count), 1)
	local denominator = GreaterNum.sub(multiplier, 1)

	return GreaterNum.mul(first, GreaterNum.div(numerator, denominator))
end

function GreaterNum.geometricCost(base, multiplier, owned: number, amount: number): buffer
	if amount <= 0 then
		return GreaterNum.zero()
	end

	return GreaterNum.geometricSum(base, multiplier, owned, owned + amount - 1)
end

function GreaterNum.affordGeometric(currency, base, multiplier, owned: number, maxAmount: number?): number
	local limit = maxAmount or 1_000_000
	local low = 0
	local high = 1

	while high < limit and GreaterNum.lte(GreaterNum.geometricCost(base, multiplier, owned, high), currency) do
		low = high
		high = min(limit, high * 2)
	end

	while low < high do
		local mid = floor((low + high + 1) / 2)

		if GreaterNum.lte(GreaterNum.geometricCost(base, multiplier, owned, mid), currency) then
			low = mid
		else
			high = mid - 1
		end
	end

	return low
end

function GreaterNum.softcap(value, start, powerValue: number): buffer
	if GreaterNum.lte(value, start) then
		return GreaterNum.clone(value)
	end

	local ratio = GreaterNum.div(value, start)
	return GreaterNum.mul(start, GreaterNum.pow(ratio, powerValue))
end

function GreaterNum.scale(value, start, powerValue: number): buffer
	if GreaterNum.lte(value, start) then
		return GreaterNum.clone(value)
	end

	return GreaterNum.add(
		start,
		GreaterNum.pow(GreaterNum.sub(value, start), powerValue)
	)
end

function GreaterNum.unscale(value, start, powerValue: number): buffer
	if GreaterNum.lte(value, start) then
		return GreaterNum.clone(value)
	end

	return GreaterNum.add(
		start,
		GreaterNum.root(GreaterNum.sub(value, start), powerValue)
	)
end

function GreaterNum.factorial(value): buffer
	local n = GreaterNum.toNumber(value)

	if n ~= n or n < 0 or n % 1 ~= 0 then
		return GreaterNum.nan()
	end

	if n <= 170 then
		local x = 1
		for i = 2, n do
			x *= i
		end
		return GreaterNum.fromNumber(x)
	end

	local logN = n * log10(n / EULER) + 0.5 * log10(2 * math.pi * n)
	return GreaterNum.new(1, 1, logN)
end

GreaterNum.fact = GreaterNum.factorial

function GreaterNum.tetrate(base, height: number): buffer
	if height < 0 or height % 1 ~= 0 then
		return GreaterNum.nan()
	end

	if height == 0 then
		return GreaterNum.one()
	end

	local result = GreaterNum.clone(base)

	for _ = 2, height do
		result = GreaterNum.pow(base, result)

		local _,l = parts(result)
		if l >= 32 then
			break
		end
	end

	return result
end

GreaterNum.tetr = GreaterNum.tetrate

local SUFFIXES = {
	"K","M","B","T","Qa","Qi","Sx","Sp","Oc","No",
	"Dc","Ud","Dd","Td","Qad","Qid","Sxd","Spd","Ocd","Nod",
	"Vg","Uvg","Dvg","Tvg","Qavg","Qivg","Sxvg","Spvg","Ocvg","Novg",
}

local function trimZeros(text: string): string
	if not string.find(text, ".", 1, true) then
		return text
	end
	return (text:gsub("0+$", ""):gsub("%.$", ""))
end

local function fixed(n: number, digits: number, trim: boolean): string
	local text = string.format("%." .. tostring(digits) .. "f", n)
	return trim and trimZeros(text) or text
end

local function commas(text: string): string
	local signText = ""

	if string.sub(text, 1, 1) == "-" or string.sub(text, 1, 1) == "+" then
		signText = string.sub(text, 1, 1)
		text = string.sub(text, 2)
	end

	local int, frac = string.match(text, "^(%d+)(%.%d+)$")

	if not int then
		int = text
		frac = ""
	end

	while true do
		local replaced
		int, replaced = string.gsub(int, "^(%d+)(%d%d%d)", "%1,%2")

		if replaced == 0 then
			break
		end
	end

	return signText .. int .. (frac or "")
end

local function sciFromParts(s: number, l: number, e: number, digits: number, trim: boolean): string
	if s == 0 then
		return "0"
	end

	if l < 0 then
		return "NaN"
	end

	if l == math.huge then
		return s < 0 and "-Infinity" or "Infinity"
	end

	local signText = s < 0 and "-" or ""

	if l == 0 then
		local exponent = floor(log10(e))
		local mantissa = e / pow(10, exponent)
		return signText .. fixed(mantissa, digits, trim) .. "e" .. tostring(exponent)
	end

	if l == 1 then
		local exponent = floor(e)
		local mantissa = pow(10, e - exponent)
		return signText .. fixed(mantissa, digits, trim) .. "e" .. tostring(exponent)
	end

	if l <= 5 then
		return signText .. string.rep("e", l) .. fixed(e, digits, trim)
	end

	return signText .. "L" .. tostring(l) .. ":" .. fixed(e, digits, trim)
end

function GreaterNum.format(value, options): string
	options = options or {}

	local notation = string.lower(options.notation or options.style or "auto")
	local digits = math.clamp(floor(options.digits or options.decimals or options.precision or 2), 0, 15)
	local trim = options.trim ~= false
	local separators = options.separators == true
	local forceSign = options.forceSign == true
	local suffixes = options.suffixes or SUFFIXES

	local s,l,e = parts(value)

	if l < 0 then
		return options.nanText or "NaN"
	end

	if l == math.huge then
		if s < 0 then
			return options.negativeInfinityText or "-Infinity"
		end
		return options.infinityText or "Infinity"
	end

	if s == 0 then
		return options.zeroText or "0"
	end

	local prefix = s < 0 and "-" or (forceSign and "+" or "")

	if notation == "layer" or notation == "raw" then
		return prefix .. "L" .. tostring(l) .. ":" .. fixed(e, digits, trim)
	end

	if notation == "scientific" or notation == "sci" then
		local result = sciFromParts(s,l,e,digits,trim)
		if forceSign and s > 0 then
			result = "+" .. result
		end
		return result
	end

	if notation == "engineering" or notation == "eng" then
		if l == 0 then
			local exp3 = floor(log10(e) / 3) * 3
			local mantissa = e / pow(10, exp3)
			local result = prefix .. fixed(mantissa, digits, trim) .. "e" .. tostring(exp3)
			return result
		end

		if l == 1 then
			local exp3 = floor(e / 3) * 3
			local mantissa = pow(10, e - exp3)
			return prefix .. fixed(mantissa, digits, trim) .. "e" .. tostring(exp3)
		end

		return sciFromParts(s,l,e,digits,trim)
	end

	if notation == "suffix" or notation == "short" or notation == "auto" then
		if l == 0 then
			if e < 1000 and notation == "auto" then
				local result = fixed(s * e, digits, trim)
				return separators and commas(result) or result
			end

			local index = floor(log10(e) / 3)

			if index >= 1 and index <= #suffixes then
				local scaled = e / pow(10, index * 3)
				return prefix .. fixed(scaled, digits, trim) .. suffixes[index]
			end

			local result = fixed(s * e, digits, trim)
			if notation == "auto" and e < 1e15 then
				return separators and commas(result) or result
			end
		elseif l == 1 then
			local index = floor(e / 3)

			if index >= 1 and index <= #suffixes then
				local scaled = pow(10, e - index * 3)
				return prefix .. fixed(scaled, digits, trim) .. suffixes[index]
			end
		end

		return sciFromParts(s,l,e,digits,trim)
	end

	if notation == "full" then
		local n = GreaterNum.toNumber(value)

		if n ~= math.huge and n ~= -math.huge then
			local result = fixed(n, digits, trim)
			return separators and commas(result) or result
		end

		return sciFromParts(s,l,e,digits,trim)
	end

	return sciFromParts(s,l,e,digits,trim)
end

function GreaterNum.toString(value, digits: number?): string
	return GreaterNum.format(value, {
		notation = "auto",
		digits = digits or 3,
	})
end

GreaterNum.tostring = GreaterNum.toString

function GreaterNum.toSuffix(value, digits: number?): string
	return GreaterNum.format(value, {
		notation = "suffix",
		digits = digits or 3,
	})
end

function GreaterNum.toScientific(value, digits: number?): string
	return GreaterNum.format(value, {
		notation = "scientific",
		digits = digits or 3,
	})
end

function GreaterNum.toEngineer(value, digits: number?): string
	return GreaterNum.format(value, {
		notation = "engineering",
		digits = digits or 3,
	})
end

function GreaterNum.toLayered(value, digits: number?): string
	return GreaterNum.format(value, {
		notation = "layer",
		digits = digits or 3,
	})
end

function GreaterNum.fromString(text: string): buffer
	if type(text) ~= "string" then
		error("GreaterNum.fromString: expected string")
	end

	text = string.gsub(text, "^%s+", "")
	text = string.gsub(text, "%s+$", "")

	local lower = string.lower(text)

	if lower == "nan" then
		return GreaterNum.nan()
	elseif lower == "inf" or lower == "infinity" then
		return GreaterNum.infinity(1)
	elseif lower == "-inf" or lower == "-infinity" then
		return GreaterNum.infinity(-1)
	end

	local signValue = 1

	if string.sub(text, 1, 1) == "-" then
		signValue = -1
		text = string.sub(text, 2)
	elseif string.sub(text, 1, 1) == "+" then
		text = string.sub(text, 2)
	end

	local layer, exponent = string.match(text, "^[Ll]([%d%.]+):([%-%d%.]+)$")

	if layer then
		return GreaterNum.new(signValue, tonumber(layer), tonumber(exponent))
	end

	local semicolonLayer, semicolonExponent = string.match(text, "^([%d%.]+);([%-%d%.]+)$")

	if semicolonLayer then
		return GreaterNum.new(signValue, tonumber(semicolonLayer), tonumber(semicolonExponent))
	end

	local mantissa, exponentText = string.match(text, "^([%d%.]+)[eE]([%-%d]+)$")

	if mantissa then
		return GreaterNum.fromScientific(signValue * tonumber(mantissa), tonumber(exponentText))
	end

	local n = tonumber((signValue < 0 and "-" or "") .. text)

	if n then
		return GreaterNum.fromNumber(n)
	end

	error("GreaterNum.fromString: invalid value '" .. text .. "'")
end


function GreaterNum.isGreaterNum(value): boolean
	return type(value) == "buffer" and blen(value) == SIZE
end

function GreaterNum.isValid(value): boolean
	if type(value) ~= "buffer" or blen(value) ~= SIZE then
		return false
	end

	local s = breadi8(value, S)
	local l = breadf64(value, L)
	local e = breadf64(value, E)

	if s < -1 or s > 1 or s % 1 ~= 0 then
		return false
	end

	if l ~= l or e ~= e then
		return false
	end

	if l < -1 then
		return false
	end

	if s == 0 then
		return l == 0 and e == 0
	end

	return true
end

function GreaterNum.assertValid(value, label: string?): buffer
	if not GreaterNum.isValid(value) then
		error((label or "GreaterNum value") .. " is not a valid 17-byte GreaterNum buffer")
	end

	return value
end

function GreaterNum.coerce(value): buffer
	if type(value) == "buffer" then
		if blen(value) ~= SIZE then
			error("GreaterNum.coerce: invalid buffer size")
		end
		return value
	end

	if type(value) == "number" then
		return GreaterNum.fromNumber(value)
	end

	if type(value) == "string" then
		return GreaterNum.fromString(value)
	end

	if type(value) == "table" then
		local s = value.sign or value.Sign or value[1]
		local l = value.layer or value.Layer or value[2]
		local e = value.exponent or value.Exponent or value.exp or value.Exp or value[3]

		if type(s) == "number" and type(l) == "number" and type(e) == "number" then
			return GreaterNum.new(s, l, e)
		end
	end

	error("GreaterNum.coerce: unsupported value type " .. typeof(value))
end

function GreaterNum.tryFromString(text: string): (buffer?, string?)
	local ok, result = pcall(GreaterNum.fromString, text)

	if ok then
		return result, nil
	end

	return nil, tostring(result)
end

function GreaterNum.tryCoerce(value): (buffer?, string?)
	local ok, result = pcall(GreaterNum.coerce, value)

	if ok then
		return result, nil
	end

	return nil, tostring(result)
end

function GreaterNum.tryToNumber(value): (number?, string?)
	local ok, n = pcall(GreaterNum.toNumber, value)

	if not ok then
		return nil, tostring(n)
	end

	if n ~= n then
		return nil, "GreaterNum.tryToNumber: value is NaN"
	end

	if n == math.huge or n == -math.huge then
		return nil, "GreaterNum.tryToNumber: value exceeds native number range"
	end

	return n, nil
end

function GreaterNum.fromTuple(data): buffer
	if type(data) ~= "table" or #data < 3 then
		error("GreaterNum.fromTuple: expected {sign, layer, exponent}")
	end

	return GreaterNum.new(data[1], data[2], data[3])
end

function GreaterNum.isOne(value): boolean
	local s,l,e = parts(value)
	return s == 1 and l == 0 and e == 1
end

function GreaterNum.isInteger(value): boolean
	local s,l,e = parts(value)

	if s == 0 then
		return true
	end

	if l > 0 then
		return e >= 0
	end

	return e % 1 == 0
end

function GreaterNum.isEven(value): boolean
	local s,l,e = parts(value)

	if s == 0 then
		return true
	end

	if l > 0 then
		return e >= 1
	end

	return e % 2 == 0
end

function GreaterNum.isOdd(value): boolean
	local s,l,e = parts(value)

	if s == 0 or l > 0 then
		return false
	end

	return e % 2 == 1
end

function GreaterNum.sqr(value): buffer
	return GreaterNum.mul(value, value)
end

function GreaterNum.cube(value): buffer
	return GreaterNum.mul(GreaterNum.mul(value, value), value)
end

function GreaterNum.signum(value): buffer
	local s = parts(value)
	return GreaterNum.fromNumber(s)
end

function GreaterNum.copySign(magnitude, signSource): buffer
	local _,l,e = parts(magnitude)
	local s2 = parts(signSource)

	if e == 0 then
		return GreaterNum.zero()
	end

	return setRaw(alloc(), s2 < 0 and -1 or 1, l, e)
end

function GreaterNum.distance(a, b): buffer
	return GreaterNum.abs(GreaterNum.sub(a, b))
end

function GreaterNum.approxEq(a, b, relativeTolerance: number?, absoluteTolerance: number?): boolean
	relativeTolerance = relativeTolerance or 1e-12
	absoluteTolerance = absoluteTolerance or 1e-12

	if GreaterNum.eq(a, b) then
		return true
	end

	local difference = GreaterNum.distance(a, b)
	local absoluteLimit = GreaterNum.fromNumber(absoluteTolerance)

	if GreaterNum.lte(difference, absoluteLimit) then
		return true
	end

	local largest = GreaterNum.max(GreaterNum.abs(a), GreaterNum.abs(b))
	local relativeLimit = GreaterNum.mul(largest, relativeTolerance)

	return GreaterNum.lte(difference, relativeLimit)
end

function GreaterNum.floorTo(value, step): buffer
	if GreaterNum.isZero(step) then
		return GreaterNum.clone(value)
	end

	return GreaterNum.mul(
		GreaterNum.floor(GreaterNum.div(value, step)),
		step
	)
end

function GreaterNum.ceilTo(value, step): buffer
	if GreaterNum.isZero(step) then
		return GreaterNum.clone(value)
	end

	return GreaterNum.mul(
		GreaterNum.ceil(GreaterNum.div(value, step)),
		step
	)
end

function GreaterNum.quantize(value, step): buffer
	return GreaterNum.roundTo(value, step)
end

function GreaterNum.clamp01(value): buffer
	return GreaterNum.clamp(value, 0, 1)
end

function GreaterNum.inRange(value, low, high, inclusive: boolean?): boolean
	if GreaterNum.gt(low, high) then
		low, high = high, low
	end

	if inclusive == false then
		return GreaterNum.gt(value, low) and GreaterNum.lt(value, high)
	end

	return GreaterNum.gte(value, low) and GreaterNum.lte(value, high)
end

GreaterNum.between = GreaterNum.inRange

function GreaterNum.lerpClamped(a, b, alpha: number): buffer
	return GreaterNum.lerp(a, b, math.clamp(alpha, 0, 1))
end

function GreaterNum.moveTowards(current, target, maxDelta): buffer
	local delta = GreaterNum.sub(target, current)
	local distance = GreaterNum.abs(delta)
	local step = GreaterNum.abs(maxDelta)

	if GreaterNum.lte(distance, step) then
		return GreaterNum.clone(target)
	end

	return GreaterNum.add(current, GreaterNum.mul(step, GreaterNum.sign(delta)))
end

function GreaterNum.addPercent(value, amount): buffer
	return GreaterNum.add(value, GreaterNum.percent(value, amount))
end

function GreaterNum.subPercent(value, amount): buffer
	return GreaterNum.sub(value, GreaterNum.percent(value, amount))
end

function GreaterNum.percentOf(part, total): buffer
	if GreaterNum.isZero(total) then
		return GreaterNum.nan()
	end

	return GreaterNum.mul(GreaterNum.div(part, total), 100)
end

function GreaterNum.percentChange(oldValue, newValue): buffer
	if GreaterNum.isZero(oldValue) then
		return GreaterNum.nan()
	end

	return GreaterNum.mul(
		GreaterNum.div(GreaterNum.sub(newValue, oldValue), GreaterNum.abs(oldValue)),
		100
	)
end

function GreaterNum.canAfford(currency, cost): boolean
	return GreaterNum.gte(currency, cost)
end

function GreaterNum.inverseLerp(a, b, value): number
	if GreaterNum.eq(a, b) then
		return 0
	end

	return GreaterNum.toNumber(
		GreaterNum.div(
			GreaterNum.sub(value, a),
			GreaterNum.sub(b, a)
		)
	)
end

function GreaterNum.remap(value, inMin, inMax, outMin, outMax): buffer
	local alpha = GreaterNum.inverseLerp(inMin, inMax, value)
	return GreaterNum.lerp(outMin, outMax, alpha)
end

function GreaterNum.smoothstep(edge0, edge1, value): number
	local x = math.clamp(GreaterNum.inverseLerp(edge0, edge1, value), 0, 1)
	return x * x * (3 - 2 * x)
end

function GreaterNum.smootherstep(edge0, edge1, value): number
	local x = math.clamp(GreaterNum.inverseLerp(edge0, edge1, value), 0, 1)
	return x * x * x * (x * (x * 6 - 15) + 10)
end

function GreaterNum.mean(values: {any}): buffer
	if #values == 0 then
		return GreaterNum.nan()
	end

	return GreaterNum.div(GreaterNum.sum(values), #values)
end

function GreaterNum.weightedMean(values: {any}, weights: {number}): buffer
	if #values == 0 or #values ~= #weights then
		return GreaterNum.nan()
	end

	local total = GreaterNum.zero()
	local term = alloc()
	local totalWeight = 0

	for i = 1, #values do
		local weight = weights[i]
		totalWeight += weight
		GreaterNum.mulInto(term, values[i], weight)
		GreaterNum.addeq(total, term)
	end

	if totalWeight == 0 then
		return GreaterNum.nan()
	end

	return GreaterNum.div(total, totalWeight)
end

function GreaterNum.geometricMean(values: {any}): buffer
	if #values == 0 then
		return GreaterNum.nan()
	end

	for i = 1, #values do
		if GreaterNum.lte(values[i], 0) then
			return GreaterNum.nan()
		end
	end

	return GreaterNum.root(GreaterNum.product(values), #values)
end

function GreaterNum.harmonicMean(values: {any}): buffer
	if #values == 0 then
		return GreaterNum.nan()
	end

	local reciprocalSum = GreaterNum.zero()
	local reciprocal = alloc()

	for i = 1, #values do
		if GreaterNum.isZero(values[i]) then
			return GreaterNum.zero()
		end

		GreaterNum.divInto(reciprocal, 1, values[i])
		GreaterNum.addeq(reciprocalSum, reciprocal)
	end

	return GreaterNum.div(#values, reciprocalSum)
end

function GreaterNum.hypot(a, b): buffer
	return GreaterNum.sqrt(
		GreaterNum.add(
			GreaterNum.sqr(a),
			GreaterNum.sqr(b)
		)
	)
end

local LANCZOS_G = 7
local LANCZOS = {
	0.99999999999980993,
	676.5203681218851,
	-1259.1392167224028,
	771.32342877765313,
	-176.61502916214059,
	12.507343278686905,
	-0.13857109526572012,
	9.9843695780195716e-6,
	1.5056327351493116e-7,
}

local function gammaNative(z: number): number
	if z < 0.5 then
		return math.pi / (math.sin(math.pi * z) * gammaNative(1 - z))
	end

	z -= 1

	local x = LANCZOS[1]

	for i = 2, #LANCZOS do
		x += LANCZOS[i] / (z + i - 1)
	end

	local t = z + LANCZOS_G + 0.5

	return math.sqrt(2 * math.pi) * t ^ (z + 0.5) * math.exp(-t) * x
end

function GreaterNum.logGamma(value): buffer
	local n = GreaterNum.toNumber(value)

	if n ~= n or n <= 0 then
		return GreaterNum.nan()
	end

	if n < 171 then
		return GreaterNum.fromNumber(math.log(gammaNative(n)))
	end

	if n == math.huge then
		return GreaterNum.infinity()
	end

	local result =
		(n - 0.5) * math.log(n)
		- n
		+ 0.5 * math.log(2 * math.pi)
		+ 1 / (12 * n)
		- 1 / (360 * n ^ 3)

	return GreaterNum.fromNumber(result)
end

function GreaterNum.gamma(value): buffer
	local n = GreaterNum.toNumber(value)

	if n ~= n or n <= 0 then
		return GreaterNum.nan()
	end

	if n < 171 then
		return GreaterNum.fromNumber(gammaNative(n))
	end

	if n == math.huge then
		return GreaterNum.infinity()
	end

	local log10Gamma =
		((n - 0.5) * math.log(n)
		- n
		+ 0.5 * math.log(2 * math.pi)
		+ 1 / (12 * n)
		- 1 / (360 * n ^ 3)) / LN10

	return GreaterNum.new(1, 1, log10Gamma)
end

function GreaterNum.permutation(n: number, r: number): buffer
	n = floor(n)
	r = floor(r)

	if n < 0 or r < 0 or r > n then
		return GreaterNum.nan()
	end

	local result = GreaterNum.one()

	for i = n - r + 1, n do
		GreaterNum.muleq(result, i)
	end

	return result
end

GreaterNum.perm = GreaterNum.permutation

function GreaterNum.combination(n: number, r: number): buffer
	n = floor(n)
	r = floor(r)

	if n < 0 or r < 0 or r > n then
		return GreaterNum.nan()
	end

	r = min(r, n - r)
	local result = GreaterNum.one()

	for i = 1, r do
		GreaterNum.muleq(result, n - r + i)
		GreaterNum.diveq(result, i)
	end

	return result
end

GreaterNum.choose = GreaterNum.combination
GreaterNum.comb = GreaterNum.combination

local function nativeUnary(value, fn): buffer
	local n = GreaterNum.toNumber(value)

	if n ~= n or n == math.huge or n == -math.huge then
		return GreaterNum.nan()
	end

	return GreaterNum.fromNumber(fn(n))
end

function GreaterNum.sin(value): buffer
	return nativeUnary(value, math.sin)
end

function GreaterNum.cos(value): buffer
	return nativeUnary(value, math.cos)
end

function GreaterNum.tan(value): buffer
	return nativeUnary(value, math.tan)
end

function GreaterNum.asin(value): buffer
	local n = GreaterNum.toNumber(value)

	if n < -1 or n > 1 then
		return GreaterNum.nan()
	end

	return GreaterNum.fromNumber(math.asin(n))
end

function GreaterNum.acos(value): buffer
	local n = GreaterNum.toNumber(value)

	if n < -1 or n > 1 then
		return GreaterNum.nan()
	end

	return GreaterNum.fromNumber(math.acos(n))
end

function GreaterNum.atan(value): buffer
	return nativeUnary(value, math.atan)
end

function GreaterNum.atan2(y, x): buffer
	local yn = GreaterNum.toNumber(y)
	local xn = GreaterNum.toNumber(x)

	if yn ~= yn or xn ~= xn then
		return GreaterNum.nan()
	end

	return GreaterNum.fromNumber(math.atan2(yn, xn))
end

function GreaterNum.sinh(value): buffer
	return nativeUnary(value, math.sinh)
end

function GreaterNum.cosh(value): buffer
	return nativeUnary(value, math.cosh)
end

function GreaterNum.tanh(value): buffer
	return nativeUnary(value, math.tanh)
end

function GreaterNum.rad(value): buffer
	return GreaterNum.mul(value, math.pi / 180)
end

function GreaterNum.deg(value): buffer
	return GreaterNum.mul(value, 180 / math.pi)
end

function GreaterNum.formatCurrency(value, symbol: string?, options): string
	symbol = symbol or "$"
	options = options or {}
	options.notation = options.notation or "auto"
	return symbol .. GreaterNum.format(value, options)
end

function GreaterNum.formatPercent(value, digits: number?): string
	return GreaterNum.format(GreaterNum.mul(value, 100), {
		notation = "auto",
		digits = digits or 2,
	}) .. "%"
end

function GreaterNum.formatRate(value, unit: string?, digits: number?): string
	return GreaterNum.format(value, {
		notation = "auto",
		digits = digits or 2,
	}) .. "/" .. (unit or "s")
end

GreaterNum.parse = GreaterNum.fromString
GreaterNum.fromtuple = GreaterNum.fromTuple
GreaterNum.roundto = GreaterNum.roundTo
GreaterNum.lerpclamped = GreaterNum.lerpClamped
GreaterNum.movetowards = GreaterNum.moveTowards
GreaterNum.canafford = GreaterNum.canAfford
GreaterNum.recipeq = function(value: buffer)
	local result = GreaterNum.recip(value)
	return GreaterNum.copy(value, result)
end

function GreaterNum.modeq(value: buffer, other): buffer
	local result = GreaterNum.mod(value, other)
	return GreaterNum.copy(value, result)
end

function GreaterNum.rooteq(value: buffer, root): buffer
	local result = GreaterNum.root(value, root)
	return GreaterNum.copy(value, result)
end

function GreaterNum.sqrteq(value: buffer): buffer
	local result = GreaterNum.sqrt(value)
	return GreaterNum.copy(value, result)
end

function GreaterNum.flooreq(value: buffer): buffer
	return GreaterNum.copy(value, GreaterNum.floor(value))
end

function GreaterNum.ceileq(value: buffer): buffer
	return GreaterNum.copy(value, GreaterNum.ceil(value))
end

function GreaterNum.roundeq(value: buffer): buffer
	return GreaterNum.copy(value, GreaterNum.round(value))
end

function GreaterNum.roundtoeq(value: buffer, step): buffer
	return GreaterNum.copy(value, GreaterNum.roundTo(value, step))
end

function GreaterNum.negeq(value: buffer): buffer
	local s = breadi8(value, S)

	if s ~= 0 then
		bwritei8(value, S, -s)
	end

	return value
end

function GreaterNum.abseq(value: buffer): buffer
	local s = breadi8(value, S)

	if s < 0 then
		bwritei8(value, S, -s)
	end

	return value
end

function GreaterNum.serialize(value): {number}
	local s,l,e = parts(value)
	return {s,l,e}
end

function GreaterNum.deserialize(data): buffer
	if type(data) ~= "table" or #data < 3 then
		error("GreaterNum.deserialize: expected {sign, layer, exponent}")
	end

	return GreaterNum.new(data[1], data[2], data[3])
end

function GreaterNum.serializeBuffer(value): buffer
	return GreaterNum.clone(value)
end

function GreaterNum.deserializeBuffer(data: buffer): buffer
	if type(data) ~= "buffer" or blen(data) ~= SIZE then
		error("GreaterNum.deserializeBuffer: expected 17-byte buffer")
	end

	return GreaterNum.clone(data)
end

function GreaterNum.encode(value): string
	return buffer.tostring(GreaterNum.toBuffer(value))
end

function GreaterNum.decode(data: string): buffer
	if type(data) ~= "string" then
		error("GreaterNum.decode: expected string")
	end

	local value = buffer.fromstring(data)

	if blen(value) ~= SIZE then
		error("GreaterNum.decode: invalid encoded GreaterNum size")
	end

	return value
end

function GreaterNum.tryDecode(data: string): (buffer?, string?)
	local ok, result = pcall(GreaterNum.decode, data)

	if ok then
		return result, nil
	end

	return nil, tostring(result)
end

function GreaterNum.bytes(): number
	return SIZE
end

function GreaterNum.version(): string
	return VERSION
end

function GreaterNum.raw(value)
	local s,l,e = parts(value)

	return {
		sign = s,
		layer = l,
		exponent = e,
	}
end

function GreaterNum.benchmark(iterations: number?)
	iterations = floor(iterations or 100000)

	local a = Fast.fromNumber(12345)
	local b = Fast.fromNumber(67890)
	local pbase = Fast.fromNumber(10)
	local pexp = Fast.fromNumber(5)
	local scratch = alloc()
	local powScratch = alloc()

	local function run(fn)
		for _ = 1, min(10000, max(100, floor(iterations / 10))) do
			fn()
		end

		local started = os.clock()

		for _ = 1, iterations do
			fn()
		end

		return (os.clock() - started) * 1e9 / iterations
	end

	return {
		version = VERSION,
		iterations = iterations,

		add = run(function() GreaterNum.add(a,b) end),
		sub = run(function() GreaterNum.sub(a,b) end),
		mul = run(function() GreaterNum.mul(a,b) end),
		div = run(function() GreaterNum.div(a,b) end),
		pow = run(function() GreaterNum.pow(pbase,pexp) end),
		log = run(function() GreaterNum.log10(a) end),
		compare = run(function() GreaterNum.compare(a,b) end),
		addeqNumber = run(function()
			Fast.copyInto(scratch, a)
			GreaterNum.addeq(scratch, 1)
		end),

		fastAdd = run(function() Fast.add(a,b) end),
		fastSub = run(function() Fast.sub(a,b) end),
		fastMul = run(function() Fast.mul(a,b) end),
		fastDiv = run(function() Fast.div(a,b) end),
		fastPow = run(function() Fast.pow(pbase,pexp) end),
		fastCompare = run(function() Fast.compare(a,b) end),

		intoAdd = run(function() Fast.addInto(scratch,a,b) end),
		intoSub = run(function() Fast.subInto(scratch,a,b) end),
		intoMul = run(function() Fast.mulInto(scratch,a,b) end),
		intoDiv = run(function() Fast.divInto(scratch,a,b) end),
		intoPow = run(function() Fast.powInto(scratch,pbase,pexp) end),
		scratchPow = run(function()
			Fast.powIntoWithScratch(scratch,powScratch,pbase,pexp)
		end),
	}
end

GreaterNum.VERSION = VERSION
GreaterNum.BUFFER_SIZE = SIZE
GreaterNum.REPRESENTATION = "Sign + Layer + Exponent"

return GreaterNum
