<p align="center">
  <a href="README.md">English</a> | <a href="README.zh.md">中文</a>
</p>

# Ghostty Blackhole - Windows Terminal 移植版

![Ghostty Blackhole 演示](demo.gif)

在 Windows Terminal 中运行一个光线追踪黑洞。本 Fork 将原版
[ghostty-blackhole](https://github.com/s0xDk/ghostty-blackhole) 移植到 Windows
Terminal 的 HLSL 像素着色器接口，并保留原有的 Ghostty GLSL 文件。

Windows 版目前提供两个稳定尺寸方案：Codex 上下文追踪版和固定尺寸版。此前的
Windows Terminal 番茄钟实现保留为实验性旧版，因为 Terminal 提供给 shader 的
`Time` 值可能重置或跳跃。

## Windows Terminal 版本

| 文件 | 行为 | 是否需要辅助脚本 | 建议用途 |
|------|------|------------------|----------|
| `blackhole.hlsl` | 当前 Codex 会话的上下文占用越高，黑洞越大 | `tools/Watch-CodexContext.ps1` | 默认上下文模式 |
| `blackhole.fixed.hlsl` | 恒定保持在配置最大尺寸的约 80% | 否 | 稳定常驻效果 |
| `blackhole.pomodoro.hlsl` | 旧的计时成长/休息循环 | 可选旧 helper | 仅供实验 |

`blackhole.glsl` 仍是原版 Ghostty shader，保留 Ghostty 特有的番茄钟、Token 和演示模式。

## 功能

- 光线追踪黑洞阴影和光子环
- 对终端内容进行引力透镜弯曲
- 带相对论多普勒致亮的吸积盘
- Windows Terminal 下追踪 Codex 上下文窗口
- 无需后台脚本的固定尺寸 Windows Terminal 版本
- HLSL 源码中保留 42 秒演示模式

## 快速开始：固定尺寸版

在 Windows Terminal `settings.json` 中直接指向 `blackhole.fixed.hlsl`：

```json
"profiles": {
    "defaults": {
        "experimental.pixelShaderPath": "C:\\path\\to\\blackhole.fixed.hlsl"
    }
}
```

保存设置，然后在命令面板运行“切换终端视觉特效”。黑洞将恒定保持在
`FIXED_SIZE_RATIO`（默认 `0.8`）对应的最大尺寸比例。尺寸保持不变，但黑洞位置会像其他版本一样
自由移动，吸积盘物质也会继续运动。

## 快速开始：Codex 上下文版

Windows Terminal shader 无法直接读取 Codex 状态。辅助脚本会监听 Codex session 日志，
把当前上下文占用写入 `%USERPROFILE%\.terminal` 下生成的 HLSL 文件，并在两个生成文件之间
切换 `experimental.pixelShaderPath`，让 Windows Terminal 重新加载数值。

先确认 profile 的 `defaults` 中已经存在该配置。辅助脚本只更新现有属性，不会自动插入缺失属性：

```json
"profiles": {
    "defaults": {
        "experimental.pixelShaderPath": "C:\\path\\to\\blackhole.hlsl"
    }
}
```

先在 PowerShell 中进入仓库根目录：

```powershell
cd C:\path\to\ghostty-blackhole-for-windows
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Watch-CodexContext.ps1 -Status
```

相对形式的 `-File` 路径只在仓库根目录有效。如果当前目录不是仓库，请使用完整路径：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\ghostty-blackhole-for-windows\tools\Watch-CodexContext.ps1" -Status
```

使用 Codex 时保持这个 PowerShell 进程运行。默认无输出，添加 `-Status` 才会打印状态。
按 `Ctrl+C` 停止；默认会恢复启动脚本前使用的 shader 路径。

常用参数：

| 参数 | 作用 |
|------|------|
| `-Status` | 显示 session id、Token 用量、上下文比例和生成文件 |
| `-Once` | 只读取并生成一次，然后退出 |
| `-NoSettingsUpdate` | 只生成 HLSL，不修改 Terminal 设置 |
| `-NoRestoreOnExit` | 退出后保留生成 shader 的路径 |
| `-TemplatePath` | 指定另一份上下文模式 HLSL 模板 |
| `-OutputDirectory` | 修改生成 shader 的目录 |

脚本读取最新 `token_count` 事件，按 `total_tokens / model_context_window` 计算并限制在
0-100%。Codex 的 Token 总数已经包含缓存输入，不会再重复叠加 `cached_input_tokens`。

## 调参

编辑所选 HLSL 文件顶部的常量，然后重新加载 shader。

| 常量 | 作用 |
|------|------|
| `HOLE_RADIUS` | 基础黑洞阴影半径 |
| `MAX_SIZE_SCALE` | 上下文满时的尺寸倍率，默认 `1.3` |
| `FIXED_SIZE_RATIO` | 固定版占最大尺寸的比例，默认 `0.8` |
| `CONTEXT_GROW_EASE` | 上下文版成长曲线 |
| `CONTEXT_DEBUG_BAR` | 是否显示屏幕顶部的上下文占用诊断条（默认关闭） |
| `WORK_AREA` | 屏幕底部不受扭曲的区域比例 |
| `N_STEPS` | 每像素测地线积分步数，也是主要性能参数 |

## 验证

可以在本机编译检查任意 Windows Terminal shader：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-HlslCompile.ps1 -Path .\blackhole.hlsl
```

把路径换成 `blackhole.fixed.hlsl` 或 `blackhole.pomodoro.hlsl` 即可测试其他版本。

## Ghostty

需要 Ghostty 1.3+。在 `~/.config/ghostty/config` 中加入：

```ini
custom-shader = /path/to/blackhole.glsl
custom-shader-animation = true
```

`claude-token.py` 是原有的 Ghostty Token 模式辅助脚本，与 Windows Terminal 上下文 helper 相互独立。

## 文件说明

| 文件 | 说明 |
|------|------|
| `blackhole.hlsl` | Windows Terminal 上下文模式模板 |
| `blackhole.fixed.hlsl` | Windows Terminal 固定 0.8x 版本 |
| `blackhole.pomodoro.hlsl` | 旧的实验性 Windows 计时版本 |
| `tools/Watch-CodexContext.ps1` | Codex 上下文监听与 shader 生成脚本 |
| `tools/Start-PomodoroHelper.ps1` | 旧番茄钟 shader 的可选辅助脚本 |
| `tools/Test-HlslCompile.ps1` | 本地 HLSL 编译检查 |
| `blackhole.glsl` | 原版 Ghostty shader |
| `claude-token.py` | Ghostty Token 模式辅助脚本 |

## 许可证

MIT，参见 [LICENSE](LICENSE)。

灵感来自 [Eric Bruneton 的黑洞 shader](https://github.com/ebruneton/black_hole_shader)
（BSD-3-Clause）。本 shader 是独立实现的屏幕空间近似。
