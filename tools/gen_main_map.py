# -*- coding: utf-8 -*-
"""生成大地图版 Main.tscn（大地图重绘提案 v2，4800×3200 四街区九建筑）。
运行：python tools/gen_main_map.py
墙段/门洞/地板/标签由数据计算，交互物(容器/NPC)保留原节点名与 starting_items（已按末世稀缺削减）。
"""
import os

W, H = 4800, 3200
OUT = os.path.join(os.path.dirname(__file__), "..", "scenes", "main", "Main.tscn")

# ---------------- ext resources（与旧文件一致的 id） ----------------
EXT = [
    ("Script", "res://scripts/world/main.gd", "1_main"),
    ("Script", "res://scripts/world/camp_storage.gd", "2_camp"),
    ("PackedScene", "res://scenes/player/Player.tscn", "3_player"),
    ("PackedScene", "res://scenes/ui/HUD.tscn", "6_hud"),
    ("PackedScene", "res://scenes/world/Bed.tscn", "18_bed"),
    ("Resource", "res://data/variants/runner.tres", "19_runner"),
    ("Resource", "res://data/variants/tank.tres", "20_tank"),
    ("Script", "res://scripts/world/day_night.gd", "21_dn"),
    ("Script", "res://scripts/world/spawn_point.gd", "14_sp"),
    ("PackedScene", "res://scenes/world/Door.tscn", "22_door"),
    ("PackedScene", "res://scenes/world/Wardrobe.tscn", "23_wardrobe"),
    ("PackedScene", "res://scenes/world/Fridge.tscn", "24_fridge"),
    ("PackedScene", "res://scenes/world/KitchenCabinet.tscn", "25_cabinet"),
    ("PackedScene", "res://scenes/world/Sofa.tscn", "26_sofa"),
    ("PackedScene", "res://scenes/world/Sink.tscn", "27_sink"),
    ("Resource", "res://data/loot/poor_table.tres", "15_poor"),
    ("Resource", "res://data/loot/rich_table.tres", "16_rich"),
    ("Resource", "res://data/loot/box_table.tres", "17_box"),
    ("PackedScene", "res://scenes/world/Shelf.tscn", "30_shelf"),
    ("Script", "res://scripts/items/item_data.gd", "31_iscript"),
    ("Resource", "res://data/items/food_canned.tres", "32_canned"),
    ("Resource", "res://data/items/water_bottle.tres", "33_water"),
    ("Resource", "res://data/items/cloth_hat.tres", "34_hat"),
    ("Resource", "res://data/items/bottle_plastic.tres", "35_bottle"),
    ("Resource", "res://data/items/cloth_jacket.tres", "36_jacket"),
    ("Resource", "res://data/items/weapon_fruit_knife.tres", "37_fruit"),
    ("Resource", "res://data/items/food_rice.tres", "38_rice"),
    ("Resource", "res://data/items/food_flour.tres", "39_flour"),
    ("Resource", "res://data/items/backpack_small.tres", "40_backpack"),
    ("Resource", "res://data/items/food_egg.tres", "41_egg"),
    ("Resource", "res://data/items/food_milk.tres", "42_milk"),
    ("Resource", "res://data/items/food_meat.tres", "43_meat"),
    ("Resource", "res://data/items/food_dumpling.tres", "44_dumpling"),
    ("PackedScene", "res://scenes/world/MedCabinet.tscn", "45_medcab"),
    ("PackedScene", "res://scenes/world/Nightstand.tscn", "46_nightstand"),
    ("Resource", "res://data/items/med_bandage.tres", "47_bandage"),
    ("Resource", "res://data/items/med_painkiller.tres", "48_pain"),
    ("Resource", "res://data/items/med_firstaid.tres", "49_firstaid"),
    ("Resource", "res://data/items/weapon_pistol.tres", "50_pistol"),
    ("Resource", "res://data/items/weapon_rifle.tres", "51_rifle"),
    ("Resource", "res://data/items/weapon_grenade.tres", "52_grenade"),
    ("Resource", "res://data/items/weapon_baton.tres", "53_baton"),
    ("Resource", "res://data/items/ammo_pistol_box.tres", "54_ammo9"),
    ("Resource", "res://data/items/ammo_rifle_box.tres", "55_ammor"),
    ("Resource", "res://data/items/armor_vest.tres", "56_vest"),
    ("PackedScene", "res://scenes/world/Workbench.tscn", "57_workbench"),
    ("Resource", "res://data/loot/hardware_table.tres", "58_hwtable"),
    ("Resource", "res://data/items/mat_scrap_metal.tres", "59_scrap"),
    ("Resource", "res://data/items/mat_metal_pipe.tres", "60_mpipe"),
    ("Resource", "res://data/items/mat_wood_board.tres", "61_board"),
    ("Resource", "res://data/items/mat_nails.tres", "62_nails"),
    ("Resource", "res://data/items/mat_duct_tape.tres", "63_tape"),
    ("Resource", "res://data/items/mat_cloth.tres", "64_cloth"),
    ("Resource", "res://data/items/mat_rope.tres", "65_rope"),
    ("Resource", "res://data/items/weapon_shovel.tres", "66_shovel"),
    ("Script", "res://scripts/systems/thought_system.gd", "67_thought"),
    ("PackedScene", "res://scenes/world/Radio.tscn", "68_radio"),
    ("Script", "res://scripts/systems/fog_of_war.gd", "69_fog"),
    ("Resource", "res://data/items/note_hospital.tres", "70_notehosp"),
    ("Resource", "res://data/items/note_military.tres", "71_notemil"),
    ("PackedScene", "res://scenes/world/SurvivorNpc.tscn", "69_pilot"),
    ("Resource", "res://data/items/fuel.tres", "70_fuel"),
    ("PackedScene", "res://scenes/world/Window.tscn", "72_window"),
]

shapes = {}   # (w,h) -> id
sub_lines = []
body = []


def shape(w, h):
    key = (int(w), int(h))
    if key not in shapes:
        shapes[key] = "S%d_%d" % key
        sub_lines.append('[sub_resource type="RectangleShape2D" id="%s"]' % shapes[key])
        sub_lines.append("size = Vector2(%d, %d)" % key)
        sub_lines.append("")
    return shapes[key]


def node(name, typ, parent, extra=""):
    body.append('[node name="%s" type="%s" parent="%s"]%s' % (name, typ, parent, extra))


def inst(name, parent, res, pos=None, extra=""):
    body.append('[node name="%s" parent="%s" instance=ExtResource("%s")]' % (name, parent, res))
    if pos:
        body.append("position = Vector2(%d, %d)" % pos)
    if extra:
        body.append(extra)


def pos_line(x, y):
    body.append("position = Vector2(%d, %d)" % (x, y))


def floor_rect(name, parent, color, x0, y0, x1, y1):
    node(name, "Polygon2D", parent)
    body.append("color = Color(%s)" % color)
    body.append("polygon = PackedVector2Array(%d, %d, %d, %d, %d, %d, %d, %d)"
                % (x0, y0, x1, y0, x1, y1, x0, y1))
    body.append("")


def poly(name, parent, color, pts):
    node(name, "Polygon2D", parent)
    body.append("color = Color(%s)" % color)
    body.append("polygon = PackedVector2Array(%s)" % ", ".join("%d, %d" % p for p in pts))
    body.append("")


def label(name, parent, text, cx, cy, w=160, color="0.9, 0.9, 0.9, 1",
          outline="0, 0, 0, 0.85", size=11, h=24):
    node(name, "Label", parent)
    body.append("offset_left = %d" % (cx - w // 2))
    body.append("offset_top = %d" % (cy - h // 2))
    body.append("offset_right = %d" % (cx + w // 2))
    body.append("offset_bottom = %d" % (cy + h // 2))
    body.append('text = "%s"' % text)
    body.append("horizontal_alignment = 1")
    body.append("theme_override_colors/font_color = Color(%s)" % color)
    if outline:
        body.append("theme_override_colors/font_outline_color = Color(%s)" % outline)
        body.append("theme_override_constants/outline_size = 3")
    body.append("theme_override_font_sizes/font_size = %d" % size)
    body.append("")


def wall(name, parent, x, y, w, h, color="0.62, 0.63, 0.66, 1"):
    """以中心 (x,y)、长 w 高 h 的一面墙：碰撞 + 视觉。"""
    node(name + "Shape", "CollisionShape2D", parent)
    pos_line(x, y)
    body.append('shape = SubResource("%s")' % shape(w, h))
    body.append("")
    node(name + "Visual", "Polygon2D", parent)
    body.append("color = Color(%s)" % color)
    pos_line(x, y)
    body.append("polygon = PackedVector2Array(%d, %d, %d, %d, %d, %d, %d, %d)"
                % (-w // 2, -h // 2, w // 2, -h // 2, w // 2, h // 2, -w // 2, h // 2))
    body.append("")


def wall_run(name, parent, axis, fixed, a, b, gaps, color, th=16):
    """沿 axis 轴从 a 到 b 的一面墙，gaps=[(g0,g1),...] 为门洞。
    axis='h': 墙在 y=fixed，沿 x；axis='v': 墙在 x=fixed，沿 y。"""
    segs = []
    cur = a
    for g0, g1 in gaps:
        if g0 > cur:
            segs.append((cur, g0))
        cur = g1
    if cur < b:
        segs.append((cur, b))
    for i, (s0, s1) in enumerate(segs):
        c = (s0 + s1) // 2
        ln = s1 - s0
        if axis == "h":
            wall("%s%d" % (name, i + 1), parent, c, fixed, ln, th, color)
        else:
            wall("%s%d" % (name, i + 1), parent, fixed, c, th, ln, color)


T = 16  # 墙厚


# ================= 场景开始 =================
body.append('[node name="Main" type="Node2D"]')
body.append('script = ExtResource("1_main")')
body.append("")

# 地面
floor_rect("Ground", ".", "0.14, 0.17, 0.14, 1", 0, 0, W, H)

# ---- 安全区（安全屋 400×280 @ 300,1900）----
node("CampArea", "Area2D", ".")
pos_line(500, 2040)
body.append('script = ExtResource("2_camp")')
body.append("half_size = Vector2(280, 190)")
body.append("")
node("Shape", "CollisionShape2D", "CampArea")
body.append('shape = SubResource("%s")' % shape(560, 380))
body.append("")
floor_rect("Visual", "CampArea", "0.3, 0.24, 0.16, 1", -280, -190, 280, 190)
floor_rect("BedroomFloor", "CampArea", "0.33, 0.26, 0.17, 1", -200, -140, 0, 140)
floor_rect("LivingFloor", "CampArea", "0.32, 0.25, 0.17, 1", 0, -140, 200, 140)
floor_rect("KitchenFloor", "CampArea", "0.36, 0.3, 0.19, 1", 60, -140, 200, -40)
label("Label", "CampArea", "安全屋 · 记得关门", 0, -204, 220, "0.85, 0.95, 0.8, 1", None, 14)
label("BedroomLabel", "CampArea", "卧室", -100, -152, 120, "0.8, 0.78, 0.7, 1", None, 12)
label("LivingLabel", "CampArea", "客厅", 100, 152, 120, "0.8, 0.78, 0.7, 1", None, 12)
label("KitchenLabel", "CampArea", "厨房", 130, -152, 120, "0.8, 0.78, 0.7, 1", None, 12)

node("HouseWalls", "StaticBody2D", ".")
body.append("collision_layer = 7")
body.append("")
HW = "0.42, 0.3, 0.18, 1"
HI = "0.5, 0.38, 0.25, 1"
wall_run("Top", "HouseWalls", "h", 1908, 300, 700, [], HW)
wall_run("Bottom", "HouseWalls", "h", 2172, 300, 700, [(460, 540)], HW)
wall("Left", "HouseWalls", 308, 2040, T, 280, HW)
wall("Right", "HouseWalls", 692, 2040, T, 280, HW)
wall_run("Inner", "HouseWalls", "v", 500, 1908, 2172, [(2020, 2100)], HI)

inst("Door", ".", "22_door", (500, 2172))
node("SpawnPoint", "Marker2D", ".")
pos_line(450, 2100)
body.append("")
inst("Bed", ".", "18_bed", (360, 1960))
inst("Wardrobe", ".", "23_wardrobe", (440, 1935))
inst("Fridge", ".", "24_fridge", (640, 1945))
inst("KitchenCabinet", ".", "25_cabinet", (575, 1945))
inst("Sofa", ".", "26_sofa", (615, 2130))
inst("Sink", ".", "27_sink", (672, 2015))
inst("Workbench", ".", "57_workbench", (570, 2070))
inst("Radio", ".", "68_radio", (335, 2085))

node("ThoughtSystem", "Node", ".")
body.append('script = ExtResource("67_thought")')
body.append("")

# ---- 地图边界墙 ----
node("Walls", "StaticBody2D", ".")
body.append("collision_layer = 7")
body.append("")
wall("Top", "Walls", W // 2, -20, W + 80, 40, "0.3, 0.3, 0.28, 1")
wall("Bottom", "Walls", W // 2, H + 20, W + 80, 40, "0.3, 0.3, 0.28, 1")
wall("Left", "Walls", -20, H // 2, 40, H + 80, "0.3, 0.3, 0.28, 1")
wall("Right", "Walls", W + 20, H // 2, 40, H + 80, "0.3, 0.3, 0.28, 1")

# ---- 废弃车辆（主街路障）----
node("AbandonedCars", "StaticBody2D", ".")
body.append("collision_layer = 7")
body.append("")
CAR_COLORS = ["0.45, 0.25, 0.2, 1", "0.35, 0.38, 0.42, 1", "0.4, 0.42, 0.3, 1",
              "0.3, 0.3, 0.35, 1", "0.5, 0.42, 0.25, 1", "0.42, 0.3, 0.32, 1"]
ROOF_COLORS = ["0.3, 0.42, 0.45, 1", "0.25, 0.28, 0.32, 1", "0.28, 0.3, 0.25, 1",
               "0.2, 0.22, 0.26, 1", "0.35, 0.3, 0.2, 1", "0.28, 0.22, 0.26, 1"]
CARS = [(1200, 1632), (2050, 1600), (3050, 1600), (2400, 900), (2400, 2500), (900, 1250)]
for i, (cx, cy) in enumerate(CARS, 1):
    wall("Car%d" % i, "AbandonedCars", cx, cy, 120, 60, CAR_COLORS[i - 1])
    node("Car%dRoof" % i, "Polygon2D", "AbandonedCars")
    body.append("color = Color(%s)" % ROOF_COLORS[i - 1])
    pos_line(cx, cy)
    body.append("polygon = PackedVector2Array(-28, -18, 28, -18, 34, 18, -34, 18)")
    body.append("")

# ---- 废墟装饰块 ----
node("Buildings", "StaticBody2D", ".")
body.append("collision_layer = 7")
body.append("")
RUINS = [(1500, 320, 220, 140), (900, 2620, 200, 140), (4260, 2900, 220, 160),
         (4380, 500, 200, 130)]
for i, (cx, cy, rw, rh) in enumerate(RUINS, 1):
    wall("Ruin%d" % i, "Buildings", cx, cy, rw, rh, "0.3, 0.31, 0.33, 1")


# ================= 军营 960×720 @ (240,240)-(1200,960) =================
node("MilitaryBase", "Node2D", ".")
body.append("")
floor_rect("Floor", "MilitaryBase", "0.3, 0.34, 0.3, 1", 240, 240, 1200, 960)
floor_rect("PadFloor", "MilitaryBase", "0.42, 0.44, 0.47, 1", 720, 240, 1200, 960)
floor_rect("FuelFloor", "MilitaryBase", "0.38, 0.32, 0.26, 1", 240, 800, 720, 960)
label("PadH", "MilitaryBase", "H", 960, 480, 60, "0.95, 0.95, 0.9, 1", "0.2, 0.2, 0.22, 0.9", 28, 40)
label("LBase", "MilitaryBase", "城北军营（撤离点）", 620, 180, 220, "1, 1, 1, 1", "0.2, 0.4, 0.2, 1", 14)
label("L营房", "MilitaryBase", "营房", 420, 300, 120, "0.85, 0.9, 0.85, 1", None)
label("LPad", "MilitaryBase", "停机坪", 960, 900, 120, "0.9, 0.92, 0.95, 1", None)
label("LFuel", "MilitaryBase", "油料区", 480, 830, 120, "0.9, 0.8, 0.6, 1", None)
node("Walls", "StaticBody2D", "MilitaryBase")
body.append("collision_layer = 7")
body.append("")
MC = "0.62, 0.63, 0.66, 1"
MI = "0.55, 0.56, 0.59, 1"
wall_run("Top", "MilitaryBase/Walls", "h", 248, 240, 1200, [], MC)
wall_run("Bottom", "MilitaryBase/Walls", "h", 952, 240, 1200, [(640, 760)], MC)
wall("Left", "MilitaryBase/Walls", 248, 600, T, 720, MC)
wall("Right", "MilitaryBase/Walls", 1192, 600, T, 720, MC)
wall_run("Divider", "MilitaryBase/Walls", "v", 720, 248, 952, [(540, 640)], MI)
wall_run("FuelWall", "MilitaryBase/Walls", "h", 800, 248, 712, [(560, 660)], MI)
# 直升机（整体从旧位平移 offset -455,+180）
OFF = (-455, 180)


def tp(pts):
    return [(x + OFF[0], y + OFF[1]) for x, y in pts]


node("Helicopter", "Node2D", "MilitaryBase")
body.append("")
node("Hull", "StaticBody2D", "MilitaryBase/Helicopter")
body.append("collision_layer = 7")
body.append("")
node("HullShape", "CollisionShape2D", "MilitaryBase/Helicopter/Hull")
pos_line(960, 480)
body.append('shape = SubResource("%s")' % shape(90, 36))
body.append("")
poly("TailBoom", "MilitaryBase/Helicopter", "0.2, 0.26, 0.22, 1",
     tp([(1320, 296), (1380, 293), (1380, 307), (1320, 304)]))
poly("TailRotor", "MilitaryBase/Helicopter", "0.12, 0.12, 0.14, 1",
     tp([(1318, 280), (1322, 280), (1322, 308), (1318, 308)]))
poly("Fuselage", "MilitaryBase/Helicopter", "0.2, 0.26, 0.22, 1",
     tp([(1370, 286), (1445, 284), (1460, 292), (1460, 308), (1445, 316), (1370, 314)]))
poly("Cockpit", "MilitaryBase/Helicopter", "0.45, 0.65, 0.75, 1",
     tp([(1440, 288), (1458, 293), (1458, 307), (1440, 312)]))
poly("Skids", "MilitaryBase/Helicopter", "0.14, 0.15, 0.16, 1",
     tp([(1375, 318), (1455, 318), (1455, 322), (1375, 322)]))
poly("Rotor", "MilitaryBase/Helicopter", "0.12, 0.12, 0.14, 1",
     tp([(1295, 298), (1535, 298), (1535, 302), (1295, 302)]))
poly("RotorHub", "MilitaryBase/Helicopter", "0.3, 0.3, 0.33, 1",
     tp([(1410, 294), (1420, 294), (1420, 306), (1410, 306)]))
# 营房床位
node("BarrackBeds", "StaticBody2D", "MilitaryBase")
body.append("collision_layer = 3")
body.append("")
for bi, by in enumerate((380, 470), 1):
    wall("Bed%d" % bi, "MilitaryBase/BarrackBeds", 350, by, 64, 36, "0.5, 0.55, 0.6, 1")
    node("Bed%dBlanket" % bi, "Polygon2D", "MilitaryBase/BarrackBeds")
    body.append("color = Color(0.4, 0.48, 0.42, 1)")
    pos_line(350, by)
    body.append("polygon = PackedVector2Array(-2, -16, 30, -16, 30, 16, -2, 16)")
    body.append("")
# 油桶装饰
for di, (dx, dy) in enumerate(((300, 870), (530, 890)), 1):
    node("Drum%d" % di, "StaticBody2D", "MilitaryBase")
    body.append("collision_layer = 3")
    body.append("")
    wall("Shape", "MilitaryBase/Drum%d" % di, dx, dy, 22, 22, "0.6, 0.38, 0.12, 1")
inst("MilCabinet", "MilitaryBase", "30_shelf", (580, 320),
     'display_name = "军需柜"\nstarting_items = Array[ExtResource("31_iscript")]'
     '([ExtResource("49_firstaid"), ExtResource("32_canned"), ExtResource("52_grenade")])')
inst("FuelDrum1", "MilitaryBase", "30_shelf", (330, 880),
     'display_name = "油桶"\nstarting_items = Array[ExtResource("31_iscript")]'
     '([ExtResource("70_fuel"), ExtResource("70_fuel")])')
inst("FuelDrum2", "MilitaryBase", "30_shelf", (430, 880),
     'display_name = "油桶"\nstarting_items = Array[ExtResource("31_iscript")]'
     '([ExtResource("70_fuel")])')
inst("Pilot", ".", "69_pilot", (580, 430))

# ================= 医院 896×672 @ (2560,200)-(3456,872) =================
node("Hospital", "Node2D", ".")
body.append("")
floor_rect("Floor", "Hospital", "0.82, 0.83, 0.85, 1", 2560, 200, 3456, 872)
floor_rect("PharmacyFloor", "Hospital", "0.76, 0.82, 0.78, 1", 2560, 200, 3040, 616)
floor_rect("WardFloor", "Hospital", "0.78, 0.8, 0.86, 1", 3040, 416, 3260, 616)
floor_rect("SurgeryFloor", "Hospital", "0.88, 0.86, 0.88, 1", 3260, 200, 3456, 416)
label("LSign", "Hospital", "仁爱医院", 2950, 165, 240, "1, 1, 1, 1", "0.72, 0.18, 0.18, 1", 14)
poly("CrossV", "Hospital", "0.85, 0.25, 0.25, 1", [(3408, 152), (3420, 152), (3420, 180), (3408, 180)])
poly("CrossH", "Hospital", "0.85, 0.25, 0.25, 1", [(3402, 160), (3426, 160), (3426, 172), (3402, 172)])
label("LPhar", "Hospital", "药房", 2750, 240, 120, "0.85, 0.95, 0.88, 1", "0.2, 0.35, 0.25, 0.9")
label("LWard", "Hospital", "病房", 3120, 450, 120, "0.88, 0.9, 0.97, 1", "0.25, 0.28, 0.4, 0.9")
label("LSurg", "Hospital", "手术室", 3358, 240, 120, "0.95, 0.9, 0.95, 1", "0.4, 0.2, 0.3, 0.9")
label("LLobby", "Hospital", "挂号大厅", 3000, 700, 160, "0.95, 0.95, 0.97, 1", "0.3, 0.3, 0.35, 0.9")
node("Walls", "StaticBody2D", "Hospital")
body.append("collision_layer = 7")
body.append("")
HC = "0.62, 0.63, 0.66, 1"
HI2 = "0.55, 0.56, 0.59, 1"
wall_run("Top", "Hospital/Walls", "h", 208, 2560, 3456, [], HC)
wall_run("Bottom", "Hospital/Walls", "h", 864, 2560, 3456, [(2950, 3070)], HC)
wall("Left", "Hospital/Walls", 2568, 536, T, 672, HC)
wall("Right", "Hospital/Walls", 3448, 536, T, 672, HC)
wall_run("MainDivider", "Hospital/Walls", "h", 616, 2560, 3456,
         [(2700, 2800), (3150, 3250)], HI2)
wall("MidV", "Hospital/Walls", 3040, 412, T, 408, HI2)
wall_run("SurgV", "Hospital/Walls", "v", 3260, 208, 416, [(280, 380)], HI2)
wall("SurgH", "Hospital/Walls", 3354, 416, 188, T, HI2)
node("Reception", "StaticBody2D", "Hospital")
body.append("collision_layer = 3")
body.append("")
wall("Shape", "Hospital/Reception", 2800, 800, 90, 20, "0.55, 0.45, 0.3, 1")
node("Bench", "StaticBody2D", "Hospital")
body.append("collision_layer = 3")
body.append("")
wall("Shape", "Hospital/Bench", 3200, 800, 80, 20, "0.4, 0.5, 0.55, 1")
node("HospitalBeds", "StaticBody2D", "Hospital")
body.append("collision_layer = 3")
body.append("")
for bi, (bx, by) in enumerate(((3130, 500), (3130, 570)), 1):
    wall("Bed%d" % bi, "Hospital/HospitalBeds", bx, by, 64, 36, "0.9, 0.91, 0.94, 1")
    node("Bed%dBlanket" % bi, "Polygon2D", "Hospital/HospitalBeds")
    body.append("color = Color(0.6, 0.7, 0.85, 1)")
    pos_line(bx, by)
    body.append("polygon = PackedVector2Array(-2, -16, 30, -16, 30, 16, -2, 16)")
    body.append("")
inst("ShelfM1", "Hospital", "30_shelf", (2700, 320),
     'display_name = "药房货架"\nstarting_items = Array[ExtResource("31_iscript")]'
     '([ExtResource("47_bandage"), ExtResource("71_notemil")])')
inst("ShelfM2", "Hospital", "30_shelf", (2700, 420),
     'display_name = "药房货架"\nstarting_items = Array[ExtResource("31_iscript")]'
     '([ExtResource("48_pain")])')
inst("MedCab", "Hospital", "45_medcab", (2870, 320))
inst("Nightstand", "Hospital", "46_nightstand", (3130, 460))

# ================= 警局 512×400 @ (3640,1820)-(4152,2220) =================
node("PoliceStation", "Node2D", ".")
body.append("")
floor_rect("Floor", "PoliceStation", "0.5, 0.52, 0.58, 1", 3640, 1820, 4152, 2220)
floor_rect("CellFloor", "PoliceStation", "0.44, 0.46, 0.5, 1", 3640, 1820, 3900, 2020)
floor_rect("ArmoryFloor", "PoliceStation", "0.42, 0.44, 0.48, 1", 3900, 1820, 4152, 2020)
label("LSign", "PoliceStation", "市公安局", 3850, 1785, 240, "1, 1, 1, 1", "0.15, 0.25, 0.55, 1", 14)
label("LCell", "PoliceStation", "拘留区", 3760, 1870, 120, "0.85, 0.88, 0.95, 1", None)
label("LArmory", "PoliceStation", "军械库", 4026, 1870, 120, "1, 0.85, 0.6, 1", None)
label("LLobby", "PoliceStation", "办公大厅", 3900, 2160, 160, "0.9, 0.92, 0.98, 1", None)
node("Walls", "StaticBody2D", "PoliceStation")
body.append("collision_layer = 7")
body.append("")
PC = "0.3, 0.32, 0.36, 1"
PI2 = "0.27, 0.29, 0.33, 1"
wall_run("Top", "PoliceStation/Walls", "h", 1828, 3640, 4152, [], PC)
wall_run("Bottom", "PoliceStation/Walls", "h", 2212, 3640, 4152, [(3830, 3950)], PC)
wall("Left", "PoliceStation/Walls", 3648, 2020, T, 400, PC)
wall("Right", "PoliceStation/Walls", 4144, 2020, T, 400, PC)
wall_run("MainDivider", "PoliceStation/Walls", "h", 2020, 3640, 4152,
         [(3720, 3820), (3980, 4080)], PI2)
wall("MidV", "PoliceStation/Walls", 3900, 1924, T, 192, PI2)
# 拘留区铁栏杆（装饰）
poly("CellBars1", "PoliceStation", "0.65, 0.68, 0.72, 1", [(3756, 1875), (3760, 1875), (3760, 1975), (3756, 1975)])
poly("CellBars2", "PoliceStation", "0.65, 0.68, 0.72, 1", [(3836, 1875), (3840, 1875), (3840, 1975), (3836, 1975)])
node("Reception", "StaticBody2D", "PoliceStation")
body.append("collision_layer = 3")
body.append("")
wall("Shape", "PoliceStation/Reception", 3790, 2160, 90, 20, "0.35, 0.4, 0.45, 1")
inst("GunLocker", "PoliceStation", "30_shelf", (4040, 1930),
     'display_name = "枪柜"\nstarting_items = Array[ExtResource("31_iscript")]'
     '([ExtResource("50_pistol"), ExtResource("54_ammo9")])')
inst("AmmoCrateA", "PoliceStation", "30_shelf", (3960, 1870),
     'display_name = "弹药箱"\nstarting_items = Array[ExtResource("31_iscript")]'
     '([ExtResource("54_ammo9")])')
inst("AmmoCrateB", "PoliceStation", "30_shelf", (4100, 1870),
     'display_name = "弹药箱"\nstarting_items = Array[ExtResource("31_iscript")]'
     '([ExtResource("52_grenade")])')
inst("EvidenceDesk", "PoliceStation", "30_shelf", (3720, 2130),
     'display_name = "证物桌"\nstarting_items = Array[ExtResource("31_iscript")]'
     '([ExtResource("53_baton"), ExtResource("47_bandage")])')
inst("OfficeDesk", "PoliceStation", "30_shelf", (4040, 2130),
     'display_name = "办公桌"\nstarting_items = Array[ExtResource("31_iscript")]'
     '([ExtResource("56_vest")])')

# ================= 超市 800×600 @ (2600,1800)-(3400,2400) =================
node("Market", "Node2D", ".")
body.append("")
floor_rect("Floor", "Market", "0.55, 0.56, 0.58, 1", 2600, 1800, 3400, 2400)
floor_rect("StorageFloor", "Market", "0.45, 0.4, 0.33, 1", 2600, 1800, 3000, 2100)
floor_rect("ColdFloor", "Market", "0.5, 0.6, 0.68, 1", 3000, 1800, 3400, 2100)
label("LSign", "Market", "惠民超市", 3000, 1765, 240, "1, 0.92, 0.6, 1", "0, 0, 0, 0.9", 14)
label("LStor", "Market", "仓储区", 2800, 1845, 120, "0.9, 0.88, 0.8, 1", None)
label("LCold", "Market", "冷藏区", 3200, 1845, 120, "0.75, 0.9, 1, 1", None)
label("LCheck", "Market", "收银台", 2850, 2330, 120, "0.95, 0.85, 0.6, 1", None)
node("Walls", "StaticBody2D", "Market")
body.append("collision_layer = 7")
body.append("")
MK = "0.35, 0.37, 0.4, 1"
MI3 = "0.32, 0.34, 0.37, 1"
wall_run("Top", "Market/Walls", "h", 1808, 2600, 3400, [], MK)
wall_run("Bottom", "Market/Walls", "h", 2392, 2600, 3400, [(2940, 3060)], MK)
wall("Left", "Market/Walls", 2608, 2100, T, 600, MK)
wall("RightUpper", "Market/Walls", 3392, 1879, T, 150, MK)
wall("RightLower", "Market/Walls", 3392, 2250, T, 300, MK)
inst("EastWindow", "Market", "72_window", (3392, 2025))
wall_run("MainDivider", "Market/Walls", "h", 2100, 2600, 3400,
         [(2700, 2800), (3200, 3300)], MI3)
wall("MidV", "Market/Walls", 3000, 1954, T, 292, MI3)
node("Checkout", "StaticBody2D", "Market")
body.append("collision_layer = 3")
body.append("")
wall("Shape", "Market/Checkout", 2850, 2360, 100, 24, "0.55, 0.42, 0.22, 1")
inst("ShelfA1", "Market", "30_shelf", (2750, 2250),
     'starting_items = Array[ExtResource("31_iscript")]'
     '([ExtResource("32_canned"), ExtResource("33_water"), ExtResource("70_notehosp")])')
inst("ShelfA2", "Market", "30_shelf", (3250, 2250),
     'starting_items = Array[ExtResource("31_iscript")]'
     '([ExtResource("32_canned"), ExtResource("37_fruit")])')
inst("ShelfB1", "Market", "30_shelf", (2750, 2330),
     'starting_items = Array[ExtResource("31_iscript")]'
     '([ExtResource("38_rice")])')
inst("ShelfB2", "Market", "30_shelf", (3250, 2330),
     'starting_items = Array[ExtResource("31_iscript")]'
     '([ExtResource("40_backpack"), ExtResource("35_bottle")])')
inst("ShelfC1", "Market", "30_shelf", (3150, 1950),
     'starting_items = Array[ExtResource("31_iscript")]'
     '([ExtResource("42_milk"), ExtResource("43_meat")])')
inst("ShelfC2", "Market", "30_shelf", (3300, 1950),
     'starting_items = Array[ExtResource("31_iscript")]'
     '([ExtResource("41_egg"), ExtResource("33_water")])')

# ================= 五金店 448×320 @ (1560,760)-(2008,1080) =================
node("HardwareStore", "Node2D", ".")
body.append("")
floor_rect("Floor", "HardwareStore", "0.5, 0.44, 0.36, 1", 1560, 760, 2008, 1080)
floor_rect("StorageFloor", "HardwareStore", "0.4, 0.34, 0.27, 1", 1560, 760, 1780, 900)
label("LSign", "HardwareStore", "废铁五金店", 1780, 725, 240, "1, 0.9, 0.6, 1", "0.25, 0.15, 0.05, 1", 14)
label("LStor", "HardwareStore", "仓库角", 1670, 795, 120, "0.85, 0.78, 0.65, 1", None)
label("LSale", "HardwareStore", "销售区", 1790, 1045, 120, "0.9, 0.85, 0.75, 1", None)
node("Walls", "StaticBody2D", "HardwareStore")
body.append("collision_layer = 7")
body.append("")
HW2 = "0.45, 0.36, 0.28, 1"
HI4 = "0.4, 0.32, 0.25, 1"
wall_run("Top", "HardwareStore/Walls", "h", 768, 1560, 2008, [], HW2)
wall_run("Bottom", "HardwareStore/Walls", "h", 1072, 1560, 2008, [(1720, 1820)], HW2)
wall("Left", "HardwareStore/Walls", 1568, 920, T, 320, HW2)
wall("Right", "HardwareStore/Walls", 2000, 920, T, 320, HW2)
wall("StorV", "HardwareStore/Walls", 1780, 834, T, 132, HI4)
wall_run("StorH", "HardwareStore/Walls", "h", 900, 1568, 1780, [(1640, 1720)], HI4)
inst("ToolCounter", "HardwareStore", "30_shelf", (1660, 845),
     'display_name = "工具柜台"\nstarting_items = Array[ExtResource("31_iscript")]'
     '([ExtResource("66_shovel"), ExtResource("40_backpack")])')
inst("ShelfR1A", "HardwareStore", "30_shelf", (1900, 880),
     'display_name = "五金货架"\nstarting_items = Array[ExtResource("31_iscript")]'
     '([ExtResource("59_scrap"), ExtResource("62_nails")])')
inst("ShelfR1B", "HardwareStore", "30_shelf", (1900, 960),
     'display_name = "五金货架"\nstarting_items = Array[ExtResource("31_iscript")]'
     '([ExtResource("61_board"), ExtResource("63_tape")])')
inst("ShelfR2A", "HardwareStore", "30_shelf", (1740, 1010),
     'display_name = "五金货架"\nstarting_items = Array[ExtResource("31_iscript")]'
     '([ExtResource("65_rope"), ExtResource("64_cloth")])')
inst("ShelfR2B", "HardwareStore", "30_shelf", (1900, 1030),
     'display_name = "五金货架"\nstarting_items = Array[ExtResource("31_iscript")]'
     '([ExtResource("60_mpipe"), ExtResource("59_scrap")])')

# ================= 学校 832×624 @ (2600,2500)-(3432,3124) =================
node("School", "Node2D", ".")
body.append("")
floor_rect("Floor", "School", "0.62, 0.6, 0.55, 1", 2600, 2500, 3432, 3124)
floor_rect("CorridorFloor", "School", "0.7, 0.68, 0.62, 1", 2600, 2780, 3432, 2900)
floor_rect("GymFloor", "School", "0.55, 0.58, 0.6, 1", 3160, 2900, 3432, 3124)
label("LSign", "School", "城东中学", 3016, 2465, 200, "1, 1, 1, 1", "0.3, 0.28, 0.5, 1", 14)
label("LC1", "School", "教室", 2740, 2540, 120, "0.9, 0.9, 0.95, 1", None)
label("LC2", "School", "教室", 3020, 2540, 120, "0.9, 0.9, 0.95, 1", None)
label("LCanteen", "School", "食堂", 3300, 2540, 120, "0.95, 0.9, 0.8, 1", None)
label("LGym", "School", "体育馆", 3296, 3010, 120, "0.9, 0.93, 0.96, 1", None)
node("Walls", "StaticBody2D", "School")
body.append("collision_layer = 7")
body.append("")
SC = "0.5, 0.48, 0.45, 1"
SI = "0.45, 0.43, 0.4, 1"
wall_run("Top", "School/Walls", "h", 2508, 2600, 3432, [(2950, 3070)], SC)
wall_run("Bottom", "School/Walls", "h", 3116, 2600, 3432, [], SC)
wall("Left", "School/Walls", 2608, 2812, T, 624, SC)
wall("Right", "School/Walls", 3424, 2812, T, 624, SC)
wall_run("CorrN", "School/Walls", "h", 2780, 2600, 3432,
         [(2700, 2790), (2990, 3080), (3260, 3350)], SI)
wall_run("CorrS", "School/Walls", "h", 2900, 2600, 3432,
         [(2700, 2790), (2990, 3080), (3290, 3380)], SI)
wall("NV1", "School/Walls", 2880, 2644, T, 272, SI)
wall("NV2", "School/Walls", 3160, 2644, T, 272, SI)
wall("SV1", "School/Walls", 2880, 3008, T, 216, SI)
wall("SV2", "School/Walls", 3160, 3008, T, 216, SI)

# ================= 公寓楼 512×384 @ (3700,700)-(4212,1084) =================
node("Apartment", "Node2D", ".")
body.append("")
floor_rect("Floor", "Apartment", "0.58, 0.55, 0.5, 1", 3700, 700, 4212, 1084)
floor_rect("CorridorFloor", "Apartment", "0.66, 0.63, 0.57, 1", 3700, 850, 4212, 910)
label("LSign", "Apartment", "城东公寓", 3956, 665, 200, "1, 1, 1, 1", "0.3, 0.3, 0.3, 1", 14)
node("Walls", "StaticBody2D", "Apartment")
body.append("collision_layer = 7")
body.append("")
AC = "0.55, 0.52, 0.48, 1"
AI = "0.5, 0.47, 0.43, 1"
wall_run("Top", "Apartment/Walls", "h", 708, 3700, 4212, [], AC)
wall_run("Bottom", "Apartment/Walls", "h", 1076, 3700, 4212, [(3890, 4010)], AC)
wall("Left", "Apartment/Walls", 3708, 892, T, 384, AC)
wall("Right", "Apartment/Walls", 4204, 892, T, 384, AC)
wall_run("CorrN", "Apartment/Walls", "h", 858, 3700, 4212,
         [(3760, 3850), (4060, 4150)], AI)
wall_run("CorrS", "Apartment/Walls", "h", 902, 3700, 4212,
         [(3760, 3850), (4060, 4150)], AI)
wall("NV", "Apartment/Walls", 3956, 783, T, 150, AI)
wall("SV", "Apartment/Walls", 3956, 989, T, 174, AI)

# ================= 便利店 320×256 @ (1000,2200)-(1320,2456) =================
node("ConvenienceStore", "Node2D", ".")
body.append("")
floor_rect("Floor", "ConvenienceStore", "0.6, 0.58, 0.5, 1", 1000, 2200, 1320, 2456)
label("LSign", "ConvenienceStore", "惠民便利店", 1160, 2165, 200, "1, 0.95, 0.7, 1", "0.3, 0.2, 0.05, 1", 14)
node("Walls", "StaticBody2D", "ConvenienceStore")
body.append("collision_layer = 7")
body.append("")
CC = "0.5, 0.47, 0.4, 1"
wall_run("Top", "ConvenienceStore/Walls", "h", 2208, 1000, 1320, [], CC)
wall_run("Bottom", "ConvenienceStore/Walls", "h", 2448, 1000, 1320, [(1130, 1190)], CC)
wall("Left", "ConvenienceStore/Walls", 1008, 2328, T, 256, CC)
wall("Right", "ConvenienceStore/Walls", 1312, 2328, T, 256, CC)

# ---- 玩家 ----
inst("Player", ".", "3_player", (450, 2100))

# ---- 出生点/丧尸/箱子 ----
node("SpawnPoints", "Node2D", ".")
body.append("")


def sp(name, pos, zc=0, variants=None, weights=None, radius=None, rolls=None,
       table=None, boxes=0, box_rolls=0, box_table=None):
    node(name, "Marker2D", "SpawnPoints")
    pos_line(*pos)
    body.append('script = ExtResource("14_sp")')
    if zc:
        body.append("zombie_count = %d" % zc)
    if variants:
        body.append("variants = [%s]" % ", ".join(
            "null" if v is None else 'ExtResource("%s")' % v for v in variants))
    if weights:
        body.append("variant_weights = [%s]" % ", ".join(str(w) for w in weights))
    if boxes:
        body.append("box_count = %d" % boxes)
    if box_rolls:
        body.append("box_rolls = %d" % box_rolls)
    if box_table:
        body.append('box_table = ExtResource("%s")' % box_table)
    if rolls is not None:
        body.append("pickup_rolls = %d" % rolls)
    if table:
        body.append('pickup_table = ExtResource("%s")' % table)
    if radius:
        body.append("spawn_radius = %.1f" % radius)
    body.append("")


sp("Suburb1", (700, 600), zc=1, variants=[None, "19_runner"], weights=[80, 20], rolls=0, table="15_poor")
sp("Suburb2", (650, 1350), zc=1, variants=[None, "19_runner"], weights=[80, 20], rolls=0, table="15_poor")
sp("Suburb3", (1300, 2650), zc=0, rolls=0, table="15_poor")
sp("City1", (1750, 1350), zc=2, variants=[None, "19_runner", "20_tank"], weights=[50, 30, 20], rolls=0, table="16_rich")
sp("City2", (2950, 1550), zc=2, variants=[None, "19_runner", "20_tank"], weights=[50, 30, 20], rolls=0, table="16_rich")
sp("City3", (2100, 2250), zc=2, variants=[None, "19_runner", "20_tank"], weights=[50, 30, 20], rolls=0, table="16_rich")
sp("MarketGuard", (3000, 2250), zc=3, variants=[None, "20_tank"], weights=[65, 35], radius=90)
sp("MarketGuardCold", (3150, 1950), zc=2, variants=[None, "20_tank"], weights=[65, 35], radius=55)
sp("HospitalGuard", (3000, 730), zc=2, radius=55)
sp("HospitalGuardTank", (2750, 300), zc=1, variants=["20_tank"], radius=40)
sp("HospitalGuardWard", (3150, 520), zc=1, radius=40)
sp("PoliceGuard", (3900, 2120), zc=2, radius=40)
sp("PoliceGuardTank", (3980, 1990), zc=1, variants=["20_tank"], radius=30)
sp("PoliceGuardCell", (3760, 1920), zc=1, radius=35)
sp("HardwareGuard", (1800, 1000), zc=2, radius=60)
sp("HardwareGuardTank", (1930, 830), zc=1, variants=["20_tank"], radius=30)
sp("HardwareBox", (1660, 860), boxes=1, box_rolls=2, box_table="58_hwtable", radius=20)
sp("MilGuards", (480, 700), zc=4, radius=80)
sp("MilTankPad", (960, 640), zc=1, variants=["20_tank"], radius=30)
sp("MilTankBarrack", (400, 400), zc=1, variants=["20_tank"], radius=30)
sp("Box1", (560, 700), boxes=1, box_rolls=2, box_table="17_box", radius=24)
sp("Box2", (2800, 1950), boxes=1, box_rolls=3, box_table="17_box", radius=24)

inst("HUD", ".", "6_hud")
node("DayNightModulate", "CanvasModulate", ".")
body.append("color = Color(1, 1, 1, 1)")
body.append("")
node("DayNight", "Node", ".")
body.append('script = ExtResource("21_dn")')
body.append("")
node("FogOfWar", "Node2D", ".")
body.append('script = ExtResource("69_fog")')
body.append("map_size = Vector2(%d, %d)" % (W, H))
body.append("")

# ---------------- 输出 ----------------
load_steps = len(EXT) + len(shapes) + 1
with open(OUT, "w", encoding="utf-8", newline="\n") as f:
    f.write("[gd_scene load_steps=%d format=3]\n\n" % load_steps)
    for typ, path, rid in EXT:
        f.write('[ext_resource type="%s" path="%s" id="%s"]\n' % (typ, path, rid))
    f.write("\n")
    for ln in sub_lines:
        f.write(ln + "\n")
    for ln in body:
        f.write(ln + "\n")
print("written %s  sub_shapes=%d ext=%d" % (os.path.abspath(OUT), len(shapes), len(EXT)))
