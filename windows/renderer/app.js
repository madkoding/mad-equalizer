import * as D from './dsp.js';
import * as G from './draw.js';

const api = window.mad;
const $ = (id) => document.getElementById(id);

// ---------------------------------------------------------------------------------------------
// Estado persistente (localStorage) y de sesión

const STORE = 'mad-equalizer-v1';
const defaults = {
  power: true, bypass: false,
  gainsL: Array(16).fill(0), gainsR: Array(16).fill(0),
  preampDB: 0, level: 1, balance: 0, width: 1, lowCutHz: 80, filters: [],
  propQ: false, autoGain: false, antiClip: true, rangeDB: 12,
  spectrumMode: true, showCurve: true,
  memories: [null, null, null, null],
};
const S = (() => {
  try { return { ...structuredClone(defaults), ...JSON.parse(localStorage.getItem(STORE) || '{}') }; }
  catch { return structuredClone(defaults); }
})();
const R = {
  channel: 'link', lastEdited: 'left', selected: 8, preset: null, memory: null, storeArmed: false,
  ab: 0, abStore: [null, null], apo: null, apoError: null, autoGain: 0, clipDB: 0,
  curveL: [], curveR: [], outputName: 'SALIDA DE WINDOWS', audio: null,
};

const save = () => localStorage.setItem(STORE, JSON.stringify(S));
const clamp = (v, a, b) => Math.min(Math.max(v, a), b);
const gainOf = (i) => (R.channel === 'right' ? S.gainsR[i] : S.gainsL[i]);
const isSplit = () => S.gainsL.some((g, i) => g !== S.gainsR[i]);

// ---------------------------------------------------------------------------------------------
// Cambios: recalcula curva, auto-gain y anti-clip, escribe la config de Equalizer APO y redibuja

function changed() {
  const filters = new Set(S.filters);
  const stL = [...D.bandStages(S.gainsL, S.propQ), ...D.filterStages(filters, S.lowCutHz)];
  const stR = [...D.bandStages(S.gainsR, S.propQ), ...D.filterStages(filters, S.lowCutHz)];
  R.curveL = D.response(stL);
  R.curveR = D.response(stR);
  R.autoGain = S.autoGain ? D.autoGainDB(R.curveL, R.curveR) : 0;
  const cfg = D.buildConfig(S, R.curveL, R.curveR, R.autoGain);
  R.clipDB = cfg.clipDB;
  writeConfig(cfg.text);
  pushDemoEQ(stL, stR);
  save();
  render();
}

// Equalizer APO recarga el archivo cada vez que cambia: durante un arrastre se limita a ~12 escrituras/s.
let writeTimer = null, pendingText = null;
function writeConfig(text) {
  pendingText = text;
  if (writeTimer) return;
  const flush = async () => {
    const t = pendingText; pendingText = null;
    const res = await api.write(t);
    R.apoError = res.ok ? null : res.error;
    renderStatus();
    writeTimer = pendingText ? setTimeout(flush, 80) : null;
  };
  writeTimer = setTimeout(flush, 0);
}

function setGain(i, v) {
  v = clamp(v, -S.rangeDB, S.rangeDB);
  if (R.channel === 'link') { S.gainsL[i] = v; S.gainsR[i] = v; }
  else if (R.channel === 'left') { S.gainsL[i] = v; R.lastEdited = 'left'; }
  else { S.gainsR[i] = v; R.lastEdited = 'right'; }
  R.selected = i; R.preset = null; R.memory = null;
  changed();
}

/** LINK → LEFT → RIGHT → LINK. Al volver a LINK se copia el último canal editado a ambos. */
function cycleChannel() {
  if (R.channel === 'link') R.channel = 'left';
  else if (R.channel === 'left') R.channel = 'right';
  else {
    if (R.lastEdited === 'right') S.gainsL = [...S.gainsR]; else S.gainsR = [...S.gainsL];
    R.channel = 'link';
  }
  changed();
}

/** Como en los EQ de hardware, el fader no se mueve: cambia cuántos dB representa su recorrido. */
function toggleRange() {
  const f = S.rangeDB === 12 ? 0.5 : 2;
  const conv = (g) => Math.round(g * f * 2) / 2;
  S.gainsL = S.gainsL.map(conv); S.gainsR = S.gainsR.map(conv);
  S.rangeDB = S.rangeDB === 12 ? 6 : 12;
  changed();
}

function applyPreset(p) {
  const g = p.gains.map(v => clamp(v, -S.rangeDB, S.rangeDB));
  if (R.channel !== 'right') S.gainsL = [...g];
  if (R.channel !== 'left') S.gainsR = [...g];
  R.preset = p.name; R.memory = null;
  changed();
}

const snapshot = () => ({ gainsL: [...S.gainsL], gainsR: [...S.gainsR], preampDB: S.preampDB,
  filters: [...S.filters], lowCutHz: S.lowCutHz, propQ: S.propQ });
function applySnapshot(s) {
  S.gainsL = s.gainsL.map(v => clamp(v, -S.rangeDB, S.rangeDB));
  S.gainsR = s.gainsR.map(v => clamp(v, -S.rangeDB, S.rangeDB));
  Object.assign(S, { preampDB: s.preampDB, filters: [...s.filters], lowCutHz: s.lowCutHz, propQ: s.propQ });
  R.preset = null;
}

/** Con STORE armado guarda en la memoria; si no, la recupera. */
function pressMemory(i) {
  if (R.storeArmed) { S.memories[i] = snapshot(); R.storeArmed = false; R.memory = i; }
  else if (S.memories[i]) { applySnapshot(S.memories[i]); R.memory = i; }
  else return render();
  changed();
}

function selectAB(slot) {
  if (slot === R.ab) return;
  R.abStore[R.ab] = snapshot();
  if (R.abStore[slot]) applySnapshot(R.abStore[slot]);
  R.ab = slot; R.memory = null;
  changed();
}

function toggleFilter(id) {
  S.filters = S.filters.includes(id) ? S.filters.filter(f => f !== id) : [...S.filters, id];
  changed();
}

function setPower(on) {
  S.power = on;
  if (R.audio) on ? R.audio.ctx.resume() : R.audio.ctx.suspend();
  changed();
}

// ---------------------------------------------------------------------------------------------
// Construcción de controles

function makeKey(parent, title, onClick, help) {
  const el = document.createElement('div');
  el.className = 'key';
  el.innerHTML = '<button></button>';
  const btn = el.querySelector('button');
  btn.textContent = title;
  if (help) btn.title = help;
  btn.addEventListener('click', onClick);
  parent.appendChild(el);
  // El LED es una barra en el borde superior del propio botón: así se ve cuál está activo.
  return {
    set(on, opts = {}) {
      btn.classList.toggle('on', !!on);
      btn.classList.toggle('dim', !on && !!opts.dim);
      btn.classList.toggle('blink', !!opts.blink);
      if (opts.label) btn.textContent = opts.label;
    },
  };
}

const keys = {};
function buildKeys() {
  const left = $('leftKeys');
  keys.bypass = makeKey(left, 'BYPASS', () => { S.bypass = !S.bypass; changed(); }, 'Escuchar sin ecualizar');
  keys.spectrum = makeKey(left, 'SPECTRUM', () => { S.spectrumMode = !S.spectrumMode; changed(); }, 'LEDs: analizador de espectro o ganancia de cada banda');
  keys.presets = D.presets.map(p => makeKey($('rowPreset'), p.name, () => applyPreset(p)));
  keys.filters = D.filterDefs.map(f => makeKey($('rowFilter'), f.name, () => toggleFilter(f.id)));
  keys.memories = [0, 1, 2, 3].map(i => makeKey($('rowMemory'), `M${i + 1}`, () => pressMemory(i)));
  keys.store = makeKey($('rowMemory'), 'STORE', () => { R.storeArmed = !R.storeArmed; render(); }, 'Pulsa STORE y luego M1–M4 para guardar');
  keys.a = makeKey($('rowMemory'), 'A', () => selectAB(0), 'Comparar dos versiones de la curva');
  keys.b = makeKey($('rowMemory'), 'B', () => selectAB(1), 'Comparar dos versiones de la curva');
  const mode = $('rowMode');
  keys.range = makeKey(mode, 'RANGE 6', toggleRange, 'Faders de ±6 dB para ajuste fino');
  keys.propQ = makeKey(mode, 'PROP Q', () => { S.propQ = !S.propQ; changed(); }, 'Q proporcional: bandas más anchas con poca ganancia');
  keys.channel = makeKey(mode, 'LINK', cycleChannel, 'Editar ambos canales, sólo el izquierdo o sólo el derecho');
  keys.auto = makeKey(mode, 'AUTO GAIN', () => { S.autoGain = !S.autoGain; changed(); }, 'Compensa el volumen para comparar curvas a igual loudness');
  keys.clip = makeKey(mode, 'ANTI CLIP', () => { S.antiClip = !S.antiClip; changed(); }, 'Baja la ganancia lo justo para que la curva no sature');
  keys.curve = makeKey(mode, 'CURVE', () => { S.showCurve = !S.showCurve; changed(); });
}

const knobs = [];
function makeKnob({ label, get, set, min, max, def, step, readout }) {
  const el = document.createElement('div');
  el.className = 'knob';
  el.innerHTML = '<canvas></canvas><span class="seg" data-cells="4" data-size="10"></span><span class="silk"></span>';
  el.querySelector('.silk').textContent = label;
  $('knobs').appendChild(el);
  const canvas = el.querySelector('canvas'), seg = el.querySelector('.seg');
  let start = null, startY = 0;
  canvas.addEventListener('pointerdown', (e) => { canvas.setPointerCapture(e.pointerId); start = get(); startY = e.clientY; });
  canvas.addEventListener('pointermove', (e) => {
    if (start === null) return;
    const v = start - (e.clientY - startY) / 160 * (max - min);
    set(Math.round(clamp(v, min, max) / step) * step);
    changed();
  });
  canvas.addEventListener('pointerup', () => { start = null; });
  canvas.addEventListener('dblclick', () => { set(def); changed(); });
  const k = { draw() { G.drawKnob(canvas, 54, (get() - min) / (max - min)); setSeg(seg, readout()); } };
  knobs.push(k);
}

function buildKnobs() {
  makeKnob({ label: 'PRE-AMP', get: () => S.preampDB, set: v => (S.preampDB = v), min: -12, max: 12, def: 0, step: 0.5,
             readout: () => fmt(S.preampDB, true) });
  makeKnob({ label: 'LEVEL', get: () => S.level, set: v => (S.level = v), min: 0, max: 1.5, def: 1, step: 0.01,
             readout: () => String(Math.round(S.level * 100)) });
  makeKnob({ label: 'LOW CUT', get: () => Math.log10(S.lowCutHz), set: v => (S.lowCutHz = Math.round(10 ** v)),
             min: Math.log10(20), max: Math.log10(200), def: Math.log10(80), step: 0.005, readout: () => String(S.lowCutHz) });
  makeKnob({ label: 'BALANCE', get: () => S.balance, set: v => (S.balance = v), min: -1, max: 1, def: 0, step: 0.02,
             readout: () => S.balance === 0 ? 'C' : (S.balance < 0 ? 'L' : 'R') + Math.round(Math.abs(S.balance) * 100) });
  // Ancho estéreo (mid/side): 0 % = mono, 100 % = original, 200 % = lados al doble para separar instrumentos.
  makeKnob({ label: 'WIDTH', get: () => S.width, set: v => (S.width = v), min: 0, max: 2, def: 1, step: 0.01,
             readout: () => String(Math.round(S.width * 100)) });
}

// ---------------------------------------------------------------------------------------------
// Faders: arrastrar la perilla la mueve en relativo; tocar el riel salta a ese punto

const WELL_W = 1028, WELL_H = 335;
function buildFaders() {
  const c = $('faders');
  const geo = G.wellGeometry(WELL_W);
  let drag = null;
  const pos = (e) => { const r = c.getBoundingClientRect(); return [(e.clientX - r.left) * WELL_W / r.width, (e.clientY - r.top) * WELL_H / r.height]; };
  c.addEventListener('pointerdown', (e) => {
    const [x, y] = pos(e), col = geo.colAt(x);
    if (col < 0) return;
    c.setPointerCapture(e.pointerId);
    const capY = geo.valueY(gainOf(col), S.rangeDB);
    drag = { col, relative: Math.abs(y - capY) <= G.WELL.cap.h, start: gainOf(col), y };
    if (!drag.relative) setGain(col, snap(geo.yValue(y, S.rangeDB)));
    else { R.selected = col; render(); }
  });
  c.addEventListener('pointermove', (e) => {
    const [x, y] = pos(e);
    if (!drag) {
      const col = geo.colAt(x);
      if (col >= 0 && col !== R.selected) { R.selected = col; render(); }
      return;
    }
    const v = drag.relative ? drag.start - (y - drag.y) / G.WELL.usable * 2 * S.rangeDB : geo.yValue(y, S.rangeDB);
    setGain(drag.col, snap(v));
  });
  c.addEventListener('pointerup', () => { drag = null; });
  c.addEventListener('dblclick', (e) => { const col = geo.colAt(pos(e)[0]); if (col >= 0) setGain(col, 0); });
}
const snap = (v) => { const step = S.rangeDB > 6 ? 0.5 : 0.25; return Math.round(v / step) * step; };

// ---------------------------------------------------------------------------------------------
// Display de 14 segmentos

/** Caracteres que DSEG14 dibuja bien; el resto se convierte en celda vacía ("!"). */
const segSafe = (s) => s.normalize('NFD').replace(/[̀-ͯ]/g, '').toUpperCase().replace(/[^A-Z0-9+-]/g, '!');
const fmt = (v, sign = false) => (sign && v >= 0 ? '+' : '') + v.toFixed(1);
const segDB = (v) => (Number.isFinite(v) && v > -99 ? v.toFixed(1) : '----');

function setSeg(el, text) {
  const cells = +el.dataset.cells, size = +el.dataset.size, lead = !!el.dataset.lead;
  if (!el.firstChild) {
    el.style.fontSize = size + 'px';
    el.innerHTML = `<span class="ghost">${'~'.repeat(cells)}</span><span class="lit"></span>`;
    el.querySelector('.lit').style.textShadow = `0 0 ${size * 0.12}px var(--led), 0 0 ${size * 0.4}px rgba(77,179,255,0.55)`;
  }
  const visible = text.replace(/\./g, '').length;
  const pad = '!'.repeat(Math.max(0, cells - visible));
  el.lastChild.textContent = lead ? text + pad : pad + text;
}

let marqueeOffset = 0;
setInterval(() => {
  const text = segSafe(R.outputName), cells = 10;
  if (text.length <= cells) return setSeg($('outSeg'), text);
  const loop = text + '!!!!';
  marqueeOffset = (marqueeOffset + 1) % loop.length;
  setSeg($('outSeg'), Array.from({ length: cells }, (_, k) => loop[(marqueeOffset + k) % loop.length]).join(''));
}, 350);

function lamp(id, on, text) {
  const el = $(id);
  el.classList.toggle('on', !!on);
  if (text) el.textContent = text;
}

function renderStatus() {
  const apoOK = R.apo && R.apo.installed && !R.apoError;
  let status;
  if (!R.apo) status = 'CONECTANDO…';
  else if (!R.apo.installed) status = 'EQUALIZER APO NO INSTALADO';
  else if (R.apoError) status = R.apoError;
  else if (!S.power) status = 'STANDBY';
  else if (R.apo.demo) status = 'DEMO · SEÑAL DE PRUEBA';
  else status = 'PROCESANDO · EQUALIZER APO';
  $('status').textContent = status;
  lamp('lampApo', apoOK);
  lamp('lampEq', apoOK && S.power && !S.bypass);
}

// ---------------------------------------------------------------------------------------------
// Render

function render() {
  const b = R.selected;
  setSeg($('bandSeg'), String(b + 1).padStart(2, '0'));
  setSeg($('freqSeg'), D.bandSeg[b]);
  setSeg($('gainSeg'), fmt(gainOf(b), true));
  $('power').classList.toggle('on', S.power);
  renderStatus();
  lamp('lampBypass', S.bypass);
  lamp('lampAuto', S.autoGain, S.autoGain ? `AUTO ${fmt(R.autoGain, true)}` : 'AUTO');
  lamp('lampChan', R.channel !== 'link' || isSplit(), { link: 'LINK', left: 'LEFT', right: 'RIGHT' }[R.channel]);

  keys.bypass.set(S.bypass);
  keys.spectrum.set(S.spectrumMode);
  keys.presets.forEach((k, i) => k.set(R.preset === D.presets[i].name));
  keys.filters.forEach((k, i) => k.set(S.filters.includes(D.filterDefs[i].id)));
  keys.memories.forEach((k, i) => k.set(R.memory === i, { dim: !!S.memories[i] }));
  keys.store.set(R.storeArmed, { blink: R.storeArmed });
  keys.a.set(R.ab === 0); keys.b.set(R.ab === 1);
  keys.range.set(S.rangeDB === 6);
  keys.propQ.set(S.propQ);
  keys.channel.set(R.channel !== 'link', { label: { link: 'LINK', left: 'LEFT', right: 'RIGHT' }[R.channel] });
  keys.auto.set(S.autoGain);
  keys.clip.set(S.antiClip);
  keys.curve.set(S.showCurve);
  knobs.forEach(k => k.draw());
  drawMeters();
}

/** Los VU miden lo mismo que el panel central (marca + display), para que queden alineados. */
let vuH = 159;
function vuHeight() {
  const h = document.querySelector('header .center')?.offsetHeight;
  if (h && h > 100) vuH = h;
  return vuH;
}

function drawMeters() {
  const m = M;
  const vuH = vuHeight();
  G.drawVU($('vuL'), 230, vuH, { position: m.left, channel: 'LEFT', peak: m.peakL, over: m.overL });
  G.drawVU($('vuR'), 230, vuH, { position: m.right, channel: 'RIGHT', peak: m.peakR, over: m.overR });
  G.drawWell($('faders'), WELL_W, WELL_H, {
    gains: Array.from({ length: 16 }, (_, i) => gainOf(i)), range: S.rangeDB, selected: R.selected,
    spectrum: S.spectrumMode && S.power, levels: m.levels, peaks: m.peaks,
    showCurve: S.showCurve, curveL: R.curveL, curveR: R.curveR, split: isSplit(),
  });
  G.drawBar($('corrBar'), 118, 7, m.corr, 'bipolar');
  G.drawBar($('grBar'), 118, 7, Math.min(-R.clipDB / 12, 1), 'right');
  setSeg($('lufsM'), segDB(m.lufsM));
  setSeg($('lufsS'), segDB(m.lufsS));
  setSeg($('lufsI'), segDB(m.lufsI));
  setSeg($('peakSeg'), segDB(m.peakHoldDB));
  setSeg($('crestSeg'), m.crestDB > 0 ? m.crestDB.toFixed(1) : '---');
  lamp('lampSignal', m.signal);
}

// ---------------------------------------------------------------------------------------------
// Medidores: misma balística que la versión de Mac

const M = {
  left: -0.04, right: -0.04, signal: false, levels: Array(16).fill(0), peaks: Array(16).fill(0), holds: Array(16).fill(0),
  peakL: 0, peakR: 0, overL: false, overR: false, overHoldL: 0, overHoldR: 0,
  lufsM: -Infinity, lufsS: -Infinity, lufsI: -Infinity, recent: [], gated: [],
  peakHoldDB: -Infinity, crestDB: 0, peakWin: [], msWin: [], corr: 0, tick: 0,
};

/** 0 VU = -12 dBFS RMS (música actual); la escala VU es lineal en voltaje. */
const vuPosition = (rms) => clamp((10 ** ((20 * Math.log10(Math.max(rms, 1e-7)) + 12) / 20) - 0.1) / (10 ** 0.15 - 0.1), -0.04, 1.06);
const loudness = (z) => (z > 0 ? -0.691 + 10 * Math.log10(z) : -Infinity);

function integrated() {
  const absGate = 10 ** ((-70 + 0.691) / 10);
  const a = M.gated.filter(z => z > absGate);
  if (!a.length) return -Infinity;
  const rel = 10 ** ((loudness(a.reduce((s, z) => s + z, 0) / a.length) - 10 + 0.691) / 10);
  const b = a.filter(z => z > rel);
  return b.length ? loudness(b.reduce((s, z) => s + z, 0) / b.length) : -Infinity;
}

function onMeters(d) {
  const run = S.power;
  M.left += ((run ? vuPosition(d.rmsL) : -0.04) - M.left) * 0.3;
  M.right += ((run ? vuPosition(d.rmsR) : -0.04) - M.right) * 0.3;

  for (let b = 0; b < 16; b++) {
    const db = 20 * Math.log10(Math.max(d.spectrum[b], 1e-7));
    const target = run ? clamp((db + 54) / 3, 0, 17) : 0;
    M.levels[b] = target > M.levels[b] ? target : Math.max(target, M.levels[b] - 0.3);
    if (M.levels[b] >= M.peaks[b]) { M.peaks[b] = M.levels[b]; M.holds[b] = 24; }
    else if (M.holds[b] > 0) M.holds[b]--;
    else M.peaks[b] = Math.max(M.levels[b], M.peaks[b] - 0.2);
  }

  const strip = (p) => clamp((20 * Math.log10(Math.max(p, 1e-7)) + 40) / 40, 0, 1);
  M.peakL = run ? Math.max(strip(d.peakL), M.peakL - 0.0167) : 0;
  M.peakR = run ? Math.max(strip(d.peakR), M.peakR - 0.0167) : 0;
  if (d.overL) M.overHoldL = 60;
  if (d.overR) M.overHoldR = 60;
  M.overHoldL = Math.max(0, M.overHoldL - 1); M.overHoldR = Math.max(0, M.overHoldR - 1);
  M.overL = run && M.overHoldL > 0; M.overR = run && M.overHoldR > 0;

  const c = d.ll * d.rr > 1e-12 ? d.lr / Math.sqrt(d.ll * d.rr) : 0;
  M.corr += ((run ? c : 0) - M.corr) * 0.15;

  M.peakWin.push(Math.max(d.peakL, d.peakR)); if (M.peakWin.length > 90) M.peakWin.shift();
  M.msWin.push((d.rmsL ** 2 + d.rmsR ** 2) / 2); if (M.msWin.length > 30) M.msWin.shift();
  const maxPeak = Math.max(...M.peakWin);
  M.peakHoldDB = run && maxPeak > 1e-6 ? 20 * Math.log10(maxPeak) : -Infinity;
  const ms = M.msWin.reduce((s, v) => s + v, 0) / M.msWin.length, pk1 = Math.max(...M.peakWin.slice(-30));
  M.crestDB = run && ms > 1e-10 && pk1 > 0 ? 20 * Math.log10(pk1 / Math.sqrt(ms)) : 0;

  for (const z of d.blocks) {
    M.recent.push(z); if (M.recent.length > 30) M.recent.shift();
    if (M.recent.length >= 4 && M.gated.length < 200000) M.gated.push(M.recent.slice(-4).reduce((s, v) => s + v, 0) / 4);
  }
  if (run && M.recent.length >= 4) {
    M.lufsM = loudness(M.recent.slice(-4).reduce((s, v) => s + v, 0) / 4);
    M.lufsS = loudness(M.recent.reduce((s, v) => s + v, 0) / M.recent.length);
  } else if (!run) { M.recent = []; M.lufsM = -Infinity; M.lufsS = -Infinity; }
  if (M.tick++ % 10 === 0) M.lufsI = integrated();

  M.signal = run && d.inPeak > 0.0005;
  drawMeters();
}

// ---------------------------------------------------------------------------------------------
// Audio: captura loopback en Windows, señal de prueba en modo demo. Nunca se reproduce nada.

async function startAudio() {
  const ctx = new AudioContext({ latencyHint: 'playback' });
  await ctx.audioWorklet.addModule('meter-worklet.js');
  const node = new AudioWorkletNode(ctx, 'mad-meter', { numberOfInputs: 1, numberOfOutputs: 1, outputChannelCount: [2],
                                                       channelCount: 2, channelCountMode: 'explicit' });
  node.port.onmessage = (e) => onMeters(e.data);
  const silent = ctx.createGain();
  silent.gain.value = 0;
  node.connect(silent).connect(ctx.destination);
  R.audio = { ctx, node, source: null, stream: null };
  await connectSource();
  if (!S.power) ctx.suspend();
  changed();
}

async function connectSource() {
  const a = R.audio;
  if (a.source) { a.source.disconnect(); a.source = null; }
  if (a.stream) { a.stream.getTracks().forEach(t => t.stop()); a.stream = null; }
  if (api.demo) {
    a.source = demoSignal(a.ctx);
    R.outputName = 'DEMO SIGNAL';
  } else {
    try {
      const stream = await navigator.mediaDevices.getDisplayMedia({ video: true, audio: true });
      stream.getVideoTracks().forEach(t => t.stop());
      a.stream = new MediaStream(stream.getAudioTracks());
      a.source = a.ctx.createMediaStreamSource(a.stream);
    } catch (e) {
      R.apoError = 'SIN CAPTURA DE AUDIO PARA LOS MEDIDORES';
      return renderStatus();
    }
    await refreshOutputName();
  }
  a.source.connect(a.node);
}

async function refreshOutputName() {
  try {
    const devs = await navigator.mediaDevices.enumerateDevices();
    const def = devs.find(d => d.kind === 'audiooutput' && d.deviceId === 'default');
    if (def && def.label) R.outputName = def.label.replace(/^(Default|Predeterminado|Por defecto)\s*-\s*/i, '');
  } catch { /* sin nombre: se queda el genérico */ }
}

/** Una pequeña pista estéreo (bombo, bajo, acordes y hi-hat) para ver los medidores sin Windows. */
function demoSignal(ctx) {
  const out = ctx.createGain();
  out.gain.value = 0.55;
  const noise = ctx.createBuffer(1, ctx.sampleRate, ctx.sampleRate);
  const nd = noise.getChannelData(0);
  for (let i = 0; i < nd.length; i++) nd[i] = Math.random() * 2 - 1;
  const chords = [[220, 277.2, 329.6], [196, 246.9, 293.7], [174.6, 220, 261.6], [196, 246.9, 329.6]];
  const pads = [-0.7, 0, 0.7].map((pan, k) => {
    const o = ctx.createOscillator(); o.type = 'sawtooth';
    const lp = ctx.createBiquadFilter(); lp.frequency.value = 1800;
    const g = ctx.createGain(); g.gain.value = 0.05;
    const p = ctx.createStereoPanner(); p.pan.value = pan;
    o.connect(lp).connect(g).connect(p).connect(out); o.start();
    return o;
  });
  const beat = 0.5;
  let next = ctx.currentTime + 0.1, n = 0;
  const schedule = () => {
    while (next < ctx.currentTime + 0.4) {
      const t = next, bar = Math.floor(n / 4) % chords.length;
      if (n % 4 === 0) pads.forEach((o, k) => o.frequency.setValueAtTime(chords[bar][k], t));
      const kick = ctx.createOscillator(), kg = ctx.createGain();
      kick.frequency.setValueAtTime(120, t); kick.frequency.exponentialRampToValueAtTime(45, t + 0.15);
      kg.gain.setValueAtTime(0.9, t); kg.gain.exponentialRampToValueAtTime(0.001, t + 0.3);
      kick.connect(kg).connect(out); kick.start(t); kick.stop(t + 0.32);
      const bass = ctx.createOscillator(), bg = ctx.createGain();
      bass.type = 'triangle'; bass.frequency.value = chords[bar][0] / 4;
      bg.gain.setValueAtTime(0.35, t + beat / 2); bg.gain.exponentialRampToValueAtTime(0.001, t + beat);
      bass.connect(bg).connect(out); bass.start(t + beat / 2); bass.stop(t + beat);
      for (const off of [0.25, 0.75]) {
        const h = ctx.createBufferSource(), hp = ctx.createBiquadFilter(), hg = ctx.createGain(), hpn = ctx.createStereoPanner();
        h.buffer = noise; hp.type = 'highpass'; hp.frequency.value = 7000; hpn.pan.value = 0.35;
        hg.gain.setValueAtTime(0.25, t + off * beat); hg.gain.exponentialRampToValueAtTime(0.001, t + off * beat + 0.05);
        h.connect(hp).connect(hg).connect(hpn).connect(out); h.start(t + off * beat); h.stop(t + off * beat + 0.06);
      }
      next += beat; n++;
    }
  };
  setInterval(schedule, 100);
  schedule();
  return out;
}

/** En modo demo el procesador de medición aplica el EQ, para que los medidores reaccionen. */
function pushDemoEQ(stL, stR) {
  if (!api.demo || !R.audio) return;
  const fs = R.audio.ctx.sampleRate;
  const on = S.power && !S.bypass;
  const gain = 10 ** ((S.preampDB + R.autoGain + R.clipDB) / 20) * S.level;
  R.audio.node.port.postMessage({
    type: 'eq',
    left: on ? stL.map(s => D.coefficients(s, fs)) : [],
    right: on ? stR.map(s => D.coefficients(s, fs)) : [],
    gain: on ? gain : 1,
  });
}

// ---------------------------------------------------------------------------------------------
// Arranque

async function init() {
  await Promise.all([document.fonts.load('10px Michroma'), document.fonts.load('10px DSEG14')]);
  buildKeys();
  buildKnobs();
  buildFaders();
  $('power').addEventListener('click', () => setPower(!S.power));
  $('output').addEventListener('click', () => api.openDevices());
  $('lufsIBtn').addEventListener('click', () => { M.gated = []; M.lufsI = -Infinity; drawMeters(); });
  R.apo = await api.status();
  changed();
  try { await startAudio(); } catch (e) { console.error(e); }
  navigator.mediaDevices.addEventListener?.('devicechange', async () => {
    if (!api.demo && R.audio) await connectSource();
    render();
  });
}

init();
