--!native

local Grid = require(script.Parent.Grid)
local SnowCells = require(script.Parent.SnowCells)

local Flag = SnowCells.Flag

local SnowSim = {}
SnowSim.__index = SnowSim

SnowSim.EventKind = table.freeze({
	Added = 1,
	Moved = 2,
	Removed = 3,
})

local FALL_DRIFT_CHANCE = 0.05 -- 5%

local PUSH_SEARCH_LIMIT = 2^12

local SNOW_FLAGS = Flag.Snow + Flag.Flying

function SnowSim.new(cells, boundsList: { SnowCells.Bounds }, maxPileLayers: number, seed: number?)
	local self = setmetatable({}, SnowSim)
	self._cells = cells
	self._random = Random.new(seed or os.clock() * 1e6)
	self._snowCount = 0

	self._containers = boundsList
	self._floorAreas = {}
	self._totalFloorArea = 0
	for containerIndex, bounds in boundsList do
		local floorArea = (bounds.maxX - bounds.minX + 1) * (bounds.maxZ - bounds.minZ + 1)
		self._floorAreas[containerIndex] = floorArea
		self._totalFloorArea += floorArea
	end

	self._maxSnowCount = maxPileLayers * self._totalFloorArea

	self._awakeCells = {} :: { [number]: true }
	self._awakeOrder = {} :: { number }

	self._searchVisited = {} :: { [number]: true }
	self._searchQueue = {} :: { number }

	self._lowestSnowIndex = cells:GetSize()

	self._events = {}
	self._dirtyCells = {} :: { [number]: true }
	return self
end

function SnowSim:GetSnowCount(): number
	return self._snowCount
end

function SnowSim:GetCellCenter(cellIndex: number): Vector3
	return Grid.CellToWorld(self._cells:GetPosition(cellIndex))
end

function SnowSim:GetEvents()
	return self._events
end

function SnowSim:GetDirtyCells(): { [number]: true }
	return self._dirtyCells
end

function SnowSim:ClearEvents()
	table.clear(self._events)
	table.clear(self._dirtyCells)
end

function SnowSim:AddSnow(x: number, y: number, z: number): boolean
	local cellIndex = self._cells:GetIndex(x, y, z)
	
	if not cellIndex or not self._cells:IsEmpty(cellIndex) then
		return false
	end

	self._cells:AddFlags(cellIndex, Flag.Snow)
	self._snowCount += 1
	self:_onSnowArrived(cellIndex)
	self:_addEvent(SnowSim.EventKind.Added, cellIndex)
	
	return true
end

function SnowSim:MoveSnow(fromIndex: number, toIndex: number)
	local snowFlags = bit32.band(self._cells:GetFlags(fromIndex), SNOW_FLAGS)
	self._cells:RemoveFlags(fromIndex, SNOW_FLAGS)
	self._cells:AddFlags(toIndex, snowFlags)

	self:_onSnowLeft(fromIndex)
	self:_onSnowArrived(toIndex)
	self:_addEvent(SnowSim.EventKind.Moved, fromIndex, toIndex)
end

function SnowSim:RemoveSnow(cellIndex: number)
	if not self._cells:HasFlag(cellIndex, Flag.Snow) then
		return
	end

	self._cells:RemoveFlags(cellIndex, SNOW_FLAGS)
	self._snowCount -= 1
	self:_onSnowLeft(cellIndex)
	self:_addEvent(SnowSim.EventKind.Removed, cellIndex)
end

function SnowSim:StartFlying(cellIndex: number)
	self._cells:AddFlags(cellIndex, Flag.Flying)
end

function SnowSim:StopFlying(cellIndex: number)
	self._cells:RemoveFlags(cellIndex, Flag.Flying)
	self._awakeCells[cellIndex] = true
	
	if self._cells:HasFlag(cellIndex, Flag.MovingObstacle) then
		self:PushSnowOut(cellIndex)
	end
end

function SnowSim:PushSnowOut(cellIndex: number)
	if not self._cells:HasFlag(cellIndex, Flag.Snow) then
		return
	end

	local targetIndex = self:_findNearestEmpty(cellIndex) or self:_findEmptyAbove(cellIndex)
	if targetIndex then
		self:MoveSnow(cellIndex, targetIndex)
	else
		self:RemoveSnow(cellIndex)
	end
end

function SnowSim:WakeCellsAbove(cellIndex: number)
	local aboveIndex = self._cells:GetAbove(cellIndex)
	
	self:_wake(aboveIndex)
	
	for _, offset in self._cells.HorizontalOffsets do
		self:_wake(aboveIndex + offset)
	end
end

function SnowSim:IsCellVisible(cellIndex: number): boolean
	local cells = self._cells
	if not cells:HasFlag(cellIndex, Flag.Snow) then
		return false
	end
	
	if not cells:HasFlag(cells:GetAbove(cellIndex), Flag.Snow) then
		return true
	end
	
	for _, offset in cells.HorizontalOffsets do
		if not cells:HasFlag(cellIndex + offset, Flag.Snow) then
			return true
		end
	end
	
	return false
end

function SnowSim:Step()
	local awakeCells = self._awakeCells
	if next(awakeCells) == nil then
		return
	end

	local awakeOrder = self._awakeOrder
	table.clear(awakeOrder)
	for cellIndex in awakeCells do
		table.insert(awakeOrder, cellIndex)
	end
	table.sort(awakeOrder)

	for _, cellIndex in awakeOrder do
		self:_stepCell(cellIndex)
	end
end

function SnowSim:SpawnSnow(cellsPerTick: number)
	local spawnCount = math.floor(cellsPerTick)
	if self._random:NextNumber() < cellsPerTick - spawnCount then
		spawnCount += 1
	end

	for _ = 1, spawnCount do
		if self._maxSnowCount > 0 and self._snowCount >= self._maxSnowCount then
			self:_removeLowestSnow()
		end
		self:_spawnOne()
	end
end

function SnowSim:_stepCell(cellIndex: number)
	local cells = self._cells

	if not cells:HasFlag(cellIndex, Flag.Snow) or cells:HasFlag(cellIndex, Flag.Flying) then
		self._awakeCells[cellIndex] = nil
		return
	end

	local belowIndex = cells:GetBelow(cellIndex)
	if cells:IsEmpty(belowIndex) then
		local targetIndex = belowIndex
		if self._random:NextNumber() < FALL_DRIFT_CHANCE then
			local driftIndex = belowIndex + cells.HorizontalOffsets[self._random:NextInteger(1, #cells.HorizontalOffsets)]
			if cells:IsEmpty(driftIndex) then
				targetIndex = driftIndex
			end
		end
		self:MoveSnow(cellIndex, targetIndex)
		return
	end

	local slideIndex = self:_getRandomEmptyNeighbor(belowIndex)
	if slideIndex then
		self:MoveSnow(cellIndex, slideIndex)
	else
		self._awakeCells[cellIndex] = nil
	end
end

function SnowSim:_getRandomEmptyNeighbor(cellIndex: number): number?
	local cells = self._cells
	local emptyCount = 0
	for _, offset in cells.HorizontalOffsets do
		if cells:IsEmpty(cellIndex + offset) then
			emptyCount += 1
		end
	end
	if emptyCount == 0 then
		return nil
	end

	local remainingChoices = self._random:NextInteger(1, emptyCount)
	for _, offset in cells.HorizontalOffsets do
		if not cells:IsEmpty(cellIndex + offset) then
			continue
		end
		remainingChoices -= 1
		if remainingChoices == 0 then
			return cellIndex + offset
		end
	end
	return nil
end

function SnowSim:_spawnOne()
	local roll = self._random:NextInteger(1, self._totalFloorArea)
	
	for containerIndex, bounds in self._containers do
		roll -= self._floorAreas[containerIndex]
		if roll > 0 then
			continue
		end
		
		self:AddSnow(
			self._random:NextInteger(bounds.minX, bounds.maxX),
			bounds.maxY,
			self._random:NextInteger(bounds.minZ, bounds.maxZ)
		)
		
		return
	end
end

function SnowSim:_removeLowestSnow()
	local cells = self._cells
	
	for cellIndex = self._lowestSnowIndex, cells:GetSize() - 1 do
		if cells:HasFlag(cellIndex, Flag.Snow) then
			self._lowestSnowIndex = cellIndex
			self:RemoveSnow(cellIndex)
			return
		end
	end
end

function SnowSim:_findNearestEmpty(startIndex: number): number?
	local cells = self._cells
	local visited = self._searchVisited
	local queue = self._searchQueue
	table.clear(visited)
	table.clear(queue)
	visited[startIndex] = true
	queue[1] = startIndex
	local queueHead = 1

	while queueHead <= #queue and queueHead <= PUSH_SEARCH_LIMIT do
		local currentIndex = queue[queueHead]
		queueHead += 1

		for _, offset in cells.NeighborOffsets do
			local neighborIndex = currentIndex + offset
			if visited[neighborIndex] then
				continue
			end
			visited[neighborIndex] = true

			if cells:IsEmpty(neighborIndex) then
				return neighborIndex
			end
			
			if not cells:HasFlag(neighborIndex, Flag.Outside) then
				table.insert(queue, neighborIndex)
			end
		end
	end
	return nil
end

function SnowSim:_findEmptyAbove(cellIndex: number): number?
	local cells = self._cells
	local aboveIndex = cells:GetAbove(cellIndex)
	
	while aboveIndex < cells:GetSize() do
		if cells:IsEmpty(aboveIndex) then
			return aboveIndex
		end
		aboveIndex = cells:GetAbove(aboveIndex)
	end
	
	return nil
end

function SnowSim:_onSnowArrived(cellIndex: number)
	self._awakeCells[cellIndex] = true
	self._lowestSnowIndex = math.min(self._lowestSnowIndex, cellIndex)
	self:_markDirty(cellIndex)
end

function SnowSim:_onSnowLeft(cellIndex: number)
	self._awakeCells[cellIndex] = nil
	self:WakeCellsAbove(cellIndex)
	self:_markDirty(cellIndex)
end

function SnowSim:_wake(cellIndex: number)
	if self._cells:HasFlag(cellIndex, Flag.Snow) then
		self._awakeCells[cellIndex] = true
	end
end

function SnowSim:_markDirty(cellIndex: number)
	local dirtyCells = self._dirtyCells
	
	dirtyCells[cellIndex] = true
	dirtyCells[self._cells:GetBelow(cellIndex)] = true
	
	for _, offset in self._cells.HorizontalOffsets do
		dirtyCells[cellIndex + offset] = true
	end
end

function SnowSim:_addEvent(kind: number, cellIndex: number, toIndex: number?)
	table.insert(self._events, { kind = kind, cellIndex = cellIndex, toIndex = toIndex })
end

return SnowSim
