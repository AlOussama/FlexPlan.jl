"""Rebuild in memory; compare PDF and TeX bytes against the actual publication files."""
import matplotlib.pyplot as plt
from matplotlib.figure import Figure
import matplotlib, numpy as np
from pathlib import Path
import io,hashlib,json,sys,runpy
from unittest.mock import patch
R=Path(__file__).parent
save=Figure.savefig;rows={}
def check_fig(self,path,*a,**kw):
 mem=io.BytesIO();save(self,mem,*a,**kw);file=Path(path)
 incoming=hashlib.sha256(mem.getvalue()).hexdigest();original=hashlib.sha256(file.read_bytes()).hexdigest()
 rows[file.name]={'kind':'PDF','generated':incoming,'original':original,'identical':incoming==original}
def check_tex(self,data,*a,**kw):
 original=self.read_text(encoding='utf8')
 rows[self.name]={'kind':'TeX','identical':original==data,'original':hashlib.sha256(self.read_bytes()).hexdigest()}
 return len(data)
with patch.object(Figure,'savefig',check_fig),patch.object(Path,'write_text',check_tex):
 runpy.run_path(str(R/'04_build_results.py'),run_name='__main__')
print(json.dumps(rows,indent=2));assert len(rows)>=8 and all(x['identical'] for x in rows.values())
(R/'05_IN_MEMORY_FIGURE_AND_TABLE_REPLAY.json').write_text(json.dumps({'reviewer':'/root/math_r','executed':[sys.executable,str(Path(__file__))],'matplotlib':matplotlib.__version__,'numpy':np.__version__,'inspection':rows,'exit':0},indent=2))

