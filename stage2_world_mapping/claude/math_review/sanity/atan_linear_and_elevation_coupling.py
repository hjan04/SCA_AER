# Sanity calculation only (Claude architecture workspace). Ideal pinhole, assumed half-FOV; fx is NOT known.
# Not an implementation and not a substitute for Codex experiments. Run: python3 -I atan_linear_and_elevation_coupling.py
import numpy as np
W,H=960,720
print("== atan approximations; error in 'center pixels' = err_rad*fx ==")
for th in [20,30,40,50]:
    fx=(W/2)/np.tan(np.radians(th))
    x=np.arange(W)+0.5-W/2
    u=x/fx; t=np.arctan(u)
    # global linear through endpoints (chord) and least-max (center tangent)
    lin_c=u*(np.arctan(u[-1])/u[-1]); lin_t=u
    e1=np.max(np.abs(t-lin_c))*fx; e2=np.max(np.abs(t-lin_t))*fx
    row=[f"th_h={th} fx={fx:.0f} 1px@ctr={np.degrees(1/fx):.4f}deg | chordLin {e1:.1f}px tangentLin {e2:.1f}px"]
    for K in [2,4,8,16,32]:
        # symmetric uniform PWL over |x| with K segments total (K/2 per half), chord interpolation
        Kh=max(K//2,1); xa=np.abs(x); edges=np.linspace(0,W/2,Kh+1)
        te=np.arctan(edges/fx); pw=np.interp(xa,edges,te)
        e=np.max(np.abs(np.arctan(xa/fx)-pw))*fx
        row.append(f"K{K}:{e:.3f}")
    print(" ".join(row))
print("== elevation coupling: atan(v) vs exact atan(v/sqrt(1+u^2)) at corner, in center px ==")
for th in [20,30,40]:
    fx=(W/2)/np.tan(np.radians(th)); u=(W/2)/fx; v=(H/2)/fx
    e=(np.arctan(v)-np.arctan(v/np.sqrt(1+u*u)))*fx
    print(f"th_h={th}: vertical half-FOV={np.degrees(np.arctan(v)):.1f}deg, corner elev error={e:.1f}px")
