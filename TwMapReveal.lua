local addon = CreateFrame("Frame")
local initialized = false
local hooked = false
local originalWorldMapUpdate = nil
local optionsFrame = nil
local enableCheckbox = nil
local darknessSlider = nil
local darknessValueText = nil

local function Print(msg)
  if DEFAULT_CHAT_FRAME then
    DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99TwMapReveal|r: " .. msg)
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
  local _, _, textureName, textureWidth, textureHeight, offsetX, offsetY =
    string.find(entry, "^([^:]+):([^:]+):([^:]+):([^:]+):([^:]+)$")

  if not textureName then
    return nil
  end

  return textureName, textureWidth + 0, textureHeight + 0, offsetX + 0, offsetY + 0
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

local errata = {
  ["Interface\\WorldMap\\Tirisfal\\BRIGHTWATERLAKE"] = { offsetX = { 587, 584 } },
  ["Interface\\WorldMap\\Silverpine\\BERENSPERIL"] = { offsetY = { 417, 415 } },
}

local function DrawRevealedOverlays()
  local mapFileName = GetMapInfo()
  if not mapFileName then return end

  local overlayData = TwMapReveal_MapData
  if not overlayData then return end

  local zoneData = overlayData[mapFileName]
  if not zoneData then return end

  local unexploredTint = GetUnexploredTint()
  local knownOverlays = {}
  local numKnown = GetNumMapOverlays()
  local n
  for n = 1, numKnown do
    local knownTexture = GetMapOverlayInfo(n)
    if knownTexture then
      knownOverlays[knownTexture] = true
    end
  end

  local prefix = "Interface\\WorldMap\\" .. mapFileName .. "\\"
  local textureCount = 0

  local i
  for i = 1, table.getn(zoneData) do
    local textureName, textureWidth, textureHeight, offsetX, offsetY = ParseOverlayEntry(zoneData[i])
    if textureName then
      local fullTextureName = prefix .. textureName

      if errata[fullTextureName] and errata[fullTextureName].offsetX and errata[fullTextureName].offsetX[1] == offsetX then
        offsetX = errata[fullTextureName].offsetX[2]
      end
      if errata[fullTextureName] and errata[fullTextureName].offsetY and errata[fullTextureName].offsetY[1] == offsetY then
        offsetY = errata[fullTextureName].offsetY[2]
      end

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
          if knownOverlays[fullTextureName] then
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
  optionsFrame:SetHeight(190)
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

  darknessSlider = CreateFrame("Slider", "TwMapRevealDarknessSlider", optionsFrame, "OptionsSliderTemplate")
  darknessSlider:SetPoint("TOPLEFT", optionsFrame, "TOPLEFT", 24, -92)
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
  ToggleOptionsWindow()
end

SLASH_TWMAPREVEAL1 = "/twmr"
SlashCmdList["TWMAPREVEAL"] = HandleSlash

addon:RegisterEvent("PLAYER_LOGIN")
addon:SetScript("OnEvent", function()
  if initialized then return end
  initialized = true

  EnsureDB()

  if not TwMapReveal_MapData then
    Print("No map data loaded. Check that MapData.lua is listed in the TOC.")
    return
  end

  HookWorldMap()
  CreateOptionsWindow()
  RefreshMapNow()
  Print("Loaded. Type /twmr")
end)
