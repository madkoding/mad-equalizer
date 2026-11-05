"""Paso 3 de MAD Microgramma Black: recorta los "labios" de los terminales de C G S 3 5 6 8 9 0 2 para abrir sus aberturas.

    python tools/open_font_apertures.py ajustada.ttf referencia.ttf MADMicrogramma-Black.ttf "CGS3568902" [tolerancia = 7] [glifos de bloque único, p. ej. "6"] [área mínima = 900]

Receta usada: un primer paso con "CGS358902" y un segundo, sobre el resultado, con "6" como bloque único; en ambos
con área mínima 2500 para ignorar fragmentos pequeños que dejarían muescas.

Se comparan los glifos de la fuente con los de la referencia (ya ajustada con fit_font_metrics.py) y se recortan,
con franjas finas, las zonas pequeñas en las que la fuente sobresale (los terminales de esas letras). Sirve para
que C, G y S se lean a 6-8 px; la referencia no se distribuye con este repositorio.
"""
import sys
import numpy as np
import pathops
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage
from fontTools.ttLib import TTFont
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.recordingPen import DecomposingRecordingPen

src, ref_p, out = sys.argv[1:4]
chars = sys.argv[4] if len(sys.argv) > 4 else "CGS3568902"
TOL = int(sys.argv[5]) if len(sys.argv) > 5 else 7      # tolerancia (px) al comparar con la referencia
BOXES = sys.argv[6] if len(sys.argv) > 6 else ""         # glifos cuyo sobrante es un único bloque rectangular (se recorta de una vez)
MIN_AREA = int(sys.argv[7]) if len(sys.argv) > 7 else 900   # píxeles mínimos de una zona sobrante para recortarla
f, ref = TTFont(src), TTFont(ref_p)
cm, cmr = f.getBestCmap(), ref.getBestCmap()
gs, gsr = f.getGlyphSet(), ref.getGlyphSet()
def cap(font, gset, cmap):
    b = BoundsPen(gset); gset[cmap[ord('H')]].draw(b); return b.bounds[3] - b.bounds[1]
K = cap(f, gs, cm) / cap(ref, gsr, cmr)
S = 700                      # px por em de la fuente
em = f['head'].unitsPerEm
fo, fr = ImageFont.truetype(src, S), ImageFont.truetype(ref_p, S * K)
W, H, X0, Y0 = 1700, 1300, 150, 950
def mask(font, ch):
    im = Image.new('L', (W, H), 0); ImageDraw.Draw(im).text((X0, Y0), ch, font=font, fill=255, anchor='ls')
    return np.array(im) > 127
glyf = f['glyf']
for ch in chars:
    name = cm.get(ord(ch))
    if not name: continue
    mo, mr = mask(fo, ch), mask(fr, ch)
    diff = mo & ~ndimage.binary_dilation(mr, iterations=TOL)
    diff = ndimage.binary_opening(diff, structure=np.ones((9, 9)))
    lab, n = ndimage.label(diff)
    rects = []
    BAND = 6   # filas por banda: la zona sobrante se descompone en rectángulos finos
    for i in range(1, n + 1):
        comp = lab == i
        ys, xs = np.where(comp)
        if len(xs) < MIN_AREA: continue
        if ch in BOXES:
            rects.append((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1)); continue
        for y in range(ys.min(), ys.max() + 1, BAND):
            band = comp[y:y + BAND]
            cols = np.where(band.any(axis=0))[0]
            if not len(cols): continue
            # tramos continuos de columnas dentro de la banda
            start = prev = cols[0]
            for c in list(cols[1:]) + [None]:
                if c is None or c != prev + 1:
                    rects.append((start, y, prev + 1, min(y + BAND, comp.shape[0])))
                    if c is not None: start = c
                if c is not None: prev = c
    if not rects: continue
    rec = DecomposingRecordingPen(gs); gs[name].draw(rec)
    path = pathops.Path(); rec.replay(path.getPen())
    for (x0, y0, x1, y1) in rects:
        # píxeles -> unidades de la fuente (y hacia arriba desde la línea base); se amplía unas unidades
        ux0, ux1 = (x0 - X0) * em / S - 3, (x1 - X0) * em / S + 3
        uy1, uy0 = (Y0 - y0) * em / S + 2, (Y0 - y1) * em / S - 2
        r = pathops.Path(); pen = r.getPen()
        pen.moveTo((ux0, uy0)); pen.lineTo((ux1, uy0)); pen.lineTo((ux1, uy1)); pen.lineTo((ux0, uy1)); pen.closePath()
        path = pathops.op(path, r, pathops.PathOp.DIFFERENCE, fix_winding=True, keep_starting_points=False)
    pen = TTGlyphPen(None); path.draw(Cu2QuPen(pen, 1.0, reverse_direction=True))
    glyf[name] = pen.glyph(); glyf[name].recalcBounds(glyf)
    print(ch, 'rectángulos recortados:', len(rects))
f.save(out)
