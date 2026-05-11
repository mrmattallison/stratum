-- stratum
--
-- from earth to sky.
--
-- uses @okyeron MUgens 
-- lfolib by @dndrks + @sixolet 
-- tweaks @Dewb + @sonoCircuit
--
-- E1 . . . . . . tempo
-- E2 . . . . . . prev param
-- E3 . . . . . . adjust value
-- K2 / K3 . . .  prev / next tab
-- K1 + E1 . . .  switch page
--
-- version 0.3.0
--

local function check_mi_ugens()
  local b = "/home/we/.local/share/SuperCollider/Extensions/"
  return util.file_exists(b .. "MiRings/MiRings.so")
     and util.file_exists(b .. "MiClouds/MiClouds.so")
end

if check_mi_ugens() then
  engine.name = "Stratum"
end

local MusicUtil = require "musicutil"

-- load stateful libs once (they self-cache). t_section must see the same
-- x_section instance that init() calls rebuild_scale on.
local x_section = include("stratum/lib/x_section")
local deja_vu   = include("stratum/lib/deja_vu")
local output    = include("stratum/lib/output")
local t_section = include("stratum/lib/t_section")

local stratum_seq    = include("stratum/lib/stratum_seq")
local stratum_rings  = include("stratum/lib/stratum_rings")
local stratum_clouds = include("stratum/lib/stratum_clouds")
local stratum_mod    = include("stratum/lib/stratum_mod")

-- ── globals ──────────────────────────────────────────────
local PAGE_NAMES   = {"STRATUM", "RINGS", "CLOUDS"}
local pages        = nil
local current_page = 1
local k1_held      = false
local screen_dirty = true
local redraw_id    = nil

-- exported so any module can request a frame
function set_dirty() screen_dirty = true end

-- ── rate constants (shared with t_section) ───────────────
RATE_LABELS = {"/8", "/4", "/2", "x1", "x2", "x4", "x8"}
RATE_MULTS  = {1/8, 1/4, 1/2, 1,   2,   4,   8}

-- ── musicutil scale names ────────────────────────────────
local function build_scale_names()
  local names = {}
  for _, s in ipairs(MusicUtil.SCALES) do
    table.insert(names, s.name)
  end
  return names
end

-- ── helpers ──────────────────────────────────────────────
-- guarded engine call. if mi-UGens missing, engine is None — no-op.
-- always test engine[cmd] before calling (guards missing commands).
local function eng(cmd)
  return function(v)
    if output.engine_ready() and engine[cmd] then engine[cmd](v) end
  end
end

local function eng_map(cmd, map)
  return function(v)
    if output.engine_ready() and engine[cmd] then engine[cmd](map(v)) end
  end
end

-- clouds_mix must reach SuperCollider; if the running engine predates the
-- command, eng() would silently no-op and mix stays at the SynthDef default.
local warned_engine_clouds_mix = false
local function eng_clouds_mix(v)
  if not output.engine_ready() then return end
  if engine.clouds_mix then
    engine.clouds_mix(v)
  elseif not warned_engine_clouds_mix then
    warned_engine_clouds_mix = true
    print("stratum: engine has no clouds_mix command — mix ignored. Reinstall Engine_Stratum.sc, then SYSTEM > RESTART.")
  end
end

local NOTE_NAMES = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}

-- ── params ───────────────────────────────────────────────
local function setup_params()
  local scale_names = build_scale_names()

  -- T SECTION (rhythm; matches “X section” grouping in PARAMETERS) -----
  params:add_separator("T section")

  params:add_number("rate_mult", "rate", 1, 7, 4,
    function(p) return RATE_LABELS[p:get()] end)
  params:set_action("rate_mult", function() t_section.rate_changed() end)

  params:add_control("jitter", "jitter",
    controlspec.new(0, 1, "lin", 0.01, 0))

  params:add_number("t_model", "t model", 1, 3, 1,
    function(p) return ({"coin","ratio","grids"})[p:get()] end)
  params:set_action("t_model", function() t_section.reset_model_state() end)

  params:add_control("t_bias", "t bias",
    controlspec.new(0, 1, "lin", 0.01, 0.5))

  params:add_control("gate_len", "gate length",
    controlspec.new(0.01, 0.99, "lin", 0.01, 0.5))

  params:add_control("gate_len_rand", "gate randomise",
    controlspec.new(0, 1, "lin", 0.01, 0))

  -- DEJA VU --------------------------------------------------
  params:add_separator("deja vu")

  params:add_control("deja_vu", "deja vu",
    controlspec.new(0, 1, "lin", 0.01, 0))

  params:add_number("dv_length", "loop length", 1, 16, 8)
  params:set_action("dv_length", function(v) deja_vu.set_length(v) end)

  params:add_option("dv_target", "dv target",
    {"off", "t", "X", "both"}, 4)

  -- X SECTION ------------------------------------------------
  params:add_separator("X section")

  params:add_control("x_spread", "spread",
    controlspec.new(0, 1, "lin", 0.01, 0.5))
  params:set_action("x_spread",
    function() x_section.reset_voice_state() end)

  params:add_control("x_bias", "bias",
    controlspec.new(0, 1, "lin", 0.01, 0.5))
  params:set_action("x_bias",
    function() x_section.reset_voice_state() end)

  params:add_control("x_steps", "steps",
    controlspec.new(0, 1, "lin", 0.01, 0.5))
  params:set_action("x_steps",
    function() x_section.reset_voice_state() end)

  params:add_number("x_diversity", "diversity", 1, 3, 1,
    function(p) return ({"same","outer-inv","gradient"})[p:get()] end)
  params:set_action("x_diversity",
    function() x_section.reset_voice_state() end)

  params:add_number("x_range", "pitch range", 1, 3, 1,
    function(p)
      return ({"narrow 0+2V","mid 0+4V","wide ±2V"})[p:get()]
    end)
  params:set_action("x_range",
    function() x_section.reset_voice_state() end)

  params:add_number("root_note", "root", 0, 11, 0,
    function(p) return NOTE_NAMES[p:get() + 1] end)
  params:set_action("root_note", function() x_section.rebuild_scale() end)

  params:add_option("scale_type", "scale", scale_names, 1)  -- 1 = Major
  params:set_action("scale_type", function() x_section.rebuild_scale() end)

  -- RINGS ----------------------------------------------------
  params:add_separator("rings")

  params:add_control("rings_struct", "structure",
    controlspec.new(0, 1, "lin", 0.01, 0.36))
  params:set_action("rings_struct", eng("rings_struct"))

  params:add_control("rings_bright", "brightness",
    controlspec.new(0, 1, "lin", 0.01, 0.5))
  params:set_action("rings_bright", eng("rings_bright"))

  params:add_control("rings_damp", "damping",
    controlspec.new(0, 1, "lin", 0.01, 0.5))
  params:set_action("rings_damp", eng("rings_damp"))

  params:add_control("rings_pos", "position",
    controlspec.new(0, 1, "lin", 0.01, 0.33))
  params:set_action("rings_pos", eng("rings_pos"))

  params:add_control("rings_odd_even", "odd/even",
    controlspec.new(0, 1, "lin", 0, 0.5))
  params:set_action("rings_odd_even", eng("rings_odd_even"))

  params:add_number("rings_poly", "polyphony", 1, 4, 4)
  params:set_action("rings_poly", eng("rings_poly"))

  params:add_option("rings_model", "model",
    {"modal","sym strings","string","FM","chords","karplusverb"}, 1)
  params:set_action("rings_model",
    eng_map("rings_model", function(v) return v - 1 end))

  params:add_option("rings_easteregg", "disastrous peace",
    {"off", "on"}, 1)
  params:set_action("rings_easteregg",
    function(v)
      if output.engine_ready() and engine.rings_easteregg then
        engine.rings_easteregg(v - 1)
      end
      set_dirty()
    end)

  params:add_control("rings_amp", "rings level",
    controlspec.new(0, 1, "lin", 0.01, 0.8))
  params:set_action("rings_amp", eng("rings_amp"))

  params:add_option("rings_bypass", "rings bypass", {"off", "on"}, 1)
  params:set_action("rings_bypass",
    eng_map("rings_bypass", function(v) return v - 1 end))

  -- CLOUDS ---------------------------------------------------
  params:add_separator("clouds")

  params:add_control("clouds_pitch", "pitch shift",
    controlspec.new(-48, 48, "lin", 1, 0, "st"))
  params:set_action("clouds_pitch", eng("clouds_pitch"))

  params:add_control("clouds_pos", "position",
    controlspec.new(0, 1, "lin", 0.01, 0.5))
  params:set_action("clouds_pos", eng("clouds_pos"))

  params:add_control("clouds_size", "size",
    controlspec.new(0, 1, "lin", 0.01, 0.3))
  params:set_action("clouds_size", eng("clouds_size"))

  params:add_number("clouds_dens", "density", 0, 100, 50)
  params:set_action("clouds_dens",
    eng_map("clouds_dens", function(v) return v / 100 end))

  params:add_control("clouds_tex", "texture",
    controlspec.new(0, 1, "lin", 0.01, 0.5))
  params:set_action("clouds_tex", eng("clouds_tex"))

  params:add_control("clouds_spread", "stereo spread",
    controlspec.new(0, 1, "lin", 0.01, 0))
  params:set_action("clouds_spread", eng("clouds_spread"))

  params:add_control("clouds_fb", "feedback",
    controlspec.new(0, 1, "lin", 0.01, 0.2))
  params:set_action("clouds_fb", eng("clouds_fb"))

  params:add_binary("clouds_freeze", "freeze", "toggle", 0)
  params:set_action("clouds_freeze", eng("clouds_freeze"))

  params:add_control("clouds_rvb", "reverb",
    controlspec.new(0, 1, "lin", 0.01, 0.1))
  params:set_action("clouds_rvb", eng("clouds_rvb"))

  params:add_option("clouds_lofi", "fidelity",
    {"hi-fi", "lo-fi"}, 1)
  params:set_action("clouds_lofi",
    eng_map("clouds_lofi", function(v) return v - 1 end))

  params:add_option("clouds_mode", "mode",
    {"granular","pitch shift","looper","spectral"}, 1)
  params:set_action("clouds_mode",
    function(v)
      if output.engine_ready() and engine.clouds_mode then
        engine.clouds_mode(v - 1)
      end
      set_dirty()
    end)

  -- step 0: allow exact 0.0 dry (0.01 quantization can leave a little wet).
  params:add_control("clouds_mix", "mix",
    controlspec.new(0, 1, "lin", 0, 0.45))
  params:set_action("clouds_mix", eng_clouds_mix)

  params:add_option("clouds_bypass", "clouds bypass", {"off", "on"}, 1)
  params:set_action("clouds_bypass",
    eng_map("clouds_bypass", function(v) return v - 1 end))

  stratum_mod.setup_params()

  -- OUTPUT ---------------------------------------------------
  params:add_separator("output")

  -- 6 modes: engine, midi, engine+midi, crow, engine+crow, midi+crow
  params:add_option("output_mode", "output mode",
    {"engine","midi","engine + midi","crow","engine + crow","midi + crow"}, 1)
  params:set_action("output_mode", function() output.mode_changed() end)

  params:add_number("midi_device", "midi device", 1, 16, 1)
  params:set_action("midi_device", function(v) output.connect_midi(v) end)

  params:add_number("midi_t1_channel", "midi t1 ch", 1, 16, 1)
  params:add_number("midi_t3_channel", "midi t3 ch", 1, 16, 2)
  params:add_number("midi_t2_channel", "midi t2 ch", 1, 16, 3)

  params:add_binary("t2_midi_out", "t2 midi out", "toggle", 0)

  params:add_binary("crow_enable", "crow enable", "toggle", 0)
  params:set_action("crow_enable", function(v)
    output.set_crow_enabled(v == 1)
    if v == 1 then
      print("stratum: crow outs active — external clock: PARAMETERS > CLOCK > clock source > crow (Crow In 1); pulse divs in CLOCK menu.")
    end
  end)
end

-- ── lifecycle ────────────────────────────────────────────
function init()
  local have_engine = check_mi_ugens()
  if not have_engine then
    print("stratum: MiRings/MiClouds extensions not found — engine disabled. install mi-UGens or use MIDI/crow.")
  end

  setup_params()

  -- modules
  output.init()
  deja_vu.init()
  x_section.init()
  t_section.init()

  params.action_write = function(_filename, _name, number)
    deja_vu.save_pset(number)
  end
  params.action_read = function(_filename, _silent, number)
    deja_vu.load_pset(number)
  end
  params.action_delete = function(_filename, _name, number)
    deja_vu.delete_pset(number)
  end

  -- output modes that need the Stratum engine → MIDI if no UGens
  if not have_engine then
    output.set_engine_ready(false)
    local mode = params:get("output_mode")
    if mode == 1 or mode == 3 or mode == 5 then
      print("stratum: engine output unavailable — falling back to MIDI")
      params:set("output_mode", 2)
    end
  else
    -- Stratum was already loaded by Script.run before this init() ran.
    output.set_engine_ready(true)
  end

  params:bang()

  stratum_mod.after_bang()

  if have_engine then
    if engine.clouds_mix then
      engine.clouds_mix(params:get("clouds_mix"))
    elseif not warned_engine_clouds_mix then
      warned_engine_clouds_mix = true
      print("stratum: engine has no clouds_mix command — mix ignored. Reinstall Engine_Stratum.sc, then SYSTEM > RESTART.")
    end
  end

  -- pages
  pages = {
    stratum_seq.new(),
    stratum_rings.new(),
    stratum_clouds.new(),
  }

  -- internal clock often starts stopped — nothing triggers until transport runs
  -- (PARAMETERS > CLOCK > reset/start if needed).
  if params:string("clock_source") == "internal" then
    clock.internal.start()
  end

  -- start clock coroutine driving the t section
  t_section.start()

  -- USB MIDI may register after init(); norns notifies via midi.add, and
  -- we also retry once after a short delay so the first vport binds.
  -- (global is lowercase `midi` from core — not `Midi`.)
  local prev_midi_add = midi.add
  midi.add = function(dev)
    if prev_midi_add then prev_midi_add(dev) end
    output.on_midi_device_change()
  end
  clock.run(function()
    clock.sleep(0.25)
    output.on_midi_device_change()
  end)

  -- 30fps redraw loop, only paints when dirty
  redraw_id = clock.run(function()
    while true do
      clock.sleep(1/30)
      if screen_dirty then
        redraw()
        screen_dirty = false
      end
    end
  end)
end

function key(n, z)
  if n == 1 then
    k1_held = (z == 1)
  end
  if pages and pages[current_page] then
    pages[current_page]:key(n, z, k1_held)
  end
  screen_dirty = true
end

function enc(n, d)
  if k1_held and n == 1 then
    current_page = util.clamp(current_page + d, 1, #pages)
  else
    if pages and pages[current_page] then
      pages[current_page]:enc(n, d, k1_held)
    end
  end
  screen_dirty = true
end

function redraw()
  screen.clear()

  -- global tab bar (y 0..8)
  local tw = 128 / #PAGE_NAMES
  for i, name in ipairs(PAGE_NAMES) do
    local x = (i - 1) * tw
    screen.level(i == current_page and 15 or 3)
    screen.move(x + tw / 2, 7)
    screen.text_center(name)
    if i == current_page then
      screen.move(x + 1, 9)
      screen.line(x + tw - 1, 9)
      screen.stroke()
    end
  end

  -- separator
  screen.level(1)
  screen.move(0, 10); screen.line(128, 10); screen.stroke()

  -- page content (y 12..63)
  if pages and pages[current_page] then
    pages[current_page]:draw()
  end

  screen.update()
end

function cleanup()
  -- Avoid double metro_stop(): norns clocks back onto metros; cancelling an
  -- already-dead handle can print "pthread_cancel() ... thread does not exist".
  local id = redraw_id
  redraw_id = nil
  if id then pcall(clock.cancel, id) end
  t_section.stop()
  stratum_mod.cleanup()
  if crow and crow.reset then
    pcall(crow.reset)
  end
end
