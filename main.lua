-- OSMMap Widget for EdgeTX
-- Single-file OSM tile map widget with auto-zoom, breadcrumbs, home marker
-- Place at /WIDGETS/OSMMap/main.lua

local W_NAME = "OSMMap"
local TILE_SIZE = 256
local ZOOM_MIN = 2
local ZOOM_MAX = 19
local TILE_PATH = "/WIDGETS/OSMMap/tiles/"
local SAVE_PATH = "/WIDGETS/OSMMap/last_"
local PI = math.pi
local RAD = PI / 180
local TRAIL_RECENT = 10      -- always-kept last N points
local TRAIL_COARSE = 100     -- coarse trail max points
local TRAIL_MIN_DIST = 10    -- meters min movement for coarse trail

-- widget options exposed to EdgeTX settings menu
local options = {
  { "ZoomSrc",  SOURCE, 0 },   -- analog source for manual zoom (0 = none/auto)
  { "ArmCh",    SOURCE, 0 },   -- arm/disarm channel (ch5 default, set in menu)
  { "MaxZoom",  VALUE,  17, ZOOM_MIN, ZOOM_MAX },
  { "MinZoom",  VALUE,  8,  ZOOM_MIN, ZOOM_MAX },
}

-- ── math helpers ────────────────────────────────────────────────────────────

local function clamp(v,lo,hi) return v<lo and lo or v>hi and hi or v end
local function floor(v) return math.floor(v) end

local function latLonToTileF(lat, lon, zoom)
  local n = 2^zoom
  local lrad = lat * RAD
  local tx = n * (lon + 180) / 360
  local ty = n * (1 - math.log(math.tan(lrad) + 1/math.cos(lrad)) / PI) / 2
  return tx, ty  -- fractional tile coords
end

local function haversine(la1, lo1, la2, lo2)
  local R = 6371000
  local dLa = (la2-la1)*RAD
  local dLo = (lo2-lo1)*RAD
  local a = math.sin(dLa/2)^2 + math.cos(la1*RAD)*math.cos(la2*RAD)*math.sin(dLo/2)^2
  return 2*R*math.asin(math.sqrt(a))
end

local function bearing(la1, lo1, la2, lo2)
  local dLo = (lo2-lo1)*RAD
  local y = math.sin(dLo)*math.cos(la2*RAD)
  local x = math.cos(la1*RAD)*math.sin(la2*RAD) - math.sin(la1*RAD)*math.cos(la2*RAD)*math.cos(dLo)
  return math.atan2(y, x)  -- radians
end

-- ── tile fetch/cache ─────────────────────────────────────────────────────────

-- In-memory bitmap cache: key="z/x/y", value=bitmap or false(missing)
local tileCache = {}
local tileCacheOrder = {}
local CACHE_MAX = 12  -- keep memory sane

local function tileKey(z,x,y) return z.."/"..x.."/"..y end

local function evictTile()
  if #tileCacheOrder > CACHE_MAX then
    local oldest = table.remove(tileCacheOrder, 1)
    tileCache[oldest] = nil
    collectgarbage()
  end
end

local function getTile(z, x, y)
  -- clamp tile coords
  local n = 2^z
  if x < 0 or y < 0 or x >= n or y >= n then return nil end
  local k = tileKey(z,x,y)
  if tileCache[k] ~= nil then return tileCache[k] end

  -- try local SD card first
  local localPath = TILE_PATH..z.."/"..x.."/"..y..".png"
  local bmp = Bitmap.open(localPath)
  local w,h = Bitmap.getSize(bmp)
  if w and w > 0 then
    tileCache[k] = bmp
    table.insert(tileCacheOrder, k)
    evictTile()
    return bmp
  end

  -- not found locally
  tileCache[k] = false
  return nil
end

-- ── file I/O helpers ─────────────────────────────────────────────────────────

local function modelSlug()
  local m = model.getInfo()
  local name = (m and m.name) or "default"
  -- sanitise: keep alphanum and underscore only
  return string.gsub(name, "[^%w]", "_")
end

local function saveLastPos(lat, lon)
  local path = SAVE_PATH..modelSlug()..".txt"
  local f = io.open(path, "w")
  if f then
    io.write(f, string.format("%.7f,%.7f\n", lat, lon))
    io.close(f)
  end
end

local function loadLastPos()
  local path = SAVE_PATH..modelSlug()..".txt"
  local f = io.open(path, "r")
  if f then
    local line = io.read(f, 64)
    io.close(f)
    if line then
      local la, lo = string.match(line, "(%-?%d+%.%d+),(%-?%d+%.%d+)")
      if la and lo then return tonumber(la), tonumber(lo) end
    end
  end
  return nil, nil
end

-- ── create ───────────────────────────────────────────────────────────────────

local function create(zone, opts)
  local w = {
    zone = zone,
    options = opts,
    -- state
    lat = nil, lon = nil,          -- live GPS
    staleLat = nil, staleLon = nil,-- loaded from file
    stalePos = false,              -- true when showing saved pos
    homeLat = nil, homeLon = nil,
    homeSet = false,
    armed = false,
    prevArmed = false,
    -- trails
    trailRecent = {},              -- {lat,lon} newest first, max TRAIL_RECENT
    trailCoarse = {},              -- {lat,lon} newest first, max TRAIL_COARSE
    lastCoarseLat = nil, lastCoarseLon = nil,
    -- zoom
    zoom = opts.MaxZoom or 15,
    autoZoom = true,
    manualZoomRaw = nil,           -- last raw value of zoom source
    zoomSettling = false,
    zoomSettleTime = 0,
    zoomOverlay = false,
    pendingZoom = nil,
  }
  -- load saved position
  w.staleLat, w.staleLon = loadLastPos()
  if w.staleLat then
    w.stalePos = true
    w.lat = w.staleLat
    w.lon = w.staleLon
  end
  return w
end

-- ── update ───────────────────────────────────────────────────────────────────

local function update(w, opts)
  w.options = opts
end

-- ── telemetry ────────────────────────────────────────────────────────────────

local function getTelem(name)
  local id = getFieldInfo(name)
  if id then return getValue(id.id) end
  return nil
end

local function readGPS(w)
  local gps = getTelem("GPS") or getTelem("Gps")
  if type(gps) == "table" and gps.lat and gps.lon then
    return gps.lat, gps.lon
  end
  -- fallback individual sensors
  local la = getTelem("Lat") or getTelem("lat")
  local lo = getTelem("Lon") or getTelem("lon")
  if type(la)=="number" and type(lo)=="number" then return la, lo end
  return nil, nil
end

local function readArmed(w)
  local src = w.options.ArmCh
  if not src or src == 0 then
    -- fallback: ch5
    local v = getValue("ch5")
    if type(v)=="number" then return v > 0 end
    return false
  end
  local v = getValue(src)
  if type(v)=="number" then return v > 500 end
  return false
end

-- ── trail management ─────────────────────────────────────────────────────────

local function pushTrail(w, lat, lon)
  -- recent trail: keep last TRAIL_RECENT
  table.insert(w.trailRecent, 1, {lat, lon})
  if #w.trailRecent > TRAIL_RECENT then
    table.remove(w.trailRecent)
  end

  -- coarse trail: only if moved >= TRAIL_MIN_DIST
  local addCoarse = false
  if not w.lastCoarseLat then
    addCoarse = true
  else
    local d = haversine(w.lastCoarseLat, w.lastCoarseLon, lat, lon)
    if d >= TRAIL_MIN_DIST then addCoarse = true end
  end
  if addCoarse then
    table.insert(w.trailCoarse, 1, {lat, lon})
    if #w.trailCoarse > TRAIL_COARSE then
      table.remove(w.trailCoarse)
    end
    w.lastCoarseLat = lat
    w.lastCoarseLon = lon
  end
end

-- ── auto zoom ────────────────────────────────────────────────────────────────

local function trailBoundsPixels(w, refTx, refTy, zoom)
  -- returns min/max pixel offsets of full trail relative to ref tile-fraction
  local minX, maxX, minY, maxY = 0,0,0,0
  local function check(lat, lon)
    local tx, ty = latLonToTileF(lat, lon, zoom)
    local px = (tx - refTx) * TILE_SIZE
    local py = (ty - refTy) * TILE_SIZE
    if px < minX then minX = px end
    if px > maxX then maxX = px end
    if py < minY then minY = py end
    if py > maxY then maxY = py end
  end
  for _, p in ipairs(w.trailRecent) do check(p[1], p[2]) end
  for _, p in ipairs(w.trailCoarse) do check(p[1], p[2]) end
  return minX, maxX, minY, maxY
end

local function doAutoZoom(w)
  if not w.autoZoom then return end
  if not w.lat then return end
  local zw = w.zone.w
  local zh = w.zone.h
  local zoom = w.zoom
  local minZ = w.options.MinZoom or 8
  local maxZ = w.options.MaxZoom or 17

  if #w.trailRecent == 0 and #w.trailCoarse == 0 then return end

  local tx, ty = latLonToTileF(w.lat, w.lon, zoom)
  local minX, maxX, minY, maxY = trailBoundsPixels(w, tx, ty, zoom)

  -- trail pixel span
  local spanX = maxX - minX
  local spanY = maxY - minY

  -- 80% threshold: zoom out if trail doesn't fit within 80% of view
  local limW = zw * 0.8
  local limH = zh * 0.8
  if (spanX > limW or spanY > limH) and zoom > minZ then
    w.zoom = zoom - 1
  -- zoom in if trail is tiny (< 20% of view) and room to zoom
  elseif (spanX < zw * 0.2 and spanY < zh * 0.2) and zoom < maxZ then
    w.zoom = zoom + 1
  end
end

-- ── manual zoom ──────────────────────────────────────────────────────────────

local ZOOM_SETTLE_MS = 800  -- ms after last change before applying

local function handleManualZoom(w)
  local src = w.options.ZoomSrc
  if not src or src == 0 then return end
  local v = getValue(src)
  if type(v) ~= "number" then return end

  -- map -1024..1024 → minZ..maxZ
  local minZ = w.options.MinZoom or 8
  local maxZ = w.options.MaxZoom or 17
  local mapped = floor(((v + 1024) / 2048) * (maxZ - minZ + 1) + minZ)
  mapped = clamp(mapped, minZ, maxZ)

  -- detect "auto" zone: if source near -1024 treat as auto re-enable
  if v < -900 then
    if not w.autoZoom then
      w.autoZoom = true
      w.zoomOverlay = false
    end
    return
  end

  if w.manualZoomRaw ~= mapped then
    w.manualZoomRaw = mapped
    w.pendingZoom = mapped
    w.zoomSettling = true
    w.zoomSettleTime = getTime()  -- EdgeTX getTime() = 10ms ticks
    w.zoomOverlay = true
    w.autoZoom = false
  end

  -- after settle period, apply
  if w.zoomSettling and w.pendingZoom then
    local elapsed = (getTime() - w.zoomSettleTime) * 10  -- to ms
    if elapsed >= ZOOM_SETTLE_MS then
      w.zoom = w.pendingZoom
      w.zoomSettling = false
      w.zoomOverlay = false
      w.pendingZoom = nil
      tileCache = {}  -- clear cache on zoom change
      tileCacheOrder = {}
      collectgarbage()
    end
  end
end

-- ── drawing ──────────────────────────────────────────────────────────────────

local COL_BG       = BLACK
local COL_TRAIL_R  = lcd.RGB and lcd.RGB(255,200,0)   or YELLOW
local COL_TRAIL_C  = lcd.RGB and lcd.RGB(255,120,0)   or ORANGE
local COL_HOME     = lcd.RGB and lcd.RGB(0,220,80)    or GREEN
local COL_CRAFT    = lcd.RGB and lcd.RGB(255,80,80)   or RED
local COL_STALE    = lcd.RGB and lcd.RGB(120,120,255) or BLUE
local COL_OVERLAY  = lcd.RGB and lcd.RGB(0,0,0)       or BLACK
local COL_TEXT     = WHITE
local COL_NOTILE   = lcd.RGB and lcd.RGB(30,30,50)    or BLACK

-- safe colour setter: CUSTOM_COLOR path for EdgeTX
local function setCol(c)
  if lcd.RGB then
    lcd.setColor(CUSTOM_COLOR, c)
    return CUSTOM_COLOR
  end
  return c
end

local function drawTiles(w, cx, cy)
  -- cx,cy = pixel center of the widget (screen coords)
  -- craft is at center
  local zoom = w.zoom
  local lat  = w.lat
  local lon  = w.lon

  local tx, ty = latLonToTileF(lat, lon, zoom)
  -- fractional offset within center tile
  local fracX = tx - floor(tx)
  local fracY = ty - floor(ty)
  local cTx = floor(tx)
  local cTy = floor(ty)

  local zw = w.zone.w
  local zh = w.zone.h
  local ox = w.zone.x
  local oy = w.zone.y

  -- how many tiles we need each side
  local tilesH = math.ceil(zw / TILE_SIZE / 2) + 1
  local tilesV = math.ceil(zh / TILE_SIZE / 2) + 1

  -- pixel origin of tile cTx,cTy on screen
  local tOriginX = cx - floor(fracX * TILE_SIZE)
  local tOriginY = cy - floor(fracY * TILE_SIZE)

  for dy = -tilesV, tilesV do
    for dx = -tilesH, tilesH do
      local px = tOriginX + dx * TILE_SIZE
      local py = tOriginY + dy * TILE_SIZE
      -- skip if fully outside zone
      if px < ox+zw and px+TILE_SIZE > ox and py < oy+zh and py+TILE_SIZE > oy then
        local bmp = getTile(zoom, cTx+dx, cTy+dy)
        if bmp then
          lcd.drawBitmap(bmp, px, py)
        else
          -- placeholder: dark rect with grid
          lcd.setColor(CUSTOM_COLOR, COL_NOTILE)
          lcd.drawFilledRectangle(px, py, TILE_SIZE, TILE_SIZE, CUSTOM_COLOR)
          lcd.setColor(CUSTOM_COLOR, lcd.RGB and lcd.RGB(50,50,70) or BLACK)
          lcd.drawRectangle(px, py, TILE_SIZE, TILE_SIZE, CUSTOM_COLOR)
        end
      end
    end
  end

  -- return tile origin for use by overlay functions
  return tOriginX, tOriginY, cTx, cTy, fracX, fracY
end

local function latLonToScreen(lat, lon, tOriginX, tOriginY, tCx, tCy, zoom)
  local tx, ty = latLonToTileF(lat, lon, zoom)
  local px = tOriginX + (tx - tCx) * TILE_SIZE
  local py = tOriginY + (ty - tCy) * TILE_SIZE
  return floor(px), floor(py)
end

local function inZone(w, px, py)
  return px >= w.zone.x and px < w.zone.x+w.zone.w
     and py >= w.zone.y and py < w.zone.y+w.zone.h
end

local function drawTrail(w, tOX, tOY, tCx, tCy)
  local zoom = w.zoom
  local ox, oy, zw, zh = w.zone.x, w.zone.y, w.zone.w, w.zone.h

  -- coarse trail first (older, dimmer)
  lcd.setColor(CUSTOM_COLOR, COL_TRAIL_C)
  for i = 2, #w.trailCoarse do
    local p1 = w.trailCoarse[i-1]
    local p2 = w.trailCoarse[i]
    local x1,y1 = latLonToScreen(p1[1],p1[2], tOX,tOY,tCx,tCy,zoom)
    local x2,y2 = latLonToScreen(p2[1],p2[2], tOX,tOY,tCx,tCy,zoom)
    if lcd.drawLineWithClipping then
      lcd.drawLineWithClipping(x1,y1,x2,y2, ox,ox+zw, oy,oy+zh, SOLID, CUSTOM_COLOR)
    else
      lcd.drawLine(x1,y1,x2,y2, SOLID, CUSTOM_COLOR)
    end
  end

  -- recent trail (bright)
  lcd.setColor(CUSTOM_COLOR, COL_TRAIL_R)
  for i = 2, #w.trailRecent do
    local p1 = w.trailRecent[i-1]
    local p2 = w.trailRecent[i]
    local x1,y1 = latLonToScreen(p1[1],p1[2], tOX,tOY,tCx,tCy,zoom)
    local x2,y2 = latLonToScreen(p2[1],p2[2], tOX,tOY,tCx,tCy,zoom)
    if lcd.drawLineWithClipping then
      lcd.drawLineWithClipping(x1,y1,x2,y2, ox,ox+zw, oy,oy+zh, SOLID, CUSTOM_COLOR)
    else
      lcd.drawLine(x1,y1,x2,y2, SOLID, CUSTOM_COLOR)
    end
  end
end

-- draw H marker (home) or edge chevron
local function drawHomeMarker(w, tOX, tOY, tCx, tCy)
  if not w.homeSet then return end
  local zoom = w.zoom
  local ox, oy, zw, zh = w.zone.x, w.zone.y, w.zone.w, w.zone.h
  local hx, hy = latLonToScreen(w.homeLat, w.homeLon, tOX, tOY, tCx, tCy, zoom)
  local cx, cy = w.lat, w.lon
  local margin = 10

  if inZone(w, hx, hy) then
    -- draw H icon
    lcd.setColor(CUSTOM_COLOR, COL_HOME)
    local s = 7
    lcd.drawLine(hx-s, hy-s, hx-s, hy+s, SOLID, CUSTOM_COLOR)
    lcd.drawLine(hx+s, hy-s, hx+s, hy+s, SOLID, CUSTOM_COLOR)
    lcd.drawLine(hx-s, hy,   hx+s, hy,   SOLID, CUSTOM_COLOR)
    lcd.setColor(CUSTOM_COLOR, COL_HOME)
    lcd.drawText(hx+s+2, hy-4, "H", SMLSIZE+CUSTOM_COLOR)
  else
    -- clamp to edge and draw chevron arrow
    local ex = clamp(hx, ox+margin, ox+zw-margin)
    local ey = clamp(hy, oy+margin, oy+zh-margin)
    -- bearing from screen center to home
    local ang = math.atan2(hy - (oy+zh/2), hx - (ox+zw/2))
    lcd.setColor(CUSTOM_COLOR, COL_HOME)
    local ar = 7
    -- arrowhead
    local ax = ex + ar * math.cos(ang)
    local ay = ey + ar * math.sin(ang)
    local bx = ex + ar * math.cos(ang + 2.4)
    local by = ey + ar * math.sin(ang + 2.4)
    local dx = ex + ar * math.cos(ang - 2.4)
    local dy = ey + ar * math.sin(ang - 2.4)
    lcd.drawLine(floor(ax), floor(ay), floor(bx), floor(by), SOLID, CUSTOM_COLOR)
    lcd.drawLine(floor(ax), floor(ay), floor(dx), floor(dy), SOLID, CUSTOM_COLOR)
    lcd.drawLine(floor(bx), floor(by), floor(ex), floor(ey), SOLID, CUSTOM_COLOR)
    lcd.drawLine(floor(dx), floor(dy), floor(ex), floor(ey), SOLID, CUSTOM_COLOR)
    lcd.drawText(ex-4, ey+ar+1, "H", SMLSIZE+CUSTOM_COLOR)
  end
end

-- draw craft dot at center
local function drawCraft(w, cx, cy)
  local col = w.stalePos and COL_STALE or COL_CRAFT
  lcd.setColor(CUSTOM_COLOR, col)
  lcd.drawFilledRectangle(cx-4, cy-4, 9, 9, CUSTOM_COLOR)
  lcd.setColor(CUSTOM_COLOR, WHITE)
  lcd.drawRectangle(cx-5, cy-5, 11, 11, CUSTOM_COLOR)
end

local function drawZoomOverlay(w)
  if not w.zoomOverlay then return end
  local ox, oy = w.zone.x, w.zone.y
  local zw, zh = w.zone.w, w.zone.h
  local pz = w.pendingZoom or w.zoom
  local label = w.autoZoom and "AUTO" or ("Z:"..pz)
  -- semi-transparent box
  lcd.setColor(CUSTOM_COLOR, lcd.RGB and lcd.RGB(0,0,0) or BLACK)
  lcd.drawFilledRectangle(ox+zw/2-30, oy+zh/2-14, 60, 28, CUSTOM_COLOR)
  lcd.setColor(CUSTOM_COLOR, WHITE)
  lcd.drawRectangle(ox+zw/2-30, oy+zh/2-14, 60, 28, CUSTOM_COLOR)
  lcd.drawText(ox+zw/2, oy+zh/2-6, label, MIDSIZE+CENTER+CUSTOM_COLOR)
end

local function drawStatusBar(w)
  -- tiny status line at top of zone
  local ox, oy = w.zone.x, w.zone.y
  local zw = w.zone.w
  local flags = SMLSIZE + CUSTOM_COLOR
  lcd.setColor(CUSTOM_COLOR, lcd.RGB and lcd.RGB(0,0,0) or BLACK)
  lcd.drawFilledRectangle(ox, oy, zw, 12, CUSTOM_COLOR)
  lcd.setColor(CUSTOM_COLOR, w.stalePos and COL_STALE or WHITE)
  local gpsStr = w.lat and string.format("Z:%d", w.zoom) or "No GPS"
  if w.stalePos then gpsStr = gpsStr.." [STALE]" end
  lcd.drawText(ox+2, oy+1, gpsStr, flags)
  if w.homeSet then
    lcd.setColor(CUSTOM_COLOR, COL_HOME)
    lcd.drawText(ox+zw-20, oy+1, "H", flags)
  end
  if w.armed then
    lcd.setColor(CUSTOM_COLOR, COL_CRAFT)
    lcd.drawText(ox+zw/2-8, oy+1, "ARMED", flags)
  end
end

local function drawNoGPS(w)
  local ox, oy = w.zone.x, w.zone.y
  local zw, zh = w.zone.w, w.zone.h
  lcd.setColor(CUSTOM_COLOR, COL_BG)
  lcd.drawFilledRectangle(ox, oy, zw, zh, CUSTOM_COLOR)
  lcd.setColor(CUSTOM_COLOR, WHITE)
  lcd.drawText(ox+zw/2, oy+zh/2-8, "Waiting for GPS", MIDSIZE+CENTER+CUSTOM_COLOR)
  if w.zoom then
    lcd.drawText(ox+zw/2, oy+zh/2+10, "Z:"..w.zoom, SMLSIZE+CENTER+CUSTOM_COLOR)
  end
end

-- ── background ───────────────────────────────────────────────────────────────

local function background(w)
  -- poll telemetry even when not visible, maintain arm/disarm state
  local la, lo = readGPS(w)
  local armed = readArmed(w)

  -- arm/disarm edge detect
  if armed and not w.armed then
    -- just armed: save home
    if la and lo then
      w.homeLat = la
      w.homeLon = lo
      w.homeSet = true
    end
  end
  if (not armed) and w.armed then
    -- just disarmed: save last position
    if la and lo then saveLastPos(la, lo) end
  end
  w.armed = armed

  if la and lo then
    w.stalePos = false
    if w.lat ~= la or w.lon ~= lo then
      pushTrail(w, la, lo)
    end
    w.lat = la
    w.lon = lo
  else
    -- telem lost: save if we had a good pos
    if w.lat and not w.stalePos then
      saveLastPos(w.lat, w.lon)
      w.stalePos = true
    end
  end
end

-- ── refresh ───────────────────────────────────────────────────────────────────

local function refresh(w, event, touchState)
  background(w)

  -- manual zoom handling
  handleManualZoom(w)

  -- nothing to show
  if not w.lat then
    drawNoGPS(w)
    return
  end

  -- auto zoom
  if w.autoZoom and not w.zoomSettling then
    doAutoZoom(w)
  end

  local ox, oy = w.zone.x, w.zone.y
  local zw, zh = w.zone.w, w.zone.h
  local cx = ox + floor(zw/2)
  local cy = oy + floor(zh/2)

  -- clip zone background
  lcd.setColor(CUSTOM_COLOR, COL_BG)
  lcd.drawFilledRectangle(ox, oy, zw, zh, CUSTOM_COLOR)

  -- tiles
  local tOX, tOY, tCx, tCy = drawTiles(w, cx, cy)

  -- overlays
  drawTrail(w, tOX, tOY, tCx, tCy)
  drawHomeMarker(w, tOX, tOY, tCx, tCy)
  drawCraft(w, cx, cy)
  drawStatusBar(w)
  drawZoomOverlay(w)
end

-- ── return interface ──────────────────────────────────────────────────────────

return {
  name       = W_NAME,
  options    = options,
  create     = create,
  update     = update,
  background = background,
  refresh    = refresh,
}
