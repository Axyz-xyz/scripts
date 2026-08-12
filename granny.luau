getgenv().AZURE = getgenv().AZURE or {}
local AZURE = getgenv().AZURE
AZURE.seq = (AZURE.seq or 0) + 1
local mySeq = AZURE.seq

-- kill a fully-built previous instance right away
if type(AZURE.disable) == "function" then
	pcall(AZURE.disable)
end
AZURE.run = true
AZURE.disableList = AZURE.disableList or {}
local alive = true

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/mstudio45/LinoriaLib/main/Library.lua"))()

AZURE.Version = "4.4.0"
AZURE.notifMiss = {}
AZURE.notifsOn = false
AZURE.started = false
AZURE.escaped = false
AZURE.stats = { items = 0, monsters = 0, players = 0, chamItems = 0, chamMonsters = 0, chamPlayers = 0 }
AZURE.lastError = nil

local function notify(text)
	if AZURE.notifsOn == false then return end
	pcall(function() Library:Notify({ Title = "Azure", Description = text, Time = 3 }) end)
end

local function E(tag, err)
	local msg = "[" .. tag .. "] " .. tostring(err)
	warn("[AZURE] " .. msg)
	local t = os.clock()
	if (AZURE.notifMiss[tag] or 0) + 8 < t then
		AZURE.notifMiss[tag] = t
		pcall(function() notify("Issue: " .. tostring(err)) end)
	end
	AZURE.lastError = msg
end

function AZURE.safeLoop(tag, fn)
	task.spawn(function()
		while alive do
			local ok, err = pcall(fn)
			if not ok then E(tag, err) task.wait(4) end
			task.wait()
		end
	end)
end

-- services
local Players = game:GetService("Players")
local WS = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TeleportService = game:GetService("TeleportService")
local HttpService = game:GetService("HttpService")
local UIS = game:GetService("UserInputService")

local Plr = game.Players.LocalPlayer
local Camera = WS.CurrentCamera

-- window
local Window = Library:CreateWindow({ Title = "Project Azure", Center = true, Resizable = true, AutoShow = true })
AZURE.Options = Library.Options
AZURE.Toggles = Library.Toggles
AZURE.Library = Library
local MenuTabs = {
	Esp = Window:AddTab("ESP"),
	Protection = Window:AddTab("Godmode"),
	Movement = Window:AddTab("Movement"),
	Teleport = Window:AddTab("Teleport/Bring"),
	Info = Window:AddTab("Info/Settings"),
}
local LeftTabs, RightTabs = {}, {}
for name, tab in pairs(MenuTabs) do
	LeftTabs[name] = tab:AddLeftGroupbox(name)
	RightTabs[name] = tab:AddRightGroupbox(name .. " extras")
end

-- theme: azure blue accent to match the name
pcall(function()
	local Lin = getgenv().Linoria or Library
	Lin.AccentColor = Color3.fromRGB(0, 140, 255)
	Lin.AccentColorDark = Color3.fromRGB(0, 95, 190)
	Lin:UpdateColorsUsingRegistry()
end)
Library:SetWatermark("Project Azure | Granny Multiplayer")
Library:SetWatermarkVisibility(false)

-- sync flags
local itemSyncDirty = true
local scanItemsWanted = true
local function dirty()
	itemSyncDirty = true
end
WS.DescendantAdded:Connect(function() itemSyncDirty = true end)
WS.DescendantRemoving:Connect(dirty)

local backpack = nil
task.spawn(function()
	backpack = Plr:WaitForChild("Backpack")
	backpack.ChildAdded:Connect(dirty)
	backpack.ChildRemoved:Connect(dirty)
end)
local function inBackpack(name)
	local bp = backpack or Plr:FindFirstChild("Backpack")
	if not bp then return nil end
	for _, v in ipairs(bp:GetChildren()) do
		if v.Name == name then return v end
	end
	return nil
end

-- escape banner (read-only, one line on the Info tab)
local escapeMsg = nil
task.spawn(function()
	while alive and not escapeMsg do
		local found = nil
		pcall(function()
			local pg = Plr:FindFirstChild("PlayerGui")
			if pg then
				for _, v in ipairs(pg:GetDescendants()) do
					if v.Name == "EscapeTopMessage" then found = v break end
				end
			end
		end)
		if found then escapeMsg = found return end
		task.wait(2)
	end
end)
local lastEscText = ""
local function readEsc()
	local t = ""
	pcall(function() if escapeMsg then t = escapeMsg.Text or "" end end)
	if t ~= lastEscText then
		lastEscText = t
		pcall(function() AZURE.EscLabel:SetText("Escape: " .. (t == "" and "idle" or t)) end)
		if t ~= "" and t:lower():find("escaped") then
			AZURE.escaped = true
			notify("Escaped — reset")
		end
	end
	return t
end

-- clean names
local ITEM_LABELS = {
	Screwdriver = "Screwdriver", Hammer = "Hammer", Key = "Key",
	BoltCutters = "Bolt Cutters", Fuse = "Fuse", ClosetClue = "Closet Clue",
	Globe = "Globe", PorcelainDoll = "Porcelain Doll", SlingshotMotor = "Slingshot Motor",
	Battery = "Battery", CarKey = "Car Key", PadlockKey = "Padlock Key",
	Padlock = "Padlock", WeirdBattery = "Weird Battery", TeddyBear = "Teddy Bear",
	AcidFlask = "Acid Flask", StandingCane = "Standing Cane", Eye = "Eye",
	Gear = "Gear", Nail = "Nail", SafeKey = "Safekey",
}
local function itemFriendly(name)
	return ITEM_LABELS[name] or name:gsub("(%l)(%u)", "%1 %2"):gsub("^%l", string.upper)
end
local function monsterFriendly(name)
	local map = { Granny = "Granny", Slendrina = "Slendrina", Grandma = "Grandma", Grandma2 = "Grandma (dark)", ["Grandma's Revenge"] = "Grandma's Revenge" }
	return map[name] or name:gsub("(%l)(%u)", "%1 %2")
end
-- ── map scenery we never show (doors, drawers, vents, props…) ────────
local function containsMatch(name, words)
	local n = name:lower()
	for _, x in ipairs(words) do
		if n:find(x, 1, true) then return true end
	end
	return false
end
local SCENERY_WORDS = {
	"door", "drawer", "vent", "window", "wall", "floor", "ceiling", "tpp", "exit",
	"badge", "click", "cellar", "locker", "trigger", "prop", "sign",
	"shelf", "cabinet", "fridge", "closet", "plant", "lamp", "switch", "light",
	"stair", "fence", "hedge", "tree", "rock", "vase", "curtain", "pillow",
	"blanket", "mat", "rug", "shower", "bathtub", "handle", "elevator", "outside",
	"part", "unlock",
}
local MONSTER_SKIP_WORDS = { "prop", "door", "gry", "stb", "char", "tpp" }
local MONSTER_FIXED = {
	Granny = true, Slendrina = true, Grandma = true, Grandma2 = true,
	["Grandma's Revenge"] = true, Spider = true, Rat = true, Teddy = true,
}
local function isSceneryPart(name)
	return containsMatch(name, SCENERY_WORDS)
end
local function isSceneryModel(name)
	return containsMatch(name, MONSTER_SKIP_WORDS)
end
local function isFixedMonster(name)
	local n = name:lower()
	for k in pairs(MONSTER_FIXED) do
		if n:find(k:lower(), 1, true) then return true end
	end
	return false
end
local function hasUnanchored(m)
	for _, v in ipairs(m:GetChildren()) do
		if v:IsA("BasePart") and not v.Anchored then return true end
	end
	return false
end

-- ── name tags (transparent — just clean text) ────────────────────────
local tagCache = setmetatable({}, { __mode = "k" }) -- inst -> BillboardGui
local function getTag(inst)
	local tag = tagCache[inst]
	if not tag or not tag.Parent then
		tag = Instance.new("BillboardGui")
		tag.Name = "AZURE-Tag"
		tag.Size = UDim2.fromOffset(180, 24)
		tag.AlwaysOnTop = true
		tag.ClipsDescendants = false
		tag.LightInfluence = 0
		tag.StudsOffsetWorldSpace = Vector3.new(0, 3, 0)
		tag.Parent = inst

		local lbl = Instance.new("TextLabel")
		lbl.Name = "Label"
		lbl.Size = UDim2.new(1, 0, 1, 0)
		lbl.BackgroundTransparency = 1
		lbl.Font = Enum.Font.GothamBold
		lbl.TextSize = 13
		lbl.TextColor3 = Color3.new(1, 1, 1)
		lbl.TextStrokeTransparency = 0.05
		lbl.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		lbl.TextXAlignment = Enum.TextXAlignment.Center
		lbl.Parent = tag

		tagCache[inst] = tag
	end
	return tag
end
local function tagWidth(text)
	local w = 10 + #text * 7.5 -- ~7.5px per bold 13px char
	return math.clamp(w, 34, 240)
end
local function setTag(inst, text, color, on, offsetY)
	if text == nil then
		local existing = tagCache[inst]
		if existing then
			pcall(function() existing.Enabled = false end)
		end
		return
	end
	local tag = getTag(inst)
	local lbl = tag:FindFirstChild("Label")
	if lbl then
		local off = offsetY or 3
		if tag.StudsOffsetWorldSpace.Y ~= off then
			tag.StudsOffsetWorldSpace = Vector3.new(0, off, 0)
		end
		tag.Size = UDim2.fromOffset(tagWidth(text), 24)
		if lbl.Text ~= text then lbl.Text = text end
		lbl.TextColor3 = color or Color3.new(1, 1, 1)
	end
	tag.Enabled = on
end
local function hideAllTags()
	for _, tag in pairs(tagCache) do
		pcall(function() tag.Enabled = false end)
	end
end

-- ── drawing cache (boxes/bars/tracers — text uses tags above) ────────
local espCache = setmetatable({}, { __mode = "k" })
local function getDraws(inst)
	local d = espCache[inst]
	if not d then
		d = { Box = Drawing.new("Square"), Bar = Drawing.new("Square"), Line = Drawing.new("Line") }
		d.Box.Visible = false
		d.Bar.Visible = false
		d.Line.Visible = false
		d.Line.Thickness = 1
		d.Line.Transparency = 1
		espCache[inst] = d
	end
	return d
end
local function hideDraws(d)
	pcall(function()
		d.Box.Visible = false
		d.Bar.Visible = false
		d.Line.Visible = false
	end)
end
local function drawBox(d, pos, size, color, on)
	if not on then d.Box.Visible = false return end
	local sp = Camera:WorldToScreenPoint(pos)
	if not sp then d.Box.Visible = false return end
	d.Box.Position = Vector2.new(sp.X - size / 2, sp.Y - size / 2)
	d.Box.Size = Vector2.new(size, size)
	d.Box.Thickness = 1
	d.Box.Color = color
	d.Box.Visible = true
end
local function drawBar(d, pos, frac, color, on)
	if not on then d.Bar.Visible = false return end
	local sp = Camera:WorldToScreenPoint(pos)
	if not sp then d.Bar.Visible = false return end
	d.Bar.Position = Vector2.new(sp.X - 14, sp.Y + 16)
	d.Bar.Size = Vector2.new(math.clamp(28 * frac, 1, 28), 3)
	d.Bar.Thickness = 1
	d.Bar.Color = color
	d.Bar.Visible = true
end
local function drawTracer(d, pos, color, on)
	if not on then d.Line.Visible = false return end
	local sp = Camera:WorldToScreenPoint(pos)
	if not sp then d.Line.Visible = false return end
	local mp = UIS:GetMouseLocation()
	d.Line.From = Vector2.new(mp.X, mp.Y)
	d.Line.To = Vector2.new(sp.X, sp.Y)
	d.Line.Color = color
	d.Line.Visible = true
end

-- ── chams (separate per type) ─────────────────────────────────────────
local chamCache = {} -- inst -> { H, Type } (strong keys: the sweep can always find and kill leftovers)
local function applyCham(inst, on, color, fillT, outT, category)
	if not on then
		local e = chamCache[inst]
		if e and e.Type == category then
			pcall(function() e.H:Destroy() end)
			chamCache[inst] = nil
		end
		return
	end
	local e = chamCache[inst]
	if not e or e.Type ~= category then
		if e then pcall(function() e.H:Destroy() end) end
		local h = Instance.new("Highlight")
		h.Name = "AzureCham"
		h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		e = { H = h, Type = category }
		chamCache[inst] = e
	end
	pcall(function()
		e.H.FillColor = color
		e.H.OutlineColor = color
		e.H.FillTransparency = fillT
		e.H.OutlineTransparency = outT
		if e.H.Parent ~= inst then e.H.Parent = inst end
	end)
end
local function clearChamsCategory(category)
	for inst, e in pairs(chamCache) do
		if e.Type == category then
			pcall(function() e.H:Destroy() end)
			chamCache[inst] = nil
		end
	end
end
local function countChams()
	local n = {}
	for _, e in pairs(chamCache) do n[e.Type] = (n[e.Type] or 0) + 1 end
	return n
end

-- sweep: despawned targets lose their drawings and glow, no leftovers
local function sweepCaches()
	local removed = 0
	for inst, d in pairs(espCache) do
		if not inst.Parent then
			hideDraws(d)
			pcall(function() d.Box:Remove() d.Bar:Remove() d.Line:Remove() end)
			espCache[inst] = nil
			removed = removed + 1
		end
	end
	for inst, e in pairs(chamCache) do
		if not inst.Parent or not inst:IsDescendantOf(WS) then
			pcall(function() e.H:Destroy() end)
			chamCache[inst] = nil
		end
	end
	for inst, tag in pairs(tagCache) do
		if not inst.Parent then
			pcall(function() tag:Destroy() end)
			tagCache[inst] = nil
		end
	end
	return removed
end
local function hideAllEsp()
	for _, d in pairs(espCache) do hideDraws(d) end
	hideAllTags()
end

-- ── world helpers ─────────────────────────────────────────────────────
local function ground(pos)
	local hit, hitPos = WS:FindPartOnRay(Ray.new(pos + Vector3.new(0, 30, 0), Vector3.new(0, -60, 0)), Plr.Character)
	return hit and hitPos.Y or pos.Y
end
local function hrpOf(m)
	for _, v in ipairs(m:GetChildren()) do
		if v.Name == "HumanoidRootPart" then return v end
	end
	return nil
end
local function hpHumanoid(m)
	for _, v in ipairs(m:GetChildren()) do
		if v:IsA("Humanoid") then return v end
	end
	return nil
end

-- ── scans (refs cached; positions read directly each frame) ──────────
local monsterList = {}
local function scanMonsters()
	local list = {}
	local myChar = Plr.Character
	for _, v in ipairs(WS:GetDescendants()) do
		if v:IsA("Model") and Players:GetPlayerFromCharacter(v) == nil
			and v ~= myChar and (not myChar or not myChar:IsAncestorOf(v))
			and not isSceneryModel(v.Name) and hasUnanchored(v) then
			local h = hpHumanoid(v)
			local r = hrpOf(v)
			if h and r and h.MaxHealth > 50 and h.Health > 0 then
				local prev = monsterList[v]
				list[v] = {
					Root = r, Humanoid = h, Name = v.Name,
					LastPos = r.Position,
					Moved = (prev and prev.Moved) or false,
					Fixed = isFixedMonster(v.Name),
				}
			end
		end
	end
	monsterList = list
	local n = 0
	for _ in pairs(list) do n = n + 1 end
	AZURE.stats.monsters = n
end

local itemTargets = {} -- part -> { Name, AvailRef, InBackpack }
local function scanItems()
	local list = {}
	for _, v in ipairs(WS:GetDescendants()) do
		if v:IsA("BasePart") and v:FindFirstChild("InteractRemote") then
			local toolName = v:FindFirstChild("Toolname")
			local base = (toolName and toolName.Value ~= "" and toolName.Value) or v.Name
			if not isSceneryPart(base) and not isSceneryPart(v.Name) then
				local remote = v:FindFirstChild("InteractRemote")
				local avail = remote:FindFirstChild("InteractAvailable")
				list[v] = {
					Name = base,
					AvailRef = avail,
					InBackpack = inBackpack(base) ~= nil,
				}
			end
		end
	end
	itemTargets = list
	local n = 0
	for _ in pairs(list) do n = n + 1 end
	AZURE.stats.items = n
end

local playerList = {}
local function scanPlayers()
	local map = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= Plr and p.Character and p.Character:FindFirstChild("HumanoidRootPart") then
			local h = p.Character:FindFirstChildOfClass("Humanoid")
			if h and h.Health > 0 then map[p.Character] = { Name = p.Name } end
		end
	end
	playerList = map
	local n = 0
	for _ in pairs(map) do n = n + 1 end
	AZURE.stats.players = n
end

-- ── godmode: delete monster hitboxes (no walls, no touch, no kill) ────
local godCache = {} -- monster -> { part -> { cc, ct } }
local function applyGodmode(on)
	if on then
		for m, d in pairs(monsterList) do
			local rec = godCache[m]
			if not rec then rec = {} godCache[m] = rec end
			for _, p in ipairs(m:GetDescendants()) do
				if p:IsA("BasePart") and not rec[p] then
					rec[p] = { p.CanCollide, p.CanTouch }
				end
			end
		end
	else
		for m, rec in pairs(godCache) do
			for p, pair in pairs(rec) do
				if p.Parent then
					p.CanCollide = pair[1]
					p.CanTouch = pair[2]
				end
			end
		end
		godCache = {}
	end
end

-- ── dynamic map anchors (chapter-proof) ──────────────────────────────
local function findPartPos(name)
	for _, v in ipairs(WS:GetDescendants()) do
		if v.Name == name and v:IsA("BasePart") then return v.Position end
	end
	return nil
end
local function findModelPos(name)
	for _, v in ipairs(WS:GetDescendants()) do
		if v.Name == name and v:IsA("Model") then
			local ok, p = pcall(function() return v:GetPivot().Position end)
			if ok then return p end
		end
	end
	return nil
end
-- ── colors ───────────────────────────────────────────────────────────
local BOX_COLORS = {
	Yellow = Color3.fromRGB(255, 216, 0), Orange = Color3.fromRGB(255, 140, 0),
	Red = Color3.fromRGB(255, 60, 60), White = Color3.new(1, 1, 1),
	Green = Color3.fromRGB(80, 255, 120), Cyan = Color3.fromRGB(0, 220, 255),
	Pink = Color3.fromRGB(255, 120, 220), Magenta = Color3.fromRGB(255, 0, 200),
	Blue = Color3.fromRGB(70, 130, 255),
}
local COLOR_NAMES = { "Yellow", "Orange", "Red", "White", "Green", "Cyan", "Pink", "Magenta", "Blue" }
local function pick(v) return BOX_COLORS[v] or Color3.new(1, 1, 1) end

-- ── ESP tab ───────────────────────────────────────────────────────────
local EspTab = LeftTabs.Esp
local TEsp = EspTab:AddToggle("azure-esp", { Text = "ESP", Default = false, Callback = function()
	itemSyncDirty = true
	if not TEsp.Value then hideAllEsp() end
end })
local TChams = EspTab:AddToggle("azure-chams", { Text = "Glow", Default = false, Callback = function()
	if not TChams.Value then
		clearChamsCategory("item")
		clearChamsCategory("monster")
		clearChamsCategory("player")
	end
end })
EspTab:AddDivider()
local TEspName = EspTab:AddToggle("azure-esp-name", { Text = "Names", Default = false })
local TEspDist = EspTab:AddToggle("azure-esp-dist", { Text = "Distance", Default = false })
local TEspBox = EspTab:AddToggle("azure-esp-box", { Text = "Boxes", Default = false })
local TEspHp = EspTab:AddToggle("azure-esp-hp", { Text = "Health", Default = false })
local TEspTracers = EspTab:AddToggle("azure-esp-tracers", { Text = "Tracers", Default = false })
EspTab:AddDivider()
local ColItems = EspTab:AddDropdown("azure-esp-itemcol", { Text = "Item color", Values = COLOR_NAMES, Default = 1 })
local ColMon = EspTab:AddDropdown("azure-esp-moncol", { Text = "Enemy color", Values = COLOR_NAMES, Default = 3 })
local ColPly = EspTab:AddDropdown("azure-esp-plycol", { Text = "Player color", Values = COLOR_NAMES, Default = 6 })
EspTab:AddDivider()
local DFocus = EspTab:AddDropdown("azure-esp-focus", { Text = "Only item", Values = { "(all)" }, Default = 1 })
EspTab:AddLabel("Labels:")
local DItemLabels = EspTab:AddDropdown("azure-esp-itemlabels", { Text = "Count", Values = { "All", "Nearest 10", "Nearest 25", "Nearest 50", "Off" }, Default = 1 })
EspTab:AddLabel("Label range:")
local DLabelDist = EspTab:AddDropdown("azure-esp-labeldist", { Text = "Label range", Values = { "Whole map", "Medium (150)", "Close (75)", "Very close (40)" }, Default = 1 })
EspTab:AddLabel("Glow range:")
local DGlowDist = EspTab:AddDropdown("azure-esp-glowdist", { Text = "Glow range", Values = { "Whole map", "Medium (300)", "Close (150)", "Near (75)" }, Default = 1 })
EspTab:AddDivider()
local ITEM_LABEL_MODES = { ["All"] = 0, ["Nearest 10"] = 10, ["Nearest 25"] = 25, ["Nearest 50"] = 50, ["Off"] = -1 }
local LABEL_DIST = { ["Whole map"] = 0, ["Medium (150)"] = 150, ["Close (75)"] = 75, ["Very close (40)"] = 40 }
local GLOW_DIST = { ["Whole map"] = 0, ["Medium (300)"] = 300, ["Close (150)"] = 150, ["Near (75)"] = 75 }
local SEspRefresh = EspTab:AddSlider("azure-esp-refresh", { Text = "Scan", Min = 0.1, Max = 2, Rounding = 2, Default = 0.3, Suffix = " s" })
local LEspCount = EspTab:AddLabel("No scan")
AZURE.EspCountLabel = LEspCount
local BtnRescan = EspTab:AddButton("Rescan", function()
	dirty()
	notify("Scanning...")
end)

-- ── Protection tab ─────────────────────────────────────────────────────
local ProTab = LeftTabs.Protection
ProTab:AddLabel("Godmode removes hitboxes")
ProTab:AddLabel("They can't hurt you.")
local TGod = ProTab:AddToggle("azure-god", { Text = "Godmode", Default = false, Callback = function(v)
	applyGodmode(v)
	notify(v and "Godmode on" or "Godmode off")
end })
local TTeleportSafe = ProTab:AddToggle("azure-safezone", { Text = "Auto dash", Default = false })
local SSSafeDist = ProTab:AddSlider("azure-safe-dist", { Text = "Range", Min = 10, Max = 60, Rounding = 0, Default = 32, Suffix = " studs" })

-- ── Movement tab ───────────────────────────────────────────────────────
local MovTab = LeftTabs.Movement
local TWalk = MovTab:AddToggle("azure-walk", { Text = "Walk", Default = false, Callback = function(v)
	if not v then
		pcall(function()
			local h = Plr.Character and Plr.Character:FindFirstChildOfClass("Humanoid")
			if h then h.WalkSpeed = 16 end
		end)
	end
end })
local SWalk = MovTab:AddSlider("azure-walk-spd", { Text = "Speed", Min = 10, Max = 200, Rounding = 0, Default = 32 })
local TJump = MovTab:AddToggle("azure-jump", { Text = "Jump", Default = false, Callback = function(v)
	if not v then
		pcall(function()
			local h = Plr.Character and Plr.Character:FindFirstChildOfClass("Humanoid")
			if h then h.JumpPower = 50 end
		end)
	end
end })
local SJump = MovTab:AddSlider("azure-jump-spd", { Text = "Jump", Min = 20, Max = 300, Rounding = 0, Default = 80 })
local TFly = MovTab:AddToggle("azure-fly", { Text = "Fly", Default = false, Callback = function(v)
	if not v then
		pcall(function()
			local c = Plr.Character
			if c then
				for _, part in ipairs(c:GetDescendants()) do
					if part:IsA("BasePart") then part.CanCollide = true end
				end
			end
		end)
	end
end })
local SFly = MovTab:AddSlider("azure-fly-spd", { Text = "Speed", Min = 10, Max = 200, Rounding = 0, Default = 50 })
local TNoFall = MovTab:AddToggle("azure-nofall", { Text = "No fall", Default = false })

-- ── smooth item bring (arc tween, stops if the item is picked up) ────
local bringThreads = {}
local function smoothBring(inst, target)
	if not inst or bringThreads[inst] then return end
	local ok, err = pcall(function() inst.Anchored = true end)
	if not ok then return end
	local fromPos = inst.Position
	local dur = 0.5
	local t0 = os.clock()
	local parentAtStart = inst.Parent
	bringThreads[inst] = task.spawn(function()
		repeat
			local t = math.min((os.clock() - t0) / dur, 1)
			local e = t * t * (3 - 2 * t) -- smoothstep
			local pos = fromPos:Lerp(target, e) + Vector3.new(0, math.sin(t * math.pi) * 3, 0)
			pcall(function() inst.CFrame = CFrame.new(pos) end)
			task.wait()
		until t >= 1 or not alive or inst.Parent ~= parentAtStart
		pcall(function() inst.Anchored = false end)
		bringThreads[inst] = nil
	end)
end

-- ── Teleport tab ───────────────────────────────────────────────────────
local TpTab = LeftTabs.Teleport
TpTab:AddLabel("Spots found by name")
TpTab:AddLabel("Works in all maps")
local FALLBACK_DEST = {
	["Spawn point"] = Vector3.new(360, 4, 220),
	["Front porch"] = Vector3.new(298, 1, 206),
	["Cellar hole"] = Vector3.new(-322, -12, 6),
	["Safe room"] = Vector3.new(74, 2, -48),
	["Ending door 1"] = Vector3.new(72, -22, -41),
	["Ending door 2"] = Vector3.new(250, -3, 236),
	["Ending door 3"] = Vector3.new(-302, -21, -256),
	["Badge door"] = Vector3.new(-100, 21, 230),
	["Car spot"] = Vector3.new(384, 14, 35),
}
local NAME_RESOLVE = {
	["Front porch"] = "Exit",
	["Cellar hole"] = "TPP",
	["Ending door 1"] = "Ending Door 1",
	["Ending door 2"] = "Ending Door 2",
	["Ending door 3"] = "Ending Door 3",
	["Badge door"] = "BadgeDoor",
	["Car spot"] = "CarDoor",
}
local function resolveDest(key, snap)
	local p = NAME_RESOLVE[key] and (findPartPos(NAME_RESOLVE[key]) or findModelPos(NAME_RESOLVE[key]))
	if not p then p = FALLBACK_DEST[key] end
	if not p then return nil end
	if snap then p = Vector3.new(p.X, ground(p) + 3, p.Z) end
	return p
end
local destNames = {}
for k in pairs(FALLBACK_DEST) do table.insert(destNames, k) end
table.sort(destNames)
local DDest = TpTab:AddDropdown("azure-tp-dest", { Text = "Choose spot", Values = destNames, Default = 1 })
local DItemTp = TpTab:AddDropdown("azure-tp-item", { Text = "Choose item", Values = { "(nothing)" }, AllowNull = true })
local BtnTp = TpTab:AddButton("Teleport", function()
	local key = DDest.Value
	local p = key and resolveDest(key, true)
	if not p then notify("Spot not found.") return end
	local hrp = Plr.Character and Plr.Character:FindFirstChild("HumanoidRootPart")
	if hrp then hrp.CFrame = CFrame.new(p) notify("Moved to " .. key) end
end)
local BtnTpItem = TpTab:AddButton("To item", function()
	local name = DItemTp.Value
	if not name or name == "(nothing)" then notify("Pick item first.") return end
	local p = findPartPos(name) or findModelPos(name)
	if not p then notify("Item gone — rescan.") return end
	local hrp = Plr.Character and Plr.Character:FindFirstChild("HumanoidRootPart")
	if hrp then hrp.CFrame = CFrame.new(Vector3.new(p.X, ground(p) + 3, p.Z)) notify("Now at " .. itemFriendly(name)) end
end)
local BtnTpMon = TpTab:AddButton("Spawn near monster", function()
	for m, d in pairs(monsterList) do
		local hrp = Plr.Character and Plr.Character:FindFirstChild("HumanoidRootPart")
		if hrp and d.Root then
			hrp.CFrame = d.Root.CFrame * CFrame.new(0, 0, 8)
			notify("Near " .. monsterFriendly(d.Name))
		end
		return
	end
	notify("No monsters now.")
end)
local BtnBring = TpTab:AddButton("Bring item", function()
	local name = DItemTp.Value
	if not name or name == "(nothing)" then notify("Pick item first.") return end
	local hrp = Plr.Character and Plr.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then notify("Wait to load.") return end
	local target = (hrp.CFrame * CFrame.new(0, 1, -4)).Position
	local found, bestD = nil, math.huge
	for inst, info in pairs(itemTargets) do
		if info.Name == name then
			local d = (inst.Position - hrp.Position).Magnitude
			if d < bestD then found, bestD = inst, d end
		end
	end
	if found then
		smoothBring(found, target)
		notify("Bringing " .. itemFriendly(name))
	else
		notify("Item gone — rescan.")
	end
end)
local BtnBringAll = TpTab:AddButton("Bring all", function()
	local hrp = Plr.Character and Plr.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then notify("Wait to load.") return end
	local target = (hrp.CFrame * CFrame.new(0, 1, -4)).Position
	local n = 0
	task.spawn(function()
		for inst, info in pairs(itemTargets) do
			if alive then
				local grid = Vector3.new((n % 5) * 2 - 4, 0, math.floor(n / 5) * 2)
				smoothBring(inst, target + grid)
				n = n + 1
			end
			task.wait(0.03)
		end
		notify("Bringing " .. n .. " items")
	end)
end)
TpTab:AddDivider()
local TAutoPick = TpTab:AddToggle("azure-autopick", { Text = "Auto pick", Default = false })
local SAutoPickRange = TpTab:AddSlider("azure-autopick-range", { Text = "Range", Min = 5, Max = 50, Rounding = 0, Default = 50, Suffix = " studs" })

-- ── Info tab ───────────────────────────────────────────────────────────
local InfoTab = LeftTabs.Info
InfoTab:AddLabel("Project Azure | Granny Multiplayer.")
InfoTab:AddLabel("All off. Turn on.")
InfoTab:AddDivider()
InfoTab:AddLabel("Join our Discord:")
InfoTab:AddLabel("https://discord.gg/5GbZqtaeAe")
local BtnCopyDiscord = InfoTab:AddButton("Copy invite", function()
	local ok = pcall(function() setclipboard("https://discord.gg/5GbZqtaeAe") end)
	notify(ok and "Invite copied!" or "discord.gg/5GbZqtaeAe")
end)
InfoTab:AddDivider()
local TNotif = InfoTab:AddToggle("azure-notifs", { Text = "Notifs", Default = false, Callback = function(v)
	AZURE.notifsOn = v
end })
local TWatermark = InfoTab:AddToggle("azure-watermark", { Text = "Watermark", Default = false, Callback = function(v)
	pcall(function()
		if v then Library:SetWatermarkVisibility(true) else Library:SetWatermarkVisibility(false) end
	end)
end })
local LLastEsc = InfoTab:AddLabel("Escape: idle")
AZURE.EscLabel = LLastEsc
InfoTab:AddDivider()
local BtnSaveCfg = InfoTab:AddButton("Save", function()
	AZURE.saveConfig()
end)
local BtnLoadCfg = InfoTab:AddButton("Load", function()
	AZURE.loadConfig()
end)
local BtnHop = InfoTab:AddButton("Hop server", function()
	pcall(function() if game.JobId ~= "" then TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId) end end)
end)
InfoTab:AddDivider()
local BtnUnload = InfoTab:AddButton("Unload", function()
	pcall(AZURE.disable)
end)
-- ── config system (file-based) ────────────────────────────────────────
local function configPath()
	return "AZURE-config.json"
end
local function collectConfig()
	local data = {}
	local function add(tab)
		for k, obj in pairs(tab) do
			if typeof(k) == "string" and obj and obj.Value ~= nil then
				data[k] = obj.Value
			end
		end
	end
	add(Library.Options)
	add(Library.Toggles)
	return data
end
local function applyConfig(data)
	local n = 0
	for k, v in pairs(data) do
		local obj = Library.Options[k] or Library.Toggles[k]
		if obj then
			local ok = pcall(function() obj:SetValue(v) end)
			if ok then n = n + 1 end
		end
	end
	return n
end
function AZURE.saveConfig()
	local data = collectConfig()
	local ok = pcall(function() writefile(configPath(), HttpService:JSONEncode(data)) end)
	if not ok then
		pcall(function()
			if not isfolder("AZURE") then makefolder("AZURE") end
			writefile("AZURE/" .. configPath(), HttpService:JSONEncode(data))
		end)
	end
	notify("Saved.")
end
function AZURE.loadConfig()
	local text = nil
	pcall(function() text = readfile(configPath()) end)
	if not text then pcall(function() text = readfile("AZURE/" .. configPath()) end) end
	if not text then notify("No config.") return end
	local ok, data = pcall(function() return HttpService:JSONDecode(text) end)
	if not ok then notify("Bad config.") return end
	local n = applyConfig(data)
	itemSyncDirty = true
	notify("Loaded (" .. tostring(n) .. " settings)")
end

-- ── render loop ───────────────────────────────────────────────────────
local myPlrHrp = nil
local function distTo(pos)
	if not myPlrHrp then return nil end
	return (pos - myPlrHrp.Position).Magnitude
end
local function inTagRange(pos)
	local r = LABEL_DIST[DLabelDist.Value] or 0
	if r <= 0 then return true end
	local d = distTo(pos)
	return d == nil or d <= r
end
local function inChamRange(pos)
	local r = GLOW_DIST[DGlowDist.Value] or 0
	if r <= 0 then return true end
	local d = distTo(pos)
	return d == nil or d <= r
end
local function renderWork(dt)
	if not alive then return end

	myPlrHrp = Plr.Character and Plr.Character:FindFirstChild("HumanoidRootPart")
	local master = TEsp.Value
	local focusName = DFocus.Value
	local fillT = 0.55 -- 1 - 0.45 cham thickness
	local outT = 0.1 -- fixed outline

	-- chams: reconciled EVERY frame, even when ESP/glow are off,
	-- so no glow can ever stay behind
	for inst, info in pairs(itemTargets) do
		local focused = focusName ~= "(all)" and info.Name ~= focusName
		local shown = master and TChams.Value and inChamRange(inst.Position) and not focused
		applyCham(inst, shown, pick(ColItems.Value), fillT, outT, "item")
	end
	for m, d in pairs(monsterList) do
		if d.Fixed or d.Moved then
			applyCham(m, master and TChams.Value and inChamRange(d.Root.Position), pick(ColMon.Value), fillT, outT, "monster")
		end
	end
	for ch in pairs(playerList) do
		local r = ch:FindFirstChild("HumanoidRootPart")
		if r then
			applyCham(ch, master and TChams.Value and inChamRange(r.Position), pick(ColPly.Value), fillT, outT, "player")
		end
	end
	-- godmode: the game re-enables CanTouch on its kill parts,
	-- so re-disarm + record every frame while it's on
	if TGod.Value then
		for m, d in pairs(monsterList) do
			local rec = godCache[m]
			if not rec then rec = {} godCache[m] = rec end
			for _, p in ipairs(m:GetDescendants()) do
				if p:IsA("BasePart") then
					if not rec[p] then rec[p] = { p.CanCollide, p.CanTouch } end
					p.CanCollide = false
					p.CanTouch = false
				end
			end
		end
	end

	local chamCounts = countChams()
	AZURE.stats.chamItems = chamCounts.item or 0
	AZURE.stats.chamMonsters = chamCounts.monster or 0
	AZURE.stats.chamPlayers = chamCounts.player or 0

	-- tags + boxes
	if master then
		local ci, cm, cp = pick(ColItems.Value), pick(ColMon.Value), pick(ColPly.Value)
		local showNames = TEspName.Value
		local showBoxes = TEspBox.Value
		local showDist = TEspDist.Value
		local showTracers = TEspTracers.Value
		local maxTags = ITEM_LABEL_MODES[DItemLabels.Value] or 0
		local tagsOff = maxTags < 0

		local itemList = {}
		for inst, info in pairs(itemTargets) do
			itemList[#itemList + 1] = { inst = inst, info = info, d = distTo(inst.Position) or math.huge }
		end
		table.sort(itemList, function(a, b) return a.d < b.d end)

		local shownCount = 0
		for _, e in ipairs(itemList) do
			local inst, info = e.inst, e.info
			local draws = getDraws(inst)
			if (focusName ~= "(all)" and info.Name ~= focusName)
				or not inTagRange(inst.Position)
				or (maxTags > 0 and shownCount >= maxTags) then
				setTag(inst, nil, ci, false)
				hideDraws(draws)
				continue
			end
			shownCount = shownCount + 1
			if tagsOff then
				setTag(inst, nil, ci, false)
			else
				local label = itemFriendly(info.Name)
				if info.InBackpack then label = label .. " [carrying]" end
				if showDist and myPlrHrp then
					label = label .. (" — %d studs"):format(math.floor(e.d))
				end
				-- text sits directly on the item
				setTag(inst, label, ci, showNames, 0.4)
			end
			drawBox(draws, inst.Position, 4, ci, showBoxes)
			drawTracer(draws, inst.Position, ci, showTracers)
		end

		for m, d in pairs(monsterList) do
			local pos = d.Root.Position
			if not d.Fixed and not d.Moved then
				d.Moved = (pos - d.LastPos).Magnitude > 0.75
			end
			d.LastPos = pos
			if not (d.Fixed or d.Moved) then continue end
			local draws = getDraws(m)
			if not inTagRange(pos) then
				setTag(d.Root, nil, cm, false)
				hideDraws(draws)
				continue
			end
			local label = monsterFriendly(d.Name)
			if showDist and myPlrHrp then
				label = label .. (" — %d studs"):format(math.floor((pos - myPlrHrp.Position).Magnitude))
			end
			local h = d.Humanoid
			local frac = h and h.MaxHealth > 0 and (h.Health / h.MaxHealth) or 1
			local top = pos + Vector3.new(0, 2.5, 0)
			setTag(d.Root, label, cm, showNames)
			drawBox(draws, top, 8, cm, showBoxes)
			drawBar(draws, top, frac, cm, TEspHp.Value)
			drawTracer(draws, top, cm, showTracers)
		end

		for ch, info in pairs(playerList) do
			local r = ch:FindFirstChild("HumanoidRootPart")
			if r then
				local draws = getDraws(ch)
				if not inTagRange(r.Position) then
					setTag(r, nil, cp, false)
					hideDraws(draws)
					continue
				end
				local label = info.Name
				if showDist and myPlrHrp then
					label = label .. (" — %d studs"):format(math.floor((r.Position - myPlrHrp.Position).Magnitude))
				end
				setTag(r, label, cp, showNames)
				drawBox(draws, r.Position, 7, cp, showBoxes)
				drawTracer(draws, r.Position, cp, showTracers)
			end
		end
	else
		hideAllEsp()
	end

	-- safe-zone dash
	if TTeleportSafe.Value and myPlrHrp then
		for m, d in pairs(monsterList) do
			if (d.Root.Position - myPlrHrp.Position).Magnitude < SSSafeDist.Value then
				local p = resolveDest("Spawn point", true)
				if p then
					myPlrHrp.CFrame = CFrame.new(p)
					notify("Monster close — dashed.")
					task.wait(1)
				end
				break
			end
		end
	end

	-- fly
	if TFly.Value then
		if myPlrHrp and Plr.Character then
			for _, part in ipairs(Plr.Character:GetDescendants()) do
				if part:IsA("BasePart") then part.CanCollide = false end
			end
			local spd = SFly.Value * dt
			local dir = Vector3.new(
				(UIS:IsKeyDown(Enum.KeyCode.D) and 1 or 0) - (UIS:IsKeyDown(Enum.KeyCode.A) and 1 or 0),
				(UIS:IsKeyDown(Enum.KeyCode.Space) and 1 or 0) - (UIS:IsKeyDown(Enum.KeyCode.LeftShift) and 1 or 0),
				(UIS:IsKeyDown(Enum.KeyCode.W) and 1 or 0) - (UIS:IsKeyDown(Enum.KeyCode.S) and 1 or 0)
			)
			if dir.Magnitude > 0 then
				local cf = Camera.CFrame
				local flat = CFrame.lookAt(cf.Position, cf.Position + Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z))
				myPlrHrp.CFrame = flat * CFrame.new(dir.Unit * spd)
				myPlrHrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
			end
		end
	end

	-- walk / jump / void guard
	if myPlrHrp and Plr.Character then
		local hum = Plr.Character:FindFirstChildOfClass("Humanoid")
		if hum then
			if TWalk.Value then hum.WalkSpeed = SWalk.Value end
			if TJump.Value then hum.JumpPower = SJump.Value end
		end
		if TNoFall.Value and myPlrHrp.Position.Y < -30 then
			local p = resolveDest("Spawn point", true)
			if p then myPlrHrp.CFrame = CFrame.new(p) end
		end
	end
end

local renderConn = RunService.RenderStepped:Connect(function(dt)
	pcall(function() renderWork(dt) end)
end)

-- ── steady loops ──────────────────────────────────────────────────────
local lastItemKey = ""
AZURE.safeLoop("scan", function()
	if scanItemsWanted or itemSyncDirty then
		scanItems()
		scanMonsters()
		scanPlayers()
		scanItemsWanted = false
		itemSyncDirty = false

		-- item teleport list only contains real pickups
		local names = {}
		for _, info in pairs(itemTargets) do
			table.insert(names, info.Name)
		end
		table.sort(names)
		local key = table.concat(names, "|")
		if key ~= lastItemKey then
			lastItemKey = key
			local oldFocus = DFocus.Value
			pcall(function()
				DItemTp:SetValues({ "(nothing)" })
				DItemTp:AddValues(names)
				if #names > 0 then DItemTp:SetValue("(nothing)") end
				DFocus:SetValues({ "(all)" })
				DFocus:AddValues(names)
				if oldFocus and oldFocus ~= "(all)" then
					DFocus:SetValue(oldFocus)
				else
					DFocus:SetValue("(all)")
				end
			end)
		end

		pcall(function()
			AZURE.EspCountLabel:SetText(("%d items / %d monsters / %d players  •  %d glows"):format(
				AZURE.stats.items, AZURE.stats.monsters, AZURE.stats.players,
				AZURE.stats.chamItems + AZURE.stats.chamMonsters + AZURE.stats.chamPlayers))
		end)
	end
	readEsc()
	task.wait(SEspRefresh.Value)
end)

AZURE.safeLoop("pickup", function()
	if not TAutoPick.Value then return end
	local hrp = Plr.Character and Plr.Character:FindFirstChild("HumanoidRootPart")
	if not hrp then return end
	local best, bestDist = nil, SAutoPickRange.Value
	for inst, info in pairs(itemTargets) do
		if info.InBackpack then continue end
		local avail = info.AvailRef == nil or info.AvailRef.Value
		if not avail then continue end
		local d = (inst.Position - hrp.Position).Magnitude
		if d <= bestDist then best, bestDist = inst, d end
	end
	if best then
		local remote = best:FindFirstChild("InteractRemote")
		if remote and remote:IsA("RemoteEvent") then
			pcall(function() remote:FireServer() end)
			task.wait(0.4)
		end
	end
	task.wait(0.5)
end)

AZURE.safeLoop("sweep", function()
	local n = sweepCaches()
	if n > 0 then warn("[AZURE] removed " .. n .. " stale esp objects") end
	task.wait(5)
end)

AZURE.safeLoop("stats", function()
	local fps = math.floor(1 / (RunService.RenderStepped:Wait() or 0.001))
	local ok, ping = pcall(function() return game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValue() end)
	if TWatermark.Value then
		Library:SetWatermark(string.format("Project Azure | Granny Multiplayer | %d fps | %.0f ms", fps, ok and ping or 0))
	end
	task.wait(1)
end)

-- ── startup ────────────────────────────────────────────────────────────
task.spawn(function()
	while alive and not Plr.PlayerGui do task.wait() end
	task.wait(1.5)
	scanItems()
	scanMonsters()
	scanPlayers()
	if AZURE.seq == mySeq then notify("Project Azure | Granny Multiplayer loaded.") end
	if AZURE.seq == mySeq then
		pcall(function() Library:Notify({ Title = "Azure", Description = "Press Right Shift to toggle the GUI", Time = 5 }) end)
	end
	AZURE.started = true
end)

-- ── unload: everything undone, nothing left behind ────────────────────
local function myDisable()
	if not alive then return end
	alive = false
	if renderConn then pcall(function() renderConn:Disconnect() end) renderConn = nil end
	applyGodmode(false)
	sweepCaches()
	for inst, e in pairs(chamCache) do
		pcall(function() e.H:Destroy() end)
	end
	chamCache = {} -- strong keys: sweep can always find leftovers
	hideAllEsp()
	pcall(function()
		local h = Plr.Character and Plr.Character:FindFirstChildOfClass("Humanoid")
		if h then h.WalkSpeed = 16 h.JumpPower = 50 end
	end)
	if TFly and TFly.Value then
		pcall(function()
			local c = Plr.Character
			if c then
				for _, part in ipairs(c:GetDescendants()) do
					if part:IsA("BasePart") then part.CanCollide = true end
				end
			end
		end)
	end
	pcall(function() Library:SetWatermarkVisibility(false) end)
	pcall(Library.Unload)
	AZURE.run = false
end
AZURE.disable = myDisable
AZURE.disableList[mySeq] = myDisable

-- newest instance wins: after everyone has finished building,
-- kill any older instances still running
task.defer(function()
	if AZURE.seq ~= mySeq then return end
	for k, fn in pairs(AZURE.disableList) do
		if k ~= mySeq then pcall(fn) end
	end
	AZURE.disableList = { [mySeq] = myDisable }
	AZURE.run = true
end)
