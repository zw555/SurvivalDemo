# 版本控制操作手册（写给 0 基础的你）

> 目的：让你敢改。因为**任何改动都能一键回到原样**。
> 前提：项目已经初始化好git，基线提交为 `b152b40`。

---

## 一、这是什么，为什么需要它

Godot 项目**没有编译产物**，你的文件夹就是游戏本身。好处是所有文件都是纯文本、能被追踪；
坏处是——一旦手滑删掉一个脚本，回收站里根本没有，永久丢失。

Git 就是给文件夹装了一个**可以回到任意时刻的存档系统**。

---

## 二、日常节奏：三句话

每天干活只需要这三个动作，顺序不能乱：

### 1. 开始干活前 —— 先确认干净

```bash
git status
```

输出为空 → 状态干净，可以开始改。
输出有`M` 或 `??` → 说明上次改的东西还没存档，先提交或撤销。

### 2. 改完一组功能 —— 立刻存档（最重要）

```bash
git add -A
git commit -m "简短描述这次改了什么"
```

**频率建议**：每完成一个小功能就提交一次。改数值、加物品、加一个场景各算一次。
提交信息写人话，将来能看懂，例如：
- `调整僵尸血量和移速`
- `新增绷带药品`
- `修复门关上后丧尸还能看到玩家的问题`

### 3. 改崩了 / 想反悔 —— 一键还原

```bash
# 撤销未提交的改动（Ctrl+Z 关掉 Godot 后还能用）
git restore .
```

---

## 三、回滚的四种场景

### 场景 A：改乱了，还没提交

```bash
git status                # 看哪些文件被改了
git restore scripts/player/player.gd   # 只还原单个文件
git restore .                         # 全部还原
```

### 场景 B：已经提交了，想回到上一个版本

```bash
git log --oneline                # 找到要回到的那一行的哈希值，如 b152b40
git revert <哈希值>              # 安全回退，产生一个新提交，历史不被破坏
```

**不要用** `git reset --hard`，它会抹掉历史，新手容易把自己搞晕。

### 场景 C：想看看某个文件以前长什么样（不改）

```bash
git log --oneline -- scripts/player/player.gd     # 这个文件的修改历史
git show b152b40:scripts/player/player.gd         # 看某个版本的内容
```

### 场景 D：想整个回到最初状态（危险，慎用）

```bash
git branch backup-today        # 先给现在这个状态留个分支保险
git reset --hard b152b40       # 硬回退
```

---

## 四、必须记住的几条红线

| 情况 | 后果 | 正确做法 |
|---|---|---|
| 手删了 `.godot/` 文件夹 | **没事**，引擎自动重建 | 当作没发生，重新打开 Godot |
| 手改 `.import` 文件 | 素材导入异常 | 让 Godot 自己生成，别手改 |
| 改名 / 移动 `.gd` 文件 | `.uid` 失配，全项目报错 | 在 Godot 编辑器里用 FileSystem 面板重命名 |
| 手删 `.uid` 文件 | 同上 | **绝不要删**，它们是身份证明 |
| 直接手改 `project.godot` | 设置错乱且难排查 | 只用编辑器里的 Project Settings 界面 |
| 一次改 20 个文件再提交 | 出问题无法定位 | 小步提交，每步都跑一次游戏 |

---

## 五、每次改完必须做的验证（照抄）

```bash
# 1. 语法检查（抓 GDScript 解析错误）
"E:/Godot_v4.5.2-stable_win64.exe/Godot_v4.5.2-stable_win64_console.exe" \
  --headless --path . --import

# 2. 冒烟测试（221 项断言）
"E:/Godot_v4.5.2-stable_win64.exe/Godot_v4.5.2-stable_win64_console.exe" \
  --headless --path . -s tools/smoke_test.gd
```

两项都通过 → 再 `git commit`。**测试没过绝不提交**，否则存档里存的是坏状态。

---

## 六、彻底搞坏时的救命操作

```bash
# 1. 先别慌，什么都别删，看历史
git log --oneline

# 2. 找到最后一个游戏还能跑的提交
#    （用编辑器逐个试不现实，通常就是上一次 commit）

# 3. 单文件找回
git checkout <哈希值> -- scripts/player/player.gd

# 4. 整个项目回到那个状态
git branch 抢救-<日期>
git reset --hard <哈希值>
```

只要 git 里有，你的东西就永远丢不了。这是你从今天起最大的底气。