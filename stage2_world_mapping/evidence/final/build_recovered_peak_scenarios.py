#!/usr/bin/env python3
"""Make RTL vectors from the restored Exp03 three-frame pixel-event artifact."""
from pathlib import Path
import csv, hashlib, json, sys
import numpy as np

ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'verification/system'))
from gen_system_vectors import load_codex
CameraConfig,FixedT32Mapper,make_grid,ray2addr,Pose=load_codex(ROOT/'codex')
cfg=CameraConfig(fx=800,fy=800)
grid=make_grid(cfg,Pose(0.0,0.0),15,16)
seqdir=ROOT/'final_evidence/peak_sequence'
npz=np.load(seqdir/'decoded_three_frames.npz')
data={k:npz[k] for k in ('frame','t_us','x','y','p','word','slot')}
sequence_data=data
sel=json.loads((ROOT/'final_evidence/real_data_summary/peak_selection.json').read_text())['event_rate_peak']
count_peak=json.loads((ROOT/'final_evidence/real_data_summary/peak_selection.json').read_text())['event_count_peak']
frame_ids=[sel['frame_index']-1,sel['frame_index'],sel['frame_index']+1]
source=ROOT/'real_data'/sel['recording']
source_hash=hashlib.sha256(source.read_bytes()).hexdigest()

def native_words(frame):
    ix=np.flatnonzero(data['frame']==frame)
    # Source decoder outputs each word's events in exact source-word/slot/LSB order.
    ix=ix[np.argsort(data['word'][ix],kind='stable')]
    out=[]; raw_rows=[]
    for j in ix:
        w=int(data['word'][j])
        if out and out[-1]['source_word']==w:
            e=out[-1]
        else:
            e={'source_word':w,'x':int(data['x'][j]),'ga':None,'gb':None}
            out.append(e)
        slot='ga' if int(data['slot'][j])==0 else 'gb'
        group=int(data['y'][j])>>3; bit=int(data['y'][j])&7; pol=int(data['p'][j])
        if e[slot] is None: e[slot]=[group,0,pol]
        assert e[slot][0]==group and e[slot][2]==pol
        e[slot][1] |= 1<<bit
    for e in out:
        raw_rows.append({'frame_index':frame,'source_event_word_index':e['source_word'],'x':e['x'],
          'group_a': '' if e['ga'] is None else e['ga'][0],
          'mask_a_hex':'' if e['ga'] is None else f"{e['ga'][1]:02x}",
          'polarity_a':'' if e['ga'] is None else e['ga'][2],
          'group_b':'' if e['gb'] is None else e['gb'][0],
          'mask_b_hex':'' if e['gb'] is None else f"{e['gb'][1]:02x}",
          'polarity_b':'' if e['gb'] is None else e['gb'][2]})
    return out,raw_rows

def wordpack(e, frame=0):
    v=(frame&255)<<44 | (e['x']&0x3ff)<<34
    for g,flag,shift in ((e['ga'],1,17),(e['gb'],1,0)):
        if g is None: continue
        if shift==17: v|=1<<33|(g[0]&0x7f)<<26|(g[1]&255)<<18|(g[2]&1)<<17
        else: v|=1<<16|(g[0]&0x7f)<<9|(g[1]&255)<<1|(g[2]&1)
    return v

def write_scenario(path, frames, scheduled=False):
    path.mkdir(parents=True,exist_ok=True)
    all_words=[]; wordrows=[]; schedule=[]; event_total=0
    for f in frames:
        ws,rows=native_words(f); all_words.extend(ws); wordrows.extend(rows)
        n_events=sum((bin(g[1]).count('1') if g else 0) for e in ws for g in (e['ga'],e['gb']))
        event_total+=n_events
        interval=int(next((r['frame_interval_us'] for r in csv.DictReader(open(ROOT/'final_evidence/real_data_summary/sept22_frame_stats.csv'))
                           if r['recording']==sel['recording'] and int(r['frame_index'])==f),'' ) or 0)
        schedule.append({'frame_index':f,'native_words':len(ws),'events':n_events,
                         'frame_interval_us':interval,'duration_cycles':interval*100})
    if not scheduled:
        all_words=[(f,w) for f in frames for w in native_words(f)[0]]
    with (path/'frames.txt').open('w') as f: f.write('0 0\n')
    with (path/'grids.hex').open('w') as f:
        for gy in range(24):
            for gx in range(31):
                x,y,z=(int(v)&0xffff for v in grid.nodes[gy,gx]); f.write(f'{(x<<32)|(y<<16)|z:012x}\n')
    with (path/'words.hex').open('w') as f:
        for item in all_words:
            if scheduled: w=item
            else: _,w=item
            f.write(f'{wordpack(w,0):013x}\n')
    expect={'words':len(all_words),'events':event_total,'dropped':0,'elite_records':0,'elite_merged':0,
            'd2_records':0,'sat_loss':-1,'issue_cycles':0,'frames':1}
    with (path/'expect.txt').open('w') as f:
        for k,v in expect.items(): f.write(f'{k}={v}\n')
    (path/'schedule.csv').write_text('frame_index,native_words,events,frame_interval_us,duration_cycles\n'+''.join(
        f"{r['frame_index']},{r['native_words']},{r['events']},{r['frame_interval_us']},{r['duration_cycles']}\n" for r in schedule))
    (path/'schedule.txt').write_text(''.join(f"{r['native_words']} {r['duration_cycles']}\n" for r in schedule))
    (path/'provenance.txt').write_text(
        f"source={source}\nsource_sha256={source_hash}\nframes={frames}\n"
        "pose_convention=synthetic/identity architectural T32 grid (fx=fy=800); not pose ground truth\n"
        "ordering=restored Exp03 source event-word index; slot A then B; LSB-first pixel order; polarity preserved\n"
        "native words=event words with at least one in-range decoded pixel contribution\n")
    return wordrows

single=ROOT/'final_evidence/peak_frame/recovered_peak_rate'
single.mkdir(parents=True,exist_ok=True)
write_scenario(single,[frame_ids[1]])
count_dir=ROOT/'final_evidence/peak_frame/recovered_peak_count'
count_dir.mkdir(parents=True,exist_ok=True)
count_npz=np.load(ROOT/'final_evidence/peak_frame/decoded_count_peak.npz')
data={k:count_npz[k] for k in ('frame','t_us','x','y','p','word','slot')}
count_rows=write_scenario(count_dir,[int(count_peak['frame_index'])])
with (count_dir/'native_words.csv').open('w',newline='') as f:
    wr=csv.DictWriter(f,fieldnames=list(count_rows[0]));wr.writeheader();wr.writerows(count_rows)
data=sequence_data
seq=ROOT/'final_evidence/peak_sequence/rtl_vectors'
rows=write_scenario(seq,frame_ids,scheduled=True)
with (seq/'native_words.csv').open('w',newline='') as f:
    wr=csv.DictWriter(f,fieldnames=list(rows[0]));wr.writeheader();wr.writerows(rows)
print('peak_frame',frame_ids[1],'schedule',[(r['native_words'],r['events'],r['frame_interval_us']) for r in csv.DictReader(open(seq/'schedule.csv'))])
