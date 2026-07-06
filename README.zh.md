# Ghostty Blackhole — Windows Terminal 移植版

![Ghostty Blackhole 演示](demo.gif)

在你的终端里运行一个光线追踪黑洞 — 现已支持 **Windows Terminal**。

本 Fork 将原版 [ghostty-blackhole](https://github.com/s0xDk/ghostty-blackhole)
移植到 Windows Terminal 的 HLSL 像素着色器接口，同时保留了原版的 Ghostty GLSL 着色器。

黑洞实时积分 Schwarzschild 度规下的零测地线 — 黑洞附近的每个像素都追踪自己的光子路径。
你的终端内容就是被引力透镜弯曲的背景天空。

## 功能

- **光线追踪黑洞阴影** — `b_crit` 以下的光子螺旋坠入视界；黑洞后面的文字真的消失了
- **引力透镜** — 文字在爱因斯坦环内弯曲、放大、镜像；远处平滑过渡到弱场近似
- **吸积盘** — Shakura-Sunyaev 温度分布、相对论多普勒致亮、开普勒轨道条纹；星际穿越同款
- **光子环** — `1.5 r_s` 光子球附近的光子自然形成的明亮细环
- **引力时间膨胀** — 内轨随黑洞增长而冻结
- **番茄钟模式** — 黑洞在 `WORK_PERIOD_MIN`（默认 45 分钟）内逐渐长大，`BREAK_MIN`（默认 5 分钟）内保持最小
- **演示模式** — 42 秒自动循环展示所有吸积盘预设

## 支持的平台

| 平台 | 文件 | 状态 |
|------|------|------|
| **Windows Terminal**（Windows 10 22H2+、Windows 11） | `blackhole.hlsl` | ✅ 完整支持（番茄钟 + 演示） |
| **Ghostty**（macOS、Linux） | `blackhole.glsl` | ✅ 完整支持（番茄钟 + Token + 演示） |

> **Token 模式**（Claude Code 上下文窗口追踪）仅限 Ghostty —
> Windows Terminal 的着色器无法访问光标颜色变量。

## 快速开始（Windows Terminal）

1. 克隆本仓库，记下 `blackhole.hlsl` 的路径。

2. 编辑 Windows Terminal 的 `settings.json`（`Ctrl+,` → "打开 JSON 文件"），
   在 profile 的 `defaults` 中添加：

   ```json
   "profiles": {
       "defaults": {
           "experimental.pixelShaderPath": "C:\\path\\to\\blackhole.hlsl"
       }
   }
   ```

3. 保存，然后按 `Ctrl+Shift+P` → **"切换终端视觉特效"**。
   或在 `actions` 中绑定快捷键：

   ```json
   { "command": "toggleShaderEffects", "keys": "ctrl+shift+b" }
   ```

## 快速开始（Ghostty）

需要 Ghostty 1.3+。在 `~/.config/ghostty/config` 中添加：

```ini
custom-shader = /path/to/blackhole.glsl
custom-shader-animation = true
```

重新加载配置（`cmd+shift+,`）或打开新窗口。

## 番茄钟模式

工作时黑洞始终存在 — 从最小开始，在 `WORK_PERIOD_MIN`（默认 45 分钟）内逐渐长大，
最后一分钟坍缩，在 `BREAK_MIN`（默认 5 分钟）内保持最小。
Ghostty 使用墙钟时间锚定；Windows Terminal 使用 `Time`（从着色器启动开始的秒数）。

## 尺寸模式

在 `blackhole.glsl` / `blackhole.hlsl` 顶部设置 `SIZE_MODE`：

- **`MODE_POMODORO`**（默认）— 自包含番茄钟计时器
- **`MODE_DEMO`** — 42 秒展示循环，适合录制和测试
- **`MODE_TOKENS`** — 仅 Ghostty；跟踪 Claude Code 上下文窗口占用

### 演示模式

黑洞在 40 秒内从种子大小生长到最大，同时吸积盘外观循环切换 8 个预设
（Inferno → Gargantua → M87\* 甜甜圈 → Face-on ember → Quasar →
Blazar → Pure lens → Inferno），每约 5 秒交叉淡入淡出。

## 调参

编辑着色器文件顶部的常量，然后重新加载着色器。

| 常量 | 作用 |
|------|------|
| `HOLE_RADIUS` | 最大时阴影半径（占屏幕高度的比例） |
| `LENS_DEPTH` | 透镜强度 — 越大文字弯曲越厉害 |
| `STAR_GAIN` | 星场亮度（0 = 关闭） |
| `DISK_INNER` / `DISK_OUTER` | 吸积盘内外边缘（`r_s` 单位） |
| `DISK_INCL` / `DISK_ROLL` | 吸积盘倾角和旋转（弧度） |
| `DISK_TEMP` | 最热环的色温（开尔文） |
| `DISK_GAIN` / `DISK_OPACITY` | 吸积盘亮度和不透明度 |
| `DOPPLER_MIX` / `DISK_BEAM` | 相对论颜色/致亮强度 |
| `DISK_SPEED` / `DISK_WIND` / `DISK_CONTRAST` | 轨道条纹 |
| `EXPOSURE` | 吸积盘光照的色调映射曝光 |
| `DRIFT_SPEED` | 黑洞飘移速度 |
| `WORK_AREA` | 屏幕底部保持不变形的区域比例 |
| `DILATION_MIN` | 最大时的引力时间膨胀 |
| `WORK_PERIOD_MIN` | 番茄钟工作时长（分钟） |
| `BREAK_MIN` | 番茄钟休息时长（分钟） |
| `TIME_SCALE` | 测试用：>1 倍速快进（如 100 约 27 秒一个周期） |

`N_STEPS`（`#define`）是每像素测地线积分步数 — 主要性能调节参数。
如果终端卡顿，可以降低此值。

## 文件说明

| 文件 | 说明 |
|------|------|
| `blackhole.glsl` | 原版 Ghostty 着色器（GLSL，全部模式） |
| `blackhole.hlsl` | Windows Terminal 着色器（HLSL，番茄钟 + 演示） |
| `claude-token.py` | Token 模式辅助脚本（仅 Ghostty） |
| `tuner/` | macOS SwiftUI 调参应用（仅 Ghostty） |

## 许可证

MIT — 参见 [LICENSE](LICENSE)。

灵感来自 [Eric Bruneton 的黑洞着色器](https://github.com/ebruneton/black_hole_shader)
（BSD-3-Clause）。本着色器是独立实现的屏幕空间近似，从头编写。
