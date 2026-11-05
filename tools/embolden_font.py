"""Engrosa una fuente TrueType de forma anisótropa: dx = extra de trazos verticales, dy = extra de horizontales.

Así se generó MADMicrogramma-Black.ttf a partir de Michroma-Regular.ttf (SIL OFL 1.1, sin nombre reservado):

    pip install fonttools skia-pathops
    python tools/embolden_font.py Michroma-Regular.ttf MADMicrogramma-Black.ttf 270 110 "MAD Microgramma" Black

Michroma tiene 2048 unidades por em: 270 / 110 suman 270 al grosor de los trazos verticales y 110 al de los
horizontales, de modo que las aberturas de C, S y G siguen abiertas a tamaños pequeños.
"""
import sys
import pathops
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.recordingPen import DecomposingRecordingPen

src, out, dx, dy, family, style = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4]), sys.argv[5], sys.argv[6]
f = TTFont(src)
gs = f.getGlyphSet()
glyf, hmtx = f['glyf'], f['hmtx']
r = dy / dx
new = {}
for name in f.getGlyphOrder():
    rec = DecomposingRecordingPen(gs)
    gs[name].draw(rec)
    if not rec.value:
        new[name] = None
        continue
    base = pathops.Path()
    rec.replay(TransformPen(base.getPen(), (1, 0, 0, 1 / r, 0, 0)))
    ribbon = pathops.Path()
    rec.replay(TransformPen(ribbon.getPen(), (1, 0, 0, 1 / r, 0, 0)))
    ribbon.stroke(dx, pathops.LineCap.BUTT_CAP, pathops.LineJoin.MITER_JOIN, 4)
    merged = pathops.op(base, ribbon, pathops.PathOp.UNION, fix_winding=True, keep_starting_points=False)
    pen = TTGlyphPen(None)
    merged.draw(TransformPen(Cu2QuPen(pen, 1.0, reverse_direction=True), (1, 0, 0, r, dx / 2, 0)))
    new[name] = pen.glyph()
for name, g in new.items():
    adv, lsb = hmtx[name]
    if g is None:
        hmtx[name] = (int(round(adv + (dx if adv else 0))), lsb)
        continue
    glyf[name] = g
    g.recalcBounds(glyf)
    hmtx[name] = (int(round(adv + dx)), int(g.xMin))
for t in ('fpgm', 'prep', 'cvt ', 'hdmx', 'VDMX', 'LTSH', 'gasp', 'DSIG'):
    if t in f:
        del f[t]
f['OS/2'].usWeightClass = 900 if style == 'Black' else 700
n = f['name']
ps = (family + '-' + style).replace(' ', '')
for rec_ in list(n.names):
    if rec_.nameID in (1, 16): rec_.string = family
    elif rec_.nameID in (2, 17): rec_.string = style
    elif rec_.nameID == 4: rec_.string = family + ' ' + style
    elif rec_.nameID == 6: rec_.string = ps
    elif rec_.nameID == 3: rec_.string = ps + ';derivado de Michroma (SIL OFL 1.1)'
f['head'].flags &= ~(1 << 3)
f.save(out)
print('ok', out)
