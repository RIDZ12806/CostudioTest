--[[
DZ HUP  |  3D Name Maker  (Executor Edition)
Made by RiyadoDzz

Single LocalScript-style file. No Studio setup needed:
letters are loaded from Roblox asset IDs automatically.
Names are saved to a file and restored on the next launch.

v3: effects (dual color flow, rainbow, float, glow) are now saved INSIDE each name
(attributes on the model). Every animated name also gets its own Script (DZHUP_Effect) inside it,
so the effects keep playing after you save the project and open it again. Run this script once so old names
are rebuilt with the new data, then save the project.

FIX: the main chunk had more than 200 local variables at the same time
(Luau limit: "Out of local registers ... exceeded limit 200").
Nothing was removed or changed in behaviour. Self-contained sections are
now wrapped in `do ... end` blocks so their locals are released.
Also: no backslash is used anymore (Studio Lite deletes them on paste).
]]

do -- BLOCK banner
	local function u(...)
		local out = {}
		for _, code in ipairs({ ... }) do
			out[#out + 1] = utf8.char(code)
		end
		return table.concat(out)
	end
	local pad = string.rep("_", 16)
	print(pad .. u(0x2591, 0x2588, 0x2580, 0x2584, 0x2591, 0x2588, 0x2591, 0x2588, 0x2591, 0x2588, 0x2580, 0x2584, 0x2591, 0x2580, 0x2580, 0x2588) .. pad)
	print(pad .. u(0x2591, 0x2588, 0x2580, 0x2584, 0x2591, 0x2584, 0x2580, 0x2584, 0x2591, 0x2588, 0x2591, 0x2588, 0x2591, 0x2584, 0x2580, 0x2591) .. pad)
	print(pad .. u(0x2591, 0x2580, 0x2591, 0x2580, 0x2591, 0x2580, 0x2591, 0x2580, 0x2591, 0x2580, 0x2580, 0x2591, 0x2591, 0x2580, 0x2580, 0x2580) .. pad)
	print(" ")
	print(u(0x25C6) .. " RXDZ | NAME STUDIO")
	print(u(0x25C6) .. " Name Maker " .. u(0x2022) .. " Symbols " .. u(0x2022) .. " Emojis")
end -- BLOCK banner

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

---------------------------------------------------------------------
-- CONFIG  (fill the marked fields)
---------------------------------------------------------------------
local CONFIG = {
	Creator = "RiyadoDzz",
	Community = "DZ HUP",
	Discord = "https://discord.gg/Dj3CCnZAxJ",
	WhatsApp = "https://whatsapp.com/channel/0029VbDuGkhGJP8DJbzVEG0K",
	TikTok = "https://tiktok.com/@rx..dz",

	-- >>> Your picture (use ONE of these two) <<<
	RobloxUsername = "RiyadoDzz", -- your avatar is loaded automatically from this username
	AvatarRobloxUserId = 0, -- optional: set the user id directly if the username lookup fails
	AvatarImageUrl = "", -- or a direct image link (GitHub raw), e.g. https://raw.githubusercontent.com/.../me.png

	-- >>> Fonts <<<
	-- Each font is one asset (a model holding the letters and numbers) or one id per letter.
	-- Add more fonts to this list later. Optional per font:
	--   frontNegZ = false  (set it if that font looks mirrored)
	--   orient = Vector3.new(x, y, z)  (degrees, if the letters are rotated inside the model)
	DefaultFont = "Rockwell",
	Fonts = {
		{ key = "Rockwell", title = "Rockwell", packId = 4506165589, letterIds = {} },
		{ key = "GothamBlack", title = "Gotham Black", packId = 15715862597, letterIds = {} },
		{ key = "Horror", title = "Horror", packId = 3789128815, letterIds = {} },
	},

	SaveFile = "DZHUP_NameMaker.json",
	PromptOnLaunch = true, -- ask about Discord / WhatsApp when the system opens

	-- sound played when any button is pressed: the first one that loads is used
	-- (official Roblox client sounds first, then official library clicks)
	ClickSoundIds = {
		"rbxasset://sounds/button.wav",
		"rbxasset://sounds/switch.wav",
		"rbxasset://sounds/clickfast.wav",
		"rbxassetid://421058925",
		"rbxassetid://6895079853",
	},
	ClickSoundVolume = 0.8,

	-- press this key to open / close the window
	ToggleKey = Enum.KeyCode.RightShift,

	-- dual color: how fast the colors flow (cycles per second) and how many waves fit in one name
	WaveSpeed = 0.35,
	WaveSpread = 1,

	MaxNameLength = 24,
	MaxNames = 40,
	LetterGap = 0.16,
	SpaceWidthRatio = 0.6,
	PlaceDistance = 18, -- fallback distance in front of you
	MaxPlaceDistance = 150, -- furthest point your view can hit when placing a name
	StackRadius = 25, -- names closer than this are stacked above each other
	HeightOffset = 2.8,
	-- true = the readable face of each letter is -Z. Set false if names look mirrored.
	FrontFaceIsNegativeZ = true,
	-- Saved names come back where you saved them. If a saved name is farther than this
	-- from you (for example you opened another project), it is placed in front of you instead.
	RestoreMaxDistance = 150,
}

local FONTS = CONFIG.Fonts
local FONT_BY_KEY = {}
for _, font in ipairs(FONTS) do
	FONT_BY_KEY[font.key] = font
end
local function fontOf(key)
	return FONT_BY_KEY[key] or FONT_BY_KEY[CONFIG.DefaultFont] or FONTS[1]
end

---------------------------------------------------------------------
-- Cleanup of an older run
---------------------------------------------------------------------
local genv = (type(getgenv) == "function" and getgenv()) or _G
if genv.DZHUP_NameMakerCleanup then
	pcall(genv.DZHUP_NameMakerCleanup)
end
local conns = {}
local function on(signal, fn)
	local c = signal:Connect(fn)
	table.insert(conns, c)
	return c
end

---------------------------------------------------------------------
-- Executor helpers
---------------------------------------------------------------------
local hasFS = type(writefile) == "function" and type(readfile) == "function" and type(isfile) == "function"

local function copyText(text)
	local fn = setclipboard or toclipboard or set_clipboard
	if type(fn) == "function" then
		local ok = pcall(fn, text)
		return ok
	end
	return false
end

local function loadObject(id)
	local ok, result = pcall(function()
		return game:GetObjects("rbxassetid://" .. tostring(id))
	end)
	if ok and type(result) == "table" and result[1] then
		return result[1]
	end
	return nil, tostring(result)
end

---------------------------------------------------------------------
-- Saved data
---------------------------------------------------------------------
local save = { settings = {}, places = {} }
if hasFS and isfile(CONFIG.SaveFile) then
	pcall(function()
		local decoded = HttpService:JSONDecode(readfile(CONFIG.SaveFile))
		if type(decoded) == "table" then
			save.settings = type(decoded.settings) == "table" and decoded.settings or {}
			save.places = type(decoded.places) == "table" and decoded.places or {}
		end
	end)
end

local placeKey = tostring(game.PlaceId)
if type(save.places[placeKey]) ~= "table" then
	save.places[placeKey] = {}
end
local names = save.places[placeKey]

local function persist()
	if not hasFS then
		return false
	end
	local ok = pcall(function()
		writefile(CONFIG.SaveFile, HttpService:JSONEncode(save))
	end)
	return ok
end

---------------------------------------------------------------------
-- Theme
---------------------------------------------------------------------
local THEME = {
	bg = Color3.fromRGB(14, 16, 23),
	bgTop = Color3.fromRGB(24, 27, 38),
	header = Color3.fromRGB(17, 19, 27),
	surface = Color3.fromRGB(23, 26, 36),
	surface2 = Color3.fromRGB(33, 37, 50),
	field = Color3.fromRGB(13, 15, 21),
	line = Color3.fromRGB(50, 56, 75),
	text = Color3.fromRGB(238, 241, 248),
	muted = Color3.fromRGB(140, 149, 172),
	dark = Color3.fromRGB(22, 19, 12),
	accent = Color3.fromRGB(240, 185, 80),
	accentSoft = Color3.fromRGB(255, 218, 150),
	danger = Color3.fromRGB(240, 98, 110),
	success = Color3.fromRGB(96, 214, 150),
	discord = Color3.fromRGB(88, 101, 242),
	whatsapp = Color3.fromRGB(37, 211, 102),
	tiktok = Color3.fromRGB(254, 44, 85),
}

local PALETTE = {
	{ "White", Color3.fromRGB(245, 245, 245) },
	{ "Gold", Color3.fromRGB(255, 211, 105) },
	{ "Orange", Color3.fromRGB(255, 150, 60) },
	{ "Red", Color3.fromRGB(255, 70, 75) },
	{ "Pink", Color3.fromRGB(255, 105, 190) },
	{ "Purple", Color3.fromRGB(170, 115, 255) },
	{ "Blue", Color3.fromRGB(65, 150, 255) },
	{ "Cyan", Color3.fromRGB(80, 230, 240) },
	{ "Green", Color3.fromRGB(70, 225, 145) },
	{ "Lime", Color3.fromRGB(190, 240, 70) },
	{ "Silver", Color3.fromRGB(170, 176, 190) },
	{ "Black", Color3.fromRGB(34, 34, 40) },
}

local STYLES = {
	{ key = "Plastic", title = "Plastic" },
	{ key = "Neon", title = "Neon" },
	{ key = "Metal", title = "Metal" },
	{ key = "Glass", title = "Glass" },
	{ key = "Modern", title = "Modern" },
}
local STYLE_TITLES = {}
for _, item in ipairs(STYLES) do
	STYLE_TITLES[item.key] = item.title
end

local STYLE_DEFS = {
	Plastic = { material = Enum.Material.SmoothPlastic, reflectance = 0.03, transparency = 0 },
	Neon = { material = Enum.Material.Neon, reflectance = 0, transparency = 0 },
	Metal = { material = Enum.Material.Metal, reflectance = 0.12, transparency = 0 },
	Glass = { material = Enum.Material.Glass, reflectance = 0.08, transparency = 0.12 },
	Modern = { material = Enum.Material.SmoothPlastic, reflectance = 0.08, transparency = 0 },
}

---------------------------------------------------------------------
-- UI helpers
---------------------------------------------------------------------
local function new(className, props, parent)
	local instance = Instance.new(className)
	for key, value in pairs(props) do
		instance[key] = value
	end
	instance.Parent = parent
	return instance
end

local function corner(parent, radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function stroke(parent, color, transparency, thickness)
	return new("UIStroke", {
		Color = color,
		Transparency = transparency,
		Thickness = thickness or 1,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

local function tween(instance, duration, goal, style, direction, delay)
	local t = TweenService:Create(
		instance,
		TweenInfo.new(
			duration,
			style or Enum.EasingStyle.Quad,
			direction or Enum.EasingDirection.Out,
			0,
			false,
			delay or 0
		),
		goal
	)
	t:Play()
	return t
end

local function loop(instance, duration, goal, style, reverses)
	local t = TweenService:Create(
		instance,
		TweenInfo.new(duration, style or Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, reverses ~= false),
		goal
	)
	t:Play()
	return t
end

local function textLabel(parent, text, props)
	props.BackgroundTransparency = 1
	props.Text = text
	props.Font = props.Font or Enum.Font.GothamMedium
	props.TextColor3 = props.TextColor3 or THEME.text
	props.TextSize = props.TextSize or 13
	props.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Left
	return new("TextLabel", props, parent)
end

local function makeButton(parent, props, options)
	options = options or {}
	local fill = options.fill or THEME.surface2
	local hoverFill = options.hover or fill:Lerp(Color3.new(1, 1, 1), 0.08)
	local pressFill = fill:Lerp(Color3.new(0, 0, 0), 0.25)

	props.BackgroundColor3 = fill
	props.AutoButtonColor = false
	props.BorderSizePixel = 0
	props.Font = props.Font or Enum.Font.GothamBold
	props.TextColor3 = props.TextColor3 or THEME.text
	props.TextSize = props.TextSize or 13

	local button = new("TextButton", props, parent)
	corner(button, options.radius or 9)
	local buttonStroke = stroke(button, options.stroke or THEME.line, options.strokeTransparency or 0.3, 1)

	local hovering = false
	button.MouseEnter:Connect(function()
		hovering = true
		tween(button, 0.12, { BackgroundColor3 = hoverFill })
	end)
	button.MouseLeave:Connect(function()
		hovering = false
		tween(button, 0.12, { BackgroundColor3 = fill })
	end)
	button.MouseButton1Down:Connect(function()
		tween(button, 0.06, { BackgroundColor3 = pressFill })
	end)
	button.MouseButton1Up:Connect(function()
		tween(button, 0.1, { BackgroundColor3 = hovering and hoverFill or fill })
	end)
	return button, buttonStroke
end

local function trim(text)
	return (string.gsub(string.gsub(text, "^%s+", ""), "%s+$", ""))
end

---------------------------------------------------------------------
-- Roots
---------------------------------------------------------------------
local oldFolder = Workspace:FindFirstChild("DZHUP_Names")
if oldFolder then
	oldFolder:Destroy()
end
local namesFolder = Instance.new("Folder")
namesFolder.Name = "DZHUP_Names"
namesFolder.Parent = Workspace

local guiParent
do
	local ok, hui = pcall(function()
		return type(gethui) == "function" and gethui() or nil
	end)
	guiParent = (ok and hui) or player:WaitForChild("PlayerGui")
end
pcall(function()
	for _, child in ipairs(guiParent:GetChildren()) do
		if child.Name == "DZHUP_NameMaker" then
			child:Destroy()
		end
	end
end)

local PANEL_W, PANEL_H = 620, 510
local MIN_SCALE = 0.4

local gui = new("ScreenGui", {
	Name = "DZHUP_NameMaker",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 999,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, guiParent)

---------------------------------------------------------------------
-- Button click sound (every TextButton in the interface)
---------------------------------------------------------------------
local SoundService = game:GetService("SoundService")
local ContentProvider = game:GetService("ContentProvider")

pcall(function()
	for _, old in ipairs(SoundService:GetChildren()) do
		if old.Name == "DZHUP_ClickSound" then
			old:Destroy()
		end
	end
end)

local clickSound = new("Sound", {
	Name = "DZHUP_ClickSound",
	SoundId = CONFIG.ClickSoundIds[1],
	Volume = CONFIG.ClickSoundVolume,
}, SoundService)

-- pick the first sound that really loads on this device
task.spawn(function()
	for _, id in ipairs(CONFIG.ClickSoundIds) do
		local test = Instance.new("Sound")
		test.SoundId = id
		test.Volume = 0
		test.Parent = SoundService
		pcall(function()
			ContentProvider:PreloadAsync({ test })
		end)
		local waited = 0
		while not test.IsLoaded and waited < 2 do
			task.wait(0.1)
			waited += 0.1
		end
		local works = test.IsLoaded and test.TimeLength > 0
		test:Destroy()
		if works then
			clickSound.SoundId = id
			return
		end
	end
end)

local function playClick()
	pcall(function()
		clickSound.TimePosition = 0
		clickSound:Play()
	end)
end

local function hookClick(instance)
	if instance:IsA("TextButton") and instance.Name ~= "ResizeHandle" then
		instance.Activated:Connect(playClick)
	end
end
gui.DescendantAdded:Connect(hookClick)

local backdrop = new("Frame", {
	Name = "Backdrop",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(0, 0, 0),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	Visible = false,
}, gui)

local openButton, openStroke = makeButton(gui, {
	Text = "RX",
	AnchorPoint = Vector2.new(0, 0.5),
	Position = UDim2.new(0, 12, 0.5, 0),
	Size = UDim2.fromOffset(44, 44),
	TextSize = 14,
	Font = Enum.Font.GothamBlack,
}, { fill = THEME.header, stroke = THEME.accent, strokeTransparency = 0.6, radius = 22 })
openButton.TextColor3 = THEME.accent
openButton.BackgroundTransparency = 0.5
openButton.TextTransparency = 0.1
local openButtonScale = new("UIScale", { Scale = 1 }, openButton)

local holder = new("Frame", {
	Name = "Holder",
	Position = UDim2.fromOffset(0, 0),
	Size = UDim2.fromOffset(PANEL_W, PANEL_H),
	BackgroundTransparency = 1,
	Visible = false,
}, gui)
local scaler = new("UIScale", { Scale = 1 }, holder)

-- Plain Frame (no CanvasGroup) so text stays sharp at any size
local panel = new("Frame", {
	Name = "Panel",
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.bg,
	BorderSizePixel = 0,
	ClipsDescendants = true,
}, holder)
corner(panel, 16)
local panelStroke = stroke(panel, THEME.line, 0.2, 1.2)
local popScale = new("UIScale", { Scale = 0.9 }, panel)

do -- BLOCK fillFrame
local fillFrame = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
}, panel)
corner(fillFrame, 16)
new("UIGradient", { Color = ColorSequence.new(THEME.bgTop, THEME.bg), Rotation = 90 }, fillFrame)
end -- BLOCK fillFrame

---------------------------------------------------------------------
-- Position and size
---------------------------------------------------------------------
local placed = false

local function maxScaleFor(x, y)
	local v = gui.AbsoluteSize
	return math.max(MIN_SCALE, math.min((v.X - x) / PANEL_W, (v.Y - y) / PANEL_H, 1.8))
end

local function defaultScale()
	local v = gui.AbsoluteSize
	return math.clamp(math.min(v.X * 0.94 / PANEL_W, v.Y * 0.9 / PANEL_H), MIN_SCALE, 1.25)
end

local function clampHolder()
	local v = gui.AbsoluteSize
	local w, h = PANEL_W * scaler.Scale, PANEL_H * scaler.Scale
	local x = math.clamp(holder.Position.X.Offset, 0, math.max(0, v.X - w))
	local y = math.clamp(holder.Position.Y.Offset, 0, math.max(0, v.Y - h))
	holder.Position = UDim2.fromOffset(x, y)
end

local function placeInitially()
	local v = gui.AbsoluteSize
	scaler.Scale = defaultScale()
	local w, h = PANEL_W * scaler.Scale, PANEL_H * scaler.Scale
	holder.Position = UDim2.fromOffset(math.max(0, (v.X - w) / 2), math.max(0, (v.Y - h) / 2))
	placed = true
end

gui:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
	if not placed then
		return
	end
	scaler.Scale = math.min(scaler.Scale, maxScaleFor(0, 0))
	clampHolder()
end)

---------------------------------------------------------------------
-- Header
---------------------------------------------------------------------
local header = new("Frame", {
	Name = "Header",
	Size = UDim2.new(1, 0, 0, 56),
	BackgroundColor3 = THEME.header,
	BorderSizePixel = 0,
	Active = true,
}, panel)
corner(header, 16)
new("Frame", {
	Position = UDim2.fromOffset(0, 40),
	Size = UDim2.new(1, 0, 0, 16),
	BackgroundColor3 = THEME.header,
	BorderSizePixel = 0,
}, header)

do -- BLOCK badge
local badge = new("Frame", {
	Position = UDim2.fromOffset(16, 12),
	Size = UDim2.fromOffset(32, 32),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
}, header)
corner(badge, 9)
new("UIGradient", { Color = ColorSequence.new(THEME.accentSoft, THEME.accent), Rotation = 60 }, badge)
textLabel(badge, "3D", {
	Size = UDim2.fromScale(1, 1),
	Font = Enum.Font.GothamBlack,
	TextSize = 14,
	TextColor3 = THEME.dark,
	TextXAlignment = Enum.TextXAlignment.Center,
})
end -- BLOCK badge

textLabel(header, "DZ HUP  Name Maker", {
	Position = UDim2.fromOffset(58, 10),
	Size = UDim2.new(1, -260, 0, 20),
	Font = Enum.Font.GothamBold,
	TextSize = 15,
})
textLabel(header, "Design your name in 3D letters", {
	Position = UDim2.fromOffset(58, 31),
	Size = UDim2.new(1, -260, 0, 16),
	TextSize = 11,
	TextColor3 = THEME.muted,
})

do -- BLOCK logo
-- Glowing RXDZ logo
local logoHolder = new("Frame", {
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -60, 0.5, 0),
	Size = UDim2.fromOffset(70, 28),
	BackgroundTransparency = 1,
}, header)
local logoPill = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.surface,
	BorderSizePixel = 0,
}, logoHolder)
corner(logoPill, 14)
stroke(logoPill, THEME.accent, 0.1, 1.5)
local logoText = textLabel(logoPill, "RXDZ", {
	Size = UDim2.fromScale(1, 1),
	Font = Enum.Font.GothamBlack,
	TextSize = 13,
	TextColor3 = Color3.new(1, 1, 1),
	TextXAlignment = Enum.TextXAlignment.Center,
})
local logoGradient = new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, THEME.accent),
		ColorSequenceKeypoint.new(0.5, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(1, THEME.accent),
	}),
	Offset = Vector2.new(-1, 0),
}, logoText)
loop(logoGradient, 2, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Linear, false)
end -- BLOCK logo

local closeButton = makeButton(header, {
	Text = "X",
	AnchorPoint = Vector2.new(1, 0.5),
	Position = UDim2.new(1, -14, 0.5, 0),
	Size = UDim2.fromOffset(32, 32),
	TextSize = 13,
	Font = Enum.Font.GothamBlack,
	TextColor3 = THEME.muted,
}, { fill = THEME.surface, stroke = THEME.line, strokeTransparency = 0.3, radius = 9, hover = THEME.danger })
closeButton.MouseEnter:Connect(function()
	tween(closeButton, 0.12, { TextColor3 = THEME.text })
end)
closeButton.MouseLeave:Connect(function()
	tween(closeButton, 0.12, { TextColor3 = THEME.muted })
end)

local sweep = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 56),
	Size = UDim2.new(1, 0, 0, 1),
	BackgroundColor3 = THEME.accent,
	BackgroundTransparency = 0.6,
	BorderSizePixel = 0,
	ZIndex = 5,
}, panel)
new("UIGradient", {
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.5, 0),
		NumberSequenceKeypoint.new(1, 1),
	}),
}, sweep)

---------------------------------------------------------------------
-- Tabs and pages
---------------------------------------------------------------------
local TAB_Y, CONTENT_Y = 70, 120
local TAB_COUNT = 4

local tabTrack = new("Frame", {
	Position = UDim2.fromOffset(16, TAB_Y),
	Size = UDim2.fromOffset(588, 38),
	BackgroundColor3 = THEME.field,
	BorderSizePixel = 0,
	ClipsDescendants = true,
}, panel)
corner(tabTrack, 10)
stroke(tabTrack, THEME.line, 0.5, 1)

local tabIndicator = new("Frame", {
	Position = UDim2.new(0, 4, 0, 4),
	Size = UDim2.new(1 / TAB_COUNT, -8, 1, -8),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
}, tabTrack)
corner(tabIndicator, 7)
new("UIGradient", { Color = ColorSequence.new(THEME.accentSoft, THEME.accent), Rotation = 90 }, tabIndicator)

local content = new("Frame", {
	Position = UDim2.fromOffset(16, CONTENT_Y),
	Size = UDim2.fromOffset(588, 356),
	BackgroundTransparency = 1,
}, panel)
local createPage = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, content)
local studioPage = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, content)
local listPage = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, content)
local aboutPage = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, content)
local pages = { createPage, studioPage, listPage, aboutPage }

local TAB_TITLES = { "Create", "Studio", "My Names", "Creator" }
local tabButtons = {}
for i, title in ipairs(TAB_TITLES) do
	tabButtons[i] = new("TextButton", {
		Position = UDim2.new((i - 1) / TAB_COUNT, 0, 0, 0),
		Size = UDim2.new(1 / TAB_COUNT, 0, 1, 0),
		BackgroundTransparency = 1,
		AutoButtonColor = false,
		Text = title,
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextColor3 = THEME.text,
		ZIndex = 3,
	}, tabTrack)
end

textLabel(panel, "Drag the bottom-right corner to resize", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -10),
	Size = UDim2.fromOffset(400, 14),
	TextSize = 10,
	TextColor3 = THEME.muted,
	TextXAlignment = Enum.TextXAlignment.Center,
})

---------------------------------------------------------------------
-- Toast
---------------------------------------------------------------------
local toast = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, 24),
	AutomaticSize = Enum.AutomaticSize.XY,
	BackgroundColor3 = THEME.header,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 30,
	Visible = false,
}, panel)
corner(toast, 10)
local toastStroke = stroke(toast, THEME.line, 1, 1)
new("UIPadding", {
	PaddingTop = UDim.new(0, 8),
	PaddingBottom = UDim.new(0, 8),
	PaddingLeft = UDim.new(0, 16),
	PaddingRight = UDim.new(0, 16),
}, toast)
local toastLabel = textLabel(toast, "", {
	AutomaticSize = Enum.AutomaticSize.XY,
	Size = UDim2.new(),
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextTransparency = 1,
	ZIndex = 31,
	TextXAlignment = Enum.TextXAlignment.Center,
})

local toastToken = 0
local function showToast(message, good)
	toastToken += 1
	local token = toastToken
	local color = good and THEME.success or THEME.danger

	toastLabel.Text = message
	toastLabel.TextColor3 = color
	toastStroke.Color = color
	toast.Visible = true
	toast.Position = UDim2.new(0.5, 0, 1, 24)
	tween(toast, 0.3, { Position = UDim2.new(0.5, 0, 1, -30), BackgroundTransparency = 0.05 }, Enum.EasingStyle.Quint)
	tween(toastLabel, 0.2, { TextTransparency = 0 })
	tween(toastStroke, 0.2, { Transparency = 0.35 })

	task.delay(3.2, function()
		if token ~= toastToken then
			return
		end
		tween(toast, 0.22, { Position = UDim2.new(0.5, 0, 1, 24), BackgroundTransparency = 1 })
		tween(toastLabel, 0.2, { TextTransparency = 1 })
		tween(toastStroke, 0.2, { Transparency = 1 })
		task.delay(0.25, function()
			if token == toastToken then
				toast.Visible = false
			end
		end)
	end)
end

---------------------------------------------------------------------
-- Create page: settings card
---------------------------------------------------------------------
local form = new("Frame", {
	Size = UDim2.fromOffset(350, 356),
	BackgroundColor3 = THEME.surface,
	BorderSizePixel = 0,
}, createPage)
corner(form, 12)
stroke(form, THEME.line, 0.5, 1)

local function sectionTitle(parent, text, y)
	return textLabel(parent, text, {
		Position = UDim2.fromOffset(16, y),
		Size = UDim2.new(1, -32, 0, 16),
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = THEME.muted,
	})
end

sectionTitle(form, "NAME", 12)
local counter = textLabel(form, "0/" .. CONFIG.MaxNameLength, {
	Position = UDim2.fromOffset(16, 12),
	Size = UDim2.new(1, -32, 0, 16),
	TextSize = 11,
	TextColor3 = THEME.muted,
	TextXAlignment = Enum.TextXAlignment.Right,
})

local nameBox = new("TextBox", {
	Position = UDim2.fromOffset(16, 32),
	Size = UDim2.fromOffset(318, 42),
	BackgroundColor3 = THEME.field,
	BorderSizePixel = 0,
	ClearTextOnFocus = false,
	PlaceholderText = "Type your name...",
	PlaceholderColor3 = THEME.muted,
	Text = "",
	TextColor3 = THEME.text,
	TextSize = 17,
	Font = Enum.Font.GothamBold,
	TextXAlignment = Enum.TextXAlignment.Center,
}, form)
corner(nameBox, 10)
local nameStroke = stroke(nameBox, THEME.line, 0.35, 1)
nameBox.Focused:Connect(function()
	tween(nameStroke, 0.18, { Color = THEME.accent, Transparency = 0 })
end)
nameBox.FocusLost:Connect(function()
	tween(nameStroke, 0.18, { Color = THEME.line, Transparency = 0.35 })
end)

sectionTitle(form, "LETTER COLOR", 88)
local swatchGrid = new("Frame", {
	Position = UDim2.fromOffset(16, 108),
	Size = UDim2.fromOffset(318, 59),
	BackgroundTransparency = 1,
}, form)
new("UIGridLayout", {
	CellSize = UDim2.fromOffset(44, 26),
	CellPadding = UDim2.fromOffset(10, 7),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, swatchGrid)

sectionTitle(form, "MATERIAL", 178)
local styleRow = new("Frame", {
	Position = UDim2.fromOffset(16, 198),
	Size = UDim2.fromOffset(318, 30),
	BackgroundTransparency = 1,
}, form)
new("UIGridLayout", {
	CellSize = UDim2.fromOffset(58, 30),
	CellPadding = UDim2.fromOffset(7, 0),
	HorizontalAlignment = Enum.HorizontalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, styleRow)

sectionTitle(form, "FONT", 240)
local fontRow = new("ScrollingFrame", {
	Position = UDim2.fromOffset(16, 260),
	Size = UDim2.fromOffset(318, 30),
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ScrollBarThickness = 0,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.X,
	ScrollingDirection = Enum.ScrollingDirection.X,
}, form)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal,
	Padding = UDim.new(0, 7),
	SortOrder = Enum.SortOrder.LayoutOrder,
}, fontRow)

local createButton = makeButton(form, {
	Text = "CREATE 3D NAME",
	Position = UDim2.fromOffset(16, 302),
	Size = UDim2.fromOffset(318, 46),
	TextSize = 14,
	Font = Enum.Font.GothamBlack,
	TextColor3 = THEME.dark,
}, { fill = THEME.accent, hover = THEME.accentSoft, stroke = THEME.accentSoft, strokeTransparency = 0.5, radius = 11 })

---------------------------------------------------------------------
-- Create page: preview card
---------------------------------------------------------------------
local previewCard = new("Frame", {
	Position = UDim2.fromOffset(362, 0),
	Size = UDim2.fromOffset(226, 356),
	BackgroundColor3 = THEME.surface,
	BorderSizePixel = 0,
}, createPage)
corner(previewCard, 12)
stroke(previewCard, THEME.line, 0.5, 1)

textLabel(previewCard, "PREVIEW", {
	Position = UDim2.fromOffset(14, 12),
	Size = UDim2.new(1, -28, 0, 16),
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextColor3 = THEME.muted,
})

local stage = new("Frame", {
	Position = UDim2.fromOffset(12, 34),
	Size = UDim2.fromOffset(202, 190),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
	ClipsDescendants = true,
}, previewCard)
corner(stage, 10)
new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(40, 45, 62)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(16, 18, 26)),
	}),
	Rotation = 90,
}, stage)
stroke(stage, THEME.line, 0.55, 1)

new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1),
	Position = UDim2.new(0.5, 0, 1, -26),
	Size = UDim2.new(0.76, 0, 0, 1),
	BackgroundColor3 = THEME.line,
	BackgroundTransparency = 0.3,
	BorderSizePixel = 0,
}, stage)

local previewText = textLabel(stage, "YOUR NAME", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.new(0.5, 0, 0.5, -10),
	Size = UDim2.new(1, -24, 1, -64),
	Font = Enum.Font.GothamBlack,
	TextScaled = true,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Center,
})
new("UITextSizeConstraint", { MaxTextSize = 44, MinTextSize = 10 }, previewText)
local previewStroke = new("UIStroke", {
	Thickness = 1.5,
	Color = Color3.fromRGB(8, 8, 12),
	Transparency = 0.2,
	ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
}, previewText)
local previewGradient = new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(150, 150, 150)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 255, 255)),
	}),
	Rotation = 90,
	Enabled = false,
}, previewText)

local previewDual = new("UIGradient", {
	Color = ColorSequence.new(Color3.new(1, 1, 1)),
	Offset = Vector2.new(-1, 0),
	Enabled = false,
}, previewText)
loop(previewDual, 2.2, { Offset = Vector2.new(1, 0) }, Enum.EasingStyle.Linear, false)

local infoStyle = textLabel(previewCard, "", {
	Position = UDim2.fromOffset(14, 238),
	Size = UDim2.new(1, -28, 0, 18),
	TextSize = 12,
})
local infoColor = textLabel(previewCard, "", {
	Position = UDim2.fromOffset(14, 262),
	Size = UDim2.new(1, -28, 0, 18),
	TextSize = 12,
})
local infoFont = textLabel(previewCard, "", {
	Position = UDim2.fromOffset(14, 286),
	Size = UDim2.new(1, -28, 0, 18),
	TextSize = 12,
})
local infoDot = new("Frame", {
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -14, 0, 265),
	Size = UDim2.fromOffset(12, 12),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
}, previewCard)
corner(infoDot, 6)
stroke(infoDot, THEME.text, 0.6, 1)

---------------------------------------------------------------------
-- Selection state
---------------------------------------------------------------------
local selectedColorIndex = 1
local selectedColor2Index = 6
local dualOn = false
local activeSlot = 1
local refreshDual = nil
local selectedStyle = "Plastic"
local selectedFont = fontOf(CONFIG.DefaultFont)
local swatches = {}

-- Studio options (applied to the next name)
local SIZES = {
	{ key = "S", title = "Small" },
	{ key = "M", title = "Medium" },
	{ key = "L", title = "Large" },
	{ key = "XL", title = "Huge" },
}
local SIZE_VALUES = { S = 0.6, M = 1, L = 1.6, XL = 2.4 }
local SPACINGS = {
	{ key = "T", title = "Tight" },
	{ key = "N", title = "Normal" },
	{ key = "W", title = "Wide" },
}
local SPACING_VALUES = { T = 0.25, N = 1, W = 2.6 }
local SHAPES = {
	{ key = "Straight", title = "Straight" },
	{ key = "ArcUp", title = "Arc Up" },
	{ key = "ArcDown", title = "Arc Down" },
	{ key = "Wave", title = "Wave" },
}
local SHAPE_TITLES = { Straight = "Straight", ArcUp = "Arc Up", ArcDown = "Arc Down", Wave = "Wave" }
local CASES = {
	{ key = "Normal", title = "As typed" },
	{ key = "Upper", title = "UPPER" },
	{ key = "Lower", title = "lower" },
	{ key = "Title", title = "Title Case" },
}
local EFFECTS = {
	{ key = "glow", title = "Glow" },
	{ key = "float", title = "Float" },
	{ key = "rainbow", title = "Rainbow" },
}
local FX_TITLES = { glow = "Glow", float = "Float", rainbow = "Rainbow" }

local studio = {
	size = "M",
	gap = "N",
	shape = "Straight",
	case = "Normal",
	fx = { glow = false, float = false, rainbow = false },
}

local function applyCase(text)
	if studio.case == "Upper" then
		return string.upper(text)
	elseif studio.case == "Lower" then
		return string.lower(text)
	elseif studio.case == "Title" then
		return (string.gsub(string.lower(text), "(%a)([%w']*)", function(first, rest)
			return string.upper(first) .. rest
		end))
	end
	return text
end

local function currentFx()
	local result, any = {}, false
	for key, value in pairs(studio.fx) do
		if value then
			result[key] = true
			any = true
		end
	end
	return any and result or nil
end

local function selectedColor2()
	return PALETTE[selectedColor2Index][2]
end

local function selectedColor()
	return PALETTE[selectedColorIndex][2]
end

local function updatePreview()
	local color = selectedColor()
	local text = nameBox.Text ~= "" and applyCase(nameBox.Text) or "YOUR NAME"
	previewText.Text = text
	previewText.TextColor3 = color
	previewText.TextTransparency = 0
	previewGradient.Enabled = false
	previewStroke.Color = Color3.fromRGB(8, 8, 12)
	previewStroke.Thickness = 1.5
	previewStroke.Transparency = 0.2

	if selectedStyle == "Neon" then
		previewStroke.Color = color
		previewStroke.Thickness = 3
		previewStroke.Transparency = 0.55
	elseif selectedStyle == "Metal" then
		previewGradient.Enabled = true
	elseif selectedStyle == "Glass" then
		previewText.TextTransparency = 0.3
		previewStroke.Color = Color3.new(1, 1, 1)
		previewStroke.Transparency = 0.5
	elseif selectedStyle == "Modern" then
		previewText.TextTransparency = 0.88
		previewStroke.Color = color
		previewStroke.Thickness = 2
		previewStroke.Transparency = 0.05
	end

	if dualOn then
		local c2 = selectedColor2()
		previewText.TextColor3 = Color3.new(1, 1, 1)
		previewGradient.Enabled = false
		previewDual.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, color),
			ColorSequenceKeypoint.new(0.5, c2),
			ColorSequenceKeypoint.new(1, color),
		})
		previewDual.Enabled = true
	else
		previewDual.Enabled = false
	end

	infoStyle.Text = "Material: " .. (STYLE_TITLES[selectedStyle] or selectedStyle)
	if dualOn then
		infoColor.Text = "Color: " .. PALETTE[selectedColorIndex][1] .. " + " .. PALETTE[selectedColor2Index][1]
	else
		infoColor.Text = "Color: " .. PALETTE[selectedColorIndex][1]
	end
	if refreshDual then
		refreshDual()
	end
	infoFont.Text = "Font: " .. selectedFont.title
	infoDot.BackgroundColor3 = color
end

for index, item in ipairs(PALETTE) do
	local swatch = new("TextButton", {
		BackgroundColor3 = item[2],
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Text = "",
		LayoutOrder = index,
	}, swatchGrid)
	corner(swatch, 8)
	local ring = stroke(swatch, THEME.accentSoft, 1, 2)
	swatches[index] = ring
	local function isChosen()
		return selectedColorIndex == index or (dualOn and selectedColor2Index == index)
	end
	swatch.MouseEnter:Connect(function()
		if not isChosen() then
			tween(ring, 0.1, { Transparency = 0.6 })
		end
	end)
	swatch.MouseLeave:Connect(function()
		if not isChosen() then
			tween(ring, 0.1, { Transparency = 1 })
		end
	end)
	swatch.Activated:Connect(function()
		if dualOn and activeSlot == 2 then
			selectedColor2Index = index
		else
			selectedColorIndex = index
		end
		updatePreview()
	end)
end

-- Dual color controls (next to the LETTER COLOR title)
local dualButton = new("TextButton", {
	Text = "DUAL",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -16, 0, 84),
	Size = UDim2.fromOffset(56, 20),
	TextSize = 10,
	Font = Enum.Font.GothamBold,
	TextColor3 = THEME.text,
	BackgroundColor3 = THEME.surface2,
	AutoButtonColor = false,
	BorderSizePixel = 0,
}, form)
corner(dualButton, 6)
stroke(dualButton, THEME.line, 0.4, 1)

local slotButtons = {}
for slot = 1, 2 do
	local button = new("TextButton", {
		Text = tostring(slot),
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -(16 + 56 + 6 + (2 - slot) * 28), 0, 84),
		Size = UDim2.fromOffset(22, 20),
		TextSize = 10,
		Font = Enum.Font.GothamBold,
		TextColor3 = THEME.text,
		BackgroundColor3 = THEME.surface2,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		Visible = false,
	}, form)
	corner(button, 6)
	local slotStroke = stroke(button, THEME.accentSoft, 1, 2)
	slotButtons[slot] = { button = button, stroke = slotStroke }
	button.Activated:Connect(function()
		activeSlot = slot
		updatePreview()
	end)
end

refreshDual = function()
	dualButton.BackgroundColor3 = dualOn and THEME.accent or THEME.surface2
	dualButton.TextColor3 = dualOn and THEME.dark or THEME.text
	for slot = 1, 2 do
		local item = slotButtons[slot]
		item.button.Visible = dualOn
		local color = slot == 1 and selectedColor() or selectedColor2()
		item.button.BackgroundColor3 = color
		local luma = color.R * 0.3 + color.G * 0.59 + color.B * 0.11
		item.button.TextColor3 = luma > 0.55 and THEME.dark or THEME.text
		item.stroke.Transparency = (dualOn and activeSlot == slot) and 0 or 1
	end
	for i, ring in ipairs(swatches) do
		local chosen = selectedColorIndex == i or (dualOn and selectedColor2Index == i)
		tween(ring, 0.14, { Transparency = chosen and 0 or 1 })
	end
end

dualButton.Activated:Connect(function()
	dualOn = not dualOn
	activeSlot = 1
	updatePreview()
end)

local chips = {}
local function setStyle(key)
	selectedStyle = key
	for _, chip in ipairs(chips) do
		local active = chip.key == key
		tween(chip.button, 0.14, { BackgroundColor3 = active and THEME.accent or THEME.surface2 })
		chip.button.TextColor3 = active and THEME.dark or THEME.text
		chip.stroke.Transparency = active and 1 or 0.4
	end
	updatePreview()
end

for index, item in ipairs(STYLES) do
	local button = new("TextButton", {
		Text = item.title,
		TextSize = 11,
		Font = Enum.Font.GothamBold,
		TextColor3 = THEME.text,
		BackgroundColor3 = THEME.surface2,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		LayoutOrder = index,
	}, styleRow)
	corner(button, 8)
	local chip = { key = item.key, button = button, stroke = stroke(button, THEME.line, 0.4, 1) }
	table.insert(chips, chip)
	button.MouseEnter:Connect(function()
		if selectedStyle ~= chip.key then
			tween(button, 0.1, { BackgroundColor3 = THEME.line })
		end
	end)
	button.MouseLeave:Connect(function()
		if selectedStyle ~= chip.key then
			tween(button, 0.1, { BackgroundColor3 = THEME.surface2 })
		end
	end)
	button.Activated:Connect(function()
		setStyle(item.key)
	end)
end

local fontChips = {}
local function setFont(key)
	selectedFont = fontOf(key)
	for _, chip in ipairs(fontChips) do
		local active = chip.key == selectedFont.key
		tween(chip.button, 0.14, { BackgroundColor3 = active and THEME.accent or THEME.surface2 })
		chip.button.TextColor3 = active and THEME.dark or THEME.text
		chip.stroke.Transparency = active and 1 or 0.4
	end
	updatePreview()
end

for index, item in ipairs(FONTS) do
	local button = new("TextButton", {
		Text = item.title,
		Size = UDim2.fromOffset(74, 30),
		TextSize = 10,
		Font = Enum.Font.GothamBold,
		TextColor3 = THEME.text,
		BackgroundColor3 = THEME.surface2,
		AutoButtonColor = false,
		BorderSizePixel = 0,
		LayoutOrder = index,
	}, fontRow)
	corner(button, 8)
	local chip = { key = item.key, button = button, stroke = stroke(button, THEME.line, 0.4, 1) }
	table.insert(fontChips, chip)
	button.MouseEnter:Connect(function()
		if selectedFont.key ~= chip.key then
			tween(button, 0.1, { BackgroundColor3 = THEME.line })
		end
	end)
	button.MouseLeave:Connect(function()
		if selectedFont.key ~= chip.key then
			tween(button, 0.1, { BackgroundColor3 = THEME.surface2 })
		end
	end)
	button.Activated:Connect(function()
		setFont(item.key)
	end)
end
setFont(selectedFont.key)

nameBox:GetPropertyChangedSignal("Text"):Connect(function()
	local text = nameBox.Text
	local length = utf8.len(text)
	if length and length > CONFIG.MaxNameLength then
		local cut = utf8.offset(text, CONFIG.MaxNameLength + 1)
		if cut then
			nameBox.Text = string.sub(text, 1, cut - 1)
			return
		end
	end
	counter.Text = string.format("%d/%d", length or 0, CONFIG.MaxNameLength)
	updatePreview()
end)

---------------------------------------------------------------------
-- Studio page: pro options for the next name
---------------------------------------------------------------------
local refreshStudio

do -- BLOCK studio
local studioCard = new("Frame", {
	Size = UDim2.fromOffset(588, 356),
	BackgroundColor3 = THEME.surface,
	BorderSizePixel = 0,
}, studioPage)
corner(studioCard, 12)
stroke(studioCard, THEME.line, 0.5, 1)

local studioGroups = {}

local function chipGroup(y, items, onPick)
	local row = new("Frame", {
		Position = UDim2.fromOffset(16, y),
		Size = UDim2.new(1, -32, 0, 30),
		BackgroundTransparency = 1,
	}, studioCard)
	new("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 8),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, row)

	local group = { chips = {} }
	group.isActive = function()
		return false
	end
	function group.refresh()
		for _, chip in ipairs(group.chips) do
			local active = group.isActive(chip.key)
			tween(chip.button, 0.14, { BackgroundColor3 = active and THEME.accent or THEME.surface2 })
			chip.button.TextColor3 = active and THEME.dark or THEME.text
			chip.stroke.Transparency = active and 1 or 0.4
		end
	end

	for index, item in ipairs(items) do
		local button = new("TextButton", {
			Text = item.title,
			Size = UDim2.fromOffset(126, 30),
			TextSize = 11,
			Font = Enum.Font.GothamBold,
			TextColor3 = THEME.text,
			BackgroundColor3 = THEME.surface2,
			AutoButtonColor = false,
			BorderSizePixel = 0,
			LayoutOrder = index,
		}, row)
		corner(button, 8)
		local chip = { key = item.key, button = button, stroke = stroke(button, THEME.line, 0.4, 1) }
		table.insert(group.chips, chip)
		button.MouseEnter:Connect(function()
			if not group.isActive(chip.key) then
				tween(button, 0.1, { BackgroundColor3 = THEME.line })
			end
		end)
		button.MouseLeave:Connect(function()
			if not group.isActive(chip.key) then
				tween(button, 0.1, { BackgroundColor3 = THEME.surface2 })
			end
		end)
		button.Activated:Connect(function()
			onPick(chip.key)
		end)
	end
	table.insert(studioGroups, group)
	return group
end

sectionTitle(studioCard, "SIZE", 12)
local sizeGroup = chipGroup(32, SIZES, function(key)
	studio.size = key
	refreshStudio()
end)
sizeGroup.isActive = function(key)
	return studio.size == key
end

sectionTitle(studioCard, "LETTER SPACING", 76)
local gapGroup = chipGroup(96, SPACINGS, function(key)
	studio.gap = key
	refreshStudio()
end)
gapGroup.isActive = function(key)
	return studio.gap == key
end

sectionTitle(studioCard, "SHAPE", 140)
local shapeGroup = chipGroup(160, SHAPES, function(key)
	studio.shape = key
	refreshStudio()
end)
shapeGroup.isActive = function(key)
	return studio.shape == key
end

sectionTitle(studioCard, "TEXT CASE", 204)
local caseGroup = chipGroup(224, CASES, function(key)
	studio.case = key
	refreshStudio()
	updatePreview()
end)
caseGroup.isActive = function(key)
	return studio.case == key
end

sectionTitle(studioCard, "EFFECTS (can be combined)", 268)
local fxGroup = chipGroup(288, EFFECTS, function(key)
	studio.fx[key] = not studio.fx[key]
	refreshStudio()
end)
fxGroup.isActive = function(key)
	return studio.fx[key] == true
end

textLabel(studioCard, "These options apply to the next name you create.", {
	Position = UDim2.fromOffset(16, 330),
	Size = UDim2.new(1, -32, 0, 14),
	TextSize = 10,
	TextColor3 = THEME.muted,
})

refreshStudio = function()
	for _, group in ipairs(studioGroups) do
		group.refresh()
	end
end
end -- BLOCK studio

---------------------------------------------------------------------
-- 3D engine (letters loaded from asset IDs)
---------------------------------------------------------------------
local templates = {}
local animated = {} -- dual color names: group -> { c1, c2, letters }
local packs = {} -- per font: { index = table or nil, failed = bool }

-- Removes invisible helper parts (they would break size and color of the letter)
local function stripInvisible(model)
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") and item.Transparency >= 0.95 then
			item:Destroy()
		end
	end
end

local function toModel(source)
	local copy = source:Clone()
	if not copy then
		return nil
	end
	for _, item in ipairs(copy:GetDescendants()) do
		if item:IsA("LuaSourceContainer") then
			item:Destroy()
		end
	end
	if copy:IsA("LuaSourceContainer") then
		copy:Destroy()
		return nil
	end
	if copy:IsA("Model") then
		copy.PrimaryPart = nil
		stripInvisible(copy)
		return copy
	end
	local container = Instance.new("Model")
	container.Name = source.Name
	if copy:IsA("BasePart") then
		copy.Parent = container
		return container
	end
	if copy:IsA("Folder") then
		for _, child in ipairs(copy:GetChildren()) do
			child.Parent = container
		end
		copy:Destroy()
		stripInvisible(container)
		return container
	end
	copy:Destroy()
	container:Destroy()
	return nil
end

local NUMBER_WORDS = {
	zero = "0", one = "1", two = "2", three = "3", four = "4",
	five = "5", six = "6", seven = "7", eight = "8", nine = "9",
}

-- "Meshes/C" -> "C", "Meshes/Five" -> "5", "A" -> "A", anything else -> nil
local function keyFromName(name)
	local tail = string.match(name, "([^/" .. utf8.char(92) .. "]+)$") or name
	tail = trim(tail)
	if #tail == 1 then
		return tail
	end
	local lower = string.lower(tail)
	if NUMBER_WORDS[lower] then
		return NUMBER_WORDS[lower]
	end
	local digit = string.match(lower, "^number(%d)$") or string.match(lower, "^num(%d)$")
	return digit
end

local function getPackIndex(font)
	local state = packs[font.key]
	if not state then
		state = {}
		packs[font.key] = state
	end
	if state.index then
		return state.index
	end
	if state.failed or not font.packId or font.packId == 0 then
		return nil
	end
	local root = loadObject(font.packId)
	if not root then
		state.failed = true
		return nil
	end
	-- Case-sensitive index: "a" and "A" are two different models in a pack
	local index = {}
	local function accept(child)
		return child:IsA("Model") or child:IsA("BasePart") or child:IsA("Folder")
	end
	local function scan(container)
		for _, child in ipairs(container:GetChildren()) do
			if accept(child) then
				local key = keyFromName(child.Name)
				if key and not index[key] then
					index[key] = child
				end
			end
		end
	end
	scan(root)
	if next(index) == nil then
		for _, item in ipairs(root:GetDescendants()) do
			if accept(item) then
				local key = keyFromName(item.Name)
				if key and not index[key] then
					index[key] = item
				end
			end
		end
	end
	if next(index) == nil then
		state.failed = true
		return nil
	end
	state.index = index
	return index
end

local function oppositeCase(character)
	local upper = string.upper(character)
	if upper ~= character then
		return upper
	end
	return string.lower(character)
end

local function getTemplate(font, character)
	local cacheKey = font.key .. "|" .. character
	local cached = templates[cacheKey]
	if cached then
		return cached
	end

	local source = nil
	local index = getPackIndex(font)
	if index then
		-- exact character first (a vs A), then the other case as a fallback
		source = index[character] or index[oppositeCase(character)]
	end
	local ids = font.letterIds or {}
	if not source then
		local id = ids[character] or ids[string.upper(character)] or ids[string.lower(character)]
		if id then
			source = loadObject(id)
		end
	end
	if not source then
		if (not font.packId or font.packId == 0) and next(ids) == nil then
			return nil, 'Font "' .. font.title .. '" has no asset id. Set packId in CONFIG.Fonts.'
		end
		return nil, 'Letter "' .. character .. '" is not available in ' .. font.title
	end

	local model = toModel(source)
	if not model then
		return nil, 'Could not read the model for "' .. character .. '"'
	end
	model.Name = character

	local pivot = model:GetPivot()
	model:PivotTo(CFrame.new(pivot.Position))
	if font.orient then
		model:PivotTo(
			CFrame.new(model:GetPivot().Position)
				* CFrame.Angles(math.rad(font.orient.X), math.rad(font.orient.Y), math.rad(font.orient.Z))
		)
	end

	local ok, boxCFrame, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok or size.X <= 0 or size.Y <= 0 then
		model:Destroy()
		return nil, 'The model for "' .. character .. '" has no 3D parts'
	end

	local template = {
		model = model,
		center = boxCFrame.Position,
		pivotPos = model:GetPivot().Position,
		width = size.X,
		height = size.Y,
	}
	templates[cacheKey] = template
	return template
end

local function paintModel(model, color, style)
	for _, item in ipairs(model:GetDescendants()) do
		if item:IsA("BasePart") then
			item.Anchored = true
			item.CanCollide = false
			item.CanTouch = false
			item.CanQuery = false
			item.CastShadow = true
			item.Color = color
			item.Material = style.material
			item.Reflectance = style.reflectance
			item.Transparency = style.transparency
			if item:IsA("PartOperation") then
				item.UsePartColor = true
			elseif item:IsA("MeshPart") then
				item.TextureID = ""
			end
		elseif item:IsA("SurfaceAppearance") then
			item:Destroy()
		end
	end
end

local function flat(vector)
	return Vector3.new(vector.X, 0, vector.Z)
end

-- Where the map starts (SpawnLocation). Studio Lite opens you around here.
local function findSpawnPosition()
	local spawn = nil
	pcall(function()
		spawn = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	end)
	if spawn then
		return spawn.Position
	end
	return Vector3.new(0, 0.5, 0)
end

-- Height for the next name: the spawn height, or just above any names already standing
-- at that spot, so names made in the same place never overlap.
local function nextHeight(center, skipEntry)
	local anchor = findSpawnPosition()
	local y = anchor.Y + CONFIG.HeightOffset
	for _, item in ipairs(names) do
		if item ~= skipEntry and type(item.center) == "table" then
			local c = Vector3.new(item.center[1], item.center[2], item.center[3])
			if flat(c - center).Magnitude <= CONFIG.StackRadius and c.Y < anchor.Y + 200 then
				y = math.max(y, c.Y + (item.h or 6) + 1.5)
			end
		end
	end
	return y
end

-- Where you are looking from: the editor camera (Studio Lite), else your character.
local function viewBasis()
	local camera = Workspace.CurrentCamera
	if camera then
		local cf = camera.CFrame
		local forward = flat(cf.LookVector)
		if forward.Magnitude < 0.3 then
			-- looking down: the top of the screen is "forward"
			local up = flat(cf.UpVector)
			if up.Magnitude > 0.05 then
				forward = up
			end
		end
		if forward.Magnitude < 0.05 then
			forward = Vector3.new(0, 0, -1)
		end
		return cf.Position, cf.LookVector, forward.Unit
	end
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root then
		local forward = flat(root.CFrame.LookVector)
		if forward.Magnitude < 0.05 then
			forward = Vector3.new(0, 0, -1)
		end
		return root.Position, root.CFrame.LookVector, forward.Unit
	end
	local anchor = findSpawnPosition()
	return anchor + Vector3.new(0, 10, 40), Vector3.new(0, 0, -1), Vector3.new(0, 0, -1)
end

-- In front of you, at the same height as before (spawn height, stacked), facing you.
local function getPlacement(skipEntry)
	local position, look, forward = viewBasis()
	local anchor = findSpawnPosition()
	local baseY = anchor.Y + CONFIG.HeightOffset

	-- the spot where your view meets the name height
	local point = nil
	if look.Y < -0.05 then
		local t = (baseY - position.Y) / look.Y
		if t > 12 and t <= CONFIG.MaxPlaceDistance then
			point = position + look * t
		end
	end
	if not point then
		point = position + forward * CONFIG.PlaceDistance
	end

	local flatPoint = Vector3.new(point.X, 0, point.Z)
	local center = Vector3.new(point.X, nextHeight(flatPoint, skipEntry), point.Z)

	local toward = -forward
	local rotation = CFrame.lookAt(Vector3.zero, toward).Rotation
	local right = forward:Cross(Vector3.yAxis)
	return center, rotation, right.Unit
end

local function storePlacement(entry, center, rotation, right)
	local comps = { rotation:GetComponents() }
	entry.center = { center.X, center.Y, center.Z }
	entry.rot = { table.unpack(comps, 4, 12) }
	entry.right = { right.X, right.Y, right.Z }
end

local function modelNameOf(entry)
	return "DZHUP_" .. entry.id
end

-- Script that is created INSIDE every animated name and saved with the project.
-- It reads the effect data stored on its own name (attributes) and plays the effects.
local EFFECT_SOURCE = [==[
-- DZ HUP | name effect (lives inside this name, saved with the project)
local RunService = game:GetService("RunService")
local model = script.Parent
if not model or not model:IsA("Model") then
	return
end

local c1 = model:GetAttribute("DZ_C1")
local c2 = model:GetAttribute("DZ_C2")
local useColors = model:GetAttribute("DZ_Colors") == true
local rainbow = model:GetAttribute("DZ_Rainbow") == true
local floating = model:GetAttribute("DZ_Float") == true
local amp = model:GetAttribute("DZ_Amp") or 0.35
local phase = model:GetAttribute("DZ_Phase") or 0
local base = model:GetAttribute("DZ_Base")
local speed = model:GetAttribute("DZ_Speed") or 0.35
local spread = model:GetAttribute("DZ_Spread") or 1

if typeof(c1) ~= "Color3" then
	c1 = Color3.new(1, 1, 1)
end
if typeof(c2) ~= "Color3" then
	c2 = nil
end
if typeof(base) ~= "CFrame" then
	base = model:GetPivot()
end

local letters = {}
if useColors then
	for _, letter in ipairs(model:GetChildren()) do
		local t = letter:GetAttribute("DZ_T")
		if type(t) == "number" then
			local parts = {}
			if letter:IsA("BasePart") then
				parts[#parts + 1] = letter
			end
			for _, item in ipairs(letter:GetDescendants()) do
				if item:IsA("BasePart") then
					parts[#parts + 1] = item
				end
			end
			letters[#letters + 1] = {
				t = t,
				parts = parts,
				light = letter:FindFirstChildWhichIsA("PointLight", true),
			}
		end
	end
end

local last = 0
RunService.Heartbeat:Connect(function()
	local now = os.clock()
	if now - last < 0.05 then
		return
	end
	last = now

	if useColors then
		for _, letter in ipairs(letters) do
			local blended = nil
			if rainbow then
				blended = Color3.fromHSV((letter.t * 0.8 - now * 0.12) % 1, 0.8, 1)
			elseif c2 then
				local wave = (math.sin((letter.t * spread - now * speed) * math.pi * 2) + 1) / 2
				blended = c1:Lerp(c2, wave)
			end
			if blended then
				for _, part in ipairs(letter.parts) do
					part.Color = blended
				end
				if letter.light then
					letter.light.Color = blended
				end
			end
		end
	end
	if floating then
		model:PivotTo(base + Vector3.new(0, math.sin(now * 1.4 + phase) * amp, 0))
	end
end)
]==]

local function buildName(entry)
	local font = fontOf(entry.font)
	local style = STYLE_DEFS[entry.style] or STYLE_DEFS.Plastic
	local color = Color3.fromRGB(entry.color[1], entry.color[2], entry.color[3])
	local color2 = nil
	if type(entry.color2) == "table" then
		color2 = Color3.fromRGB(entry.color2[1], entry.color2[2], entry.color2[3])
	end
	local scale = type(entry.size) == "number" and math.clamp(entry.size, 0.2, 6) or 1
	local gapMul = type(entry.gap) == "number" and math.clamp(entry.gap, 0, 6) or 1
	local shape = entry.shape or "Straight"
	local fx = type(entry.fx) == "table" and entry.fx or {}
	local colorAnim = color2 ~= nil or fx.rainbow == true

	local center = Vector3.new(entry.center[1], entry.center[2], entry.center[3])
	local rotation = CFrame.new(0, 0, 0, table.unpack(entry.rot))
	local normal = rotation.LookVector
	local right = Vector3.new(entry.right[1], entry.right[2], entry.right[3])
	local frontNegZ = font.frontNegZ
	if frontNegZ == nil then
		frontNegZ = CONFIG.FrontFaceIsNegativeZ
	end
	if not frontNegZ then
		rotation = rotation * CFrame.Angles(0, math.pi, 0)
	end

	local pieces = {}
	local letterCount, widthSum, maxHeight = 0, 0, 1
	for _, codepoint in utf8.codes(entry.name) do
		local character = utf8.char(codepoint)
		if string.match(character, "^%s$") then
			table.insert(pieces, { space = true })
		else
			local template, templateError = getTemplate(font, character)
			if not template then
				return nil, templateError
			end
			table.insert(pieces, { template = template })
			letterCount += 1
			widthSum += template.width * scale
			maxHeight = math.max(maxHeight, template.height * scale)
		end
	end

	local gap = CONFIG.LetterGap * gapMul * scale
	local spaceWidth = letterCount > 0 and (widthSum / letterCount) * CONFIG.SpaceWidthRatio or 1
	local totalWidth = -gap
	for _, piece in ipairs(pieces) do
		piece.width = piece.template and piece.template.width * scale or spaceWidth
		totalWidth += piece.width + gap
	end

	-- shape: returns sideways offset, height offset and tilt (radians) for a letter at xc
	local arcAngle = math.min(math.rad(110), totalWidth / (maxHeight * 3))
	local radius = arcAngle > 0.01 and totalWidth / arcAngle or nil
	local function shapeAt(xc)
		if (shape == "ArcUp" or shape == "ArcDown") and radius then
			local phi = xc / radius
			local sign = shape == "ArcUp" and 1 or -1
			return radius * math.sin(phi), sign * (radius * math.cos(phi) - radius), -sign * phi
		elseif shape == "Wave" then
			local amp = maxHeight * 0.28
			local k = (math.pi * 2 * 1.5) / math.max(totalWidth, 0.01)
			return xc, amp * math.sin(k * xc), math.atan(amp * k * math.cos(k * xc))
		end
		return xc, 0, 0
	end

	local group = Instance.new("Model")
	group.Name = modelNameOf(entry)

	local cursor = -totalWidth / 2
	local firstPart = nil
	local waveLetters = {}
	for _, piece in ipairs(pieces) do
		local template = piece.template
		if template then
			local letter = template.model:Clone()
			local appliedScale = 1
			if scale ~= 1 then
				if pcall(function()
					letter:ScaleTo(scale)
				end) then
					appliedScale = scale
				end
			end
			paintModel(letter, color, style)

			local xc = cursor + piece.width / 2
			local dx, dy, roll = shapeAt(xc)
			local rollCF = CFrame.fromAxisAngle(normal, roll)
			local up = rollCF:VectorToWorldSpace(Vector3.yAxis)
			local scaledCenter = template.pivotPos + (template.center - template.pivotPos) * appliedScale
			local target = center + right * dx + Vector3.yAxis * dy + up * (template.height * appliedScale / 2)
			local placement = CFrame.new(target) * rollCF * rotation * CFrame.new(-scaledCenter)
			letter:PivotTo(placement * letter:GetPivot())

			letter.Name = template.model.Name
			letter.Parent = group

			local light = nil
			if fx.glow then
				local anchorPart = letter:FindFirstChildWhichIsA("BasePart", true)
				if anchorPart then
					light = Instance.new("PointLight")
					light.Color = color
					light.Brightness = 2
					light.Range = math.clamp(10 * scale, 6, 30)
					light.Shadows = false
					light.Parent = anchorPart
				end
			end

			if colorAnim then
				local parts = {}
				for _, item in ipairs(letter:GetDescendants()) do
					if item:IsA("BasePart") then
						table.insert(parts, item)
					end
				end
				local t = totalWidth > 0 and (xc + totalWidth / 2) / totalWidth or 0
				pcall(function()
					letter:SetAttribute("DZ_T", t)
				end)
				table.insert(waveLetters, { parts = parts, t = t, light = light })
			end
			firstPart = firstPart or letter:FindFirstChildWhichIsA("BasePart", true)
		end
		cursor += piece.width + gap
	end

	if not firstPart then
		group:Destroy()
		return nil, "No letters could be created"
	end

	if entry.style == "Modern" then
		local highlight = Instance.new("Highlight")
		highlight.Name = "ModernEdge"
		highlight.Adornee = group
		highlight.FillTransparency = 1
		highlight.OutlineColor = color
		highlight.OutlineTransparency = 0.2
		highlight.DepthMode = Enum.HighlightDepthMode.Occluded
		highlight.Parent = group
	end

	group.PrimaryPart = firstPart
	group.Parent = namesFolder
	pcall(function()
		local _, size = group:GetBoundingBox()
		entry.h = size.Y
	end)
	if colorAnim or fx.float then
		local fxBase = group:GetPivot()
		local fxAmp = 0.35 * math.max(scale, 0.6)
		local fxPhase = math.random() * math.pi * 2
		-- Effect data is written on the model itself (attributes are saved with the project),
		-- so the Effects script can bring the animation back after saving and reopening.
		pcall(function()
			group:SetAttribute("DZ_FX", true)
			group:SetAttribute("DZ_C1", color)
			if color2 then
				group:SetAttribute("DZ_C2", color2)
			end
			group:SetAttribute("DZ_Colors", colorAnim)
			group:SetAttribute("DZ_Rainbow", fx.rainbow == true)
			group:SetAttribute("DZ_Float", fx.float == true)
			group:SetAttribute("DZ_Amp", fxAmp)
			group:SetAttribute("DZ_Phase", fxPhase)
			group:SetAttribute("DZ_Base", fxBase)
			group:SetAttribute("DZ_Speed", CONFIG.WaveSpeed)
			group:SetAttribute("DZ_Spread", CONFIG.WaveSpread)
		end)
		-- the effect script itself, stored inside the name
		local scriptOk, scriptError = pcall(function()
			local fxScript = Instance.new("Script")
			fxScript.Name = "DZHUP_Effect"
			fxScript.Source = EFFECT_SOURCE
			fxScript.Parent = group
		end)
		if not scriptOk and not genv.DZHUP_SourceWarned then
			genv.DZHUP_SourceWarned = true
			warn("[DZHUP] Could not put the effect script inside the name: " .. tostring(scriptError))
		end
		animated[group] = {
			c1 = color,
			c2 = color2,
			rainbow = fx.rainbow == true,
			letters = colorAnim and waveLetters or nil,
			float = fx.float == true,
			base = fxBase,
			amp = fxAmp,
			phase = fxPhase,
		}
	end
	return group
end

---------------------------------------------------------------------
-- Animations: flowing dual color, rainbow and floating names
---------------------------------------------------------------------
do -- BLOCK heartbeat
local lastWave = 0
on(RunService.Heartbeat, function()
	local now = os.clock()
	if now - lastWave < 0.033 then
		return
	end
	lastWave = now
	for group, info in pairs(animated) do
		if not group.Parent then
			animated[group] = nil
		else
			if info.letters then
				for _, letter in ipairs(info.letters) do
					local blended
					if info.rainbow then
						blended = Color3.fromHSV((letter.t * 0.8 - now * 0.12) % 1, 0.8, 1)
					else
						local wave = (math.sin((letter.t * CONFIG.WaveSpread - now * CONFIG.WaveSpeed) * math.pi * 2) + 1) / 2
						blended = info.c1:Lerp(info.c2, wave)
					end
					for _, part in ipairs(letter.parts) do
						part.Color = blended
					end
					if letter.light then
						letter.light.Color = blended
					end
				end
			end
			if info.float then
				group:PivotTo(info.base + Vector3.new(0, math.sin(now * 1.4 + info.phase) * info.amp, 0))
			end
		end
	end
end)
end -- BLOCK heartbeat

---------------------------------------------------------------------
-- My Names page
---------------------------------------------------------------------
local renderList

do -- BLOCK mynames
textLabel(listPage, "Saved names", {
	Position = UDim2.fromOffset(4, 0),
	Size = UDim2.new(1, -8, 0, 22),
	Font = Enum.Font.GothamBold,
	TextSize = 14,
})
local listCount = textLabel(listPage, "", {
	Position = UDim2.fromOffset(4, 0),
	Size = UDim2.new(1, -8, 0, 22),
	TextSize = 12,
	TextColor3 = THEME.muted,
	TextXAlignment = Enum.TextXAlignment.Right,
})

local listFrame = new("ScrollingFrame", {
	Position = UDim2.fromOffset(0, 28),
	Size = UDim2.new(1, 0, 1, -28),
	BackgroundColor3 = THEME.surface,
	BorderSizePixel = 0,
	ScrollBarThickness = 3,
	ScrollBarImageColor3 = THEME.muted,
	CanvasSize = UDim2.new(),
	AutomaticCanvasSize = Enum.AutomaticSize.Y,
	ScrollingDirection = Enum.ScrollingDirection.Y,
}, listPage)
corner(listFrame, 12)
stroke(listFrame, THEME.line, 0.5, 1)
new("UIPadding", {
	PaddingTop = UDim.new(0, 8),
	PaddingBottom = UDim.new(0, 8),
	PaddingLeft = UDim.new(0, 8),
	PaddingRight = UDim.new(0, 10),
}, listFrame)
new("UIListLayout", { Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }, listFrame)

local emptyState = textLabel(listPage, "No saved names yet" .. utf8.char(10) .. "Create your first one from the Create tab", {
	Position = UDim2.fromOffset(0, 28),
	Size = UDim2.new(1, 0, 1, -28),
	TextSize = 13,
	TextColor3 = THEME.muted,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Center,
})

local function moveEntry(entry)
	task.spawn(function()
		local old = namesFolder:FindFirstChild(modelNameOf(entry))
		if old then
			old:Destroy()
		end
		local center, rotation, right = getPlacement(entry)
		storePlacement(entry, center, rotation, right)
		local ok, group, err = pcall(buildName, entry)
		persist()
		if ok and group then
			showToast("Moved in front of you", true)
		else
			showToast(tostring(ok and err or group or "Could not move the name"), false)
		end
	end)
end

local function deleteEntry(entry)
	local old = namesFolder:FindFirstChild(modelNameOf(entry))
	if old then
		old:Destroy()
	end
	for i, item in ipairs(names) do
		if item == entry then
			table.remove(names, i)
			break
		end
	end
	persist()
	renderList()
	showToast("Name deleted", true)
end

function renderList()
	for _, child in ipairs(listFrame:GetChildren()) do
		if child:IsA("GuiObject") then
			child:Destroy()
		end
	end

	local sorted = table.clone(names)
	table.sort(sorted, function(a, b)
		return (a.order or 0) > (b.order or 0)
	end)

	tabButtons[3].Text = string.format("My Names (%d)", #sorted)
	listCount.Text = string.format("%d / %d", #sorted, CONFIG.MaxNames)
	emptyState.Visible = #sorted == 0
	listFrame.Visible = #sorted > 0

	for index, entry in ipairs(sorted) do
		local row = new("Frame", {
			Size = UDim2.new(1, 0, 0, 62),
			BackgroundColor3 = THEME.surface2,
			BorderSizePixel = 0,
			LayoutOrder = index,
		}, listFrame)
		corner(row, 10)
		stroke(row, THEME.line, 0.7, 1)

		local dot = new("Frame", {
			AnchorPoint = Vector2.new(0, 0.5),
			Position = UDim2.new(0, 14, 0.5, 0),
			Size = UDim2.fromOffset(32, 32),
			BackgroundColor3 = Color3.fromRGB(entry.color[1], entry.color[2], entry.color[3]),
			BorderSizePixel = 0,
		}, row)
		corner(dot, 9)
		stroke(dot, THEME.text, 0.7, 1)
		if type(entry.color2) == "table" then
			dot.BackgroundColor3 = Color3.new(1, 1, 1)
			new("UIGradient", {
				Color = ColorSequence.new(
					Color3.fromRGB(entry.color[1], entry.color[2], entry.color[3]),
					Color3.fromRGB(entry.color2[1], entry.color2[2], entry.color2[3])
				),
				Rotation = 45,
			}, dot)
		end

		textLabel(row, tostring(entry.name), {
			Position = UDim2.fromOffset(60, 10),
			Size = UDim2.new(1, -230, 0, 24),
			Font = Enum.Font.GothamBold,
			TextSize = 17,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local details = fontOf(entry.font).title .. "  |  " .. (STYLE_TITLES[entry.style] or "Plastic")
		if entry.shape and SHAPE_TITLES[entry.shape] then
			details = details .. "  |  " .. SHAPE_TITLES[entry.shape]
		end
		if type(entry.fx) == "table" then
			for _, item in ipairs(EFFECTS) do
				if entry.fx[item.key] then
					details = details .. "  |  " .. FX_TITLES[item.key]
				end
			end
		end
		textLabel(row, details, {
			Position = UDim2.fromOffset(60, 35),
			Size = UDim2.new(1, -230, 0, 16),
			TextSize = 11,
			TextColor3 = THEME.muted,
		})

		local deleteButton = makeButton(row, {
			Text = "Delete",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -10, 0.5, 0),
			Size = UDim2.fromOffset(72, 32),
			TextSize = 12,
			TextColor3 = THEME.danger,
		}, { fill = THEME.surface, stroke = THEME.danger, strokeTransparency = 0.6, radius = 8 })

		local moveButton = makeButton(row, {
			Text = "Move here",
			AnchorPoint = Vector2.new(1, 0.5),
			Position = UDim2.new(1, -90, 0.5, 0),
			Size = UDim2.fromOffset(82, 32),
			TextSize = 12,
			TextColor3 = THEME.accent,
		}, { fill = THEME.surface, stroke = THEME.accent, strokeTransparency = 0.6, radius = 8 })
		moveButton.Activated:Connect(function()
			moveEntry(entry)
		end)

		local armed = false
		deleteButton.Activated:Connect(function()
			if not armed then
				armed = true
				deleteButton.Text = "Confirm?"
				deleteButton.TextColor3 = THEME.text
				tween(deleteButton, 0.12, { BackgroundColor3 = THEME.danger })
				task.delay(2.5, function()
					if armed and deleteButton.Parent then
						armed = false
						deleteButton.Text = "Delete"
						deleteButton.TextColor3 = THEME.danger
						tween(deleteButton, 0.12, { BackgroundColor3 = THEME.surface })
					end
				end)
				return
			end
			deleteEntry(entry)
		end)
	end
end

local clearButton = makeButton(listPage, {
	Text = "Clear all",
	AnchorPoint = Vector2.new(1, 0),
	Position = UDim2.new(1, -62, 0, 0),
	Size = UDim2.fromOffset(74, 22),
	TextSize = 11,
	TextColor3 = THEME.danger,
}, { fill = THEME.surface, stroke = THEME.danger, strokeTransparency = 0.6, radius = 7 })
local clearArmed = false
clearButton.Activated:Connect(function()
	if #names == 0 then
		showToast("Nothing to clear", false)
		return
	end
	if not clearArmed then
		clearArmed = true
		clearButton.Text = "Confirm?"
		clearButton.TextColor3 = THEME.text
		tween(clearButton, 0.12, { BackgroundColor3 = THEME.danger })
		task.delay(2.5, function()
			if clearArmed and clearButton.Parent then
				clearArmed = false
				clearButton.Text = "Clear all"
				clearButton.TextColor3 = THEME.danger
				tween(clearButton, 0.12, { BackgroundColor3 = THEME.surface })
			end
		end)
		return
	end
	clearArmed = false
	clearButton.Text = "Clear all"
	clearButton.TextColor3 = THEME.danger
	tween(clearButton, 0.12, { BackgroundColor3 = THEME.surface })
	for _, item in ipairs(names) do
		local old = namesFolder:FindFirstChild(modelNameOf(item))
		if old then
			old:Destroy()
		end
	end
	table.clear(names)
	persist()
	renderList()
	showToast("All names deleted", true)
end)
end -- BLOCK mynames

---------------------------------------------------------------------
-- Creator page
---------------------------------------------------------------------
do -- BLOCK creator
local aboutLeft = new("Frame", {
	Size = UDim2.fromOffset(240, 300),
	BackgroundColor3 = THEME.surface,
	BorderSizePixel = 0,
}, aboutPage)
corner(aboutLeft, 12)
stroke(aboutLeft, THEME.line, 0.5, 1)

local avatarHolder = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 30),
	Size = UDim2.fromOffset(116, 116),
	BackgroundTransparency = 1,
}, aboutLeft)

local avatarGlow = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.fromOffset(134, 134),
	BackgroundColor3 = THEME.accent,
	BackgroundTransparency = 0.86,
	BorderSizePixel = 0,
}, avatarHolder)
corner(avatarGlow, 100)
loop(avatarGlow, 1.4, { BackgroundTransparency = 0.62, Size = UDim2.fromOffset(150, 150) })

local avatarRing = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.surface2,
	BorderSizePixel = 0,
}, avatarHolder)
corner(avatarRing, 100)
local ringStroke = stroke(avatarRing, Color3.new(1, 1, 1), 0, 3)
local ringGradient = new("UIGradient", {
	Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, THEME.accentSoft),
		ColorSequenceKeypoint.new(0.5, THEME.accent),
		ColorSequenceKeypoint.new(1, THEME.accentSoft),
	}),
	Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.55, 0.85),
		NumberSequenceKeypoint.new(1, 0),
	}),
}, ringStroke)
loop(ringGradient, 3, { Rotation = 360 }, Enum.EasingStyle.Linear, false)

local avatarInner = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0.5),
	Position = UDim2.fromScale(0.5, 0.5),
	Size = UDim2.new(1, -12, 1, -12),
	BackgroundColor3 = THEME.header,
	BorderSizePixel = 0,
	ClipsDescendants = true,
}, avatarRing)
corner(avatarInner, 100)
local avatarLetter = textLabel(avatarInner, "R", {
	Size = UDim2.fromScale(1, 1),
	Font = Enum.Font.GothamBlack,
	TextSize = 44,
	TextColor3 = THEME.accent,
	TextXAlignment = Enum.TextXAlignment.Center,
})
local avatarImage = new("ImageLabel", {
	Size = UDim2.fromScale(1, 1),
	BackgroundTransparency = 1,
	ScaleType = Enum.ScaleType.Crop,
	Image = "",
	Visible = false,
}, avatarInner)
corner(avatarImage, 100)

textLabel(aboutLeft, CONFIG.Creator, {
	Position = UDim2.fromOffset(0, 164),
	Size = UDim2.new(1, 0, 0, 26),
	Font = Enum.Font.GothamBlack,
	TextSize = 21,
	TextXAlignment = Enum.TextXAlignment.Center,
})
textLabel(aboutLeft, "Creator of this system", {
	Position = UDim2.fromOffset(0, 192),
	Size = UDim2.new(1, 0, 0, 16),
	TextSize = 12,
	TextColor3 = THEME.muted,
	TextXAlignment = Enum.TextXAlignment.Center,
})
local communityPill = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0),
	Position = UDim2.new(0.5, 0, 0, 224),
	Size = UDim2.fromOffset(120, 28),
	BackgroundColor3 = THEME.surface2,
	BorderSizePixel = 0,
}, aboutLeft)
corner(communityPill, 14)
stroke(communityPill, THEME.accent, 0.55, 1)
textLabel(communityPill, CONFIG.Community, {
	Size = UDim2.fromScale(1, 1),
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextColor3 = THEME.accent,
	TextXAlignment = Enum.TextXAlignment.Center,
})

local aboutRight = new("Frame", {
	Position = UDim2.fromOffset(252, 0),
	Size = UDim2.fromOffset(336, 300),
	BackgroundColor3 = THEME.surface,
	BorderSizePixel = 0,
}, aboutPage)
corner(aboutRight, 12)
stroke(aboutRight, THEME.line, 0.5, 1)

textLabel(aboutRight, "CONNECT WITH ME", {
	Position = UDim2.fromOffset(16, 14),
	Size = UDim2.new(1, -32, 0, 16),
	Font = Enum.Font.GothamBold,
	TextSize = 12,
	TextColor3 = THEME.muted,
})

local function copyLink(link, doneMessage)
	if copyText(link) then
		showToast(doneMessage, true)
	else
		showToast("Clipboard is not supported. " .. link, false)
	end
end

local function contactCard(y, letter, color, title, sub, link, doneMessage)
	local button = makeButton(aboutRight, {
		Text = "",
		Position = UDim2.fromOffset(16, y),
		Size = UDim2.fromOffset(304, 68),
	}, { fill = THEME.surface2, stroke = color, strokeTransparency = 0.6, radius = 12 })

	local icon = new("Frame", {
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0, 14, 0.5, 0),
		Size = UDim2.fromOffset(42, 42),
		BackgroundColor3 = color,
		BorderSizePixel = 0,
	}, button)
	corner(icon, 11)
	textLabel(icon, letter, {
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.GothamBlack,
		TextSize = 18,
		TextColor3 = Color3.new(1, 1, 1),
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	textLabel(button, title, {
		Position = UDim2.fromOffset(68, 14),
		Size = UDim2.new(1, -150, 0, 20),
		Font = Enum.Font.GothamBold,
		TextSize = 15,
	})
	textLabel(button, sub, {
		Position = UDim2.fromOffset(68, 36),
		Size = UDim2.new(1, -150, 0, 16),
		TextSize = 11,
		TextColor3 = THEME.muted,
	})
	local chip = new("Frame", {
		AnchorPoint = Vector2.new(1, 0.5),
		Position = UDim2.new(1, -12, 0.5, 0),
		Size = UDim2.fromOffset(60, 26),
		BackgroundColor3 = color,
		BackgroundTransparency = 0.75,
		BorderSizePixel = 0,
	}, button)
	corner(chip, 8)
	textLabel(chip, "COPY", {
		Size = UDim2.fromScale(1, 1),
		Font = Enum.Font.GothamBold,
		TextSize = 11,
		TextXAlignment = Enum.TextXAlignment.Center,
	})
	button.Activated:Connect(function()
		copyLink(link, doneMessage)
	end)
end

contactCard(38, "D", THEME.discord, "Discord", "Join the community server", CONFIG.Discord, "Discord link copied")
contactCard(108, "W", THEME.whatsapp, "WhatsApp", "Follow the channel", CONFIG.WhatsApp, "WhatsApp link copied")
contactCard(178, "T", THEME.tiktok, "TikTok", "Follow my account", CONFIG.TikTok, "TikTok link copied")

textLabel(aboutRight, "Tap a card to copy its link, then paste it in your browser.", {
	Position = UDim2.fromOffset(16, 250),
	Size = UDim2.new(1, -32, 0, 22),
	TextSize = 10,
	TextColor3 = THEME.muted,
	TextWrapped = true,
})
textLabel(aboutRight, "Made by " .. CONFIG.Creator .. "  |  " .. CONFIG.Community, {
	AnchorPoint = Vector2.new(0, 1),
	Position = UDim2.new(0, 16, 1, -12),
	Size = UDim2.new(1, -32, 0, 16),
	Font = Enum.Font.GothamBold,
	TextSize = 11,
	TextColor3 = THEME.accent,
})

-- Resolve the avatar picture without blocking the UI
task.spawn(function()
	local image = nil
	if CONFIG.AvatarImageUrl ~= "" and hasFS and type(getcustomasset) == "function" then
		local ok, result = pcall(function()
			local data = game:HttpGet(CONFIG.AvatarImageUrl)
			writefile("DZHUP_avatar.png", data)
			return getcustomasset("DZHUP_avatar.png")
		end)
		if ok and result then
			image = result
		end
	end
	if not image then
		local userId = CONFIG.AvatarRobloxUserId
		if (not userId or userId <= 0) and CONFIG.RobloxUsername and CONFIG.RobloxUsername ~= "" then
			local ok, id = pcall(function()
				return Players:GetUserIdFromNameAsync(CONFIG.RobloxUsername)
			end)
			if ok and type(id) == "number" then
				userId = id
			end
		end
		if userId and userId > 0 then
			local ok, thumb, ready = pcall(function()
				return Players:GetUserThumbnailAsync(
					userId,
					Enum.ThumbnailType.HeadShot,
					Enum.ThumbnailSize.Size150x150
				)
			end)
			if ok and thumb and thumb ~= "" and ready ~= false then
				image = thumb
			else
				image = string.format("rbxthumb://type=AvatarHeadShot&id=%d&w=150&h=150", userId)
			end
		end
	end
	if image then
		avatarImage.Image = image
		avatarImage.Visible = true
		avatarLetter.Visible = false
	end
end)
end -- BLOCK creator

---------------------------------------------------------------------
-- Tab switching
---------------------------------------------------------------------
local currentTab = 1
local function switchTab(index, instant)
	currentTab = index
	for i, page in ipairs(pages) do
		page.Visible = i == index
		tabButtons[i].TextColor3 = i == index and THEME.dark or THEME.muted
	end
	local target = UDim2.new((index - 1) / TAB_COUNT, 4, 0, 4)
	if instant then
		tabIndicator.Position = target
	else
		tween(tabIndicator, 0.3, { Position = target }, Enum.EasingStyle.Quint)
	end
	if index == 3 then
		renderList()
	end
end
for i, button in ipairs(tabButtons) do
	button.Activated:Connect(function()
		switchTab(i)
	end)
end

---------------------------------------------------------------------
-- Resize handle + Drag and resize
---------------------------------------------------------------------
do -- BLOCK dragresize
local resizeHandle = new("TextButton", {
	Name = "ResizeHandle",
	AnchorPoint = Vector2.new(1, 1),
	Position = UDim2.new(1, 0, 1, 0),
	Size = UDim2.fromOffset(38, 38),
	BackgroundTransparency = 1,
	Text = "",
	AutoButtonColor = false,
	Active = true,
	ZIndex = 20,
}, panel)

local gripDots = {}
for row = 0, 2 do
	for col = 0, 2 - row do
		local dot = new("Frame", {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.new(1, -(9 + col * 6), 1, -(9 + row * 6)),
			Size = UDim2.fromOffset(3, 3),
			BackgroundColor3 = THEME.muted,
			BorderSizePixel = 0,
			ZIndex = 21,
		}, resizeHandle)
		corner(dot, 2)
		table.insert(gripDots, dot)
	end
end
local function tintGrip(color)
	for _, dot in ipairs(gripDots) do
		tween(dot, 0.12, { BackgroundColor3 = color })
	end
end
resizeHandle.MouseEnter:Connect(function()
	tintGrip(THEME.accent)
end)
resizeHandle.MouseLeave:Connect(function()
	tintGrip(THEME.muted)
end)

local function isPointer(input)
	return input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
end
local function pointOf(input)
	return Vector2.new(input.Position.X, input.Position.Y)
end

local dragging, resizing = false, false
local dragStart, startOffset = Vector2.zero, Vector2.zero
local resizeStart, startScale = Vector2.zero, 1

header.InputBegan:Connect(function(input)
	if isPointer(input) and not resizing then
		dragging = true
		dragStart = pointOf(input)
		startOffset = Vector2.new(holder.Position.X.Offset, holder.Position.Y.Offset)
	end
end)

resizeHandle.InputBegan:Connect(function(input)
	if isPointer(input) and not dragging then
		resizing = true
		resizeStart = pointOf(input)
		startScale = scaler.Scale
		tintGrip(THEME.accent)
		tween(panelStroke, 0.12, { Color = THEME.accent, Transparency = 0.2 })
	end
end)

on(UserInputService.InputChanged, function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseMovement and input.UserInputType ~= Enum.UserInputType.Touch then
		return
	end
	if dragging then
		local delta = pointOf(input) - dragStart
		holder.Position = UDim2.fromOffset(startOffset.X + delta.X, startOffset.Y + delta.Y)
		clampHolder()
	elseif resizing then
		local delta = pointOf(input) - resizeStart
		local x, y = holder.Position.X.Offset, holder.Position.Y.Offset
		local target = startScale + (delta.X / PANEL_W + delta.Y / PANEL_H) / 2
		scaler.Scale = math.clamp(target, MIN_SCALE, maxScaleFor(x, y))
	end
end)

on(UserInputService.InputEnded, function(input)
	if not isPointer(input) then
		return
	end
	if resizing then
		resizing = false
		tintGrip(THEME.muted)
		tween(panelStroke, 0.25, { Color = THEME.line, Transparency = 0.2 })
	end
	dragging = false
end)
end -- BLOCK dragresize

---------------------------------------------------------------------
-- Open / close animation
---------------------------------------------------------------------
do -- BLOCK openclose
local veil = new("Frame", {
	Name = "Veil",
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = THEME.bg,
	BackgroundTransparency = 1,
	BorderSizePixel = 0,
	ZIndex = 40,
	Visible = false,
}, panel)
corner(veil, 16)

local isOpen = false
local openToken = 0

-- RX icon: slides away when the window opens, pops back with a ripple when it closes
local function hideOpenButton(token)
	tween(openButtonScale, 0.28, { Scale = 0 }, Enum.EasingStyle.Back, Enum.EasingDirection.In)
	tween(openButton, 0.28, { Rotation = 120, BackgroundTransparency = 1, TextTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(openStroke, 0.25, { Transparency = 1 })
	task.delay(0.3, function()
		if token == openToken and isOpen then
			openButton.Visible = false
		end
	end)
end

local function showOpenButton(token)
	openButton.Visible = true
	openButtonScale.Scale = 0
	openButton.Rotation = -180
	openButton.BackgroundTransparency = 1
	openButton.TextTransparency = 1
	openStroke.Transparency = 1

	task.delay(0.22, function()
		if token ~= openToken or isOpen then
			return
		end
		tween(openButtonScale, 0.6, { Scale = 1 }, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
		tween(openButton, 0.6, { Rotation = 0 }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
		tween(openButton, 0.4, { BackgroundTransparency = 0.5, TextTransparency = 0.1 }, Enum.EasingStyle.Sine)
		tween(openStroke, 0.5, { Transparency = 0.45 }, Enum.EasingStyle.Sine)

		-- ripple ring that expands from the icon
		local ring = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0, 34, 0.5, 0),
			Size = UDim2.fromOffset(44, 44),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
		}, gui)
		corner(ring, 100)
		local ringLine = stroke(ring, THEME.accent, 0.1, 2.5)
		tween(ring, 0.8, { Size = UDim2.fromOffset(120, 120) }, Enum.EasingStyle.Quint)
		tween(ringLine, 0.8, { Transparency = 1, Thickness = 0.5 }, Enum.EasingStyle.Quad)
		task.delay(0.85, function()
			ring:Destroy()
		end)

		-- small glow pulse on the icon after it lands
		task.delay(0.45, function()
			if token ~= openToken or isOpen then
				return
			end
			tween(openButtonScale, 0.14, { Scale = 1.12 }, Enum.EasingStyle.Sine)
			task.delay(0.14, function()
				if token == openToken and not isOpen then
					tween(openButtonScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
				end
			end)
		end)
	end)
end

local function setOpen(open)
	if isOpen == open then
		return
	end
	isOpen = open
	openToken += 1
	local token = openToken

	if open then
		hideOpenButton(token)

		if not placed then
			placeInitially()
		else
			scaler.Scale = math.min(scaler.Scale, maxScaleFor(0, 0))
			clampHolder()
		end

		holder.Visible = true
		backdrop.Visible = true
		veil.Visible = true
		veil.BackgroundTransparency = 0
		panel.Position = UDim2.new(0.5, 0, 0.5, 30)
		popScale.Scale = 0.9
		tabTrack.Position = UDim2.fromOffset(16, TAB_Y + 14)
		content.Position = UDim2.fromOffset(16, CONTENT_Y + 22)
		sweep.Size = UDim2.new(0, 0, 0, 1)
		sweep.BackgroundTransparency = 0
		panelStroke.Color = THEME.accent
		panelStroke.Transparency = 0

		tween(backdrop, 0.4, { BackgroundTransparency = 0.62 })
		tween(veil, 0.45, { BackgroundTransparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0.05)
		tween(panel, 0.6, { Position = UDim2.new(0.5, 0, 0.5, 0) }, Enum.EasingStyle.Quint)
		tween(popScale, 0.6, { Scale = 1 }, Enum.EasingStyle.Quint)
		tween(panelStroke, 0.9, { Color = THEME.line, Transparency = 0.2 }, Enum.EasingStyle.Sine)
		tween(sweep, 0.7, { Size = UDim2.new(1, 0, 0, 1) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0.08)
		tween(sweep, 0.5, { BackgroundTransparency = 0.6 }, Enum.EasingStyle.Sine, Enum.EasingDirection.Out, 0.6)
		tween(tabTrack, 0.5, { Position = UDim2.fromOffset(16, TAB_Y) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0.1)
		tween(content, 0.55, { Position = UDim2.fromOffset(16, CONTENT_Y) }, Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0.18)

		task.delay(0.55, function()
			if token == openToken and isOpen then
				veil.Visible = false
			end
		end)
	else
		veil.Visible = true
		showOpenButton(token)
		tween(backdrop, 0.22, { BackgroundTransparency = 1 })
		tween(veil, 0.2, { BackgroundTransparency = 0 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(panel, 0.24, { Position = UDim2.new(0.5, 0, 0.5, 14) }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)
		tween(popScale, 0.24, { Scale = 0.95 }, Enum.EasingStyle.Quint, Enum.EasingDirection.In)

		task.delay(0.26, function()
			if token == openToken and not isOpen then
				holder.Visible = false
				backdrop.Visible = false
				veil.Visible = false
			end
		end)
	end
end

openButton.Activated:Connect(function()
	setOpen(not isOpen)
end)
closeButton.Activated:Connect(function()
	setOpen(false)
end)
on(UserInputService.InputBegan, function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == CONFIG.ToggleKey then
		setOpen(not isOpen)
	end
end)
end -- BLOCK openclose

---------------------------------------------------------------------
-- Create a name
---------------------------------------------------------------------
local busy = false

local function setBusy(state)
	busy = state
	createButton.Text = state and "BUILDING LETTERS..." or "CREATE 3D NAME"
	createButton.TextTransparency = state and 0.35 or 0
end

local function cleanName(value)
	local name = string.gsub(value, "%c", "")
	name = trim(name)
	name = string.gsub(name, "%s+", " ")
	local count = utf8.len(name)
	if name == "" or not count or count > CONFIG.MaxNameLength then
		return nil
	end
	return name
end

local function rememberSettings()
	save.settings.last = {
		color = selectedColorIndex,
		color2 = selectedColor2Index,
		dual = dualOn,
		style = selectedStyle,
		font = selectedFont.key,
		size = studio.size,
		gap = studio.gap,
		shape = studio.shape,
		case = studio.case,
		fx = {
			glow = studio.fx.glow,
			float = studio.fx.float,
			rainbow = studio.fx.rainbow,
		},
	}
end

local function submit()
	if busy then
		return
	end
	local name = cleanName(nameBox.Text)
	if not name then
		showToast("Type a name (1 to " .. CONFIG.MaxNameLength .. " characters)", false)
		return
	end
	if #names >= CONFIG.MaxNames then
		showToast("Name limit reached. Delete one first.", false)
		return
	end

	name = applyCase(name)
	local color = selectedColor()
	local order = 0
	for _, item in ipairs(names) do
		order = math.max(order, item.order or 0)
	end

	local entry = {
		id = string.sub(string.gsub(HttpService:GenerateGUID(false), "-", ""), 1, 12),
		order = order + 1,
		name = name,
		style = selectedStyle,
		font = selectedFont.key,
		size = SIZE_VALUES[studio.size],
		gap = SPACING_VALUES[studio.gap],
		shape = studio.shape ~= "Straight" and studio.shape or nil,
		fx = currentFx(),
		color2 = dualOn and {
			math.floor(selectedColor2().R * 255 + 0.5),
			math.floor(selectedColor2().G * 255 + 0.5),
			math.floor(selectedColor2().B * 255 + 0.5),
		} or nil,
		color = {
			math.floor(color.R * 255 + 0.5),
			math.floor(color.G * 255 + 0.5),
			math.floor(color.B * 255 + 0.5),
		},
	}

	setBusy(true)
	task.spawn(function()
		local center, rotation, right = getPlacement()
		storePlacement(entry, center, rotation, right)

		local ok, group, err = pcall(buildName, entry)
		setBusy(false)
		if not ok then
			warn("[DZHUP] " .. tostring(group))
			showToast("Could not build the name. Check the console.", false)
			return
		end
		if not group then
			showToast(tostring(err or "Could not create the name"), false)
			return
		end

		table.insert(names, entry)
		rememberSettings()
		local saved = persist()
		renderList()
		if saved then
			showToast("Name created and saved", true)
		else
			showToast("Name created (saving is not supported here)", true)
		end
	end)
end
createButton.Activated:Connect(submit)
nameBox.FocusLost:Connect(function(enterPressed)
	if enterPressed then
		submit()
	end
end)

---------------------------------------------------------------------
-- Boot
---------------------------------------------------------------------
do
	local last = save.settings.last
	if type(last) == "table" then
		if PALETTE[last.color] then
			selectedColorIndex = last.color
		end
		if PALETTE[last.color2] then
			selectedColor2Index = last.color2
		end
		dualOn = last.dual == true
		if FONT_BY_KEY[last.font] then
			selectedFont = FONT_BY_KEY[last.font]
		end
		if STYLE_TITLES[last.style] then
			selectedStyle = last.style
		end
		if SIZE_VALUES[last.size] then
			studio.size = last.size
		end
		if SPACING_VALUES[last.gap] then
			studio.gap = last.gap
		end
		if SHAPE_TITLES[last.shape] then
			studio.shape = last.shape
		end
		for _, item in ipairs(CASES) do
			if item.key == last.case then
				studio.case = last.case
			end
		end
		if type(last.fx) == "table" then
			for key in pairs(studio.fx) do
				studio.fx[key] = last.fx[key] == true
			end
		end
	end
end
setStyle(selectedStyle)
setFont(selectedFont.key)
refreshStudio()
switchTab(1, true)
updatePreview()
renderList()

genv.DZHUP_NameMakerCleanup = function()
	for _, c in ipairs(conns) do
		pcall(function()
			c:Disconnect()
		end)
	end
	pcall(function()
		gui:Destroy()
	end)
	pcall(function()
		clickSound:Destroy()
	end)
	pcall(function()
		namesFolder:Destroy()
	end)
end

-- Restore saved names for this place
-- Only the letters are rebuilt. The character is never touched.
task.spawn(function()
	local warned = false
	task.wait(1) -- let the map finish loading so the spawn area is known

	local anchor = findSpawnPosition()
	local moved = 0

	-- wait for the camera so we know where you are
	local waited = 0
	while not Workspace.CurrentCamera and waited < 5 do
		task.wait(0.25)
		waited += 0.25
	end
	local viewPosition = viewBasis()

	for _, entry in ipairs(names) do
		-- a name saved far from you (another project, or up in the air) is brought in front of you
		if type(entry.center) == "table" then
			local saved = Vector3.new(entry.center[1], entry.center[2], entry.center[3])
			if flat(saved - viewPosition).Magnitude > CONFIG.RestoreMaxDistance or saved.Y > anchor.Y + 200 then
				local center, rotation, right = getPlacement(entry)
				moved += 1
				storePlacement(entry, center, rotation, right)
			end
		end
		local ok, group, err = pcall(buildName, entry)
		if (not ok or not group) and not warned then
			warned = true
			warn("[DZHUP] Could not restore saved names: " .. tostring(ok and err or group))
		end
		task.wait()
	end
	if moved > 0 then
		persist()
	end
end)

for _, font in ipairs(FONTS) do
	if (not font.packId or font.packId == 0) and next(font.letterIds or {}) == nil then
		warn("[DZHUP] Font " .. font.title .. " has no asset id. Set packId in CONFIG.Fonts.")
	end
end

-- Native Roblox notifications: Discord first, then WhatsApp
local function askNotification(title, text, yesText, onYes)
	local answered = false
	local callback = Instance.new("BindableFunction")
	callback.OnInvoke = function(choice)
		answered = true
		if choice == yesText then
			onYes()
		end
	end
	-- the Roblox core UI can take a moment to accept notifications, so retry a few times
	local sent = false
	for _ = 1, 8 do
		local ok = pcall(function()
			StarterGui:SetCore("SendNotification", {
				Title = title,
				Text = text,
				Duration = 15,
				Button1 = yesText,
				Button2 = "Not now",
				Callback = callback,
			})
		end)
		if ok then
			sent = true
			break
		end
		task.wait(1)
	end
	if not sent then
		callback:Destroy()
		return
	end
	local waited = 0
	while not answered and waited < 16 do
		task.wait(0.25)
		waited += 0.25
	end
	callback:Destroy()
end

local function notifyCopied(text)
	pcall(function()
		StarterGui:SetCore("SendNotification", { Title = CONFIG.Creator, Text = text, Duration = 5 })
	end)
end

-- Shown on every launch: Discord first, then WhatsApp, then TikTok
if CONFIG.PromptOnLaunch then
	task.spawn(function()
		task.wait(3)
		askNotification(CONFIG.Creator .. "  |  " .. CONFIG.Community, "Do you want to join my Discord community?", "Join", function()
			if copyText(CONFIG.Discord) then
				notifyCopied("Discord link copied. Paste it in your browser.")
			else
				notifyCopied(CONFIG.Discord)
			end
		end)
		task.wait(1)
		askNotification(CONFIG.Creator .. "  |  " .. CONFIG.Community, "Do you want to follow my WhatsApp channel?", "Follow", function()
			if copyText(CONFIG.WhatsApp) then
				notifyCopied("WhatsApp link copied. Paste it in your browser.")
			else
				notifyCopied(CONFIG.WhatsApp)
			end
		end)
		task.wait(1)
		askNotification(CONFIG.Creator .. "  |  " .. CONFIG.Community, "Do you want to follow my TikTok account?", "Follow", function()
			if copyText(CONFIG.TikTok) then
				notifyCopied("TikTok link copied. Paste it in your browser.")
			else
				notifyCopied(CONFIG.TikTok)
			end
		end)
	end)
end
