#!/usr/bin/env python3
import csv, math, random, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
sys.path.insert(0,str(ROOT/'codex'))
from model.ray_address import (TAN_Q32,TAN2_Q32,ray_q15_to_world_address_direct)
source=ROOT/'codex/results/exp05b/rtl_address_vectors.csv'
out=Path(__file__).resolve().parent/'direct_vectors.hex'
rng=random.Random(0xE05B003)
rays=[]
with source.open(newline='') as f:
 for r in csv.DictReader(f): rays.append(tuple(int(r[k]) for k in ('ray_x_q15','ray_y_q15','ray_z_q15')))
# For every rounded threshold find closest realizable Q1.15 ratio around its edge,
# retain adjacent integer codes, and replicate across signs/quadrants.
def closest_linear(t):
 best=[]
 for hi in range(1,32769):
  num=hi*t
  lo=min(hi, max(1,(num+(1<<31))>>32))
  for l in (lo-1,lo,lo+1):
   if 1<=l<=hi:
    best.append((abs((l<<32)-num),l,hi))
 _,lo,hi=min(best)
 return lo,hi
for t in TAN_Q32:
 lo,hi=closest_linear(t)
 for a,b in ((lo,hi),(hi,lo)):
  for da in (-1,0,1):
   aa=max(0,min(32768,a+da))
   for sx in (0,1):
    for sz in (0,1): rays.append(((-aa if sx else aa),0,(-b if sz else b)))
# Vertical thresholds: x=0,z=r makes sqrt(r2)=abs(z), yielding the exact squared-ratio test.
def closest_vertical(t):
 best=None
 for rad in range(1,32769):
  val=rad*math.sqrt(t/(1<<32))
  y0=int(val)
  for yy in (y0-1,y0,y0+1,y0+2):
   if 1<=yy<=32768:
    err=abs((yy*yy<<32)-rad*rad*t)
    if best is None or err<best[0]: best=(err,yy,rad)
 return best[1],best[2]
for t in TAN2_Q32:
 y0,rad=closest_vertical(t)
 for yy in (y0-1,y0,y0+1):
  if yy>0:
   for sy in (0,1):
    for sz in (0,1): rays.append((0,-yy if sy else yy,-rad if sz else rad))
# Additional axes, quadrant, wrap, near-zero and nonzero near-zero-z/x/y vectors.
rays += [(x,y,z) for x,y,z in [(0,1,32767),(0,-1,32767),(1,0,32767),(-1,0,32767),
 (32767,0,1),(-32768,1,-32768),(1,32767,0),(1,-32768,0),(0,32767,0),(0,-32768,0)]]
# Additional random full-range nonzero Q1.15 rays.
for _ in range(10000):
 q=tuple(rng.randint(-32768,32767) for _ in range(3))
 if q!=(0,0,0): rays.append(q)
# Deduplicate while preserving all data categories and original vector order.
seen=set(); uniq=[]
for ray in rays:
 if ray not in seen: seen.add(ray); uniq.append(ray)
if len(uniq)>50000: raise SystemExit(f'too many vectors for testbench: {len(uniq)}')
mis=[]; maxdx=maxdy=0
with out.open('w') as f:
 for x,y,z in uniq:
  result=ray_q15_to_world_address_direct(x,y,z)
  # packed x/y/z then output address for cycle-accurate RTL comparison
  f.write(f'{((x&0xffff)<<47)|((y&0xffff)<<31)|((z&0xffff)<<15)|result.world_addr:016x}\n')
print(f'Verification rays: {len(uniq)} (Exp05b={len(list(csv.DictReader(source.open(newline=""))))}; boundary/axis/random supplements included)')
