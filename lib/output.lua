-- output
--
-- routes gate+pitch events from t_section to engine / MIDI / crow per output_mode.
--
-- MIDI NOTE (norns): midi.connect(n) returns a *virtual port* wrapper.
-- note_on only reaches USB if that vport has a device (see core/vport.lua).
-- Use SYSTEM > DEVICES > MIDI to map hardware to vports. this module
-- falls back to the first connected vport if the requested one is empty.
--
-- output_mode (1..6):
--   1 engine                       4 crow
--   2 midi                         5 engine + crow
--   3 engine + midi                6 midi + crow
--
-- channel mapping:
--   t1 → midi midi_t1_channel, crow Out 1 (gate) + Out 2 (CV from X1)
--   t3 → midi midi_t3_channel, crow Out 3 (gate) + Out 4 (CV from X3)
--   t2 → midi midi_t2_channel (only if t2_midi_out on); no crow out
--
-- engine: single Rings voice. t1/t3 alternate excitation (Option C
-- from the design doc). t2 does not trigger Rings — MIDI/gated stream only

STRATUM_LIB = STRATUM_LIB or {}
if STRATUM_LIB.output ~= nil then
  return STRATUM_LIB.output
end

local M = {}

-- ── readiness flags ──────────────────────────────────────
local engine_ready = false
local crow_enabled = false   -- mirror of crow_enable param

-- ── midi ─────────────────────────────────────────────────
local midi_out = nil
local midi_active = {}       -- midi_active[ch] = currently sounding note

local warned_no_device  = false
local warned_fallback   = nil   -- "1->3" style string, print once per change

-- Resolve usb midi: requested vport or first connected. Returns true if
-- a device is present (note_on will not be a silent no-op).
function M.ensure_midi_out()
  if midi == nil or midi.vports == nil then return false end

  local want = util.clamp(params:get("midi_device") or 1, 1, 16)
  local vp = midi.vports[want]

  if vp and vp.connected and vp.device then
    midi_out = midi.connect(want)
    warned_no_device = false
    return true
  end

  for i = 1, 16 do
    local v = midi.vports[i]
    if v and v.connected and v.device then
      local key = want .. "->" .. i
      if warned_fallback ~= key then
        print("stratum: midi vport " ..
          want .. " has no device; sending on vport " ..
          i .. " (" .. tostring(v.name) .. ")")
        warned_fallback = key
      end
      midi_out = midi.connect(i)
      warned_no_device = false
      return true
    end
  end

  if not warned_no_device then
    print("stratum: no MIDI output device — check USB," ..
      " then SYSTEM > DEVICES > MIDI to assign a virtual port.")
    warned_no_device = true
  end
  midi_out = midi.connect(want)
  return false
end

function M.connect_midi()
  M.ensure_midi_out()
end

-- when a device is hot-plugged, try again (silent except normal fallback msg)
function M.on_midi_device_change()
  warned_no_device = false
  warned_fallback = nil
  M.ensure_midi_out()
end

-- ── readiness setters / getters ──────────────────────────
function M.set_engine_ready(b) engine_ready = b end
function M.engine_ready()      return engine_ready end

function M.set_crow_enabled(b)
  crow_enabled = b
  if b then
    M.zero_crow_outputs()
  end
end

-- silence crow jacks when enabling output or on cleanup (no-op if no hardware)
local function crow_hardware_connected()
  if crow == nil then return false end
  if crow.connected and not crow.connected() then return false end
  return true
end

function M.zero_crow_outputs()
  if not crow_hardware_connected() then return end
  for i = 1, 4 do
    crow.output[i].volts = 0
  end
end

local function crow_ready()
  return crow_enabled and crow_hardware_connected()
end

-- ── mode capability checks ───────────────────────────────
local function has_engine(m) return m == 1 or m == 3 or m == 5 end
local function has_midi(m)   return m == 2 or m == 3 or m == 6 end
local function has_crow(m)   return m == 4 or m == 5 or m == 6 end

-- ── helpers ──────────────────────────────────────────────
local function midi_channel_for(ch)
  if ch == "t1" then return params:get("midi_t1_channel")
  elseif ch == "t3" then return params:get("midi_t3_channel")
  elseif ch == "t2" then return params:get("midi_t2_channel") end
end

local function send_midi_note(chan, note, dur)
  if not chan or not note then return end
  M.ensure_midi_out()
  if not midi_out then return end
  -- monophonic-per-channel: kill the previous note before triggering
  if midi_active[chan] then
    midi_out:note_off(midi_active[chan], 0, chan)
  end
  midi_out:note_on(note, 100, chan)
  midi_active[chan] = note
  clock.run(function()
    clock.sleep(dur)
    if midi_active[chan] == note then
      midi_out:note_off(note, 0, chan)
      midi_active[chan] = nil
    end
  end)
end

local function send_engine_gate(note, dur)
  if not engine_ready then return end
  if engine.rings_pit then engine.rings_pit(note) end
  if engine.rings_gate then engine.rings_gate(1) end
  clock.run(function()
    clock.sleep(dur)
    if engine_ready and engine.rings_gate then engine.rings_gate(0) end
  end)
end

local function send_crow_gate(out_n, dur)
  if not crow_ready() then return end
  -- short rise, then fall over the gate duration
  crow.output[out_n].action = "{to(5,0.002),to(0," .. dur .. ")}"
  crow.output[out_n]()
end

local function send_crow_cv(out_n, note)
  if not crow_ready() or not note then return end
  crow.output[out_n].volts = (note - 48) / 12   -- C3 = MIDI 48 = 0V
end

-- ── all-notes-off (panic on mode change) ─────────────────
local function panic_midi()
  if not midi_out then return end
  for ch, note in pairs(midi_active) do
    midi_out:note_off(note, 0, ch)
  end
  midi_active = {}
end

-- ── public api ───────────────────────────────────────────
-- fire a single gate event. ch ∈ {"t1","t2","t3"}, note is midi#,
-- duration is seconds.
function M.fire(ch, note, dur)
  local mode = params:get("output_mode")

  -- ENGINE (single Rings voice, t1/t3 alternate; t2 silent on engine)
  if has_engine(mode) and ch ~= "t2" and engine_ready then
    send_engine_gate(note, dur)
  end

  -- MIDI
  if has_midi(mode) then
    if ch == "t2" and params:get("t2_midi_out") ~= 1 then
      -- t2 midi out gated by separate toggle (default off)
    else
      send_midi_note(midi_channel_for(ch), note, dur)
    end
  end

  -- CROW: gate on Out1/Out3, CV on Out2/Out4 (no t2 output)
  if has_crow(mode) and crow_ready() then
    if ch == "t1" then
      send_crow_cv(2, note)
      send_crow_gate(1, dur)
    elseif ch == "t3" then
      send_crow_cv(4, note)
      send_crow_gate(3, dur)
    end
  end
end

-- called by the output_mode param action
function M.mode_changed()
  -- panic on mode flip so we don't leave stuck MIDI notes
  panic_midi()
end

function M.init()
  M.ensure_midi_out()
end

STRATUM_LIB.output = M
return M
