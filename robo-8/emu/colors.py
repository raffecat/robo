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

HI = 0.8
LO = 0.5

# Y, ns (0-279), sat
colors = [
    (0, 180, 0),
    (HI, 45, 0.6),
    (HI, 90, 0.6),
    (HI, 135, 0.6),
    (HI, 180, 1.0),
    (HI, 225, 1.0),
    (HI, 270, 1.0),
    (HI, 315, 1.0),
    (HI, 180, 0),
]

for (Y,ns,sat) in colors:
    ang = DelayToAng(ns)
    # print("ang",ang)
    I,Q = AngSatToIQ(ang,sat)
    R,G,B = YIQtoRGB(Y,I,Q)
    color = (R<<16)|(B<<8)|G
    # print("col",R,G,B,hex(color))
    print(hex(color))
