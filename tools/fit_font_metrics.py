"""Paso 2 de MAD Microgramma Black: ajusta ancho y espaciado de cada glifo a los de una fuente de referencia.

    python tools/fit_font_metrics.py base.ttf referencia.ttf MADMicrogramma-Black.ttf 1.0 0.72 1.2

Argumentos: base, referencia, salida, [fuerza = 1.0], [escala mínima = 0.88], [escala máxima = 1.12].
Las medidas se normalizan por la altura de la mayúscula H. Solo se leen anchos, avances y márgenes de la
referencia (una Microgramma / Eurostile Bold Extended); no se copian sus contornos y la referencia no se
distribuye con este repositorio. En los símbolos también se ajusta la altura y la posición vertical.
"""
import sys
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.recordingPen import DecomposingRecordingPen, replayRecording
from fontTools.pens.boundsPen import BoundsPen

base_p, ref_p, out_p = sys.argv[1:4]
strength = float(sys.argv[4]) if len(sys.argv) > 4 else 1.0
lo = float(sys.argv[5]) if len(sys.argv) > 5 else 0.88
hi = float(sys.argv[6]) if len(sys.argv) > 6 else 1.12
f, ref = TTFont(base_p), TTFont(ref_p)
cm_f, cm_r = f.getBestCmap(), ref.getBestCmap()
gs_f, gs_r = f.getGlyphSet(), ref.getGlyphSet()

def bounds(font, gs, name):
    from fontTools.pens.boundsPen import BoundsPen
    bp = BoundsPen(gs); gs[name].draw(bp); return bp.bounds
bh_f, bh_r = bounds(f, gs_f, cm_f[ord('H')]), bounds(ref, gs_r, cm_r[ord('H')])
cap_f, cap_r = bh_f[3] - bh_f[1], bh_r[3] - bh_r[1]

def split_contours(value):
    """Separa una grabación de pluma en contornos (cada uno empieza en un moveTo)."""
    out, cur = [], []
    for op, args in value:
        if op == 'moveTo' and cur: out.append(cur); cur = []
        cur.append((op, args))
    if cur: out.append(cur)
    return out

def contours_bounds(conts):
    bp = BoundsPen(None)
    for c in conts: replayRecording(c, bp)
    return bp.bounds


k = cap_f / cap_r
glyf, hmtx = f['glyf'], f['hmtx']
done = 0; report = []
for cp, name in cm_f.items():
    if cp not in cm_r or name not in hmtx.metrics: continue
    ch = chr(cp)
    if not (ch.isalnum() or ch in "+-−.,:;/%&()!?'\"#*=<>_@" ) or ch == ' ': continue
    bf = bounds(f, gs_f, name); br = bounds(ref, gs_r, cm_r[cp])
    if ch.isupper() and not ch.isascii():
        # mayúsculas acentuadas: el ancho y los márgenes se miden solo en la letra, sin el acento
        rf0 = DecomposingRecordingPen(gs_f); gs_f[name].draw(rf0)
        rr0 = DecomposingRecordingPen(gs_r); gs_r[cm_r[cp]].draw(rr0)
        cb_f = [c for c in split_contours(rf0.value) if contours_bounds([c])[1] <= bh_f[3] + 30]
        cb_r = [c for c in split_contours(rr0.value) if contours_bounds([c])[1] <= bh_r[3] + 30]
        if cb_f and cb_r:
            bf = (*contours_bounds(cb_f)[:2], *contours_bounds(cb_f)[2:]) if False else (contours_bounds(cb_f)[0], bf[1], contours_bounds(cb_f)[2], bf[3])
            br = (contours_bounds(cb_r)[0], br[1], contours_bounds(cb_r)[2], br[3])
    if not bf or not br: continue
    wf = bf[2] - bf[0]; wr = (br[2] - br[0]) * k
    advr = ref['hmtx'][cm_r[cp]][0] * k; lsbr = br[0] * k
    fac = 1 + (min(hi, max(lo, wr / wf)) - 1) * strength
    # nuevo ancho y márgenes izquierdo y derecho escalados como en la referencia
    neww = wf * fac
    newadv = advr * strength + hmtx[name][0] * (1 - strength)
    newlsb = lsbr * strength + bf[0] * (1 - strength)
    rec = DecomposingRecordingPen(gs_f); gs_f[name].draw(rec)
    pen = TTGlyphPen(None)
    fy, ty = 1.0, 0.0
    if not ch.isalnum():
        # símbolos: también se ajusta la altura y la posición vertical
        hr = (br[3] - br[1]) * k; hf = bf[3] - bf[1]
        if hf > 0 and hr > 0:
            fy = min(1.25, max(0.75, hr / hf)); ty = br[1] * k - bf[1] * fy
    M = (fac, 0, 0, fy, newlsb - bf[0] * fac, ty)
    # Acentos de mayúsculas: los contornos por encima de la mayúscula se ajustan a la caja del acento de la referencia.
    acc = None
    if ch.isupper() and not ch.isascii():
        from fontTools.pens.recordingPen import RecordingPen
        conts = []
        for c in split_contours(rec.value):
            t = RecordingPen(); replayRecording(c, TransformPen(t, M)); conts.append(t.value)
        capTop = bh_f[3]
        a_f = [c for c in conts if contours_bounds([c])[1] > capTop + 30]
        rr = DecomposingRecordingPen(gs_r); gs_r[cm_r[cp]].draw(rr)
        a_r = [c for c in split_contours(rr.value) if contours_bounds([c])[1] > bh_r[3] + 30]
        if a_f and a_r:
            ba, br2 = contours_bounds(a_f), contours_bounds(a_r)
            tw, th = (br2[2] - br2[0]) * k, (br2[3] - br2[1]) * k
            sx, sy = tw / (ba[2] - ba[0]), th / (ba[3] - ba[1])
            tx, ty2 = br2[0] * k - ba[0] * sx, br2[1] * k - ba[1] * sy
            for c in conts:
                if c in a_f: replayRecording(c, TransformPen(pen, (sx, 0, 0, sy, tx, ty2)))
                else: replayRecording(c, pen)
            acc = True
    if acc is None:
        rec.replay(TransformPen(pen, M))
    glyf[name] = pen.glyph(); glyf[name].recalcBounds(glyf)
    hmtx[name] = (int(round(max(newadv, newlsb + neww))), int(glyf[name].xMin))
    done += 1; report.append((ch, round(fac, 3)))
if 'GPOS' in f: del f['GPOS']   # los kernings de Michroma ya no corresponden
if 'kern' in f: del f['kern']
f.save(out_p)
print('glifos ajustados:', done)
print(' '.join(f"{c}:{x}" for c, x in report if c.isalnum()))
