--!native

local Grid = require(script.Parent.Grid)

local SnowCells = {}
SnowCells.__index = SnowCells

SnowCells.Flag = table.freeze({
	Snow = 1,
	StaticObstacle = 2, --map geometry that never moves
	MovingObstacle = 4, --a part that is checked every tick
	Flying = 8, --kicked snow on its way to a target
	Outside = 16, --the border or a gap between containers
})

local EMPTY = 0

export type Bounds = {
	minX: number,
	minY: number,
	minZ: number,
	maxX: number,
	maxY: number,
	maxZ: number,
}

function SnowCells.new(boundsList: { Bounds })
	local self = setmetatable({}, SnowCells)

	--bounding box of all containers
	self._minX, self._minY, self._minZ = math.huge, math.huge, math.huge
	self._maxX, self._maxY, self._maxZ = -math.huge, -math.huge, -math.huge
	for _, bounds in boundsList do
		self._minX = math.min(self._minX, bounds.minX)
		self._minY = math.min(self._minY, bounds.minY)
		self._minZ = math.min(self._minZ, bounds.minZ)
		self._maxX = math.max(self._maxX, bounds.maxX)
		self._maxY = math.max(self._maxY, bounds.maxY)
		self._maxZ = math.max(self._maxZ, bounds.maxZ)
	end

	--buffer index 0 is the border cell below each min
	self._originX, self._originY, self._originZ = self._minX - 1, self._minY - 1, self._minZ - 1
	self._width = self._maxX - self._minX + 3
	self._depth = self._maxZ - self._minZ + 3
	self._layerSize = self._width * self._depth
	local height = self._maxY - self._minY + 3

	self.HorizontalOffsets = { 1, -1, self._width, -self._width }
	self.NeighborOffsets = { 1, -1, self._width, -self._width, self._layerSize, -self._layerSize }

	--mark every cell outside then clear each container to empty
	self._buffer = buffer.create(self._layerSize * height)
	buffer.fill(self._buffer, 0, SnowCells.Flag.Outside)
	for _, bounds in boundsList do
		for y = bounds.minY, bounds.maxY do
			for z = bounds.minZ, bounds.maxZ do
				self:_fillRow(y, z, bounds.minX, bounds.maxX, EMPTY)
			end
		end
	end

	return self
end

function SnowCells:GetSize(): number
	return buffer.len(self._buffer)
end

function SnowCells:GetIndex(x: number, y: number, z: number): number?
	if x < self._minX or x > self._maxX
		or y < self._minY or y > self._maxY
		or z < self._minZ or z > self._maxZ then
		return nil
	end
	
	return self:_getIndexUnchecked(x, y, z)
end

--grid coordinates of a cell index
function SnowCells:GetPosition(cellIndex: number): (number, number, number)
	return cellIndex % self._width + self._originX,
		cellIndex // self._layerSize + self._originY,
		(cellIndex // self._width) % self._depth + self._originZ
end

function SnowCells:GetAbove(cellIndex: number): number
	return cellIndex + self._layerSize
end

function SnowCells:GetBelow(cellIndex: number): number
	return cellIndex - self._layerSize
end

function SnowCells:GetFlags(cellIndex: number): number
	return buffer.readu8(self._buffer, cellIndex)
end

function SnowCells:IsEmpty(cellIndex: number): boolean
	return buffer.readu8(self._buffer, cellIndex) == EMPTY
end

--true when the cell has any of the flags
function SnowCells:HasFlag(cellIndex: number, flags: number): boolean
	return bit32.band(buffer.readu8(self._buffer, cellIndex), flags) ~= 0
end

function SnowCells:AddFlags(cellIndex: number, flags: number)
	buffer.writeu8(self._buffer, cellIndex, bit32.bor(buffer.readu8(self._buffer, cellIndex), flags))
end

function SnowCells:RemoveFlags(cellIndex: number, flags: number)
	buffer.writeu8(self._buffer, cellIndex, bit32.band(buffer.readu8(self._buffer, cellIndex), bit32.bnot(flags)))
end

function SnowCells:FillPart(part: BasePart, flags: number)
	for _, row in Grid.GetRowsInPart(part) do
		local minX, maxX = self:_clipRow(row)
		if minX then
			self:_fillRow(row.y, row.z, minX, maxX, flags)
		end
	end
end

function SnowCells:GetCellsInPart(part: BasePart): { number }
	local cellIndices = {}
	
	for _, row in Grid.GetRowsInPart(part) do
		local minX, maxX = self:_clipRow(row)
		if not minX then
			continue
		end
		for x = minX, maxX do
			table.insert(cellIndices, self:_getIndexUnchecked(x, row.y, row.z))
		end
	end
	
	return cellIndices
end

function SnowCells:_getIndexUnchecked(x: number, y: number, z: number): number
	return (x - self._originX) + (z - self._originZ) * self._width + (y - self._originY) * self._layerSize
end

function SnowCells:_clipRow(row: Grid.Row): (number?, number?)
	if row.y < self._minY or row.y > self._maxY or row.z < self._minZ or row.z > self._maxZ then
		return nil, nil
	end
	
	local minX = math.max(row.minX, self._minX)
	local maxX = math.min(row.maxX, self._maxX)
	
	if minX > maxX then
		return nil, nil
	end
	
	return minX, maxX
end

function SnowCells:_fillRow(y: number, z: number, minX: number, maxX: number, flags: number)
	buffer.fill(self._buffer, self:_getIndexUnchecked(minX, y, z), flags, maxX - minX + 1)
end

return SnowCells
