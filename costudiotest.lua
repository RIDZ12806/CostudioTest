--[[
DZ HUP  |  3D Name Maker  (Executor Edition)
Made by RiyadoDzz

Single LocalScript-style file. No Studio setup needed:
letters are loaded from Roblox asset IDs automatically.
Names are saved to a file and restored on the next launch.
]]

if not game:IsLoaded() then
	game.Loaded:Wait()
end

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
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

	-- >>> Your picture (use ONE of these two) <<<
	RobloxUsername = "RiyadoDzz", -- your avatar is loaded automatically from this username
	AvatarRobloxUserId = 0, -- optional: set the user id directly if the username lookup fails
	AvatarImageUrl = "", -- or a direct image link (GitHub raw), e.g. https://raw.githubusercontent.com/.../me.png

	-- >>> Letter models (use ONE of these two) <<<
	-- Rockwell Letters pack: models named A..Z, a..z, 0..9 (upper and lower case are separate)
	PackAssetId = 4506165589,
	LetterAssetIds = {
		-- or one id per letter, for example:
		-- A = 1234567890,
		-- B = 1234567891,
	},

	SaveFile = "DZHUP_NameMaker.json",
	PromptOnLaunch = true, -- ask about Discord / WhatsApp when the system opens

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

local PANEL_W, PANEL_H = 620, 460
local MIN_SCALE = 0.4

local gui = new("ScreenGui", {
	Name = "DZHUP_NameMaker",
	ResetOnSpawn = false,
	IgnoreGuiInset = true,
	DisplayOrder = 999,
	ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, guiParent)

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

local fillFrame = new("Frame", {
	Size = UDim2.fromScale(1, 1),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
}, panel)
corner(fillFrame, 16)
new("UIGradient", { Color = ColorSequence.new(THEME.bgTop, THEME.bg), Rotation = 90 }, fillFrame)

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
	Size = UDim2.new(1 / 3, -8, 1, -8),
	BackgroundColor3 = Color3.new(1, 1, 1),
	BorderSizePixel = 0,
}, tabTrack)
corner(tabIndicator, 7)
new("UIGradient", { Color = ColorSequence.new(THEME.accentSoft, THEME.accent), Rotation = 90 }, tabIndicator)

local content = new("Frame", {
	Position = UDim2.fromOffset(16, CONTENT_Y),
	Size = UDim2.fromOffset(588, 300),
	BackgroundTransparency = 1,
}, panel)
local createPage = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, content)
local listPage = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, content)
local aboutPage = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false }, content)
local pages = { createPage, listPage, aboutPage }

local TAB_TITLES = { "Create", "My Names", "Creator" }
local tabButtons = {}
for i, title in ipairs(TAB_TITLES) do
	tabButtons[i] = new("TextButton", {
		Position = UDim2.new((i - 1) / 3, 0, 0, 0),
		Size = UDim2.new(1 / 3, 0, 1, 0),
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
	Size = UDim2.fromOffset(350, 300),
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

local createButton = makeButton(form, {
	Text = "CREATE 3D NAME",
	Position = UDim2.fromOffset(16, 242),
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
	Size = UDim2.fromOffset(226, 300),
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
local selectedStyle = "Plastic"
local swatches = {}

local function selectedColor()
	return PALETTE[selectedColorIndex][2]
end

local function updatePreview()
	local color = selectedColor()
	local text = nameBox.Text ~= "" and nameBox.Text or "YOUR NAME"
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

	infoStyle.Text = "Material: " .. (STYLE_TITLES[selectedStyle] or selectedStyle)
	infoColor.Text = "Color: " .. PALETTE[selectedColorIndex][1]
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
	swatch.MouseEnter:Connect(function()
		if selectedColorIndex ~= index then
			tween(ring, 0.1, { Transparency = 0.6 })
		end
	end)
	swatch.MouseLeave:Connect(function()
		if selectedColorIndex ~= index then
			tween(ring, 0.1, { Transparency = 1 })
		end
	end)
	swatch.Activated:Connect(function()
		selectedColorIndex = index
		for i, otherRing in ipairs(swatches) do
			tween(otherRing, 0.14, { Transparency = i == index and 0 or 1 })
		end
		updatePreview()
	end)
end
swatches[1].Transparency = 0

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
-- 3D engine (letters loaded from asset IDs)
---------------------------------------------------------------------
local templates = {}
local packIndex = nil
local packFailed = false

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

local function getPackIndex()
	if packIndex then
		return packIndex
	end
	if packFailed or CONFIG.PackAssetId == 0 then
		return nil
	end
	local root = loadObject(CONFIG.PackAssetId)
	if not root then
		packFailed = true
		return nil
	end
	-- Case-sensitive index: "a" and "A" are two different models in the pack
	local index = {}
	local function scan(container)
		for _, child in ipairs(container:GetChildren()) do
			local key = child.Name
			if #key == 1 and (child:IsA("Model") or child:IsA("BasePart") or child:IsA("Folder")) then
				if not index[key] then
					index[key] = child
				end
			end
		end
	end
	scan(root)
	if next(index) == nil then
		for _, item in ipairs(root:GetDescendants()) do
			if (item:IsA("Folder") or item:IsA("Model")) and #item:GetChildren() > 3 then
				scan(item)
				if next(index) ~= nil then
					break
				end
			end
		end
	end
	if next(index) == nil then
		packFailed = true
		return nil
	end
	packIndex = index
	return index
end

local function oppositeCase(character)
	local upper = string.upper(character)
	if upper ~= character then
		return upper
	end
	return string.lower(character)
end

local function getTemplate(character)
	local cached = templates[character]
	if cached then
		return cached
	end

	local source = nil
	local index = getPackIndex()
	if index then
		-- exact character first (a vs A), then the other case as a fallback
		source = index[character] or index[oppositeCase(character)]
	end
	if not source then
		local id = CONFIG.LetterAssetIds[character]
			or CONFIG.LetterAssetIds[string.upper(character)]
			or CONFIG.LetterAssetIds[string.lower(character)]
		if id then
			source = loadObject(id)
		end
	end
	if not source then
		if CONFIG.PackAssetId == 0 and next(CONFIG.LetterAssetIds) == nil then
			return nil, "Letter asset IDs are not set. Fill PackAssetId or LetterAssetIds in CONFIG."
		end
		return nil, 'Letter "' .. character .. '" is not available'
	end

	local model = toModel(source)
	if not model then
		return nil, 'Could not read the model for "' .. character .. '"'
	end

	local pivot = model:GetPivot()
	model:PivotTo(CFrame.new(pivot.Position))

	local ok, boxCFrame, size = pcall(function()
		return model:GetBoundingBox()
	end)
	if not ok or size.X <= 0 or size.Y <= 0 then
		model:Destroy()
		return nil, 'The model for "' .. character .. '" has no 3D parts'
	end

	local template = { model = model, center = boxCFrame.Position, width = size.X, height = size.Y }
	templates[character] = template
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
	if not CONFIG.FrontFaceIsNegativeZ then
		rotation = rotation * CFrame.Angles(0, math.pi, 0)
	end
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

local function buildName(entry)
	local style = STYLE_DEFS[entry.style] or STYLE_DEFS.Plastic
	local color = Color3.fromRGB(entry.color[1], entry.color[2], entry.color[3])
	local center = Vector3.new(entry.center[1], entry.center[2], entry.center[3])
	local rotation = CFrame.new(0, 0, 0, table.unpack(entry.rot))
	local right = Vector3.new(entry.right[1], entry.right[2], entry.right[3])

	local pieces = {}
	local letterCount, widthSum = 0, 0
	for _, codepoint in utf8.codes(entry.name) do
		local character = utf8.char(codepoint)
		if string.match(character, "^%s$") then
			table.insert(pieces, { space = true })
		else
			local template, templateError = getTemplate(character)
			if not template then
				return nil, templateError
			end
			table.insert(pieces, { template = template })
			letterCount += 1
			widthSum += template.width
		end
	end

	local spaceWidth = letterCount > 0 and (widthSum / letterCount) * CONFIG.SpaceWidthRatio or 1
	local totalWidth = -CONFIG.LetterGap
	for _, piece in ipairs(pieces) do
		piece.width = piece.template and piece.template.width or spaceWidth
		totalWidth += piece.width + CONFIG.LetterGap
	end

	local group = Instance.new("Model")
	group.Name = modelNameOf(entry)

	local cursor = -totalWidth / 2
	local firstPart = nil
	for _, piece in ipairs(pieces) do
		local template = piece.template
		if template then
			local letter = template.model:Clone()
			paintModel(letter, color, style)

			local target = center + right * (cursor + piece.width / 2) + Vector3.yAxis * (template.height / 2)
			local placement = CFrame.new(target) * rotation * CFrame.new(-template.center)
			letter:PivotTo(placement * letter:GetPivot())

			letter.Name = template.model.Name
			letter.Parent = group
			firstPart = firstPart or letter:FindFirstChildWhichIsA("BasePart", true)
		end
		cursor += piece.width + CONFIG.LetterGap
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
	return group
end

---------------------------------------------------------------------
-- My Names page
---------------------------------------------------------------------
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

local emptyState = textLabel(listPage, "No saved names yet\nCreate your first one from the Create tab", {
	Position = UDim2.fromOffset(0, 28),
	Size = UDim2.new(1, 0, 1, -28),
	TextSize = 13,
	TextColor3 = THEME.muted,
	TextWrapped = true,
	TextXAlignment = Enum.TextXAlignment.Center,
})

local renderList

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

	tabButtons[2].Text = string.format("My Names (%d)", #sorted)
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

		textLabel(row, tostring(entry.name), {
			Position = UDim2.fromOffset(60, 10),
			Size = UDim2.new(1, -230, 0, 24),
			Font = Enum.Font.GothamBold,
			TextSize = 17,
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		textLabel(row, (STYLE_TITLES[entry.style] or "Plastic") .. " material", {
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

---------------------------------------------------------------------
-- Creator page
---------------------------------------------------------------------
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

contactCard(44, "D", THEME.discord, "Discord", "Join the community server", CONFIG.Discord, "Discord link copied")
contactCard(124, "W", THEME.whatsapp, "WhatsApp", "Follow the channel", CONFIG.WhatsApp, "WhatsApp link copied")

textLabel(aboutRight, "Tap a card to copy its link,\nthen paste it in your browser.", {
	Position = UDim2.fromOffset(16, 214),
	Size = UDim2.new(1, -32, 0, 36),
	TextSize = 11,
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
	local target = UDim2.new((index - 1) / 3, 4, 0, 4)
	if instant then
		tabIndicator.Position = target
	else
		tween(tabIndicator, 0.3, { Position = target }, Enum.EasingStyle.Quint)
	end
	if index == 2 then
		renderList()
	end
end
for i, button in ipairs(tabButtons) do
	button.Activated:Connect(function()
		switchTab(i)
	end)
end

---------------------------------------------------------------------
-- Resize handle
---------------------------------------------------------------------
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

---------------------------------------------------------------------
-- Drag and resize
---------------------------------------------------------------------
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

---------------------------------------------------------------------
-- Open / close animation
---------------------------------------------------------------------
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

local function setOpen(open)
	if isOpen == open then
		return
	end
	isOpen = open
	openToken += 1
	local token = openToken

	tween(openButtonScale, 0.1, { Scale = 0.92 })
	task.delay(0.1, function()
		tween(openButtonScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
	end)

	if open then
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

		tween(openStroke, 0.25, { Transparency = 0 })
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
		tween(openStroke, 0.25, { Transparency = 0.45 })
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
setStyle("Plastic")
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

if CONFIG.PackAssetId == 0 and next(CONFIG.LetterAssetIds) == nil then
	warn("[DZHUP] Letter asset IDs are not set. Fill PackAssetId or LetterAssetIds in CONFIG.")
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

-- Shown on every launch: Discord first, then WhatsApp
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
	end)
end
