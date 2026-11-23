local Players = game:GetService("Players")

local hitboxTemplate = game:GetService("ReplicatedStorage"):WaitForChild("Hitbox")

local function setupCharacter(character: Model)
	local humanoidRootPart = character:WaitForChild("HumanoidRootPart", 5)
	if not humanoidRootPart then
		return
	end

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant:SetAttribute("SnowIgnore", true)
		end
	end

	character.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") and descendant:GetAttribute("SnowKickHitbox") ~= true then
			descendant:SetAttribute("SnowIgnore", true)
		end
	end)

	local hitbox = hitboxTemplate:Clone()
	hitbox.Name = "SnowHitbox"
	hitbox:SetAttribute("SnowKickHitbox", true)
	hitbox.Anchored = false
	hitbox.CanCollide = false
	hitbox.CanTouch = false
	hitbox.Massless = true
	hitbox.CFrame = humanoidRootPart.CFrame
	hitbox.Parent = character

	local weld = Instance.new("Weld")
	weld.Part0 = humanoidRootPart
	weld.Part1 = hitbox
	weld.C0 = CFrame.new(0, -0.5, 0)
	weld.Parent = hitbox
end

Players.PlayerAdded:Connect(function(player)
	player.CharacterAdded:Connect(setupCharacter)
	if player.Character then
		setupCharacter(player.Character)
	end
end)

for _, player in Players:GetPlayers() do
	player.CharacterAdded:Connect(setupCharacter)
	if player.Character then
		setupCharacter(player.Character)
	end
end
