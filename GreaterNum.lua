--!native
--!optimize 2

local GreaterNum = {}

local Fast = {}
GreaterNum.Fast = Fast

local VERSION = "1.2.9"
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
local sqrtNative = math.sqrt
local sign = math.sign
local min = math.min
local max = math.max

local HUGE = math.huge
local strformat = string.format
local strfind = string.find
local strgsub = string.gsub
local strbyte = string.byte
local strsub = string.sub

local FIXED_FORMATS = table.create(16)
for i = 0, 15 do
	FIXED_FORMATS[i + 1] = "%." .. i .. "f"
end

local POW10_3 = table.create(31)
for i = 0, 30 do
	POW10_3[i + 1] = pow(10, i * 3)
end

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


local function notationToRawInto(out: buffer, s: number, l: number, e: number): buffer
	if s ~= s or l ~= l or e ~= e then
		return setNaN(out)
	end

	if s == 0 then
		return setZero(out)
	end

	if l < 0 then
		return setNaN(out)
	end

	if l == HUGE or abs(e) == HUGE then
		return setInf(out, s)
	end

	local rawLayer = floor(l) + 1
	local ae = abs(e)
	local rawSign = s < 0 and -1 or 1

	-- Common notation values are already canonical after the public->raw
	-- layer shift. Avoid the recursive normalizer on this hot path.
	if ae >= HIGH then
		return setRaw(out, rawSign, rawLayer + 1, sign(e) * log10(ae))
	end

	if ae >= 10 then
		return setRaw(out, rawSign, rawLayer, e)
	end

	return normalizeInto(out, rawSign, rawLayer, e)
end

local function rawToNotationParts(s: number, l: number, e: number): (number, number, number)
	if s == 0 then
		return 0, 0, 0
	end

	if l < 0 or l == HUGE then
		return s, l, e
	end

	if l == 0 then
		return s, 0, log10(e)
	end

	return s, l - 1, e
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

	-- v1.2.2: raw layer-2 x raw layer-2 is a common public-new() path.
	-- Mirror the existing fallback's OOM-dominance rule without computing
	-- transformed exponents/logs when one operand is already overwhelming.
	if l1 == 2 and l2 == 2 then
		local a1 = e1 < 0 and -e1 or e1
		local a2 = e2 < 0 and -e2 or e2
		if a1 - a2 >= OOM_CUTOFF then
			return setRaw(out, rs, 2, e1)
		elseif a2 - a1 >= OOM_CUTOFF then
			return setRaw(out, rs, 2, e2)
		end
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

	-- v1.2.2: same layer-2 dominance shortcut as multiplication. This is
	-- semantically identical to the existing fallback once the magnitude
	-- gap reaches OOM_CUTOFF, but avoids several abs/sign/log operations.
	if l1 == 2 and l2 == 2 then
		local a1 = e1 < 0 and -e1 or e1
		local a2 = e2 < 0 and -e2 or e2
		if a1 - a2 >= OOM_CUTOFF then
			return setRaw(out, rs, 2, e1)
		elseif a2 - a1 >= OOM_CUTOFF then
			return setRaw(out, rs, 2, -e2)
		end
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

local function powPartsFastInto(
	out: buffer,
	scratch: buffer?,
	s1: number, l1: number, e1: number,
	s2: number, l2: number, e2: number
): buffer
	if s1 == 0 then
		if s2 > 0 then
			return setZero(out)
		end
		return setNaN(out)
	end

	if s2 == 0 then
		return setRaw(out, 1, 0, 1)
	end

	if l2 == 0 then
		local exponent = s2 * e2

		if l1 == 0 then
			if s1 < 0 and exponent % 1 ~= 0 then
				return setNaN(out)
			end

			local n = pow(e1, exponent)
			if n == n and n ~= HUGE and n ~= 0 then
				local rs = (s1 < 0 and exponent % 2 ~= 0) and -1 or 1
				n = abs(n)

				if n >= HIGH or n <= LOW then
					return setRaw(out, rs, 1, log10(n))
				end

				return setRaw(out, rs, 0, n)
			end
		elseif l1 == 1 and s1 > 0 then
			local scale = e1 * exponent

			if scale >= 10 and scale < HIGH then
				return setRaw(out, 1, 1, scale)
			elseif scale > -10 and scale < 10 then
				local n = pow(10, scale)
				if n >= LOW and n < HIGH then
					return setRaw(out, 1, 0, n)
				end
			end
		end
	end

	return powPartsInto(out, s1,l1,e1, s2,l2,e2, scratch)
end

function Fast.new(s: number, l: number, e: number): buffer
	return notationToRawInto(alloc(), s, l, e)
end

function Fast.checkless(s: number, l: number, e: number): buffer
	return setRaw(alloc(), s, l, e)
end

function Fast.fromRawParts(s: number, l: number, e: number): buffer
	return normalizeInto(alloc(), s, l, e)
end


function Fast.fromNumber(n: number): buffer
	local out = bcreate(SIZE)

	if n > 0 then
		if n == HUGE then
			bwritei8(out, S, 1)
			bwritef64(out, L, HUGE)
			bwritef64(out, E, 1)
			return out
		end

		bwritei8(out, S, 1)

		if n >= HIGH or n <= LOW then
			bwritef64(out, L, 1)
			bwritef64(out, E, log10(n))
		else
			bwritef64(out, E, n)
		end

		return out
	end

	if n < 0 then
		if n == -HUGE then
			bwritei8(out, S, -1)
			bwritef64(out, L, HUGE)
			bwritef64(out, E, 1)
			return out
		end

		n = -n
		bwritei8(out, S, -1)

		if n >= HIGH or n <= LOW then
			bwritef64(out, L, 1)
			bwritef64(out, E, log10(n))
		else
			bwritef64(out, E, n)
		end

		return out
	end

	if n == 0 then
		return out
	end

	bwritei8(out, S, 1)
	bwritef64(out, L, -1)
	bwritef64(out, E, 1)
	return out
end

function Fast.fromNumberInto(out: buffer, n: number): buffer
	if n > 0 then
		bwritei8(out, S, 1)

		if n == HUGE then
			bwritef64(out, L, HUGE)
			bwritef64(out, E, 1)
		elseif n >= HIGH or n <= LOW then
			bwritef64(out, L, 1)
			bwritef64(out, E, log10(n))
		else
			bwritef64(out, L, 0)
			bwritef64(out, E, n)
		end

		return out
	end

	if n < 0 then
		bwritei8(out, S, -1)

		if n == -HUGE then
			bwritef64(out, L, HUGE)
			bwritef64(out, E, 1)
			return out
		end

		n = -n

		if n >= HIGH or n <= LOW then
			bwritef64(out, L, 1)
			bwritef64(out, E, log10(n))
		else
			bwritef64(out, L, 0)
			bwritef64(out, E, n)
		end

		return out
	end

	if n == 0 then
		bwritei8(out, S, 0)
		bwritef64(out, L, 0)
		bwritef64(out, E, 0)
		return out
	end

	bwritei8(out, S, 1)
	bwritef64(out, L, -1)
	bwritef64(out, E, 1)
	return out
end

function Fast.copyInto(out: buffer, value: buffer): buffer
	bcopy(out, 0, value, 0)
	return out
end

function Fast.add(a: buffer, b: buffer): buffer
	local s1 = breadi8(a, S)
	local l1 = breadf64(a, L)
	local e1 = breadf64(a, E)
	local s2 = breadi8(b, S)
	local l2 = breadf64(b, L)
	local e2 = breadf64(b, E)
	local out = bcreate(SIZE)

	if s1 == 0 then
		bwritei8(out,S,s2); bwritef64(out,L,l2); bwritef64(out,E,e2)
		return out
	elseif s2 == 0 then
		bwritei8(out,S,s1); bwritef64(out,L,l1); bwritef64(out,E,e1)
		return out
	end

	if l1 == 0 and l2 == 0 then
		local n = s1*e1 + s2*e2
		if n == 0 then return out end
		local sn = n < 0 and -1 or 1
		if n < 0 then n = -n end
		bwritei8(out,S,sn)
		if n >= HIGH or n <= LOW then
			bwritef64(out,L,1); bwritef64(out,E,log10(n))
		else
			bwritef64(out,E,n)
		end
		return out
	end

	if s1 == -s2 and l1 == l2 and e1 == e2 then
		return out
	end

	if l1 >= 2 or l2 >= 2 then
		-- Positive layered values are overwhelmingly common and can compare
		-- raw layer/exponent directly without signed-layer temporaries.
		if e1 >= 0 and e2 >= 0 then
			if l1 > l2 or (l1 == l2 and e1 > e2) then
				bwritei8(out,S,s1); bwritef64(out,L,l1); bwritef64(out,E,e1)
			else
				bwritei8(out,S,s2); bwritef64(out,L,l2); bwritef64(out,E,e2)
			end
			return out
		end

		local l1s = if e1 >= 0 then l1 else -l1
		local l2s = if e2 >= 0 then l2 else -l2
		if l1s > l2s or (l1s == l2s and e1 > e2) then
			bwritei8(out,S,s1); bwritef64(out,L,l1); bwritef64(out,E,e1)
		else
			bwritei8(out,S,s2); bwritef64(out,L,l2); bwritef64(out,E,e2)
		end
		return out
	end

	if l1 == 1 and l2 == 1 then
		if e1 - e2 >= OOM_CUTOFF then
			bwritei8(out,S,s1); bwritef64(out,L,1); bwritef64(out,E,e1)
			return out
		elseif e2 - e1 >= OOM_CUTOFF then
			bwritei8(out,S,s2); bwritef64(out,L,1); bwritef64(out,E,e2)
			return out
		end
	end

	return signedAddPartsInto(out,s1,l1,e1,s2,l2,e2)
end

function Fast.sub(a: buffer, b: buffer): buffer
	local s1 = breadi8(a,S)
	local l1 = breadf64(a,L)
	local e1 = breadf64(a,E)
	local s2 = breadi8(b,S)
	local l2 = breadf64(b,L)
	local e2 = breadf64(b,E)
	local out = bcreate(SIZE)

	if s1 == 0 then
		bwritei8(out,S,-s2); bwritef64(out,L,l2); bwritef64(out,E,e2)
		return out
	elseif s2 == 0 then
		bwritei8(out,S,s1); bwritef64(out,L,l1); bwritef64(out,E,e1)
		return out
	end

	if l1 == 0 and l2 == 0 then
		local n = s1*e1 - s2*e2
		if n == 0 then return out end
		local sn = n < 0 and -1 or 1
		if n < 0 then n = -n end
		bwritei8(out,S,sn)
		if n >= HIGH or n <= LOW then
			bwritef64(out,L,1); bwritef64(out,E,log10(n))
		else
			bwritef64(out,E,n)
		end
		return out
	end

	if s1 == s2 and l1 == l2 and e1 == e2 then
		return out
	end

	if l1 >= 2 or l2 >= 2 then
		if e1 >= 0 and e2 >= 0 then
			if l1 > l2 or (l1 == l2 and e1 > e2) then
				bwritei8(out,S,s1); bwritef64(out,L,l1); bwritef64(out,E,e1)
			else
				bwritei8(out,S,-s2); bwritef64(out,L,l2); bwritef64(out,E,e2)
			end
			return out
		end

		local l1s = if e1 >= 0 then l1 else -l1
		local l2s = if e2 >= 0 then l2 else -l2
		if l1s > l2s or (l1s == l2s and e1 > e2) then
			bwritei8(out,S,s1); bwritef64(out,L,l1); bwritef64(out,E,e1)
		else
			bwritei8(out,S,-s2); bwritef64(out,L,l2); bwritef64(out,E,e2)
		end
		return out
	end

	if l1 == 1 and l2 == 1 then
		if e1 - e2 >= OOM_CUTOFF then
			bwritei8(out,S,s1); bwritef64(out,L,1); bwritef64(out,E,e1)
			return out
		elseif e2 - e1 >= OOM_CUTOFF then
			bwritei8(out,S,-s2); bwritef64(out,L,1); bwritef64(out,E,e2)
			return out
		end
	end

	return signedAddPartsInto(out,s1,l1,e1,-s2,l2,e2)
end

function Fast.mul(a: buffer, b: buffer): buffer
	local s1 = breadi8(a,S)
	local l1 = breadf64(a,L)
	local e1 = breadf64(a,E)
	local s2 = breadi8(b,S)
	local l2 = breadf64(b,L)
	local e2 = breadf64(b,E)
	local out = bcreate(SIZE)

	if s1 == 0 or s2 == 0 then return out end
	local rs = s1*s2

	if l1 == 0 and l2 == 0 then
		local n = e1*e2
		bwritei8(out,S,rs)
		if n >= HIGH or n <= LOW then
			bwritef64(out,L,1); bwritef64(out,E,log10(n))
		else
			bwritef64(out,E,n)
		end
		return out
	end

	if l1 == 2 and l2 == 2 then
		local d
		if e1 >= 0 and e2 >= 0 then
			d = e1 - e2
		else
			d = abs(e1) - abs(e2)
		end
		if d >= OOM_CUTOFF then
			bwritei8(out,S,rs); bwritef64(out,L,2); bwritef64(out,E,e1)
			return out
		elseif d <= -OOM_CUTOFF then
			bwritei8(out,S,rs); bwritef64(out,L,2); bwritef64(out,E,e2)
			return out
		end
	end

	if l1 == 1 and l2 == 1 then
		local scale = e1+e2
		if scale >= 10 and scale < HIGH then
			bwritei8(out,S,rs); bwritef64(out,L,1); bwritef64(out,E,scale)
			return out
		elseif scale > -10 and scale < 10 then
			local n = pow(10,scale)
			if n >= LOW and n < HIGH then
				bwritei8(out,S,rs); bwritef64(out,E,n)
				return out
			end
		end
	end

	if l1 == 1 and l2 == 0 then
		local scale = e1 + log10(e2)
		if scale >= 10 and scale < HIGH then
			bwritei8(out,S,rs); bwritef64(out,L,1); bwritef64(out,E,scale)
			return out
		end
	elseif l1 == 0 and l2 == 1 then
		local scale = log10(e1) + e2
		if scale >= 10 and scale < HIGH then
			bwritei8(out,S,rs); bwritef64(out,L,1); bwritef64(out,E,scale)
			return out
		end
	end

	return mulPartsInto(out,s1,l1,e1,s2,l2,e2)
end

function Fast.div(a: buffer, b: buffer): buffer
	local s1 = breadi8(a,S)
	local l1 = breadf64(a,L)
	local e1 = breadf64(a,E)
	local s2 = breadi8(b,S)
	local l2 = breadf64(b,L)
	local e2 = breadf64(b,E)
	local out = bcreate(SIZE)

	if s2 == 0 then
		bwritei8(out,S,1); bwritef64(out,L,-1); bwritef64(out,E,1)
		return out
	elseif s1 == 0 then
		return out
	end

	local rs = s1*s2
	if l1 == 0 and l2 == 0 then
		local n = e1/e2
		bwritei8(out,S,rs)
		if n >= HIGH or n <= LOW then
			bwritef64(out,L,1); bwritef64(out,E,log10(n))
		else
			bwritef64(out,E,n)
		end
		return out
	end

	if l1 == l2 and e1 == e2 then
		bwritei8(out,S,rs); bwritef64(out,E,1)
		return out
	end

	if l1 == 2 and l2 == 2 then
		local d
		if e1 >= 0 and e2 >= 0 then
			d = e1 - e2
		else
			d = abs(e1) - abs(e2)
		end
		if d >= OOM_CUTOFF then
			bwritei8(out,S,rs); bwritef64(out,L,2); bwritef64(out,E,e1)
			return out
		elseif d <= -OOM_CUTOFF then
			bwritei8(out,S,rs); bwritef64(out,L,2); bwritef64(out,E,-e2)
			return out
		end
	end

	if l1 == 1 and l2 == 1 then
		local scale = e1-e2
		if scale >= 10 and scale < HIGH then
			bwritei8(out,S,rs); bwritef64(out,L,1); bwritef64(out,E,scale)
			return out
		elseif scale > -10 and scale < 10 then
			local n = pow(10,scale)
			if n >= LOW and n < HIGH then
				bwritei8(out,S,rs); bwritef64(out,E,n)
				return out
			end
		end
	end

	if l1 == 1 and l2 == 0 then
		local scale = e1 - log10(e2)
		if scale >= 10 and scale < HIGH then
			bwritei8(out,S,rs); bwritef64(out,L,1); bwritef64(out,E,scale)
			return out
		end
	elseif l1 == 0 and l2 == 1 then
		local scale = log10(e1) - e2
		if scale >= 10 and scale < HIGH then
			bwritei8(out,S,rs); bwritef64(out,L,1); bwritef64(out,E,scale)
			return out
		end
	end

	return divPartsInto(out,s1,l1,e1,s2,l2,e2)
end

function Fast.pow(a: buffer, b: buffer): buffer
	local s1 = breadi8(a,S)
	local l1 = breadf64(a,L)
	local e1 = breadf64(a,E)
	local s2 = breadi8(b,S)
	local l2 = breadf64(b,L)
	local e2 = breadf64(b,E)
	local out = bcreate(SIZE)

	if s1 == 0 then
		if s2 > 0 then return out end
		bwritei8(out,S,1); bwritef64(out,L,-1); bwritef64(out,E,1)
		return out
	end
	if s2 == 0 then
		bwritei8(out,S,1); bwritef64(out,E,1)
		return out
	end

	if l2 == 0 then
		local exponent = s2*e2
		if l1 == 0 then
			if s1 < 0 and exponent % 1 ~= 0 then
				bwritei8(out,S,1); bwritef64(out,L,-1); bwritef64(out,E,1)
				return out
			end
			local n = pow(e1,exponent)
			if n == n and n ~= HUGE and n ~= 0 then
				local rs = (s1 < 0 and exponent % 2 ~= 0) and -1 or 1
				bwritei8(out,S,rs)
				if n >= HIGH or n <= LOW then
					bwritef64(out,L,1); bwritef64(out,E,log10(n))
				else
					bwritef64(out,E,n)
				end
				return out
			end
		elseif l1 == 1 and s1 > 0 then
			local scale = e1*exponent
			if scale >= 10 and scale < HIGH then
				bwritei8(out,S,1); bwritef64(out,L,1); bwritef64(out,E,scale)
				return out
			elseif scale > -10 and scale < 10 then
				local n = pow(10,scale)
				if n >= LOW and n < HIGH then
					bwritei8(out,S,1); bwritef64(out,E,n)
					return out
				end
			end
		end
	end

	return powPartsInto(out,s1,l1,e1,s2,l2,e2)
end

function Fast.addInto(out: buffer, a: buffer, b: buffer): buffer
	local s1 = breadi8(a, S)
	local l1 = breadf64(a, L)
	local e1 = breadf64(a, E)
	local s2 = breadi8(b, S)
	local l2 = breadf64(b, L)
	local e2 = breadf64(b, E)

	if l1 == 0 and l2 == 0 then
		local n = s1 * e1 + s2 * e2
		if n == 0 then
			bwritei8(out, S, 0)
			bwritef64(out, L, 0)
			bwritef64(out, E, 0)
			return out
		end

		local rs = 1
		if n < 0 then
			rs = -1
			n = -n
		end
		bwritei8(out, S, rs)
		if n >= HIGH or n <= LOW then
			bwritef64(out, L, 1)
			bwritef64(out, E, log10(n))
		else
			bwritef64(out, L, 0)
			bwritef64(out, E, n)
		end
		return out
	end

	return signedAddPartsInto(out, s1,l1,e1, s2,l2,e2)
end

function Fast.subInto(out: buffer, a: buffer, b: buffer): buffer
	local s1 = breadi8(a, S)
	local l1 = breadf64(a, L)
	local e1 = breadf64(a, E)
	local s2 = breadi8(b, S)
	local l2 = breadf64(b, L)
	local e2 = breadf64(b, E)

	if l1 == 0 and l2 == 0 then
		local n = s1 * e1 - s2 * e2
		if n == 0 then
			bwritei8(out, S, 0)
			bwritef64(out, L, 0)
			bwritef64(out, E, 0)
			return out
		end

		local rs = 1
		if n < 0 then
			rs = -1
			n = -n
		end
		bwritei8(out, S, rs)
		if n >= HIGH or n <= LOW then
			bwritef64(out, L, 1)
			bwritef64(out, E, log10(n))
		else
			bwritef64(out, L, 0)
			bwritef64(out, E, n)
		end
		return out
	end

	return signedAddPartsInto(out, s1,l1,e1, -s2,l2,e2)
end

function Fast.mulInto(out: buffer, a: buffer, b: buffer): buffer
	local s1 = breadi8(a, S)
	local l1 = breadf64(a, L)
	local e1 = breadf64(a, E)
	local s2 = breadi8(b, S)
	local l2 = breadf64(b, L)
	local e2 = breadf64(b, E)

	if s1 == 0 or s2 == 0 then
		bwritei8(out, S, 0)
		bwritef64(out, L, 0)
		bwritef64(out, E, 0)
		return out
	end

	if l1 == 0 and l2 == 0 then
		local n = e1 * e2
		local rs = s1 * s2
		bwritei8(out, S, rs)
		if n >= HIGH or n <= LOW then
			bwritef64(out, L, 1)
			bwritef64(out, E, log10(n))
		else
			bwritef64(out, L, 0)
			bwritef64(out, E, n)
		end
		return out
	end

	return mulPartsInto(out, s1,l1,e1, s2,l2,e2)
end

function Fast.divInto(out: buffer, a: buffer, b: buffer): buffer
	local s1 = breadi8(a, S)
	local l1 = breadf64(a, L)
	local e1 = breadf64(a, E)
	local s2 = breadi8(b, S)
	local l2 = breadf64(b, L)
	local e2 = breadf64(b, E)

	if s2 == 0 then
		bwritei8(out, S, 1)
		bwritef64(out, L, -1)
		bwritef64(out, E, 1)
		return out
	end
	if s1 == 0 then
		bwritei8(out, S, 0)
		bwritef64(out, L, 0)
		bwritef64(out, E, 0)
		return out
	end

	if l1 == 0 and l2 == 0 then
		local n = e1 / e2
		local rs = s1 * s2
		bwritei8(out, S, rs)
		if n >= HIGH or n <= LOW then
			bwritef64(out, L, 1)
			bwritef64(out, E, log10(n))
		else
			bwritef64(out, L, 0)
			bwritef64(out, E, n)
		end
		return out
	end

	return divPartsInto(out, s1,l1,e1, s2,l2,e2)
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

	return powPartsFastInto(
		out,
		scratch,
		breadi8(a, S), breadf64(a, L), breadf64(a, E),
		breadi8(b, S), breadf64(b, L), breadf64(b, E)
	)
end

function Fast.addeq(a: buffer, b: buffer): buffer
	local s1 = breadi8(a, S)
	local l1 = breadf64(a, L)
	local e1 = breadf64(a, E)
	local s2 = breadi8(b, S)
	local l2 = breadf64(b, L)
	local e2 = breadf64(b, E)

	if s2 == 0 then
		return a
	end

	if s1 == 0 then
		bwritei8(a, S, s2)
		bwritef64(a, L, l2)
		bwritef64(a, E, e2)
		return a
	end

	if l1 == 0 and l2 == 0 then
		local n = s1 * e1 + s2 * e2

		if n == 0 then
			bwritei8(a, S, 0)
			bwritef64(a, L, 0)
			bwritef64(a, E, 0)
			return a
		end

		local sn
		if n < 0 then
			sn = -1
			n = -n
		else
			sn = 1
		end

		bwritei8(a, S, sn)

		if n >= HIGH or n <= LOW then
			bwritef64(a, L, 1)
			bwritef64(a, E, log10(n))
		else
			bwritef64(a, L, 0)
			bwritef64(a, E, n)
		end

		return a
	end

	return signedAddPartsInto(a, s1,l1,e1, s2,l2,e2)
end

function Fast.copyAddInto(out: buffer, source: buffer, addend: buffer): buffer
	local s1 = breadi8(source, S)
	local l1 = breadf64(source, L)
	local e1 = breadf64(source, E)
	local s2 = breadi8(addend, S)
	local l2 = breadf64(addend, L)
	local e2 = breadf64(addend, E)

	if s2 == 0 then
		bwritei8(out, S, s1)
		bwritef64(out, L, l1)
		bwritef64(out, E, e1)
		return out
	end

	if s1 == 0 then
		bwritei8(out, S, s2)
		bwritef64(out, L, l2)
		bwritef64(out, E, e2)
		return out
	end

	if l1 == 0 and l2 == 0 then
		local n = s1 * e1 + s2 * e2

		if n == 0 then
			bwritei8(out, S, 0)
			bwritef64(out, L, 0)
			bwritef64(out, E, 0)
			return out
		end

		local sn
		if n < 0 then
			sn = -1
			n = -n
		else
			sn = 1
		end

		bwritei8(out, S, sn)

		if n >= HIGH or n <= LOW then
			bwritef64(out, L, 1)
			bwritef64(out, E, log10(n))
		else
			bwritef64(out, L, 0)
			bwritef64(out, E, n)
		end

		return out
	end

	return signedAddPartsInto(out, s1,l1,e1, s2,l2,e2)
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
	local s1 = breadi8(a, S)
	local s2 = breadi8(b, S)
	if s1 ~= s2 then return s1 < s2 end
	if s1 == 0 then return false end

	local l1 = breadf64(a, L)
	local l2 = breadf64(b, L)
	local e1 = breadf64(a, E)
	local e2 = breadf64(b, E)

	if e1 >= 0 and e2 >= 0 then
		if l1 ~= l2 then
			return if s1 > 0 then l1 < l2 else l1 > l2
		end
		return if s1 > 0 then e1 < e2 else e1 > e2
	end
	return rawCompare(s1,l1,e1,s2,l2,e2) < 0
end

function Fast.gt(a: buffer, b: buffer): boolean
	local s1 = breadi8(a, S)
	local s2 = breadi8(b, S)
	if s1 ~= s2 then return s1 > s2 end
	if s1 == 0 then return false end

	local l1 = breadf64(a, L)
	local l2 = breadf64(b, L)
	local e1 = breadf64(a, E)
	local e2 = breadf64(b, E)

	if e1 >= 0 and e2 >= 0 then
		if l1 ~= l2 then
			return if s1 > 0 then l1 > l2 else l1 < l2
		end
		return if s1 > 0 then e1 > e2 else e1 < e2
	end
	return rawCompare(s1,l1,e1,s2,l2,e2) > 0
end

function Fast.compare(a: buffer, b: buffer): number
	local s1 = breadi8(a, S)
	local s2 = breadi8(b, S)
	if s1 ~= s2 then return if s1 < s2 then -1 else 1 end
	if s1 == 0 then return 0 end

	local l1 = breadf64(a, L)
	local l2 = breadf64(b, L)
	local e1 = breadf64(a, E)
	local e2 = breadf64(b, E)

	if e1 >= 0 and e2 >= 0 then
		if l1 ~= l2 then
			local r = if l1 < l2 then -1 else 1
			return if s1 < 0 then -r else r
		end
		if e1 ~= e2 then
			local r = if e1 < e2 then -1 else 1
			return if s1 < 0 then -r else r
		end
		return 0
	end
	return rawCompare(s1,l1,e1,s2,l2,e2)
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

function Fast.log10(a: buffer): buffer
	local s = breadi8(a, S)
	local l = breadf64(a, L)
	local e = breadf64(a, E)
	local out = bcreate(SIZE)

	if s <= 0 or l < 0 then
		bwritei8(out, S, 1)
		bwritef64(out, L, -1)
		bwritef64(out, E, 1)
		return out
	end

	if l == HUGE then
		bwritei8(out, S, 1)
		bwritef64(out, L, HUGE)
		bwritef64(out, E, 1)
		return out
	end

	if l > 0 then
		if e < 0 then
			bwritei8(out, S, -1)
			bwritef64(out, L, l - 1)
			bwritef64(out, E, -e)
		else
			bwritei8(out, S, 1)
			bwritef64(out, L, l - 1)
			bwritef64(out, E, e)
		end
		return out
	end

	if e == 1 then
		return out
	end

	local n = log10(e)

	if n < 0 then
		bwritei8(out, S, -1)
		bwritef64(out, E, -n)
	elseif n > 0 then
		bwritei8(out, S, 1)
		bwritef64(out, E, n)
	end

	return out
end

function Fast.log10Into(out: buffer, a: buffer): buffer
	local s = breadi8(a, S)
	local l = breadf64(a, L)
	local e = breadf64(a, E)

	if s <= 0 or l < 0 then
		bwritei8(out, S, 1)
		bwritef64(out, L, -1)
		bwritef64(out, E, 1)
		return out
	end

	if l == HUGE then
		bwritei8(out, S, 1)
		bwritef64(out, L, HUGE)
		bwritef64(out, E, 1)
		return out
	end

	if l > 0 then
		bwritef64(out, L, l - 1)

		if e < 0 then
			bwritei8(out, S, -1)
			bwritef64(out, E, -e)
		else
			bwritei8(out, S, 1)
			bwritef64(out, E, e)
		end

		return out
	end

	if e == 1 then
		bwritei8(out, S, 0)
		bwritef64(out, L, 0)
		bwritef64(out, E, 0)
		return out
	end

	local n = log10(e)
	bwritef64(out, L, 0)

	if n < 0 then
		bwritei8(out, S, -1)
		bwritef64(out, E, -n)
	elseif n > 0 then
		bwritei8(out, S, 1)
		bwritef64(out, E, n)
	else
		bwritei8(out, S, 0)
		bwritef64(out, E, 0)
	end

	return out
end

function GreaterNum.new(s: number, l: number, e: number): buffer
	if type(s) ~= "number" or type(l) ~= "number" or type(e) ~= "number" then
		error("GreaterNum.new: expected (sign: number, layer: number, exponent: number)")
	end

	local out = bcreate(SIZE)

	-- v1.2.8 ultra-hot canonical notation paths.
	-- These are the common new(1,0,e) / new(1,1,e) cases used by games
	-- and benchmarks. They preserve public notation-layer semantics exactly:
	-- notation layer N => raw layer N + 1.
	if s ~= 0 and e == e and e >= 10 and e < HIGH then
		local rs = if s < 0 then -1 else 1

		if l == 0 then
			bwritei8(out, S, rs)
			bwritef64(out, L, 1)
			bwritef64(out, E, e)
			return out
		elseif l == 1 then
			bwritei8(out, S, rs)
			bwritef64(out, L, 2)
			bwritef64(out, E, e)
			return out
		elseif l == 2 then
			bwritei8(out, S, rs)
			bwritef64(out, L, 3)
			bwritef64(out, E, e)
			return out
		end
	end

	-- Negative canonical exponent hot paths.
	if s ~= 0 and e == e and e <= -10 and e > -HIGH then
		local rs = if s < 0 then -1 else 1

		if l == 0 then
			bwritei8(out, S, rs)
			bwritef64(out, L, 1)
			bwritef64(out, E, e)
			return out
		elseif l == 1 then
			bwritei8(out, S, rs)
			bwritef64(out, L, 2)
			bwritef64(out, E, e)
			return out
		elseif l == 2 then
			bwritei8(out, S, rs)
			bwritef64(out, L, 3)
			bwritef64(out, E, e)
			return out
		end
	end

	-- General canonical layered notation path. Only uncommon layer values pay
	-- floor()/abs() and the generic normalizer remains the final authority.
	if s ~= 0 and s == s and l == l and e == e and l >= 0 and l ~= HUGE then
		local ae = if e < 0 then -e else e
		if ae >= 10 and ae < HIGH then
			bwritei8(out, S, if s < 0 then -1 else 1)
			bwritef64(out, L, floor(l) + 1)
			bwritef64(out, E, e)
			return out
		end
	end

	return notationToRawInto(out, s, l, e)
end

GreaterNum.fromParts = GreaterNum.new

function GreaterNum.fromRawParts(s: number, l: number, e: number): buffer
	if type(s) ~= "number" or type(l) ~= "number" or type(e) ~= "number" then
		error("GreaterNum.fromRawParts: expected (sign: number, rawLayer: number, rawExponent: number)")
	end

	return normalizeInto(alloc(), s, l, e)
end


function GreaterNum.createCheckless(s: number, l: number, e: number): buffer
	return setRaw(alloc(), s, l, e)
end

function GreaterNum.fromNumber(n: number): buffer
	if type(n) ~= "number" then
		error("GreaterNum.fromNumber: expected number")
	end

	local out = bcreate(SIZE)

	if n > 0 then
		if n == HUGE then
			bwritei8(out, S, 1)
			bwritef64(out, L, HUGE)
			bwritef64(out, E, 1)
			return out
		end

		bwritei8(out, S, 1)

		if n >= HIGH or n <= LOW then
			bwritef64(out, L, 1)
			bwritef64(out, E, log10(n))
		else
			bwritef64(out, E, n)
		end

		return out
	end

	if n < 0 then
		if n == -HUGE then
			bwritei8(out, S, -1)
			bwritef64(out, L, HUGE)
			bwritef64(out, E, 1)
			return out
		end

		n = -n
		bwritei8(out, S, -1)

		if n >= HIGH or n <= LOW then
			bwritef64(out, L, 1)
			bwritef64(out, E, log10(n))
		else
			bwritef64(out, E, n)
		end

		return out
	end

	if n == 0 then
		return out
	end

	bwritei8(out, S, 1)
	bwritef64(out, L, -1)
	bwritef64(out, E, 1)
	return out
end

function GreaterNum.fromScientific(mantissa: number, exponent: number): buffer
	if type(mantissa) ~= "number" then
		error("GreaterNum.fromScientific: expected number for mantissa")
	end
	if type(exponent) ~= "number" then
		error("GreaterNum.fromScientific: expected number for exponent")
	end

	-- v1.2.8 finite hot path: common scientific values skip all exceptional
	-- checks, sign helpers, normalization and secondary constructors.
	if mantissa > 0 and mantissa < HUGE and exponent == exponent and exponent > -HUGE and exponent < HUGE then
		local out = bcreate(SIZE)

		if exponent == 0 then
			bwritei8(out, S, 1)
			if mantissa >= HIGH or mantissa <= LOW then
				bwritef64(out, L, 1)
				bwritef64(out, E, log10(mantissa))
			else
				bwritef64(out, E, mantissa)
			end
			return out
		end

		local scale = if mantissa == 1 then exponent else exponent + log10(mantissa)
		if scale == HUGE then
			bwritei8(out, S, 1)
			bwritef64(out, L, HUGE)
			bwritef64(out, E, 1)
			return out
		elseif scale == -HUGE then
			return out
		end

		if scale >= 10 and scale < HIGH then
			bwritei8(out, S, 1)
			bwritef64(out, L, 1)
			bwritef64(out, E, scale)
			return out
		elseif scale <= -10 and scale > -HIGH then
			bwritei8(out, S, 1)
			bwritef64(out, L, 1)
			bwritef64(out, E, scale)
			return out
		elseif scale > -10 and scale < 10 then
			bwritei8(out, S, 1)
			bwritef64(out, E, pow(10, scale))
			return out
		end

		local aScale = if scale < 0 then -scale else scale
		bwritei8(out, S, 1)
		bwritef64(out, L, 2)
		bwritef64(out, E, (if scale < 0 then -1 else 1) * log10(aScale))
		return out
	end

	-- Symmetric negative finite hot path.
	if mantissa < 0 and mantissa > -HUGE and exponent == exponent and exponent > -HUGE and exponent < HUGE then
		local magnitude = -mantissa
		local out = bcreate(SIZE)

		if exponent == 0 then
			bwritei8(out, S, -1)
			if magnitude >= HIGH or magnitude <= LOW then
				bwritef64(out, L, 1)
				bwritef64(out, E, log10(magnitude))
			else
				bwritef64(out, E, magnitude)
			end
			return out
		end

		local scale = if magnitude == 1 then exponent else exponent + log10(magnitude)
		if scale == HUGE then
			bwritei8(out, S, -1)
			bwritef64(out, L, HUGE)
			bwritef64(out, E, 1)
			return out
		elseif scale == -HUGE then
			return out
		end

		if scale >= 10 and scale < HIGH then
			bwritei8(out, S, -1)
			bwritef64(out, L, 1)
			bwritef64(out, E, scale)
			return out
		elseif scale <= -10 and scale > -HIGH then
			bwritei8(out, S, -1)
			bwritef64(out, L, 1)
			bwritef64(out, E, scale)
			return out
		elseif scale > -10 and scale < 10 then
			bwritei8(out, S, -1)
			bwritef64(out, E, pow(10, scale))
			return out
		end

		local aScale = if scale < 0 then -scale else scale
		bwritei8(out, S, -1)
		bwritef64(out, L, 2)
		bwritef64(out, E, (if scale < 0 then -1 else 1) * log10(aScale))
		return out
	end

	local out = bcreate(SIZE)

	if mantissa ~= mantissa or exponent ~= exponent then
		bwritei8(out, S, 1)
		bwritef64(out, L, -1)
		bwritef64(out, E, 1)
		return out
	end

	if mantissa == 0 then
		if exponent == HUGE then
			bwritei8(out, S, 1)
			bwritef64(out, L, -1)
			bwritef64(out, E, 1)
		end
		return out
	end

	local s = if mantissa < 0 then -1 else 1
	local magnitude = if mantissa < 0 then -mantissa else mantissa

	if magnitude == HUGE then
		if exponent == -HUGE then
			bwritei8(out, S, 1)
			bwritef64(out, L, -1)
			bwritef64(out, E, 1)
			return out
		end
		bwritei8(out, S, s)
		bwritef64(out, L, HUGE)
		bwritef64(out, E, 1)
		return out
	end

	if exponent == HUGE then
		bwritei8(out, S, s)
		bwritef64(out, L, HUGE)
		bwritef64(out, E, 1)
		return out
	elseif exponent == -HUGE then
		return out
	end

	local scale = if magnitude == 1 then exponent else exponent + log10(magnitude)
	local scaleAbs = if scale < 0 then -scale else scale
	bwritei8(out, S, s)

	if scaleAbs < 10 then
		bwritef64(out, E, pow(10, scale))
		return out
	end

	if scaleAbs >= HIGH then
		bwritef64(out, L, 2)
		bwritef64(out, E, (if scale < 0 then -1 else 1) * log10(scaleAbs))
		return out
	end

	bwritef64(out, L, 1)
	bwritef64(out, E, scale)
	return out
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
		local out = bcreate(SIZE)
		bcopy(out, 0, v, 0, SIZE)
		return out
	end

	local s, l, e = parts(v)
	local out = bcreate(SIZE)
	bwritei8(out, S, s)
	bwritef64(out, L, l)
	bwritef64(out, E, e)
	return out
end

function GreaterNum.tuple(v): (number, number, number)
	if type(v) == "buffer" then
		local l = breadf64(v, L)
		local s = breadi8(v, S)

		-- Canonical non-zero layered values dominate normal gameplay.
		if s ~= 0 and l > 0 and l < HUGE then
			return s, l - 1, breadf64(v, E)
		end

		if s == 0 then
			return 0, 0, 0
		end

		local e = breadf64(v, E)
		if l < 0 or l == HUGE then
			return s, l, e
		end

		return s, 0, log10(e)
	end

	local s,l,e = parts(v)
	return rawToNotationParts(s,l,e)
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
	return notationToRawInto(out, s, l, e)
end

function GreaterNum.setCheckless(out: buffer, s: number, l: number, e: number): buffer
	return setRaw(out, s, l, e)
end

function GreaterNum.setRawParts(out: buffer, s: number, l: number, e: number): buffer
	return normalizeInto(out, s, l, e)
end


function GreaterNum.setFromNumber(out: buffer, n: number): buffer
	return Fast.fromNumberInto(out, n)
end

function GreaterNum.copy(out: buffer, source: buffer): buffer
	bcopy(out, 0, source, 0)
	return out
end

function GreaterNum.add(a, b): buffer
	if type(a) == "buffer" and type(b) == "buffer" then
		local s1 = breadi8(a,S); local l1 = breadf64(a,L); local e1 = breadf64(a,E)
		local s2 = breadi8(b,S); local l2 = breadf64(b,L); local e2 = breadf64(b,E)
		local out = bcreate(SIZE)

		if s1 == 0 then bwritei8(out,S,s2); bwritef64(out,L,l2); bwritef64(out,E,e2); return out end
		if s2 == 0 then bwritei8(out,S,s1); bwritef64(out,L,l1); bwritef64(out,E,e1); return out end

		if l1 == 0 and l2 == 0 then
			local n = s1*e1 + s2*e2
			if n == 0 then return out end
			local sn = n < 0 and -1 or 1
			if n < 0 then n = -n end
			bwritei8(out,S,sn)
			if n >= HIGH or n <= LOW then bwritef64(out,L,1); bwritef64(out,E,log10(n)) else bwritef64(out,E,n) end
			return out
		end

		if l1 >= 2 or l2 >= 2 then
			if e1 >= 0 and e2 >= 0 then
				if l1 > l2 or (l1 == l2 and e1 > e2) then
					bwritei8(out,S,s1); bwritef64(out,L,l1); bwritef64(out,E,e1)
				else
					bwritei8(out,S,s2); bwritef64(out,L,l2); bwritef64(out,E,e2)
				end
				return out
			end
			local l1s = if e1 >= 0 then l1 else -l1
			local l2s = if e2 >= 0 then l2 else -l2
			if l1s > l2s or (l1s == l2s and e1 > e2) then
				bwritei8(out,S,s1); bwritef64(out,L,l1); bwritef64(out,E,e1)
			else
				bwritei8(out,S,s2); bwritef64(out,L,l2); bwritef64(out,E,e2)
			end
			return out
		end

		if l1 == 1 and l2 == 1 then
			if e1-e2 >= OOM_CUTOFF then bwritei8(out,S,s1); bwritef64(out,L,1); bwritef64(out,E,e1); return out end
			if e2-e1 >= OOM_CUTOFF then bwritei8(out,S,s2); bwritef64(out,L,1); bwritef64(out,E,e2); return out end
		end
		return signedAddPartsInto(out,s1,l1,e1,s2,l2,e2)
	end

	local s1,l1,e1 = parts(a)
	local s2,l2,e2 = parts(b)
	return signedAddPartsInto(alloc(),s1,l1,e1,s2,l2,e2)
end

function GreaterNum.sub(a, b): buffer
	if type(a) == "buffer" and type(b) == "buffer" then
		local s1 = breadi8(a,S); local l1 = breadf64(a,L); local e1 = breadf64(a,E)
		local s2 = breadi8(b,S); local l2 = breadf64(b,L); local e2 = breadf64(b,E)
		local out = bcreate(SIZE)

		if s1 == 0 then bwritei8(out,S,-s2); bwritef64(out,L,l2); bwritef64(out,E,e2); return out end
		if s2 == 0 then bwritei8(out,S,s1); bwritef64(out,L,l1); bwritef64(out,E,e1); return out end

		if l1 == 0 and l2 == 0 then
			local n = s1*e1 - s2*e2
			if n == 0 then return out end
			local sn = n < 0 and -1 or 1
			if n < 0 then n = -n end
			bwritei8(out,S,sn)
			if n >= HIGH or n <= LOW then bwritef64(out,L,1); bwritef64(out,E,log10(n)) else bwritef64(out,E,n) end
			return out
		end

		if l1 >= 2 or l2 >= 2 then
			if e1 >= 0 and e2 >= 0 then
				if l1 > l2 or (l1 == l2 and e1 > e2) then
					bwritei8(out,S,s1); bwritef64(out,L,l1); bwritef64(out,E,e1)
				else
					bwritei8(out,S,-s2); bwritef64(out,L,l2); bwritef64(out,E,e2)
				end
				return out
			end
			local l1s = if e1 >= 0 then l1 else -l1
			local l2s = if e2 >= 0 then l2 else -l2
			if l1s > l2s or (l1s == l2s and e1 > e2) then
				bwritei8(out,S,s1); bwritef64(out,L,l1); bwritef64(out,E,e1)
			else
				bwritei8(out,S,-s2); bwritef64(out,L,l2); bwritef64(out,E,e2)
			end
			return out
		end

		if l1 == 1 and l2 == 1 then
			if e1-e2 >= OOM_CUTOFF then bwritei8(out,S,s1); bwritef64(out,L,1); bwritef64(out,E,e1); return out end
			if e2-e1 >= OOM_CUTOFF then bwritei8(out,S,-s2); bwritef64(out,L,1); bwritef64(out,E,e2); return out end
		end
		return signedAddPartsInto(out,s1,l1,e1,-s2,l2,e2)
	end

	local s1,l1,e1 = parts(a)
	local s2,l2,e2 = parts(b)
	return signedAddPartsInto(alloc(),s1,l1,e1,-s2,l2,e2)
end

function GreaterNum.mul(a, b): buffer
	if type(a) == "buffer" and type(b) == "buffer" then
		local s1 = breadi8(a,S); local l1 = breadf64(a,L); local e1 = breadf64(a,E)
		local s2 = breadi8(b,S); local l2 = breadf64(b,L); local e2 = breadf64(b,E)
		local out = bcreate(SIZE)
		if s1 == 0 or s2 == 0 then return out end
		local rs = s1*s2

		if l1 == 0 and l2 == 0 then
			local n = e1*e2
			bwritei8(out,S,rs)
			if n >= HIGH or n <= LOW then bwritef64(out,L,1); bwritef64(out,E,log10(n)) else bwritef64(out,E,n) end
			return out
		end
		if l1 >= 3 or l2 >= 3 or (l1 == 2 and l2 == 0) or (l2 == 2 and l1 == 0) then
			if l1 > l2 then
				bwritei8(out,S,rs); bwritef64(out,L,l1); bwritef64(out,E,e1)
			elseif l2 > l1 then
				bwritei8(out,S,rs); bwritef64(out,L,l2); bwritef64(out,E,e2)
			elseif abs(e1) >= abs(e2) then
				bwritei8(out,S,rs); bwritef64(out,L,l1); bwritef64(out,E,e1)
			else
				bwritei8(out,S,rs); bwritef64(out,L,l2); bwritef64(out,E,e2)
			end
			return out
		end

		if l1 == 2 and l2 == 2 then
			local d = if e1 >= 0 and e2 >= 0 then e1 - e2 else abs(e1) - abs(e2)
			if d >= OOM_CUTOFF then bwritei8(out,S,rs); bwritef64(out,L,2); bwritef64(out,E,e1); return out end
			if d <= -OOM_CUTOFF then bwritei8(out,S,rs); bwritef64(out,L,2); bwritef64(out,E,e2); return out end
		end

		if l1 == 1 and l2 == 1 then
			local scale = e1+e2
			if scale >= 10 and scale < HIGH then bwritei8(out,S,rs); bwritef64(out,L,1); bwritef64(out,E,scale); return out end
		end
		return mulPartsInto(out,s1,l1,e1,s2,l2,e2)
	end

	local s1,l1,e1 = parts(a)
	local s2,l2,e2 = parts(b)
	return mulPartsInto(alloc(),s1,l1,e1,s2,l2,e2)
end

function GreaterNum.div(a, b): buffer
	if type(a) == "buffer" and type(b) == "buffer" then
		local s1 = breadi8(a,S); local l1 = breadf64(a,L); local e1 = breadf64(a,E)
		local s2 = breadi8(b,S); local l2 = breadf64(b,L); local e2 = breadf64(b,E)
		local out = bcreate(SIZE)

		if s2 == 0 then bwritei8(out,S,1); bwritef64(out,L,-1); bwritef64(out,E,1); return out end
		if s1 == 0 then return out end
		local rs = s1*s2

		if l1 == 0 and l2 == 0 then
			local n = e1/e2
			bwritei8(out,S,rs)
			if n >= HIGH or n <= LOW then bwritef64(out,L,1); bwritef64(out,E,log10(n)) else bwritef64(out,E,n) end
			return out
		end
		if l1 == l2 and e1 == e2 then bwritei8(out,S,rs); bwritef64(out,E,1); return out end

		if l1 >= 3 or l2 >= 3 or (l1 == 2 and l2 == 0) or (l2 == 2 and l1 == 0) then
			if l1 > l2 then
				bwritei8(out,S,rs); bwritef64(out,L,l1); bwritef64(out,E,e1)
			elseif l2 > l1 then
				bwritei8(out,S,rs); bwritef64(out,L,l2); bwritef64(out,E,-e2)
			elseif abs(e1) >= abs(e2) then
				bwritei8(out,S,rs); bwritef64(out,L,l1); bwritef64(out,E,e1)
			else
				bwritei8(out,S,rs); bwritef64(out,L,l2); bwritef64(out,E,-e2)
			end
			return out
		end

		if l1 == 2 and l2 == 2 then
			local d = if e1 >= 0 and e2 >= 0 then e1 - e2 else abs(e1) - abs(e2)
			if d >= OOM_CUTOFF then bwritei8(out,S,rs); bwritef64(out,L,2); bwritef64(out,E,e1); return out end
			if d <= -OOM_CUTOFF then bwritei8(out,S,rs); bwritef64(out,L,2); bwritef64(out,E,-e2); return out end
		end

		if l1 == 1 and l2 == 1 then
			local scale = e1-e2
			if scale >= 10 and scale < HIGH then bwritei8(out,S,rs); bwritef64(out,L,1); bwritef64(out,E,scale); return out end
		end
		return divPartsInto(out,s1,l1,e1,s2,l2,e2)
	end

	local s1,l1,e1 = parts(a)
	local s2,l2,e2 = parts(b)
	return divPartsInto(alloc(),s1,l1,e1,s2,l2,e2)
end

function GreaterNum.pow(a, b): buffer
	if type(a) == "buffer" and type(b) == "buffer" then
		local s1 = breadi8(a,S); local l1 = breadf64(a,L); local e1 = breadf64(a,E)
		local s2 = breadi8(b,S); local l2 = breadf64(b,L); local e2 = breadf64(b,E)
		local out = bcreate(SIZE)

		if s1 == 0 then
			if s2 > 0 then return out end
			bwritei8(out,S,1); bwritef64(out,L,-1); bwritef64(out,E,1); return out
		end
		if s2 == 0 then bwritei8(out,S,1); bwritef64(out,E,1); return out end

		if l2 == 0 then
			local exponent = s2*e2
			if l1 == 0 then
				if s1 < 0 and exponent % 1 ~= 0 then bwritei8(out,S,1); bwritef64(out,L,-1); bwritef64(out,E,1); return out end
				local n = pow(e1,exponent)
				if n == n and n ~= HUGE and n ~= 0 then
					local rs = (s1 < 0 and exponent % 2 ~= 0) and -1 or 1
					bwritei8(out,S,rs)
					if n >= HIGH or n <= LOW then bwritef64(out,L,1); bwritef64(out,E,log10(n)) else bwritef64(out,E,n) end
					return out
				end
			elseif l1 == 1 and s1 > 0 then
				local scale = e1*exponent
				if scale >= 10 and scale < HIGH then bwritei8(out,S,1); bwritef64(out,L,1); bwritef64(out,E,scale); return out end
			end
		end
		return powPartsInto(out,s1,l1,e1,s2,l2,e2)
	end

	local s1,l1,e1 = parts(a)
	local s2,l2,e2 = parts(b)
	return powPartsInto(alloc(),s1,l1,e1,s2,l2,e2)
end

function GreaterNum.addInto(out: buffer, a, b): buffer
	if type(a) == "buffer" and type(b) == "buffer" then
		return signedAddPartsInto(out,
			breadi8(a,S), breadf64(a,L), breadf64(a,E),
			breadi8(b,S), breadf64(b,L), breadf64(b,E)
		)
	end

	local s1,l1,e1 = parts(a)
	local s2,l2,e2 = parts(b)
	return signedAddPartsInto(out, s1,l1,e1,s2,l2,e2)
end

function GreaterNum.subInto(out: buffer, a, b): buffer
	if type(a) == "buffer" and type(b) == "buffer" then
		return signedAddPartsInto(out,
			breadi8(a,S), breadf64(a,L), breadf64(a,E),
			-breadi8(b,S), breadf64(b,L), breadf64(b,E)
		)
	end

	local s1,l1,e1 = parts(a)
	local s2,l2,e2 = parts(b)
	return signedAddPartsInto(out, s1,l1,e1,-s2,l2,e2)
end

function GreaterNum.mulInto(out: buffer, a, b): buffer
	if type(a) == "buffer" and type(b) == "buffer" then
		return mulPartsInto(out,
			breadi8(a,S), breadf64(a,L), breadf64(a,E),
			breadi8(b,S), breadf64(b,L), breadf64(b,E)
		)
	end

	local s1,l1,e1 = parts(a)
	local s2,l2,e2 = parts(b)
	return mulPartsInto(out, s1,l1,e1,s2,l2,e2)
end

function GreaterNum.divInto(out: buffer, a, b): buffer
	if type(a) == "buffer" and type(b) == "buffer" then
		return divPartsInto(out,
			breadi8(a,S), breadf64(a,L), breadf64(a,E),
			breadi8(b,S), breadf64(b,L), breadf64(b,E)
		)
	end

	local s1,l1,e1 = parts(a)
	local s2,l2,e2 = parts(b)
	return divPartsInto(out, s1,l1,e1,s2,l2,e2)
end

function GreaterNum.powInto(out: buffer, a, b): buffer
	if type(a) == "buffer" and type(b) == "buffer" then
		return powPartsInto(out,
			breadi8(a,S), breadf64(a,L), breadf64(a,E),
			breadi8(b,S), breadf64(b,L), breadf64(b,E)
		)
	end

	local s1,l1,e1 = parts(a)
	local s2,l2,e2 = parts(b)
	return powPartsInto(out, s1,l1,e1,s2,l2,e2)
end

function GreaterNum.addeq(a: buffer, b): buffer
	local s1 = breadi8(a, S)
	local l1 = breadf64(a, L)
	local e1 = breadf64(a, E)

	if type(b) == "buffer" then
		local s2 = breadi8(b, S)
		local l2 = breadf64(b, L)
		local e2 = breadf64(b, E)

		if s2 == 0 then
			return a
		end

		if s1 == 0 then
			bwritei8(a, S, s2)
			bwritef64(a, L, l2)
			bwritef64(a, E, e2)
			return a
		end

		if l1 == 0 and l2 == 0 then
			local n = s1 * e1 + s2 * e2

			if n == 0 then
				bwritei8(a, S, 0)
				bwritef64(a, L, 0)
				bwritef64(a, E, 0)
				return a
			end

			local sn
			if n < 0 then
				sn = -1
				n = -n
			else
				sn = 1
			end

			bwritei8(a, S, sn)

			if n >= HIGH or n <= LOW then
				bwritef64(a, L, 1)
				bwritef64(a, E, log10(n))
			else
				bwritef64(a, L, 0)
				bwritef64(a, E, n)
			end

			return a
		end

		if s1 == -s2 and l1 == l2 and e1 == e2 then
			bwritei8(a, S, 0)
			bwritef64(a, L, 0)
			bwritef64(a, E, 0)
			return a
		end

		if l1 >= 2 or l2 >= 2 then
			local l1s = e1 >= 0 and l1 or -l1
			local l2s = e2 >= 0 and l2 or -l2

			if l1s > l2s or (l1s == l2s and e1 > e2) then
				return a
			end

			bwritei8(a, S, s2)
			bwritef64(a, L, l2)
			bwritef64(a, E, e2)
			return a
		end

		return signedAddPartsInto(a, s1,l1,e1, s2,l2,e2)
	end

	if type(b) == "number" then
		if b == 0 then
			return a
		end

		if l1 == 0 and b > -HIGH and b < HIGH and abs(b) > LOW then
			local n = s1 * e1 + b

			if n == 0 then
				bwritei8(a, S, 0)
				bwritef64(a, L, 0)
				bwritef64(a, E, 0)
				return a
			end

			local sn
			if n < 0 then
				sn = -1
				n = -n
			else
				sn = 1
			end

			bwritei8(a, S, sn)

			if n >= HIGH or n <= LOW then
				bwritef64(a, L, 1)
				bwritef64(a, E, log10(n))
			else
				bwritef64(a, L, 0)
				bwritef64(a, E, n)
			end

			return a
		end

		local s2,l2,e2 = numberParts(b)
		return signedAddPartsInto(a, s1,l1,e1, s2,l2,e2)
	end

	local s2,l2,e2 = parts(b)
	return signedAddPartsInto(a, s1,l1,e1, s2,l2,e2)
end

function GreaterNum.subeq(a: buffer, b): buffer
	local s1 = breadi8(a, S)
	local l1 = breadf64(a, L)
	local e1 = breadf64(a, E)

	if type(b) == "buffer" then
		return signedAddPartsInto(
			a,
			s1, l1, e1,
			-breadi8(b, S), breadf64(b, L), breadf64(b, E)
		)
	end

	if type(b) == "number" then
		if b == 0 then
			return a
		end

		if l1 == 0 and b > -HIGH and b < HIGH and abs(b) > LOW then
			local n = s1 * e1 - b
			if n == 0 then
				return setZero(a)
			end

			local sn = n < 0 and -1 or 1
			n = abs(n)

			if n >= HIGH or n <= LOW then
				return setRaw(a, sn, 1, log10(n))
			end

			return setRaw(a, sn, 0, n)
		end

		local s2,l2,e2 = numberParts(b)
		return signedAddPartsInto(a, s1,l1,e1, -s2,l2,e2)
	end

	local s2,l2,e2 = parts(b)
	return signedAddPartsInto(a, s1,l1,e1, -s2,l2,e2)
end

function GreaterNum.muleq(a: buffer, b): buffer
	local s1 = breadi8(a, S)
	local l1 = breadf64(a, L)
	local e1 = breadf64(a, E)

	if type(b) == "buffer" then
		local s2 = breadi8(b, S)
		local l2 = breadf64(b, L)
		local e2 = breadf64(b, E)

		if s1 == 0 or s2 == 0 then
			return setZero(a)
		end

		local rs = s1 * s2

		if l1 == 0 and l2 == 0 then
			local n = abs(e1 * e2)
			if n >= HIGH or n <= LOW then
				return setRaw(a, rs, 1, log10(n))
			end
			return setRaw(a, rs, 0, n)
		end

		if l1 == l2 and e1 == -e2 then
			return setRaw(a, rs, 0, 1)
		end

		return mulPartsInto(a, s1,l1,e1, s2,l2,e2)
	end

	if type(b) == "number" then
		if b == 0 or s1 == 0 then
			return setZero(a)
		end

		if l1 == 0 and b > -HIGH and b < HIGH and abs(b) > LOW then
			local n = s1 * e1 * b
			local sn = n < 0 and -1 or 1
			n = abs(n)

			if n >= HIGH or n <= LOW then
				return setRaw(a, sn, 1, log10(n))
			end

			return setRaw(a, sn, 0, n)
		end

		local s2,l2,e2 = numberParts(b)
		return mulPartsInto(a, s1,l1,e1, s2,l2,e2)
	end

	local s2,l2,e2 = parts(b)
	return mulPartsInto(a, s1,l1,e1, s2,l2,e2)
end

function GreaterNum.diveq(a: buffer, b): buffer
	local s1 = breadi8(a, S)
	local l1 = breadf64(a, L)
	local e1 = breadf64(a, E)

	if type(b) == "buffer" then
		local s2 = breadi8(b, S)
		local l2 = breadf64(b, L)
		local e2 = breadf64(b, E)

		if s2 == 0 then
			return setNaN(a)
		end

		if s1 == 0 then
			return setZero(a)
		end

		local rs = s1 * s2

		if l1 == 0 and l2 == 0 then
			local n = abs(e1 / e2)
			if n >= HIGH or n <= LOW then
				return setRaw(a, rs, 1, log10(n))
			end
			return setRaw(a, rs, 0, n)
		end

		if l1 == l2 and e1 == e2 then
			return setRaw(a, rs, 0, 1)
		end

		return divPartsInto(a, s1,l1,e1, s2,l2,e2)
	end

	if type(b) == "number" then
		if b == 0 then
			return setNaN(a)
		end
		if s1 == 0 then
			return setZero(a)
		end

		if l1 == 0 and b > -HIGH and b < HIGH and abs(b) > LOW then
			local n = s1 * e1 / b
			local sn = n < 0 and -1 or 1
			n = abs(n)

			if n >= HIGH or n <= LOW then
				return setRaw(a, sn, 1, log10(n))
			end

			return setRaw(a, sn, 0, n)
		end

		local s2,l2,e2 = numberParts(b)
		return divPartsInto(a, s1,l1,e1, s2,l2,e2)
	end

	local s2,l2,e2 = parts(b)
	return divPartsInto(a, s1,l1,e1, s2,l2,e2)
end

function GreaterNum.poweq(a: buffer, b): buffer
	if type(b) == "buffer" then
		return Fast.poweq(a, b)
	end

	local s1 = breadi8(a, S)
	local l1 = breadf64(a, L)
	local e1 = breadf64(a, E)

	if type(b) == "number" then
		if b == 0 then
			return setRaw(a, 1, 0, 1)
		end

		if l1 == 0 then
			if s1 < 0 and b % 1 ~= 0 then
				return setNaN(a)
			end

			local n = pow(e1, b)
			if n == n and n ~= HUGE and n ~= 0 then
				local rs = (s1 < 0 and b % 2 ~= 0) and -1 or 1
				n = abs(n)

				if n >= HIGH or n <= LOW then
					return setRaw(a, rs, 1, log10(n))
				end

				return setRaw(a, rs, 0, n)
			end
		elseif l1 == 1 and s1 > 0 then
			local scale = e1 * b
			if scale >= 10 and scale < HIGH then
				return setRaw(a, 1, 1, scale)
			end
		end

		local s2,l2,e2 = numberParts(b)
		return powPartsInto(a, s1,l1,e1, s2,l2,e2)
	end

	local s2,l2,e2 = parts(b)
	return powPartsInto(a, s1,l1,e1, s2,l2,e2)
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
	local ta = type(a)
	local tb = type(b)

	if (ta == "buffer" or ta == "number") and (tb == "buffer" or tb == "number") then
		local s1,l1,e1 = parts(a)
		local s2,l2,e2 = parts(b)

		if l1 == 0 and l2 == 0 and s2 ~= 0 then
			local av = s1 * e1
			local bv = s2 * e2

			-- Exact shortcut for the integer case. Keep the legacy composite
			-- path for fractional/extreme values so behavior is unchanged.
			if av % 1 == 0 and bv % 1 == 0 and abs(av / bv) < HIGH then
				return Fast.fromNumber(av % bv)
			end
		end
	end

	local q = GreaterNum.intdiv(a, b)
	return GreaterNum.sub(a, GreaterNum.mul(q, b))
end

function GreaterNum.root(a, n): buffer
	return GreaterNum.pow(a, GreaterNum.div(1, n))
end

function GreaterNum.sqrt(a): buffer
	local ta = type(a)

	if ta == "buffer" then
		local s = breadi8(a, S)
		local l = breadf64(a, L)
		local e = breadf64(a, E)

		if l == 0 then
			if s < 0 then
				return setNaN(alloc())
			end
			if s == 0 then
				return alloc()
			end
			return Fast.fromNumber(sqrtNative(e))
		end
	elseif ta == "number" then
		if a < 0 then
			return setNaN(alloc())
		end
		return Fast.fromNumber(sqrtNative(a))
	end

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
	if type(a) == "buffer" then
		local s = breadi8(a,S)
		local l = breadf64(a,L)
		local e = breadf64(a,E)
		local out = bcreate(SIZE)

		if s == 0 or l < 0 then bwritei8(out,S,1); bwritef64(out,L,-1); bwritef64(out,E,1); return out end
		if l == 0 then
			local n = log10(e)
			if n == 0 then return out end
			local sn = n < 0 and -1 or 1
			if n < 0 then n = -n end
			bwritei8(out,S,sn); bwritef64(out,E,n)
			return out
		end

		local ae = e < 0 and -e or e
		local rs = e < 0 and -1 or 1
		if l == 1 then bwritei8(out,S,rs); bwritef64(out,E,ae); return out end
		if ae >= 10 then bwritei8(out,S,rs); bwritef64(out,L,l-1); bwritef64(out,E,ae); return out end
		return normalizeInto(out,rs,l-1,ae)
	end

	local s,l,e = parts(a)
	if s == 0 then return GreaterNum.nan() end
	if l == 0 then return GreaterNum.fromNumber(log10(e)) end
	return normalizeInto(alloc(),sign(e),l-1,abs(e))
end

function GreaterNum.log10(a): buffer
	if type(a) == "buffer" then
		local s = breadi8(a, S)
		local l = breadf64(a, L)
		local e = breadf64(a, E)
		local out = bcreate(SIZE)

		if s <= 0 or l < 0 then
			bwritei8(out, S, 1)
			bwritef64(out, L, -1)
			bwritef64(out, E, 1)
			return out
		end

		if l == HUGE then
			bwritei8(out, S, 1)
			bwritef64(out, L, HUGE)
			bwritef64(out, E, 1)
			return out
		end

		if l > 0 then
			if e < 0 then
				bwritei8(out, S, -1)
				bwritef64(out, L, l - 1)
				bwritef64(out, E, -e)
			else
				bwritei8(out, S, 1)
				bwritef64(out, L, l - 1)
				bwritef64(out, E, e)
			end
			return out
		end

		if e == 1 then
			return out
		end

		local n = log10(e)

		if n < 0 then
			bwritei8(out, S, -1)
			bwritef64(out, E, -n)
		elseif n > 0 then
			bwritei8(out, S, 1)
			bwritef64(out, E, n)
		end

		return out
	end

	if type(a) == "number" then
		if a > 0 then
			if a == HUGE then
				local out = bcreate(SIZE)
				bwritei8(out, S, 1)
				bwritef64(out, L, HUGE)
				bwritef64(out, E, 1)
				return out
			end

			local n = log10(a)
			local out = bcreate(SIZE)

			if n < 0 then
				bwritei8(out, S, -1)
				bwritef64(out, E, -n)
			elseif n > 0 then
				bwritei8(out, S, 1)
				if n >= HIGH then
					bwritef64(out, L, 1)
					bwritef64(out, E, log10(n))
				else
					bwritef64(out, E, n)
				end
			end

			return out
		end

		local out = bcreate(SIZE)
		bwritei8(out, S, 1)
		bwritef64(out, L, -1)
		bwritef64(out, E, 1)
		return out
	end

	error("GreaterNum.log10: expected number or GreaterNum buffer")
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
		local s1 = breadi8(a, S)
		local s2 = breadi8(b, S)

		if s1 ~= s2 then
			return if s1 < s2 then -1 else 1
		end
		if s1 == 0 then
			return 0
		end

		local l1 = breadf64(a, L)
		local l2 = breadf64(b, L)
		local e1 = breadf64(a, E)
		local e2 = breadf64(b, E)

		-- Positive layered values can compare without rawCompare().
		if e1 >= 0 and e2 >= 0 then
			if l1 ~= l2 then
				local r = if l1 < l2 then -1 else 1
				return if s1 < 0 then -r else r
			end
			if e1 ~= e2 then
				local r = if e1 < e2 then -1 else 1
				return if s1 < 0 then -r else r
			end
			return 0
		end

		return rawCompare(s1,l1,e1,s2,l2,e2)
	end

	local s1,l1,e1 = parts(a)
	local s2,l2,e2 = parts(b)
	return rawCompare(s1,l1,e1,s2,l2,e2)
end

function GreaterNum.eq(a,b): boolean
	if type(a) == "buffer" and type(b) == "buffer" then
		return breadi8(a, S) == breadi8(b, S)
			and breadf64(a, L) == breadf64(b, L)
			and breadf64(a, E) == breadf64(b, E)
	end
	return GreaterNum.compare(a,b) == 0
end

function GreaterNum.ne(a,b): boolean
	if type(a) == "buffer" and type(b) == "buffer" then
		return breadi8(a, S) ~= breadi8(b, S)
			or breadf64(a, L) ~= breadf64(b, L)
			or breadf64(a, E) ~= breadf64(b, E)
	end
	return GreaterNum.compare(a,b) ~= 0
end

function GreaterNum.lt(a,b): boolean
	if type(a) == "buffer" and type(b) == "buffer" then
		local s1 = breadi8(a, S)
		local s2 = breadi8(b, S)
		if s1 ~= s2 then
			return s1 < s2
		end
		if s1 == 0 then
			return false
		end

		local l1 = breadf64(a, L)
		local l2 = breadf64(b, L)
		local e1 = breadf64(a, E)
		local e2 = breadf64(b, E)
		if e1 >= 0 and e2 >= 0 then
			if l1 ~= l2 then
				return if s1 > 0 then l1 < l2 else l1 > l2
			end
			return if s1 > 0 then e1 < e2 else e1 > e2
		end
		return rawCompare(s1,l1,e1,s2,l2,e2) < 0
	end
	return GreaterNum.compare(a,b) < 0
end

function GreaterNum.lte(a,b): boolean
	if type(a) == "buffer" and type(b) == "buffer" then
		local s1 = breadi8(a, S)
		local s2 = breadi8(b, S)
		if s1 ~= s2 then
			return s1 < s2
		end
		if s1 == 0 then
			return true
		end

		local l1 = breadf64(a, L)
		local l2 = breadf64(b, L)
		local e1 = breadf64(a, E)
		local e2 = breadf64(b, E)
		if e1 >= 0 and e2 >= 0 then
			if l1 ~= l2 then
				return if s1 > 0 then l1 < l2 else l1 > l2
			end
			return if s1 > 0 then e1 <= e2 else e1 >= e2
		end
		return rawCompare(s1,l1,e1,s2,l2,e2) <= 0
	end
	return GreaterNum.compare(a,b) <= 0
end

function GreaterNum.gt(a,b): boolean
	if type(a) == "buffer" and type(b) == "buffer" then
		local s1 = breadi8(a, S)
		local s2 = breadi8(b, S)
		if s1 ~= s2 then
			return s1 > s2
		end
		if s1 == 0 then
			return false
		end

		local l1 = breadf64(a, L)
		local l2 = breadf64(b, L)
		local e1 = breadf64(a, E)
		local e2 = breadf64(b, E)
		if e1 >= 0 and e2 >= 0 then
			if l1 ~= l2 then
				return if s1 > 0 then l1 > l2 else l1 < l2
			end
			return if s1 > 0 then e1 > e2 else e1 < e2
		end
		return rawCompare(s1,l1,e1,s2,l2,e2) > 0
	end
	return GreaterNum.compare(a,b) > 0
end

function GreaterNum.gte(a,b): boolean
	if type(a) == "buffer" and type(b) == "buffer" then
		local s1 = breadi8(a, S)
		local s2 = breadi8(b, S)
		if s1 ~= s2 then
			return s1 > s2
		end
		if s1 == 0 then
			return true
		end

		local l1 = breadf64(a, L)
		local l2 = breadf64(b, L)
		local e1 = breadf64(a, E)
		local e2 = breadf64(b, E)
		if e1 >= 0 and e2 >= 0 then
			if l1 ~= l2 then
				return if s1 > 0 then l1 > l2 else l1 < l2
			end
			return if s1 > 0 then e1 >= e2 else e1 <= e2
		end
		return rawCompare(s1,l1,e1,s2,l2,e2) >= 0
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
	if type(v) == "buffer" then return breadi8(v, S) > 0 end
	local s = parts(v)
	return s > 0
end

function GreaterNum.isNegative(v): boolean
	if type(v) == "buffer" then return breadi8(v, S) < 0 end
	local s = parts(v)
	return s < 0
end

function GreaterNum.isZero(v): boolean
	if type(v) == "buffer" then return breadi8(v, S) == 0 end
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
	if type(v) == "buffer" then return breadi8(v, S) end
	local s = parts(v)
	return s
end

function GreaterNum.layer(v): number
	local s,l,e = parts(v)
	local _, notationLayer = rawToNotationParts(s,l,e)
	return notationLayer
end

function GreaterNum.exponent(v): number
	local s,l,e = parts(v)
	local _,_,notationExponent = rawToNotationParts(s,l,e)
	return notationExponent
end

function GreaterNum.toNumber(v): number
	if type(v) == "buffer" then
		local s = breadi8(v, S)
		if s == 0 then
			return 0
		end

		local l = breadf64(v, L)
		if l < 0 then
			return 0/0
		end
		if l == HUGE then
			return s * HUGE
		end

		local e = breadf64(v, E)
		if l == 0 then
			return s * e
		end
		if l == 1 and e <= 308 and e >= -324 then
			return s * pow(10, e)
		end
		return s * HUGE
	end

	local s,l,e = parts(v)
	if l < 0 then return 0/0 end
	if l == HUGE then return s * HUGE end
	if s == 0 then return 0 end
	if l == 0 then return s * e end
	if l == 1 and e <= 308 and e >= -324 then return s * pow(10, e) end
	return s * HUGE
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

	return GreaterNum.fromRawParts(s1, l1, rng:NextNumber(e1, e2))
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
	return GreaterNum.fromRawParts(1, 1, logN)
end

GreaterNum.fact = GreaterNum.factorial

function GreaterNum.tetrate(base, height: number): buffer
	if height < 0 or height % 1 ~= 0 then
		return GreaterNum.nan()
	end

	if height == 0 then
		return GreaterNum.one()
	end

	local bs, bl, be = parts(base)

	-- Exact fixed point.
	if bs == 1 and bl == 0 and be == 1 then
		return setRaw(alloc(), 1, 0, 1)
	end

	-- 10^^h maps directly onto GreaterNum's raw layer representation.
	-- Preserve the existing layer>=32 early-stop behavior.
	if bs == 1 and bl == 0 and be == 10 then
		return setRaw(alloc(), 1, min(height - 1, 32), 10)
	end

	local result
	local startHeight

	-- Exact first towers for base 2. These are the same IEEE-754 values
	-- produced by the old repeated-pow path, without the temporary buffers.
	if bs == 1 and bl == 0 and be == 2 then
		if height == 1 then
			return setRaw(alloc(), 1, 0, 2)
		elseif height == 2 then
			return setRaw(alloc(), 1, 0, 4)
		elseif height == 3 then
			return setRaw(alloc(), 1, 0, 16)
		end

		result = setRaw(alloc(), 1, 0, 65536)
		startHeight = 5
	else
		result = setRaw(alloc(), bs, bl, be)
		startHeight = 2
	end

	if startHeight > height then
		return result
	end

	local nextValue = alloc()
	local scratch = alloc()

	for _ = startHeight, height do
		powPartsFastInto(
			nextValue,
			scratch,
			bs, bl, be,
			breadi8(result, S), breadf64(result, L), breadf64(result, E)
		)

		result, nextValue = nextValue, result

		if breadf64(result, L) >= 32 then
			break
		end
	end

	return result
end

GreaterNum.tetr = GreaterNum.tetrate

local SUFFIX_SETS = {"k","M","B"}
local SUFFIX_FIRST = {"", "U","D","T","Qd","Qn","Sx","Sp","Oc","No"}
local SUFFIX_SECOND = {"", "De","Vt","Tg","qg","Qg","sg","Sg","Og","Ng"}
local SUFFIX_THIRD = {"", "Ce", "Du","Tr","Qa","Qi","Se","Si","Ot","Ni"}
local SUFFIX_MULT = {
	"", "Mi","Mc","Na","Pi","Fm","At","Zp","Yc", "Xo", "Ve", "Me", 
	"Due", "Tre", "Te", "Pt", "He", "Hp", "Oct", "En", "Ic", "Mei", 
	"Dui", "Tri", "Teti", "Pti", "Hei", "Hp", "Oci", "Eni", "Tra","TeC",
	"MTc","DTc","TrTc","TeTc","PeTc","HTc","HpT","OcT","EnT","TetC","MTetc",
	"DTetc","TrTetc","TeTetc","PeTetc","HTetc","HpTetc","OcTetc","EnTetc","PcT",
	"MPcT","DPcT","TPCt","TePCt","PePCt","HePCt","HpPct","OcPct","EnPct","HCt",
	"MHcT","DHcT","THCt","TeHCt","PeHCt","HeHCt","HpHct","OcHct","EnHct","HpCt",
	"MHpcT","DHpcT","THpCt","TeHpCt","PeHpCt","HeHpCt","HpHpct","OcHpct","EnHpct",
	"OCt","MOcT","DOcT","TOCt","TeOCt","PeOCt","HeOCt","HpOct","OcOct","EnOct","Ent","MEnT",
	"DEnT","TEnt","TeEnt","PeEnt","HeEnt","HpEnt","OcEnt","EnEnt","Hect", "MeHect"}

local DEFAULT_SUFFIX_DIGITS = 2

local function suffixPartOne(group: number): string
	local n = floor(group)
	local hundreds = floor(n / 100)
	n %= 100
	local tens = floor(n / 10)
	local ones = floor(n % 10)

	return (SUFFIX_FIRST[ones + 1] or "")
		.. (SUFFIX_SECOND[tens + 1] or "")
		.. (SUFFIX_THIRD[hundreds + 1] or "")
end

local MAX_SAFE_SUFFIX_DECIMAL_EXPONENT = 9007199254740991 -- 2^53 - 1
local MAX_SAFE_SUFFIX_GROUP = floor(MAX_SAFE_SUFFIX_DECIMAL_EXPONENT / 3) - 1
local MAX_SAFE_SUFFIX_LAYER2_EXPONENT = log10(MAX_SAFE_SUFFIX_DECIMAL_EXPONENT)
local SUFFIX_CACHE = {}

local function suffixMultiplier(tier: number): string?
	local direct = SUFFIX_MULT[tier + 1]
	if direct ~= nil then
		return direct
	end

	return nil
end

local function suffixGroupRecursive(group: number, tier: number, out: {string})
	if tier < 0 or group <= 0 then
		return
	end

	if tier == 0 then
		local chunk = floor(group % 1000)
		if chunk > 0 then
			out[#out + 1] = suffixPartOne(chunk)
		end
		return
	end

	local divisor = pow(1000, tier)
	local chunk = floor(group / divisor)

	if chunk > 0 then
		local multiplier = suffixMultiplier(tier)

		if multiplier == nil then
			return
		end

		if chunk > 1 then
			out[#out + 1] = suffixPartOne(chunk)
		end

		out[#out + 1] = multiplier
		group -= chunk * divisor
	end

	suffixGroupRecursive(group, tier - 1, out)
end

local function suffixForGroup(group: number): string?
	group = floor(group)

	if group < 0 then
		return ""
	end

	if group > MAX_SAFE_SUFFIX_GROUP then
		return nil
	end

	if group < 3 then
		return SUFFIX_SETS[group + 1]
	end

	local cached = SUFFIX_CACHE[group]
	if cached ~= nil then
		return cached
	end

	if group < 1000 then
		local simple = suffixPartOne(group)
		if group <= 4096 then
			SUFFIX_CACHE[group] = simple
		end
		return simple
	end

	local tier = floor(log10(group) / 3)

	-- Any exact-safe Luau integer is at most six base-1000 chunks, so the
	-- supplied MultOnes table has far more multiplier tiers than are needed
	-- before IEEE-754 integer precision becomes the real limit.
	if suffixMultiplier(tier) == nil then
		return nil
	end

	local out = table.create(tier * 2 + 2)
	suffixGroupRecursive(group, tier, out)

	if #out == 0 then
		return nil
	end

	local result = table.concat(out)

	if group <= 4096 then
		SUFFIX_CACHE[group] = result
	end

	return result
end

local function suffixDecimalExponentFromParts(l: number, e: number): number?
	if l == 0 then
		if e <= 0 then
			return nil
		end
		return floor(log10(e))
	end

	if l == 1 then
		if e < 0 or e > MAX_SAFE_SUFFIX_DECIMAL_EXPONENT then
			return nil
		end
		return floor(e)
	end

	if l == 2 then
		if e < 0 or e > MAX_SAFE_SUFFIX_LAYER2_EXPONENT then
			return nil
		end

		local decimalExponent = pow(10, e)
		if decimalExponent > MAX_SAFE_SUFFIX_DECIMAL_EXPONENT then
			return nil
		end

		return floor(decimalExponent)
	end

	return nil
end

local function suffixNumberText(n: number, digits: number): string
	if digits <= 0 then
		return tostring(floor(n))
	end

	local factor = pow(10, digits)
	local cut = floor(n * factor + 1e-12) / factor
	return tostring(cut)
end

local function trimZeros(text: string): string
	if not string.find(text, ".", 1, true) then
		return text
	end
	return (text:gsub("0+$", ""):gsub("%.$", ""))
end

local function fixed(n: number, digits: number, trim: boolean): string
	local text = strformat(FIXED_FORMATS[digits + 1], n)

	if not trim or digits == 0 then
		return text
	end

	local last = #text

	while last > 0 and strbyte(text, last) == 48 do
		last -= 1
	end

	if last > 0 and strbyte(text, last) == 46 then
		last -= 1
	end

	if last == #text then
		return text
	end

	return strsub(text, 1, last)
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

	if notation == "layer" then
		return GreaterNum.toLayered(value, digits)
	end

	if notation == "raw" then
		return prefix .. "R" .. tostring(l) .. ":" .. fixed(e, digits, trim)
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
		if options.suffixes == nil and not forceSign and not separators then
			return GreaterNum.toSuffix(value, digits)
		end

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
	return GreaterNum.toSuffix(value, digits == nil and 3 or digits)
end

GreaterNum.tostring = GreaterNum.toString

function GreaterNum.toSuffix(value, digits: number?): string
	local d = digits == nil and DEFAULT_SUFFIX_DIGITS or floor(digits)
	if d < 0 then d = 0 elseif d > 15 then d = 15 end

	local s,l,e

	if type(value) == "buffer" then
		s = breadi8(value,S)
		l = breadf64(value,L)
		e = breadf64(value,E)
	elseif type(value) == "number" then
		if value ~= value then return "NaN" end
		if value == HUGE then return "Infinity" end
		if value == -HUGE then return "-Infinity" end
		if value == 0 then return "0" end

		s = value < 0 and -1 or 1
		local magnitude = abs(value)

		if magnitude >= HIGH or magnitude <= LOW then
			l = 1
			e = log10(magnitude)
		else
			l = 0
			e = magnitude
		end
	else
		s,l,e = parts(value)
	end

	if l < 0 then return "NaN" end
	if l == HUGE then return s < 0 and "-Infinity" or "Infinity" end
	if s == 0 then return "0" end

	local prefix = s < 0 and "-" or ""

	if l == 0 and e < 1000 then
		return suffixNumberText(s * e, d)
	end

	if l == 1 and e < 0 then
		-- Preserve reciprocal-style formatting for tiny layer-1 values.
		local positiveExponent = -e
		local decimalExponent = floor(positiveExponent)
		local mod3 = decimalExponent % 3
		local group = floor(decimalExponent / 3) - 1

		if group <= -1 then
			return prefix .. suffixNumberText(pow(10, e), d)
		end

		local suffix = suffixForGroup(group)
		if suffix then
			local mantissa = pow(10, positiveExponent - decimalExponent)
			local shown = mantissa * pow(10, mod3)
			return prefix .. "1 / " .. suffixNumberText(shown, d) .. suffix
		end

		return sciFromParts(s,l,e,d,true)
	end

	local decimalExponent = suffixDecimalExponentFromParts(l, e)

	if decimalExponent ~= nil then
		local mod3 = decimalExponent % 3
		local group = floor(decimalExponent / 3) - 1

		if group <= -1 then
			if l == 0 then
				return suffixNumberText(s * e, d)
			end

			local ordinary = pow(10, decimalExponent)
			return prefix .. suffixNumberText(ordinary, d)
		end

		local suffix = suffixForGroup(group)

		if suffix then
			local mantissa

			if l == 0 then
				mantissa = e / pow(10, decimalExponent)
			elseif l == 1 then
				mantissa = pow(10, e - decimalExponent)
			else
				-- raw layer 2: exponent-of-exponent.  The fractional part of
				-- 10^e determines the leading mantissa of the represented value.
				local exactExponent = pow(10, e)
				mantissa = pow(10, exactExponent - decimalExponent)
			end

			local shown = mantissa * pow(10, mod3)
			return prefix .. suffixNumberText(shown, d) .. suffix
		end
	end

	local _,notationLayer,notationExponent = rawToNotationParts(s,l,e)
	return prefix .. "E(" .. tostring(notationLayer) .. ")" .. suffixNumberText(abs(notationExponent), d)
end

function GreaterNum.suffixName(decimalExponent: number): string?
	if type(decimalExponent) ~= "number" or decimalExponent ~= decimalExponent then
		return nil
	end

	decimalExponent = floor(decimalExponent)

	if decimalExponent < 3 then
		return ""
	end

	local group = floor(decimalExponent / 3) - 1
	return suffixForGroup(group)
end

function GreaterNum.suffixInfo(value)
	local s,l,e = parts(value)

	if s == 0 then
		return {
			supported = true,
			decimalExponent = 0,
			group = -1,
			suffix = "",
		}
	end

	if l < 0 or l == HUGE then
		return {
			supported = false,
			reason = "special",
		}
	end

	local decimalExponent = suffixDecimalExponentFromParts(l,e)

	if decimalExponent == nil then
		return {
			supported = false,
			reason = "unsafe-index",
			maxSafeGroup = MAX_SAFE_SUFFIX_GROUP,
			maxSafeDecimalExponent = MAX_SAFE_SUFFIX_DECIMAL_EXPONENT,
		}
	end

	local group = floor(decimalExponent / 3) - 1
	local suffix = group <= -1 and "" or suffixForGroup(group)

	return {
		supported = suffix ~= nil,
		decimalExponent = decimalExponent,
		group = group,
		suffix = suffix,
		maxSafeGroup = MAX_SAFE_SUFFIX_GROUP,
		maxSafeDecimalExponent = MAX_SAFE_SUFFIX_DECIMAL_EXPONENT,
	}
end

function GreaterNum.canSuffix(value): boolean
	return GreaterNum.suffixInfo(value).supported == true
end

function GreaterNum.toScientific(value, digits: number?): string
	local d = digits or 3
	if d < 0 then d = 0 elseif d > 15 then d = 15 else d = floor(d) end
	if type(value) == "buffer" then
		return sciFromParts(breadi8(value,S),breadf64(value,L),breadf64(value,E),d,true)
	end
	local s,l,e = parts(value)
	return sciFromParts(s,l,e,d,true)
end

function GreaterNum.toEngineer(value, digits: number?): string
	local d = digits or 3
	if d < 0 then d = 0 elseif d > 15 then d = 15 else d = floor(d) end

	local s,l,e
	if type(value) == "buffer" then
		s = breadi8(value,S)
		l = breadf64(value,L)
		e = breadf64(value,E)
	else
		s,l,e = parts(value)
	end

	if l < 0 then return "NaN" end
	if l == HUGE then return s < 0 and "-Infinity" or "Infinity" end
	if s == 0 then return "0" end

	local prefix = s < 0 and "-" or ""

	if l == 0 then
		local exp3 = floor(log10(e) / 3) * 3
		local mantissa = e / pow(10, exp3)
		return prefix .. fixed(mantissa, d, true) .. "e" .. tostring(exp3)
	end

	if l == 1 then
		local exp3 = floor(e / 3) * 3
		local mantissa = pow(10, e - exp3)
		return prefix .. fixed(mantissa, d, true) .. "e" .. tostring(exp3)
	end

	return sciFromParts(s,l,e,d,true)
end

function GreaterNum.toLayered(value, digits: number?): string
	local d = digits or 3
	if d < 0 then d = 0 elseif d > 15 then d = 15 else d = floor(d) end

	local rawS,rawL,rawE = parts(value)

	if rawL < 0 then return "NaN" end
	if rawL == HUGE then return rawS < 0 and "-Infinity" or "Infinity" end
	if rawS == 0 then return "0" end

	local s,l,e = rawToNotationParts(rawS,rawL,rawE)
	local prefix = s < 0 and "-" or ""
	return prefix .. "L" .. tostring(l) .. ":" .. fixed(e, d, true)
end

function GreaterNum.fromString(text: string): buffer
	if type(text) ~= "string" then
		error("GreaterNum.fromString: expected string")
	end

	-- v1.2.9 native-first numeric hot path.
	--
	-- Finite, non-zero decimal AND scientific strings can be converted
	-- directly from Luau's native number parser. This removes the v1.2.8
	-- string.find("e"/"E") pre-pass and avoids the full scientific byte
	-- scanner for ordinary finite inputs such as:
	--   "12345.6789", "1e250", "3.14159e250", "-6.022e23".
	--
	-- Zero / +/-Infinity / NaN / parse failures deliberately fall through:
	-- zero may be scientific underflow (e.g. 1e-1000), and Infinity may be
	-- scientific overflow (e.g. 1e1000), both of which GreaterNum can
	-- represent more accurately than a native Luau number.
	local native = tonumber(text)
	if native ~= nil
		and native == native
		and native ~= 0
		and native ~= HUGE
		and native ~= -HUGE
	then
		local out = bcreate(SIZE)
		local s = 1

		if native < 0 then
			s = -1
			native = -native
		end

		bwritei8(out, S, s)

		if native >= HIGH or native <= LOW then
			bwritef64(out, L, 1)
			bwritef64(out, E, log10(native))
		else
			bwritef64(out, E, native)
		end

		return out
	end

	local len = #text
	local first = 1
	local last = len

	-- Inline trim. No parser/helper function call.
	while first <= last do
		local c = strbyte(text, first)
		if c ~= 32 and (c < 9 or c > 13) then
			break
		end
		first += 1
	end

	while last >= first do
		local c = strbyte(text, last)
		if c ~= 32 and (c < 9 or c > 13) then
			break
		end
		last -= 1
	end

	if first > last then
		error("GreaterNum.fromString: empty string")
	end

	-- =====================================================================
	-- SCIENTIFIC HOT PATH
	-- Fully inline byte scanner. No trim/scientific/helper function calls.
	-- Handles:
	--   1e250, -1e250, +2e+250, 3.14159e250, .5e3, 1.e10, etc.
	-- =====================================================================
	do
		local i = first
		local valueSign = 1
		local c = strbyte(text, i)

		if c == 45 then -- '-'
			valueSign = -1
			i += 1
		elseif c == 43 then -- '+'
			i += 1
		end

		if i <= last then
			local mantissa = 0
			local fractionalDigits = 0
			local sawDigit = false
			local sawDot = false
			local sawExponent = false
			local valid = true

			while i <= last do
				c = strbyte(text, i)

				if c >= 48 and c <= 57 then
					sawDigit = true
					mantissa = mantissa * 10 + (c - 48)
					if sawDot then
						fractionalDigits += 1
					end
					i += 1
				elseif c == 46 then -- '.'
					if sawDot then
						valid = false
						break
					end
					sawDot = true
					i += 1
				elseif c == 101 or c == 69 then -- e/E
					sawExponent = true
					i += 1
					break
				else
					valid = false
					break
				end
			end

			if valid and sawExponent and sawDigit and i <= last then
				local exponentSign = 1
				c = strbyte(text, i)

				if c == 43 then
					i += 1
				elseif c == 45 then
					exponentSign = -1
					i += 1
				end

				if i <= last then
					local exponent = 0
					local exponentDigits = false

					while i <= last do
						c = strbyte(text, i)
						if c < 48 or c > 57 then
							valid = false
							break
						end

						exponentDigits = true
						exponent = exponent * 10 + (c - 48)
						i += 1
					end

					if valid and exponentDigits then
						exponent *= exponentSign
						local out = bcreate(SIZE)

						if mantissa == 0 then
							return out
						end

						if mantissa == HUGE then
							if exponent == -HUGE then
								bwritei8(out, S, 1)
								bwritef64(out, L, -1)
								bwritef64(out, E, 1)
								return out
							end

							bwritei8(out, S, valueSign)
							bwritef64(out, L, HUGE)
							bwritef64(out, E, 1)
							return out
						end

						if exponent == HUGE then
							bwritei8(out, S, valueSign)
							bwritef64(out, L, HUGE)
							bwritef64(out, E, 1)
							return out
						elseif exponent == -HUGE then
							return out
						end

						local mantissaLog
						if mantissa == 1 then
							mantissaLog = -fractionalDigits
						else
							mantissaLog = log10(mantissa) - fractionalDigits
						end

						local scale = exponent + mantissaLog

						if scale ~= scale then
							bwritei8(out, S, 1)
							bwritef64(out, L, -1)
							bwritef64(out, E, 1)
							return out
						end

						if scale == HUGE then
							bwritei8(out, S, valueSign)
							bwritef64(out, L, HUGE)
							bwritef64(out, E, 1)
							return out
						elseif scale == -HUGE then
							return out
						end

						local aScale = if scale < 0 then -scale else scale

						if aScale < 10 then
							bwritei8(out, S, valueSign)
							bwritef64(out, L, 0)
							bwritef64(out, E, pow(10, scale))
							return out
						end

						if aScale >= HIGH then
							bwritei8(out, S, valueSign)
							bwritef64(out, L, 2)
							bwritef64(out, E, (if scale < 0 then -1 else 1) * log10(aScale))
							return out
						end

						bwritei8(out, S, valueSign)
						bwritef64(out, L, 1)
						bwritef64(out, E, scale)
						return out
					end
				end
			end
		end
	end

	-- =====================================================================
	-- CACHED NATIVE FALLBACK
	-- Reuses the single tonumber() result from the function entry. This
	-- handles zero and native special results after the scientific scanner
	-- has had first chance to preserve underflow/overflow magnitude.
	-- =====================================================================
	if native ~= nil then
		local out = bcreate(SIZE)

		if native ~= native then
			bwritei8(out, S, 1)
			bwritef64(out, L, -1)
			bwritef64(out, E, 1)
			return out
		end

		if native == HUGE then
			bwritei8(out, S, 1)
			bwritef64(out, L, HUGE)
			bwritef64(out, E, 1)
			return out
		elseif native == -HUGE then
			bwritei8(out, S, -1)
			bwritef64(out, L, HUGE)
			bwritef64(out, E, 1)
			return out
		elseif native == 0 then
			return out
		end

		local valueSign = 1
		if native < 0 then
			valueSign = -1
			native = -native
		end

		bwritei8(out, S, valueSign)

		if native >= HIGH or native <= LOW then
			bwritef64(out, L, 1)
			bwritef64(out, E, log10(native))
		else
			bwritef64(out, L, 0)
			bwritef64(out, E, native)
		end

		return out
	end

	-- =====================================================================
	-- SPECIAL VALUES
	-- Inline ASCII case folding. No lowercase/equality helper function.
	-- Preserves: NaN, +NaN, Inf, Infinity, +/- variants.
	-- =====================================================================
	do
		local i = first
		local specialSign = 1
		local c = strbyte(text, i)

		if c == 43 then
			i += 1
		elseif c == 45 then
			specialSign = -1
			i += 1
		end

		local count = last - i + 1

		if count == 3 then
			local a = strbyte(text, i)
			local b = strbyte(text, i + 1)
			local c3 = strbyte(text, i + 2)

			if a >= 65 and a <= 90 then a += 32 end
			if b >= 65 and b <= 90 then b += 32 end
			if c3 >= 65 and c3 <= 90 then c3 += 32 end

			-- nan
			if a == 110 and b == 97 and c3 == 110 and specialSign == 1 then
				local out = bcreate(SIZE)
				bwritei8(out, S, 1)
				bwritef64(out, L, -1)
				bwritef64(out, E, 1)
				return out
			end

			-- inf
			if a == 105 and b == 110 and c3 == 102 then
				local out = bcreate(SIZE)
				bwritei8(out, S, specialSign)
				bwritef64(out, L, HUGE)
				bwritef64(out, E, 1)
				return out
			end
		elseif count == 8 then
			-- infinity
			local ok = true
			local expected1 = 105 -- i
			local expected2 = 110 -- n
			local expected3 = 102 -- f
			local expected4 = 105 -- i
			local expected5 = 110 -- n
			local expected6 = 105 -- i
			local expected7 = 116 -- t
			local expected8 = 121 -- y

			local c1 = strbyte(text, i)
			local c2 = strbyte(text, i + 1)
			local c3 = strbyte(text, i + 2)
			local c4 = strbyte(text, i + 3)
			local c5 = strbyte(text, i + 4)
			local c6 = strbyte(text, i + 5)
			local c7 = strbyte(text, i + 6)
			local c8 = strbyte(text, i + 7)

			if c1 >= 65 and c1 <= 90 then c1 += 32 end
			if c2 >= 65 and c2 <= 90 then c2 += 32 end
			if c3 >= 65 and c3 <= 90 then c3 += 32 end
			if c4 >= 65 and c4 <= 90 then c4 += 32 end
			if c5 >= 65 and c5 <= 90 then c5 += 32 end
			if c6 >= 65 and c6 <= 90 then c6 += 32 end
			if c7 >= 65 and c7 <= 90 then c7 += 32 end
			if c8 >= 65 and c8 <= 90 then c8 += 32 end

			ok = c1 == expected1
				and c2 == expected2
				and c3 == expected3
				and c4 == expected4
				and c5 == expected5
				and c6 == expected6
				and c7 == expected7
				and c8 == expected8

			if ok then
				local out = bcreate(SIZE)
				bwritei8(out, S, specialSign)
				bwritef64(out, L, HUGE)
				bwritef64(out, E, 1)
				return out
			end
		end
	end

	-- =====================================================================
	-- GREATERNUM EXTENDED SYNTAX
	-- Inline parser for:
	--   L<layer>:<exponent>
	--   <layer>;<exponent>
	-- No pattern/range/new/normalize helper calls.
	-- =====================================================================
	do
		local i = first
		local valueSign = 1
		local c = strbyte(text, i)

		if c == 45 then
			valueSign = -1
			i += 1
		elseif c == 43 then
			i += 1
		end

		if i <= last then
			local layerStart = i
			local separator = 0
			local separatorByte = 0

			c = strbyte(text, i)
			if c == 76 or c == 108 then -- L/l
				layerStart = i + 1
				i = layerStart

				while i <= last do
					c = strbyte(text, i)
					if c == 58 then -- ':'
						separator = i
						separatorByte = 58
						break
					end
					i += 1
				end
			else
				while i <= last do
					c = strbyte(text, i)
					if c == 59 then -- ';'
						separator = i
						separatorByte = 59
						break
					end
					i += 1
				end
			end

			if separator ~= 0 and separatorByte ~= 0 and layerStart <= separator - 1 and separator + 1 <= last then
				-- Parse layer, unsigned decimal.
				local j = layerStart
				local layerWhole = 0
				local layerFrac = 0
				local layerFracScale = 1
				local layerSawDigit = false
				local layerSawDot = false
				local layerValid = true

				while j <= separator - 1 do
					c = strbyte(text, j)

					if c >= 48 and c <= 57 then
						layerSawDigit = true
						local d = c - 48
						if layerSawDot then
							layerFrac = layerFrac * 10 + d
							layerFracScale *= 10
						else
							layerWhole = layerWhole * 10 + d
						end
					elseif c == 46 and not layerSawDot then
						layerSawDot = true
					else
						layerValid = false
						break
					end

					j += 1
				end

				-- Parse exponent, signed decimal.
				j = separator + 1
				local exponentSign = 1
				c = strbyte(text, j)

				if c == 45 then
					exponentSign = -1
					j += 1
				elseif c == 43 then
					j += 1
				end

				local exponentWhole = 0
				local exponentFrac = 0
				local exponentFracScale = 1
				local exponentSawDigit = false
				local exponentSawDot = false
				local exponentValid = j <= last

				while exponentValid and j <= last do
					c = strbyte(text, j)

					if c >= 48 and c <= 57 then
						exponentSawDigit = true
						local d = c - 48
						if exponentSawDot then
							exponentFrac = exponentFrac * 10 + d
							exponentFracScale *= 10
						else
							exponentWhole = exponentWhole * 10 + d
						end
					elseif c == 46 and not exponentSawDot then
						exponentSawDot = true
					else
						exponentValid = false
						break
					end

					j += 1
				end

				if layerValid and layerSawDigit and exponentValid and exponentSawDigit then
					local nl = layerWhole + layerFrac / layerFracScale
					local ne = exponentSign * (exponentWhole + exponentFrac / exponentFracScale)
					local ns = valueSign
					local out = bcreate(SIZE)

					-- Inline GreaterNum.new semantics:
					-- notation layer -> raw layer + 1, then canonical normalization.
					if ns ~= ns or nl ~= nl or ne ~= ne then
						bwritei8(out, S, 1)
						bwritef64(out, L, -1)
						bwritef64(out, E, 1)
						return out
					end

					if ns == 0 then
						return out
					end

					if nl < 0 then
						bwritei8(out, S, 1)
						bwritef64(out, L, -1)
						bwritef64(out, E, 1)
						return out
					end

					if nl == HUGE or (if ne < 0 then -ne else ne) == HUGE then
						bwritei8(out, S, if ns < 0 then -1 else 1)
						bwritef64(out, L, HUGE)
						bwritef64(out, E, 1)
						return out
					end

					ns = if ns < 0 then -1 else 1
					nl = floor(nl) + 1

					-- Iterative equivalent of normalizeInto(), kept inline.
					while true do
						if ns == 0 or (nl == 0 and ne == 0) then
							bwritei8(out, S, 0)
							bwritef64(out, L, 0)
							bwritef64(out, E, 0)
							return out
						end

						if nl < 0 then
							bwritei8(out, S, 1)
							bwritef64(out, L, -1)
							bwritef64(out, E, 1)
							return out
						end

						if nl == HUGE or (if ne < 0 then -ne else ne) == HUGE then
							bwritei8(out, S, ns)
							bwritef64(out, L, HUGE)
							bwritef64(out, E, 1)
							return out
						end

						if nl == 0 then
							if ne < 0 then
								ne = -ne
								ns = -ns
							end

							if ne <= LOW or ne >= HIGH then
								bwritei8(out, S, ns)
								bwritef64(out, L, 1)
								bwritef64(out, E, log10(ne))
								return out
							end

							bwritei8(out, S, ns)
							bwritef64(out, L, 0)
							bwritef64(out, E, ne)
							return out
						end

						local ae = if ne < 0 then -ne else ne

						if ae >= HIGH then
							bwritei8(out, S, ns)
							bwritef64(out, L, nl + 1)
							bwritef64(out, E, (if ne < 0 then -1 else 1) * log10(ae))
							return out
						end

						if nl == 1 and ae < 10 then
							nl = 0
							ne = pow(10, ne)
							continue
						end

						if ae < 1 then
							if nl >= 3 then
								local inner = (if ne < 0 then -1 else 1) * pow(10, ae)
								nl -= 2
								ne = (if inner < 0 then -1 else 1) * pow(10, if inner < 0 then -inner else inner)
								continue
							end

							nl = 0
							local signedPow = (if ne < 0 then -1 else 1) * pow(10, ae)
							ne = pow(10, signedPow)
							continue
						end

						if ae < 10 then
							nl -= 1
							ne = (if ne < 0 then -1 else 1) * pow(10, ae)
							continue
						end

						bwritei8(out, S, ns)
						bwritef64(out, L, nl)
						bwritef64(out, E, ne)
						return out
					end
				end
			end
		end
	end

	-- Surrounding-whitespace fallback for runtimes where tonumber(fullText)
	-- does not accept it. This is the only substring allocation in fromString.
	if first ~= 1 or last ~= len then
		local trimmed = strsub(text, first, last)
		native = tonumber(trimmed)

		if native ~= nil then
			local out = bcreate(SIZE)

			if native ~= native then
				bwritei8(out, S, 1)
				bwritef64(out, L, -1)
				bwritef64(out, E, 1)
				return out
			end

			if native == HUGE then
				bwritei8(out, S, 1)
				bwritef64(out, L, HUGE)
				bwritef64(out, E, 1)
				return out
			elseif native == -HUGE then
				bwritei8(out, S, -1)
				bwritef64(out, L, HUGE)
				bwritef64(out, E, 1)
				return out
			elseif native == 0 then
				return out
			end

			local valueSign = 1
			if native < 0 then
				valueSign = -1
				native = -native
			end

			bwritei8(out, S, valueSign)

			if native >= HIGH or native <= LOW then
				bwritef64(out, L, 1)
				bwritef64(out, E, log10(native))
			else
				bwritef64(out, L, 0)
				bwritef64(out, E, native)
			end

			return out
		end
	end

	error("GreaterNum.fromString: invalid value '" .. strsub(text, first, last) .. "'")
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

	return GreaterNum.fromRawParts(1, 1, log10Gamma)
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
		error("GreaterNum.deserialize: expected raw {sign, layer, exponent}")
	end

	return GreaterNum.fromRawParts(data[1], data[2], data[3])
end


function GreaterNum.serializeNotation(value): {number}
	local s,l,e = GreaterNum.tuple(value)
	return {s,l,e}
end

function GreaterNum.deserializeNotation(data): buffer
	if type(data) ~= "table" or #data < 3 then
		error("GreaterNum.deserializeNotation: expected notation {sign, layer, exponent}")
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

function GreaterNum.rawTuple(value): (number, number, number)
	return parts(value)
end

function GreaterNum.notation(value)
	local s,l,e = GreaterNum.tuple(value)
	return {
		sign = s,
		layer = l,
		exponent = e,
	}
end



function GreaterNum.copyAddInto(out: buffer, source: buffer, addend): buffer
	if type(addend) == "buffer" then
		return Fast.copyAddInto(out, source, addend)
	end

	Fast.copyInto(out, source)
	return GreaterNum.addeq(out, addend)
end

function GreaterNum.addNumberInto(out: buffer, a: buffer, n: number): buffer
	Fast.copyInto(out, a)
	return GreaterNum.addeq(out, n)
end

function GreaterNum.subNumberInto(out: buffer, a: buffer, n: number): buffer
	Fast.copyInto(out, a)
	return GreaterNum.subeq(out, n)
end

function GreaterNum.mulNumberInto(out: buffer, a: buffer, n: number): buffer
	Fast.copyInto(out, a)
	return GreaterNum.muleq(out, n)
end

function GreaterNum.divNumberInto(out: buffer, a: buffer, n: number): buffer
	Fast.copyInto(out, a)
	return GreaterNum.diveq(out, n)
end

function GreaterNum.increment(value: buffer, amount: number?): buffer
	return GreaterNum.addeq(value, amount or 1)
end

function GreaterNum.decrement(value: buffer, amount: number?): buffer
	return GreaterNum.subeq(value, amount or 1)
end

function GreaterNum.compact(value, digits: number?): string
	return GreaterNum.toSuffix(value, digits)
end

function GreaterNum.parse(text: string): buffer
	return GreaterNum.fromString(text)
end

function GreaterNum.tryParse(text: string): (buffer?, string?)
	return GreaterNum.tryFromString(text)
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
		toString = run(function() GreaterNum.toString(a) end),
		toSuffix = run(function() GreaterNum.toSuffix(a) end),
		intoAddPublic = run(function() GreaterNum.addInto(scratch,a,b) end),

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
GreaterNum.REPRESENTATION = "17-byte canonical raw Sign + Layer + Exponent; public new() uses exponent notation"
GreaterNum.OPTIMIZATION_LEVEL = "v1.2.9 Single-Parse Scientific Fast Path + Inline Compare/Convert + Layer Hot Paths"
GreaterNum.COMPATIBLE_BUFFER_VERSION = 1
GreaterNum.CONSTRUCTOR_SEMANTICS_VERSION = 2
GreaterNum.PERFORMANCE_PATCH = "1.2.8"
GreaterNum.DEFAULT_SUFFIX_DIGITS = DEFAULT_SUFFIX_DIGITS
GreaterNum.MAX_SAFE_SUFFIX_GROUP = MAX_SAFE_SUFFIX_GROUP
GreaterNum.MAX_SAFE_SUFFIX_DECIMAL_EXPONENT = MAX_SAFE_SUFFIX_DECIMAL_EXPONENT

GreaterNum.Convert = {
	number = GreaterNum.fromNumber,
	scientific = GreaterNum.fromScientific,
	string = GreaterNum.fromString,
	parse = GreaterNum.parse,
	coerce = GreaterNum.coerce,
	buffer = GreaterNum.toBuffer,
	tuple = GreaterNum.fromTuple,
	raw = GreaterNum.fromRawParts,
	rawTuple = GreaterNum.rawTuple,
	notation = GreaterNum.notation,
}

GreaterNum.Compare = {
	compare = GreaterNum.compare,
	eq = GreaterNum.eq,
	ne = GreaterNum.ne,
	lt = GreaterNum.lt,
	lte = GreaterNum.lte,
	gt = GreaterNum.gt,
	gte = GreaterNum.gte,
	clamp = GreaterNum.clamp,
}

GreaterNum.Into = {
	add = GreaterNum.addInto,
	sub = GreaterNum.subInto,
	mul = GreaterNum.mulInto,
	div = GreaterNum.divInto,
	pow = GreaterNum.powInto,
	addNumber = GreaterNum.addNumberInto,
	copyAdd = GreaterNum.copyAddInto,
	subNumber = GreaterNum.subNumberInto,
	mulNumber = GreaterNum.mulNumberInto,
	divNumber = GreaterNum.divNumberInto,
}

GreaterNum.Mutate = {
	add = GreaterNum.addeq,
	sub = GreaterNum.subeq,
	mul = GreaterNum.muleq,
	div = GreaterNum.diveq,
	pow = GreaterNum.poweq,
	increment = GreaterNum.increment,
	decrement = GreaterNum.decrement,
}

GreaterNum.Format = {
	auto = GreaterNum.toString,
	compact = GreaterNum.toSuffix,
	suffix = GreaterNum.toSuffix,
	scientific = GreaterNum.toScientific,
	engineering = GreaterNum.toEngineer,
	layered = GreaterNum.toLayered,
	custom = GreaterNum.format,
	name = GreaterNum.suffixName,
	info = GreaterNum.suffixInfo,
	canSuffix = GreaterNum.canSuffix,
}

return GreaterNum
