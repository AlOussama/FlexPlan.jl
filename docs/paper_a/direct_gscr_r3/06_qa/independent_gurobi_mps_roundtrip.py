"""Independent Gurobi MPS binary64 roundtrip. Calls no optimizer."""
if not __debug__:raise RuntimeError('Assertion checks required')
import ctypes as C,hashlib,json,pathlib,sys
import numpy as np
folder=pathlib.Path(sys.argv[1]);out=pathlib.Path(sys.argv[2]);root=next(p for p in folder.parents if (p/'04_reproducibility').is_dir())
libs=json.loads((root/'04_reproducibility/SOLVER_LIBRARY_HASHES.json').read_text(encoding='utf-8-sig'))
libpath=next(x['path'] for x in libs if pathlib.Path(x['path']).name.lower()=='gurobi130.dll')
lib=C.WinDLL(libpath);env=C.c_void_p();model=C.c_void_p()
def call(name,*args):
    code=getattr(lib,name)(*args)
    if code:raise RuntimeError((name,code))
def integer(attr):
    a=C.c_int();call('GRBgetintattr',model,attr.encode(),C.byref(a));return a.value
def array(attr,n):
    a=np.empty(n,dtype=np.float64);call('GRBgetdblattrarray',model,attr.encode(),0,n,C.c_void_p(a.ctypes.data));return a
def chars(attr,n):
    a=(C.c_char*n)();call('GRBgetcharattrarray',model,attr.encode(),0,n,a);return [x.decode() for x in a]
def names(attr,n):
    a=(C.c_char_p*n)();call('GRBgetstrattrarray',model,attr.encode(),0,n,a);return [x.decode() for x in a]
def identity_names(attr,n,prefix):
    values=names(attr,n)
    if all(v.startswith(prefix) and v[len(prefix):].isdigit() for v in values):
        mapping=[int(v[len(prefix):]) for v in values]
        assert set(mapping)==set(range(n))
        return mapping,'persisted_native_index_names'
    return list(range(n)),'position_preserved_small_named_fixture'
def sparse(cols,vals):
    d={}
    for c,v in zip(cols,vals):
        if float(v):
            assert int(c) not in d
            d[int(c)]=float(v)
    return d
def sha(p):return hashlib.file_digest(open(p,'rb'),'sha256').hexdigest()
rawpath=folder/'g3_actual_native_readback.json';raw=json.loads(rawpath.read_text(encoding='utf-8-sig'))
assert raw['backend']=='Gurobi_actual_C_API'
call('GRBemptyenv',C.byref(env));call('GRBsetintparam',env,b'OutputFlag',0);call('GRBstartenv',env)
try:
    call('GRBreadmodel',env,str(folder/'g3_actual_native.mps').encode(),C.byref(model))
    nv,nr,nq=integer('NumVars'),integer('NumConstrs'),integer('NumQConstrs')
    assert nv==len(raw['lower_bounds']) and nr==len(raw['linear_rows']) and nq==len(raw['quadratic_rows'])
    colmap,colmethod=identity_names('VarName',nv,'C')
    rowmap,rowmethod=identity_names('ConstrName',nr,'R')
    qcmap,qcmethod=identity_names('QCName',nq,'qc')
    inversecols=np.argsort(np.array(colmap));inverserows=np.argsort(np.array(rowmap));inverseq=np.argsort(np.array(qcmap))
    assert np.array_equal(array('LB',nv)[inversecols],np.array(raw['lower_bounds']))
    assert np.array_equal(array('UB',nv)[inversecols],np.array(raw['upper_bounds']))
    nz=C.c_int();call('GRBgetconstrs',model,C.byref(nz),None,None,None,0,nr)
    starts=np.empty(nr,dtype=np.int32);cols=np.empty(nz.value,dtype=np.int32);vals=np.empty(nz.value)
    call('GRBgetconstrs',model,C.byref(nz),C.c_void_p(starts.ctypes.data),C.c_void_p(cols.ctypes.data),C.c_void_p(vals.ctypes.data),0,nr)
    rhs=array('RHS',nr);sense=chars('Sense',nr);count=0
    for row in raw['linear_rows']:
        r=int(inverserows[row['index_zero_based']]);end=starts[r+1] if r+1<nr else nz.value
        actual=sparse([colmap[c] for c in cols[starts[r]:end]],vals[starts[r]:end]);expected=sparse(row['columns_zero_based'],row['coefficients'])
        assert actual==expected,('linear coefficients',r)
        assert float(rhs[r])==float(row['rhs']),('linear RHS',r,float(rhs[r]),row['rhs'])
        assert sense[r]==row['sense'];count+=len(actual)
    qrhs=array('QCRHS',nq);qsense=chars('QCSense',nq);qcount=0
    for row in raw['quadratic_rows']:
        r=int(inverseq[row['index_zero_based']]);nl=C.c_int();nn=C.c_int()
        call('GRBgetqconstr',model,r,C.byref(nl),None,None,C.byref(nn),None,None,None)
        li=np.empty(nl.value,dtype=np.int32);lv=np.empty(nl.value);ii=np.empty(nn.value,dtype=np.int32);jj=np.empty(nn.value,dtype=np.int32);vv=np.empty(nn.value)
        call('GRBgetqconstr',model,r,C.byref(nl),C.c_void_p(li.ctypes.data),C.c_void_p(lv.ctypes.data),C.byref(nn),C.c_void_p(ii.ctypes.data),C.c_void_p(jj.ctypes.data),C.c_void_p(vv.ctypes.data))
        assert sparse([colmap[c] for c in li],lv)==sparse(row['linear_columns_zero_based'],row['linear_coefficients']),('QC linear',r)
        actual={(min(colmap[int(i)],colmap[int(j)]),max(colmap[int(i)],colmap[int(j)])):float(v) for i,j,v in zip(ii,jj,vv) if v}
        expected={(min(i,j),max(i,j)):float(v) for i,j,v in zip(row['quadratic_i_zero_based'],row['quadratic_j_zero_based'],row['quadratic_coefficients']) if v}
        assert actual==expected,('QC polynomial',r)
        assert float(qrhs[r])==float(row['rhs']) and qsense[r]==row['sense'],('QC bound',r)
        qcount+=len(actual)
    report={'status':'PASS','scope':'Entire saved MPS constraint matrix, RHS, senses, variable bounds and quadratic rows equal live native C-API JSON exactly as binary64; includes all G3 coordinates/node budgets/q bounds','optimization_called':False,'column_mapping':colmethod,'linear_row_mapping':rowmethod,'quadratic_row_mapping':qcmethod,'variables':nv,'linear_rows':nr,'linear_nonzero_coefficients':count,'quadratic_rows':nq,'quadratic_nonzero_coefficients':qcount,'mps_sha256':sha(folder/'g3_actual_native.mps'),'raw_readback_sha256':sha(rawpath),'gurobi_library_sha256':sha(pathlib.Path(libpath)),'qa_program_sha256':sha(pathlib.Path(__file__))}
    out.write_text(json.dumps(report,indent=2)+'\n',encoding='utf-8');print(folder.name,'MPS exact roundtrip PASS',nv,nr,nq)
finally:
    if model.value:lib.GRBfreemodel(model)
    if env.value:lib.GRBfreeenv(env)
