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
    ang = 180 + (1.2886363636363 * ns) # 360 * Colorburst / 1000 = 1.2886363636363
    return ang % 360

LO = 0.65
PHI = 1.0
Sat = 0.8

HI = 0.5
SatHi = 0.3

Tune = 23+6  # 23ns = 30° + 6ns adjust

# Y, ns (0-279), sat
colors = [
    (0.0,  0,   0),     # black        180° + 33° + 0ns = 30°  (no color component)
    (1.0,  45,  0.68),  # magenta      180° + 33° + 45ns = 275°
    (0.68, 120, 0.68),  # red (+30)    180° + 33° + 120ns = 12°
    (0.68, 135, 0.68),  # orange       180° + 33° + 135ns = 31°
    (0.68, 180, 0.68),  # yellow       180° + 33° + 180ns = 89°
    (0.68, 225, 0.68),  # green        180° + 33° + 225ns = 147°
    (0.68, 270, 0.68),  # cyan         180° + 33° + 270ns = 205°
    (0.68, 300, 0.68),  # blue         180° + 33° + 300ns = 244°

    (0.47, 0,   0),     # grey         180° + 33° + ? = 216° ??
    (0.47, 45,  0.22),  # dark purple  180° + 33° + ? = 274° ??
    (0.47, 120, 0.22),  # dark red     180° + 33° + 
    (0.47, 135, 0.22),  # brown            9B
    (0.47, 180, 0.22),  # olive            9C
    (0.47, 225, 0.22),  # mint             9D
    (0.47, 270, 0.22),  # teal             9E•
    (1.0,  0,   0),     # white            9F
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
    print("col at ",ns,"is ang",ang)
    I,Q = AngSatToIQ(ang,sat)
    # print("ang",ang,"sat",sat,"I",I,"Q",Q)
    R,G,B = YIQtoRGB(Y,I,Q)
    color = (R<<16)|(B<<8)|G
    # print("col",R,G,B,hex(color))
    print(hex(color)+",")
