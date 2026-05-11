-- stratum_rings
--
-- RINGS page: PITCH / TONE / MODEL.  TONE includes odd/even MiRings output blend;
-- Disastrous Peace swaps model *names* on the MODEL tab.
-- Param list matches STRATUM page: 3-row viewport, scrolls with E2.

local Page = include("stratum/lib/stratum_page")

local M = {}

local MODEL_LABELS = {
  "modal", "sym strings", "string", "FM", "chords", "karplusverb",
}
local DP_MODEL_LABELS = {
  "formant", "chorus", "reverb", "formant 2", "chorus 2", "reverb 2",
}

local TABS = {
  {label = "PITCH", params = {"rings_struct"}},
  {label = "TONE", params = {
    "rings_bright", "rings_damp", "rings_pos", "rings_odd_even", "rings_poly",
  }},
  {label = "MODEL", params = {
    "rings_model", "rings_easteregg", "rings_amp", "rings_bypass",
  }},
}

local function model_value_string()
  local i  = params:get("rings_model")
  local dp = params:get("rings_easteregg") == 2
  local t  = dp and DP_MODEL_LABELS or MODEL_LABELS
  return t[i] or "?"
end

function M.new()
  local p = Page.new({tabs = TABS})

  function p:draw()
    local ly = Page.layout_y()
    self:draw_tabs()
    self:draw_param_list({
      y0  = ly.list,
      rows = 3,
      value_fmt = function(id, s)
        if id == "rings_model" then return model_value_string() end
        return s
      end,
    })
  end

  return p
end

return M
