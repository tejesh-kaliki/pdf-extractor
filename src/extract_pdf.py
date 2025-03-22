import io
import pymupdf
import bisect
import statistics

MIN_FONT_SIZE = 3

def find_line_index(values: list[int], value: int) -> int:
    """Find the right row coordinate.

    Args:
        values: (list) y-coordinates of rows.
        value: (int) lookup for this value (y-origin of char).
    Returns:
        y-ccordinate of appropriate line for value.
    """
    i = bisect.bisect_right(values, value)
    if i:
        return values[i - 1]
    raise RuntimeError("Line for %g not found in %s" % (value, values))

def curate_rows(rows: set[int], GRID: int) -> list[int]:
    rows_list = list(rows)
    rows_list.sort()  # sort ascending
    nrows = [rows_list[0]]
    for h in rows_list[1:]:
        if h >= nrows[-1] + GRID:  # only keep significant differences
            nrows.append(h)
    return nrows  # curated list of line bottom coordinates

def joinligature(lig: str) -> str:
    """Return ligature character for a given pair / triple of characters.

    Args:
        lig: (str) 2/3 characters, e.g. "ff"
    Returns:
        Ligature, e.g. "ff" -> chr(0xFB00)
    """

    mapping = {
        "ff": chr(0xFB00),
        "fi": chr(0xFB01),
        "fl": chr(0xFB02),
        "ffi": chr(0xFB03),
        "ffl": chr(0xFB04),
        "ft": chr(0xFB05),
        "st": chr(0xFB06)
    }
    return mapping.get(lig, lig)

def make_textline(left: float, slot: float, minslot: float, lchars: list[tuple]):
    """Produce the text of one output line.

    Args:
        left: (float) left most coordinate used on page
        slot: (float) avg width of one character in any font in use.
        minslot: (float) min width for the characters in this line.
        chars: (list[tuple]) characters of this line.
    Returns:
        text: (str) text string for this line
    """
    text = ""  # we output this
    old_char = ""
    old_x1 = 0  # end coordinate of last char
    old_ox = 0  # x-origin of last char
    if minslot <= pymupdf.EPSILON:
        raise RuntimeError("program error: minslot too small = %g" % minslot)

    for char, ox, _, cwidth in lchars:  # loop over characters
        ox = ox - left  # its (relative) start coordinate
        x1 = ox + cwidth  # ending coordinate

        # eliminate overprint effect
        if old_char == char and ox - old_ox <= cwidth * 0.2:
            continue

        # omit spaces overlapping previous char
        if char == " " and (old_x1 - ox) / cwidth > 0.8:
            continue

        old_char = char
        # close enough to previous?
        if ox < old_x1 + minslot:  # assume char adjacent to previous
            text += char  # append to output
            old_x1, old_ox = x1, ox  # new end coord
            continue

        # else next char starts after some gap:
        # fill in right number of spaces, so char is positioned
        # in the right slot of the line
        if char == " ":  # rest relevant for non-space only
            continue

        delta = int(ox / slot) - len(text)
        if ox > old_x1 and delta > 1:
            text += " " * delta

        # now append char
        text += char
        old_x1, old_ox = x1, ox  # new end coordinate
    return text.rstrip()

def process_blocks(blocks: list[dict], page: pymupdf.Page):
    rows = set()
    page_width = page.rect.width
    page_height = page.rect.height
    rowheight = page_height
    left = page_width
    right = 0
    chars = []
    for block in blocks:
        for line in block["lines"]:
            if line["dir"] != (1, 0):  # ignore non-horizontal text
                continue

            x0, y0, x1, y1 = line["bbox"]
            if y1 < 0 or y0 > page.rect.height:  # ignore if outside CropBox
                continue

            # update row height
            rowheight = min(rowheight, y1 - y0)

            for span in line["spans"]:
                if span["size"] <= MIN_FONT_SIZE:
                    continue

                for c in span["chars"]:
                    x0, _, x1, _ = c["bbox"]
                    cwidth = x1 - x0
                    ox, oy = c["origin"]
                    oy = int(round(oy))
                    rows.add(oy)
                    ch = c["c"]

                    right = max(right, x1)
                    if ch != " ":
                        left = min(left, ox)

                    # handle ligatures:
                    if cwidth == 0 and chars != []:  # potential ligature
                        old_ch, old_ox, old_oy, old_cwidth = chars[-1]
                        if old_oy == oy:  # ligature
                            if old_ch != chr(0xFB00):  # previous "ff" char lig?
                                lig = joinligature(old_ch + ch)  # no
                            # convert to one of the 3-char ligatures:
                            elif ch == "i":
                                lig = chr(0xFB03)  # "ffi"
                            elif ch == "l":
                                lig = chr(0xFB04)  # "ffl"
                            else:  # something wrong, leave old char in place
                                lig = old_ch
                            chars[-1] = (lig, old_ox, old_oy, old_cwidth)
                            continue
                    chars.append((ch, ox, oy, cwidth))  # all chars on page
    return chars, rows, left, right, rowheight

def page_layout(page: pymupdf.Page, textout: io.BytesIO, flags: int):
    eop = bytes([12])

    # extract page text by single characters ("rawdict")
    blocks = page.get_text("rawdict", flags=flags)["blocks"] # type: ignore
    chars, rows, left, right, rowheight = process_blocks(blocks, page)

    if chars == []:
        textout.write(eop)  # write formfeed
        return

    # compute list of line coordinates - ignoring small (GRID) differences
    rows = curate_rows(rows, 2)

    # sort all chars by x-coordinates, so every line will receive char info,
    # sorted from left to right.
    chars.sort(key=lambda c: c[1])

    # populate the lines with their char info
    lines = {}  # key: y1-ccordinate, value: char list
    for c in chars:
        _, _, oy, _ = c
        y = find_line_index(rows, oy)  # y-coord of the right line
        lchars = lines.get(y, [])  # read line chars so far
        lchars.append(c)  # append this char
        lines[y] = lchars  # write back to line

    # ensure line coordinates are ascending
    keys = list(lines.keys())
    keys.sort()

    # -------------------------------------------------------------------------
    # Compute "char resolution" for the page: the char width corresponding to
    # 1 text char position on output - call it 'slot'.
    # For each line, compute median of its char widths. The minimum across all
    # lines is 'slot'.
    # The minimum char width of each line is used to determine if spaces must
    # be inserted in between two characters.
    # -------------------------------------------------------------------------
    slot = right - left
    minslots = {}
    for k in keys:
        lchars = lines[k]
        ccount = len(lchars)
        if ccount < 2:
            minslots[k] = 1
            continue
        widths = [c[3] for c in lchars]
        widths.sort()
        this_slot = statistics.median(widths)  # take median value
        if this_slot < slot:
            slot = this_slot
        minslots[k] = widths[0]

    # compute line advance in text output
    rowheight = rowheight * (rows[-1] - rows[0]) / (rowheight * len(rows)) * 1.2
    rowpos = rows[0]  # first line positioned here
    textout.write(b"\n")
    for k in keys:  # walk through the lines
        while rowpos < k:  # honor distance between lines
            textout.write(b"\n")
            rowpos += rowheight
        text = make_textline(left, slot, minslots[k], lines[k])
        textout.write((text + "\n").encode("utf8", errors="surrogatepass"))
        rowpos = k + rowheight

    textout.write(eop)  # write formfeed

def extract_text_from_pdf(stream: io.BytesIO) -> bytes:
    response = None
    with pymupdf.open(stream=stream) as pdf, io.BytesIO() as output:
        for page in pdf:
            page_layout(
                page,
                output,
                flags=pymupdf.TEXT_PRESERVE_LIGATURES | pymupdf.TEXT_PRESERVE_WHITESPACE,
            )
        response = output.getvalue()

    return response

if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description='Extract text from PDF file')
    parser.add_argument('filename', help='Path to the PDF file')
    args = parser.parse_args()

    with open(args.filename, "rb") as file:
        content = file.read()

    with io.BytesIO(content) as stream:
        response = extract_text_from_pdf(stream)
    print(response.decode("utf8"))
