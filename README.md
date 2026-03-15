# Minecraft Clone

使用 Godot 4.x 引擎开发的类 Minecraft 游戏。

## 项目状态

![Godot Version](https://img.shields.io/badge/Godot-4.6-blue)
![License](https://img.shields.io/badge/License-MIT-green)

## 功能特性

### 核心功能
- Perlin Noise 地形生成
- 多种方块类型（草地、泥土、石头、沙子、水、木头、树叶、圆石）
- 第一人称视角控制
- 方块挖掘与放置
- 动态区块加载

### 玩家控制
| 按键 | 功能 |
|------|------|
| W/A/S/D | 移动 |
| 空格 | 跳跃 |
| 鼠标 | 视角控制 |
| 左键 | 挖掘方块 |
| 右键 | 放置方块 |
| 1-8 | 切换方块类型 |
| Shift | 冲刺 |
| Esc | 释放鼠标 |

## 运行方式

### 方式一：Godot 编辑器
1. 下载 [Godot 4.x](https://godotengine.org/download) Mac 版本
2. 打开项目目录
3. 按 F5 运行

### 方式二：直接运行
下载 release 页面中的 ZIP 文件，解压后双击 .app 即可运行。

## 项目结构

```
minecraft-clone/
├── project.godot      # 项目配置
├── main.tscn         # 主场景
├── main.gd           # 主脚本（地形生成、玩家控制）
├── environment.tres  # 环境配置
├── save_manager.gd   # 存档管理
└── icon.svg         # 项目图标
```

## 技术细节

- **引擎**: Godot 4.6
- **渲染器**: Forward Plus
- **脚本语言**: GDScript
- **区块大小**: 16x64
- **视距**: 4 个区块
- **坐标系统**: 世界坐标（统一存储和渲染）

## 更新日志

### v1.1 (2026-03-15)
- 修复：Raycast 碰撞检测无法找到方块的问题
- 优化：统一使用世界坐标存储区块数据

## 开发计划

- [ ] 保存/加载世界
- [ ] 生物群系系统
- [ ] 更多方块类型
- [ ] 性能优化
- [ ] 合成系统

## 许可证

MIT License
