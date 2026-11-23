from pathlib import Path
import json,sys,hashlib
import pypdfium2 as pdf
from PIL import Image,ImageDraw
from pypdf import PdfReader
r=Path(__file__).parent;p=r/'04_PAPER_A.pdf';doc=pdf.PdfDocument(str(p));reader=PdfReader(str(p)); pages=[]
for i,page in enumerate(doc):
 im=page.render(scale=0.78).to_pil().convert('RGB');pages.append(im.copy());print('Page',i+1,(reader.pages[i].extract_text() or '').splitlines()[0][:100])
w,h=pages[0].size; montage=Image.new('RGB',(w*3,(h+22)*((len(pages)+2)//3)),(226,226,226));d=ImageDraw.Draw(montage)
for i,im in enumerate(pages):
 x=i%3*w;y=i//3*(h+22);montage.paste(im,(x,y));d.text((x+4,y+h+3),str(i+1),fill='black')
out=r/'05_REVIEW_PDF_CONTACT.png';montage.save(out);print('PDF SHA',hashlib.sha256(p.read_bytes()).hexdigest(),len(doc))

