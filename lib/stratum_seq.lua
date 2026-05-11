-- stratum_seq
--
-- STRATUM page. Tab bar: UI → T → DEJA VU → X (short labels; UI first on load).
--   UI       — live feedback only (t / X / deja vu visuals); no params here
--   T        — rate, jitter, t model, t bias, gate length / random
--   DEJA VU  — deja vu amount, loop length, dv target
--   X        — spread, bias, steps, diversity, range, root, scale
--
-- shortcuts:
--   K1 + K2   reseed deja vu buffers
--   K1 + K3   cycle dv target (off → t → X → both)
--
-- Live visuals on the UI tab (three columns L→R: T, DEJA VU, X):
--   gate dots | deja vu bar | X bars; captions below graphics

local Page      = include("stratum/lib/stratum_page")
local t_section = include("stratum/lib/t_section")
local x_section = include("stratum/lib/x_section")
local deja_vu   = include("stratum/lib/deja_vu")

local M = {}

local TABS = {
  {label = "UI", params = {}},
  {label = "T", params = {
    "rate_mult", "jitter", "t_model", "t_bias", "gate_len", "gate_len_rand",
  }},
  {label = "DEJA VU", params = {
    "deja_vu", "dv_length", "dv_target",
  }},
  {label = "X", params = {
    "x_spread", "x_bias", "x_steps", "x_diversity", "x_range",
    "root_note", "scale_type",
  }},
}

-- Three equal columns (matches Marbles-style sectioning)
local COL_W = 128 / 3

local function col_center(i)
  return (i - 0.5) * COL_W
end

-- ── T section: gate activity dots (centered in column i=1) ─
local function draw_t_dots_column(cx, cy)
  local channels = {"t1", "t2", "t3"}
  local spread = 8
  local r = 2
  cy = math.floor(cy + 0.5)
  -- Centers at cx-8, cx, cx+8 — integer pixel centers to avoid edge clipping
  for i, ch in ipairs(channels) do
    local op  = t_section.gate_opacity(ch) or 0
    local lvl = math.floor(2 + op * 13)
    screen.level(lvl)
    local xi = math.floor(cx + (i - 2) * spread + 0.5)
    screen.circle(xi, cy, r)
    screen.fill()
  end
end

-- ── X section: normalized value bars (column i=2) ─
local function draw_x_bars_column(cx, ytop)
  local spread = 6
  local bar_w, bar_h = 3, 7
  local x0 = cx - spread - bar_w / 2
  for i = 1, 3 do
    local v = x_section.last_value(i) or 0.5
    local h = math.max(1, math.floor(v * bar_h))
    local x = x0 + (i - 1) * spread
    screen.level(2)
    screen.rect(x, ytop, bar_w, bar_h)
    screen.stroke()
    screen.level(12)
    screen.rect(x, ytop + (bar_h - h), bar_w, h)
    screen.fill()
  end
end

-- ── Deja vu bar (column i=3), scaled to column width ─
local function draw_dv_bar_column(cx, y0, max_w)
  local w = math.min(max_w, COL_W - 6)
  local h = 5
  local x0 = cx - w / 2
  local amt = params:get("deja_vu") or 0

  screen.level(2)
  screen.rect(x0, y0, w, h)
  screen.stroke()
  screen.level(8)
  screen.rect(x0, y0, math.max(1, math.floor(w * amt)), h)
  screen.fill()

  screen.level(4)
  screen.move(x0 + w / 2, y0 - 1)
  screen.line(x0 + w / 2, y0 + h + 1)
  screen.stroke()

  if amt > 0.5 then
    local blink = (math.floor(util.time() * 3) % 2 == 0)
    if blink then
      screen.level(15)
      screen.rect(x0 + w + 2, y0, 2, h)
      screen.fill()
    end
  end
end

-- Full dashboard: graphics + vertical dividers + captions under each (UI tab only)
-- Columns left→right: T, DEJA VU, X (matches tab naming order).
local function draw_ui_dashboard()
  local ly = Page.layout_y()
  local titles = {"T", "DEJA VU", "X"}
  local y_label = 52
  local y_mid   = ly.subline + 1
  local y_bars  = y_mid - 5
  local y_dv    = y_mid - 4
  -- Shift illustrations down by half the gap between their bottom and label baseline
  local y_bottom = math.max(y_mid + 2, y_dv + 5, y_bars + 7)
  local shift    = math.floor((y_label - y_bottom) / 2)
  y_mid  = y_mid + shift
  y_bars = y_bars + shift
  y_dv   = y_dv + shift

  local y_rule_top = ly.tab_rule + 1
  local y_rule_bot = 60

  screen.level(1)
  screen.move(math.floor(COL_W), y_rule_top)
  screen.line(math.floor(COL_W), y_rule_bot)
  screen.stroke()
  screen.move(math.floor(2 * COL_W), y_rule_top)
  screen.line(math.floor(2 * COL_W), y_rule_bot)
  screen.stroke()

  -- Slight +X nudge keeps 3rd dot off the column divider (was clipping fractionally)
  draw_t_dots_column(col_center(1) + 2, y_mid)
  draw_dv_bar_column(col_center(2), y_dv, COL_W - 8)
  draw_x_bars_column(col_center(3), y_bars)

  screen.level(4)
  for i = 1, 3 do
    screen.move(col_center(i), y_label)
    screen.text_center(titles[i])
  end
end

-- ── page constructor ─────────────────────────────────────
function M.new()
  local p = Page.new({tabs = TABS})

  function p:draw()
    local ly = Page.layout_y()
    self:draw_tabs()

    local tab = self:current_tab()
    if tab and tab.label == "UI" then
      draw_ui_dashboard()
      return
    end

    self:draw_param_list({y0 = ly.list, rows = 3})
  end

  function p:enc(n, d, k1)
    local tab = self:current_tab()
    if tab and tab.label == "UI" then
      if n == 1 and not k1 then params:delta("clock_tempo", d) end
      return
    end
    if n == 1 then
      if not k1 then params:delta("clock_tempo", d) end
    elseif n == 2 then
      if d > 0 then self:next_param() else self:prev_param() end
    elseif n == 3 then
      self:delta_param(d)
    end
  end

  function p:key(n, z, k1)
    if z ~= 1 then return end
    if k1 then
      if n == 2 then
        deja_vu.reseed()
      elseif n == 3 then
        deja_vu.cycle_target()
      end
    else
      if n == 2 then self:prev_tab()
      elseif n == 3 then self:next_tab() end
    end
  end

  return p
end

return M
