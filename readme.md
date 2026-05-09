# AlphaMap, Lua Widget for EdgeTX

*A lightweight OpenStreetMap viewer widget for EdgeTX radios*

[![EdgeTX](https://img.shields.io/badge/EdgeTX-Compatible-blue?style=flat-square)](https://edgetx.org/)
[![Lua](https://img.shields.io/badge/Lua-Widget-orange?style=flat-square)](https://www.lua.org/)

[<img src="https://t413.com/p/projects/osm2edgetx/AlphaMap_demo.gif" width="400" alt="osm2edgetx in action">](https://t413.com/p/projects/osm2edgetx/AlphaMap_demo.webp)

AlphaMap is a fast, self-contained OpenStreetMap viewer widget for EdgeTX radios. It's like having google maps directly on your transmitter, centered on your aircraft’s live GPS position, with breadcrumbs, home marker tracking, zoom control, and persistent last-known position storage.

Designed for FPV pilots, fixed wing, and long-range flying where having an onboard moving map directly on your radio is genuinely useful.


## Features

- **Offline OpenStreetMap tiles**
- **Single-file widget** — simple install and minimal memory usage
- **Breadcrumb trail/history**
  * Distance-based point filtering with progressive decimation with past points
- **Automatic home marker** on arm (configurable arm channel)
- **Distance-to-home display** with offscreen home direction arrow
- **Persistent last known position** saved to SD card across reboots
- **Manual zoom control** assign a channel or use the scroll wheel in full screen widget mode
  * Scroll wheel for super quick zooming
  * Analog source input for users without an extra channel to spare
- **Low CPU / memory aware**
- **Works entirely offline after tiles are loaded**


# Installation

## 1. Download
- Either download the [latest version from GitHub](https://github.com/t413/AlphaMapLua/archive/refs/heads/master.zip)
  * then copy the `AlphaMap` folder to your SD card under `/WIDGETS/`
- Or clone the repository directly into place on your SD Card:

```bash
cd /Volumes/SD_CARD_PATH/WIDGETS/
git clone https://github.com/t413/AlphaMapLua.git
```

## 2. Download map tiles

Use my python tool [osm2edgetx](https://github.com/t413/osm2edgetx) from the command line to download tiles from OpenStreetMap. This project uses unmodified 256x256 OSM tiles, [documentation here](https://wiki.openstreetmap.org/wiki/Slippy_map_tilenames).

Download the [lastest version](https://github.com/t413/osm2edgetx/archive/refs/heads/master.zip) and run something like:

```bash
cd /Volumes/SD_CARD_PATH/WIDGETS/AlphaMap/
python osm2edgetx.py --osm ./tiles --fetch "37.87,-122.32" --radius 5 --zoom 17
```

Changing the coordinates, radius, and zoom level as needed.
- Tip: right click anywhere on [google maps](https://maps.google.com) and click the first item, the coordinates, to copy to your clipboard and paste into the `--fetch` argument.

## 3. Add the Widget in EdgeTX

On your radio:

1. Open a screen
2. Add a widget
3. Select `AlphaMap`



# Related Projects

- [osm2edgetx](https://github.com/t413/osm2edgetx?utm_source=chatgpt.com)
- [yaapu Horus Mapping Widget](https://github.com/yaapu/HorusMappingWidget)
- [b14ckyy's ETHOSMappingWidget-Revisited](https://github.com/b14ckyy/ETHOSMappingWidget-Revisited) is specifically for ETHOS radios

