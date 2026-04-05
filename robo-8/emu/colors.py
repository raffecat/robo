#!/usr/bin/env python3

import math

def YIQtoRGB(Y,I,Q):
    R = Y + 0.9561*I + 0.619*Q
    G = Y - 0.272*I - 0.647*Q
    B = Y - 1.106*I + 1.703*Q
    R = max(min(int(R*255),255),0)
    G = max(min(int(G*255),255),0)
    B = max(min(int(B*255),255),0)
    return (R,G,B)

# ang is CCW from +I axis
# Y,sat in [0,1)
def AngSatToIQ(ang,sat):
    A = math.radians(ang)
    I = sat * math.cos(A)
    Q = sat * math.sin(A)
    return (I,Q)

def DelayToAng(ns):
    ang = 180 + 33 + (360 * 315/88 * ns * 10**-3)
    return ang % 360

LO = 0.65
PHI = 1.0
Sat = 0.8

HI = 0.5
SatHi = 0.2

Tune = 3

# Y, ns (0-279), sat
colors = [
    (0.0, 0, 0.0),    # black
    (LO, 45, Sat),    # blue
    (LO, 90, Sat),    # red
    (LO, 135, Sat),   # orange
    (LO, 180, Sat),   # green
    (LO, 225, Sat),   # yellow
    (LO, 270, Sat),   # cyan
    (PHI, 315, Sat),  # purple
    (0.5, 0, 0.0),    # grey
    (HI, 45, SatHi),  # light purple
    (HI, 90, SatHi),  # pink
    (HI, 135, SatHi), # pastel green
    (HI, 180, SatHi), # pastel yellow
    (HI, 225, SatHi), # mint
    (HI, 270, Sat),   # pastel blue
    (1.0, 0, 0.0),    # white
]

    # HI = 0.95
    # LO = 0.65
    # Sat = 0.8
    # SatHi = 0.5
    # Tune = 3
    # (HI, 45, SatHi),  # light purple
    # (HI, 90, SatHi),  # pink
    # (HI, 135, SatHi), # pastel green
    # (HI, 180, SatHi), # pastel yellow
    # (HI, 225, SatHi), # mint
    # (HI, 270, Sat),   # pastel blue

for (Y,ns,sat) in colors:
    ang = DelayToAng(ns + Tune)
    # print("ang",ang)
    I,Q = AngSatToIQ(ang,sat)
    # print("ang",ang,"sat",sat,"I",I,"Q",Q)
    R,G,B = YIQtoRGB(Y,I,Q)
    color = (R<<16)|(B<<8)|G
    # print("col",R,G,B,hex(color))
    print(hex(color)+",")
