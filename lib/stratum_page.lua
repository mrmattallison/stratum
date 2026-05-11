-- stratum_page
--
-- base class for tabbed pages. each page owns:
--   tabs        = list of {label=..., params={"id1","id2",...}}
--   tab_index   = which tab is focused
--   param_index = which param within the focused tab is focused
--
-- subclasses override :draw(), :enc(n,d,k1), :key(n,z,k1) and may
-- additionally override :draw_indicators() to paint live state above
-- the param list.

local Page = {}
Page.__index = Page

-- Page band below parent chrome (separator ~y=10). Extra space before subline so
-- tab labels clear STRATUM readouts / Clouds section titles.
local Y_TABS     = 22   -- sub-tab label baseline
local Y_TAB_RUL  = 24   -- underline two px below labels
local Y_SUBLINE  = 30   -- readout / section title / indicator strip
local Y_LIST     = 40   -- first param row (3 rows + footer fit in 64px)
local LINE_H     = 9
local Y_FOOTER   = 62

function Page.new(o)
  local p = setmetatable(o or {}, Page)
  p.tabs        = p.tabs or {}
  p.tab_index   = 1
  p.param_index = 1
  return p
end

-- shared Y positions for page UIs (use instead of magic numbers in rings/clouds/seq)
Page.LAYOUT_Y = {
  tabs     = Y_TABS,
  tab_rule = Y_TAB_RUL,
  subline  = Y_SUBLINE,
  list     = Y_LIST,
}

-- Resolved at runtime — do not cache layout in other modules at file load
-- (include / load order can leave Page.LAYOUT_Y nil when upvalues close).
function Page.layout_y()
  return Page.LAYOUT_Y or {
    tabs = 22, tab_rule = 24, subline = 30, list = 40,
  }
end

-- ── selection ────────────────────────────────────────────
function Page:current_tab()
  return self.tabs[self.tab_index]
end

function Page:current_param_id()
  local tab = self:current_tab()
  if not tab or not tab.params then return nil end
  return tab.params[self.param_index]
end

function Page:tab_param_count()
  local tab = self:current_tab()
  if not tab or not tab.params then return 0 end
  return #tab.params
end

-- ── navigation ───────────────────────────────────────────
function Page:next_param()
  local n = self:tab_param_count()
  if n > 0 then
    self.param_index = math.min(self.param_index + 1, n)
  end
end

function Page:prev_param()
  self.param_index = math.max(self.param_index - 1, 1)
end

function Page:next_tab()
  if #self.tabs == 0 then return end
  self.tab_index   = math.min(self.tab_index + 1, #self.tabs)
  self.param_index = 1
end

function Page:prev_tab()
  if #self.tabs == 0 then return end
  self.tab_index   = math.max(self.tab_index - 1, 1)
  self.param_index = 1
end

function Page:delta_param(d)
  local id = self:current_param_id()
  if id then params:delta(id, d) end
end

-- ── drawing helpers ──────────────────────────────────────
function Page:draw_tabs()
  local n = #self.tabs
  if n == 0 then return end
  local w = 128 / n
  for i, tab in ipairs(self.tabs) do
    local x = (i - 1) * w
    screen.level(i == self.tab_index and 15 or 3)
    screen.move(x + w / 2, Y_TABS)
    screen.text_center(tab.label)
    if i == self.tab_index then
      screen.move(x + 4, Y_TAB_RUL)
      screen.line(x + w - 4, Y_TAB_RUL)
      screen.stroke()
    end
  end
end

-- compact param list — current param highlighted, value on the right.
-- opts:
--   y0, rows — list origin (default Y_LIST) and visible row count (default 3)
--   value_fmt(id, default_string) — optional; return replacement value string
--   before_row(page, y, idx, id, focused) — e.g. inverted row background
--   after_row(page, y, idx, id, focused) — e.g. mod indicator
--   text_levels(id, focused) — optional; returns name_level, value_level (ints)
function Page:draw_param_list(opts)
  opts = opts or {}
  local tab = self:current_tab()
  if not tab or not tab.params then return end

  local y0        = opts.y0       or Y_LIST  -- default 40
  local visible   = opts.rows     or 3
  local n         = #tab.params
  local value_fmt = opts.value_fmt
  local before_row = opts.before_row
  local after_row = opts.after_row
  local text_levels = opts.text_levels

  -- viewport: keep selected row visible (same as STRATUM page)
  local first = math.max(1, math.min(self.param_index - math.floor(visible / 2),
                                     n - visible + 1))
  if first < 1 then first = 1 end

  for row = 0, visible - 1 do
    local idx = first + row
    if idx > n then break end
    local id  = tab.params[idx]
    local pr  = params:lookup_param(id)
    if pr then
      local y       = y0 + row * LINE_H
      local focused = (idx == self.param_index)

      if before_row then
        before_row(self, y, idx, id, focused)
      end

      local nl, vl = focused and 15 or 4, focused and 15 or 4
      if text_levels then
        local a, b = text_levels(id, focused)
        if a ~= nil then nl = a end
        if b ~= nil then vl = b end
      end

      screen.level(nl)
      screen.move(2, y)
      screen.text(pr.name)
      screen.level(vl)
      screen.move(126, y)
      local valstr = params:string(id)
      if value_fmt then
        local v = value_fmt(id, valstr)
        if v ~= nil then valstr = v end
      end
      screen.text_right(valstr)

      if focused then
        local ul = 1
        if text_levels then
          local a = select(1, text_levels(id, true))
          if a == 0 then ul = 4 end
        end
        screen.level(ul)
        screen.move(0, y + 2)
        screen.line(128, y + 2)
        screen.stroke()
      end

      if after_row then
        after_row(self, y, idx, id, focused)
      end
    end
  end
end

-- single-line footer with param name + value (alternative to list view)
function Page:draw_param_footer(id)
  if id == nil then return end
  local p = params:lookup_param(id)
  if p == nil then return end
  screen.level(4)
  screen.move(2, Y_FOOTER)
  screen.text(p.name)
  screen.level(15)
  screen.move(126, Y_FOOTER)
  screen.text_right(params:string(id))
end

-- ── default no-op overrides ──────────────────────────────
function Page:draw()
  self:draw_tabs()
  self:draw_param_list()
end

function Page:enc(n, d, k1)
  if n == 1 then
    if not k1 then params:delta("clock_tempo", d) end
  elseif n == 2 then
    if d > 0 then self:next_param() else self:prev_param() end
  elseif n == 3 then
    self:delta_param(d)
  end
end

function Page:key(n, z, k1)
  if z ~= 1 then return end
  if k1 then return end          -- k1 combos handled by subclass
  if n == 2 then self:prev_tab()
  elseif n == 3 then self:next_tab() end
end

return Page
