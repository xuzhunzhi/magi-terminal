# Windows Terminal 全窗 CRT 化 —— 设计与进度

> 交接文档。目的：换机器 / 换沙箱后，能从这里继续，不用重新摸一遍。
> 最后更新：2026-11-01

---

## 1. 目标

**整个窗口看起来就是一台 CRT 显示器。**

```
┌────────────────────────────────────┐   ← 窗口边框 = 显示器外壳
│  ╭──────────────────────────────╮  │
│  │ ┌─────────┐                  │  │
│  │ │ tab 1   │                  │  │   ← 屏幕区域：曲率 / 扫描线 / 辉光
│  │ │ tab 2   │   终端内容        │  │
│  │ │ tab 3   │                  │  │
│  │ └─────────┘                  │  │
│  ╰──────────────────────────────╯  │
└────────────────────────────────────┘
```

- 外壳（斜边、高光、厚边框）＝ 窗口 chrome
- 侧边栏（标签列表）在**屏幕内部**，不是原生标签栏
- 标签列表和终端内容在同一块"屏幕"上，视觉连续

**后端保持 Windows Terminal 原样**（ConPTY、Atlas 渲染器、settings 模型全部复用），只重做前端。

---

## 2. 当前状态（2026-11-01 17:00）

| 项 | 状态 |
|---|---|
| Fork | ✅ `xuzhunzhi/terminal`（fork 自 `microsoft/terminal`） |
| 本地克隆 | ✅ `C:\Users\XuZhunzhi\terminal`（`--depth 1`） |
| 编译工具链 | ✅ MSVC 14.51.36231 / SDK 10.0.26100.0 / MSBuild 18 |
| vcpkg | ⏳ VS Installer 安装中（用户手动勾选 `Microsoft.VisualStudio.Component.Vcpkg`） |
| 首次完整编译 | ❌ 见 §6 |
| 侧边栏方案 | ✅ 已定：终端 pane 方案（§4） |

---

## 3. 上游代码结构（`main`，2026-11）

关键：**`TabStrip.xaml` 已经不存在了**，上游重构过。

```
src/cascadia/TerminalApp/
  TerminalPage.xaml          ← 窗口根布局
  TabRowControl.xaml         ← 现在的标签栏（基于 WinUI TabView）
  TabHeaderControl.xaml      ← 单个标签的渲染（可复用！）
  TitlebarControl.xaml
src/cascadia/TerminalControl/
  TermControl.xaml(.cpp)     ← 终端控件，swapchain + shader 挂在这里
```

`TerminalPage.xaml` 是 3 行网格：

```xml
<Grid.RowDefinitions>
    <RowDefinition Height="Auto" />   <!-- 0: TabRowControl -->
    <RowDefinition Height="Auto" />   <!-- 1: 一些工具条 -->
    <RowDefinition Height="*"    />   <!-- 2: 内容 -->
</Grid.RowDefinitions>
```

`TabRowControl.xaml` 用的是 WinUI 原生 `mux:TabView`：

```xml
<mux:TabView x:Name="TabView"
             CanDragTabs="True" CanReorderTabs="True"
             TabWidthMode="Equal" ... />
```

**`TabView` 只支持横向**，这是"垂直标签"必须改代码的根本原因。

---

## 4. 设计决策（已定）

### 4.1 侧边栏 = 一个终端 pane，不是 XAML 控件

WT 的 pixel shader 加在**每个终端 pane 的 swapchain** 上。所以只要侧边栏**自己就是一个 pane**，扫描线/辉光/曲率全部自动继承，不需要和 WinUI 搏斗。

```
Window
└─ 显示器外壳（XAML Border，只画边框）
   └─ Grid
      ├─ 侧边栏 pane  ← TerminalControl，同一个 shader
      └─ 主 pane      ← 终端内容
```

### 4.2 为什么不走 XAML 侧边栏

WinUI 2.8（WT 使用的版本）**没有向应用开放自定义合成效果**，XAML 层无法整体套 shader。
若侧边栏是 XAML，只能靠"琥珀色 + 像素字体 + 扫描线纹理 PNG"伪造，没有辉光、不随屏幕弯曲。

### 4.3 交互方案（分两步）

侧边栏 pane 里跑一个 TUI 画标签列表，但 TUI 需要能**切换标签**：

1. **先做**：TUI 调用 WT 自带 CLI —— `wt.exe focus-tab -t <N>`。不用改代码，验证可行性。
2. **后做**：fork 里加命名管道。`TerminalPage` 把标签增删/标题/激活状态推给侧边栏进程，侧边栏回发切换命令。这是最终形态。

### 4.4 侧边栏 pane 的约束（fork 要处理）

- 不可关闭（默认 `Ctrl+Shift+W` 能关掉 pane）
- 不可移动/拖动到别的窗口
- 窗口重建时自动恢复
- 需要标记为"系统 pane"，与用户手动分的 pane 区分

---

## 5. 参考实现

`microsoft/intelligent-terminal`（MIT，微软自家的 WT fork，2.1k★）有一整套侧边栏，**可以照抄结构**：

```
src/cascadia/TerminalApp/TabStrip.xaml              ← 侧边栏布局（94KB）
src/cascadia/TerminalApp/SidebarLayoutResources.xaml ← 度量/样式
src/cascadia/TerminalApp/TabHeaderControl.xaml       ← 每行渲染（上游也有）
src/cascadia/TerminalApp/TabListViewModel.h          ← 列表模型
```

关键片段：

```xml
<mux:TreeView x:Name="SidebarTree">
    ...
    <local:TabHeaderControl x:Name="TabHeaderPresenter" />
```

**注意**：它的侧边栏和 agent 会话耦合（`SidebarFilters.ShowAgentsOnly` 等），并且**侧边栏代码是 2026-10 底才进 main 的，最新发布 v0.2.2572（09-14）里没有**。所以不能直接装来用，只能当源码参考。

它还有 `tools/wta`（Rust crate + helper 服务）一整套 agent 依赖，剥离成本不低。

---

## 6. 编译

### 6.1 一次性准备

```powershell
cd $env:USERPROFILE\terminal
git submodule update --init --recursive

Import-Module .\tools\OpenConsole.psm1
Set-MsBuildDevEnvironment        # 会自动下载 VSSetup 模块到 .PowershellModules
```

### 6.2 编译命令

```powershell
# 只编终端本体，避开 vtapp / UIA.Tests（它们需要 .NET Framework 4.7.2 目标包）
msbuild OpenConsole.slnx /p:Configuration=Release /p:Platform=x64 /t:Terminal\CascadiaPackage /m
```

或走便捷函数（会先 nuget restore）：

```powershell
Invoke-OpenConsoleBuild /p:Configuration=Release /p:Platform=x64 /m /v:m
```

### 6.3 已知阻塞

| 错误 | 原因 | 解法 |
|---|---|---|
| `MSB4019: 找不到 dep\vcpkg\scripts\buildsystems\msbuild\vcpkg.props` | VS 没装 vcpkg 组件，`dep\vcpkg` 也不存在 | VS Installer 勾选 **C++ vcpkg 包管理器** |
| `MSB3644: 找不到 .NETFramework,Version=v4.7.2` | 缺目标包 | 只影响 `vtapp`/`UIA.Tests`，只编 `CascadiaPackage` 可绕过；要全编就装 .NET 4.7.2 Developer Pack |

`common.build.pre.props:289-290` 决定 vcpkg 位置：

```xml
<VcpkgRoot Condition="'$(VcpkgRoot)'==''">$(VsInstallRoot)\VC\vcpkg</VcpkgRoot>
<VcpkgRoot Condition="'$(VcpkgRoot)'=='' or !Exists('$(VcpkgRoot)\vcpkg.exe')">$(SolutionDir)\dep\vcpkg</VcpkgRoot>
```

> ⚠️ 不要尝试 `git clone microsoft/vcpkg` + bootstrap：bootstrap 要从 github.com 下 vcpkg.exe，这台机器直连 github.com 不通（只有 `api.github.com` 和 SSH 可用）。

---

## 7. 网络限制（换沙箱后仍适用）

| 目标 | 可用性 |
|---|---|
| `github.com` HTTPS | ❌ 超时 |
| `github.com` SSH（`git@github.com:`） | ✅ |
| `api.github.com` | ✅（`gh` CLI 正常） |
| `download.visualstudio.microsoft.com` | ✅ |
| `pkgs.dev.azure.com`（WT 的 nuget 源） | ✅ |
| `download.microsoft.com`（VS 组件清单） | ✅ |

git 全局已配置：`git config url."git@github.com:".insteadOf "https://github.com/"`（仅 `terminal` 仓库内）。

---

## 8. 接下来的任务（按顺序）

1. [ ] VS Installer 装完 vcpkg 组件 → 验证 `C:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\vcpkg\vcpkg.exe`
2. [ ] 编译原版 `CascadiaPackage`，确认能出包、能运行（**不改一行代码**）
3. [ ] 手动验证 pane 侧边栏：用 `split-pane` 左开一个 pane 跑任意 TUI，确认**它有 CRT 效果**（这是方案成立的前提）
4. [ ] 原型：写侧边栏 TUI（列标签 + 回车切换），用 `wt focus-tab` 打通
5. [ ] fork 改动：根布局（外壳 Border + Grid[sidebar|content]）
6. [ ] fork 改动：侧边栏 pane 的"系统 pane"约束
7. [ ] 外壳视觉：边框层、高光、圆角，与 shader 曲率对齐
8. [ ] 统一：像素字体、琥珀配色、选中态

---

## 9. 已有的相关工作（本仓库）

- `shaders/cool-retro-frame-*.hlsl`：CRT 着色器，`-lite` 版是性能优化版（174 → 20 次纹理采样）
- `scripts/setup-magi-terminal.ps1`：一键装字体 / shader / profile
- `README.md`：安装说明、性能对比、CJK 标点处理

配套的环境侧改动（不在仓库里，换机器时注意）：

| 文件 | 作用 |
|---|---|
| `scripts/MagiPrompt.ps1`（本仓库已附带） | 提示符、`[magi]` 前缀、问候语、`uu` 命令、**UTF-8 编码修正** |
| `~\Documents\PowerShell\MagiPrompt.ps1` | 上面那份的安装位置（PS7） |
| `~\Documents\PowerShell\Microsoft.PowerShell_profile.ps1` | PS7 入口，dot-source 上面的文件 |
| `~\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1` | PS 5.1 入口 |
| WT `settings.json` | 两个 MAGI profile、`startingDirectory`、主题 |

**编码问题**（曾经让 MSBuild 中文全是 `鎵句笉鍒`）：控制台默认 936/GBK，而工具输出 UTF-8。
修法写在 `MagiPrompt.ps1` 里：把 `[Console]::InputEncoding/OutputEncoding` 和 `$OutputEncoding` 都设成 UTF-8，并 `chcp 65001`。

---

## 10. 合规边界

`microsoft/terminal` 有 `AGENTS.md`（AI 使用政策），对**公开贡献**有严格限制：

- ❌ 禁止 AI 撰写的 GitHub 评论 / PR / commit（含 `Co-authored-by`）
- ✅ 允许"保持非公开"的 AI 使用，例如本地实验
- ✅ 小型、局部 bug 修复（单文件/单函数）且人工理解并验证

**本工作的定位**：个人 fork、本地修改、自用，属于 non-public local experiments，允许。
**不要**把这里的 AI 生成代码直接提到 `microsoft/terminal` 上游。
