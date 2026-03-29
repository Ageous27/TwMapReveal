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

Requirements
------------
- Turtle WoW (WoW 1.12 client API)

Installation
------------
1. Copy the folder "TwMapReveal" into:
   Interface\AddOns\
2. Restart the game or run /reload.
3. Enable "TwMapReveal" in the AddOns menu if needed.

Usage
-----
- Type /twmr to open or close the options window.

Options
-------
- Enable: Turns map reveal on/off.
- Unexplored Darkness: Slider from 0% to 50% darker.
  - 0% = same brightness as explored tiles
  - 50% = maximum darkening

Saved Variables
---------------
- TwMapRevealDB.enabled
- TwMapRevealDB.darknessPercent
