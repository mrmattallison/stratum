-- x_section
--
-- the pitch generator. each gate fire from t_section asks for a fresh
-- pitch on a given stream (1, 2, or 3). pipeline:
--
--   raw 0..1 (from deja_vu.query("X"))
--     → spread shaping (constant / bell / uniform / bimodal)
--     → bias offset (low / centred / high)
--     → steps (slew or quantise-to-scale, with carving CW of noon)
--     → midi note via scale window (narrow / mid / wide range)
--
-- DIVERSITY: mode 1 same | mode 2 outer streams inverted spread+steps |
-- mode 3 X1 inverted, X2 neutral (0.5/0.5/0.5), X3 normal.
--
-- norns `include()` is dofile — cache so rebuild_scale() and generate()
-- share one `windows` table.

STRATUM_LIB = STRATUM_LIB or {}
if STRATUM_LIB.x_section ~= nil then
  return STRATUM_LIB.x_section
end

local MusicUtil = require "musicutil"
local deja_vu   = include("stratum/lib/deja_vu")

local M = {}

-- tonal center: design doc — C3 (MIDI 48) + semitone 0..11
local function tonic_midi()
  return 48 + util.clamp(params:get("root_note") or 0, 0, 11)
end

local function clamp_scale_index()
  local idx = params:get("scale_type")
  if type(idx) ~= "number" then idx = 1 end
  idx = math.floor(idx + 0)
  local n = #MusicUtil.SCALES
  if n < 1 then return 1 end
  return util.clamp(idx, 1, n)
end

-- range windows: inclusive MIDI bounds (C3 = 48 = 0V). tuned for
-- midi/engine — narrower than full euro table.  v∈[0,1] picks along the
-- *ordered* scale tones in range (no V/oct octave flip; just low→high).
local RANGE_BOUNDS = {
  {48, 72},   -- 1 narrow: 0 .. +2V  → +2 octaves from C3
  {48, 96},   -- 2 mid:    0 .. +4V  → +4 octaves from C3
  {24, 72},   -- 3 wide:   −2 .. +2V → ±2 octaves about C3 (symmetric)
}

-- per-range cached arrays of in-scale midi notes
local windows = {{}, {}, {}}

-- pitch classes present in current scale (for STEPS carving prominence)
local scale_pitch_classes = {}

-- per-stream history for slew + UI display
local prev_norm = {0.5, 0.5, 0.5}
local last_norm = {0.5, 0.5, 0.5}

-- ── scale build ──────────────────────────────────────────
function M.rebuild_scale()
  local scale_idx = clamp_scale_index()
  local root      = tonic_midi()

  -- pass scale by *numeric index* — matches params option index and avoids
  -- string/out-of-range PSET mismatches that leave `windows` empty (then
  -- every pitch became fallback 60).
  local full = MusicUtil.generate_scale(root, scale_idx, 6)
  if full == nil or #full == 0 then
    print("stratum: generate_scale failed; falling back to major @ C3")
    full = MusicUtil.generate_scale(48, 1, 6)
  end

  scale_pitch_classes = {}
  for _, note in ipairs(full) do
    scale_pitch_classes[note % 12] = true
  end

  for i = 1, 3 do
    local lo, hi = RANGE_BOUNDS[i][1], RANGE_BOUNDS[i][2]
    local w = {}
    for _, note in ipairs(full) do
      if note >= lo and note <= hi then table.insert(w, note) end
    end
    -- at least one pitch in range
    if #w == 0 then table.insert(w, util.clamp(root, lo, hi)) end
    -- if the filtered scale only hit one pitch class in this span, pitch
    -- mapping collapses to one midi note — widen to chromatic in-range.
    if #w == 1 and (hi - lo) >= 1 then
      w = {}
      for nn = lo, hi do
        table.insert(w, nn)
      end
    end
    windows[i] = w
  end
  M.reset_voice_state()
end

-- ── shaping pipeline ─────────────────────────────────────
-- deterministic 0..1 jitter from raw (same raw → same jitter). bell zone
-- previously used math.random(), which re-randomised every tick and washed
-- out DEJA VU buffer-lock even at amount = 1.
local function det01(raw, salt)
  local x = raw * 9973.413 + salt * 0.3183098861
  return x - math.floor(x)
end

-- 4-zone distribution shaping per the design doc.
local function shaped(raw, spread)
  if spread < 0.25 then
    -- concentrate toward centre (constant → bell)
    local k = spread * 4                      -- 0..1
    return raw * k + 0.5 * (1 - k)
  elseif spread < 0.5 then
    -- bell: widen distribution like averaging uniforms, without fresh RNG
    return util.clamp((raw + det01(raw, 1) + det01(raw, 2)) / 3, 0, 1)
  elseif spread < 0.75 then
    -- uniform: pass through
    return raw
  else
    -- bimodal: push toward extremes
    local amt = (spread - 0.75) * 4           -- 0..1
    if raw < 0.5 then
      return raw * (1 - amt)
    else
      return 1 - (1 - raw) * (1 - amt)
    end
  end
end

local function biased(v, bias)
  return util.clamp(v + (bias - 0.5) * 0.6, 0, 1)
end

-- prominence for carving: root > fifth > other scale tones > chromatic
local function prominence(note, root)
  local pc = note % 12
  local rpc = root % 12
  if pc == rpc then return 4 end
  if pc == (rpc + 7) % 12 then return 3 end
  if scale_pitch_classes[pc] then return 2 end
  return 1
end

local function idx_from_norm(v, w)
  local n = #w
  if n <= 1 then return 1 end
  local idx = math.floor(v * (n - 1) + 0.5) + 1
  return util.clamp(idx, 1, n)
end

local function closest_idx(note, w)
  local best_i, best_d = 1, 99999
  for i, pitch in ipairs(w) do
    local d = math.abs(pitch - note)
    if d < best_d then best_d = d; best_i = i end
  end
  return best_i
end

-- map post-pipeline 0..1 value to a midi note in the active range
local function note_from_norm(v, range_idx)
  local w = windows[range_idx] or windows[1]
  if #w == 0 then return 60 end
  return w[idx_from_norm(v, w)]
end

local function norm_from_note(note, range_idx)
  local w = windows[range_idx] or windows[1]
  local n = #w
  if n <= 1 then return 0.5 end
  local idx = closest_idx(note, w)
  return (idx - 1) / (n - 1)
end

-- STEPS > 0.75: progressively snap index toward most prominent scale tones (→ root at 1.0)
local function carve_note(note, range_idx, steps)
  local q = (steps - 0.5) * 2
  if q <= 0.5 then return note end
  local t = (q - 0.5) * 2
  local w = windows[range_idx] or windows[1]
  if #w <= 1 then return note end

  local root = tonic_midi()
  local idx = closest_idx(note, w)

  local max_p = -1
  for _, pitch in ipairs(w) do
    max_p = math.max(max_p, prominence(pitch, root))
  end

  local cand = {}
  for i, pitch in ipairs(w) do
    if prominence(pitch, root) == max_p then
      table.insert(cand, i)
    end
  end
  table.sort(cand, function(a, b)
    return math.abs(w[a] - note) < math.abs(w[b] - note)
  end)
  local target_idx = cand[1]

  local new_idx = math.floor(idx + (target_idx - idx) * t + 0.5)
  new_idx = util.clamp(new_idx, 1, #w)
  return w[new_idx]
end

local function diversity_params(stream, spread, bias, steps)
  local mode = params:get("x_diversity")
  if mode == 2 and (stream == 1 or stream == 3) then
    return 1 - spread, bias, 1 - steps
  elseif mode == 3 then
    if stream == 1 then
      return 1 - spread, bias, 1 - steps
    elseif stream == 2 then
      return 0.5, 0.5, 0.5
    end
  end
  return spread, bias, steps
end

-- ── public API ───────────────────────────────────────────
-- generate a pitch for the given stream (1, 2, or 3).
-- returns (midi_note, normalised_value_for_modulation)
function M.generate(stream)
  local raw    = deja_vu.query("X")
  local spread = params:get("x_spread")
  local bias   = params:get("x_bias")
  local steps  = params:get("x_steps")
  local range  = util.clamp(math.floor(0.5 + (params:get("x_range") or 1)), 1, 3)

  spread, bias, steps = diversity_params(stream, spread, bias, steps)

  local v_latent = shaped(raw, spread)
  v_latent = biased(v_latent, bias)

  local prev = prev_norm[stream] or 0.5
  local v_out

  if steps < 0.5 then
    -- slew: CCW = slow glide (alpha≈0.04); → noon approaches tracking latent.
    -- (plain steps*2 would freeze at 0 — unusable for “smooth” zone.)
    local alpha = util.linlin(0, 0.5, 0.04, 1, steps)
    v_out = prev + (v_latent - prev) * alpha
  else
    -- noon = S&H of latent; CW = quantise (+ carve past ~75%)
    v_out = v_latent
  end

  prev_norm[stream] = v_out

  local note = note_from_norm(v_out, range)
  if steps > 0.5 then
    note = carve_note(note, range, steps)
  end

  local v_ui = norm_from_note(note, range)
  last_norm[stream] = v_ui

  return note, v_ui
end

function M.last_value(stream)
  return last_norm[stream] or 0.5
end

-- call when X pitch params change so slew / stale state does not ignore new shaping
function M.reset_voice_state()
  prev_norm = {0.5, 0.5, 0.5}
  last_norm = {0.5, 0.5, 0.5}
end

function M.init()
  M.rebuild_scale()
end

STRATUM_LIB.x_section = M
return M
