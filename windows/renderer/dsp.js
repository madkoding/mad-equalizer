// Matemáticas de filtros y generación de la configuración de Equalizer APO.
// Mismas fórmulas que la versión de Mac (RBJ Audio EQ Cookbook) para que la curva sea idéntica.

export const bandFreqs = [20, 31.5, 50, 80, 125, 200, 315, 500, 800, 1250, 2000, 3150, 5000, 8000, 12500, 20000];
export const bandLabels = ['20', '31', '50', '80', '125', '200', '315', '500', '800', '1.2K', '2K', '3.1K', '5K', '8K', '12K', '20K'];
export const bandSeg = ['20', '31.5', '50', '80', '125', '200', '315', '500', '800', '1.25K', '2K', '3.15K', '5K', '8K', '12.5K', '20K'];

export const presets = [
  { name: 'FLAT',   gains: Array(16).fill(0) },
  { name: 'BASS',   gains: [6, 6, 5, 4, 3, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0] },
  { name: 'TREBLE', gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 2, 3, 4, 5, 6, 6] },
  { name: 'VOCAL',  gains: [-4, -3, -2, -1, 0, 1, 2, 3, 4, 4, 3, 2, 1, 0, -1, -2] },
  { name: 'ROCK',   gains: [5, 5, 4, 2, 0, -1, -2, -2, -1, 0, 2, 3, 4, 5, 5, 5] },
  { name: 'DANCE',  gains: [6, 6, 5, 3, 1, 0, -1, -1, 0, 1, 2, 2, 3, 4, 5, 5] },
];

export const filterDefs = [
  { id: 'hp', name: 'LOW CUT' }, { id: 'lp', name: 'HIGH CUT' }, { id: 'loud', name: 'LOUDNESS' },
  { id: 'bass', name: 'BASS +' }, { id: 'treble', name: 'TREBLE +' }, { id: 'deess', name: 'DE-ESS' },
  { id: 'mono', name: 'MONO' },
];

/** Puntos de la curva de respuesta: 20 Hz a 20 kHz en escala logarítmica. */
export const curvePoints = 96;
export const curveFreqs = Array.from({ length: curvePoints }, (_, k) => 20 * Math.pow(1000, k / (curvePoints - 1)));

// ---------------------------------------------------------------------------------------------
// Biquads

const identity = () => ({ b0: 1, b1: 0, b2: 0, a1: 0, a2: 0 });
const make = (b0, b1, b2, a0, a1, a2) => ({ b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0 });
const w0 = (f, fs) => 2 * Math.PI * Math.min(f, fs * 0.45) / fs;

export const Biquad = {
  identity,
  peaking(f, q, gain, fs) {
    if (gain === 0) return identity();
    const A = Math.pow(10, gain / 40), w = w0(f, fs), al = Math.sin(w) / (2 * q), c = Math.cos(w);
    return make(1 + al * A, -2 * c, 1 - al * A, 1 + al / A, -2 * c, 1 - al / A);
  },
  lowShelf(f, gain, fs) {
    const A = Math.pow(10, gain / 40), w = w0(f, fs), c = Math.cos(w), al = Math.sin(w) / 2 * Math.SQRT2, s = 2 * Math.sqrt(A) * al;
    return make(A * ((A + 1) - (A - 1) * c + s), 2 * A * ((A - 1) - (A + 1) * c), A * ((A + 1) - (A - 1) * c - s),
                (A + 1) + (A - 1) * c + s, -2 * ((A - 1) + (A + 1) * c), (A + 1) + (A - 1) * c - s);
  },
  highShelf(f, gain, fs) {
    const A = Math.pow(10, gain / 40), w = w0(f, fs), c = Math.cos(w), al = Math.sin(w) / 2 * Math.SQRT2, s = 2 * Math.sqrt(A) * al;
    return make(A * ((A + 1) + (A - 1) * c + s), -2 * A * ((A - 1) + (A + 1) * c), A * ((A + 1) + (A - 1) * c - s),
                (A + 1) - (A - 1) * c + s, 2 * ((A - 1) - (A + 1) * c), (A + 1) - (A - 1) * c - s);
  },
  highPass(f, fs) {
    const w = w0(f, fs), c = Math.cos(w), al = Math.sin(w) / (2 * 0.7071);
    return make((1 + c) / 2, -(1 + c), (1 + c) / 2, 1 + al, -2 * c, 1 - al);
  },
  lowPass(f, fs) {
    const w = w0(f, fs), c = Math.cos(w), al = Math.sin(w) / (2 * 0.7071);
    return make((1 - c) / 2, 1 - c, (1 - c) / 2, 1 + al, -2 * c, 1 - al);
  },
  bandPass(f, q, fs) {
    const w = w0(f, fs), c = Math.cos(w), al = Math.sin(w) / (2 * q);
    return make(al, 0, -al, 1 + al, -2 * c, 1 - al);
  },
  /** Ponderación K de ITU-R BS.1770 (fórmulas de libebur128, válidas a cualquier frecuencia). */
  kShelf(fs) {
    const f0 = 1681.974450955533, G = 3.999843853973347, Q = 0.7071752369554196;
    const K = Math.tan(Math.PI * f0 / fs), Vh = Math.pow(10, G / 20), Vb = Math.pow(Vh, 0.4996667741545416);
    const a0 = 1 + K / Q + K * K;
    return { b0: (Vh + Vb * K / Q + K * K) / a0, b1: 2 * (K * K - Vh) / a0, b2: (Vh - Vb * K / Q + K * K) / a0,
             a1: 2 * (K * K - 1) / a0, a2: (1 - K / Q + K * K) / a0 };
  },
  kHighPass(fs) {
    const f0 = 38.13547087602444, Q = 0.5003270373238773;
    const K = Math.tan(Math.PI * f0 / fs), a0 = 1 + K / Q + K * K;
    return { b0: 1, b1: -2, b2: 1, a1: 2 * (K * K - 1) / a0, a2: (1 - K / Q + K * K) / a0 };
  },
};

export function magnitudeSquared(c, f, fs) {
  const w = 2 * Math.PI * f / fs, c1 = Math.cos(w), s1 = Math.sin(w), c2 = Math.cos(2 * w), s2 = Math.sin(2 * w);
  const nr = c.b0 + c.b1 * c1 + c.b2 * c2, ni = -(c.b1 * s1 + c.b2 * s2);
  const dr = 1 + c.a1 * c1 + c.a2 * c2, di = -(c.a1 * s1 + c.a2 * s2);
  return (nr * nr + ni * ni) / Math.max(dr * dr + di * di, 1e-30);
}

// ---------------------------------------------------------------------------------------------
// Etapas: una descripción común sirve para la curva, el EQ de demostración y el archivo de Equalizer APO.

/** Q proporcional: ancha con poca ganancia, estrecha con mucha. Q constante: 2/3 de octava fijo. */
export const bandQ = (gain, propQ) => (propQ ? 0.9 + 1.25 * Math.min(Math.abs(gain), 12) / 12 : 2.15);

export function bandStages(gains, propQ) {
  return gains.map((g, i) => ({ type: 'PK', f: bandFreqs[i], gain: g, q: bandQ(g, propQ) }));
}

export function filterStages(filters, lowCutHz) {
  const s = [];
  const loud = filters.has('loud');
  if (filters.has('hp')) s.push({ type: 'HPQ', f: lowCutHz, q: 0.7071 });
  if (filters.has('lp')) s.push({ type: 'LPQ', f: 8000, q: 0.7071 });
  if (filters.has('bass') || loud) s.push({ type: 'LSC', f: 100, gain: 6, q: 0.7071 });
  if (filters.has('treble') || loud) s.push({ type: 'HSC', f: 10000, gain: 4, q: 0.7071 });
  if (filters.has('deess')) s.push({ type: 'PK', f: 7000, gain: -6, q: 3 });
  return s;
}

export function coefficients(stage, fs) {
  switch (stage.type) {
    case 'PK': return Biquad.peaking(stage.f, stage.q, stage.gain, fs);
    case 'HPQ': return Biquad.highPass(stage.f, fs);
    case 'LPQ': return Biquad.lowPass(stage.f, fs);
    case 'LSC': return Biquad.lowShelf(stage.f, stage.gain, fs);
    case 'HSC': return Biquad.highShelf(stage.f, stage.gain, fs);
    default: return identity();
  }
}

export function response(stages, fs = 48000) {
  const coefs = stages.map(s => coefficients(s, fs));
  return curveFreqs.map(f => 10 * Math.log10(Math.max(coefs.reduce((m, c) => m * magnitudeSquared(c, f, fs), 1), 1e-12)));
}

/** Peso de cada punto para el auto-gain: igual por octava (ruido rosa) y ponderado K. */
const autoGainWeights = (() => {
  const s = Biquad.kShelf(48000), h = Biquad.kHighPass(48000);
  return curveFreqs.map(f => (f < 30 || f > 16000) ? 0 : magnitudeSquared(s, f, 48000) * magnitudeSquared(h, f, 48000));
})();

export function autoGainDB(curveL, curveR) {
  let num = 0, den = 0;
  for (let k = 0; k < curvePoints; k++) {
    const w = autoGainWeights[k];
    if (!w) continue;
    num += w * (Math.pow(10, curveL[k] / 10) + Math.pow(10, curveR[k] / 10)) / 2;
    den += w;
  }
  return Math.min(Math.max(-10 * Math.log10(num / den), -24), 6);
}

// ---------------------------------------------------------------------------------------------
// Archivo de configuración de Equalizer APO

const n = (v, d = 2) => (Math.round(v * 10 ** d) / 10 ** d).toString();

function stageLine(s) {
  switch (s.type) {
    case 'PK': return `Filter: ON PK Fc ${n(s.f, 1)} Hz Gain ${n(s.gain)} dB Q ${n(s.q, 3)}`;
    case 'HPQ': return `Filter: ON HPQ Fc ${n(s.f, 1)} Hz Q ${n(s.q, 3)}`;
    case 'LPQ': return `Filter: ON LPQ Fc ${n(s.f, 1)} Hz Q ${n(s.q, 3)}`;
    case 'LSC': return `Filter: ON LSC Fc ${n(s.f, 1)} Hz Gain ${n(s.gain)} dB Q ${n(s.q, 3)}`;
    case 'HSC': return `Filter: ON HSC Fc ${n(s.f, 1)} Hz Gain ${n(s.gain)} dB Q ${n(s.q, 3)}`;
    default: return '';
  }
}

/**
 * Traduce el estado de MAD a comandos de Equalizer APO (que los aplica en orden y recarga el
 * archivo en cuanto cambia). Devuelve también la reducción del anti-clip para el medidor GR.
 */
export function buildConfig(st, curveL, curveR, autoGain) {
  const lines = ['# MAD Equalizer: archivo generado automáticamente, no lo edites a mano.'];
  if (!st.power || st.bypass) {
    lines.push(st.power ? '# BYPASS' : '# POWER OFF');
    return { text: lines.join('\r\n') + '\r\n', clipDB: 0 };
  }
  const levelDB = 20 * Math.log10(Math.max(st.level, 0.001));
  let gain = st.preampDB + autoGain + levelDB;
  // Anti-clip: si algún punto de la curva superaría 0 dB, se baja la ganancia lo justo.
  let clipDB = 0;
  if (st.antiClip) {
    const peak = Math.max(...curveL, ...curveR) + gain;
    if (peak > 0) clipDB = -peak;
  }
  lines.push(`Preamp: ${n(st.preampDB + autoGain + clipDB)} dB`);

  const linked = st.gainsL.every((g, i) => g === st.gainsR[i]);
  const bands = (g) => bandStages(g, st.propQ).filter(s => s.gain !== 0).map(stageLine);
  if (linked) {
    lines.push('Channel: all', ...bands(st.gainsL));
  } else {
    lines.push('Channel: L', ...bands(st.gainsL), 'Channel: R', ...bands(st.gainsR), 'Channel: all');
  }
  lines.push(...filterStages(new Set(st.filters), st.lowCutHz).map(stageLine));
  if (st.filters.includes('mono')) lines.push('Copy: L=0.5*L+0.5*R R=0.5*L+0.5*R');

  const balL = st.balance > 0 ? 20 * Math.log10(Math.max(1 - st.balance, 0.001)) : 0;
  const balR = st.balance < 0 ? 20 * Math.log10(Math.max(1 + st.balance, 0.001)) : 0;
  if (balL || balR) lines.push('Channel: L', `Preamp: ${n(balL)} dB`, 'Channel: R', `Preamp: ${n(balR)} dB`, 'Channel: all');
  if (levelDB !== 0) lines.push(`Preamp: ${n(levelDB)} dB`);
  return { text: lines.join('\r\n') + '\r\n', clipDB };
}
