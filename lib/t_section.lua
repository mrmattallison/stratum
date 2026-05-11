-- t_section
--
-- the rhythm engine. one clock coroutine fires on a master-clock-locked
-- division. on each tick:
--   • t2 fires unconditionally at 50% duty (master pulse, drives X2)
--   • the active model decides whether / how often t1 and t3 fire
--     (coin: exclusive t1|t3 · ratio: phased bursts · grids: euclidean)
--   • the X section is asked for a fresh pitch for the firing stream(s)
--   • output.fire(...) routes the gate+pitch to engine / midi / crow
--
-- timing uses clock.sleep from clock_tempo / get_beat_sec (not clock.sync)
-- so the sequencer runs when clock PARAMS > source is "midi" but no MIDI
-- clock is wired in (clock.sync would block forever in that case).
-- jitter is applied after the wait: tempo from param, slight timing drift.
--
-- norns `include()` is dofile — cache so only one clock coroutine runs and
-- we use the same x_section / output / deja_vu tables as the main script.

STRATUM_LIB = STRATUM_LIB or {}
if STRATUM_LIB.t_section ~= nil then
  return STRATUM_LIB.t_section
end

local x_section = include("stratum/lib/x_section")
local deja_vu   = include("stratum/lib/deja_vu")
local output    = include("stratum/lib/output")

local M = {}

-- coroutine handles
local clock_id = nil

-- live state for the UI (gate "lit" decay)
local gate_lit = {t1 = 0, t2 = 0, t3 = 0}

-- max additional sleep when jitter = 1.0 (seconds). a tasteful upper
-- bound so even max jitter never derails tempo audibly.
local MAX_JITTER_S = 0.12

-- model 2: phase integrators (advance each master tick)
local phase_t1, phase_t3 = 0, 0

-- model 3: euclidean step counter 1..EUCLID_LEN
local EUCLID_LEN = 16
local grid_step  = 0

-- ── public state queries (UI) ────────────────────────────
-- returns an opacity 0..1 for live gate dot drawing (wall-clock so it
-- still animates when clock.get_beats does not advance e.g. midi source
-- with no clock in).
function M.gate_opacity(ch)
  local off = gate_lit[ch] or 0
  local now = util.time()
  if now >= off then return 0 end
  local remain = off - now
  return math.min(1, remain * 12)
end

-- ── helpers ──────────────────────────────────────────────
local function rate_division()
  -- clock.sync expects "beats". if rate = x1, sync every 1 beat.
  -- if x2, sync every 0.5 beats. if /2, every 2 beats. etc.
  local idx  = params:get("rate_mult")
  local mult = RATE_MULTS[idx] or 1
  return 1 / mult
end

local function period_seconds()
  -- duration of one tick in seconds (for gate length math)
  local bpm = params:get("clock_tempo")
  return rate_division() * (60 / math.max(bpm, 1))
end

local function jittered_sleep()
  local j = params:get("jitter")
  if j > 0 then
    clock.sleep(math.random() * j * MAX_JITTER_S)
  end
end

-- gate length with optional randomisation
local function gate_duration_s(period)
  local len  = params:get("gate_len")
  local rand = params:get("gate_len_rand")
  if rand > 0 then
    local offset = (math.random() - 0.5) * rand
    len = util.clamp(len + offset, 0.01, 0.99)
  end
  return period * len
end

-- ── routing models ───────────────────────────────────────
-- design: t1 rate = RATIOS[idx], t3 rate = RATIOS[#RATIOS - idx + 1]
-- CCW bias (0) → t1 fast / t3 slow; CW (1) → the reverse. centre = both 1.
local RATIOS = {1/4, 1/3, 1/2, 2/3, 1, 3/2, 2, 3, 4}

-- model 1: coin toss. below bias → t3, at/above → t1 so CCW (0) = all t1,
-- CW (1) = all t3 (matches design prose + typical “bias right” expectation).
local function route_coin(bias, dv_val)
  return dv_val < bias and "t3" or "t1"
end

-- true if step (1..len) is a hit for Euclidean(k, len) (Bjorklund test)
local function euclid_hit(hits, len, step1)
  hits = util.clamp(math.floor(hits + 0.5), 0, len)
  if hits >= len then return true end
  if hits <= 0 then return false end
  return ((step1 - 1) * hits) % len < hits
end

-- model 2: advance phase; may fire t1 and/or t3 multiple times in one tick.
local function collect_ratio_fires(bias, out)
  -- bias 0 → high idx (t1 fast); bias 1 → low idx (t1 slow) — see design doc
  local idx = util.clamp(
    math.floor((1 - bias) * (#RATIOS - 1e-9)) + 1, 1, #RATIOS)
  local r1 = RATIOS[idx]
  local r3 = RATIOS[#RATIOS - idx + 1]
  phase_t1 = phase_t1 + r1
  phase_t3 = phase_t3 + r3
  while phase_t1 >= 1 do
    phase_t1 = phase_t1 - 1
    out[#out + 1] = "t1"
  end
  while phase_t3 >= 1 do
    phase_t3 = phase_t3 - 1
    out[#out + 1] = "t3"
  end
end

-- model 3: one euclidean pattern per stream; bias moves hit count t1 vs t3.
local function collect_grids_fires(bias, out)
  grid_step = grid_step + 1
  if grid_step > EUCLID_LEN then grid_step = 1 end
  local i   = grid_step
  -- bias 0 → many t1 hits / few t3; bias 1 → few t1 / many t3
  local h1f = util.linlin(0, 1, 2, EUCLID_LEN - 2, 1 - bias)
  local h3f = util.linlin(0, 1, 2, EUCLID_LEN - 2, bias)
  local h1  = util.clamp(math.floor(h1f + 0.5), 1, EUCLID_LEN - 1)
  local h3  = util.clamp(math.floor(h3f + 0.5), 1, EUCLID_LEN - 1)
  if euclid_hit(h1, EUCLID_LEN, i) then out[#out + 1] = "t1" end
  if euclid_hit(h3, EUCLID_LEN, i) then out[#out + 1] = "t3" end
end

-- mark a gate as "lit" until `dur` seconds from now (for UI)
local function mark_lit(ch, dur_s)
  gate_lit[ch] = util.time() + dur_s
end

local function fire_t_stream(ch, period)
  local stream = (ch == "t1") and 1 or 3
  local note, _ = x_section.generate(stream)
  local dur     = gate_duration_s(period)
  output.fire(ch, note, dur)
  mark_lit(ch, dur)
end

-- ── tick: one master pulse ───────────────────────────────
function M.tick()
  local period  = period_seconds()
  local t_model = params:get("t_model")
  local bias    = params:get("t_bias")

  -- advance DEJA VU buffer for “t” every tick (model 1 uses it for routing)
  local dv_t = deja_vu.query("t")

  -- ── t2 pulse: always fires, 50% duty ────────────────────
  local x2_note = select(1, x_section.generate(2))
  local t2_dur = period * 0.5
  output.fire("t2", x2_note, t2_dur)
  mark_lit("t2", t2_dur)
  if set_dirty then set_dirty() end

  -- ── t1 / t3: model-dependent (exclusive coin vs multi-fire ratio/grids)
  if t_model == 1 then
    local ch = route_coin(bias, dv_t)
    fire_t_stream(ch, period)
  else
    local fires = {}
    if t_model == 2 then
      collect_ratio_fires(bias, fires)
    else
      collect_grids_fires(bias, fires)
    end
    for _, ch in ipairs(fires) do
      fire_t_stream(ch, period)
    end
  end
end

-- ── coroutine lifecycle ──────────────────────────────────
local function wait_tick()
  local div_ok, div = pcall(rate_division)
  if not div_ok or not div then div = 1 end
  -- same period as one clock.sync(div) quantum, without blocking on transport
  local sec = clock.get_beat_sec() * div
  clock.sleep(math.max(0.001, sec))
end

local function loop()
  while true do
    wait_tick()
    jittered_sleep()
    local ok, err = pcall(M.tick)
    if not ok then print("stratum t_section tick error: " .. tostring(err)) end
  end
end

function M.start()
  if clock_id then return end
  clock_id = clock.run(loop)
end

function M.stop()
  if not clock_id then return end
  local id = clock_id
  clock_id = nil
  pcall(clock.cancel, id)
end

-- restart the coroutine when rate changes so the new division applies
-- quickly instead of finishing the previous wait interval.
function M.rate_changed()
  if clock_id then
    M.stop()
    M.start()
  end
end

function M.init()
  phase_t1, phase_t3 = 0, 0
  grid_step = 0
end

-- call when switching t model (param action) so phases don’t carry over oddly
function M.reset_model_state()
  phase_t1, phase_t3 = 0, 0
  grid_step = 0
end

STRATUM_LIB.t_section = M
return M
