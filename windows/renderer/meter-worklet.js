// Medición en el hilo de audio: VU, peak/OVER, espectro de 16 bandas, loudness BS.1770,
// correlación y goniómetro. En Windows el EQ lo aplica Equalizer APO; en modo demo (sin Windows)
// este procesador aplica también las etapas de EQ para que los medidores reaccionen igual.
import { Biquad, bandFreqs } from './dsp.js';

const BANDS = 16;

class MeterProcessor extends AudioWorkletProcessor {
  constructor() {
    super();
    const fs = sampleRate;
    this.ana = bandFreqs.map(f => Biquad.bandPass(f, 2.15, fs));
    this.anaState = new Float64Array(BANDS * 2);
    this.anaSum = new Float64Array(BANDS);
    this.kShelf = Biquad.kShelf(fs);
    this.kHP = Biquad.kHighPass(fs);
    this.kState = new Float64Array(8);
    this.kSum = 0; this.kCount = 0; this.kBlock = Math.round(fs * 0.1);
    this.blocks = [];
    this.eqL = []; this.eqR = []; this.eqState = new Float64Array(64 * 4); this.eqGain = 1;
    this.reset();
    this.post = Math.round(fs / 30); this.count = 0;
    this.port.onmessage = (e) => {
      if (e.data.type === 'eq') {
        this.eqL = e.data.left; this.eqR = e.data.right; this.eqGain = e.data.gain;
        this.eqState.fill(0);
      }
    };
  }

  reset() {
    this.sumL = 0; this.sumR = 0; this.n = 0;
    this.peakL = 0; this.peakR = 0; this.overL = false; this.overR = false; this.inPeak = 0;
    this.lr = 0; this.ll = 0; this.rr = 0;
    this.anaSum.fill(0);
  }

  run(c, x, s, k) {
    const y = c.b0 * x + s[k];
    s[k] = c.b1 * x - c.a1 * y + s[k + 1];
    s[k + 1] = c.b2 * x - c.a2 * y;
    return y;
  }

  process(inputs, outputs) {
    const input = inputs[0];
    const L = input[0], R = input[1] || input[0];
    const frames = L ? L.length : 128;
    const eqL = this.eqL, eqR = this.eqR, es = this.eqState;
    for (let i = 0; i < frames; i++) {
      let l = L ? L[i] : 0, r = R ? R[i] : 0;
      this.inPeak = Math.max(this.inPeak, Math.abs(l), Math.abs(r));
      if (eqL.length) {
        for (let s = 0; s < eqL.length; s++) l = this.run(eqL[s], l, es, s * 4);
        for (let s = 0; s < eqR.length; s++) r = this.run(eqR[s], r, es, s * 4 + 2);
        l *= this.eqGain; r *= this.eqGain;
      }
      if (Math.abs(l) > 1) this.overL = true;
      if (Math.abs(r) > 1) this.overR = true;

      this.sumL += l * l; this.sumR += r * r; this.n++;
      this.peakL = Math.max(this.peakL, Math.abs(l)); this.peakR = Math.max(this.peakR, Math.abs(r));
      this.lr += l * r; this.ll += l * l; this.rr += r * r;

      const m = (l + r) * 0.5;
      for (let b = 0; b < BANDS; b++) {
        const y = this.run(this.ana[b], m, this.anaState, b * 2);
        this.anaSum[b] += y * y;
      }

      const kl = this.run(this.kHP, this.run(this.kShelf, l, this.kState, 0), this.kState, 2);
      const kr = this.run(this.kHP, this.run(this.kShelf, r, this.kState, 4), this.kState, 6);
      this.kSum += kl * kl + kr * kr;
      if (++this.kCount >= this.kBlock) {
        this.blocks.push(this.kSum / this.kCount);
        this.kSum = 0; this.kCount = 0;
      }
    }

    this.count += frames;
    if (this.count >= this.post && this.n > 0) {
      this.count = 0;
      const spectrum = new Float32Array(BANDS);
      for (let b = 0; b < BANDS; b++) spectrum[b] = Math.sqrt(this.anaSum[b] / this.n);
      this.port.postMessage({
        rmsL: Math.sqrt(this.sumL / this.n), rmsR: Math.sqrt(this.sumR / this.n),
        peakL: this.peakL, peakR: this.peakR, overL: this.overL, overR: this.overR, inPeak: this.inPeak,
        lr: this.lr, ll: this.ll, rr: this.rr, spectrum, blocks: this.blocks,
      }, [spectrum.buffer]);
      this.blocks = [];
      this.reset();
    }
    return true;
  }
}

registerProcessor('mad-meter', MeterProcessor);
