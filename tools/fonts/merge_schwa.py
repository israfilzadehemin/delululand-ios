#!/usr/bin/env python3
"""
Adds capital schwa (U+018F, "Ə") to Manrope, which lacks it, by copying the glyph from Noto Sans.

Same rule as the web app (src/styles/fonts.css, face 'DL Schwa'): weights 400-500 take Noto Sans 400,
weights 600-800 take Noto Sans 700. Noto Sans is 1000 units per em, Manrope 2000, so the outline and
advance are scaled by Manrope's UPM / Noto's UPM. Both fonts are SIL OFL 1.1 without Reserved Font Names.

Usage: merge_schwa.py <manrope.ttf> <notosans.ttf> <out.ttf>
"""
import sys

from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

SCHWA = 0x018F


def merge(manrope_path: str, noto_path: str, out_path: str) -> None:
    target = TTFont(manrope_path)
    source = TTFont(noto_path)
    if SCHWA in target.getBestCmap():
        target.save(out_path)
        return
    src_name = source.getBestCmap()[SCHWA]
    scale = target["head"].unitsPerEm / source["head"].unitsPerEm

    glyph_set = source.getGlyphSet()
    # The Noto glyph is a composite (schwa + accent parts); flatten it into plain contours.
    recording = DecomposingRecordingPen(glyph_set)
    glyph_set[src_name].draw(recording)
    pen = TTGlyphPen(None)
    recording.replay(TransformPen(pen, (scale, 0, 0, scale, 0, 0)))
    glyph = pen.glyph()

    name = "uni018F"
    order = target.getGlyphOrder() + [name]
    target.setGlyphOrder(order)
    target["glyf"][name] = glyph
    glyph.recalcBounds(target["glyf"])
    advance, _ = source["hmtx"][src_name]
    target["hmtx"][name] = (round(advance * scale), glyph.xMin)
    for table in target["cmap"].tables:
        if table.isUnicode():
            table.cmap[SCHWA] = name
    target["maxp"].numGlyphs = len(order)
    target.save(out_path)


if __name__ == "__main__":
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    merge(sys.argv[1], sys.argv[2], sys.argv[3])
