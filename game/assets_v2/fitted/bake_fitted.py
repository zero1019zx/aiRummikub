#!/usr/bin/env python3
"""assets_v2 -> fitted/ 烘焙(去留白 + 受控九宫格 + 按钮烘字)。v4。
- 删木框, 毛毡接近屏宽; 卡牌裁掉透明留白后填满卡槽(更饱满)。
- 牌架单排。
- 动作按钮把中文直接烘进底板(整图), Godot 用 TextureButton, 4 个按钮完全一致、不再错位。
用法: 在 game/ 下运行  python3 assets_v2/fitted/bake_fitted.py
"""
from PIL import Image, ImageDraw, ImageFont
import numpy as np, os
HERE=os.path.dirname(os.path.abspath(__file__)); AV2=os.path.normpath(os.path.join(HERE,".."))+"/"; OUT=HERE+"/"
GAME=os.path.normpath(os.path.join(HERE,"..",".."))+"/"
def load(p): return Image.open(AV2+p).convert("RGBA")
def crop_opaque(im):
    a=np.array(im)[:,:,3]; ys,xs=np.where(a>18); return im.crop((xs.min(),ys.min(),xs.max()+1,ys.max()+1))
def nine(src,W,H,sl,st,sr,sb,tl,tt,tr,tb):
    sw,sh=src.size; out=Image.new("RGBA",(W,H),(0,0,0,0))
    sx=[0,sl,sw-sr,sw]; sy=[0,st,sh-sb,sh]; dx=[0,tl,W-tr,W]; dy=[0,tt,H-tb,H]
    for i in range(3):
        for j in range(3):
            a=src.crop((sx[i],sy[j],sx[i+1],sy[j+1])); d=(dx[i+1]-dx[i],dy[j+1]-dy[j])
            if a.size[0]<=0 or a.size[1]<=0 or d[0]<=0 or d[1]<=0: continue
            out.alpha_composite(a.resize(d,Image.LANCZOS),(dx[i],dy[j]))
    return out

# ---------- 几何(与 main.gd 对齐) ----------
TW,TH,SX,SY=70,100,75,106
COLS,ROWS=9,6; PADX,PADY=15,28
grid_w=(COLS-1)*SX+TW; grid_h=(ROWS-1)*SY+TH        # 670 x 630
felt_w=grid_w+2*PADX; felt_h=grid_h+2*PADY           # 700 x 686

# felt.png = 毛毡(九宫格留叶角) + 格位
felt=nine(crop_opaque(load("board/table_felt.png")),felt_w,felt_h,165,150,165,150,165,150,165,150)
slot=crop_opaque(load("board/slot_cell.png")).resize((TW,TH),Image.LANCZOS)
slot.putalpha(slot.getchannel("A").point(lambda v:int(v*0.38)))
for r in range(ROWS):
    for c in range(COLS):
        felt.alpha_composite(slot,(PADX+c*SX,PADY+r*SY))
felt.save(OUT+"felt.png")

# rack1.png = 单排木托盘
nine(crop_opaque(load("board/hand_rack.png")),felt_w,138,95,34,95,52,62,30,62,48).save(OUT+"rack1.png")

# ---------- 动作按钮:底板 + 烘中文 ----------
def pick_font(sz):
    for p in [GAME+"assets/fonts/cjk_subset.ttf",
              "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc",
              "/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"]:
        try: return ImageFont.truetype(p,sz)
        except: pass
    return ImageFont.load_default()
def bake_button(base_name,text,out_name):
    base=crop_opaque(load(f"ui/buttons/base/{base_name}_base.png"))
    W,H=base.size; img=base.copy(); d=ImageDraw.Draw(img)
    f=pick_font(int(H*0.46))
    cx,cy=int(W*0.63),int(H*0.45)   # 文字落在宝石图标右侧的彩色按钮面上
    # 深色描边 + 白字
    for dx in range(-3,4):
        for dy in range(-3,4):
            if dx*dx+dy*dy<=9: d.text((cx+dx,cy+dy),text,font=f,fill=(70,40,12,255),anchor="mm")
    d.text((cx,cy),text,font=f,fill=(255,255,255,255),anchor="mm")
    img.save(OUT+out_name+".png")
bake_button("button_play","出牌","btn_play")
bake_button("button_sort","整理","btn_sort")
bake_button("button_undo","撤回","btn_undo")
bake_button("button_hint","换牌","btn_hint")
bake_button("button_hint","确认","btn_confirm")

# ---------- 去留白裁剪(木牌/角标/Combo) ----------
def sc(p,n): crop_opaque(load(p)).save(OUT+n+".png")
sc("board/wood_plaque.png","plaque")
sc("ui/badges/base/badge_deck_count_base.png","badge_deck")
sc("ui/badges/base/badge_turn_base.png","badge_turn")
sc("ui/badges/base/badge_hp_base.png","badge_hp")
sc("ui/combo/combo_wordmark_panel.png","combo")

BX,BY=(720-felt_w)//2,150
print(f"felt {felt_w}x{felt_h} @({BX},{BY})  TILE=({TW},{TH}) SX={SX} SY={SY}")
print(f"TABLE_ORIGIN=Vector2({BX+PADX},{BY+PADY})  felt bottom={BY+felt_h}")
print("card crop region (tile_node AtlasTexture): Rect2(24,12,140,224)")
print("buttons baked: btn_play/sort/undo/hint(换牌)/confirm(确认)")
print("done ->",OUT)
