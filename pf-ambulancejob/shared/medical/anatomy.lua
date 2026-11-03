-- Anatomy for the medical engine: named structures (bones, joints, organs, vessels, soft tissue),
-- hit regions with weighted structures and depth, the GTA bone map and armour coverage.
-- Pure data plus lookups; shared so the client can label things the same way. Edit freely: every
-- other medical module reads these tables instead of hard-coding names.

PFMed = PFMed or {}
PFMed.Anatomy = PFMed.Anatomy or {}
local A = PFMed.Anatomy

local function S(label, kind, group, side, vital, bleedClass, armour)
    return { label = label, kind = kind, group = group, side = side, vital = vital == true, bleedClass = bleedClass or 0, armour = armour }
end

-- kind: bone | joint | organ | vessel | soft. bleedClass 0 none, 1 slow, 2 heavy, 3 massive.
-- armour: what covers it ('vest' or 'helmet'); nil when nothing does.
A.Structures = {
    skull          = S('Skull', 'bone', 'head', nil, true, 1, 'helmet'),
    brain          = S('Brain', 'organ', 'head', nil, true, 2, 'helmet'),
    face_jaw       = S('Face and jaw', 'bone', 'head', nil, false, 1),
    neck           = S('Neck soft tissue', 'soft', 'neck', nil, false, 1),
    spine_cervical = S('Cervical spine', 'bone', 'neck', nil, true, 1),
    spine_thoracic = S('Thoracic spine', 'bone', 'torso', nil, true, 1, 'vest'),
    spine_lumbar   = S('Lumbar spine', 'bone', 'torso', nil, true, 1, 'vest'),
    shoulder_l     = S('Left shoulder', 'joint', 'arm_l', 'l', false, 1),
    shoulder_r     = S('Right shoulder', 'joint', 'arm_r', 'r', false, 1),
    clavicle_l     = S('Left clavicle', 'bone', 'arm_l', 'l', false, 1),
    clavicle_r     = S('Right clavicle', 'bone', 'arm_r', 'r', false, 1),
    humerus_l      = S('Left humerus', 'bone', 'arm_l', 'l', false, 1),
    humerus_r      = S('Right humerus', 'bone', 'arm_r', 'r', false, 1),
    elbow_l        = S('Left elbow', 'joint', 'arm_l', 'l', false, 1),
    elbow_r        = S('Right elbow', 'joint', 'arm_r', 'r', false, 1),
    forearm_l      = S('Left forearm', 'bone', 'arm_l', 'l', false, 1),
    forearm_r      = S('Right forearm', 'bone', 'arm_r', 'r', false, 1),
    wrist_l        = S('Left wrist', 'joint', 'arm_l', 'l', false, 0),
    wrist_r        = S('Right wrist', 'joint', 'arm_r', 'r', false, 0),
    hand_l         = S('Left hand', 'bone', 'arm_l', 'l', false, 1),
    hand_r         = S('Right hand', 'bone', 'arm_r', 'r', false, 1),
    sternum        = S('Sternum', 'bone', 'torso', nil, false, 1, 'vest'),
    ribs_l         = S('Left ribs', 'bone', 'torso', 'l', false, 1, 'vest'),
    ribs_r         = S('Right ribs', 'bone', 'torso', 'r', false, 1, 'vest'),
    heart          = S('Heart', 'organ', 'torso', nil, true, 3, 'vest'),
    lung_l         = S('Left lung', 'organ', 'torso', 'l', true, 2, 'vest'),
    lung_r         = S('Right lung', 'organ', 'torso', 'r', true, 2, 'vest'),
    airway         = S('Airway', 'organ', 'neck', nil, true, 1),
    liver          = S('Liver', 'organ', 'torso', 'r', true, 3, 'vest'),
    spleen         = S('Spleen', 'organ', 'torso', 'l', true, 3, 'vest'),
    kidney_l       = S('Left kidney', 'organ', 'torso', 'l', false, 2, 'vest'),
    kidney_r       = S('Right kidney', 'organ', 'torso', 'r', false, 2, 'vest'),
    stomach        = S('Stomach', 'organ', 'torso', nil, false, 2, 'vest'),
    bowel          = S('Bowel', 'organ', 'torso', nil, false, 1, 'vest'),
    bladder        = S('Bladder', 'organ', 'pelvis', nil, false, 1),
    pelvis         = S('Pelvis', 'bone', 'pelvis', nil, true, 2),
    hip_l          = S('Left hip', 'joint', 'leg_l', 'l', false, 1),
    hip_r          = S('Right hip', 'joint', 'leg_r', 'r', false, 1),
    femur_l        = S('Left femur', 'bone', 'leg_l', 'l', false, 2),
    femur_r        = S('Right femur', 'bone', 'leg_r', 'r', false, 2),
    knee_l         = S('Left knee', 'joint', 'leg_l', 'l', false, 1),
    knee_r         = S('Right knee', 'joint', 'leg_r', 'r', false, 1),
    tibia_l        = S('Left tibia', 'bone', 'leg_l', 'l', false, 1),
    tibia_r        = S('Right tibia', 'bone', 'leg_r', 'r', false, 1),
    fibula_l       = S('Left fibula', 'bone', 'leg_l', 'l', false, 1),
    fibula_r       = S('Right fibula', 'bone', 'leg_r', 'r', false, 1),
    ankle_l        = S('Left ankle', 'joint', 'leg_l', 'l', false, 0),
    ankle_r        = S('Right ankle', 'joint', 'leg_r', 'r', false, 0),
    foot_l         = S('Left foot', 'bone', 'leg_l', 'l', false, 1),
    foot_r         = S('Right foot', 'bone', 'leg_r', 'r', false, 1),
    heel_l         = S('Left heel', 'bone', 'leg_l', 'l', false, 0),
    heel_r         = S('Right heel', 'bone', 'leg_r', 'r', false, 0),
    carotid        = S('Carotid artery', 'vessel', 'neck', nil, true, 3),
    aorta          = S('Aorta', 'vessel', 'torso', nil, true, 3, 'vest'),
    brachial_l     = S('Left brachial artery', 'vessel', 'arm_l', 'l', false, 3),
    brachial_r     = S('Right brachial artery', 'vessel', 'arm_r', 'r', false, 3),
    femoral_l      = S('Left femoral artery', 'vessel', 'leg_l', 'l', true, 3),
    femoral_r      = S('Right femoral artery', 'vessel', 'leg_r', 'r', true, 3),
}

-- Region entries: { structure | false, weight, depth }. false = skin and muscle only (the injury
-- then has a region and no structure). depth: surface | bone | organ.
local function R(label, group, armour, list)
    return { label = label, group = group, armour = armour, structures = list }
end
local function limb(side, parts)
    local out = {}
    for name, def in pairs(parts) do out[name .. '_' .. side] = def end
    return out
end

A.Regions = {
    head       = R('Head', 'head', 'helmet', { { 'skull', 0.30, 'bone' }, { 'brain', 0.30, 'organ' }, { false, 0.40, 'surface' } }),
    face       = R('Face', 'head', nil, { { 'face_jaw', 0.45, 'bone' }, { 'airway', 0.10, 'organ' }, { false, 0.45, 'surface' } }),
    neck       = R('Neck', 'neck', nil, { { 'neck', 0.35, 'surface' }, { 'spine_cervical', 0.20, 'bone' }, { 'airway', 0.20, 'organ' }, { 'carotid', 0.15, 'organ' }, { false, 0.10, 'surface' } }),
    chest_l    = R('Left chest', 'torso', 'vest', { { 'ribs_l', 0.25, 'bone' }, { 'lung_l', 0.30, 'organ' }, { 'heart', 0.12, 'organ' }, { 'sternum', 0.05, 'bone' }, { 'aorta', 0.03, 'organ' }, { false, 0.25, 'surface' } }),
    chest_r    = R('Right chest', 'torso', 'vest', { { 'ribs_r', 0.25, 'bone' }, { 'lung_r', 0.35, 'organ' }, { 'sternum', 0.05, 'bone' }, { 'liver', 0.07, 'organ' }, { 'aorta', 0.03, 'organ' }, { false, 0.25, 'surface' } }),
    abdomen    = R('Abdomen', 'torso', 'vest', { { 'bowel', 0.30, 'organ' }, { 'liver', 0.20, 'organ' }, { 'spleen', 0.12, 'organ' }, { 'stomach', 0.12, 'organ' }, { 'kidney_l', 0.04, 'organ' }, { 'kidney_r', 0.04, 'organ' }, { 'aorta', 0.03, 'organ' }, { false, 0.15, 'surface' } }),
    back_upper = R('Upper back', 'torso', 'vest', { { 'spine_thoracic', 0.25, 'bone' }, { 'ribs_l', 0.10, 'bone' }, { 'ribs_r', 0.10, 'bone' }, { 'lung_l', 0.10, 'organ' }, { 'lung_r', 0.10, 'organ' }, { false, 0.35, 'surface' } }),
    back_lower = R('Lower back', 'torso', 'vest', { { 'spine_lumbar', 0.25, 'bone' }, { 'kidney_l', 0.15, 'organ' }, { 'kidney_r', 0.15, 'organ' }, { false, 0.45, 'surface' } }),
    pelvis     = R('Pelvis', 'pelvis', nil, { { 'pelvis', 0.35, 'bone' }, { 'bladder', 0.12, 'organ' }, { 'bowel', 0.08, 'organ' }, { 'hip_l', 0.05, 'bone' }, { 'hip_r', 0.05, 'bone' }, { false, 0.35, 'surface' } }),
}
for _, side in ipairs({ 'l', 'r' }) do
    local s = side == 'l' and 'Left' or 'Right'
    local regions = limb(side, {
        shoulder  = R(s .. ' shoulder', 'arm_' .. side, nil, { { 'shoulder_' .. side, 0.35, 'bone' }, { 'clavicle_' .. side, 0.30, 'bone' }, { 'lung_' .. side, 0.05, 'organ' }, { false, 0.30, 'surface' } }),
        upper_arm = R(s .. ' upper arm', 'arm_' .. side, nil, { { 'humerus_' .. side, 0.35, 'bone' }, { 'brachial_' .. side, 0.10, 'organ' }, { 'elbow_' .. side, 0.10, 'bone' }, { false, 0.45, 'surface' } }),
        forearm   = R(s .. ' forearm', 'arm_' .. side, nil, { { 'forearm_' .. side, 0.40, 'bone' }, { 'wrist_' .. side, 0.10, 'bone' }, { 'elbow_' .. side, 0.05, 'bone' }, { false, 0.45, 'surface' } }),
        hand      = R(s .. ' hand', 'arm_' .. side, nil, { { 'hand_' .. side, 0.60, 'bone' }, { 'wrist_' .. side, 0.15, 'bone' }, { false, 0.25, 'surface' } }),
        thigh     = R(s .. ' thigh', 'leg_' .. side, nil, { { 'femur_' .. side, 0.35, 'bone' }, { 'femoral_' .. side, 0.10, 'organ' }, { 'hip_' .. side, 0.05, 'bone' }, { false, 0.50, 'surface' } }),
        knee      = R(s .. ' knee', 'leg_' .. side, nil, { { 'knee_' .. side, 0.70, 'bone' }, { false, 0.30, 'surface' } }),
        lower_leg = R(s .. ' lower leg', 'leg_' .. side, nil, { { 'tibia_' .. side, 0.35, 'bone' }, { 'fibula_' .. side, 0.20, 'bone' }, { false, 0.45, 'surface' } }),
        foot      = R(s .. ' foot', 'leg_' .. side, nil, { { 'foot_' .. side, 0.60, 'bone' }, { false, 0.40, 'surface' } }),
    })
    for k, v in pairs(regions) do A.Regions[k] = v end
end

-- Structures no GTA bone reaches, listed with the mechanisms that reach them (16B mechanisms.lua
-- reads these; falls land on heels and ankles, crushes on chest/pelvis/limbs, inhalation in the airway).
A.MechanismStructures = {
    fall       = { 'heel_l', 'heel_r', 'ankle_l', 'ankle_r', 'tibia_l', 'tibia_r', 'femur_l', 'femur_r', 'pelvis', 'spine_lumbar', 'wrist_l', 'wrist_r', 'skull', 'brain' },
    crush      = { 'ribs_l', 'ribs_r', 'sternum', 'pelvis', 'femur_l', 'femur_r', 'tibia_l', 'tibia_r', 'foot_l', 'foot_r', 'heel_l', 'heel_r', 'ankle_l', 'ankle_r', 'hand_l', 'hand_r' },
    vehicle    = { 'neck', 'spine_cervical', 'sternum', 'ribs_l', 'ribs_r', 'spleen', 'liver', 'knee_l', 'knee_r', 'femur_l', 'femur_r', 'skull', 'brain' },
    pedestrian = { 'tibia_l', 'tibia_r', 'fibula_l', 'fibula_r', 'knee_l', 'knee_r', 'pelvis', 'skull', 'brain' },
    inhalation = { 'airway', 'lung_l', 'lung_r' },
    drowning   = { 'airway', 'lung_l', 'lung_r' },
}

-- GTA bone id -> region, or a weighted list when one bone can stand for several regions (a spine
-- bone is hit by shots from the front and from the back). Ids from Config.Bones; knee and elbow
-- helper bones are added only after they were checked in game (architecture 10).
local CHEST = { { 'chest_l', 0.35 }, { 'chest_r', 0.35 }, { 'back_upper', 0.30 } }
local BELLY = { { 'abdomen', 0.60 }, { 'back_lower', 0.40 } }
A.BoneMap = {
    [31085] = { { 'head', 0.6 }, { 'face', 0.4 } },
    [31086] = { { 'head', 0.6 }, { 'face', 0.4 } },
    [39317] = 'neck',
    [57597] = BELLY, [23553] = BELLY, [24816] = BELLY,
    [24817] = CHEST, [24818] = CHEST,
    [64729] = 'shoulder_l', [10706] = 'shoulder_r',
    [11816] = 'pelvis',
    [45509] = 'upper_arm_l', [61163] = 'forearm_l', [18905] = 'hand_l',
    [40269] = 'upper_arm_r', [28252] = 'forearm_r', [57005] = 'hand_r',
    [58271] = 'thigh_l', [63931] = 'lower_leg_l', [14201] = 'foot_l', [2108] = 'foot_l',
    [51826] = 'thigh_r', [36864] = 'lower_leg_r', [52301] = 'foot_r', [20781] = 'foot_r',
}
for _, id in ipairs({ 4089, 4090, 4137, 4138, 4153, 4154, 4169, 4170, 4185, 4186, 26610, 26611, 26612, 26613, 26614 }) do A.BoneMap[id] = 'hand_l' end
for _, id in ipairs({ 58866, 58867, 58868, 58869, 58870, 64016, 64017, 64064, 64065, 64080, 64081, 64096, 64097, 64112, 64113 }) do A.BoneMap[id] = 'hand_r' end

-- Body groups used by the effect model: legs drive walking, arms aiming, the head vision.
A.GroupKind = { head = 'head', neck = 'neck', torso = 'torso', pelvis = 'pelvis', arm_l = 'arm', arm_r = 'arm', leg_l = 'leg', leg_r = 'leg' }

local function pick(list, roll, weightIndex)
    local total = 0
    for _, e in ipairs(list) do total = total + e[weightIndex] end
    if total <= 0 then return nil end
    local target = (roll or 0.5) * total
    local acc = 0
    for _, e in ipairs(list) do
        acc = acc + e[weightIndex]
        if target <= acc then return e end
    end
    return list[#list]
end

--- Region for a GTA bone id. `roll` in [0, 1) picks among candidates (deterministic for a roll).
function A.RegionForBone(boneId, roll)
    local v = A.BoneMap[tonumber(boneId) or -1]
    if type(v) == 'string' then return v end
    if type(v) == 'table' then
        local e = pick(v, roll, 2)
        return e and e[1] or nil
    end
    return nil
end

function A.IsRegion(id) return type(id) == 'string' and A.Regions[id] ~= nil end
function A.IsStructure(id) return type(id) == 'string' and A.Structures[id] ~= nil end

--- True when `structure` lies in `region` (listed there, or the same limb/body group).
function A.StructureInRegion(structure, region)
    local r, s = A.Regions[region], A.Structures[structure]
    if not r or not s then return false end
    for _, e in ipairs(r.structures) do if e[1] == structure then return true end end
    return s.group == r.group
end

--- The first region that lists the structure, else a region of its body group.
function A.DefaultRegion(structure)
    local s = A.Structures[structure]
    if not s then return nil end
    local names = {}
    for name in pairs(A.Regions) do names[#names + 1] = name end
    table.sort(names)
    for _, name in ipairs(names) do
        for _, e in ipairs(A.Regions[name].structures) do if e[1] == structure then return name end end
    end
    for _, name in ipairs(names) do if A.Regions[name].group == s.group then return name end end
    return nil
end

--- Picks a structure in a region. `filter(structureId, def, depth)` limits the candidates (an
--- injury type allows only some kinds); `allowSurface` keeps skin-only entries. Returns
--- structure (or nil for skin only), depth; nothing when no entry is allowed.
function A.PickStructure(region, roll, filter, allowSurface)
    local r = A.Regions[region]
    if not r then return nil end
    local list = {}
    for _, e in ipairs(r.structures) do
        local id = e[1]
        if id == false then
            if allowSurface then list[#list + 1] = { false, e[2], e[3] } end
        elseif not filter or filter(id, A.Structures[id], e[3]) then
            list[#list + 1] = e
        end
    end
    if #list == 0 then return nil end
    local e = pick(list, roll, 2)
    if e[1] == false then return nil, e[3], true end
    return e[1], e[3], true
end

--- Armour that covers a region ('vest', 'helmet' or nil).
function A.ArmourFor(region, structure)
    local r = A.Regions[region]
    if r and r.armour then return r.armour end
    local s = A.Structures[structure]
    return s and s.armour or nil
end

--- 'leg', 'arm', 'head', 'neck', 'torso', 'pelvis' for an injury's place (nil for systemic).
function A.GroupKindOf(region, structure)
    local s = A.Structures[structure]
    if s then return A.GroupKind[s.group] end
    local r = A.Regions[region]
    if r then return A.GroupKind[r.group] end
    return nil
end
