-- stratum_clouds
--
-- CLOUDS page: tab names POS / SIZ / TEX / FDBK / ALG (aligned with RINGS/STRATUM).
-- Density row shows Rnd/Reg/Off; freeze highlighted row when active.
-- Param list: 3-row viewport, scrolls with E2.

local Page = include("stratum/lib/stratum_page")

local M = {}

local LINE_H = 9

local PARAM_IDS = {
  {"clouds_pitch", "clouds_pos"},
  {"clouds_size",  "clouds_dens"},
  {"clouds_tex",   "clouds_spread"},
  {"clouds_fb",    "clouds_freeze"},
  {
    "clouds_rvb", "clouds_lofi", "clouds_mode",
    "clouds_mix", "clouds_bypass",
  },
}

local function cloud_density_string()
  local dens = params:get("clouds_dens")
  if dens == 50 then return "Off"
  elseif dens < 50 then return "Reg: " .. tostring((50 - dens) * 2)
  else return "Rnd: " .. tostring((dens - 50) * 2)
  end
end

function M.new()
  local p = Page.new({
    tabs = {
      { label = "POS", params = PARAM_IDS[1] },
      { label = "SIZ", params = PARAM_IDS[2] },
      { label = "TEX", params = PARAM_IDS[3] },
      { label = "FDBK", params = PARAM_IDS[4] },
      { label = "ALG", params = PARAM_IDS[5] },
    }
  })

  function p:draw()
    local ly = Page.layout_y()
    self:draw_tabs()
    self:draw_param_list({
      y0   = ly.list,
      rows = 3,
      value_fmt = function(id, s)
        if id == "clouds_dens" then return cloud_density_string() end
        return s
      end,
      before_row = function(_, y, _, id, _)
        if id == "clouds_freeze" and (params:get("clouds_freeze") or 0) ~= 0 then
          screen.level(15)
          screen.rect(0, y - 6, 128, LINE_H)
          screen.fill()
        end
      end,
      text_levels = function(id, focused)
        if id == "clouds_freeze" and (params:get("clouds_freeze") or 0) ~= 0 then
          return 0, 0
        end
        if focused then return 15, 15 end
        return 4, 4
      end,
    })
  end

  function p:key(n, z, k1)
    if z ~= 1 then return end
    if k1 then
      if n == 2 then
        local cur = params:get("clouds_freeze")
        params:set("clouds_freeze", cur == 0 and 1 or 0)
      end
    else
      if n == 2 then self:prev_tab()
      elseif n == 3 then self:next_tab() end
    end
  end

  return p
end

return M
