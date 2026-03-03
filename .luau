-- HiddenDevs sample script
-- This script manages survival gameplay:
-- 1. Spawns balls that chase and damage players
-- 2. Randomly activates a laser minigame
-- 3. Tracks survival time and shows it on GUI
-- 4. Saves best survival time using DataStore
-- 5. Cleans up balls and lasers when a player dies

-- Services
local Players = game:GetService("Players")              -- Player management
local TweenService = game:GetService("TweenService")    -- movement service
local ReplicatedStorage = game:GetService("ReplicatedStorage") -- Shared storage for client-server 
local ServerStorage = game:GetService("ServerStorage")  -- no cheaters storage :)
local DataStoreService = game:GetService("DataStoreService")   -- For Datasave
local CollectionService = game:GetService("CollectionService") -- Adds Tag
local Debris = game:GetService("Debris")                -- Clean up service
local RunService = game:GetService("RunService")        -- Frame-based updates

-- Modules
local Config = require(ReplicatedStorage:WaitForChild("Config")) -- Configurable values
local Events = ReplicatedStorage:WaitForChild("Events")          -- RemoteEvents folder

-- DataStore for best survival times
local survivalStore = DataStoreService:GetDataStore("SurvivalTimes")

-- Random number generator
local rng = Random.new()

-- Tween settings for ball movement
local TWInfo = TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.In)

-- Function: choose a random position inside SpawnBall area
local function chooseRandomPos()
	local SpawnBall = workspace:WaitForChild("SpawnBall")
	local x = SpawnBall.Position.X + rng:NextNumber(-SpawnBall.Size.X/2, SpawnBall.Size.X/2)
	local y = SpawnBall.Position.Y + rng:NextNumber(-SpawnBall.Size.Y/2, SpawnBall.Size.Y/2)
	local z = SpawnBall.Position.Z + rng:NextNumber(-SpawnBall.Size.Z/2, SpawnBall.Size.Z/2)
	return CFrame.new(x,y,z)
end

-- Function: find the nearest player to a given part
local function getNearestPlayer(part)
	local nearest, shortest = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		if hrp then
			local dist = (part.Position - hrp.Position).Magnitude
			if dist < shortest then
				nearest, shortest = player, dist
			end
		end
	end
	return nearest
end

-- Function: throw a ball towards a player
-- Uses AssemblyLinearVelocity (modern API) instead of deprecated LinearVelocity
local function throwBall(player, ball, target)
	local direction = (target.Position - ball.Position).Unit
	local distance = (target.Position - ball.Position).Magnitude
	local speed = distance * Config.BallSpeedMultiplier + player.leaderstats.Time.Value/50
	ball.AssemblyLinearVelocity = direction * speed
end

-- Extra utility: add sound effect when ball spawns
local function playSpawnSound(ball)
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://12222005" -- example sound
	sound.Parent = ball
	sound:Play()
	Debris:AddItem(sound, 5)
end

-- Function: laser minigame logic
-- Every 5 seconds, 25% chance lasers activate and damage players
local function rollForLasers()
	task.spawn(function()
		while true do
			task.wait(Config.BallSpawnInterval)
			local chance = rng:NextInteger(1,100)
			local lasers = workspace:WaitForChild("Lasers"):GetChildren()
			if chance <= Config.LaserChance then
				-- Activate lasers
				for _, laser in ipairs(lasers) do
					if laser:IsA("BasePart") then
						CollectionService:AddTag(laser,"ActiveLaser")
						laser.Transparency = 0.2
						laser.CanCollide = true
						laser.CanTouch = true
						laser.Touched:Connect(function(hit)
							local hum = hit.Parent:FindFirstChild("Humanoid")
							if hum then hum:TakeDamage(Config.LaserDamage) end
						end)
					end
				end
			else
				-- Deactivate lasers
				for _, laser in ipairs(lasers) do
					if laser:IsA("BasePart") then
						CollectionService:RemoveTag(laser,"ActiveLaser")
						laser.Transparency = 1
						laser.CanCollide = false
						laser.CanTouch = false
					end
				end
			end
		end
	end)
end

-- Player setup
Players.PlayerAdded:Connect(function(player)
	-- Leaderstats setup (used for GUI and tracking)
	local leaderstats = Instance.new("Folder", player)
	leaderstats.Name = "leaderstats"
	local Time = Instance.new("IntValue", leaderstats)
	Time.Name = "Time"

	-- Survival timer loop
	task.spawn(function()
		while player.Parent do
			task.wait(Config.TimeUpdateInterval)
			Time.Value += 1
			Events.UpdateTime:FireClient(player, Time.Value) -- Update GUI
		end
	end)

	-- Ball spawning loop
	task.spawn(function()
		while player.Parent do
			task.wait(Config.BallSpawnInterval)
			local Ball = ServerStorage:WaitForChild("Ball"):Clone()
			Ball.Parent = workspace:WaitForChild("Balls")
			Ball.CFrame = chooseRandomPos()

			-- Highlight the newest ball
			for _, v in ipairs(workspace.Balls:GetDescendants()) do
				if v:IsA("Highlight") then v:Destroy() end
			end
			Instance.new("Highlight", Ball)

			-- Play sound effect
			playSpawnSound(Ball)

			-- Tween ball to new position
			local tween = TweenService:Create(Ball, TWInfo, {CFrame = chooseRandomPos()})
			tween:Play()
			tween.Completed:Connect(function()
				-- After tween, spawn ThrowPart and launch it
				local ThrowPart = ServerStorage:WaitForChild("ThrowPart"):Clone()
				ThrowPart.Parent = Ball
				ThrowPart.CFrame = Ball.CFrame
				throwBall(player, ThrowPart, player.Character.HumanoidRootPart)

				-- Damage player if hit
				ThrowPart.Touched:Connect(function(hit)
					local hum = hit.Parent:FindFirstChild("Humanoid")
					if hum then hum:TakeDamage(Config.BallDamage) end
				end)

				Debris:AddItem(ThrowPart, 3) -- Auto-clean ThrowPart after 3 seconds
			end)
		end
	end)
	
	player.Chatted:Connect(function(msg)
		if msg == "!clearballs" then
			for _, v in ipairs(workspace:WaitForChild("Balls"):GetChildren()) do
				v:Destroy()
			end
			Events.AdminCommand:FireClient(player,"Balls cleared!")
		elseif msg == "!lasers" then
			rollForLasers()
			Events.AdminCommand:FireClient(player,"Laser roll triggered!")
		elseif msg == "!besttime" then
			local best = survivalStore:GetAsync(player.UserId) or 0
			Events.AdminCommand:FireClient(player,"Your best survival time: "..best.." seconds")
		end
	end)

	-- On player death: reset game state
	player.CharacterAdded:Connect(function(char)
		char:WaitForChild("Humanoid").Died:Connect(function()
			-- Remove ForceField if present
			local ff = char:FindFirstChildOfClass("ForceField")
			if ff then ff:Destroy() end

			-- Save best survival time
			local best = survivalStore:GetAsync(player.UserId) or 0
			if Time.Value > best then
				survivalStore:SetAsync(player.UserId, Time.Value)
			end
			Time.Value = 0

			-- Clear all balls
			for _, ball in ipairs(workspace:WaitForChild("Balls"):GetChildren()) do
				ball:Destroy()
			end

			-- Reset lasers
			for _, laser in ipairs(workspace:WaitForChild("Lasers"):GetChildren()) do
				if laser:IsA("BasePart") then
					laser.Transparency = 1
					laser.CanCollide = false
				end
			end
		end)
	end)
end)

-- Start laser minigame loop
rollForLasers()

-- frame-based debug print (shows ball count every second)
RunService.Heartbeat:Connect(function()
	if tick() % 1 < 0.05 then
		print("Balls in workspace: ", #workspace:WaitForChild("Balls"):GetChildren())
	end
end)

-- Power Up System

-- This system spawns green spheres in the map.
-- When a player touches them, they gain temporary speed boost and a shield.
-- Admins can also spawn power-ups manually with the chat command "!powerup"

local SpeedBoost = 8
local PowerUpDuration = 10
local PowerUpInterval = 20



local function spawnPowerUp()  -- Function: spawn a part(PowerUp) in random position
	local PowerUp = Instance.new("Part")
	PowerUp.Name = "PowerUp"
	PowerUp.Size = Vector3.new(2,2,2)
	PowerUp.Shape = Enum.PartType.Ball
	PowerUp.Color = Color3.fromRGB(0,255,0)
	PowerUp.Anchored = false
	PowerUp.CanCollide = true
	PowerUp.CFrame = chooseRandomPos()
	PowerUp.Parent = workspace:FindFirstChild("PowerUps") or Instance.new("Folder",workspace)
	PowerUp.Parent.Name = "PowerUps"

	PowerUp.Touched:Connect(function(hit)
		local hum = hit.Parent:FindFirstChild("Humanoid")
		if hum then
			hum.WalkSpeed = hum.WalkSpeed + SpeedBoost
			local shield = Instance.new("ForceField", hit.Parent)
			Debris:AddItem(shield, SpeedBoost)
			task.delay(PowerUpDuration, function()
				if hum then hum.WalkSpeed = hum.WalkSpeed - SpeedBoost end
			end)
			PowerUp:Destroy() 
		end
	end)

	Debris:AddItem(PowerUp, PowerUpDuration + 2)
end

-- Spawn Power up every 20(PowerUPINTERVRVAL) seconds
task.spawn(function()
	while true do
		task.wait(PowerUpInterval)
		spawnPowerUp()
	end
end)

-- AdminCommands for test
Players.PlayerAdded:Connect(function(player)
	player.Chatted:Connect(function(msg)
		if msg == "!powerup" then
			spawnPowerUp()
			Events.AdminCommand:FireClient(player,"PowerUp spawned!")
		end
	end)
end)
