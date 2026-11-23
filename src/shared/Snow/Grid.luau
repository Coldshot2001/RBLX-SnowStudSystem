--!strict
local Grid = {}

Grid.TileSize = Vector3.new(1, 0.25, 1)

local BOX_CORNER_COUNT = 8
local SLOPE_EPSILON = 1e-9

export type Row = {
	y: number,
	z: number,
	minX: number,
	maxX: number,
}

function Grid.CellToWorld(x: number, y: number, z: number): Vector3
	return Vector3.new(x + 0.5, y + 0.5, z + 0.5) * Grid.TileSize
end

function Grid.GetCellBounds(part: BasePart): (number, number, number, number, number, number)
	local halfSize = part.Size * 0.5
	local minCorner = Vector3.one * math.huge
	local maxCorner = Vector3.one * -math.huge

	for cornerNumber = 0, BOX_CORNER_COUNT - 1 do
		local corner = part.CFrame:PointToWorldSpace(Vector3.new(
			if bit32.band(cornerNumber, 1) == 0 then -halfSize.X else halfSize.X,
			if bit32.band(cornerNumber, 2) == 0 then -halfSize.Y else halfSize.Y,
			if bit32.band(cornerNumber, 4) == 0 then -halfSize.Z else halfSize.Z
			))
		
		minCorner = minCorner:Min(corner)
		maxCorner = maxCorner:Max(corner)
	end

	local minCell = minCorner / Grid.TileSize
	local maxCell = maxCorner / Grid.TileSize
	return math.floor(minCell.X), math.floor(minCell.Y), math.floor(minCell.Z),
		math.ceil(maxCell.X) - 1, math.ceil(maxCell.Y) - 1, math.ceil(maxCell.Z) - 1
end

local function clipToAxis(minX: number, maxX: number, base: number, slope: number, limit: number): (number, number)
	if math.abs(slope) < SLOPE_EPSILON then
		if math.abs(base) < limit then
			return minX, maxX
		end
		return 1, 0
	end

	local firstBound = (-limit - base) / slope
	local secondBound = (limit - base) / slope
	return math.max(minX, math.floor(math.min(firstBound, secondBound)) + 1),
		math.min(maxX, math.ceil(math.max(firstBound, secondBound)) - 1)
end

local function axisLimit(axis: Vector3, halfExtent: number): number
	local halfTile = Grid.TileSize * 0.5
	return halfExtent
		+ math.abs(axis.X) * halfTile.X
		+ math.abs(axis.Y) * halfTile.Y
		+ math.abs(axis.Z) * halfTile.Z
end

function Grid.GetRowsInPart(part: BasePart): { Row }
	local rows = {}

	local minX, minY, minZ, maxX, maxY, maxZ = Grid.GetCellBounds(part)
	local tileSize = Grid.TileSize
	local halfSize = part.Size * 0.5
	local axes = { part.CFrame.XVector, part.CFrame.YVector, part.CFrame.ZVector }
	local limits = { axisLimit(axes[1], halfSize.X), axisLimit(axes[2], halfSize.Y), axisLimit(axes[3], halfSize.Z) }

	local cellZeroOffset = tileSize * 0.5 - part.Position

	for y = minY, maxY do
		for z = minZ, maxZ do
			local rowOffset = Vector3.new(
				cellZeroOffset.X,
				cellZeroOffset.Y + y * tileSize.Y,
				cellZeroOffset.Z + z * tileSize.Z
			)

			local rowMinX, rowMaxX = minX, maxX
			for axisIndex, axis in axes do
				rowMinX, rowMaxX =
					clipToAxis(
						rowMinX, rowMaxX, axis:Dot(rowOffset),
						axis.X * tileSize.X, limits[axisIndex]
					)
			end
			if rowMinX > rowMaxX then
				continue
			end

			table.insert(rows, { y = y, z = z, minX = rowMinX, maxX = rowMaxX })
		end
	end

	return rows
end

return Grid
