-- stratum modulation: LFOs routed to Core / Rings / Clouds params.
-- PARAMETERS order: stratum → rings → clouds

local LFO = include("stratum/lib/stratum_lfo")

STRATUM_LIB = STRATUM_LIB or {}
if STRATUM_LIB.stratum_mod ~= nil then
  return STRATUM_LIB.stratum_mod
end

local M = {}

local lfos = {}

local SLOTS = 3

-- { menu label, params id }
local STRATUM_TARGETS = {
  {"none", nil},
  {"rate",              "rate_mult"},
  {"jitter",            "jitter"},
  {"t bias",            "t_bias"},
  {"gate randomise",    "gate_len_rand"},
  {"spread",            "x_spread"},
  {"bias",              "x_bias"},
  {"steps",             "x_steps"},
}

local RINGS_TARGETS = {
  {"none", nil},
  {"structure",         "rings_struct"},
  {"brightness",        "rings_bright"},
  {"damping",           "rings_damp"},
  {"position",          "rings_pos"},
  {"odd/even",          "rings_odd_even"},
  {"polyphony",         "rings_poly"},
  {"rings level",       "rings_amp"},
}

local CLOUDS_TARGETS = {
  {"none", nil},
  {"pitch shift",       "clouds_pitch"},
  {"position",          "clouds_pos"},
  {"size",              "clouds_size"},
  {"density",           "clouds_dens"},
  {"texture",           "clouds_tex"},
  {"stereo spread",     "clouds_spread"},
  {"feedback",          "clouds_fb"},
  {"reverb",            "clouds_rvb"},
  {"mix",               "clouds_mix"},
}

local function target_labels(tbl)
  local t = {}
  for _, row in ipairs(tbl) do
    table.insert(t, row[1])
  end
  return t
end

local function target_id(tbl, idx)
  local row = tbl[idx]
  if not row then return nil end
  return row[2]
end

-- Hard bounds for params where lookup misses min/max (LFO defaulted to 0..1 —
-- rate_mult then stuck at division /8 after rounding).
local MOD_BOUND = {
  rate_mult       = {1, 7},
  rings_poly      = {1, 4},
  clouds_dens     = {0, 100},
}

local function param_range(pid)
  if pid == nil or pid == "" then return 0, 1 end

  local ovr = MOD_BOUND[pid]
  if ovr then return ovr[1], ovr[2] end

  local ok, p = pcall(function() return params:lookup_param(pid) end)
  if not ok or p == nil then return 0, 1 end

  if p.controlspec then
    return p.controlspec.minval, p.controlspec.maxval
  end

  local gr_ok, range = pcall(function()
    if type(p.get_range) == "function" then return p:get_range() end
  end)
  if gr_ok and type(range) == "table"
      and type(range[1]) == "number" and type(range[2]) == "number" then
    return range[1], range[2]
  end

  if type(p.min) == "number" and type(p.max) == "number" then
    return p.min, p.max
  end

  return 0, 1
end

local function apply_value(pid, scaled)
  if pid == nil or pid == "" then return end
  local v = scaled
  if pid == "rings_poly" then
    v = util.clamp(math.floor(v + 0.5), MOD_BOUND.rings_poly[1], MOD_BOUND.rings_poly[2])
  elseif pid == "clouds_dens" then
    v = util.clamp(math.floor(v + 0.5), MOD_BOUND.clouds_dens[1], MOD_BOUND.clouds_dens[2])
  elseif pid == "rate_mult" then
    local lo, hi = MOD_BOUND.rate_mult[1], MOD_BOUND.rate_mult[2]
    v = util.clamp(math.floor(v + 0.5), lo, hi)
  end
  params:set(pid, v)
end

-- lfos keyed by which_key .. slot_idx  ("s1","r1","c1",...)
local function bind_slot(which_key, mod_prefix, slot_idx, tbl, lid)
  lfos[which_key .. slot_idx] = LFO.new(
    "sine",
    0,
    1,
    0.25,
    "clocked",
    4,
    function(scaled, _raw)
      local ix = params:get(mod_prefix .. slot_idx .. "_target")
      local pid = target_id(tbl, ix)
      if pid == nil or pid == "" then return end
      apply_value(pid, scaled)
    end,
    0,
    "center",
    function(_) end
  )
  lfos[which_key .. slot_idx]:add_params(lid, nil, nil)
end

local function sync_lfo_bounds(which_key, mod_prefix, slot_idx, tbl, lid)
  local ix = params:get(mod_prefix .. slot_idx .. "_target")
  local pid = target_id(tbl, ix)
  local lfo_inst = lfos[which_key .. slot_idx]
  if not lfo_inst then return end
  local mn, mx = param_range(pid)
  lfo_inst:set("min", mn)
  lfo_inst:set("max", mx)
  pcall(function()
    params:set("lfo_min_" .. lid, mn)
    params:set("lfo_max_" .. lid, mx)
  end)
end

local S_LABELS = target_labels(STRATUM_TARGETS)
local R_LABELS = target_labels(RINGS_TARGETS)
local C_LABELS = target_labels(CLOUDS_TARGETS)

function M.setup_params()
  LFO.init()

  params:add_separator("modulation")

  params:add_group("mod_grp_stratum", "stratum", SLOTS * 16)

  for s = 1, SLOTS do
    params:add_option(
      "mod_stratum_slot" .. s .. "_target",
      "slot " .. s .. " >",
      S_LABELS,
      1
    )
    params:set_action("mod_stratum_slot" .. s .. "_target", function()
      sync_lfo_bounds("s", "mod_stratum_slot", s, STRATUM_TARGETS, "ms" .. s)
    end)

    bind_slot("s", "mod_stratum_slot", s, STRATUM_TARGETS, "ms" .. s)
  end

  params:add_group("mod_grp_rings", "rings", SLOTS * 16)

  for s = 1, SLOTS do
    params:add_option(
      "mod_ring_slot" .. s .. "_target",
      "slot " .. s .. " >",
      R_LABELS,
      1
    )
    params:set_action("mod_ring_slot" .. s .. "_target", function()
      sync_lfo_bounds("r", "mod_ring_slot", s, RINGS_TARGETS, "mr" .. s)
    end)

    bind_slot("r", "mod_ring_slot", s, RINGS_TARGETS, "mr" .. s)
  end

  params:add_group("mod_grp_clouds", "clouds", SLOTS * 16)

  for s = 1, SLOTS do
    params:add_option(
      "mod_cloud_slot" .. s .. "_target",
      "slot " .. s .. " >",
      C_LABELS,
      1
    )
    params:set_action("mod_cloud_slot" .. s .. "_target", function()
      sync_lfo_bounds("c", "mod_cloud_slot", s, CLOUDS_TARGETS, "mc" .. s)
    end)

    bind_slot("c", "mod_cloud_slot", s, CLOUDS_TARGETS, "mc" .. s)
  end
end

function M.after_bang()
  for s = 1, SLOTS do
    sync_lfo_bounds("s", "mod_stratum_slot", s, STRATUM_TARGETS, "ms" .. s)
    sync_lfo_bounds("r", "mod_ring_slot", s, RINGS_TARGETS, "mr" .. s)
    sync_lfo_bounds("c", "mod_cloud_slot", s, CLOUDS_TARGETS, "mc" .. s)
  end
end

function M.cleanup()
  for s = 1, SLOTS do
    for _, k in ipairs({"s", "r", "c"}) do
      local L = lfos[k .. s]
      if L then L:stop() end
    end
  end
end

STRATUM_LIB.stratum_mod = M
return M
