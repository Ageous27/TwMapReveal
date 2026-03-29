local addon = CreateFrame("Frame")
local initialized = false
local hooked = false
local originalWorldMapUpdate = nil
local optionsFrame = nil
local enableCheckbox = nil
local debugCheckbox = nil
local darknessSlider = nil
local darknessValueText = nil
local pfuiConflictHandled = false

local function Print(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99TwMapReveal|r: " .. msg)
  end
end

local function IsDebugChatEnabled()
  return TwMapRevealDB and TwMapRevealDB.debugChat == 1
end

local function DebugPrint(msg)
  if IsDebugChatEnabled() then
    Print(msg)
  end
end

local function Trim(s)
  if not s then return "" end
  s = string.gsub(s, "^%s+", "")
  s = string.gsub(s, "%s+$", "")
  return s
end

local function Clamp(value, minValue, maxValue)
  if value < minValue then return minValue end
  if value > maxValue then return maxValue end
  return value
end

local function EnsureDB()
  if type(TwMapRevealDB) ~= "table" then
    TwMapRevealDB = {}
  end
  if TwMapRevealDB.enabled == nil then
    TwMapRevealDB.enabled = 1
  end
  if type(TwMapRevealDB.darknessPercent) ~= "number" then
    TwMapRevealDB.darknessPercent = 30
  end
  TwMapRevealDB.darknessPercent = math.floor(Clamp(TwMapRevealDB.darknessPercent, 0, 50) + 0.5)
  if TwMapRevealDB.debugChat == nil then
    TwMapRevealDB.debugChat = 0
  end
  TwMapRevealDB.debugChat = (TwMapRevealDB.debugChat == 1) and 1 or 0

  if type(TwMapRevealDB.debug) ~= "table" then
    TwMapRevealDB.debug = {}
  end
  if type(TwMapRevealDB.debug.logs) ~= "table" then
    TwMapRevealDB.debug.logs = {}
  end
  if type(TwMapRevealDB.debug.nextId) ~= "number" then
    TwMapRevealDB.debug.nextId = 1
  end
end

local function IsPfUIMapRevealEnabled()
  if type(C) == "table"
    and type(C.appearance) == "table"
    and type(C.appearance.worldmap) == "table"
    and C.appearance.worldmap.mapreveal == "1" then
    return true
  end

  if type(pfUI_config) == "table"
    and type(pfUI_config.appearance) == "table"
    and type(pfUI_config.appearance.worldmap) == "table"
    and pfUI_config.appearance.worldmap.mapreveal == "1" then
    return true
  end

  return false
end

local function DisablePfUIMapReveal()
  if pfuiConflictHandled then return end
  pfuiConflictHandled = true

  if not IsPfUIMapRevealEnabled() then
    return
  end

  if type(C) == "table"
    and type(C.appearance) == "table"
    and type(C.appearance.worldmap) == "table" then
    C.appearance.worldmap.mapreveal = "0"
  end

  if type(pfUI_config) == "table"
    and type(pfUI_config.appearance) == "table"
    and type(pfUI_config.appearance.worldmap) == "table" then
    pfUI_config.appearance.worldmap.mapreveal = "0"
  end

  if type(pfUI) == "table"
    and type(pfUI.mapreveal) == "table"
    and type(pfUI.mapreveal.UpdateConfig) == "function" then
    pfUI.mapreveal:UpdateConfig()
  end

  Print("Disabled pfUI map reveal to prevent overlap with TwMapReveal.")
end

local function GetDarknessPercent()
  if not TwMapRevealDB then
    return 30
  end
  return TwMapRevealDB.darknessPercent or 30
end

local function GetUnexploredTint()
  return 1 - (GetDarknessPercent() / 100)
end

local function ParseOverlayEntry(entry)
  local _, _, textureName, textureWidth, textureHeight, offsetX, offsetY, mapPointX, mapPointY =
    string.find(entry, "^([^:]+):([^:]+):([^:]+):([^:]+):([^:]+):?([^:]*):?([^:]*)$")

  if not textureName then
    return nil
  end

  mapPointX = (mapPointX and mapPointX ~= "") and (mapPointX + 0) or 0
  mapPointY = (mapPointY and mapPointY ~= "") and (mapPointY + 0) or 0

  return textureName, textureWidth + 0, textureHeight + 0, offsetX + 0, offsetY + 0, mapPointX, mapPointY
end

local function NormalizeMapName(name)
  return Trim(name or "")
end

local function GetOverlayTexture(index)
  local name = "WorldMapOverlay" .. index
  local tex = getglobal(name)
  if tex then
    return tex
  end

  tex = WorldMapDetailFrame:CreateTexture(name, "ARTWORK")
  if index > NUM_WORLDMAP_OVERLAYS then
    NUM_WORLDMAP_OVERLAYS = index
  end
  return tex
end

local function HideAllOverlayTextures()
  local i
  for i = 1, NUM_WORLDMAP_OVERLAYS do
    local tex = getglobal("WorldMapOverlay" .. i)
    if tex then
      tex:Hide()
    end
  end
end

local CALIBRATED_OVERLAY_GEOMETRY = {}
if type(TwMapReveal_CalibrationData) == "table" then
  CALIBRATED_OVERLAY_GEOMETRY = TwMapReveal_CalibrationData
end
local warnedMissingGeometry = {}

local function NormalizeLookupKey(s)
  s = string.lower(tostring(s or ""))
  s = string.gsub(s, "[%s%-_']", "")
  return s
end

local function GetTextureBaseName(texturePath)
  if not texturePath then return nil end
  return string.gsub(tostring(texturePath), "^.*\\", "")
end

local function ApplyOverlayGeometryOverride(mapFileName, textureName, textureWidth, textureHeight, offsetX, offsetY)
  local zoneOverrides = CALIBRATED_OVERLAY_GEOMETRY[mapFileName]
  if zoneOverrides and zoneOverrides[textureName] then
    local o = zoneOverrides[textureName]
    return o.width, o.height, o.offsetX, o.offsetY, true
  end

  return textureWidth, textureHeight, offsetX, offsetY, false
end

local function GetKnownOverlayData(mapFileName)
  local knownOverlays = {}
  local knownGeometry = {}
  local prefix = "Interface\\WorldMap\\" .. mapFileName .. "\\"
  local numKnown = GetNumMapOverlays()
  local n
  for n = 1, numKnown do
    local knownTexture, knownWidth, knownHeight, knownOffsetX, knownOffsetY = GetMapOverlayInfo(n)
    if knownTexture then
      local fullTextureName = knownTexture
      if not string.find(fullTextureName, "Interface\\WorldMap\\", 1, true) then
        fullTextureName = prefix .. knownTexture
      end
      local shortTextureName = GetTextureBaseName(fullTextureName)
      local geometry = {
        width = knownWidth or 0,
        height = knownHeight or 0,
        offsetX = knownOffsetX or 0,
        offsetY = knownOffsetY or 0,
      }

      knownOverlays[knownTexture] = true
      knownOverlays[fullTextureName] = true
      knownOverlays[shortTextureName] = true

      knownGeometry[knownTexture] = geometry
      knownGeometry[fullTextureName] = geometry
      knownGeometry[shortTextureName] = geometry
    end
  end
  return knownOverlays, knownGeometry
end

local function DrawRevealedOverlays()
  local mapFileName = NormalizeMapName(GetMapInfo())
  if not mapFileName then return end
  if mapFileName == "" then return end

  local overlayData = TwMapReveal_MapData
  if not overlayData then return end

  local zoneData = overlayData[mapFileName]
  if not zoneData then return end

  local unexploredTint = GetUnexploredTint()
  local prefix = "Interface\\WorldMap\\" .. mapFileName .. "\\"
  local knownOverlays, knownGeometry = GetKnownOverlayData(mapFileName)
  local skippedMissingGeometry = 0

  local textureCount = 0
  local i
  for i = 1, table.getn(zoneData) do
    local textureName, textureWidth, textureHeight, offsetX, offsetY = ParseOverlayEntry(zoneData[i])
    if textureName then
      local fullTextureName = prefix .. textureName
      local isKnown = knownOverlays[fullTextureName] == true or knownOverlays[textureName] == true
      local hasLiveGeometry = false
      local liveGeometry = knownGeometry[fullTextureName] or knownGeometry[textureName]
      if liveGeometry then
        textureWidth = liveGeometry.width
        textureHeight = liveGeometry.height
        offsetX = liveGeometry.offsetX
        offsetY = liveGeometry.offsetY
        hasLiveGeometry = true
      end

      local hasCalibration = false
      if not hasLiveGeometry then
        textureWidth, textureHeight, offsetX, offsetY, hasCalibration =
          ApplyOverlayGeometryOverride(mapFileName, textureName, textureWidth, textureHeight, offsetX, offsetY)
      end

      if not hasLiveGeometry and not hasCalibration then
        skippedMissingGeometry = skippedMissingGeometry + 1
      else
        local numTexturesHorz = math.ceil(textureWidth / 256)
        local numTexturesVert = math.ceil(textureHeight / 256)

        local j, k
        for j = 1, numTexturesVert do
          local texturePixelHeight
          local textureFileHeight
          if j < numTexturesVert then
            texturePixelHeight = 256
            textureFileHeight = 256
          else
            texturePixelHeight = math.mod(textureHeight, 256)
            if texturePixelHeight == 0 then
              texturePixelHeight = 256
            end
            textureFileHeight = 16
            while textureFileHeight < texturePixelHeight do
              textureFileHeight = textureFileHeight * 2
            end
          end

          for k = 1, numTexturesHorz do
            textureCount = textureCount + 1
            local tex = GetOverlayTexture(textureCount)

            local texturePixelWidth
            local textureFileWidth
            if k < numTexturesHorz then
              texturePixelWidth = 256
              textureFileWidth = 256
            else
              texturePixelWidth = math.mod(textureWidth, 256)
              if texturePixelWidth == 0 then
                texturePixelWidth = 256
              end
              textureFileWidth = 16
              while textureFileWidth < texturePixelWidth do
                textureFileWidth = textureFileWidth * 2
              end
            end

            tex:SetTexture(fullTextureName .. (((j - 1) * numTexturesHorz) + k))
            tex:SetWidth(texturePixelWidth)
            tex:SetHeight(texturePixelHeight)
            tex:SetTexCoord(0, texturePixelWidth / textureFileWidth, 0, texturePixelHeight / textureFileHeight)
            tex:ClearAllPoints()
            tex:SetPoint("TOPLEFT", "WorldMapDetailFrame", "TOPLEFT", offsetX + (256 * (k - 1)), -(offsetY + (256 * (j - 1))))
            if isKnown then
              tex:SetVertexColor(1, 1, 1, 1)
            else
              tex:SetVertexColor(unexploredTint, unexploredTint, unexploredTint, 1)
            end
            tex:Show()
          end
        end
      end
    end
  end

  if skippedMissingGeometry > 0 and not warnedMissingGeometry[mapFileName] then
    warnedMissingGeometry[mapFileName] = true
    DebugPrint("Missing authoritative geometry in " .. mapFileName .. ": skipped " .. skippedMissingGeometry .. " overlays.")
  end
end

local function BuildKeyMatches(mapFileName)
  local matches = {}
  local overlayData = TwMapReveal_MapData
  if type(overlayData) ~= "table" then
    return matches
  end

  local target = NormalizeLookupKey(mapFileName)
  if target == "" then
    return matches
  end

  local key
  for key in pairs(overlayData) do
    if NormalizeLookupKey(key) == target then
      table.insert(matches, key)
      if table.getn(matches) >= 6 then
        break
      end
    end
  end

  return matches
end

local function BuildMapDataPreview(zoneData, maxItems)
  local preview = {}
  if type(zoneData) ~= "table" then
    return preview
  end

  local count = math.min(table.getn(zoneData), maxItems or 8)
  local i
  for i = 1, count do
    table.insert(preview, zoneData[i])
  end
  return preview
end

local function BuildKnownOverlayPreview(maxItems)
  local preview = {}
  local count = GetNumMapOverlays()
  local i
  for i = 1, math.min(count, maxItems or 40) do
    local textureName, textureWidth, textureHeight, offsetX, offsetY, mapPointX, mapPointY = GetMapOverlayInfo(i)
    table.insert(preview, {
      i = i,
      textureName = tostring(textureName),
      textureWidth = textureWidth or 0,
      textureHeight = textureHeight or 0,
      offsetX = offsetX or 0,
      offsetY = offsetY or 0,
      mapPointX = mapPointX or 0,
      mapPointY = mapPointY or 0,
    })
  end
  return preview
end

local function BuildDrawPreview(mapFileName, zoneData, maxItems)
  local preview = {}
  if type(zoneData) ~= "table" then
    return preview
  end

  local prefix = "Interface\\WorldMap\\" .. mapFileName .. "\\"
  local knownOverlays, knownGeometry = GetKnownOverlayData(mapFileName)
  local count = math.min(table.getn(zoneData), maxItems or 20)
  local i
  for i = 1, count do
    local textureName, textureWidth, textureHeight, offsetX, offsetY = ParseOverlayEntry(zoneData[i])
    if textureName then
      local fullTextureName = prefix .. textureName
      local isKnown = knownOverlays[fullTextureName] == true or knownOverlays[textureName] == true
      local hasLiveGeometry = false
      local liveGeometry = knownGeometry[fullTextureName] or knownGeometry[textureName]
      if liveGeometry then
        textureWidth = liveGeometry.width
        textureHeight = liveGeometry.height
        offsetX = liveGeometry.offsetX
        offsetY = liveGeometry.offsetY
        hasLiveGeometry = true
      end

      local hasCalibration = false
      if not hasLiveGeometry then
        textureWidth, textureHeight, offsetX, offsetY, hasCalibration =
          ApplyOverlayGeometryOverride(mapFileName, textureName, textureWidth, textureHeight, offsetX, offsetY)
      end

      local skippedByFallback = (not hasCalibration and not hasLiveGeometry) and 1 or 0
      local geometrySource = "missing"
      if hasLiveGeometry then
        geometrySource = "live"
      elseif hasCalibration then
        geometrySource = "calibrated"
      end

      table.insert(preview, {
        i = i,
        textureName = textureName,
        fullTextureName = fullTextureName,
        textureWidth = textureWidth,
        textureHeight = textureHeight,
        offsetX = offsetX,
        offsetY = offsetY,
        tilesX = math.ceil(textureWidth / 256),
        tilesY = math.ceil(textureHeight / 256),
        isKnown = isKnown and 1 or 0,
        hasCalibration = hasCalibration and 1 or 0,
        skippedByFallback = skippedByFallback,
        geometrySource = geometrySource,
      })
    end
  end
  return preview
end

local function CaptureDebugSnapshot()
  local mapFileName = NormalizeMapName(GetMapInfo())
  local overlayData = TwMapReveal_MapData
  local zoneData = nil
  if type(overlayData) == "table" then
    zoneData = overlayData[mapFileName]
  end

  local id = TwMapRevealDB.debug.nextId
  TwMapRevealDB.debug.nextId = id + 1

  local snapshot = {
    id = id,
    time = date("%Y-%m-%d %H:%M:%S"),
    mapInfo = mapFileName,
    continent = GetCurrentMapContinent() or 0,
    zone = GetCurrentMapZone() or 0,
    realZone = tostring(GetRealZoneText() or ""),
    subZone = tostring(GetSubZoneText() or ""),
    worldMapVisible = (WorldMapFrame and WorldMapFrame:IsVisible()) and 1 or 0,
    twmrEnabled = (TwMapRevealDB.enabled == 1) and 1 or 0,
    debugChatEnabled = (TwMapRevealDB.debugChat == 1) and 1 or 0,
    darknessPercent = GetDarknessPercent(),
    mapDataEntryCount = (type(zoneData) == "table") and table.getn(zoneData) or 0,
    keyMatches = BuildKeyMatches(mapFileName),
    mapDataPreview = BuildMapDataPreview(zoneData, 12),
    knownOverlayCount = GetNumMapOverlays() or 0,
    knownOverlayPreview = BuildKnownOverlayPreview(40),
    drawPreview = BuildDrawPreview(mapFileName, zoneData, 24),
    addonState = {
      pfUI = IsAddOnLoaded("pfUI") and 1 or 0,
      ModernMapMarkers = IsAddOnLoaded("ModernMapMarkers") and 1 or 0,
      Cartographer = IsAddOnLoaded("Cartographer") and 1 or 0,
      MetaMap = METAMAP_TITLE and 1 or 0,
    },
    pfuiMapReveal = {
      C = tostring(C and C.appearance and C.appearance.worldmap and C.appearance.worldmap.mapreveal),
      config = tostring(pfUI_config and pfUI_config.appearance and pfUI_config.appearance.worldmap and pfUI_config.appearance.worldmap.mapreveal),
    },
  }

  table.insert(TwMapRevealDB.debug.logs, 1, snapshot)
  while table.getn(TwMapRevealDB.debug.logs) > 30 do
    table.remove(TwMapRevealDB.debug.logs)
  end

  return snapshot
end

local function RunDebugCapture()
  if not TwMapRevealDB or not TwMapRevealDB.debug then
    EnsureDB()
  end

  local snapshot = CaptureDebugSnapshot()
  Print("Debug snapshot #" .. snapshot.id .. " saved for map '" .. tostring(snapshot.mapInfo) .. "'.")
  Print("MapData entries: " .. snapshot.mapDataEntryCount .. ", Known overlays: " .. snapshot.knownOverlayCount)
end

local function ClearDebugLogs()
  if not TwMapRevealDB or not TwMapRevealDB.debug then
    EnsureDB()
  end
  TwMapRevealDB.debug.logs = {}
  TwMapRevealDB.debug.nextId = 1
  Print("Debug logs cleared.")
end

local function RefreshMapNow()
  if WorldMapFrame and WorldMapFrame:IsVisible() then
    WorldMapFrame_Update()
  end
end

local function HookWorldMap()
  if hooked then return end
  if type(WorldMapFrame_Update) ~= "function" then
    Print("World map API unavailable, addon not initialized.")
    return
  end

  originalWorldMapUpdate = WorldMapFrame_Update
  WorldMapFrame_Update = function()
    HideAllOverlayTextures()
    originalWorldMapUpdate()
    if TwMapRevealDB and TwMapRevealDB.enabled == 1 then
      DrawRevealedOverlays()
    end
  end

  hooked = true
end

local function SetEnabled(enabled)
  if enabled then
    TwMapRevealDB.enabled = 1
    Print("Enabled.")
  else
    TwMapRevealDB.enabled = 0
    Print("Disabled.")
  end
  RefreshMapNow()
end

local function SetDebugChatEnabled(enabled)
  TwMapRevealDB.debugChat = enabled and 1 or 0
  if enabled then
    Print("Debug chat output enabled.")
  else
    Print("Debug chat output disabled.")
  end
end

local function SetDarknessPercent(value)
  local clamped = math.floor(Clamp(value, 0, 50) + 0.5)
  TwMapRevealDB.darknessPercent = clamped
  if darknessValueText then
    darknessValueText:SetText(clamped .. "% darker")
  end
  RefreshMapNow()
end

local function SyncOptionsWindow()
  if not optionsFrame then return end

  if enableCheckbox then
    enableCheckbox:SetChecked(TwMapRevealDB.enabled == 1)
  end

  if debugCheckbox then
    debugCheckbox:SetChecked(TwMapRevealDB.debugChat == 1)
  end

  if darknessSlider then
    darknessSlider._syncing = true
    darknessSlider:SetValue(GetDarknessPercent())
    darknessSlider._syncing = nil
  end

  if darknessValueText then
    darknessValueText:SetText(GetDarknessPercent() .. "% darker")
  end
end

local function CreateOptionsWindow()
  if optionsFrame then return end

  optionsFrame = CreateFrame("Frame", "TwMapRevealOptionsFrame", UIParent)
  optionsFrame:SetWidth(340)
  optionsFrame:SetHeight(220)
  optionsFrame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  optionsFrame:SetFrameStrata("DIALOG")
  optionsFrame:EnableMouse(true)
  optionsFrame:SetMovable(true)
  optionsFrame:RegisterForDrag("LeftButton")
  optionsFrame:SetScript("OnDragStart", function() this:StartMoving() end)
  optionsFrame:SetScript("OnDragStop", function() this:StopMovingOrSizing() end)
  optionsFrame:SetBackdrop({
    bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 32,
    edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
  })

  local title = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", optionsFrame, "TOP", 0, -16)
  title:SetText("TwMapReveal")

  local closeButton = CreateFrame("Button", nil, optionsFrame, "UIPanelCloseButton")
  closeButton:SetPoint("TOPRIGHT", optionsFrame, "TOPRIGHT", -4, -4)

  local subtitle = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  subtitle:SetPoint("TOP", title, "BOTTOM", 0, -6)
  subtitle:SetText("World map reveal settings")

  enableCheckbox = CreateFrame("CheckButton", "TwMapRevealEnableCheckbox", optionsFrame, "UICheckButtonTemplate")
  enableCheckbox:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -48)
  getglobal("TwMapRevealEnableCheckboxText"):SetText("Enable")
  enableCheckbox:SetScript("OnClick", function()
    SetEnabled(this:GetChecked() and true or false)
  end)

  debugCheckbox = CreateFrame("CheckButton", "TwMapRevealDebugCheckbox", optionsFrame, "UICheckButtonTemplate")
  debugCheckbox:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 20, -72)
  getglobal("TwMapRevealDebugCheckboxText"):SetText("Debug Chat Output")
  debugCheckbox:SetScript("OnClick", function()
    SetDebugChatEnabled(this:GetChecked() and true or false)
  end)

  darknessSlider = CreateFrame("Slider", "TwMapRevealDarknessSlider", optionsFrame, "OptionsSliderTemplate")
  darknessSlider:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 24, -126)
  darknessSlider:SetWidth(280)
  darknessSlider:SetMinMaxValues(0, 50)
  darknessSlider:SetValueStep(1)
  getglobal("TwMapRevealDarknessSliderLow"):SetText("0%")
  getglobal("TwMapRevealDarknessSliderHigh"):SetText("50%")
  getglobal("TwMapRevealDarknessSliderText"):SetText("Unexplored Darkness")
  darknessSlider:SetScript("OnValueChanged", function()
    if this._syncing then return end
    SetDarknessPercent(this:GetValue())
  end)

  darknessValueText = optionsFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  darknessValueText:SetPoint("TOP", darknessSlider, "BOTTOM", 0, -4)

  optionsFrame:Hide()
  SyncOptionsWindow()
end

local function ToggleOptionsWindow()
  if not optionsFrame then
    CreateOptionsWindow()
  end

  if optionsFrame:IsVisible() then
    optionsFrame:Hide()
  else
    SyncOptionsWindow()
    optionsFrame:Show()
  end
end

local function HandleSlash(msg)
  local command = string.lower(Trim(msg or ""))

  if command == "" then
    ToggleOptionsWindow()
    return
  end

  if command == "debug" then
    RunDebugCapture()
    return
  end

  if command == "debug clear" then
    ClearDebugLogs()
    return
  end

  if command == "help" then
    Print("Commands: /twmr, /twmr debug, /twmr debug clear")
    return
  end

  Print("Unknown command. Type /twmr help")
end

SLASH_TWMAPREVEAL1 = "/twmr"
SlashCmdList["TWMAPREVEAL"] = HandleSlash

addon:RegisterEvent("PLAYER_LOGIN")
addon:SetScript("OnEvent", function()
  if initialized then return end
  initialized = true

  EnsureDB()
  DisablePfUIMapReveal()

  if not TwMapReveal_MapData then
    Print("No map data loaded. Check that MapData.lua is listed in the TOC.")
    return
  end

  HookWorldMap()
  CreateOptionsWindow()
  RefreshMapNow()
  Print("Loaded. /twmr opens options, /twmr debug saves diagnostics.")
end)
