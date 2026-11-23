--!strict

local SnowSim = require(script.Parent.SnowSim)
local Grid = require(script.Parent.Grid)

local SnowRenderer = {}
SnowRenderer.__index = SnowRenderer

local INLET_CHANCE = 0.15 -- 15%
local POOL_BATCH_SIZE = 500

local HIDDEN_CFRAME = CFrame.new(1e50, 1e50, 1e50)

local function makeTemplatePart(): Part
	local part = Instance.new("Part")
	part.Size = Grid.TileSize
	part.Anchored = true
	part.CanCollide = false
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = false
	part.Material = Enum.Material.Plastic
	part.Color = Color3.fromRGB(245, 250, 255)
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Transparency = 1
	
	return part
end

function SnowRenderer.new(parent: Instance, snowSim: any)
	local self = setmetatable({}, SnowRenderer)
	
	self._parent = parent
	self._snowSim = snowSim
	self._template = makeTemplatePart()
	self._freeParts = {} :: { Part }
	self._partByCell = {} :: { [number]: Part }
	self._inletCells = {} :: { [number]: true }
	
	return self
end

function SnowRenderer:Render()
	local snowSim = self._snowSim
	local movedFrom = self:_trackInlets()

	local cellsToShow = {}
	local spareParts = {} :: { [number]: Part }
	for cellIndex in snowSim:GetDirtyCells() do
		local isVisible = snowSim:IsCellVisible(cellIndex)
		local part = self._partByCell[cellIndex]
		
		if isVisible and not part then
			table.insert(cellsToShow, cellIndex)
		elseif part and not isVisible then
			spareParts[cellIndex] = part
			self._partByCell[cellIndex] = nil
		elseif part then
			self:_setTopSurface(part, cellIndex)
		end
	end

	local partsToMove: { Part } = {}
	local targetCFrames: { CFrame } = {}

	local cellsWithoutPart = {}
	for _, cellIndex in cellsToShow do
		local sourceCell = movedFrom[cellIndex]
		local part = sourceCell and spareParts[sourceCell]
		
		if part then
			spareParts[sourceCell] = nil
			self:_place(part, cellIndex, partsToMove, targetCFrames)
		else
			table.insert(cellsWithoutPart, cellIndex)
		end
	end

	for _, cellIndex in cellsWithoutPart do
		local sourceCell, part = next(spareParts)
		
		if sourceCell then
			spareParts[sourceCell] = nil
		else
			part = self:_takeFromPool()
		end
		
		self:_place(part :: Part, cellIndex, partsToMove, targetCFrames)
	end

	for _, part in spareParts do
		part.Transparency = 1
		table.insert(self._freeParts, part)
		table.insert(partsToMove, part)
		table.insert(targetCFrames, HIDDEN_CFRAME)
	end

	if #partsToMove > 0 then
		workspace:BulkMoveTo(partsToMove, targetCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

function SnowRenderer:_trackInlets(): { [number]: number }
	local inletCells = self._inletCells
	local movedFrom = {}

	for _, event in self._snowSim:GetEvents() do
		if event.kind == SnowSim.EventKind.Added then
			inletCells[event.cellIndex] = if math.random() < INLET_CHANCE then true else nil
		elseif event.kind == SnowSim.EventKind.Moved then
			inletCells[event.toIndex] = inletCells[event.cellIndex]
			inletCells[event.cellIndex] = nil
			movedFrom[event.toIndex] = event.cellIndex
		else
			inletCells[event.cellIndex] = nil
		end
	end
	
	return movedFrom
end

function SnowRenderer:_place(part: Part, cellIndex: number, partsToMove: { Part }, targetCFrames: { CFrame })
	self:_setTopSurface(part, cellIndex)
	
	self._partByCell[cellIndex] = part
	
	table.insert(partsToMove, part)
	
	table.insert(targetCFrames, CFrame.new(self._snowSim:GetCellCenter(cellIndex)))
end

function SnowRenderer:_setTopSurface(part: Part, cellIndex: number)
	local topSurface = if self._inletCells[cellIndex] then Enum.SurfaceType.Inlet else Enum.SurfaceType.Smooth
	
	if part.TopSurface ~= topSurface then
		part.TopSurface = topSurface
	end
end

function SnowRenderer:_takeFromPool(): Part
	if #self._freeParts == 0 then
		self:_growPool()
	end
	
	local part = table.remove(self._freeParts) :: Part
	part.Transparency = 0
	
	return part
end

function SnowRenderer:_growPool()
	local newParts: { Part } = {}
	local hiddenCFrames: { CFrame } = {}
	
	for partIndex = 1, POOL_BATCH_SIZE do
		local part = self._template:Clone()
		part.Parent = self._parent
		newParts[partIndex] = part
		hiddenCFrames[partIndex] = HIDDEN_CFRAME
	end
	
	workspace:BulkMoveTo(newParts, hiddenCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	
	table.move(newParts, 1, #newParts, #self._freeParts + 1, self._freeParts)
end

return SnowRenderer
