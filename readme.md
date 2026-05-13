# AlphaMap, Lua Widget for EdgeTX

*A lightweight OpenStreetMap viewer widget for EdgeTX radios*

[![EdgeTX](https://img.shields.io/badge/EdgeTX-Compatible-blue?style=flat-square)](https://edgetx.org/)
[![Lua](https://img.shields.io/badge/Lua-Widget-orange?style=flat-square)](https://www.lua.org/)
[![License](https://img.shields.io/badge/License-GPL--3.0-green?style=flat-square)](https://github.com/t413/AlphaMapLua/blob/master/LICENSE)

<p align="center">
  <a href="https://t413.com/go/alphamaptool?ref=gh"><img src="https://t413.com/p/projects/osm2edgetx/AlphaMap_demo.gif" width="400" alt="osm2edgetx in action"></a>
</p>

AlphaMap is a fast, self-contained OpenStreetMap viewer widget for EdgeTX radios. It's like having google maps directly on your transmitter, centered on your aircraft’s live GPS position, with breadcrumbs, home marker tracking, zoom control, persistent last-known position storage, and now QR Code display on disarm.

Designed for FPV pilots, fixed wing, and long-range flying where having an onboard moving map directly on your radio is genuinely useful.

→ **New:** Use the [AlphaMap Web Installer & Map Downloader](ps://t413.com/go/alphamaptool?ref=gh) to easily install the script and download map tiles for entire regions! ←

[![web tool screenshot](https://t413.com/p/projects/AlphaMapLua/web-tool.jpeg)](https://t413.com/go/alphamaptool?ref=gh)


## Features

- **Offline OpenStreetMap tiles**- download via the [Web App](ps://t413.com/go/alphamaptool?ref=gh) or my osm2edgetx tool (see below), or any OSM tile downloader.
- **Single-file widget** — simple install and minimal memory usage
- **Breadcrumb trail/history**
  * Distance-based point filtering with progressive decimation with past points
- **Automatic home marker** on arm (configurable arm channel)
- **Distance-to-home display** with offscreen home direction arrow
- **QR Code** shows when disarmed >10m away, scan with your phone to help navigate out to your downed craft
- **Persistent last known position** saved to SD card across reboots
- **Manual zoom control** assign a channel or use the scroll wheel in full screen widget mode
  * Scroll wheel for super quick zooming
  * Analog source input for users without an extra channel to spare
- **Low CPU / memory aware**
- **Works entirely offline after tiles are loaded**


# Installation

## 1. Web Install & Map Downloader (Recommended)
The easiest way to install AlphaMap and download map tiles is using the web-based installer:

**[👉 Launch AlphaMap Web Installer & Map Downloader](ps://t413.com/go/alphamaptool?ref=gh)**

This tool allows you to update the Lua script and fetch map tiles for entire continents or specific regions directly to your SD card.

## 2. Manual Install Method
1. **Download**
  * Either download the [latest version from GitHub](https://github.com/t413/AlphaMapLua/archive/refs/heads/master.zip)
    * then copy the `AlphaMapLua` folder to your SD card under `/WIDGETS/`
  * Or clone the repository directly into place on your SD Card:
    ```bash
    cd /Volumes/SD_CARD_PATH/WIDGETS/
    git clone https://github.com/t413/AlphaMapLua.git
    ```
2. **Download Map Tiles**
  - Use my python tool [osm2edgetx](https://github.com/t413/osm2edgetx) from the command line to download tiles from OpenStreetMap. This project uses unmodified 256x256 OSM tiles, [documentation here](https://wiki.openstreetmap.org/wiki/Slippy_map_tilenames).

    * Download the [lastest version](https://github.com/t413/osm2edgetx/archive/refs/heads/master.zip) and run something like:

      ```bash
      cd /Volumes/SD_CARD_PATH/WIDGETS/AlphaMapLua/
      python osm2edgetx.py --osm ./tiles --fetch "37.87,-122.32" --radius 5 --zoom 17
      ```
    - Changing the coordinates, radius, and zoom level as needed.
    - Tip: right click anywhere on [google maps](https://maps.google.com) and click the first item, the coordinates, to copy to your clipboard and paste into the `--fetch` argument.

## 3. Add the Widget in EdgeTX

<a href="https://t413.com/p/projects/osm2edgetx/alphamap-screenshot.png">
  <img src="https://t413.com/p/projects/osm2edgetx/alphamap-screenshot.png" align="right" alt="AlphaMap Screenshot" style="margin-left:10px; max-width:220px; border-radius:8px;">
</a>

On your radio:

1. Open a screen
2. Add a widget
3. Select `AlphaMap`

## 4. Advanced Usage

- On the home screen hold down on the select wheel to allow selecting of the widget
- Select the widget, it opens a menu. Choose either
  * **Full screen**- when in full screen use the scroll wheel to zoom in and out without assigning a zoom channel
  * **Widget settings**- set the zoom levels, arm/zoom channels, QR code, and other options
- **DisarmQR** setting: set to a pixel size (recommend >60) and if you disarm further away than 10m it will make a maps QR that you phone can open to help navigate to your downed craft.
- **HomeOnce** setting: Only sets what this widget things as a homepoint on the first arming

<br clear="both">

# Related Projects

- [osm2edgetx](https://github.com/t413/osm2edgetx?utm_source=chatgpt.com)
- [yaapu Horus Mapping Widget](https://github.com/yaapu/HorusMappingWidget)
- [b14ckyy's ETHOSMappingWidget-Revisited](https://github.com/b14ckyy/ETHOSMappingWidget-Revisited) is specifically for ETHOS radios

# License

This project is licensed under the GPL-3.0 License. See details in the [LICENSE](https://github.com/t413/AlphaMapLua/blob/master/LICENSE) file.
