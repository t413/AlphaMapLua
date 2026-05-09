-- OSMMap Widget for EdgeTX
-- Single-file OSM tile map widget breadcrumbs, home marker
-- Place at /WIDGETS/OSMMap/main.lua
-- Tiles go in /WIDGETS/OSMMap/tiles/Z/X/Y.png

local W_NAME = "OSMMap"
local TILE_SIZE = 256
local ZOOM_MIN = 2
local ZOOM_MAX = 19
local TILE_PATH = "/WIDGETS/OSMMap/tiles/"
local SAVE_PATH = "/WIDGETS/OSMMap/last_"
local PI = math.pi
local RAD = PI / 180
local MAX_USAGE = 50
local TRAIL_MAX = 100
local TRAIL_MIN_STEP = 1
local TRAIL_BAND_THRESHOLDS = {10, 20, 50, TRAIL_MAX} --point index
local TRAIL_BAND_TOLERANCES = { 1, 10, 20, 50} --meters tollerance
local ZOOM_OVERLAY_TICKS = 40
local TRAIL_MAX_DECIMATE = 500 --ticks between decimations


-- widget options exposed to EdgeTX settings menu
local options = {
  { "ZoomSrc",  SOURCE, 0 },   -- analog source for manual zoom (0 = none/auto)
  { "ArmCh",    SOURCE, 0 },   -- arm/disarm channel (ch5 default, set in menu)
  { "DefZoom",  VALUE,  15, ZOOM_MIN, ZOOM_MAX },
  { "MaxZoom",  VALUE,  17, ZOOM_MIN, ZOOM_MAX },
  { "MinZoom",  VALUE,  8,  ZOOM_MIN, ZOOM_MAX },
}

-- ── math helpers ────────────────────────────────────────────────────────────
-- ── colors (initialised in create so lcd.RGB is available) ─────────────────
local C = {}
local function initColors()
  if lcd.RGB then
    C.bg        = lcd.RGB(20,20,30)
    C.noTile    = lcd.RGB(30,30,50)
    C.noTileBdr = lcd.RGB(50,50,80)
    C.trailR    = lcd.RGB(255,210,0)    -- recent: bright yellow
    C.home      = lcd.RGB(0,220,80)     -- green
    C.homeShdw  = lcd.RGB(0,60,20)
    C.craft     = lcd.RGB(255,80,80)    -- red
    C.craftShdw = lcd.RGB(80,0,0)
    C.stale     = lcd.RGB(100,140,255)  -- blue-ish
    C.barBg     = lcd.RGB(0,0,0)
    C.armed     = lcd.RGB(255,60,60)
    C.disarmed  = lcd.RGB(80,200,80)
    C.white     = WHITE
  else
    C.bg=BLACK; C.noTile=BLACK; C.noTileBdr=BLACK
    C.trailR=YELLOW; C.home=GREEN; C.homeShdw=BLACK
    C.craft=RED; C.craftShdw=BLACK; C.stale=BLUE; C.barBg=BLACK
    C.armed=RED; C.disarmed=GREEN; C.white=WHITE
  end
end

-- ── math helpers ────────────────────────────────────────────────────────────
local mfloor = math.floor
local function clamp(v,lo,hi) return v<lo and lo or v>hi and hi or v end

local function latLonToTileF(lat, lon, zoom)
  local n = 2^zoom
  local lrad = lat * RAD
  local tx = n * (lon + 180) / 360
  local ty = n * (1 - math.log(math.tan(lrad) + 1/math.cos(lrad)) / PI) / 2
  return tx, ty  -- fractional tile coords
end

local function approxDist(lat1, lon1, lat2, lon2)
  -- Rough Euclidean in meters (accurate for small deltas)
  local dLat = (lat2 - lat1) * 111320  -- ~111km per degree lat
  local dLon = (lon2 - lon1) * 111320 * math.cos((lat1 + lat2) / 2 * RAD)
  return math.sqrt(dLat*dLat + dLon*dLon)
end

local function fmtDist(m)
  if m < 1000 then return string.format("%dm", mfloor(m))
  else              return string.format("%.1fkm", m/1000) end
end

-- ── tile fetch/cache ─────────────────────────────────────────────────────────

-- In-memory bitmap cache: key="z/x/y", value=bitmap or false(missing)
local tileCache = {}
local tileCacheOrder = {}
local CACHE_MAX = 12  -- keep memory sane

local function evictTiles()
  while #tileCacheOrder > CACHE_MAX do
    local k = table.remove(tileCacheOrder, 1)
    tileCache[k] = nil
  end
  collectgarbage()
end

local function getTile(z, x, y)
  local n = 2^z
  if x<0 or y<0 or x>=n or y>=n then return nil end
  local k = z.."/"..x.."/"..y
  if tileCache[k] ~= nil then return tileCache[k] or nil end
  local bmp = Bitmap.open(TILE_PATH..k..".png")
  local w,_ = Bitmap.getSize(bmp)
  if w and w > 0 then
    tileCache[k] = bmp
    table.insert(tileCacheOrder, k)
    evictTiles()
    return bmp
  end
  tileCache[k] = false
  return nil
end

local function hasTilesForZoom(lat, lon, zoom)
  if not lat then return false end
  local tx,ty = latLonToTileF(lat, lon, zoom)
  local cTx,cTy = mfloor(tx), mfloor(ty)
  return getTile(zoom, cTx, cTy) ~= nil
end

local function clearTileCache()
  tileCache = {}; tileCacheOrder = {}
  collectgarbage(); collectgarbage()
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
  print("[OSMMap] saved last pos "..lat..","..lon)
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

-- ── status bar height (memoised after first lcd call) ───────────────────────
local BAR_H = nil
local function getBarH()
  if BAR_H then return BAR_H end
  local _, h = lcd.sizeText("Ag", SMLSIZE)
  BAR_H = (h or 10) + 4
  return BAR_H
end

-- ── create ───────────────────────────────────────────────────────────────────
local function create(zone, opts)
  initColors()
  local w = {
    zone = zone,
    options = opts,
    lat = nil, lon = nil,          -- live GPS
    stalePos = false,              -- true when showing saved pos
    homeLat = nil, homeLon = nil,
    homeSet = false,
    armed = false,
    trail = {},                    -- {lat,lon} newest first, progressive decimation
    zoom = opts.DefZoom or 15,
    manualZoomLast = nil,
    zoomSettling = false,
    zoomSettleTime = 0,
    zoomOverlay = false,
    zoomOverlayTime = 0,
    pendingZoom = nil,
    lastDecimate = 0,
  }
  -- load saved position
  local sLa, sLo = loadLastPos()
  if sLa then
    w.lat = sLa; w.lon = sLo; w.stalePos = true
    -- find initial zoom level that has tiles available
    for z = w.zoom, (w.options.MinZoom or 8), -1 do
      w.zoom = z
      if hasTilesForZoom(w.lat, w.lon, z) then break end
    end
    print("[OSMMap] create: stale pos "..sLa..","..sLo)
  end
  return w
end

-- ── update ───────────────────────────────────────────────────────────────────
local function update(w, opts)
  w.options = opts
  print("[OSMMap] options updated: MaxZoom="..opts.MaxZoom.." MinZoom="..opts.MinZoom)
end

-- ── telemetry ────────────────────────────────────────────────────────────────
local function getTelem(name)
  local id = getFieldInfo(name)
  if id then return getValue(id.id) end
  return nil
end

local function readGPS(w)
  local gps = getTelem("GPS") or getTelem("Gps")
  local lat, lon, sats
  if type(gps) == "table" and gps.lat and gps.lon then
    lat = gps.lat
    lon = gps.lon
    sats = gps.sat or gps.sats or gps.numSat or gps.numSats
  else
    lat = getTelem("Lat") or getTelem("lat")
    lon = getTelem("Lon") or getTelem("lon")
  end
  if type(lat)=="number" and type(lon)=="number" and lat~=0 and lon~=0 then
    return lat, lon, type(sats)=="number" and sats or nil
  end
  return nil, nil, nil
end

local function readArmed(w)
  local src = w.options.ArmCh
  if not src or src == 0 then
    local v = getValue("ch5")
    if type(v)=="number" then return v > 0 end
    return false
  end
  local v = getValue(src)
  if type(v)=="number" then return v > 500 end
  return false
end

-- ── trail management ─────────────────────────────────────────────────────────

local function trailTolerance(index)
  if index <= TRAIL_BAND_THRESHOLDS[1] then return TRAIL_BAND_TOLERANCES[1] end
  if index <= TRAIL_BAND_THRESHOLDS[2] then return TRAIL_BAND_TOLERANCES[2] end
  if index <= TRAIL_BAND_THRESHOLDS[3] then return TRAIL_BAND_TOLERANCES[3] end
  return TRAIL_BAND_TOLERANCES[4]
end

local function decimateTrail(w)
  local old = w.trail
  local kept = {}
  local last = nil
  for i = 1, #old do
    local pt = old[i]
    if not last then
      table.insert(kept, pt)
      last = pt
    else
      local idx = #kept + 1
      local tol = trailTolerance(idx)
      if approxDist(pt[1], pt[2], last[1], last[2]) >= tol then
        table.insert(kept, pt)
        last = pt
      end
    end
    if #kept >= TRAIL_MAX then break end
  end
  w.trail = kept
  print(string.format("[OSMMap] trail decimate from %d to %d", #old, #kept))
end

local function pushTrail(w, lat, lon)
  local last = w.trail[1]
  if last then
    local delta = approxDist(lat, lon, last[1], last[2])
    if delta < TRAIL_MIN_STEP then
      return
    end
  end

  table.insert(w.trail, 1, {lat, lon})
  local now = getTime()
  if now - w.lastDecimate >= TRAIL_MAX_DECIMATE then
    w.lastDecimate = now
    decimateTrail(w)
  end
end

-- ── manual zoom ──────────────────────────────────────────────────────────────
local ZOOM_SETTLE_TICKS = 80  -- ~800ms

local function handleManualZoom(w)
  local src = w.options.ZoomSrc
  if not src or src == 0 then return end
  local v = getValue(src)
  if type(v) ~= "number" then return end

  local minZ = w.options.MinZoom or 8
  local maxZ = w.options.MaxZoom or 17

  local mapped = mfloor(((v + 1024) / 2048) * (maxZ - minZ) + minZ + 0.5)
  mapped = clamp(mapped, minZ, maxZ)

  if w.manualZoomLast ~= mapped then
    w.manualZoomLast = mapped
    w.pendingZoom    = mapped
    w.zoomSettling   = true
    w.zoomSettleTime = getTime()
    w.zoomOverlay    = true
    w.zoomOverlayTime = getTime()
    print("[OSMMap] manual zoom: pending "..mapped)
  end

  if w.zoomSettling and w.pendingZoom then
    if (getTime() - w.zoomSettleTime) >= ZOOM_SETTLE_TICKS then
      if w.zoom ~= w.pendingZoom then
        w.zoom = w.pendingZoom
        clearTileCache()
        print("[OSMMap] manual zoom: applied "..w.zoom)
      end
      w.zoomSettling = false; w.zoomOverlay = false; w.pendingZoom = nil
    end
  end
end

local function handleWidgetEvents(w, event)
  local minZ = w.options.MinZoom or 8
  local maxZ = w.options.MaxZoom or 17

  if event == EVT_ROT_RIGHT or event == EVT_ROT_LEFT then
    local delta = event == EVT_ROT_RIGHT and 1 or -1
    local nextZoom = clamp(w.zoom + delta, minZ, maxZ)
    if nextZoom ~= w.zoom then
      w.zoom = nextZoom
      w.zoomSettling = false
      w.pendingZoom = nil
      w.zoomOverlay = true
      w.zoomOverlayTime = getTime()
      clearTileCache()
      print(string.format("[OSMMap] wheel zoom -> %d", w.zoom))
    end
    return
  end
end

-- ── drawing helpers ──────────────────────────────────────────────────────────
local function setC(col) lcd.setColor(CUSTOM_COLOR, col) end

-- ── draw tiles ───────────────────────────────────────────────────────────────
-- Returns tOX, tOY (pixel top-left of tile [cTx,cTy]), cTx, cTy
local function drawTiles(w, cx, cy)
  local zoom = w.zoom
  local tx,ty = latLonToTileF(w.lat, w.lon, zoom)
  local cTx = mfloor(tx);  local cTy = mfloor(ty)
  local tOX = cx - mfloor((tx-cTx) * TILE_SIZE)
  local tOY = cy - mfloor((ty-cTy) * TILE_SIZE)
  local ox,oy,zw,zh = w.zone.x, w.zone.y, w.zone.w, w.zone.h
  local tilesH = math.ceil(zw/TILE_SIZE/2)+1
  local tilesV = math.ceil(zh/TILE_SIZE/2)+1

  for dy=-tilesV,tilesV do
    for dx=-tilesH,tilesH do
      local px = tOX + dx*TILE_SIZE
      local py = tOY + dy*TILE_SIZE
      if px < ox+zw and px+TILE_SIZE > ox and py < oy+zh and py+TILE_SIZE > oy then
        local bmp = getTile(zoom, cTx+dx, cTy+dy)
        if bmp then
          lcd.drawBitmap(bmp, px, py)
        else
          setC(C.noTile);    lcd.drawFilledRectangle(px,py,TILE_SIZE,TILE_SIZE,CUSTOM_COLOR)
          setC(C.noTileBdr); lcd.drawRectangle(px,py,TILE_SIZE,TILE_SIZE,CUSTOM_COLOR)
        end
      end
    end
  end
  return tOX, tOY, cTx, cTy
end

-- ── coordinate helpers ───────────────────────────────────────────────────────
local function toScreen(lat, lon, tOX, tOY, cTx, cTy, zoom)
  local tx,ty = latLonToTileF(lat, lon, zoom)
  return mfloor(tOX + (tx-cTx)*TILE_SIZE),
         mfloor(tOY + (ty-cTy)*TILE_SIZE)
end

local function inZone(w, px, py)
  return px >= w.zone.x and px < w.zone.x+w.zone.w
     and py >= w.zone.y and py < w.zone.y+w.zone.h
end

local function drawTrail(w, tOX, tOY, cTx, cTy)
  local zoom = w.zoom
  local ox, oy, zw, zh = w.zone.x, w.zone.y, w.zone.w, w.zone.h

  -- compute coordinate bounds once to skip offscreen points
  local minTx = (ox - tOX) / TILE_SIZE + cTx
  local maxTx = (ox + zw - tOX) / TILE_SIZE + cTx
  local minTy = (oy - tOY) / TILE_SIZE + cTy
  local maxTy = (oy + zh - tOY) / TILE_SIZE + cTy

  setC(C.trailR)
  for _, p in ipairs(w.trail) do
    local tx, ty = latLonToTileF(p[1], p[2], zoom)
    if tx >= minTx and tx <= maxTx and ty >= minTy and ty <= maxTy then
      local px = mfloor(tOX + (tx - cTx) * TILE_SIZE)
      local py = mfloor(tOY + (ty - cTy) * TILE_SIZE)
      lcd.drawFilledRectangle(px-2, py-2, 4, 4, CUSTOM_COLOR)
    end
  end
end

-- draw H marker (home) or edge chevron
local function drawHomeMarker(w, tOX, tOY, cTx, cTy)
  if not w.homeSet then return end
  local zoom = w.zoom
  local ox, oy, zw, zh = w.zone.x, w.zone.y, w.zone.w, w.zone.h
  local hx, hy = toScreen(w.homeLat, w.homeLon, tOX, tOY, cTx, cTy, zoom)
  local margin = 14

  if inZone(w, hx, hy) then
    -- H glyph with contrast shadow
    local s = 6
    -- draw shadow (offset neighbours)
    setC(C.homeShdw)
    for _,d in ipairs({{-1,-1},{1,-1},{-1,1},{1,1},{0,-1},{0,1},{-1,0},{1,0}}) do
      local dx,dy2 = d[1],d[2]
      lcd.drawLine(hx-s+dx,hy-s+dy2, hx-s+dx,hy+s+dy2, SOLID, CUSTOM_COLOR)
      lcd.drawLine(hx+s+dx,hy-s+dy2, hx+s+dx,hy+s+dy2, SOLID, CUSTOM_COLOR)
      lcd.drawLine(hx-s+dx,hy+dy2,   hx+s+dx,hy+dy2,   SOLID, CUSTOM_COLOR)
    end
    -- H colour strokes
    setC(C.home)
    lcd.drawLine(hx-s, hy-s, hx-s, hy+s, SOLID, CUSTOM_COLOR)
    lcd.drawLine(hx+s, hy-s, hx+s, hy+s, SOLID, CUSTOM_COLOR)
    lcd.drawLine(hx-s, hy,   hx+s, hy,   SOLID, CUSTOM_COLOR)

  else
    -- clamp to edge and draw chevron arrow
    local ex = clamp(hx, ox+margin, ox+zw-margin)
    local ey = clamp(hy, oy+margin, oy+zh-margin)
    local ang = math.atan2(hy-(oy+zh/2), hx-(ox+zw/2))
    local ar = 10
    local tip  = {ex + ar*math.cos(ang),         ey + ar*math.sin(ang)}
    local lw   = {ex + ar*math.cos(ang+2.5),      ey + ar*math.sin(ang+2.5)}
    local rw   = {ex + ar*math.cos(ang-2.5),      ey + ar*math.sin(ang-2.5)}
    local tail = {ex + ar*0.35*math.cos(ang+PI),  ey + ar*0.35*math.sin(ang+PI)}
    local pts  = {tip, lw, tail, rw, tip}

    -- fat shadow (draw 3 offsets)
    setC(C.homeShdw)
    for _,off in ipairs({{-1,-1},{1,-1},{0,1}}) do
      for i=1,#pts-1 do
        lcd.drawLine(mfloor(pts[i][1])+off[1], mfloor(pts[i][2])+off[2],
                     mfloor(pts[i+1][1])+off[1], mfloor(pts[i+1][2])+off[2], SOLID, CUSTOM_COLOR)
      end
    end
    -- colour arrow
    setC(C.home)
    for i=1,#pts-1 do
      lcd.drawLine(mfloor(pts[i][1]), mfloor(pts[i][2]),
                   mfloor(pts[i+1][1]), mfloor(pts[i+1][2]), SOLID, CUSTOM_COLOR)
    end
  end
end

-- draw craft dot at center
local function drawCraft(w, cx, cy)
  local col  = w.stalePos and C.stale  or C.craft
  local shdw = w.stalePos and C.barBg  or C.craftShdw
  -- shadow ring
  setC(shdw)
  lcd.drawCircle(cx, cy, 8, CUSTOM_COLOR)
  -- filled craft circle
  setC(col)
  lcd.drawFilledCircle(cx, cy, 5, CUSTOM_COLOR)
  -- white outline
  setC(C.white)
  lcd.drawCircle(cx, cy, 5, CUSTOM_COLOR)
end

-- ── status bar ───────────────────────────────────────────────────────────────
local function drawStatusBar(w)
  local bh = getBarH()
  local ox,oy,zw = w.zone.x, w.zone.y, w.zone.w
  setC(C.barBg)
  lcd.drawFilledRectangle(ox, oy, zw, bh, CUSTOM_COLOR)

  local f  = SMLSIZE + CUSTOM_COLOR
  local yT = oy + 2

  -- left: zoom level
  local leftStr = string.format("Z:%d", w.zoom)
  if w.stalePos then leftStr = leftStr.." STALE" end
  setC(w.stalePos and C.stale or C.white)
  lcd.drawText(ox+2, yT, leftStr, f)

  -- center: ARMED / disarmed
  setC(w.armed and C.armed or C.disarmed)
  lcd.drawText(ox + zw/2, yT, w.armed and "ARMED" or "disarmed", f + CENTER)

  -- right: home distance
  if w.homeSet and w.lat then
    local dist = approxDist(w.lat, w.lon, w.homeLat, w.homeLon)
    local distStr = "H "..fmtDist(dist)
    local sw,_  = lcd.sizeText(distStr, SMLSIZE)
    setC(C.home)
    lcd.drawText(ox+zw-sw-2, yT, distStr, f)
  end
end

-- ── zoom overlay ─────────────────────────────────────────────────────────────
local function drawZoomOverlay(w)
  if not w.zoomOverlay then return end
  local ox,oy,zw,zh = w.zone.x, w.zone.y, w.zone.w, w.zone.h
  local label = (w.pendingZoom and ("Zoom: "..w.pendingZoom) or ("Zoom: "..w.zoom))
  local sw,sh = lcd.sizeText(label, MIDSIZE)
  local bw = sw+20;  local bh = sh+12
  local bx = ox + mfloor((zw-bw)/2)
  local by = oy + mfloor((zh-bh)/2)
  setC(C.barBg)
  lcd.drawFilledRectangle(bx, by, bw, bh, CUSTOM_COLOR)
  setC(C.white)
  lcd.drawRectangle(bx, by, bw, bh, CUSTOM_COLOR)
  lcd.drawText(ox+zw/2, by+6, label, MIDSIZE+CENTER+CUSTOM_COLOR)
end

-- ── no-GPS screen ────────────────────────────────────────────────────────────
local function drawNoGPS(w)
  local ox,oy,zw,zh = w.zone.x, w.zone.y, w.zone.w, w.zone.h
  setC(C.bg)
  lcd.drawFilledRectangle(ox,oy,zw,zh,CUSTOM_COLOR)
  setC(C.white)
  lcd.drawText(ox+zw/2, oy+zh/2-10, "Waiting for GPS", MIDSIZE+CENTER+CUSTOM_COLOR)
  lcd.drawText(ox+zw/2, oy+zh/2+8,  "Z:"..w.zoom, SMLSIZE+CENTER+CUSTOM_COLOR)
end

-- ── background ───────────────────────────────────────────────────────────────

local function background(w)
  -- poll telemetry even when not visible, maintain arm/disarm state
  local la, lo, sats = readGPS(w)
  local armed = readArmed(w)

  -- arm/disarm edge detect
  if armed and not w.armed then
    -- just armed: save home
    if la and lo then
      w.homeLat = la
      w.homeLon = lo
      w.homeSet = true
      print(string.format("[OSMMap] ARMED -> home %.6f,%.6f", la, lo))
    else
      print("[OSMMap] ARMED but no GPS lock for home")
    end
  end
  -- disarm falling edge -> persist last position
  if (not armed) and w.armed then
    if la and lo then saveLastPos(la, lo) end
    print("[OSMMap] DISARMED")
  end
  w.armed = armed

  if la and lo then
    w.stalePos = false
    if sats == nil or sats >= 3 then
      pushTrail(w, la, lo)
    end
    w.lat = la
    w.lon = lo
  else
    -- telem lost: save if we had a good pos
    if w.lat and not w.stalePos then
      saveLastPos(w.lat, w.lon)
      w.stalePos = true
      print("[OSMMap] telem lost -> stale, saved last pos")
    end
  end
end

-- ── refresh ───────────────────────────────────────────────────────────────────

local function refresh(w, event, touchState)
  background(w)
  if event then
    handleWidgetEvents(w, event)
  end

  handleManualZoom(w)

  if w.zoomOverlay and (getTime() - w.zoomOverlayTime) >= ZOOM_OVERLAY_TICKS then
    w.zoomOverlay = false
  end

  if not w.lat then
    drawNoGPS(w)
    return
  end

  local ox, oy = w.zone.x, w.zone.y
  local zw, zh = w.zone.w, w.zone.h
  local cx = ox + mfloor(zw/2)
  local cy = oy + mfloor(zh/2)

  setC(C.bg)
  lcd.drawFilledRectangle(ox, oy, zw, zh, CUSTOM_COLOR)

  -- tiles
  local tOX,tOY,cTx,cTy = drawTiles(w, cx, cy)

  -- overlays
  if getUsage() < MAX_USAGE then drawTrail(w, tOX, tOY, cTx, cTy)
  else print(string.format("[OSMMap] skip drawTrail, high CPU %d%%", getUsage())) end
  drawHomeMarker(w, tOX, tOY, cTx, cTy)
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
