TwMapReveal
===========

TwMapReveal is a Turtle WoW addon for the 1.12 client that reveals unexplored
areas on the world map.

Features
--------
- Reveals hidden world map areas.
- Keeps explored areas full color.
- Tints unexplored revealed areas darker (adjustable).
- Simple options window opened with /twmr.
- Uses authoritative map overlay geometry generated from Turtle WoW client data.
- Uses live discovered overlay geometry when available from the game client.

Requirements
------------
- Turtle WoW (WoW 1.12 client API)
- No required in-game addon dependencies.

Installation
------------
1. Copy the folder "TwMapReveal" into:
   Interface\AddOns\
2. Restart the game or run /reload.
3. Enable "TwMapReveal" in the AddOns menu if needed.

Usage
-----
- Type /twmr to open or close the options window.
- Type /twmr debug to capture a debug snapshot in SavedVariables.
- Type /twmr debug clear to clear stored debug snapshots.

Options
-------
- Enable: Turns map reveal on/off.
- Debug Chat Output: Enables/disables general debug messages in chat.
- Unexplored Darkness: Slider from 0% to 50% darker.
  - 0% = same brightness as explored tiles
  - 50% = maximum darkening

Saved Variables
---------------
- TwMapRevealDB.enabled
- TwMapRevealDB.darknessPercent
- TwMapRevealDB.debugChat
- TwMapRevealDB.debug.logs
- TwMapRevealDB.debug.nextId

Developer Data Pipeline
-----------------------
- Runtime data files:
  - MapData.lua
  - CalibrationData.lua
- Regeneration script:
  - tools\GenerateAuthoritativeMapData.ps1
- Script output includes:
  - MapData.lua
  - CalibrationData.lua
  - CoverageReport.txt

Changelog
---------
v1.1.0 (2026-03-29)
- Replaced guessed overlay placement with authoritative geometry data.
- Added generated calibration data for all supported map overlays.
- Updated rendering precedence: live discovered geometry first, then generated data.
- Removed runtime guessed-placement fallback path.
- Added options checkbox to enable/disable general debug chat output.
- Added generation script and coverage report pipeline.
