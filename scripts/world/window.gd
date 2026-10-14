class_name BuildingWindow
extends StaticBody2D
## 窗户：阻挡角色移动、允许视线穿透的最小实现。
## 关键机制：collision_layer 只占实体层 1、不占视线层 2——丧尸与玩家的
## 视线射线（mask=2）自然从玻璃穿过，而物理碰撞照常挡人。
## 墙体在窗户位置必须断开成两段独立 shape，否则整面墙会被射线绕过。
## 不可交互、无状态；不实现破窗/翻窗。

