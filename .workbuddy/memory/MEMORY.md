# SurvivalDemo — 项目长期备忘

## 引擎与环境
- 引擎：Godot 4.5.2 stable（GL Compatibility 渲染后端）。
- Godot 可执行文件：
  - `E:/Godot_v4.5.2-stable_win64.exe/Godot_v4.5.2-stable_win64_console.exe`（**用 console 版**，可直接拿到 stdout/stderr）
  - `E:/Godot_v4.5.2-stable_win64.exe/Godot_v4.5.2-stable_win64.exe`（无控制台输出）
- 项目根：`E:/GameProject/SurvivalDemo`，主场景固定为 `res://scenes/main/Main.tscn`。

## 验证项目改动的标准流程（每次改完必做）
1. 导入/解析检查（抓 GDScript parser error）：
   `Godot_v4.5.2-stable_win64_console.exe --headless --path <项目> --import`
2. 实跑抓 runtime error：
   `Godot_v4.5.2-stable_win64_console.exe --path <项目> --quit-after 90`
   退出码 0 且无报错即通过。
3. 需要确认「画面真的渲染出来」时，用 Movie Writer 抓帧为 PNG 序列：
   `... --write-movie "<输出目录>/shot.png" --quit-after 3`
   会生成 `shot00000000.png` 等文件（1152×648），再用 Read 工具查看图片即可。
   （注意：`.png` 后缀才会输出 PNG 序列；输出目录建议放在项目外，避免被 Godot 当资源导入。）
4. 验证实际游戏行为用冒烟测试：
   `Godot_v4.5.2-stable_win64_console.exe --headless --path <项目> -s tools/smoke_test.gd`
   新增玩法后应往里补断言，全部 PASS 才算完成。

## 约定
- **游戏设计以 `DESIGN.md` 为唯一来源**（2026-10-07 起）；已确定的设计决定不要随意推翻，新想法先写进「待定」。
- 项目状态维护在 `PROJECT_STATUS.md`（AGENTS.md §12 要求每个 Task 完成后更新）。
- 目录结构遵循 AGENTS.md 第 4 节；不为将来预留占位文件/空类。
- 保持 Godot 原生架构（Scene/Node/Script/Resource），不引入第三方插件与额外架构层。
- 修改 `project.godot` 仅在任务明确要求时进行。

## 版本控制（2026-10-13 起强制）
- 项目已 `git init`，基线提交 `b152b40`（221 项冒烟测试全过的可运行状态）。
- 详细操作说明见项目根 `GIT_WORKFLOW.md`。
- **改动纪律**：小步提交；测试通过才commit；回滚用 `git restore` / `git revert`，不用 `reset --hard`（除非已先建 `backup-*` 分支）。
- 红线：`.uid` 不可删/改名（改了用编辑器 FileSystem 面板操作）；`.godot/` 可整个删除重建；`.import` 不手改；`project.godot` 只走编辑器 Project Settings。

## 开发者画像（重要）
- **用户是 0 基础个人开发者**，自陈「有的东西微调后面改不了」，因此：
  - 讲改动风险/影响时要具体到「改坏了会怎样、能不能退回」，不能只说结论。
  - 涉及破坏性操作前先说明后果，并先建立可回滚的提交点。
  - 解释引擎概念时优先用本项目真实文件/节点树举例，而非抽象示例。

## 已知事项
- 项目根目录曾出现一个 0 字节的 `新建 文本文档.txt`（2026-09-28 13:28），来源不明，未处理。

## 引擎 API 备忘（4.5.2 实测）
- **导航烘焙**：`NavigationPolygon` 已无 source_geometry_mode/source_group_name，走 `NavigationServer2D.parse_source_geometry_data(poly, data, root_node)` + `bake_from_source_geometry_data`；**parse 会清空 data，可通行外轮廓要在 parse 之后 `data.add_traversable_outline(...)`**，否则烘焙 0 多边形。
- **class_name 不能与原生类重名**（如 Noise/Theme/Range），解析器会报 "hides a native class"。
- 物理层约定：layer1 = 实体碰撞；layer2 = 视线遮挡（静态障碍 StaticBody2D 用 collision_layer=3 同时占用两层，丧尸视线射线只查 mask 2）。
