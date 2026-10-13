# Sanity calculation only (Claude architecture workspace). Ideal pinhole, assumed half-FOV; fx is NOT known.
# Not an implementation and not a substitute for Codex experiments. Run: python3 -I pwl_power_of_two_segments.py
import numpy as np
W,H=960,720
print("PWL over |dx| in [0,480), power-of-two segment width S; errors in centre px; chord vs minimax(shifted)")
print("alpha(x)=fx*atan(dx/fx); c(x)=1/sqrt(1+(dx/fx)^2), error in h = 360*dc px (worst row)")
for th in [20,30,40]:
    fx=(W/2)/np.tan(np.radians(th)); dx=np.arange(0,480)+0.5
    a=fx*np.arctan(dx/fx); c=1/np.sqrt(1+(dx/fx)**2)
    row=[f"th{th}:"]
    for S in [128,64,32,16]:
        seg=(dx//S).astype(int); ea=0;ec=0;eam=0;ecm=0
        for s in np.unique(seg):
            m=seg==s; x0=s*S; x1=x0+S
            for f,name in [(lambda z: fx*np.arctan(z/fx),'a'),(lambda z: 1/np.sqrt(1+(z/fx)**2),'c')]:
                y0,y1=f(x0),f(x1); lin=y0+(y1-y0)*(dx[m]-x0)/S; e=f(dx[m])-lin
                emm=(e.max()-e.min())/2
                if name=='a': ea=max(ea,np.abs(e).max()); eam=max(eam,emm)
                else: ec=max(ec,np.abs(e).max()*360); ecm=max(ecm,emm*360)
        n=int(np.ceil(480/S))
        row.append(f"S{S}(K/2={n}): a {ea:.3f}/{eam:.3f} c {ec:.3f}/{ecm:.3f}")
    print(" ".join(row))
print("slope ranges: d alpha/dx = 1/(1+u^2) in [cos^2 th,1]")
for th in [30,40]: print(th, np.cos(np.radians(th))**2)
