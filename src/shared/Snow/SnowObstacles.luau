local SnowCells = require(script.Parent.SnowCells)

local Flag = SnowCells.Flag
local OBSTACLE_FLAGS = Flag.StaticObstacle + Flag.MovingObstacle

local SnowObstacles = {}
SnowObstacles.__index = SnowObstacles

function SnowObstacles.new(cells, snowSim)
	local self = setmetatable({}, SnowObstacles)
	
	self._cells = cells
	self._snowSim = snowSim
	self._ownerByCell = {} :: { [number]: BasePart }
	self._cellsByPart = {} :: { [BasePart]: { [number]: true } }
	
	return self
end

function SnowObstacles:AddStaticPart(part: BasePart)
	assert(
		self._snowSim:GetSnowCount() == 0 and next(self._cellsByPart) == nil,
		"add static obstacles before the simulation starts"
	)
	
	self._cells:FillPart(part, Flag.StaticObstacle)
end

function SnowObstacles:UpdateMovingPart(part: BasePart)
	local oldCells = self._cellsByPart[part] or {}
	local newCells = {}
	for _, cellIndex in self._cells:GetCellsInPart(part) do
		newCells[cellIndex] = true
	end

	for cellIndex in oldCells do
		if not newCells[cellIndex] then
			self:_release(cellIndex, part)
		end
	end
	self:_claim(part, newCells)

	self._cellsByPart[part] = if next(newCells) then newCells else nil
end

function SnowObstacles:RemoveMovingPart(part: BasePart)
	local oldCells = self._cellsByPart[part]
	
	if not oldCells then
		return
	end
	
	for cellIndex in oldCells do
		self:_release(cellIndex, part)
	end
	
	self._cellsByPart[part] = nil
end

function SnowObstacles:_claim(part: BasePart, cellIndices: { [number]: true })
	local cells = self._cells
	local snowToPush = {}

	for cellIndex in cellIndices do
		if cells:HasFlag(cellIndex, OBSTACLE_FLAGS) then
			continue
		end

		cells:AddFlags(cellIndex, Flag.MovingObstacle)
		
		self._ownerByCell[cellIndex] = part
		
		if cells:HasFlag(cellIndex, Flag.Snow) and not cells:HasFlag(cellIndex, Flag.Flying) then
			table.insert(snowToPush, cellIndex)
		end
	end

	for _, cellIndex in snowToPush do
		self._snowSim:PushSnowOut(cellIndex)
	end
end

function SnowObstacles:_release(cellIndex: number, part: BasePart)
	if self._ownerByCell[cellIndex] ~= part then
		return
	end
	
	self._ownerByCell[cellIndex] = nil
	
	self._cells:RemoveFlags(cellIndex, Flag.MovingObstacle)
	
	if self._cells:IsEmpty(cellIndex) then
		self._snowSim:WakeCellsAbove(cellIndex)
	end
end

return SnowObstacles
