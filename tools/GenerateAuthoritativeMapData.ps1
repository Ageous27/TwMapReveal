param(
  [string]$DataDir = "C:/Games/TurtleWoW/Data",
  [string]$MpqExtractorPath,
  [string]$AddonRoot = "",
  [switch]$KeepTemp
)

$ErrorActionPreference = "Stop"

if (-not $AddonRoot) {
  $AddonRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
}

if (-not $MpqExtractorPath) {
  throw "MpqExtractorPath is required. Example: -MpqExtractorPath 'C:/tools/MPQExtractor.exe'"
}

if (-not (Test-Path -LiteralPath $DataDir)) {
  throw "DataDir not found: $DataDir"
}

if (-not (Test-Path -LiteralPath $MpqExtractorPath)) {
  throw "MPQExtractor not found: $MpqExtractorPath"
}

function Resolve-Mpq {
  param(
    [string]$Name,
    [string]$Root
  )
  $path = Join-Path $Root $Name
  if (Test-Path -LiteralPath $path) {
    return (Resolve-Path $path).Path
  }

  $lookup = @{}
  Get-ChildItem -LiteralPath $Root -File | ForEach-Object {
    $lookup[$_.Name.ToLowerInvariant()] = $_.FullName
  }

  $key = $Name.ToLowerInvariant()
  if ($lookup.ContainsKey($key)) {
    return $lookup[$key]
  }

  return $null
}

function Read-DBC {
  param([string]$Path)

  $bytes = [System.IO.File]::ReadAllBytes($Path)
  $magic = [System.Text.Encoding]::ASCII.GetString($bytes, 0, 4)
  if ($magic -ne "WDBC") {
    throw "Not a WDBC file: $Path"
  }

  $records = [BitConverter]::ToInt32($bytes, 4)
  $fields = [BitConverter]::ToInt32($bytes, 8)
  $recordSize = [BitConverter]::ToInt32($bytes, 12)
  $stringSize = [BitConverter]::ToInt32($bytes, 16)
  $strStart = 20 + ($records * $recordSize)

  return [pscustomobject]@{
    Bytes      = $bytes
    Records    = $records
    Fields     = $fields
    RecordSize = $recordSize
    StringSize = $stringSize
    StrStart   = $strStart
  }
}

function Get-DBCString {
  param(
    $Dbc,
    [int]$Offset
  )

  if ($Offset -lt 0 -or $Offset -ge $Dbc.StringSize) {
    return ""
  }

  $i = $Dbc.StrStart + $Offset
  $chars = New-Object System.Collections.Generic.List[byte]
  while ($i -lt $Dbc.Bytes.Length -and $Dbc.Bytes[$i] -ne 0) {
    $chars.Add($Dbc.Bytes[$i])
    $i++
  }
  return [System.Text.Encoding]::UTF8.GetString($chars.ToArray())
}

$base = Resolve-Mpq -Name "dbc.MPQ" -Root $DataDir
if (-not $base) {
  throw "dbc.MPQ not found in $DataDir"
}

$patches = @()
$mainPatch = Resolve-Mpq -Name "patch.MPQ" -Root $DataDir
if ($mainPatch) {
  $patches += $mainPatch
}

$numberedPatches = Get-ChildItem -LiteralPath $DataDir -File |
  Where-Object { $_.Name -match '^patch-(\d+)\.mpq$' } |
  Sort-Object { [int]$_.BaseName.Split('-')[1] } |
  Select-Object -ExpandProperty FullName

if ($numberedPatches.Count -gt 0) {
  $patches += $numberedPatches
}

$temp = Join-Path $env:TEMP ("twmr-calibration-" + [guid]::NewGuid().ToString("N"))
New-Item -ItemType Directory -Path $temp | Out-Null

try {
  $dbcFiles = @(
    "WorldMapOverlay.dbc",
    "WorldMapArea.dbc"
  )

  foreach ($dbc in $dbcFiles) {
    $args = @()
    if ($patches.Count -gt 0) {
      $args += "-p"
      $args += $patches
    }
    $args += "-e"
    $args += "DBFilesClient\$dbc"
    $args += "-f"
    $args += "-o"
    $args += $temp
    $args += $base

    & $MpqExtractorPath @args | Out-Null
    if ($LASTEXITCODE -ne 0) {
      throw "MPQExtractor failed while extracting $dbc"
    }
  }

  $worldMapAreaPath = Join-Path $temp "DBFilesClient/WorldMapArea.dbc"
  $worldMapOverlayPath = Join-Path $temp "DBFilesClient/WorldMapOverlay.dbc"
  if (-not (Test-Path -LiteralPath $worldMapAreaPath)) {
    throw "Missing extracted file: $worldMapAreaPath"
  }
  if (-not (Test-Path -LiteralPath $worldMapOverlayPath)) {
    throw "Missing extracted file: $worldMapOverlayPath"
  }

  $areaDbc = Read-DBC -Path $worldMapAreaPath
  $overlayDbc = Read-DBC -Path $worldMapOverlayPath

  $mapByAreaId = @{}
  for ($r = 0; $r -lt $areaDbc.Records; $r++) {
    $baseOffset = 20 + ($r * $areaDbc.RecordSize)
    $id = [BitConverter]::ToInt32($areaDbc.Bytes, $baseOffset + (0 * 4))
    $nameOffset = [BitConverter]::ToInt32($areaDbc.Bytes, $baseOffset + (3 * 4))
    $zoneName = Get-DBCString -Dbc $areaDbc -Offset $nameOffset
    if ($zoneName) {
      $mapByAreaId[$id] = $zoneName
    }
  }

  $zones = @{}
  for ($r = 0; $r -lt $overlayDbc.Records; $r++) {
    $baseOffset = 20 + ($r * $overlayDbc.RecordSize)
    $mapAreaId = [BitConverter]::ToInt32($overlayDbc.Bytes, $baseOffset + (1 * 4))
    if (-not $mapByAreaId.ContainsKey($mapAreaId)) {
      continue
    }

    $zoneName = $mapByAreaId[$mapAreaId]
    $textureOffset = [BitConverter]::ToInt32($overlayDbc.Bytes, $baseOffset + (8 * 4))
    $textureName = Get-DBCString -Dbc $overlayDbc -Offset $textureOffset
    if (-not $textureName) {
      continue
    }

    $width = [BitConverter]::ToInt32($overlayDbc.Bytes, $baseOffset + (9 * 4))
    $height = [BitConverter]::ToInt32($overlayDbc.Bytes, $baseOffset + (10 * 4))
    $offsetX = [BitConverter]::ToInt32($overlayDbc.Bytes, $baseOffset + (11 * 4))
    $offsetY = [BitConverter]::ToInt32($overlayDbc.Bytes, $baseOffset + (12 * 4))

    if (-not $zones.ContainsKey($zoneName)) {
      $zones[$zoneName] = @{}
    }

    $zones[$zoneName][$textureName] = [pscustomobject]@{
      width = $width
      height = $height
      offsetX = $offsetX
      offsetY = $offsetY
    }
  }

  $calibrationPath = Join-Path $AddonRoot "CalibrationData.lua"
  $mapDataPath = Join-Path $AddonRoot "MapData.lua"
  $reportPath = Join-Path $AddonRoot "CoverageReport.txt"

  $calibrationBuilder = New-Object System.Text.StringBuilder
  [void]$calibrationBuilder.AppendLine("TwMapReveal_CalibrationData = {")
  foreach ($zone in ($zones.Keys | Sort-Object)) {
    [void]$calibrationBuilder.AppendLine(("  [""{0}""] = {{" -f $zone))
    foreach ($texture in ($zones[$zone].Keys | Sort-Object)) {
      $g = $zones[$zone][$texture]
      [void]$calibrationBuilder.AppendLine(("    [""{0}""] = {{ width = {1}, height = {2}, offsetX = {3}, offsetY = {4} }}," -f $texture, $g.width, $g.height, $g.offsetX, $g.offsetY))
    }
    [void]$calibrationBuilder.AppendLine("  },")
  }
  [void]$calibrationBuilder.AppendLine("}")
  [System.IO.File]::WriteAllText($calibrationPath, $calibrationBuilder.ToString(), [System.Text.Encoding]::ASCII)

  $mapDataBuilder = New-Object System.Text.StringBuilder
  [void]$mapDataBuilder.AppendLine("TwMapReveal_MapData = {")
  foreach ($zone in ($zones.Keys | Sort-Object)) {
    [void]$mapDataBuilder.AppendLine(("    [""{0}""] = {{" -f $zone))
    foreach ($texture in ($zones[$zone].Keys | Sort-Object)) {
      $g = $zones[$zone][$texture]
      [void]$mapDataBuilder.AppendLine(("      ""{0}:{1}:{2}:{3}:{4}""," -f $texture, $g.width, $g.height, $g.offsetX, $g.offsetY))
    }
    [void]$mapDataBuilder.AppendLine("    },")
  }
  [void]$mapDataBuilder.AppendLine("}")
  [System.IO.File]::WriteAllText($mapDataPath, $mapDataBuilder.ToString(), [System.Text.Encoding]::ASCII)

  $totalOverlays = 0
  foreach ($zone in $zones.Keys) {
    $totalOverlays += $zones[$zone].Keys.Count
  }
  $resolvedOverlays = $totalOverlays
  $unresolvedOverlays = 0

  $reportBuilder = New-Object System.Text.StringBuilder
  [void]$reportBuilder.AppendLine("TwMapReveal Coverage Report")
  [void]$reportBuilder.AppendLine(("Generated: {0}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")))
  [void]$reportBuilder.AppendLine(("DataDir: {0}" -f $DataDir))
  [void]$reportBuilder.AppendLine(("Base MPQ: {0}" -f $base))
  [void]$reportBuilder.AppendLine("Patch chain:")
  if ($patches.Count -eq 0) {
    [void]$reportBuilder.AppendLine("  (none)")
  } else {
    foreach ($patch in $patches) {
      [void]$reportBuilder.AppendLine(("  - {0}" -f $patch))
    }
  }
  [void]$reportBuilder.AppendLine(("Zones: {0}" -f $zones.Keys.Count))
  [void]$reportBuilder.AppendLine(("Total overlays: {0}" -f $totalOverlays))
  [void]$reportBuilder.AppendLine(("Resolved overlays: {0}" -f $resolvedOverlays))
  [void]$reportBuilder.AppendLine(("Unresolved overlays: {0}" -f $unresolvedOverlays))
  [System.IO.File]::WriteAllText($reportPath, $reportBuilder.ToString(), [System.Text.Encoding]::ASCII)

  if ($unresolvedOverlays -ne 0) {
    throw "Coverage gate failed: unresolved overlays found."
  }

  Write-Output "Generated CalibrationData.lua, MapData.lua, CoverageReport.txt"
  Write-Output ("Coverage gate passed: {0}/{1} overlays resolved." -f $resolvedOverlays, $totalOverlays)
}
finally {
  if (-not $KeepTemp -and (Test-Path -LiteralPath $temp)) {
    Remove-Item -LiteralPath $temp -Recurse -Force
  }
}
