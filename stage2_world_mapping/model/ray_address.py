"""Deterministic Q1.15 ray-to-world/tile/bank reference implementations.

The selected RTL candidate is fixed-point CORDIC vectoring. The direct-bin
threshold candidate is included as a comparison: it returns bins without
forming angles and uses integer cross-products only.
"""
from __future__ import annotations

from dataclasses import dataclass
import math
from typing import Literal

from model.fixed_point import round_shift

WORLD_W=256
WORLD_H=128
TILE_W=TILE_H=4
BANKS=4
CORDIC_ATAN_BAM32=(536870912,316933406,167458907,85004756,42667331,21354465,
 10679838,5340245,2670163,1335087,667544,333772,166886,83443,41722,20861,
 10430,5215,2608,1304,652,326,163,81)
TAN_Q32=(105435529,210998213,316815821,423017356,529733691,637098215,745247522,854322113,
 964467159,1075833302,1188577525,1302864085,1418865542,1536763871,1656751707,
 1779033704,1903828065,2031368245,2161904859,2295707848,2433068920,2574304328,
 2719758045,2869805398,3024857252,3185364841,3351825376,3524788567,3704864268,
 3892731450,4089148798)
TAN2_Q32=(2588297,10365678,23369739,41663573,65336419,94504593,129312712,169935234,
 216578343,269482214,328923700,395219500,468729861,549862905,639079655,736899888,
 843908941,960765627,1088211457,1227081410,1378316518,1542978635,1722267788,
 1917542662,2130344834,2362427575,2615790197,2892719219,3195837896,3528166129,
 3893193299)
INTERNAL_W=32
INPUT_GUARD_BITS=12
ANGLE_W=32
ANGLE_MASK=(1<<ANGLE_W)-1


@dataclass(frozen=True)
class AddressResult:
    world_x:int
    world_y:int
    world_addr:int
    az_angle_code:int
    el_angle_code:int
    angle_bits:int
    tile_x:int
    tile_y:int
    cell_x:int
    cell_y:int
    cell_offset:int
    bank_id:int
    bank_word_addr:int


def _signed_wrap(v:int,bits:int)->int:
    mask=(1<<bits)-1
    v &= mask
    return v-(1<<bits) if v&(1<<(bits-1)) else v


def _signed_bam(v:int,bits:int=ANGLE_W)->int:
    return _signed_wrap(v,bits)


def cordic_atan2_bam(y:int,x:int,iterations:int=16,internal_bits:int=INTERNAL_W,
                      angle_bits:int=24)->int:
    """Integer vectoring atan2(y,x), full-turn BAM angle, modulo wrap.

    Each x/y update wraps as a two's-complement internal register. Arithmetic
    right shift is floor toward -infinity, matching RTL signed >>> semantics.
    The angle accumulator wraps modulo 2**32. Zero y skips that iteration.
    """
    if not 1<=iterations<=len(CORDIC_ATAN_BAM32):
        raise ValueError(f"iterations must be 1..{len(CORDIC_ATAN_BAM32)}")
    if not 16<=angle_bits<=32:
        raise ValueError("angle_bits must be 16..32")
    x=_signed_wrap(int(x),internal_bits); y=_signed_wrap(int(y),internal_bits)
    if x==0:
        return (1<<(angle_bits-2)) if y>0 else (-(1<<(angle_bits-2)) if y<0 else 0)
    if y==0:
        return 0 if x>0 else -(1<<(angle_bits-1))
    z=0
    if x<0:
        if y>0: z=1<<(angle_bits-1)
        else: z=-(1<<(angle_bits-1))
        x=-x; y=-y
    shift=32-angle_bits
    for i in range(iterations):
        step=CORDIC_ATAN_BAM32[i] if shift==0 else round_shift(CORDIC_ATAN_BAM32[i],shift,"nearest_even")
        if y>0:
            xn=x+(y>>i); yn=y-(x>>i); z+=step
        elif y<0:
            xn=x-(y>>i); yn=y+(x>>i); z-=step
        else:
            continue
        x=_signed_wrap(xn,internal_bits); y=_signed_wrap(yn,internal_bits)
        z=_signed_wrap(z,angle_bits)
    return _signed_bam(z,angle_bits)


def bam_to_world_xy(az:int,el:int,bits:int=24)->tuple[int,int]:
    """Floor convention from the Exp01/02 equirectangular software model."""
    # Full turn is 2**bits; pi is half a turn. Shift exactly implements floor.
    if not 16<=bits<=32: raise ValueError("bits must be 16..32")
    az=_signed_bam(int(az),bits); el=_signed_bam(int(el),bits)
    wx=((az+(1<<(bits-1)))>>(bits-8))&0xff
    # elevation spans a half-turn and WORLD_H=128, hence 2**24 BAM32
    # units per vertical world bin.
    wy=((1<<(bits-2))-el)>>(bits-8)
    wy=min(WORLD_H-1,max(0,wy))
    return wx,wy


def _address_result(wx:int,wy:int,az:int,el:int,angle_bits:int=32)->AddressResult:
    wx%=WORLD_W
    wy=min(WORLD_H-1,max(0,int(wy)))
    tx,ty=wx>>2,wy>>2
    cx,cy=wx&3,wy&3
    cell=cy*TILE_W+cx
    # Claude RTL convention: bank = tx[1:0] XOR (-ty mod 4).
    bank=(tx&3) ^ ((-ty)&3)
    # word_addr={ty,tx>>2}; widths 5+4=9; 512 words per bank.
    word=(ty<<4)|(tx>>2)
    addr=wy*WORLD_W+wx
    return AddressResult(wx,wy,addr,_signed_bam(az,angle_bits),_signed_bam(el,angle_bits),angle_bits,tx,ty,cx,cy,cell,bank,word)


def ray_q15_to_world_address(ray_x_q15:int,ray_y_q15:int,ray_z_q15:int,
                             iterations:int=24,angle_bits:int=32)->AddressResult:
    """Selected RTL reference: integer sqrt + two fixed-point CORDIC vectorings.

    Inputs are signed Q1.15 codes. Elevation radius is floor(sqrt(x²+z²)) via
    integer square root; no floating operation participates in this path.
    """
    x,y,z=map(int,(ray_x_q15,ray_y_q15,ray_z_q15))
    if any(v < -32768 or v > 32767 for v in (x,y,z)):
        raise ValueError("ray components must be signed 16-bit Q1.15")
    if x==0 and y==0 and z==0:
        raise ValueError("zero ray has no direction")
    guard=INPUT_GUARD_BITS
    az=cordic_atan2_bam(x<<guard,z<<guard,iterations,angle_bits=angle_bits)
    radial=math.isqrt((x*x+z*z)<<(2*guard))
    el=cordic_atan2_bam(y<<guard,radial,iterations,angle_bits=angle_bits)
    wx,wy=bam_to_world_xy(az,el,angle_bits)
    return _address_result(wx,wy,az,el,angle_bits)


def _octant_bin(a:int,b:int)->tuple[int,bool]:
    """floor(atan2(a,b)/(pi/128)) and exact-boundary flag for nonnegative a,b."""
    if a==0 and b==0:
        return 0,True
    if a==0: return 0,True
    if b==0: return 64,True
    if a==b: return 32,True
    lo=min(a,b); hi=max(a,b)
    # Count crossed irrational thresholds; Q32 tangent constants are rounded
    # nearest-even offline. Products are exact integer comparisons (≤48 bits).
    j=sum(1 for t in TAN_Q32 if (lo<<32)>=hi*t)
    return (j if a<b else 63-j),False


def ray_q15_to_world_address_direct(ray_x_q15:int,ray_y_q15:int,ray_z_q15:int)->AddressResult:
    """Direct world-bin classifier; no angle code, sqrt, or floating point.

    Azimuth uses octant ratio threshold comparisons. Elevation compares the
    squared ratio to Q32 tan² boundaries, avoiding sqrt. It is a correctness
    comparator/alternative implementation; its many wide comparisons are not
    the selected V1 datapath.
    """
    x,y,z=map(int,(ray_x_q15,ray_y_q15,ray_z_q15))
    if any(v < -32768 or v > 32767 for v in (x,y,z)):
        raise ValueError("ray components must be signed 16-bit Q1.15")
    if x==0 and y==0 and z==0: raise ValueError("zero ray has no direction")
    if x==0 and z==0:
        wx=128
    else:
        theta,exact=_octant_bin(abs(x),abs(z))
        if x>=0 and z>=0: wx=128+theta
        elif x>=0 and z<0: wx=256-(theta if exact else theta+1)
        elif x<0 and z<0: wx=theta
        else: wx=128-(theta if exact else theta+1)
        wx%=256
    # Compare alpha=atan(|y|/sqrt(x²+z²)) to k*pi/128 boundaries.
    r2=x*x+z*z; ya=abs(y)
    if ya==0: alpha,exact=0,True
    elif r2==0: alpha,exact=64,True
    else:
        # Reduce to ratio <= 1 and count tangent boundaries by squaring.
        y2=ya*ya
        if y2 < r2:
            small2,large2=y2,r2
            alpha=sum(1 for t2 in TAN2_Q32 if (small2<<32)>=large2*t2)
        elif y2 > r2:
            small2,large2=r2,y2
            delta=sum(1 for t2 in TAN2_Q32 if (small2<<32)>=large2*t2)
            alpha=63-delta
        else:
            alpha=32
        exact=(y2==r2)  # only rational exact acute boundary besides axes
    if y>=0:
        wy=(64-alpha) if exact else (63-alpha)
    else:
        wy=64+alpha
    wy=min(127,max(0,wy))
    # BAMs here are only labels; selected correctness path is integer-bin direct.
    return _address_result(wx,wy,0,0,32)


def ray_q15_to_world_address_lut(ray_x_q15:int,ray_y_q15:int,ray_z_q15:int,
                                 lut_bits:int=8)->AddressResult:
    """Compact ratio LUT study candidate with deterministic integer ratio.

    The prototype normalizes each acute ratio to `lut_bits` and indexes a
    quarter-octant BAM16 table. A hardware version needs a reciprocal/ratio
    front end; this function's integer divide is an evaluation oracle only.
    """
    if lut_bits!=8: raise ValueError("study candidate currently fixes an 8-bit ratio table")
    x,y,z=map(int,(ray_x_q15,ray_y_q15,ray_z_q15))
    if any(v < -32768 or v > 32767 for v in (x,y,z)):
        raise ValueError("ray components must be signed 16-bit Q1.15")
    if x==0 and y==0 and z==0: raise ValueError("zero ray has no direction")
    tab=_ratio_lut_bam16()
    if x==0 and z==0: az16=0
    else:
        a,b=abs(x),abs(z); lo,hi=min(a,b),max(a,b)
        idx=min(256,(lo*256+hi//2)//hi) if hi else 0
        delta=tab[idx]
        theta=delta if a<=b else 16384-delta
        if x>=0 and z>=0: az16=theta
        elif x>=0 and z<0: az16=32768-theta
        elif x<0 and z<0: az16=32768+theta
        else: az16=65536-theta
    radial=math.isqrt(x*x+z*z)
    if y==0: el16=0
    else:
        a,b=abs(y),radial; lo,hi=min(a,b),max(a,b)
        idx=256 if hi==0 else min(256,(lo*256+hi//2)//hi)
        delta=tab[idx]
        alpha=delta if a<=b else 16384-delta
        el16=alpha if y>0 else -alpha
    az=_signed_bam(az16,16)
    el=_signed_bam(el16,16)
    wx,wy=bam_to_world_xy(az,el,16)
    return _address_result(wx,wy,az,el,16)


_RATIO_LUT=None
def _ratio_lut_bam16():
    global _RATIO_LUT
    if _RATIO_LUT is None:
        # Offline table construction uses host math only for this nonselected
        # candidate. The generated constant artifact is saved by Exp05b.
        _RATIO_LUT=tuple(round(math.atan(i/256.0)/(2*math.pi)*(1<<16)) for i in range(257))
    return _RATIO_LUT


def bank_id(tx:int,ty:int,mode:Literal["xor_neg","xor_plain","linear"]="xor_neg")->int:
    if mode=="xor_neg": return (tx&3)^((-ty)&3)
    if mode=="xor_plain": return (tx&3)^(ty&3)
    if mode=="linear": return tx&3
    raise ValueError(mode)
