--[[
    PeexHubs | GrowBlox v7
    UI mengikuti gaya game (ungu tua + garis magenta, panel cokelat, font Nunito).
    Tab: Profil, Click Walk, Fishing.

    Gerak karakter dan kerusakan dihitung SERVER (client hanya mengirim input kiri/kanan/lompat),
    jadi teleport, noclip, dan god mode tidak bisa dibuat dari client.
    Click Walk berjalan lewat tombol gerak biasa. Auto Fishing memakai event Fishing milik game:
    tekan HOOK saat ikan menggigit, tahan/lepas Space selama pertarungan, lalu lempar ulang.

    Tombol P (atau tombol "P" di layar) untuk buka/tutup menu.
]]

local genv = (getgenv and getgenv()) or _G
local existing = genv.PeexHubsGB7
if type(existing) == "table" and type(existing.toggle) == "function" then
    pcall(existing.toggle)
    return
end
genv.PeexHubsGB7 = nil

local function Main()
local API = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui")
local Camera = workspace.CurrentCamera or workspace:WaitForChild("Camera")

local VERSION = "v7.1.0"

----------------------------------------------------------------------
-- CONFIG
----------------------------------------------------------------------
local CONFIG_FILE = "PeexHubs_GrowBlox_v7.json"
local Config = {
    walkCtrl = true, -- Click Walk hanya jalan kalau Ctrl ditahan (PC)
    walkTimeout = 20, -- detik maksimal per perjalanan
    fishReactMin = 0.25, -- jeda minimal sebelum menekan HOOK (detik)
    fishReactMax = 0.6,
    fishRecast = true, -- lempar ulang otomatis ke titik lemparan terakhir
    fishRecastDelay = 2.5,
    fishRecastTimeout = 15, -- detik maksimal mencoba lempar ulang sebelum menyerah (bukan berhenti permanen)
}

pcall(function()
    if isfile and readfile and isfile(CONFIG_FILE) then
        local data = HttpService:JSONDecode(readfile(CONFIG_FILE))
        for key, value in pairs(data) do
            if Config[key] ~= nil and type(value) == type(Config[key]) then
                Config[key] = value
            end
        end
    end
end)

local function SaveConfig()
    pcall(function()
        if writefile then
            writefile(CONFIG_FILE, HttpService:JSONEncode(Config))
        end
    end)
end

----------------------------------------------------------------------
-- GAYA UI (warna dan font diambil dari UI game)
----------------------------------------------------------------------
local P = {
    purple = Color3.fromRGB(100, 20, 123),
    magenta = Color3.fromRGB(224, 68, 235),
    cream = Color3.fromRGB(255, 245, 255),
    brown = Color3.fromRGB(92, 58, 30),
    tan = Color3.fromRGB(214, 160, 96),
    dark = Color3.fromRGB(24, 24, 24),
    gray = Color3.fromRGB(110, 110, 110),
    slate = Color3.fromRGB(78, 98, 128),
    mint = Color3.fromRGB(120, 255, 195),
}

local okFont, FONT = pcall(Font.fromName, "Nunito", Enum.FontWeight.ExtraBold)
if not okFont then
    FONT = Font.fromEnum(Enum.Font.GothamBold)
end

local function New(class, props, parent)
    local inst = Instance.new(class)
    for key, value in pairs(props or {}) do
        inst[key] = value
    end
    if parent then
        inst.Parent = parent
    end
    return inst
end

local function Corner(inst, radius)
    return New("UICorner", { CornerRadius = UDim.new(0, radius or 8) }, inst)
end

local function Stroke(inst, color, thickness)
    return New("UIStroke", {
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Color = color,
        Thickness = thickness or 2,
    }, inst)
end

local function Text(parent, props)
    local base = {
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        FontFace = FONT,
        TextColor3 = P.cream,
        TextSize = 16,
        TextWrapped = true,
        TextXAlignment = Enum.TextXAlignment.Left,
        TextYAlignment = Enum.TextYAlignment.Center,
    }
    for key, value in pairs(props or {}) do
        base[key] = value
    end
    return New("TextLabel", base, parent)
end

local gui = New("ScreenGui", {
    Name = "PeexHub",
    ResetOnSpawn = false,
    DisplayOrder = 30,
    IgnoreGuiInset = false,
    ScreenInsets = Enum.ScreenInsets.DeviceSafeInsets,
})
gui.Parent = PlayerGui

-- Notifikasi kecil (gaya label game) --------------------------------------
local toast = nil
local function Notify(message)
    task.spawn(function()
        if toast then
            toast:Destroy()
        end
        local label = Text(gui, {
            AnchorPoint = Vector2.new(0.5, 1),
            Position = UDim2.new(0.5, 0, 1, -96),
            Size = UDim2.fromOffset(0, 0),
            AutomaticSize = Enum.AutomaticSize.XY,
            BackgroundTransparency = 0,
            BackgroundColor3 = P.purple,
            TextXAlignment = Enum.TextXAlignment.Center,
            TextWrapped = false,
            TextSize = 16,
            Text = tostring(message),
            ZIndex = 50,
        })
        Corner(label, 8)
        Stroke(label, P.magenta, 3)
        New("UIPadding", {
            PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14),
            PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
        }, label)
        toast = label
        task.wait(2.6)
        if toast == label then
            TweenService:Create(label, TweenInfo.new(0.3), { BackgroundTransparency = 1, TextTransparency = 1 }):Play()
            task.wait(0.3)
            label:Destroy()
            toast = nil
        end
    end)
end

----------------------------------------------------------------------
-- AKSES GAME (modul Shared milik game)
----------------------------------------------------------------------
local Shared = ReplicatedStorage:WaitForChild("Shared", 10)

local function Req(name)
    local inst = Shared and Shared:FindFirstChild(name)
    if not inst then
        return nil
    end
    local ok, mod = pcall(require, inst)
    if ok and type(mod) == "table" then
        return mod
    end
    return nil
end

local TileMath = Req("TileMath")
local TileConfig = Req("TileConfig")
local WorldNames = Req("WorldNames")

local function Root()
    local char = Player.Character
    return char and char:FindFirstChild("HumanoidRootPart"), char
end

local function GridOf(position)
    if not TileMath then
        return nil
    end
    local ok, gx, gy = pcall(TileMath.WorldToGrid, position)
    if ok and type(gx) == "number" and type(gy) == "number" then
        return gx, gy
    end
    return nil
end

local function GridCenter(gx, gy)
    if not TileMath then
        return nil
    end
    local ok, pos = pcall(TileMath.GridToWorld, gx, gy)
    if ok and typeof(pos) == "Vector3" then
        return pos
    end
    return nil
end

local function TileSize()
    return (TileConfig and tonumber(TileConfig.TILE_SIZE_X)) or 3
end

local function CurrentWorld()
    if not WorldNames then
        return nil
    end
    local ok, name = pcall(WorldNames.Current, Player)
    if ok and name ~= nil then
        return tostring(name)
    end
    return nil
end

----------------------------------------------------------------------
-- CLICK WALK: klik tile -> karakter berjalan ke sana memakai tombol gerak game
-- (kiri / kanan / lompat lewat VirtualInputManager). Fisika tetap dijalankan server.
----------------------------------------------------------------------
local TileIndex = Req("TileIndex")
local Keybinds = Req("Keybinds")
local MovePrediction = Req("MovePrediction")
local VIM = nil
pcall(function()
    VIM = game:GetService("VirtualInputManager")
end)

local Walk = { on = false, token = 0, conn = nil, status = "-", held = {} }
local DEFAULT_KEYS = { left = Enum.KeyCode.A, right = Enum.KeyCode.D, jump = Enum.KeyCode.Space }
local ACTION_IDS = { left = "Left", right = "Right", jump = "Jump" }

local function KeyFor(name)
    if Keybinds and Keybinds.Keys then
        local ok, list = pcall(Keybinds.Keys, ACTION_IDS[name])
        if ok and type(list) == "table" and list[1] then
            return list[1]
        end
    end
    return DEFAULT_KEYS[name]
end

local function Hold(name, down, force)
    if Walk.held[name] == down and not force then
        return
    end
    Walk.held[name] = down
    if VIM then
        pcall(VIM.SendKeyEvent, VIM, down, KeyFor(name), false, game)
    end
end

local function ReleaseAll()
    for name in pairs(DEFAULT_KEYS) do
        Hold(name, false, true) -- selalu kirim, supaya tidak ada tombol yang tersangkut
    end
end

local function BodyGrid()
    local char = Player.Character
    local pos = nil
    local current = MovePrediction and MovePrediction.Current
    if current and char and current.character == char and current.RenderPosition then
        local ok, p = pcall(current.RenderPosition)
        if ok and typeof(p) == "Vector3" then
            pos = p
        end
    end
    if not pos then
        local root = char and char:FindFirstChild("HumanoidRootPart")
        pos = root and root.Position
    end
    if not pos then
        return nil
    end
    return GridOf(pos)
end

local function SolidAt(gx, gy)
    if not TileIndex or not TileConfig then
        return false
    end
    local ok, tile = pcall(TileIndex.At, "Foreground", gx, gy)
    if not ok or not tile then
        return false
    end
    local id = tile:GetAttribute("ItemId")
    if typeof(id) ~= "number" then
        return false
    end
    local okItem, item = pcall(TileConfig.GetItem, id)
    return okItem and item ~= nil and item.collisionType == TileConfig.CollisionType.SOLID
end

local function Tap(name)
    Hold(name, true)
    task.wait(0.06)
    Hold(name, false)
end

function Walk.Go(tx, ty)
    Walk.token += 1
    local token = Walk.token
    ReleaseAll()
    local sx, sy = BodyGrid()
    Notify(string.format("Click Walk: %s,%s -> %d,%d", sx and tostring(sx) or "?", sy and tostring(sy) or "?", tx, ty))
    task.spawn(function()
        local started, lastMove, lastJump = os.clock(), os.clock(), 0
        local lastX, lastY = nil, nil
        local result = "timeout"
        Walk.status = "Berjalan"
        while Walk.on and Walk.token == token do
            if os.clock() - started > math.clamp(Config.walkTimeout, 3, 120) then
                break
            end
            local gx, gy = BodyGrid()
            if not gx then
                result = "pos"
                break
            end
            if gx == tx and math.abs(gy - ty) <= 1 then
                result = "ok"
                break
            end
            local dir = tx > gx and 1 or (tx < gx and -1 or 0)
            Hold("left", dir < 0)
            Hold("right", dir > 0)
            local needJump = false
            if dir ~= 0 and SolidAt(gx + dir, gy) then
                needJump = true
            end
            if ty > gy and (dir == 0 or SolidAt(gx + dir, gy)) then
                needJump = true
            end
            if needJump and os.clock() - lastJump > 0.35 then
                lastJump = os.clock()
                task.spawn(Tap, "jump")
            end
            if gx ~= lastX or gy ~= lastY then
                lastX, lastY, lastMove = gx, gy, os.clock()
            elseif os.clock() - lastMove > 2.5 then
                result = "stuck"
                break
            end
            task.wait(0.05)
        end
        ReleaseAll()
        if Walk.token ~= token then
            return
        end
        if result == "ok" then
            Walk.status = "Sampai"
            Notify("Click Walk: sampai.")
        elseif result == "stuck" then
            Walk.status = "Terhalang"
            Notify("Click Walk: terhalang, berhenti.")
        elseif result == "timeout" then
            Walk.status = "Waktu habis"
            Notify("Click Walk: waktu habis.")
        else
            Walk.status = "Gagal"
        end
    end)
end

local function ClickGrid(input)
    if not TileMath or not TileMath.ScreenToGrid then
        return nil
    end
    local position
    if input.UserInputType == Enum.UserInputType.Touch then
        position = Vector2.new(input.Position.X, input.Position.Y) + GuiService:GetGuiInset()
    else
        position = UIS:GetMouseLocation()
    end
    local ok, gx, gy = pcall(function()
        local camera = workspace.CurrentCamera or Camera
        return TileMath.ScreenToGrid(camera, position, TileMath.PlaneZ())
    end)
    if ok and type(gx) == "number" and type(gy) == "number" then
        return gx, gy
    end
    return nil
end

local function OnClick(input, processed)
    if processed or not Walk.on then
        return
    end
    local kind = input.UserInputType
    if kind ~= Enum.UserInputType.MouseButton1 and kind ~= Enum.UserInputType.Touch then
        return
    end
    local touchOnly = UIS.TouchEnabled and not UIS.KeyboardEnabled
    if Config.walkCtrl and not touchOnly
        and not (UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.RightControl)) then
        return
    end
    local gx, gy = ClickGrid(input)
    if gx then
        Walk.Go(gx, gy)
    else
        Notify("Click Walk: posisi klik tidak terbaca.")
    end
end

Player.CharacterRemoving:Connect(function()
    Walk.token += 1
    ReleaseAll()
end)

function Walk.Start()
    if Walk.on then
        return true
    end
    if not VIM then
        Notify("VirtualInputManager tidak tersedia di executor ini.")
        return false
    end
    if not TileMath then
        Notify("Modul tile belum siap.")
        return false
    end
    Walk.on = true
    Walk.conn = UIS.InputBegan:Connect(OnClick)
    return true
end

function Walk.Stop()
    if not Walk.on then
        return false
    end
    Walk.on = false
    Walk.token += 1
    if Walk.conn then
        Walk.conn:Disconnect()
        Walk.conn = nil
    end
    ReleaseAll()
    Walk.status = "-"
    return true
end

----------------------------------------------------------------------
-- AUTO FISHING
-- Alur game (event Events.Fishing): Cast -> Nibble -> Bite -> (HOOK) -> Fight -> Caught / End.
-- Bot hanya melakukan yang dilakukan pemain: menekan Space saat ikan menggigit, lalu menahan /
-- melepas Space supaya jarum tetap di zona hijau (dibaca dari UI mini-game), dan mengklik lagi
-- titik lemparan terakhir. Lemparan pertama dilakukan sendiri.
----------------------------------------------------------------------
local FishingRemote = nil
do
    local events = ReplicatedStorage:FindFirstChild("Events")
    FishingRemote = events and events:FindFirstChild("Fishing")
end

local Fish = {
    on = false, conn = nil, token = 0, fightToken = 0, castToken = 0, status = "Mati",
    caught = 0, lost = 0, hooks = 0, recasts = 0, lastCast = nil, spaceDown = false,
    lastEventAt = 0, waiting = false,
}

local function SpaceKey(down)
    if Fish.spaceDown == down then
        return
    end
    Fish.spaceDown = down
    if VIM then
        pcall(VIM.SendKeyEvent, VIM, down, Enum.KeyCode.Space, false, game)
    end
end

local function DialogBusy()
    return PlayerGui:GetAttribute("DialogOpen") == true or PlayerGui:GetAttribute("WorldMenuOpen") == true
end

local function FightLoop(token)
    local ui = PlayerGui:FindFirstChild("Fishing")
    local needle = ui and ui:FindFirstChild("Needle", true)
    local zone = ui and ui:FindFirstChild("Zone", true)
    Fish.status = "Melawan ikan"
    while Fish.on and Fish.fightToken == token do
        if needle and zone then
            local tension = needle.Position.X.Scale
            local center = zone.Position.X.Scale
            SpaceKey(tension < center) -- tahan untuk menarik jarum ke kanan, lepas untuk ke kiri
        end
        task.wait()
    end
    SpaceKey(false)
end

-- Klik ulang ke tile terakhir (Fish.lastCast). Game ini tidak punya event "cast ulang
-- otomatis" dari server: casting SELALU butuh klik tile, jadi fungsi ini meniru klik itu.
-- castToken = token per-siklus lempar: kalau ada "End" baru / Stop / Start, retry lama
-- otomatis berhenti sendiri (castToken sudah tidak cocok) supaya tidak dobel klik.
--
-- PERBAIKAN dari versi lama: dulu fungsi ini cuma mencoba SEKALI. Kalau pas giliran klik
-- popup "Caught!" / dialog lain masih kebuka, kamera belum selesai zoom balik (titik lempar
-- jadi di luar layar sesaat), atau modul tile belum siap, fungsi langsung menyerah diam-diam
-- dan Auto Fishing berhenti total sampai dilempar manual. Sekarang dia mencoba berulang
-- (tiap 0.4 dtk) selama kondisi belum aman, sampai batas waktu fishRecastTimeout habis.
local function Recast(castToken)
    if not Config.fishRecast then
        Fish.status = "Menunggu lemparan manual"
        return
    end
    if not VIM then
        Fish.status = "Menunggu lemparan manual (VIM tidak ada)"
        return
    end
    local function Cancelled()
        return not Fish.on or Fish.castToken ~= castToken
    end
    task.wait(math.max(0.5, Config.fishRecastDelay) + math.random() * 0.8)
    if Cancelled() then
        return
    end
    Fish.status = "Lempar ulang..."
    local timeout = math.max(3, tonumber(Config.fishRecastTimeout) or 15)
    local deadline = os.clock() + timeout
    while not Cancelled() do
        if not Fish.lastCast then
            Fish.status = "Menunggu titik lemparan terakhir (lempar manual sekali)"
        elseif DialogBusy() then
            Fish.status = "Lempar ulang: menunggu dialog tertutup"
        elseif not TileMath then
            Fish.status = "Lempar ulang: modul tile belum siap"
        else
            local camera = workspace.CurrentCamera or Camera
            local world = camera and GridCenter(Fish.lastCast.x, Fish.lastCast.y)
            if not world then
                Fish.status = "Lempar ulang: tile belum terbaca"
            else
                local screen, visible = camera:WorldToViewportPoint(world)
                if not visible then
                    Fish.status = "Lempar ulang: titik di luar layar, menunggu kamera"
                else
                    pcall(VIM.SendMouseButtonEvent, VIM, screen.X, screen.Y, 0, true, game, 0)
                    task.wait(0.06)
                    pcall(VIM.SendMouseButtonEvent, VIM, screen.X, screen.Y, 0, false, game, 0)
                    Fish.recasts += 1
                    Fish.waiting = true
                    Fish.status = "Menunggu ikan"
                    return
                end
            end
        end
        if os.clock() > deadline then
            Fish.status = "Lempar ulang gagal (" .. timeout .. "dtk), coba lempar manual"
            Notify("Auto Fishing: lempar ulang gagal terus (cek dialog/kamera), lempar manual sekali untuk lanjut.")
            return
        end
        task.wait(0.4)
    end
end

local function OnFishing(kind, a, b, c)
    if not Fish.on then
        return
    end
    Fish.lastEventAt = os.clock()
    local me = Player.UserId
    if kind == "Line" then
        if a == me and type(b) == "number" and type(c) == "number" then
            Fish.lastCast = { x = b, y = c }
        end
    elseif kind == "Cast" then
        Fish.waiting = true
        Fish.status = "Menunggu ikan"
    elseif kind == "Bite" then
        if a == me then
            Fish.status = "Ikan menggigit"
            local token = Fish.token
            local window = type(b) == "number" and b or 1
            local lo, hi = math.max(0.1, Config.fishReactMin), math.max(Config.fishReactMin, Config.fishReactMax)
            local delay = math.min(lo + math.random() * (hi - lo), window * 0.6)
            task.delay(delay, function()
                if Fish.on and Fish.token == token and not DialogBusy() then
                    Fish.hooks += 1
                    SpaceKey(true)
                    task.wait(0.06)
                    SpaceKey(false)
                end
            end)
        end
    elseif kind == "Fight" then
        Fish.fightToken += 1
        task.spawn(FightLoop, Fish.fightToken)
    elseif kind == "Caught" then
        Fish.caught += 1
    elseif kind == "Spooked" or kind == "Missed" then
        Fish.status = "Ikan lolos, menunggu"
    elseif kind == "End" then
        Fish.fightToken += 1
        Fish.waiting = false
        SpaceKey(false)
        if a == "snap" or a == "escape" then
            Fish.lost += 1
        end
        Fish.castToken += 1
        task.spawn(Recast, Fish.castToken)
    end
end

-- Watchdog: kalau sudah lama tidak ada event Fishing sama sekali padahal Auto Fishing
-- masih aktif dan sedang menunggu ikan (bukan lagi lempar ulang / lawan ikan), paksa
-- lempar ulang. Ini jaring pengaman kalau event "End" sampai tidak diterima (koneksi event
-- terlewat) sehingga dulu bot bisa diam total tanpa pernah mencoba lempar lagi.
local function FishWatchdog()
    while Fish.on do
        task.wait(1)
        if Fish.on and Fish.waiting
            and os.clock() - Fish.lastEventAt > math.max(20, Config.fishRecastDelay + 15) then
            Fish.status = "Tidak ada respons, coba lempar ulang"
            Fish.waiting = false
            Fish.castToken += 1
            task.spawn(Recast, Fish.castToken)
        end
    end
end

function Fish.Start()
    if Fish.on then
        return true
    end
    if not FishingRemote or not FishingRemote:IsA("RemoteEvent") then
        Notify("Event Fishing tidak ditemukan.")
        return false
    end
    if not VIM then
        Notify("VirtualInputManager tidak tersedia di executor ini.")
        return false
    end
    Fish.on = true
    Fish.token += 1
    Fish.fightToken += 1
    Fish.castToken += 1
    Fish.waiting = false
    Fish.lastEventAt = os.clock()
    Fish.status = "Lempar pancing pertama sendiri"
    Fish.conn = FishingRemote.OnClientEvent:Connect(OnFishing)
    task.spawn(FishWatchdog)
    return true
end

function Fish.Stop()
    if not Fish.on then
        return false
    end
    Fish.on = false
    Fish.token += 1
    Fish.fightToken += 1
    Fish.castToken += 1
    Fish.waiting = false
    if Fish.conn then
        Fish.conn:Disconnect()
        Fish.conn = nil
    end
    SpaceKey(false)
    Fish.status = "Mati"
    return true
end

local Features = {
    clickwalk = { label = "Click Walk", get = function() return Walk.on end,
        set = function(on) if on then return Walk.Start() end return Walk.Stop() end },
    fishing = { label = "Auto Fishing", get = function() return Fish.on end,
        set = function(on) if on then return Fish.Start() end return Fish.Stop() end },
}

local refreshers = {}
local function RefreshAll()
    for _, fn in ipairs(refreshers) do
        pcall(fn)
    end
end

local function SetFeature(key, on)
    local feature = Features[key]
    local ok, err = pcall(feature.set, on)
    if not ok then
        warn(err)
        Notify(feature.label .. " error")
    elseif feature.get() == on then
        Notify(feature.label .. (on and " aktif." or " dimatikan."))
    end
    RefreshAll()
end

----------------------------------------------------------------------
-- UI: jendela
----------------------------------------------------------------------
local viewport = Camera.ViewportSize
local width = math.min(440, math.max(280, viewport.X - 24))
local height = math.min(360, math.max(260, viewport.Y - 90))

local win = New("Frame", {
    Name = "Window",
    AnchorPoint = Vector2.new(0.5, 0.5),
    Position = UDim2.fromScale(0.5, 0.5),
    Size = UDim2.fromOffset(width, height),
    BackgroundColor3 = P.purple,
    BorderSizePixel = 0,
    Visible = false,
}, gui)
Corner(win, 14)
Stroke(win, P.magenta, 3)

local titleBar = New("Frame", {
    Size = UDim2.new(1, 0, 0, 44),
    BackgroundTransparency = 1,
}, win)
Text(titleBar, {
    Position = UDim2.fromOffset(16, 0),
    Size = UDim2.new(1, -70, 1, 0),
    Text = "PEEX HUB  <font size=\"13\" color=\"rgb(214,160,96)\">" .. VERSION .. "</font>",
    RichText = true,
    TextSize = 24,
    TextWrapped = false,
})

local closeButton = New("TextButton", {
    AnchorPoint = Vector2.new(1, 0.5),
    Position = UDim2.new(1, -10, 0.5, 0),
    Size = UDim2.fromOffset(34, 34),
    BackgroundColor3 = P.purple,
    Text = "X",
    FontFace = FONT,
    TextSize = 18,
    TextColor3 = P.cream,
    AutoButtonColor = false,
}, titleBar)
Corner(closeButton, 8)
Stroke(closeButton, P.magenta, 3)

-- geser jendela lewat title bar
do
    local dragging, dragStart, startPos = false, nil, nil
    titleBar.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, dragStart, startPos = true, input.Position, win.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            win.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
        end
    end)
end

local tabBar = New("Frame", {
    Position = UDim2.fromOffset(12, 46),
    Size = UDim2.new(1, -24, 0, 36),
    BackgroundTransparency = 1,
}, win)
New("UIListLayout", {
    FillDirection = Enum.FillDirection.Horizontal,
    Padding = UDim.new(0, 8),
    SortOrder = Enum.SortOrder.LayoutOrder,
}, tabBar)

local content = New("Frame", {
    Position = UDim2.fromOffset(12, 90),
    Size = UDim2.new(1, -24, 1, -102),
    BackgroundTransparency = 1,
    ClipsDescendants = true,
}, win)

local pages, tabButtons = {}, {}

local function NewPage(id)
    local page = New("ScrollingFrame", {
        Size = UDim2.fromScale(1, 1),
        BackgroundTransparency = 1,
        BorderSizePixel = 0,
        ScrollBarThickness = 4,
        ScrollBarImageColor3 = P.magenta,
        CanvasSize = UDim2.new(),
        AutomaticCanvasSize = Enum.AutomaticSize.Y,
        Visible = false,
    }, content)
    New("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }, page)
    New("UIPadding", { PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6) }, page)
    pages[id] = page
    return page
end

local function SwitchTab(id)
    for pageId, page in pairs(pages) do
        page.Visible = pageId == id
    end
    for tabId, button in pairs(tabButtons) do
        local active = tabId == id
        button.BackgroundColor3 = active and P.magenta or P.brown
        button.TextColor3 = active and P.dark or P.cream
    end
end

local function NewTab(id, label, order)
    local button = New("TextButton", {
        Size = UDim2.new(1 / 3, -6, 1, 0),
        BackgroundColor3 = P.brown,
        Text = label,
        FontFace = FONT,
        TextSize = 16,
        TextColor3 = P.cream,
        AutoButtonColor = false,
        LayoutOrder = order,
    }, tabBar)
    Corner(button, 8)
    Stroke(button, P.tan, 2)
    button.Activated:Connect(function()
        SwitchTab(id)
    end)
    tabButtons[id] = button
end

local function Card(page, cardHeight)
    local card = New("Frame", {
        Size = UDim2.new(1, 0, 0, cardHeight),
        BackgroundColor3 = P.brown,
        BorderSizePixel = 0,
    }, page)
    Corner(card, 8)
    Stroke(card, P.tan, 2)
    return card
end

local function Section(page, label)
    Text(page, {
        Size = UDim2.new(1, 0, 0, 22),
        Text = label:upper(),
        TextSize = 14,
        TextColor3 = P.tan,
    })
end

local function SwitchCard(page, title, desc, get, set)
    local card = Card(page, 58)
    Text(card, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -100, 0, 22), Text = title, TextSize = 18 })
    Text(card, {
        Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -100, 0, 24),
        Text = desc, TextSize = 13, TextColor3 = P.tan,
    })
    local button = New("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(70, 34),
        FontFace = FONT,
        TextSize = 16,
        AutoButtonColor = false,
    }, card)
    Corner(button, 8)
    Stroke(button, P.tan, 2)
    local function Refresh()
        local on = get()
        button.Text = on and "ON" or "OFF"
        button.BackgroundColor3 = on and P.mint or P.dark
        button.TextColor3 = on and P.dark or P.cream
    end
    button.Activated:Connect(function()
        set(not get())
        RefreshAll()
    end)
    table.insert(refreshers, Refresh)
    Refresh()
end

local function InputCard(page, title, desc, value, onSubmit)
    local card = Card(page, 58)
    Text(card, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -110, 0, 22), Text = title, TextSize = 18 })
    Text(card, {
        Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -110, 0, 24),
        Text = desc, TextSize = 13, TextColor3 = P.tan,
    })
    local box = New("TextBox", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(84, 34),
        BackgroundColor3 = P.dark,
        Text = tostring(value),
        FontFace = FONT,
        TextSize = 16,
        TextColor3 = P.cream,
        ClearTextOnFocus = false,
    }, card)
    Corner(box, 8)
    Stroke(box, P.tan, 2)
    box.FocusLost:Connect(function()
        onSubmit(box.Text, box)
    end)
end

local function ActionCard(page, title, desc, buttonText, onClick)
    local card = Card(page, 58)
    Text(card, { Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -110, 0, 22), Text = title, TextSize = 18 })
    Text(card, {
        Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -110, 0, 24),
        Text = desc, TextSize = 13, TextColor3 = P.tan,
    })
    local button = New("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5),
        Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(84, 34),
        BackgroundColor3 = P.purple,
        Text = buttonText,
        FontFace = FONT,
        TextSize = 15,
        TextColor3 = P.cream,
        AutoButtonColor = false,
    }, card)
    Corner(button, 8)
    Stroke(button, P.magenta, 2)
    button.Activated:Connect(function()
        task.spawn(onClick)
    end)
end

----------------------------------------------------------------------
-- HALAMAN: Profil
----------------------------------------------------------------------
local function Comma(value)
    local text = tostring(math.floor(tonumber(value) or 0))
    return (text:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

local function BuildProfile(page)
    local header = Card(page, 92)
    local avatar = New("ImageLabel", {
        Position = UDim2.fromOffset(10, 10),
        Size = UDim2.fromOffset(72, 72),
        BackgroundColor3 = P.dark,
        BorderSizePixel = 0,
        Image = "",
    }, header)
    Corner(avatar, 10)
    Stroke(avatar, P.tan, 2)
    task.spawn(function()
        local ok, image = pcall(Players.GetUserThumbnailAsync, Players, Player.UserId,
            Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
        if ok then
            avatar.Image = image
        end
    end)
    local nameLabel = Text(header, {
        Position = UDim2.fromOffset(94, 10), Size = UDim2.new(1, -104, 0, 30),
        Text = Player.DisplayName, TextSize = 24, TextWrapped = false,
    })
    local subLabel = Text(header, {
        Position = UDim2.fromOffset(94, 42), Size = UDim2.new(1, -104, 0, 40),
        Text = "", TextSize = 14, TextColor3 = P.tan,
    })

    Section(page, "Akun")
    local account = Card(page, 118)
    local accountLabel = Text(account, {
        Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 1, -16),
        Text = "", TextSize = 16, TextYAlignment = Enum.TextYAlignment.Top,
    })

    Section(page, "Status")
    local status = Card(page, 98)
    local statusLabel = Text(status, {
        Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 1, -16),
        Text = "", TextSize = 16, TextYAlignment = Enum.TextYAlignment.Top,
    })

    local function Num(inst, name)
        local value = inst and inst:GetAttribute(name)
        return type(value) == "number" and value or nil
    end

    local function Update()
        local root, char = Root()
        local topian = Player:GetAttribute("TopianName")
        subLabel.Text = "@" .. Player.Name .. "\nID " .. Player.UserId
            .. (type(topian) == "string" and ("   Topian: " .. topian) or "")

        local gems, level, xp, slots = Num(Player, "Gems"), Num(Player, "Level"), Num(Player, "LevelXP"), Num(Player, "BackpackSlots")
        local role = Player:GetAttribute("StaffRole")
        local lines = {
            "Gems: " .. (gems and Comma(gems) or "-"),
            "Level: " .. (level and tostring(level) or "-") .. (xp and ("   XP " .. Comma(xp)) or ""),
            "Slot backpack: " .. (slots and tostring(slots) or "-"),
            "Role: " .. (type(role) == "string" and role or "Player"),
        }
        accountLabel.Text = table.concat(lines, "\n")

        local worldName = CurrentWorld()
        local gx, gy = nil, nil
        if root then
            gx, gy = GridOf(root.Position)
        end
        local health = Num(char, "TopianHealth")
        local motion = char and char:GetAttribute("TopianMotion")
        local state = "Normal"
        if char and char:GetAttribute("TopianRespawning") == true then
            state = "Respawn"
        elseif Player:GetAttribute("StaffCursedUntil") ~= nil then
            state = "Terkena kutukan staff"
        end
        statusLabel.Text = table.concat({
            "Dunia: " .. (worldName and worldName ~= "" and worldName or "-"),
            "Posisi tile: " .. (gx and string.format("%d, %d", gx, gy) or "-"),
            "Darah: " .. (health and tostring(health) or "-") .. "   Gerak: " .. (type(motion) == "string" and motion or "-"),
            "Kondisi: " .. state,
        }, "\n")
    end
    Update()
    task.spawn(function()
        while page.Parent do
            task.wait(0.5)
            if page.Visible and win.Visible then
                pcall(Update)
            end
        end
    end)
end

----------------------------------------------------------------------
-- HALAMAN: Click Walk
----------------------------------------------------------------------
local function BuildWalk(page)
    Section(page, "Click Walk")
    SwitchCard(page, "Click Walk", "Klik tile, karakter berjalan ke sana.",
        Features.clickwalk.get, function(on) SetFeature("clickwalk", on) end)
    SwitchCard(page, "Wajib tahan Ctrl", "PC saja. Di HP selalu aktif.",
        function() return Config.walkCtrl end,
        function(on)
            Config.walkCtrl = on
            SaveConfig()
        end)
    InputCard(page, "Batas waktu", "Detik maksimal per perjalanan.", Config.walkTimeout, function(text, box)
        local value = tonumber(text)
        if value and value >= 3 and value <= 120 then
            Config.walkTimeout = value
            SaveConfig()
        else
            Notify("Isi angka 3 sampai 120.")
        end
        box.Text = tostring(Config.walkTimeout)
    end)
    Section(page, "Catatan")
    local note = Card(page, 96)
    Text(note, {
        Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 1, -16),
        Text = "Gerak dihitung server, jadi teleport, noclip, dan god mode tidak bisa dari client. "
            .. "Click Walk memakai tombol gerak biasa dan melompat kalau terhalang block.",
        TextSize = 13, TextColor3 = P.tan, TextYAlignment = Enum.TextYAlignment.Top,
    })
end

----------------------------------------------------------------------
-- HALAMAN: Fishing
----------------------------------------------------------------------
local function BuildFishing(page)
    local info = Card(page, 78)
    local infoLabel = Text(info, {
        Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 1, -16),
        Text = "", TextSize = 16, TextYAlignment = Enum.TextYAlignment.Top,
    })
    local function Update()
        infoLabel.Text = string.format("Status: %s\nHook %d   Tangkapan %d   Lolos %d   Lempar ulang %d",
            Fish.status, Fish.hooks, Fish.caught, Fish.lost, Fish.recasts)
    end
    Update()
    task.spawn(function()
        while page.Parent do
            task.wait(0.4)
            if page.Visible and win.Visible then
                pcall(Update)
            end
        end
    end)

    Section(page, "Auto Fishing")
    SwitchCard(page, "Auto Fishing", "Hook, lawan ikan, lempar ulang.",
        Features.fishing.get, function(on) SetFeature("fishing", on) end)
    SwitchCard(page, "Lempar ulang", "Klik titik lemparan terakhir.",
        function() return Config.fishRecast end,
        function(on)
            Config.fishRecast = on
            SaveConfig()
        end)
    InputCard(page, "Jeda lempar ulang", "Detik setelah ikan selesai.", Config.fishRecastDelay, function(text, box)
        local value = tonumber(text)
        if value and value >= 0.5 and value <= 30 then
            Config.fishRecastDelay = value
            SaveConfig()
        else
            Notify("Isi angka 0.5 sampai 30.")
        end
        box.Text = tostring(Config.fishRecastDelay)
    end)
    InputCard(page, "Batas coba lempar ulang", "Detik. Kalau gagal terus (dialog/kamera), bot coba lagi tiap 0.4 dtk sampai batas ini.",
        Config.fishRecastTimeout, function(text, box)
        local value = tonumber(text)
        if value and value >= 3 and value <= 60 then
            Config.fishRecastTimeout = value
            SaveConfig()
        else
            Notify("Isi angka 3 sampai 60.")
        end
        box.Text = tostring(Config.fishRecastTimeout)
    end)
    InputCard(page, "Reaksi HOOK", "Jeda acak min-maks, contoh 0.25-0.6.",
        Config.fishReactMin .. "-" .. Config.fishReactMax, function(text, box)
            local lo, hi = tostring(text):match("^%s*([%d%.]+)%s*[-,%s]%s*([%d%.]+)%s*$")
            lo, hi = tonumber(lo), tonumber(hi)
            if lo and hi and lo >= 0.1 and hi >= lo and hi <= 1.5 then
                Config.fishReactMin, Config.fishReactMax = lo, hi
                SaveConfig()
            else
                Notify("Isi seperti 0.25-0.6.")
            end
            box.Text = Config.fishReactMin .. "-" .. Config.fishReactMax
        end)
    Section(page, "Catatan")
    local note = Card(page, 78)
    Text(note, {
        Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 1, -16),
        Text = "Pilih pancing dan lempar sendiri sekali ke air. Setelah itu bot yang menekan HOOK, "
            .. "menahan Space selama pertarungan, dan mengulang.",
        TextSize = 13, TextColor3 = P.tan, TextYAlignment = Enum.TextYAlignment.Top,
    })
end

NewTab("profile", "Profil", 1)
NewTab("walk", "Click Walk", 2)
NewTab("fishing", "Fishing", 3)
local function Safe(name, builder)
    local page = NewPage(name)
    local ok, err = pcall(builder, page)
    if not ok then
        warn("[PeexHubs] halaman " .. name .. ": " .. tostring(err))
        Text(page, {
            Size = UDim2.new(1, 0, 0, 80),
            Text = "Halaman gagal dimuat: " .. tostring(err),
            TextSize = 14,
            TextColor3 = P.mint,
        })
    end
end
Safe("profile", BuildProfile)
Safe("walk", BuildWalk)
Safe("fishing", BuildFishing)
SwitchTab("profile")

----------------------------------------------------------------------
-- Buka / tutup + tombol melayang
----------------------------------------------------------------------
local function Toggle()
    win.Visible = not win.Visible
    if win.Visible then
        RefreshAll()
    end
end
API.toggle = Toggle
closeButton.Activated:Connect(function()
    win.Visible = false
end)

do
    local launcher = New("TextButton", {
        Name = "Launcher",
        AnchorPoint = Vector2.new(0, 0.5),
        Position = UDim2.new(0, 12, 0.5, 0),
        Size = UDim2.fromOffset(44, 44),
        BackgroundColor3 = P.purple,
        Text = "P",
        FontFace = FONT,
        TextSize = 24,
        TextColor3 = P.cream,
        AutoButtonColor = false,
    }, gui)
    Corner(launcher, 10)
    Stroke(launcher, P.magenta, 3)
    local dragging, moved, dragStart, startPos = false, false, nil, nil
    launcher.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging, moved, dragStart, startPos = true, false, input.Position, launcher.Position
            input.Changed:Connect(function()
                if input.UserInputState == Enum.UserInputState.End then
                    dragging = false
                    if not moved then
                        Toggle()
                    end
                end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            if delta.Magnitude > 6 then
                moved = true
            end
            if moved then
                launcher.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
            end
        end
    end)
end

UIS.InputBegan:Connect(function(input, processed)
    if not processed and input.KeyCode == Enum.KeyCode.P and UIS:GetFocusedTextBox() == nil then
        Toggle()
    end
end)

win.Visible = true
genv.PeexHubsGB7 = API
print("[PeexHubs] " .. VERSION .. " dimuat")
Notify("PeexHubs " .. VERSION .. " siap. Tombol P untuk buka/tutup menu.")
end

local ok, err = xpcall(Main, debug.traceback)
if not ok then
    genv.PeexHubsGB7 = nil
    warn("[PeexHubs] error: " .. tostring(err))
    pcall(function()
        local errGui = Instance.new("ScreenGui")
        errGui.Name = "PeexHubError"
        errGui.ResetOnSpawn = false
        errGui.DisplayOrder = 100
        errGui.Parent = Player:WaitForChild("PlayerGui")
        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, -20, 0, 160)
        label.Position = UDim2.fromOffset(10, 10)
        label.BackgroundColor3 = Color3.fromRGB(100, 20, 123)
        label.TextColor3 = Color3.fromRGB(255, 245, 255)
        label.TextSize = 14
        label.TextWrapped = true
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.TextYAlignment = Enum.TextYAlignment.Top
        label.Text = "PeexHubs error:\n" .. tostring(err)
        label.Parent = errGui
        task.delay(30, function()
            errGui:Destroy()
        end)
    end)
end
