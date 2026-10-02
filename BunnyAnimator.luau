--[[
	BunnyAnimator.luau
	Type:  ModuleScript
	Path:  ReplicatedStorage.BunnyAnimator

	Pure procedural animation for a small hopping "mushroom bunny" character.
	Like DinoAnimator, every pose is a function of a single synced time
	value, so every client renders the same hop at the same moment without
	replicating per-frame state.

	The bunny's body is split into six rigid groups, each a child Motor6D
	under the model, all parented under Workspace.MushroomBunny:
		Root (PrimaryPart, anchored anchor point)
		 └ Pivot_Body (Motor6D "Body")
		    ├ Pivot_Head (Motor6D "Head")
		    │   ├ Pivot_Cap  (Motor6D "Cap")  -- the mushroom cap, wobbles on landing
		    │   ├ Pivot_Eyes (Motor6D "Eyes") -- blinks by sinking back into the head
		    │   └ Pivot_Nose (Motor6D "Nose") -- twitches
		    └ Pivot_Mush (Motor6D "Mush")     -- small back mushrooms, wobble too
	Every visible block of the model is welded (WeldConstraint) to whichever
	of these six pivots it visually belongs to. Every Motor6D needs a
	"BaseC0" CFrame Attribute holding its rest-pose C0.
]]

local M = {}

local HOP_AIR_TIME = 0.52   -- seconds spent in the air per hop
local WANDER_RADIUS = 9.5   -- how far from its home point the bunny may roam (studs)

local function smooth(x)
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function lerpAngle(a, b, f)
	local delta = (b - a + math.pi) % (2 * math.pi) - math.pi
	return a + delta * f
end

-- ===================== Hop plan =====================
-- A closed loop through random waypoints, cut into short hops (<= 4 studs)
-- with varied pauses between them, computed once at load time so every
-- client's hop schedule is identical.
local rng = Random.new(20260921)
local waypoints = {}
for i = 1, 9 do
	local angle = rng:NextNumber(0, math.pi * 2)
	local radius = math.sqrt(rng:NextNumber(0.08, 1)) * WANDER_RADIUS
	waypoints[i] = Vector2.new(math.cos(angle) * radius, math.sin(angle) * radius)
end

local hops = {}
for i = 1, #waypoints do
	local a, b = waypoints[i], waypoints[i % #waypoints + 1]
	local segmentLength = (b - a).Magnitude
	if segmentLength > 0.6 then
		local hopsInSegment = math.max(1, math.ceil(segmentLength / 4.0))
		for k = 1, hopsInSegment do
			table.insert(hops, { from = a:Lerp(b, (k - 1) / hopsInSegment), to = a:Lerp(b, k / hopsInSegment) })
		end
	end
end

local cursor = 0
for _, hop in ipairs(hops) do
	local delta = hop.to - hop.from
	hop.length = delta.Magnitude
	hop.yaw = math.atan2(-delta.X, -delta.Y) -- model faces -Z; Vector2.Y maps to world Z
	hop.height = 0.6 + 0.2 * hop.length       -- longer hops arc higher

	local roll = rng:NextNumber()
	if roll < 0.25 then
		hop.pause = rng:NextNumber(0.14, 0.28)   -- quick follow-up hop
	elseif roll < 0.85 then
		hop.pause = rng:NextNumber(0.6, 1.7)     -- normal pause
	else
		hop.pause = rng:NextNumber(1.9, 3.3)     -- longer "sniffing around" pause
	end

	hop.startTime = cursor
	cursor += hop.pause + HOP_AIR_TIME
end
local loopLength = cursor

M.hops = hops
M.loopLength = loopLength
M.HOP_AIR_TIME = HOP_AIR_TIME

-- Finds which hop is active at time t (mod loopLength) and how far through
-- it we are, returning ground/air position, facing, height, and a few
-- derived values the pose code needs (crouch, landing impact, time-since-land).
local function stateAt(t)
	t = t % loopLength
	local lo, hi = 1, #hops
	while lo < hi do
		local mid = math.floor((lo + hi + 1) / 2)
		if hops[mid].startTime <= t then lo = mid else hi = mid - 1 end
	end
	local hop = hops[lo]
	local prevHop = hops[(lo - 2) % #hops + 1]
	local elapsed = t - hop.startTime
	local state = {}

	if elapsed < hop.pause then
		-- On the ground: turn to face the next hop, look around, crouch just before leaping.
		state.inAir = false
		state.pos = hop.from
		local turnDuration = math.min(0.45, hop.pause * 0.7)
		state.yaw = lerpAngle(prevHop.yaw, hop.yaw, smooth(elapsed / turnDuration))
		state.height = 0
		state.crouch = smooth((elapsed - (hop.pause - 0.17)) / 0.17)
		state.landImpact = elapsed < 0.24 and math.sin(math.pi * elapsed / 0.24) or 0
		state.timeSinceLand = elapsed
	else
		-- In the air: parabolic arc from hop.from to hop.to.
		local airFrac = (elapsed - hop.pause) / HOP_AIR_TIME
		state.inAir = true
		state.pos = hop.from:Lerp(hop.to, airFrac)
		state.yaw = hop.yaw
		state.height = hop.height * 4 * airFrac * (1 - airFrac)
		state.crouch = 0
		state.landImpact = 0
		state.timeSinceLand = 9 -- "a while ago", so landing-wobble fades out while airborne
	end
	return state
end
M.stateAt = stateAt

-- Two offset blink timers so blinking doesn't look perfectly metronomic.
local function blink(t)
	local b = 0
	for _, period in ipairs({ 3.1, 4.7 }) do
		local x = (t % period) / 0.13
		if x < 1 then b = math.max(b, math.sin(math.pi * x)) end
	end
	return b
end

-- A short, repeating burst envelope: 0 most of the time, a sine pulse near
-- the start of each period. Used to drive the nose twitch.
local function burst(t, period, duration)
	local phase = (t % period) / period
	local activeFrac = duration / period
	if phase < activeFrac then
		return math.sin(math.pi * phase / activeFrac)
	end
	return 0
end

-- ===================== Rig binding =====================
function M.bind(model)
	local rig = { model = model, root = model.PrimaryPart or model:FindFirstChild("Root"), joints = {} }
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then
			rig.joints[d.Name] = { motor = d, restPose = d:GetAttribute("BaseC0") or d.C0 }
		end
	end
	rig.home = model:GetAttribute("Home") or rig.root.Position
	return rig
end

local function pose(rig, jointName, rx, ry, rz, dx, dy, dz)
	local j = rig.joints[jointName]
	if not j then return end
	j.motor.C0 = j.restPose * CFrame.new(dx or 0, dy or 0, dz or 0) * CFrame.Angles(rx or 0, ry or 0, rz or 0)
end

function M.reset(rig)
	for _, j in pairs(rig.joints) do
		j.motor.C0 = j.restPose
	end
end

-- ===================== Main update =====================
function M.update(rig, t)
	local state = stateAt(t)
	local crouch, landImpact = state.crouch, state.landImpact

	local worldPos = Vector3.new(rig.home.X + state.pos.X, rig.home.Y + state.height, rig.home.Z + state.pos.Y)
	rig.root.CFrame = CFrame.new(worldPos) * CFrame.Angles(0, state.yaw, 0)

	-- Body: crouches before the jump, nose-up on take-off, nose-down + squash on landing.
	local pitch = -0.10 * crouch - 0.14 * landImpact
	pose(rig, "Body", pitch, 0, 0, 0, -0.30 * crouch - 0.26 * landImpact + 0.02 * math.sin(t * 2.2), 0)

	-- Head: stays roughly level, looks around a little while resting.
	local look = state.inAir and 0 or (0.16 * math.sin(t * 0.8) * (1 - crouch))
	pose(rig, "Head", -0.55 * pitch + 0.04 * math.sin(t * 1.7), look, 0)

	-- Mushroom cap + small back mushrooms: heavy, so they lag and wobble
	-- for a moment after every landing (exponentially-decaying wiggle).
	local wobble = math.exp(-7 * state.timeSinceLand) * math.sin(24 * state.timeSinceLand)
	pose(rig, "Cap", -0.7 * pitch + 0.16 * wobble + 0.02 * math.sin(t * 1.3), 0,
		0.05 * math.sin(t * 1.7) + 0.08 * wobble, 0, 0.10 * wobble, 0)
	pose(rig, "Mush", 0.20 * wobble, 0, 0.06 * wobble, 0, 0.12 * wobble, 0)

	-- Eyes: "blink" by sinking back into the head along +Z.
	pose(rig, "Eyes", 0, 0, 0, 0, 0, 0.34 * blink(t))

	-- Nose: twitches in short bursts, more often while sitting still.
	local twitchEnergy = math.max(burst(t, 1.7, 0.9), 0.8 * burst(t, 2.9, 1.2))
	if state.inAir then twitchEnergy *= 0.45 end
	pose(rig, "Nose",
		0.22 * twitchEnergy * math.sin(t * 25), 0, 0,
		0, 0.06 * twitchEnergy * math.sin(t * 28), 0.05 * twitchEnergy * math.sin(t * 22 + 1))

	return state
end

return M
