-- deja_vu
--
-- the shared loop memory for the t and X sections. each section has its
-- own circular buffer; the dv_target param decides which sections
-- consult the buffer vs. produce fresh randomness.
--
-- amount knob:
--   0.0 ........ all fresh random (buffer ignored)
--   0.0 → 0.5 .. probability of recycling buffered value rises 0 → 1
--   0.5 ........ fully locked loop (no new data written)
--   0.5 → 1.0 .. zone 2: shuffle prob rises 0 → 1 (jump to random buffer slot)
--
-- target options:  off | t | X | both
--
-- norns `include()` is dofile — without this cache, every include gets a
-- fresh buffer and init() runs on a different table than query().

STRATUM_LIB = STRATUM_LIB or {}
if STRATUM_LIB.deja_vu ~= nil then
  return STRATUM_LIB.deja_vu
end

local M = {}

-- per-section state
local state = {
  t = {buf = {}, pos = 1},
  X = {buf = {}, pos = 1},
}

local length = 8

-- ── helpers ──────────────────────────────────────────────
-- maps the deja_vu knob 0..1 to a probability
--   zone 1: 0..0.5 → 0..1
--   zone 2: 0.5..1 → 1..2  (shuffle prob = result - 1)
local function amount_to_prob(a)
  if a <= 0.5 then return a * 2 end
  return 1 + (a - 0.5) * 2
end

-- is this section currently consulting the loop buffer?
local function section_targeted(section)
  local target = params:get("dv_target")  -- 1=off 2=t 3=X 4=both
  if target == 1 then return false
  elseif target == 2 then return section == "t"
  elseif target == 3 then return section == "X"
  elseif target == 4 then return true end
  return false
end

local function step_pos(s)
  s.pos = (s.pos % length) + 1
end

-- ── public api ───────────────────────────────────────────
-- query a 0..1 value for `section` ("t" or "X").
-- when the section is not targeted, always fresh random.
function M.query(section)
  local s = state[section]
  if s == nil then return math.random() end

  if not section_targeted(section) then
    return math.random()
  end

  local amt  = params:get("deja_vu")
  local prob = amount_to_prob(amt)

  -- still warming the buffer up to length
  if #s.buf < length then
    local val = math.random()
    table.insert(s.buf, val)
    return val
  end

  local r = math.random()

  if prob <= 1 then
    -- ZONE 1: prob of recycling buffer position vs. overwriting
    if r < prob then
      local val = s.buf[s.pos]
      step_pos(s)
      return val
    else
      local val = math.random()
      s.buf[s.pos] = val
      step_pos(s)
      return val
    end
  else
    -- ZONE 2: shuffle vs sequential locked step
    local shuffle_prob = prob - 1
    if r < shuffle_prob then
      return s.buf[math.random(length)]
    else
      local val = s.buf[s.pos]
      step_pos(s)
      return val
    end
  end
end

-- adjust loop length; truncate or leave room to grow
function M.set_length(n)
  length = math.max(1, math.min(16, n))
  for _, s in pairs(state) do
    while #s.buf > length do table.remove(s.buf) end
    if s.pos > length then s.pos = 1 end
  end
end

-- reseed — clear both buffers so they refill with fresh randomness
function M.reseed()
  for _, s in pairs(state) do
    s.buf = {}
    s.pos = 1
  end
end

-- cycles dv_target on K1+K3 shortcut
function M.cycle_target()
  local cur = params:get("dv_target")
  params:set("dv_target", (cur % 4) + 1)
end

-- ── PSET sidecars (params.action_write / action_read / action_delete) ──
local function pset_path(number)
  return norns.state.data .. "/" .. tostring(number) .. "/deja_vu.data"
end

function M.save_pset(number)
  local dir = norns.state.data .. "/" .. tostring(number)
  os.execute("mkdir -p " .. dir)
  tab.save({
    t = { buf = state.t.buf, pos = state.t.pos },
    X = { buf = state.X.buf, pos = state.X.pos },
  }, pset_path(number))
end

function M.load_pset(number)
  local data = tab.load(pset_path(number))
  if type(data) ~= "table" then return end
  local L = params:get("dv_length")
  M.set_length(L)
  local function restore(key, saved)
    if type(saved) ~= "table" then return end
    local buf = {}
    local src = saved.buf or {}
    for i = 1, math.min(L, #src) do
      buf[i] = src[i]
    end
    state[key].buf = buf
    local n = #buf
    state[key].pos = util.clamp(saved.pos or 1, 1, math.max(1, n))
  end
  restore("t", data.t)
  restore("X", data.X)
end

function M.delete_pset(number)
  os.remove(pset_path(number))
end

function M.init()
  state.t.buf = {}; state.t.pos = 1
  state.X.buf = {}; state.X.pos = 1
end

STRATUM_LIB.deja_vu = M
return M
