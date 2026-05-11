// Stratum — MiRings → MiClouds
//
//   SynthDef(...).add → context.server.sync → Synth.new(..., [\out, context.out_b.index], context.xg)
//   — not Function.play, and out bus is the integer context.out_b.index.
//
// UGens: okyeron / vboehm mi-UGens (MiRings / MiClouds class file API).

Engine_Stratum : CroneEngine {

  var synth;

  *new { arg context, callback;
    ^super.new(context, callback);
  }

  alloc {

    SynthDef(\stratum, {
      arg out,
          rings_pit=48.0, rings_struct=0.36, rings_bright=0.5,
          rings_damp=0.5, rings_pos=0.33, rings_model=0,
          rings_poly=4, rings_easteregg=0,
          rings_gate=0, rings_amp=0.8,
          rings_odd_even=0.5,
          rings_bypass=0,
          clouds_pos=0.5, clouds_size=0.3, clouds_pitch=0,
          clouds_dens=0.5, clouds_tex=0.5, clouds_spread=0,
          clouds_fb=0.2, clouds_freeze=0, clouds_rvb=0.1,
          clouds_lofi=0, clouds_mode=0,
          clouds_mix=0,
          clouds_bypass=0;

      var ring_trig, rings_pair, rings_even, rings_odd, rings_mono, rings_sig,
          rings_out, clouds_sig, blend, wet;

      ring_trig = Trig.kr(rings_gate, 0.01);

      // MiRings: [ EVEN, ODD ] — complementary partial / pickup components.
      // rings_odd_even: 0 = ODD only, 1 = EVEN only, 0.5 = equal mix (CW…CCW semantics from Lua UI).
      rings_pair = MiRings.ar(
        in: 0,
        trig: ring_trig,
        pit: rings_pit,
        struct: rings_struct,
        bright: rings_bright,
        damp: rings_damp,
        pos: rings_pos,
        model: rings_model,
        poly: rings_poly,
        intern_exciter: 0,
        easteregg: rings_easteregg,
        bypass: rings_bypass,
        mul: 1.0,
        add: 0
      );

      rings_even = rings_pair[0];
      rings_odd  = rings_pair[1];

      rings_mono = (rings_even * rings_odd_even) + (rings_odd * (1 - rings_odd_even));
      rings_sig = rings_mono * rings_amp;

      rings_out = [rings_sig, rings_sig];

      clouds_sig = MiClouds.ar(
        rings_out,
        pit: clouds_pitch,
        pos: clouds_pos,
        size: clouds_size,
        dens: clouds_dens,
        tex: clouds_tex,
        drywet: 1.0,
        in_gain: 1.0,
        spread: clouds_spread,
        rvb: clouds_rvb,
        fb: clouds_fb,
        freeze: clouds_freeze,
        mode: clouds_mode,
        lofi: clouds_lofi,
        trig: 0
      );

      // rings_out stays "dry MiRings"; clouds_sig is full Wet Clouds branch.
      // clouds_mix 0=dry Rings only, 1=Clouds process only — still serial into
      // Clouds internally; blend is output crossfade (not a parallel second Rings).
      blend = (rings_out * (1 - clouds_mix)) + (clouds_sig * clouds_mix);
      wet = (blend * (1 - clouds_bypass)) + (rings_out * clouds_bypass);

      Out.ar(out, wet);
    }).add;

    context.server.sync;

    synth = Synth.new(\stratum, [
        \out, context.out_b.index,
        \rings_gate, 0,
        \rings_odd_even, 0.5,
        \clouds_mix, 0.45
      ],
      context.xg);

    context.server.sync;

    this.addCommand(\rings_gate, "f", { arg msg; synth.set(\rings_gate, msg[1]); });
    this.addCommand(\rings_pit, "f", { arg msg; synth.set(\rings_pit, msg[1]); });
    this.addCommand(\rings_struct, "f", { arg msg; synth.set(\rings_struct, msg[1]); });
    this.addCommand(\rings_bright, "f", { arg msg; synth.set(\rings_bright, msg[1]); });
    this.addCommand(\rings_damp, "f", { arg msg; synth.set(\rings_damp, msg[1]); });
    this.addCommand(\rings_pos, "f", { arg msg; synth.set(\rings_pos, msg[1]); });
    this.addCommand(\rings_model, "f", { arg msg; synth.set(\rings_model, msg[1]); });
    this.addCommand(\rings_poly, "f", { arg msg; synth.set(\rings_poly, msg[1]); });
    this.addCommand(\rings_easteregg, "f", { arg msg; synth.set(\rings_easteregg, msg[1]); });
    this.addCommand(\rings_amp, "f", { arg msg; synth.set(\rings_amp, msg[1]); });
    this.addCommand(\rings_odd_even, "f", { arg msg; synth.set(\rings_odd_even, msg[1]); });
    this.addCommand(\rings_bypass, "f", { arg msg; synth.set(\rings_bypass, msg[1]); });

    this.addCommand(\clouds_pos, "f", { arg msg; synth.set(\clouds_pos, msg[1]); });
    this.addCommand(\clouds_size, "f", { arg msg; synth.set(\clouds_size, msg[1]); });
    this.addCommand(\clouds_pitch, "f", { arg msg; synth.set(\clouds_pitch, msg[1]); });
    this.addCommand(\clouds_dens, "f", { arg msg; synth.set(\clouds_dens, msg[1]); });
    this.addCommand(\clouds_tex, "f", { arg msg; synth.set(\clouds_tex, msg[1]); });
    this.addCommand(\clouds_spread, "f", { arg msg; synth.set(\clouds_spread, msg[1]); });
    this.addCommand(\clouds_fb, "f", { arg msg; synth.set(\clouds_fb, msg[1]); });
    this.addCommand(\clouds_freeze, "f", { arg msg; synth.set(\clouds_freeze, msg[1]); });
    this.addCommand(\clouds_rvb, "f", { arg msg; synth.set(\clouds_rvb, msg[1]); });
    this.addCommand(\clouds_lofi, "f", { arg msg; synth.set(\clouds_lofi, msg[1]); });
    this.addCommand(\clouds_mode, "f", { arg msg; synth.set(\clouds_mode, msg[1]); });
    this.addCommand(\clouds_mix, "f", { arg msg; synth.set(\clouds_mix, msg[1]); });
    this.addCommand(\clouds_bypass, "f", { arg msg; synth.set(\clouds_bypass, msg[1]); });
  }

  free {
    synth.free;
  }

}
