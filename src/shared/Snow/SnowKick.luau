local SnowCells = require(script.Parent.SnowCells)

local Flag = SnowCells.Flag

local SnowKick = {}
SnowKick.__index = SnowKick

--how far kicked snow goes in cells
--a cell is 1 x 0.25 x 1 studs
local KICK_UP_CELLS = 4
local KICK_AWAY_CELLS = 4

--cells moved per tick
local FLIGHT_STEPS_PER_TICK = 1

--below this horizontal distance from the player, a cell gets a random kick dir
local SAME_SPOT_DISTANCE = 0.01

local KICK_TARGETS = {}
do
	local upHeights = {}
	for upCells = KICK_UP_CELLS, 1, -2 do
		table.insert(upHeights, upCells)
	end
	table.insert(upHeights, 0)

	for _, upCells in upHeights do
		for awayCells = KICK_AWAY_CELLS, 1, -1 do
			table.insert(KICK_TARGETS, { upCells = upCells, awayCells = awayCells })
		end
	end
end

function SnowKick.new(cells, snowSim)
	local self = setmetatable({}, SnowKick)
	
	self._cells = cells
	self._snowSim = snowSim
	self._random = Random.new()
	self._flights = {}
	
	return self
end

function SnowKick:Kick(part: BasePart, playerPosition: Vector3)
	local cells = self._cells
	
	for _, cellIndex in cells:GetCellsInPart(part) do
		if cells:HasFlag(cellIndex, Flag.Snow) and not cells:HasFlag(cellIndex, Flag.Flying) then
			self:_kickCell(cellIndex, playerPosition)
		end
	end
end

function SnowKick:Update()
	local flights = self._flights
	self._flights = {}

	for cellIndex, flight in flights do
		if not self._cells:HasFlag(cellIndex, Flag.Flying) then
			continue
		end

		local currentIndex, hasLanded = self:_fly(cellIndex, flight)
		if hasLanded then
			self._snowSim:StopFlying(currentIndex)
		else
			self._flights[currentIndex] = flight
		end
	end
end

function SnowKick:_kickCell(cellIndex: number, playerPosition: Vector3)
	local cells = self._cells
	local x, y, z = cells:GetPosition(cellIndex)
	local awayX, awayZ = self:_getAwayDirection(cellIndex, playerPosition)

	for _, target in KICK_TARGETS do
		local targetX = x + math.round(awayX * target.awayCells)
		local targetY = y + target.upCells
		local targetZ = z + math.round(awayZ * target.awayCells)
		
		local targetIndex = cells:GetIndex(targetX, targetY, targetZ)
		
		if targetIndex and cells:IsEmpty(targetIndex) then
			local deltaX, deltaY, deltaZ = targetX - x, targetY - y, targetZ - z
			
			self._flights[cellIndex] = {
				startX = x,
				startY = y,
				startZ = z,
				deltaX = deltaX,
				deltaY = deltaY,
				deltaZ = deltaZ,
				stepCount = math.max(math.abs(deltaX), math.abs(deltaY), math.abs(deltaZ)),
				stepsTaken = 0,
			}
			
			self._snowSim:StartFlying(cellIndex)
			
			return
		end
	end

	self._snowSim:PushSnowOut(cellIndex)
end

function SnowKick:_getAwayDirection(cellIndex: number, playerPosition: Vector3): (number, number)
	local offset = self._snowSim:GetCellCenter(cellIndex) - playerPosition
	
	local horizontalOffset = Vector3.new(offset.X, 0, offset.Z)
	
	if horizontalOffset.Magnitude < SAME_SPOT_DISTANCE then
		local angle = self._random:NextNumber() * math.pi * 2
		
		return math.cos(angle), math.sin(angle)
	end

	local direction = horizontalOffset.Unit
	return direction.X, direction.Z
end

function SnowKick:_fly(cellIndex: number, flight): (number, boolean)
	local currentIndex = cellIndex
	
	for _ = 1, FLIGHT_STEPS_PER_TICK do
		flight.stepsTaken += 1
		local progress = flight.stepsTaken / flight.stepCount
		
		local nextIndex = self._cells:GetIndex(
			flight.startX + math.round(flight.deltaX * progress),
			flight.startY + math.round(flight.deltaY * progress),
			flight.startZ + math.round(flight.deltaZ * progress)
		)
		
		if not nextIndex or not self:_canFlyInto(nextIndex) then
			return currentIndex, true
		end

		self._snowSim:MoveSnow(currentIndex, nextIndex)
		
		currentIndex = nextIndex
		
		if flight.stepsTaken == flight.stepCount then
			return currentIndex, true
		end
	end
	
	return currentIndex, false
end

function SnowKick:_canFlyInto(cellIndex: number): boolean
	local cellFlags = self._cells:GetFlags(cellIndex)
	
	return cellFlags == 0 or cellFlags == Flag.MovingObstacle
end

return SnowKick
