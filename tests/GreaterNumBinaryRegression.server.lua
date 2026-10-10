--!strict
local N = require(script.Parent:WaitForChild("GreaterNum"))
assert(N.version() == "1.2.10")
for _, x in {0, 1, -1, 1e10, 1e-10, 1e300} do
    local original = N.fromNumber(x)
    local serial = N.encode(original)
    local result = N.decode(serial)
    assert(N.isValid(result), "Roundtrip failed for " .. tostring(x))
    assert(N.isValid(N.deserializeBuffer(original)))
end
local original = N.encode(N.fromNumber(123))
local mutated = buffer.fromstring(original)
buffer.writei8(mutated, 0, 127)
assert(not pcall(N.decode, buffer.tostring(mutated)), "Corrupted sign was accepted")
assert(not pcall(N.deserializeBuffer, mutated), "Corrupted buffer was accepted")
assert(not pcall(N.decode, "short"), "Wrong-size encoded record accepted")
print("GreaterNum 1.2.10 serialized record validation PASS")
