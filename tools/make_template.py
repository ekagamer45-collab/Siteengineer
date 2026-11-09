#!/usr/bin/env python3
"""Bangun assets/template.xlsx (ringan, tanpa foto lama) + assets/config.json
dari file LAPORAN_HARIAN_MINGGU_x.xlsx asli.
Pakai:  python3 tools/make_template.py LAPORAN_HARIAN_MINGGU_9.xlsx
"""
import sys, re, json, zipfile, io, collections
import openpyxl
from PIL import Image, ImageDraw

src = sys.argv[1]
out_xlsx, out_cfg = 'assets/template.xlsx', 'assets/config.json'
zin = zipfile.ZipFile(src)
files = {n: zin.read(n) for n in zin.namelist()}
wb = openpyxl.load_workbook(src)

# nama sheet -> file sheet
wbx = files['xl/workbook.xml'].decode()
rels = files['xl/_rels/workbook.xml.rels'].decode()
rid2t = {m[0]: m[1] for m in re.findall(r'<Relationship Id="(rId\d+)"[^>]*?Target="([^"]+)"', rels)}
rid2t.update({m[1]: m[0] for m in re.findall(r'Target="([^"]+)"[^>]*?Id="(rId\d+)"', rels)})
sheets = [(n, rid2t[r]) for n, r in re.findall(r'<sheet name="([^"]+)"[^>]*r:id="(rId\d+)"', wbx)]

def placeholder(aspect, text='Belum ada foto'):
    w = 480; h = max(1, round(w / aspect))
    im = Image.new('RGB', (w, h), (232, 232, 232))
    d = ImageDraw.Draw(im); d.text((12, 12), text, fill=(120, 120, 120))
    b = io.BytesIO(); im.save(b, 'JPEG', quality=70); return b.getvalue()

cfg = {'sheets': []}
for name, target in sheets:
    ws = wb[name]
    sheet_path = 'xl/' + target.lstrip('/').replace('xl/', '')
    srel = files[sheet_path.replace('worksheets/', 'worksheets/_rels/') + '.rels'].decode()
    dpath = 'xl/drawings/' + re.search(r'drawings/(drawing\d+\.xml)', srel).group(1)
    drel_path = dpath.replace('drawings/', 'drawings/_rels/') + '.rels'
    drels = files[drel_path].decode()
    d = files[dpath].decode()
    slots = []
    def fix_anchor(m):
        a = m.group(0)
        if '<xdr:pic>' not in a: return a
        emb = re.search(r'r:embed="(rId\d+)"', a)
        cx, cy = map(int, re.search(r'<a:ext cx="(\d+)" cy="(\d+)"/>', a).groups())
        if cx < 2_000_000: return a                       # tanda tangan, bukan foto
        col, row = map(int, re.search(r'<xdr:from><xdr:col>(\d+)</xdr:col>.*?<xdr:row>(\d+)</xdr:row>', a, re.S).groups())
        lo, hi = (1, 8) if col < 8 else (9, 16)
        parts = [str(ws.cell(row, c).value).strip() for c in range(lo, hi + 1) if ws.cell(row, c).value]
        label = re.sub(r'\s+', ' ', ' '.join(parts)) or f'Foto baris {row+1}'
        idx = len(slots) + 1
        media = f'slot_{name}_{idx:02d}.jpeg'
        slots.append({'id': f'{name}_{idx:02d}', 'label': label, 'media': 'xl/media/' + media,
                      'aspect': round(cx / cy, 4), 'row': row + 1, 'col': col})
        files['xl/media/' + media] = placeholder(cx / cy)
        rid = emb.group(1)
        if rid in nonlocal_rel:
            # Jika ada dua bingkai foto yang berbagi rId yang sama karena copy-paste di Excel,
            # buat rId baru agar tiap slot punya file media sendiri.
            new_rid = f'rIdSlot{idx}'
            a = a.replace(f'r:embed="{rid}"', f'r:embed="{new_rid}"', 1)
            nonlocal_new_rels[new_rid] = media
        else:
            nonlocal_rel[rid] = media
        return re.sub(r'<a:srcRect[^>]*/>', '', a)
    nonlocal_rel = {}
    nonlocal_new_rels = {}
    d = re.sub(r'<xdr:twoCellAnchor.*?</xdr:twoCellAnchor>', fix_anchor, d, flags=re.S)
    for rid, media in nonlocal_rel.items():
        drels = re.sub(r'(<Relationship Id="%s"[^>]*?Target=")[^"]+(")' % rid, r'\g<1>../media/%s\2' % media, drels)
    for new_rid, media in nonlocal_new_rels.items():
        rel_tag = f'<Relationship Id="{new_rid}" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="../media/{media}"/>'
        drels = drels.replace('</Relationships>', rel_tag + '</Relationships>')
    files[dpath] = d.encode(); files[drel_path] = drels.encode()
    slots.sort(key=lambda s: (s['row'], s['col']))
    pages = [r for r in range(1, ws.max_row + 1) if ws.cell(r, 1).value == 'Nama Sekolah']
    cfg['sheets'].append({'name': name, 'path': sheet_path, 'pages': pages, 'slots': slots})

# kotak centang cuaca kolom N,O: beri font Wingdings 2 (seperti kolom M) supaya 'P' tampil sebagai ✓
st = files['xl/styles.xml'].decode()
m = re.search(r'(<cellXfs count=")(\d+)(">)(.*?)(</cellXfs>)', st, re.S)
xfs = re.findall(r'<xf [^>]*?(?:/>|>.*?</xf>)', m.group(4), re.S)
newmap = {}
def wing(sid):
    if sid not in newmap:
        x = re.sub(r'fontId="\d+"', 'fontId="1"', xfs[sid], 1)
        if 'applyFont' not in x: x = x.replace('<xf ', '<xf applyFont="1" ', 1)
        xfs.append(x); newmap[sid] = len(xfs) - 1
    return newmap[sid]
for sh in cfg['sheets']:
    sx = files[sh['path']].decode()
    def fx(mm):
        sid = re.search(r' s="(\d+)"', mm.group(0))
        return re.sub(r' s="\d+"', ' s="%d"' % wing(int(sid.group(1))), mm.group(0), 1) if sid else mm.group(0)
    for col, r1, r2 in [('G',10,16),('J',10,19),('P',10,13),('M',15,19),('N',15,19),('O',15,19)]:
        for r in range(r1, r2 + 1):
            sx = re.sub(r'<c r="%s%d"[^>]*?(?:/>|>.*?</c>)' % (col, r), fx, sx, flags=re.S)
    files[sh['path']] = sx.encode()
st = st[:m.start()] + m.group(1) + str(len(xfs)) + m.group(3) + ''.join(xfs) + m.group(5) + st[m.end():]
files['xl/styles.xml'] = st.encode()

# buang media yang tak dipakai lagi
used = set()
for n, b in files.items():
    if n.endswith('.rels'):
        used |= set('xl/media/' + m for m in re.findall(r'media/([^"]+)"', b.decode('utf8', 'ignore')))
for n in [n for n in files if n.startswith('xl/media/') and n not in used]: del files[n]

# data awal (supaya aplikasi langsung berisi contoh dari minggu ini)
ws = wb['H1']
cfg['school'] = [str(ws['D4'].value), str(ws['D5'].value), str(ws['D6'].value), str(ws['D7'].value)]
cfg['ketua'] = ws['A32'].value; cfg['pengawas'] = ws['I32'].value
cfg['tools'] = sorted({str(w.cell(r, 6).value).strip() for w in wb for r in range(10, 17) if w.cell(r, 6).value})
cfg['materials'] = sorted({str(w.cell(r, c).value).strip() for w in wb for r, c in [(r, 9) for r in range(10, 20)] + [(r, 13) for r in range(10, 14)] if w.cell(r, c).value})
for s in cfg['sheets']:                       # label unik + fallback
    cnt = collections.Counter(x['label'] for x in s['slots']); seen = collections.Counter()
    for x in s['slots']:
        if x['label'].startswith('Foto baris'): x['label'] = f"Foto tambahan (baris {x['row']})"
        elif cnt[x['label']] > 1:
            seen[x['label']] += 1; x['label'] += f" – foto {seen[x['label']]}"

# template.xlsx: zip dengan [Content_Types].xml paling depan
with zipfile.ZipFile(out_xlsx, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('[Content_Types].xml', files.pop('[Content_Types].xml'))
    for n, b in files.items(): z.writestr(n, b)
json.dump(cfg, open(out_cfg, 'w'), ensure_ascii=False, indent=1)
print({s['name']: (len(s['slots']), s['pages']) for s in cfg['sheets']})
