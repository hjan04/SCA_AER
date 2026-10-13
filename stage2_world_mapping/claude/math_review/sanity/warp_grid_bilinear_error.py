# Sanity calculation only (Claude architecture workspace). Ideal pinhole, assumed half-FOV; fx is NOT known.
# Not an implementation and not a substitute for Codex experiments. Run: python3 -I warp_grid_bilinear_error.py
import numpy as np
W,H=960,720
def R(yaw,pitch,roll):
    y,p,r=np.radians([yaw,pitch,roll])
    Ry=np.array([[np.cos(y),0,np.sin(y)],[0,1,0],[-np.sin(y),0,np.cos(y)]])
    Rx=np.array([[1,0,0],[0,np.cos(p),-np.sin(p)],[0,np.sin(p),np.cos(p)]])
    Rz=np.array([[np.cos(r),-np.sin(r),0],[np.sin(r),np.cos(r),0],[0,0,1]])
    return Ry@Rx@Rz
def world(xs,ys,fx,Rm,kind):
    u=(xs-W/2)/fx; v=(ys-H/2)/fx
    d=np.stack([u,v,np.ones_like(u)],-1)@Rm.T
    az=np.arctan2(d[...,0],d[...,2])
    rho=np.hypot(d[...,0],d[...,2])
    second=np.arctan2(d[...,1],rho) if kind=="equirect" else d[...,1]/rho
    return az,second
print("bilinear warp-grid error (max, in world cells of 1/fx rad; tile T px)")
for th in [30,40]:
    fx=(W/2)/np.tan(np.radians(th))
    ys,xs=np.mgrid[0:H:3,0:W:3].astype(float)+0.5
    for kind in ["equirect","cylinder"]:
        for rot in [(0,0,0),(37,0,0),(37,20,0),(37,20,15),(10,60,0)]:
            Rm=R(*rot); az,el=world(xs,ys,fx,Rm,kind)
            out=[]
            for T in [16,32,64,120]:
                gx=np.arange(0,W+T,T).astype(float); gy=np.arange(0,H+T,T).astype(float)
                GX,GY=np.meshgrid(gx,gy); gaz,gel=world(GX,GY,fx,Rm,kind)
                gaz=np.unwrap(gaz,axis=1); gaz=np.unwrap(gaz,axis=0)
                ix=np.minimum((xs//T).astype(int),len(gx)-2); iy=np.minimum((ys//T).astype(int),len(gy)-2)
                fxr=(xs-gx[ix])/T; fyr=(ys-gy[iy])/T
                def bil(g): return (g[iy,ix]*(1-fxr)*(1-fyr)+g[iy,ix+1]*fxr*(1-fyr)+g[iy+1,ix]*(1-fxr)*fyr+g[iy+1,ix+1]*fxr*fyr)
                eaz=np.angle(np.exp(1j*(bil(gaz)-az)))
                esec=bil(gel)-el
                # cell size: az cell 1/fx rad; second coordinate: equirect 1/fx rad, cylinder 1/fx (tan units)
                eaz_c=np.abs(eaz)*fx*np.cos(0) ; e2=np.abs(esec)*fx
                out.append(f"T{T}: az {eaz_c.max():.2f} 2nd {e2.max():.2f}")
            print(f"th{th} {kind:8s} rot{rot}: "+" | ".join(out))
