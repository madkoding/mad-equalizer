"""Paso 1 de la tipografía MAD Microgramma Black: engrosa Michroma (SIL OFL 1.1) de forma anisótropa.

    pip install fonttools skia-pathops
    python tools/embolden_font.py Michroma-Regular.ttf base.ttf 360 275 "MAD Microgramma" Black 1.08 1.0

Argumentos: origen, destino, dx, dy, familia, estilo, [ensanchado horizontal = 1.0], [factor de engrosado
horizontal para C G S 3 5 6 8 9 = 1.0; con 1.0 el grosor es completo y las aberturas se abren después].

Michroma tiene 2048 unidades por em. dx / dy suman al grosor de los trazos verticales y horizontales; el
ensanchado compensa las proporciones. Las uniones agudas se bisean (miter limit 2) para que no salgan puntas, y la base de cada glifo se
sube dy/2 para que siga apoyada en la línea base. Los acentos suben lo que sube la letra. Después:
tools/fit_font_metrics.py (anchos, espaciado y caja de los acentos) y tools/open_font_apertures.py (aberturas de
C G S y números). Se usa open=1.0 en este paso.
"""
import sys
import pathops
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.recordingPen import DecomposingRecordingPen

src, out, dx, dy, family, style = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4]), sys.argv[5], sys.argv[6]
xs = float(sys.argv[7]) if len(sys.argv) > 7 else 1.0   # ensanchado horizontal previo
OPEN = float(sys.argv[8]) if len(sys.argv) > 8 else 1.0
f = TTFont(src)
gs = f.getGlyphSet()
glyf, hmtx = f['glyf'], f['hmtx']
cmap = f.getBestCmap()
r = dy / dx
open_names = {cmap[ord(c)] for c in 'CGScgs35689' if ord(c) in cmap}
# Mayúsculas y números: el engrosado se recorta contra la altura de mayúscula, de modo que los extremos de las
# diagonales (K, X, Y, V, W, 7...) queden cortados planos en vez de biselados o con puntas.
clip_names = {cmap[ord(c)] for c in 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789' if ord(c) in cmap}
bh = BoundsPen(gs); gs[cmap[ord('H')]].draw(bh)
CAP = bh.bounds[3] + dy          # altura de mayúscula tras engrosar
OVER = 45                        # sobrepaso permitido a las curvas
flat_names = {cmap[ord(c)] for c in 'AEFHIKLMNTVWXYZ1247' if ord(c) in cmap}   # letras planas: sin sobrepaso

cache = {}
def final_path(name):
    """Contorno del glifo ya engrosado, en las coordenadas finales de la fuente."""
    if name in cache: return cache[name]
    g = glyf[name]
    if g.isComposite():
        total = pathops.Path()
        for c in g.components:
            sub = final_path(c.glyphName)
            bp = BoundsPen(gs); gs[c.glyphName].draw(bp)
            lift = dy if (bp.bounds and bp.bounds[1] > 600) else 0   # los acentos suben lo que sube la letra
            moved = pathops.Path()
            sub.draw(TransformPen(moved.getPen(), (1, 0, 0, 1, c.x * xs, c.y + lift)))
            total = pathops.op(total, moved, pathops.PathOp.UNION, fix_winding=True, keep_starting_points=False)
        cache[name] = total
        return total
    rec = DecomposingRecordingPen(gs); gs[name].draw(rec)
    result = pathops.Path()
    if rec.value:
        rg = r * (OPEN if name in open_names else 1.0)
        base = pathops.Path(); rec.replay(TransformPen(base.getPen(), (xs, 0, 0, 1 / rg, 0, 0)))
        ribbon = pathops.Path(); rec.replay(TransformPen(ribbon.getPen(), (xs, 0, 0, 1 / rg, 0, 0)))
        ribbon.stroke(dx, pathops.LineCap.BUTT_CAP, pathops.LineJoin.MITER_JOIN, 8)
        merged = pathops.op(base, ribbon, pathops.PathOp.UNION, fix_winding=True, keep_starting_points=False)
        if name in clip_names:
            over = 0 if name in flat_names else OVER
            lo, hi = (-over) / rg - dx / 2, (CAP + over) / rg - dx / 2     # en el espacio estirado
            box = pathops.Path(); bp = box.getPen()
            bp.moveTo((-9000, lo)); bp.lineTo((9000, lo)); bp.lineTo((9000, hi)); bp.lineTo((-9000, hi)); bp.closePath()
            merged = pathops.op(merged, box, pathops.PathOp.INTERSECTION, fix_winding=True, keep_starting_points=False)
        merged.draw(TransformPen(result.getPen(), (1, 0, 0, rg, dx / 2, rg * dx / 2)))   # +dy/2: la base queda sobre la línea base
    cache[name] = result
    return result

for name in f.getGlyphOrder():
    path = final_path(name)
    adv, lsb = hmtx[name]
    if not any(True for _ in path.segments):
        hmtx[name] = (int(round(adv * xs + (dx if adv else 0))), lsb)
        continue
    pen = TTGlyphPen(None)
    path.draw(Cu2QuPen(pen, 1.0, reverse_direction=True))
    g = pen.glyph(); glyf[name] = g; g.recalcBounds(glyf)
    hmtx[name] = (int(round(adv * xs + dx)), int(g.xMin))
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
