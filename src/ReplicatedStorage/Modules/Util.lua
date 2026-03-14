--!strict
-- Util.lua
-- Shared utility functions used across server and client.

local Util = {}

-- ─── Math ────────────────────────────────────────────────────────────────────

-- Clamp a value between min and max.
function Util.clamp(value: number, min: number, max: number): number
    return math.max(min, math.min(max, value))
end

-- Linear interpolation.
function Util.lerp(a: number, b: number, t: number): number
    return a + (b - a) * t
end

-- Rounds to nearest integer.
function Util.round(n: number): number
    return math.floor(n + 0.5)
end

-- Returns a random integer in [min, max] (inclusive).
function Util.randomInt(min: number, max: number): number
    return math.random(min, max)
end

-- ─── Weighted Random ─────────────────────────────────────────────────────────

-- Given a table of { item, weight } pairs, returns one item by weighted chance.
-- Example:  Util.weightedRandom({ {item="a",weight=10}, {item="b",weight=90} })
function Util.weightedRandom<T>(entries: { { item: T, weight: number } }): T
    local totalWeight = 0
    for _, entry in entries do
        totalWeight += entry.weight
    end
    local roll = math.random() * totalWeight
    local cumulative = 0
    for _, entry in entries do
        cumulative += entry.weight
        if roll <= cumulative then
            return entry.item
        end
    end
    -- Fallback: return last entry
    return entries[#entries].item
end

-- ─── Table Helpers ───────────────────────────────────────────────────────────

-- Returns a shallow copy of a table.
function Util.shallowCopy<T>(t: { [any]: T }): { [any]: T }
    local copy = {}
    for k, v in t do
        copy[k] = v
    end
    return copy
end

-- Shuffles an array in place (Fisher-Yates).
function Util.shuffle<T>(arr: { T }): { T }
    for i = #arr, 2, -1 do
        local j = math.random(1, i)
        arr[i], arr[j] = arr[j], arr[i]
    end
    return arr
end

-- Returns whether a value exists in an array.
function Util.contains<T>(arr: { T }, value: T): boolean
    for _, v in arr do
        if v == value then return true end
    end
    return false
end

-- ─── String Helpers ──────────────────────────────────────────────────────────

-- Formats a number with commas: 1234567 → "1,234,567"
function Util.formatNumber(n: number): string
    local s = tostring(math.floor(n))
    local result = ""
    local count = 0
    for i = #s, 1, -1 do
        if count > 0 and count % 3 == 0 then
            result = "," .. result
        end
        result = string.sub(s, i, i) .. result
        count += 1
    end
    return result
end

-- Title-cases a snake_case string: "drum_of_the_ancients" → "Drum Of The Ancients"
function Util.titleCase(s: string): string
    return (s:gsub("(%a)([%w_']*)", function(first, rest)
        return first:upper() .. rest:lower()
    end):gsub("_", " "))
end

-- ─── Instance Helpers ────────────────────────────────────────────────────────

-- Waits for a child to exist and returns it (with timeout).
function Util.waitForChild(parent: Instance, name: string, timeout: number?): Instance?
    local t = timeout or 10
    local child = parent:FindFirstChild(name)
    if child then return child end
    local deadline = tick() + t
    repeat
        task.wait()
        child = parent:FindFirstChild(name)
    until child or tick() >= deadline
    return child
end

-- Finds all descendants matching a class name.
function Util.getDescendantsOfClass(root: Instance, className: string): { Instance }
    local result = {}
    for _, desc in root:GetDescendants() do
        if desc:IsA(className) then
            table.insert(result, desc)
        end
    end
    return result
end

-- ─── Vector Helpers ──────────────────────────────────────────────────────────

-- Returns the distance between two Vector3 positions (ignoring Y axis).
function Util.flatDistance(a: Vector3, b: Vector3): number
    local dx = a.X - b.X
    local dz = a.Z - b.Z
    return math.sqrt(dx * dx + dz * dz)
end

-- Returns a random point within a circle of radius r centred at origin (Y=0).
function Util.randomCirclePoint(origin: Vector3, radius: number): Vector3
    local angle = math.random() * math.pi * 2
    local r = math.sqrt(math.random()) * radius
    return Vector3.new(
        origin.X + r * math.cos(angle),
        origin.Y,
        origin.Z + r * math.sin(angle)
    )
end

-- ─── XP / Level Helpers ──────────────────────────────────────────────────────

-- Returns XP required to reach a given level from scratch.
function Util.xpForLevel(level: number, base: number, exponent: number): number
    return math.floor(base * (level ^ exponent))
end

return Util
