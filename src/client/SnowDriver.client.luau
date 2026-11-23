task.wait(5)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local snowModules = ReplicatedStorage:WaitForChild("Snow")
local Grid = require(snowModules.Grid)
local SnowCells = require(snowModules.SnowCells)
local SnowSim = require(snowModules.SnowSim)
local SnowObstacles = require(snowModules.SnowObstacles)
local SnowKick = require(snowModules.SnowKick)
local SnowRenderer = require(snowModules.SnowRenderer)

local MAX_PILE_LAYERS = 8

local MIN_KICK_SPEED = 2

local STATIC_LOAD_BUDGET_SECONDS = 0.004

local MAX_CATCH_UP_SECONDS = 0.1

local CELLS_PER_TICK_ATTRIBUTE = "CellsPerTick"
local TICKS_PER_SECOND_ATTRIBUTE = "TicksPerSecond"

--Parts must be marked BEFORE running the game, as it doesn't take in account updating attributes at run time
local SNOW_IGNORE_ATTRIBUTE = "SnowIgnore"
local SNOW_UPDATE_ATTRIBUTE = "SnowUpdate"

local containerFolder = workspace:WaitForChild("SnowContainers")
local containerParts = {}
local boundsList = {}
for _, child in containerFolder:GetChildren() do
	if not child:IsA("BasePart") then
		continue
	end
	local minX, minY, minZ, maxX, maxY, maxZ = Grid.GetCellBounds(child)
	table.insert(containerParts, child)
	table.insert(boundsList, {
		minX = minX,
		minY = minY,
		minZ = minZ,
		maxX = maxX,
		maxY = maxY,
		maxZ = maxZ,
	})
end
assert(#boundsList > 0, "SnowContainers must contain at least one BasePart")

local visualsFolder = Instance.new("Folder")
visualsFolder.Name = "SnowVisuals"
visualsFolder.Parent = workspace

local cells = SnowCells.new(boundsList)
local snowSim = SnowSim.new(cells, boundsList, MAX_PILE_LAYERS)
local obstacles = SnowObstacles.new(cells, snowSim)
local kick = SnowKick.new(cells, snowSim)
local renderer = SnowRenderer.new(visualsFolder, snowSim)

local function hasAttribute(instance: Instance, attributeName: string): boolean
	local current: Instance? = instance
	while current and current ~= workspace do
		if current:GetAttribute(attributeName) == true then
			return true
		end
		current = current.Parent
	end
	return false
end

local function findCharacter(part: BasePart): Model?
	local model = part:FindFirstAncestorOfClass("Model")
	while model and not Players:GetPlayerFromCharacter(model) do
		model = model:FindFirstAncestorOfClass("Model")
	end
	return model
end

local snowUpdateParts: { [BasePart]: true } = {}

local function trackSnowUpdatePart(instance: Instance)
	if instance:IsA("BasePart") and hasAttribute(instance, SNOW_UPDATE_ATTRIBUTE) then
		snowUpdateParts[instance] = true
	end
end

for _, descendant in workspace:GetDescendants() do
	trackSnowUpdatePart(descendant)
end
workspace.DescendantAdded:Connect(trackSnowUpdatePart)
workspace.DescendantRemoving:Connect(function(descendant: Instance)
	snowUpdateParts[descendant :: BasePart] = nil
end)

local function isStaticObstacle(part: BasePart): boolean
	return part:IsGrounded()
		and not hasAttribute(part, SNOW_IGNORE_ATTRIBUTE)
		and not hasAttribute(part, SNOW_UPDATE_ATTRIBUTE)
		and findCharacter(part) == nil
end

local function loadStaticObstacles()
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.FilterDescendantsInstances = { containerFolder, visualsFolder }

	local loadedParts = {}
	local frameStartTime = os.clock()
	for _, containerPart in containerParts do
		for _, part in workspace:GetPartsInPart(containerPart, overlapParams) do
			if loadedParts[part] or not isStaticObstacle(part) then
				continue
			end
			loadedParts[part] = true
			obstacles:AddStaticPart(part)

			if os.clock() - frameStartTime > STATIC_LOAD_BUDGET_SECONDS then
				task.wait()
				frameStartTime = os.clock()
			end
		end
	end
end

local movingParts: { [BasePart]: true } = {}

local function updateMovingPart(part: BasePart, updatedParts: { [BasePart]: true })
	if updatedParts[part] or hasAttribute(part, SNOW_IGNORE_ATTRIBUTE) then
		return
	end
	updatedParts[part] = true

	local character = findCharacter(part)
	local rootPart = character and character:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart.AssemblyLinearVelocity.Magnitude >= MIN_KICK_SPEED then
		kick:Kick(part, rootPart.Position)
	end
	
	obstacles:UpdateMovingPart(part)
end

local function updateMovingParts()
	local updatedParts: { [BasePart]: true } = {}

	for _, player in Players:GetPlayers() do
		if not player.Character then
			continue
		end
		for _, descendant in player.Character:GetDescendants() do
			if descendant:IsA("BasePart") then
				updateMovingPart(descendant, updatedParts)
			end
		end
	end

	for part in snowUpdateParts do
		if hasAttribute(part, SNOW_UPDATE_ATTRIBUTE) then
			updateMovingPart(part, updatedParts)
		end
	end

	for part in movingParts do
		if not updatedParts[part] then
			obstacles:RemoveMovingPart(part)
		end
	end
	
	movingParts = updatedParts
end

loadStaticObstacles()

local nextTickTime = time()

RunService.RenderStepped:Connect(function()
	local ticksPerSecond = script:GetAttribute(TICKS_PER_SECOND_ATTRIBUTE)
	if ticksPerSecond <= 0 then
		return
	end

	local now = time()
	nextTickTime = math.max(nextTickTime, now - MAX_CATCH_UP_SECONDS)
	if nextTickTime > now then
		return
	end

	updateMovingParts()

	local secondsPerTick = 1 / ticksPerSecond
	while nextTickTime <= now do
		nextTickTime += secondsPerTick
		kick:Update()
		snowSim:SpawnSnow(script:GetAttribute(CELLS_PER_TICK_ATTRIBUTE))
		snowSim:Step()
	end

	renderer:Render()
	snowSim:ClearEvents()
end)
