-- Community-service task kinds (PF_ARCHITECTURE 4.7.9). Shared: the server validates steps against
-- these numbers; the client only uses the labels and the scenario it plays while a step runs.
--
-- Every kind matches a pf-government work-order kind (server/workorders.lua KINDS). A task is one GOV
-- work unit: `steps` interaction steps at server-chosen points of the site (spread = each step at a
-- different point, at least MinStepDistance apart; otherwise every step is at the same spot), each at
-- least MinStepSeconds after the previous one, on foot, and at least `minSeconds` on site without a
-- break (GOV keeps its own minimum for the unit as well; the larger one applies).
--
-- `tool` (optional): an item the worker must hold for a step (checked on the server); `consume`
-- (optional): an item removed on the server for each step before the step counts. Neither is set by
-- default (tools are handed out in role-play); Config.CommunityService.TaskItems[kind] = { tool, consume }
-- turns them on per kind.

PFJustice = PFJustice or {}
PFJustice.CSTasks = PFJustice.CSTasks or {}
local T = PFJustice.CSTasks

T.Kinds = {
    litter          = { label = 'Litter pick-up', stepLabel = 'Pick up litter', steps = 5, spread = true, minSeconds = 60,
                        scenario = 'WORLD_HUMAN_JANITOR' },
    graffiti        = { label = 'Graffiti removal', stepLabel = 'Scrub graffiti', steps = 4, spread = true, minSeconds = 90,
                        scenario = 'WORLD_HUMAN_MAID_CLEAN' },
    park            = { label = 'Park upkeep', stepLabel = 'Tend the park', steps = 4, spread = true, minSeconds = 90,
                        scenario = 'WORLD_HUMAN_GARDENER_PLANT' },
    landscaping     = { label = 'Landscaping', stepLabel = 'Trim and clear', steps = 4, spread = true, minSeconds = 120,
                        scenario = 'WORLD_HUMAN_GARDENER_LEAF_BLOWER' },
    public_building = { label = 'Public building upkeep', stepLabel = 'Clean the building', steps = 4, spread = true, minSeconds = 120,
                        scenario = 'WORLD_HUMAN_MAID_CLEAN' },
    pothole         = { label = 'Pothole repair', stepLabel = 'Fill the pothole', steps = 3, spread = false, minSeconds = 150,
                        scenario = 'WORLD_HUMAN_CONST_DRILL' },
    streetlight     = { label = 'Streetlight repair', stepLabel = 'Repair the light', steps = 3, spread = false, minSeconds = 120,
                        scenario = 'WORLD_HUMAN_WELDING' },
    sign            = { label = 'Signal and sign repair', stepLabel = 'Fix the sign', steps = 3, spread = false, minSeconds = 90,
                        scenario = 'WORLD_HUMAN_HAMMERING' },
}

--- The community-service config block (owned by config.lua) or an empty table.
function T.Cfg()
    return (Config and Config.CommunityService) or {}
end

--- A config number with a default, clamped to [min, max].
function T.Num(key, default, min, max)
    local v = tonumber(T.Cfg()[key])
    if not v or v ~= v then v = default end
    if min and v < min then v = min end
    if max and v > max then v = max end
    return v
end

function T.Kind(kind)
    return type(kind) == 'string' and T.Kinds[kind] or nil
end

--- The item rules of a kind: { tool = name?, consume = name? } (config wins over nothing).
function T.Items(kind)
    local items = (T.Cfg().TaskItems or {})[kind]
    if type(items) ~= 'table' then return {} end
    return {
        tool = type(items.tool) == 'string' and items.tool or nil,
        consume = type(items.consume) == 'string' and items.consume or nil,
    }
end

local DEFAULT_SIGN_IN = {
    { id = 'cityhall', label = 'City Hall community service desk', coords = vector3(-544.67, -204.25, 38.22), radius = 15.0 },
}

--- Sign-in points: { id, label, coords, radius }.
function T.SignIns()
    local list = T.Cfg().SignIn
    if type(list) ~= 'table' or #list == 0 then return DEFAULT_SIGN_IN end
    return list
end

-- A deterministic number in [0, 1) for (seed, i): the same task always gets the same points, so a
-- restart or a reconnect shows the player the points the server checks, without storing them.
local function frac(seed, i)
    local v = math.sin(seed * 12.9898 + i * 78.233) * 43758.5453
    return v - math.floor(v)
end

--- The step points of a task (server truth). site = { x, y, z, r }. Spread kinds get `n` points inside
--- 75% of the radius, each at least `spacing` metres from every earlier one when the site allows it;
--- the other kinds get one spot used for every step.
function T.Points(taskId, site, n, spread, spacing)
    local seed = (tonumber(taskId) or 1) % 100000 + 1
    local r = math.max(1.0, (tonumber(site.r) or 10.0) * 0.75)
    local points = {}
    local function at(a, d) return { x = site.x + math.cos(a) * d, y = site.y + math.sin(a) * d, z = site.z } end
    if not spread then
        local p = at(frac(seed, 1) * 2 * math.pi, r * 0.3 * frac(seed, 2))
        for i = 1, n do points[i] = p end
        return points
    end
    spacing = spacing or 3.0
    for i = 1, n do
        local best, bestGap
        for try = 0, 11 do
            local p = at(frac(seed, i * 31 + try) * 2 * math.pi, r * (0.15 + 0.85 * frac(seed, i * 17 + try)))
            local gap = math.huge
            for _, q in ipairs(points) do
                local dx, dy = p.x - q.x, p.y - q.y
                gap = math.min(gap, math.sqrt(dx * dx + dy * dy))
            end
            if not bestGap or gap > bestGap then best, bestGap = p, gap end
            if gap >= spacing then break end
        end
        points[i] = best
    end
    return points
end

