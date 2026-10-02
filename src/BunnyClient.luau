--[[
	BunnyClient.luau
	Type:  LocalScript
	Path:  StarterPlayer.StarterPlayerScripts.BunnyClient

	Drives the mushroom bunny's hop animation on each player's machine.
	Skips updating when the camera is far away, since the animation has no
	gameplay effect and there's no reason to spend the per-frame cost on it
	for someone who can't see it.

	Expects:
		ReplicatedStorage.BunnyAnimator     (ModuleScript)
		Workspace.MushroomBunny             (Model, PrimaryPart = Root,
		                                      see BunnyAnimator.luau for the
		                                      expected rig structure)
]]

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Animator = require(ReplicatedStorage:WaitForChild("BunnyAnimator"))

local model = workspace:WaitForChild("MushroomBunny")
model:WaitForChild("Root")
model:WaitForChild("Pivot_Body")

local rig = Animator.bind(model)
local MAX_RELEVANT_DISTANCE = 400

RunService.RenderStepped:Connect(function()
	local camera = workspace.CurrentCamera
	if camera and (camera.CFrame.Position - rig.root.Position).Magnitude > MAX_RELEVANT_DISTANCE then
		return
	end
	Animator.update(rig, workspace:GetServerTimeNow())
end)
