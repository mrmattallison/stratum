# stratum

A generative layered sequencer for **monome norns** that creates probabilistic **t** rhythms, **X** pitches with DEJA VU loop memory, **MiRings → MiClouds** when [mi-UGens](https://github.com/v7b1/mi-UGens) are installed, plus **MIDI** and **crow** outputs.

## Acknowledgments
- based on the Èmilie Gillet Mutable Instruments code (Rings + Clouds)
- uses @okyeron SC MUgens extensions by VBoehm
- script inspiration inc. @jaseknighter's krill and @21echos pedalboard
- modulation LFO's copied from @sonoCircuit's concrete 
- lfo lib added by @dndrks + @sixolet, with improvements by @Dewb and @sonoCircuit

## Requirements

- **norns** (current firmware)
- Optional **sound**: vboehm **MiRings** + **MiClouds** SuperCollider extensions (`MiRings.so` / `MiClouds.so` under `~/.local/share/SuperCollider/Extensions/`). Without them the script falls back to MIDI-only-friendly output modes.
- Optional **crow**: USB-connected [crow](https://monome.org/docs/crow/) for gates + V/oct.

## Install

1. Copy this folder to `dust/code/stratum/` on norns (or clone into that path).
2. Install **`lib/Engine_Stratum.sc`** using your usual Crone engine install method (same layout as other norns engines loading `Engine_Stratum`).
3. **SYSTEM → RESTART** (or restart SuperCollider) after adding new UGens or the engine class.

## Quick Start

- **PARAMETERS**: clock/tempo, **T / X / DEJA VU**, **rings**, **clouds**, **modulation** LFOs, **output**.
- **STRATUM** page: tabs **UI | T | DEJA VU | X** — **K1+K2** reseed DEJA VU buffers, **K1+K3** cycle DV target.
- **Output modes**: engine only, MIDI, engine+MIDI, crow, engine+crow, MIDI+crow (`output mode`). Enable **`crow enable`** when crow is patched.

## Clock + Crow

Stratum follows the **global norns clock** (`clock.get_beat_sec()`), same as **PARAMETERS → CLOCK**:

- **Internal / MIDI / Link / crow** sources are chosen in the **system CLOCK** menu — not inside this script’s params.
- To **clock norns from modular** via crow: set **clock source** to **crow** and adjust **crow in div** to match your pulse rate (see [control + clock](https://monome.org/docs/norns/control-clock/)).
- To **send clock out** over crow, use **crow out** / **crow out div** in the same menu.

Stratum **crow outputs** when mode includes crow:

| crow jack | Signal |
|-----------|--------|
| **Out 1** | Gate (t1) |
| **Out 2** | V/oct from **X1** (C3 = MIDI 48 = 0 V) |
| **Out 3** | Gate (t3) |
| **Out 4** | V/oct from **X3** |

**t2** does not drive crow outs (dense clock / MIDI lane only).

## MIDI

Map interfaces under **SYSTEM → DEVICES → MIDI**. Choose **`midi device`** in PARAMETERS for Stratum’s USB MIDI port. Per-stream channels: **`midi t1 ch`**, **`midi t3 ch`**, **`midi t2 ch`**. **`t2 midi out`** gates whether t2 sends notes.

## PSETs

Use **PARAMETERS → PSET** to save/load snapshots (built-in norns UI). Stratum also saves **DEJA VU loop buffers** to sidecar files under `dust/data/stratum/<slot>/deja_vu.data` via `params.action_write` / `action_read`.

## Grid / Arc

None — Norns Only

## License / Credits

Mutable Instruments-inspired signal flow and code; mi-UGens by vboehm / community. Engine plumbing conceived by myself with AI support from Claude in piecing it together.
