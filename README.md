# DST Mod Publisher · macOS 版

《饥荒联机版 / Don't Starve Together》Steam 创意工坊模组上传器 —— **macOS 构建**。
Material You 风格界面 + Steamworks 引擎，开着 Steam 客户端即可一键发布/更新工坊模组。

> **macOS 版由 [Chilla](https://steamcommunity.com/id/Chilla_s_url/) 维护。**
> 原项目作者:唤月(HuanYue)· 原仓库:<https://github.com/HuanYue-NoPrediction/ConstantPublisher>
> 本仓库是在原项目基础上做 macOS 适配与修复的开源分支,遵循 GPL-3.0。

---

## 下载使用

到 [Releases](../../releases) 下载最新的 `dst_mod_publisher-macos.zip`,解压得到 `dst_mod_publisher.app`。

首次打开若被 macOS 拦（"来自身份不明的开发者"）:

```bash
xattr -dr com.apple.quarantine /path/to/dst_mod_publisher.app
```

或 右键点 app → 打开 → 再点"打开"。

运行前请确保 **Steam 客户端已登录，且账号拥有《饥荒联机版》**。

## macOS 相比原版做了什么

原版的 macOS 发布链路（作者注明"尚未实测"）在 Apple Silicon 上无法工作，本分支修复了两处:

1. **Steamworks.NET 架构标记**:其预编译 DLL 被标为 x64，arm64 进程加载器拒收（NuGet 包无 osx-arm64 版）。构建时把 PE 头 Machine 字段从 x64 改为 arm64（纯 IL，安全），使其可在 arm64 加载。见 [`helper/patch_steamworks.py`](helper/patch_steamworks.py)。
2. **AppID 识别**:macOS 上 Steam 不认环境变量，需工作目录内的 `steam_appid.txt`。helper 启动时自动切换到自身目录并生成该文件。见 [`helper/Program.cs`](helper/Program.cs)。

此外标题栏做了 macOS 适配:去掉多余的自绘窗口按钮，给系统红绿灯按钮让位。

## 自行构建

无需本地装 Flutter/Xcode——推送到本仓库即由 GitHub Actions 的 macOS 服务器自动构建，
产物在对应 workflow run 的 Artifacts 里。流程见 [`.github/workflows/build-macos.yml`](.github/workflows/build-macos.yml)。

本地构建步骤见 [`BUILD_MACOS.md`](BUILD_MACOS.md)（需 Flutter stable + 完整 Xcode + .NET 8）。

代码结构说明见 [`PROJECT_STRUCTURE.md`](PROJECT_STRUCTURE.md)。

## 许可

GPL-3.0（沿用原项目许可）。详见 [`LICENSE`](LICENSE)。

- 非 Klei / Valve 官方软件。
- *Don't Starve* 是 Klei Entertainment 商标，*Steam* 是 Valve 商标。
