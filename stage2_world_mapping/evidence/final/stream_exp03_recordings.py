#!/usr/bin/env python3
"""Bounded-memory chunk adapter around the restored Exp03 dvs_decode.decode().

The word decoding/output expansion is performed by the restored decoder.  Each
chunk is prefixed with synthetic column/time context words representing the
decoder's carried parser state; frame and source-word indexes are rebased.
This keeps its implementation and event ordering authoritative while bounding
the working set to one chunk.  Pass 1 writes frame statistics; pass 2 extracts
only the selected three-frame sequence.
"""
from __future__ import annotations
import csv, importlib.util, json, pathlib, sys
import numpy as np

ROOT = pathlib.Path(__file__).resolve().parents[1]
TOOLS = ROOT / "exp03_tools"
spec = importlib.util.spec_from_file_location("restored_dvs_decode", TOOLS / "dvs_decode.py")
decoder = importlib.util.module_from_spec(spec); spec.loader.exec_module(decoder)
CHUNK_WORDS = 1_000_000

def unpack_state(words, state):
    b0,b1,b2,b3=(words[:,i].astype(np.int32) for i in range(4))
    typ=np.where(b0>=0x80,-1,b0 & 0x7c)
    is_col=typ==4
    if is_col.any():
        i=np.flatnonzero(is_col)[-1]
        state['col']=int(((b2[i]&7)<<8)|b3[i]); state['flag']=int(b1[i]>>7)
    is_hi=(typ==8)&((b1&0x80)==0)
    idx=np.arange(len(words))
    vpos=np.maximum.accumulate(np.where(is_hi,idx,-1))
    v_at=np.full(len(words),state['V'] if state['V'] is not None else -1,dtype=np.int64)
    hasv=vpos>=0
    if hasv.any():
        vals=np.where(is_hi,((b1&0x3f)<<16)|(b2<<8)|b3,0)
        v_at[hasv]=vals[vpos[hasv]]
    if is_hi.any():
        i=np.flatnonzero(is_hi)[-1]
        state['V']=int(((b1[i]&0x3f)<<16)|(b2[i]<<8)|b3[i])
    is_lo=(typ==8)&((b1&0x80)!=0)
    validlo=is_lo&(v_at>=0)
    if validlo.any():
        i=np.flatnonzero(validlo)[-1]
        F=int(((b2[i]&3)<<8)|b3[i])
        state['t']=int(v_at[i])*1000+F
        state['tV']=int(v_at[i])
    if is_hi.any():
        i=np.flatnonzero(is_hi)[-1]
        state['V']=int(((b1[i]&0x3f)<<16)|(b2[i]<<8)|b3[i])
    state['frames'] += int((typ==0x0c).sum())

def context_bytes(state):
    a=[]
    if state['col'] is not None:
        col=state['col']; flag=state['flag'] or 0
        a.extend([4,flag<<7,(col>>8)&7,col&255])
    if state['t'] is not None and state['tV'] is not None:
        v=state['tV']; f=state['t']-v*1000
        a.extend([8,(v>>16)&0x3f,(v>>8)&255,v&255])
        a.extend([8,0x80,(f>>8)&3,f&255])
    if state['V'] is not None and state['V'] != state['tV']:
        v=state['V']
        a.extend([8,(v>>16)&0x3f,(v>>8)&255,v&255])
    return bytes(a)

def chunks(path):
    state={'col':None,'flag':0,'V':None,'t':None,'tV':None,'frames':0}
    offset=0
    with open(path,'rb') as f:
        while True:
            raw=f.read(CHUNK_WORDS*4)
            if not raw: break
            words=np.frombuffer(raw,dtype=np.uint8).reshape(-1,4)
            frame_base=state['frames']
            prefix=context_bytes(state)
            with __import__('tempfile').NamedTemporaryFile(suffix='.dvs') as tmp:
                tmp.write(prefix); tmp.write(raw); tmp.flush()
                res,meta,extra=decoder.decode(tmp.name)
            npre=len(prefix)//4
            # Rebase frame IDs and original absolute word indexes.
            res['frame'] += state['frames']
            res['word'] += offset-npre
            unpack_state(words,state)
            yield offset, len(words), res, meta, extra, frame_base
            offset += len(words)

def stats_one(path, csvpath):
    counts={}; nativecounts={}; first_ts={}; boundary_ts={}; metadata={}
    for off,n,res,meta,extra,frame_base in chunks(path):
        metadata={k:metadata.get(k,0)+v for k,v in meta.items()}
        for j,t in enumerate(extra['frame_end_t_us_after']):
            if int(t)>=0: boundary_ts[frame_base+j+1]=int(t)
        if len(res['x']):
            fr=res['frame']; ts=res['t_us']; wd=res['word']
            u,c=np.unique(fr,return_counts=True)
            for f,v in zip(u,c): counts[int(f)]=counts.get(int(f),0)+int(v)
            # Unique (frame, source event-word) pairs; the two bit-mask groups
            # remain grouped as one native word.
            pair=np.unique(fr.astype(np.int64)*(off+n+1)+wd.astype(np.int64))
            pf=pair//(off+n+1)
            u,c=np.unique(pf,return_counts=True)
            for f,v in zip(u,c): nativecounts[int(f)]=nativecounts.get(int(f),0)+int(v)
            valid=ts>=0
            if valid.any():
                vf=fr[valid]; vt=ts[valid]
                u,ix=np.unique(vf,return_index=True)
                for f,t in zip(u,vt[ix]):
                    if int(f) not in first_ts: first_ts[int(f)]=int(t)
        print(f"{pathlib.Path(path).name}: decoded through word {off+n:,}",flush=True)
    ids=range(int(metadata.get('n_frame_end',0))+1)
    intervals={}
    for f,t in boundary_ts.items():
        if f+1 in boundary_ts: intervals[f]=boundary_ts[f+1]-t
    rows=[]
    for f in ids:
        dt=intervals.get(f)
        cnt=counts.get(f,0)
        rows.append({'recording':pathlib.Path(path).name,'frame_index':f,
          'event_count':cnt,'native_word_count':nativecounts.get(f,0),
          'frame_start_t_us':boundary_ts.get(f,''),'frame_interval_us':dt if dt is not None else '',
          'event_rate_per_s':(cnt*1e6/dt if dt and dt>0 else '')})
    with open(csvpath,'a',newline='') as f:
        wr=csv.DictWriter(f,fieldnames=list(rows[0]) if rows else ['recording','frame_index','event_count','native_word_count','frame_start_t_us','frame_interval_us','event_rate_per_s'])
        for r in rows: wr.writerow(r)
    return rows,metadata

def extract(path, frames, out_npz):
    parts={k:[] for k in ('frame','t_us','x','y','p','word','slot')}
    frame_values=np.asarray(sorted(frames),dtype=np.int32)
    for off,n,res,meta,extra,frame_base in chunks(path):
        mask=np.isin(res['frame'],frame_values)
        for k in parts: parts[k].append(res[k][mask])
    out={k:(np.concatenate(v) if v else np.empty(0)) for k,v in parts.items()}
    np.savez_compressed(out_npz,**out)

if __name__=='__main__':
    outdir=ROOT/'final_evidence/real_data_summary'; outdir.mkdir(parents=True,exist_ok=True)
    csvp=outdir/'sept22_frame_stats.csv'
    csvp.write_text('recording,frame_index,event_count,native_word_count,frame_start_t_us,frame_interval_us,event_rate_per_s\n')
    allrows=[]
    for p in map(pathlib.Path,sys.argv[1:]):
        rows,meta=stats_one(p,csvp); allrows.extend(rows)
        (outdir/(p.stem+'_decode_meta.json')).write_text(json.dumps(meta,indent=2)+'\n')
        print(p.name,'frames',len(rows),'events',sum(r['event_count'] for r in rows),'metadata',meta,flush=True)
    valid=[r for r in allrows if r['event_rate_per_s']!='']
    pcount=max(allrows,key=lambda r:r['event_count'])
    prate=max(valid,key=lambda r:r['event_rate_per_s'])
    print('PEAK_COUNT',pcount); print('PEAK_RATE',prate)
    (outdir/'peak_selection.json').write_text(json.dumps({'event_count_peak':pcount,'event_rate_peak':prate},indent=2)+'\n')
    peak=prate
    pp=ROOT/'real_data'/peak['recording']
    seqdir=ROOT/'final_evidence/peak_sequence'; seqdir.mkdir(parents=True,exist_ok=True)
    extract(pp,{peak['frame_index']-1,peak['frame_index'],peak['frame_index']+1},seqdir/'decoded_three_frames.npz')
    countdir=ROOT/'final_evidence/peak_frame'; countdir.mkdir(parents=True,exist_ok=True)
    count=pcount
    extract(ROOT/'real_data'/count['recording'],{count['frame_index']},countdir/'decoded_count_peak.npz')
