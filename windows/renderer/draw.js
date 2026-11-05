// Dibujo en Canvas de los elementos analógicos: VU, goniómetro, faders con LEDs, perillas y barras.
import { bandLabels, curveFreqs, curvePoints } from './dsp.js';

export const C = {
  led: 'rgb(77,179,255)', ledCore: 'rgb(199,235,255)', ledOff: 'rgb(15,28,48)',
  silk: 'rgb(209,217,227)', ink: 'rgb(10,26,51)', red: 'rgb(199,31,26)', redOff: 'rgb(51,10,10)',
};
export const wide = (size) => `900 ${size * 0.64 * 0.99}px MADMicrogramma`;
const rad = (d) => d * Math.PI / 180;

/** Ajusta el canvas a la densidad de píxeles y devuelve un contexto en px CSS. */
export function setup(canvas, w, h) {
  const dpr = window.devicePixelRatio || 1;
  if (canvas.width !== Math.round(w * dpr) || canvas.height !== Math.round(h * dpr)) {
    canvas.width = Math.round(w * dpr); canvas.height = Math.round(h * dpr);
    canvas.style.width = w + 'px'; canvas.style.height = h + 'px';
  }
  const ctx = canvas.getContext('2d');
  ctx.textRendering = 'geometricPrecision';
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.clearRect(0, 0, w, h);
  return ctx;
}

function rr(ctx, x, y, w, h, r) { ctx.beginPath(); ctx.roundRect(x, y, w, h, r); }

/** Bloom: halo ancho y suave que suma luz sobre el fondo, más el núcleo brillante del LED. */
function glow(ctx, color, blur, fn) {
  ctx.save(); ctx.globalCompositeOperation = 'lighter'; ctx.globalAlpha = 0.55;
  ctx.shadowColor = color; ctx.shadowBlur = blur * 3.4; fn(); ctx.restore();
  ctx.save(); ctx.shadowColor = color; ctx.shadowBlur = blur; fn(); ctx.restore();
}

function bezel(ctx, w, h) {
  const g = ctx.createLinearGradient(0, 0, 0, h);
  g.addColorStop(0, 'rgb(61,61,61)'); g.addColorStop(1, 'rgb(18,18,18)');
  rr(ctx, 0, 0, w, h, 10); ctx.fillStyle = g; ctx.fill();
}

const vuPos = (db) => (Math.pow(10, db / 20) - 0.1) / (Math.pow(10, 0.15) - 0.1);

// ---------------------------------------------------------------------------------------------
// VU con peak meter

export function drawVU(canvas, w, h, { position, channel, peak, over }) {
  const ctx = setup(canvas, w, h);
  bezel(ctx, w, h);
  const face = { x: 9, y: 9, w: w - 18, h: h - 18 - 20 };
  const fg = ctx.createRadialGradient(face.x + face.w / 2, face.y + face.h, 0, face.x + face.w / 2, face.y + face.h, face.w * 0.85);
  fg.addColorStop(0, 'rgb(230,245,255)'); fg.addColorStop(0.5, 'rgb(163,209,247)'); fg.addColorStop(1, 'rgb(71,122,184)');
  rr(ctx, face.x, face.y, face.w, face.h, 5); ctx.fillStyle = fg; ctx.fill();

  ctx.save();
  rr(ctx, face.x, face.y, face.w, face.h, 5); ctx.clip();
  const R = Math.min(face.h * 0.8, (face.w / 2 - 20) / Math.sin(rad(40)) - 16);
  const px = face.x + face.w / 2, py = face.y + 34 + R;
  const pt = (p, r) => { const a = rad(-40 + 80 * p); return [px + r * Math.sin(a), py - r * Math.cos(a)]; };
  const p0 = vuPos(0);
  const arc = (from, to, r, color, width) => {
    ctx.beginPath();
    for (let k = 0; k <= 30; k++) { const [x, y] = pt(from + (to - from) * k / 30, r); k ? ctx.lineTo(x, y) : ctx.moveTo(x, y); }
    ctx.strokeStyle = color; ctx.lineWidth = width; ctx.stroke();
  };
  arc(0, p0, R, C.ink, 1.2);
  arc(p0, 1, R + 2, C.red, 5);
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle';
  const marks = [[-20, '20'], [-10, '10'], [-7, '7'], [-5, '5'], [-3, '3'], [-2, '2'], [-1, '1'], [0, '0'], [1, '1'], [2, '2'], [3, '3']];
  for (const [db, lab] of marks) {
    const p = vuPos(db), color = db > 0 ? C.red : C.ink;
    const [x1, y1] = pt(p, R - 3), [x2, y2] = pt(p, R + 7);
    ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2);
    ctx.strokeStyle = color; ctx.lineWidth = db === 0 ? 1.8 : 1.1; ctx.stroke();
    const [tx, ty] = pt(p, R + 16);
    ctx.fillStyle = color; ctx.font = wide(10); ctx.fillText(lab, tx, ty);
  }
  for (const db of [-15, -8.5, -6, -4, -2.5, -1.5, -0.5, 0.5, 1.5, 2.5]) {
    const [x1, y1] = pt(vuPos(db), R), [x2, y2] = pt(vuPos(db), R + 4);
    ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2);
    ctx.strokeStyle = db > 0 ? C.red : C.ink; ctx.lineWidth = 0.8; ctx.stroke();
  }
  ctx.fillStyle = C.ink; ctx.font = wide(22); ctx.fillText('VU', px, face.y + face.h - face.h * 0.36);
  ctx.globalAlpha = 0.75; ctx.font = wide(9);
  ctx.fillText(channel, face.x + 24, face.y + face.h - 11);
  ctx.fillText('MAD', face.x + face.w - 22, face.y + face.h - 11);
  ctx.globalAlpha = 1;

  const [n1x, n1y] = pt(position, 0), [n2x, n2y] = pt(position, R + 12);
  ctx.save();
  ctx.shadowColor = 'rgba(0,0,0,0.35)'; ctx.shadowBlur = 3; ctx.shadowOffsetX = 2; ctx.shadowOffsetY = 2;
  ctx.beginPath(); ctx.moveTo(n1x, n1y); ctx.lineTo(n2x, n2y);
  ctx.strokeStyle = 'rgb(18,18,23)'; ctx.lineWidth = 1.4; ctx.lineCap = 'round'; ctx.stroke();
  ctx.restore();
  const cg = ctx.createLinearGradient(0, face.y + face.h - 14, 0, face.y + face.h + 8);
  cg.addColorStop(0, 'rgb(51,51,51)'); cg.addColorStop(1, 'rgb(13,13,13)');
  ctx.beginPath(); ctx.ellipse(px, face.y + face.h + 6, face.w * 0.3, 20, 0, 0, Math.PI * 2); ctx.fillStyle = cg; ctx.fill();
  const rg = ctx.createLinearGradient(face.x, face.y, face.x + face.w * 0.35, face.y + face.h / 2);
  rg.addColorStop(0, 'rgba(255,255,255,0.24)'); rg.addColorStop(1, 'rgba(255,255,255,0)');
  ctx.fillStyle = rg; ctx.fillRect(face.x, face.y, face.w, face.h);
  ctx.restore();
  rr(ctx, face.x, face.y, face.w, face.h, 5); ctx.strokeStyle = '#000'; ctx.lineWidth = 1.5; ctx.stroke();

  // Peak: -40 a 0 dBFS, los últimos 4 segmentos (> -6 dB) en blanco, y OVER
  const y = face.y + face.h + 7, overW = 36, x0 = face.x + 20, segW = face.w - 20 - overW - 6, n = 24, sw = segW / n;
  ctx.fillStyle = 'rgba(209,217,227,0.6)'; ctx.font = wide(9); ctx.textAlign = 'center';
  ctx.fillText('PK', face.x + 8, y + 4);
  const lit = Math.round(peak * n);
  for (let i = 0; i < n; i++) {
    const on = i < lit;
    const draw = () => { rr(ctx, x0 + i * sw + 0.75, y, sw - 1.5, 8, 1); ctx.fillStyle = on ? (i >= n - 4 ? '#fff' : C.led) : C.ledOff; ctx.fill(); };
    on ? glow(ctx, C.led, 5, draw) : draw();
  }
  const ox = face.x + face.w - overW;
  const drawOver = () => { rr(ctx, ox, y - 1, overW, 10, 2); ctx.fillStyle = over ? C.red : C.redOff; ctx.fill(); };
  over ? glow(ctx, C.red, 8, drawOver) : drawOver();
  ctx.fillStyle = over ? '#fff' : 'rgb(128,56,56)'; ctx.font = wide(8);
  ctx.fillText('OVER', ox + overW / 2, y + 4);
}

// ---------------------------------------------------------------------------------------------
// Faders: geometría compartida con el manejo del ratón en app.js

export const WELL = {
  top: 14, colH: 212, colW: 46, gap: 8, scaleW: 32, cap: { w: 30, h: 18 },
  get usable() { return this.colH - this.cap.h; },
  get innerW() { return this.scaleW * 2 + 16 * this.colW + 17 * this.gap; },
};

export function wellGeometry(w) {
  const x0 = (w - WELL.innerW) / 2;
  const colX = (i) => x0 + WELL.scaleW + WELL.gap + i * (WELL.colW + WELL.gap);
  const faderX = (i) => colX(i) + (WELL.colW - 41) / 2 + 11;          // LEDs 7 + 4 de separación
  const faderCenter = (i) => faderX(i) + WELL.cap.w / 2;
  const valueY = (v, range) => WELL.top + WELL.cap.h / 2 + WELL.usable * (range - v) / (2 * range);
  const yValue = (y, range) => range - Math.min(Math.max((y - WELL.top - WELL.cap.h / 2) / WELL.usable, 0), 1) * 2 * range;
  const colAt = (x) => {
    for (let i = 0; i < 16; i++) if (x >= colX(i) - WELL.gap / 2 && x < colX(i) + WELL.colW + WELL.gap / 2) return i;
    return -1;
  };
  return { x0, colX, faderX, faderCenter, valueY, yValue, colAt };
}

function capPath(ctx, x, y) {
  const { w, h } = WELL.cap;
  ctx.save();
  ctx.shadowColor = 'rgba(0,0,0,0.75)'; ctx.shadowBlur = 5; ctx.shadowOffsetY = 2.5;
  const g = ctx.createLinearGradient(0, y, 0, y + h);
  g.addColorStop(0, 'rgb(237,237,237)'); g.addColorStop(0.46, 'rgb(158,158,158)');
  g.addColorStop(0.54, 'rgb(209,209,209)'); g.addColorStop(1, 'rgb(107,107,107)');
  rr(ctx, x, y, w, h, 3); ctx.fillStyle = g; ctx.fill();
  ctx.restore();
  rr(ctx, x, y, w, h, 3); ctx.strokeStyle = 'rgba(0,0,0,0.75)'; ctx.lineWidth = 0.6; ctx.stroke();
  ctx.fillStyle = 'rgba(0,0,0,0.3)';
  ctx.fillRect(x + 5, y + h / 2 - 5, w - 10, 0.7); ctx.fillRect(x + 5, y + h / 2 + 4.5, w - 10, 0.7);
  glow(ctx, C.led, 5, () => { ctx.fillStyle = C.ledCore; ctx.fillRect(x + 3, y + h / 2 - 1, w - 6, 2); });
}

export function drawWell(canvas, w, h, o) {
  const ctx = setup(canvas, w, h);
  const G = wellGeometry(w);
  const r = o.range;
  ctx.textAlign = 'center'; ctx.textBaseline = 'middle';

  // Escalas laterales en dB
  ctx.font = wide(10); ctx.fillStyle = 'rgba(209,217,227,0.5)';
  for (const v of [r, r / 2, 0, -r / 2, -r]) {
    const y = G.valueY(v, r), label = v > 0 ? `+${v}` : `${v}`;
    ctx.fillText(label, G.x0 + 16, y);
    ctx.fillText(label, G.x0 + WELL.innerW - 16, y);
  }

  // Curva de respuesta real, detrás de los faders
  if (o.showCurve && o.curveL.length === curvePoints) {
    const xa = G.faderCenter(0), xb = G.faderCenter(15);
    const path = (c) => {
      ctx.beginPath();
      for (let k = 0; k < curvePoints; k++) {
        const t = Math.log(curveFreqs[k] / 20) / Math.log(1000);
        const y = G.valueY(Math.min(Math.max(c[k], -r - 1.5), r + 1.5), r);
        k ? ctx.lineTo(xa + (xb - xa) * t, y) : ctx.moveTo(xa + (xb - xa) * t, y);
      }
    };
    glow(ctx, C.led, 6, () => {
      path(o.curveL); ctx.strokeStyle = 'rgba(199,235,255,0.8)'; ctx.lineWidth = 1.6; ctx.stroke();
      if (o.split) {
        path(o.curveR); ctx.setLineDash([4, 3]); ctx.strokeStyle = 'rgba(77,179,255,0.75)'; ctx.lineWidth = 1.4; ctx.stroke();
        ctx.setLineDash([]);
      }
    });
  }

  const n = 17, center = 8, span = WELL.usable, ledH = Math.max(3, span / (n - 1) * 0.55);
  for (let i = 0; i < 16; i++) {
    const lx = G.colX(i) + (WELL.colW - 41) / 2, fx = G.faderX(i);
    const ledY = (k) => WELL.top + WELL.cap.h / 2 + span * k / (n - 1);   // k = 0 arriba
    const led = (k, color, glowOn) => {
      const d = () => { rr(ctx, lx, ledY(k) - ledH / 2, 7, ledH, 1.2); ctx.fillStyle = color; ctx.fill(); };
      glowOn ? glow(ctx, C.led, 6, d) : d();
    };

    // LEDs: analizador (desde abajo, pico retenido) o ganancia de la banda (desde el centro)
    if (o.spectrum) {
      const lit = Math.round(o.levels[i]), peakLED = Math.round(o.peaks[i]) - 1;
      for (let b = 0; b < n; b++) {
        const k = n - 1 - b;
        if (b < lit) led(k, b >= n - 3 ? '#fff' : C.led, true);
        else if (b === peakLED && peakLED >= 0) led(k, C.ledCore, true);
        else led(k, C.ledOff, false);
      }
    } else {
      const litTo = center - Math.round(o.gains[i] / (r / 8));
      const lo = Math.min(center, litTo), hi = Math.max(center, litTo);
      for (let k = 0; k < n; k++) {
        if (litTo !== center && k >= lo && k <= hi) led(k, C.ledCore, true);
        else if (k === center) led(k, 'rgba(77,179,255,0.4)', false);
        else led(k, C.ledOff, false);
      }
    }

    // Marcas cada cuarto de recorrido y riel
    for (let k = 0; k <= 8; k++) {
      const ty = WELL.top + WELL.cap.h / 2 + span * k / 8, long = k % 4 === 0, tw = long ? 7 : 4;
      ctx.fillStyle = `rgba(209,217,227,${long ? 0.5 : 0.22})`;
      ctx.fillRect(fx, ty - 0.5, tw, 1); ctx.fillRect(fx + WELL.cap.w - tw, ty - 0.5, tw, 1);
    }
    rr(ctx, fx + WELL.cap.w / 2 - 2.5, WELL.top + WELL.cap.h / 2 - 3, 5, span + 6, 2.5);
    ctx.fillStyle = '#000'; ctx.fill();
    ctx.strokeStyle = 'rgba(255,255,255,0.08)'; ctx.lineWidth = 0.5; ctx.stroke();

    capPath(ctx, fx, G.valueY(o.gains[i], r) - WELL.cap.h / 2);

    const sel = o.selected === i;
    ctx.font = wide(11);
    const lab = () => { ctx.fillStyle = sel ? C.ledCore : 'rgba(209,217,227,0.7)'; ctx.fillText(bandLabels[i], G.colX(i) + WELL.colW / 2, WELL.top + WELL.colH + 15); };
    sel ? glow(ctx, C.led, 6, lab) : lab();
  }
}

// ---------------------------------------------------------------------------------------------
// Perilla con anillo de LEDs

export function drawKnob(canvas, size, t) {
  const ctx = setup(canvas, size, size);
  const c = size / 2, R = size / 2;
  const at = (a, r) => [c + r * Math.sin(a), c - r * Math.cos(a)];
  for (let i = 0; i < 21; i++) {
    const f = i / 20, [x, y] = at(rad(-135 + 270 * f), R - 3), on = f <= t + 0.001;
    const d = () => { ctx.beginPath(); ctx.arc(x, y, 1.6, 0, Math.PI * 2); ctx.fillStyle = on ? C.ledCore : C.ledOff; ctx.fill(); };
    on ? glow(ctx, C.led, 5, d) : d();
  }
  const bodyR = R - 9;
  ctx.save(); ctx.shadowColor = 'rgba(0,0,0,0.85)'; ctx.shadowBlur = 8; ctx.shadowOffsetY = 3;
  ctx.beginPath(); ctx.arc(c, c, bodyR, 0, Math.PI * 2); ctx.fillStyle = 'rgb(23,23,23)'; ctx.fill(); ctx.restore();
  ctx.strokeStyle = 'rgba(255,255,255,0.2)'; ctx.lineWidth = 1; ctx.beginPath();
  for (let i = 0; i < 48; i++) { const a = i / 48 * Math.PI * 2; const [x1, y1] = at(a, bodyR - 3), [x2, y2] = at(a, bodyR); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); }
  ctx.stroke();
  const capR = bodyR * 0.74;
  const g = ctx.createRadialGradient(c - capR * 0.35, c - capR * 0.45, 0, c - capR * 0.35, c - capR * 0.45, capR * 1.7);
  g.addColorStop(0, 'rgb(219,219,219)'); g.addColorStop(0.5, 'rgb(140,140,140)'); g.addColorStop(1, 'rgb(71,71,71)');
  ctx.beginPath(); ctx.arc(c, c, capR, 0, Math.PI * 2); ctx.fillStyle = g; ctx.fill();
  ctx.strokeStyle = 'rgba(255,255,255,0.06)'; ctx.lineWidth = 0.6;
  for (let k = 0.3; k < 1; k += 0.15) { ctx.beginPath(); ctx.arc(c, c, capR * k, 0, Math.PI * 2); ctx.stroke(); }
  const a = rad(-135 + 270 * t), [x1, y1] = at(a, capR * 0.3), [x2, y2] = at(a, bodyR - 2);
  glow(ctx, C.led, 5, () => {
    ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2);
    ctx.strokeStyle = C.ledCore; ctx.lineWidth = 2.2; ctx.lineCap = 'round'; ctx.stroke();
  });
}

// ---------------------------------------------------------------------------------------------
// Barra horizontal: bipolar desde el centro (correlación) o desde la derecha (reducción de ganancia)

export function drawBar(canvas, w, h, value, mode) {
  const ctx = setup(canvas, w, h);
  const n = 21, c = 10, sw = w / n;
  const t = Math.round(value * (mode === 'bipolar' ? c : n));
  for (let i = 0; i < n; i++) {
    let lit, warn = false;
    if (mode === 'bipolar') { lit = t !== 0 && i >= Math.min(c, c + t) && i <= Math.max(c, c + t); warn = i < c; }
    else { lit = i >= n - t; warn = i < n - 14; }
    const color = lit ? (warn ? C.red : C.ledCore) : (mode === 'bipolar' && i === c ? 'rgba(77,179,255,0.4)' : C.ledOff);
    const d = () => { rr(ctx, i * sw + 1, 0, sw - 2, h, 1); ctx.fillStyle = color; ctx.fill(); };
    lit ? glow(ctx, warn ? C.red : C.led, 4, d) : d();
  }
}
