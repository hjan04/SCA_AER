import csv,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3];sys.path.insert(0,str(ROOT/'codex'))
from model.ray_address import ray_q15_to_world_address_direct
p=ROOT/'codex/results/exp05b/rtl_address_vectors.csv'
rows=list(csv.DictReader(p.open(newline='')))
mx=my=0; naddr=nx=ny=0;examples=[]
for r in rows:
 x,y,z=(int(r[k]) for k in ('ray_x_q15','ray_y_q15','ray_z_q15'))
 got=ray_q15_to_world_address_direct(x,y,z)
 ex=int(r['expected_world_addr']); gx=int(r['golden_world_x']); gy=int(r['golden_world_y'])
 dx=min((got.world_x-gx)%256,(gx-got.world_x)%256); dy=abs(got.world_y-gy)
 mx=max(mx,dx);my=max(my,dy)
 nx+=got.world_x!=gx; ny+=got.world_y!=gy; naddr+=got.world_addr!=ex
 if got.world_addr!=ex and len(examples)<10: examples.append((r['vector_id'],(x,y,z),got.world_addr,ex,gx,gy))
print(f'Exp05b={len(rows)} address_mismatches={naddr} x_mismatches={nx} y_mismatches={ny} max_x_displacement={mx} max_y_displacement={my}')
print('Examples:',examples)
# Verify RTL vector file carries the independent direct-bin address, not the Exp05b expected address.
