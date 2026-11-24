"""Render and independently compare every committed and freshly rebuilt page."""
from pathlib import Path
import sys,json,hashlib,re
import pypdfium2 as pdfium
from PIL import Image,ImageChops
from pypdf import PdfReader
def H(p):return hashlib.sha256(p.read_bytes()).hexdigest()
def main(a,b,d):
    d.mkdir(exist_ok=True,parents=True);orig=pdfium.PdfDocument(str(a));fresh=pdfium.PdfDocument(str(b));assert len(orig)==len(fresh)>0
    info=[]
    for i in range(len(orig)):
        origpg,freshpg=orig[i],fresh[i]
        left=origpg.render(scale=1.65).to_pil().convert('RGB');right=freshpg.render(scale=1.65).to_pil().convert('RGB')
        lt,rt=[pg.get_textpage().get_text_bounded() for pg in [origpg,freshpg]]
        assert lt==rt and len(lt)>40 and '??' not in lt and '\ufffd' not in lt
        target=d/f'page-{i+1:02}.png';left.save(target)
        (d/f'page-{i+1:02}.txt').write_text(lt,encoding='utf8')
        diff=ImageChops.difference(left,right);assert not diff.getbbox(),(i,diff.getbbox())
        info.append(dict(page=i+1,render_sha256=H(target),text_sha256=hashlib.sha256(lt.encode()).hexdigest(),pixels=left.size,visible_chars=len(lt),first_line=lt.splitlines()[0],fresh_pixelwise_equal=True))
    for idx in range(0,len(info),2):
        sheet=Image.new('RGB',(1400,990),'#ccc')
        for i in range(idx,min(idx+2,len(info))):
            im=Image.open(d/f'page-{i+1:02}.png');im.thumbnail((695,980));sheet.paste(im,((i-idx)*700,0))
        sheet.save(d/f'spread-{idx+1:02}.jpg',quality=90)
    # Embedded fonts actually present; do not mistake unembedded base fonts for success.
    pgreader=PdfReader(a);fonts={}
    for pg in pgreader.pages:
        for k,v in (pg['/Resources'].get('/Font') or {}).get_object().items():
            v=v.get_object();z=v.get('/DescendantFonts');font=z[0].get_object() if z else v; desc=font.get('/FontDescriptor')
            if desc: desc=desc.get_object();fonts[str(v.get('/BaseFont'))]=any(k in desc for k in ['/FontFile','/FontFile2','/FontFile3'])
    assert fonts and all(fonts.values()),fonts
    (d/'pages.json').write_text(json.dumps({'committed_pdf':H(a),'rebuilt_pdf':H(b),'pages':info,'fonts_embedded':fonts},indent=2))
if __name__=='__main__':main(*map(Path,sys.argv[1:]))