# DST Mod Publisher 项目结构说明

这是一个 **《饥荒联机版（Don't Starve Together）》Steam 创意工坊模组上传器**。

- 界面用 **Flutter（Dart 语言）** 写，风格是 Material You（跟 FlClash 类似的现代化桌面界面）。
- 真正跟 Steam 打交道的活儿，交给一个用 **C#（.NET 8）** 写的小程序 `helper` 去做。
- 支持两种上传引擎：**Steamworks**（开着 Steam 客户端就能传，免账号密码，推荐）和 **steamcmd**（命令行工具，适合服务器/CI）。

一句话概括工作流程：
> 扫描本地模组文件夹 → 读取 `modinfo.lua` → 填写工坊标题/简介/版本 → 清洗打包内容 → 调用 helper 或 steamcmd 上传到工坊。

---

## 目录总览

```
DSTModPublisher-macos-src/
├── pubspec.yaml              项目配置（依赖、版本、资源）
├── analysis_options.yaml     Dart 代码检查规则
├── BUILD_MACOS.md            macOS 打包构建步骤
├── assets/                   图片资源
├── helper/                   C# 小程序（真正对接 Steam）
└── lib/                      Flutter 应用主体（Dart 源码）
```

---

## 📄 根目录文件

| 文件 | 作用 |
|------|------|
| **pubspec.yaml** | 项目的「身份证 + 购物清单」。定义 App 名字、版本号（0.3.14）、用到的第三方库（如 provider 状态管理、window_manager 窗口控制、shared_preferences 本地存储等）以及打包进 App 的图片资源。 |
| **analysis_options.yaml** | 代码风格检查配置。这里只加了一条：字符串统一用单引号。 |
| **BUILD_MACOS.md** | 手把手的 macOS 打包教程。告诉你怎么用 Flutter 编译出 `.app`、怎么把 C# helper 一起塞进去、怎么绕过系统安全拦截。 |

---

## 🖼️ assets/ — 图片资源

| 文件 | 作用 |
|------|------|
| **assets/icon.png** | App 图标（打包时生成 Windows 图标用）。 |
| **assets/eye.gif** | 标题栏左上角那只会动的「眼睛」小图标（饥荒风格）。 |

---

## ⚙️ helper/ — C# 助手程序（对接 Steam 的核心）

这是一个**独立的小程序**，Flutter 界面通过启动它、给它发命令、读它打印的 JSON 来完成所有 Steam 操作。之所以要单独做一个，是因为 Steam 的官方接口（Steamworks）是给 C/C++/C# 用的，Dart 直接调不了。

| 文件 | 作用 |
|------|------|
| **helper/Program.cs** | helper 的全部逻辑。根据启动参数干不同的活：<br>• 传请求文件 → **发布/更新**工坊条目（新建或更新）<br>• `list` → **拉取**你账号名下的所有工坊模组<br>• `desc` → 读取某条目的多语言标题/简介<br>• `delete` → 删除条目<br>• `apply` → 自动更新时替换程序文件<br>它以「Mod Tools（AppID 245850）」身份连接 Steam，结果用 JSON 一行行打印出来给界面读。 |
| **helper/CpSteamHelper.csproj** | helper 的项目配置（C# 版的 pubspec）。指定用 .NET 8、引用 Steamworks.NET 库、打包成单文件 exe，并把对应平台的 Steam 原生库一起带上。 |
| **helper/native/steam_api64.dll** | Windows 平台的 Steam 原生库（helper 靠它连 Steam）。 |
| **helper/native/libsteam_api.dylib** | macOS 平台的 Steam 原生库（作用同上）。 |

---

## 📱 lib/ — Flutter 应用主体

Dart 源码分成几层：入口 → 主题 → 数据模型（models） → 业务逻辑（services） → 全局状态（state） → 界面（ui）。

### lib/ 顶层

| 文件 | 作用 |
|------|------|
| **lib/main.dart** | **程序入口**。设置窗口大小、隐藏系统标题栏，初始化全局状态，然后启动 App，套上明暗主题。 |
| **lib/version.dart** | 只存一个当前版本号常量 `0.3.14`，供检查更新时对比用。 |
| **lib/theme.dart** | **外观主题**。定义 14 种主题色、字体、卡片/输入框/分割线等控件样式，以及「成功绿 / 警告黄」这类语义色。明暗两套都在这里生成。 |

### lib/models/ — 数据模型（描述「东西长什么样」）

| 文件 | 作用 |
|------|------|
| **lib/models/mod.dart** | **模组数据模型**，核心之一。包含：<br>• `ModInfo`：解析 `modinfo.lua` 里的名字、作者、版本、类型（客户端/服务端）<br>• `DstPub`：保存该模组的发布设置（AppID、可见性、标签、忽略/保留哪些文件），存成 `dstpub.json`<br>• `Mod`：把一个模组文件夹整体打包（找预览图、改版本号、存设置）<br>• 还有版本号比较、自增、推断发布通道（alpha/beta/release）等工具函数。 |
| **lib/models/eresult.dart** | **Steam 错误码翻译表**。把 Steam 返回的数字错误码（如 15、25）翻译成中文人话（如"无权限，账号是否拥有该游戏？"）。 |

### lib/services/ — 业务逻辑（描述「怎么干活」）

| 文件 | 作用 |
|------|------|
| **lib/services/stager.dart** | **上传前的「打包清洗」**。扫描模组文件夹，按规则（默认忽略 `.git`/`*.psd` 等、用户自定义、`.modignore` 文件）决定哪些文件要传、哪些跳过，复制到临时目录，并生成饥荒专用的 `mod.manifest` 资源索引。 |
| **lib/services/steamcmd.dart** | **steamcmd 上传引擎**。生成 Steam 要的 VDF 配置文件，启动 steamcmd 命令行进程上传，边读输出边解析进度、错误码、条目 ID。也定义了发布请求/事件/多语言这些公共数据结构。 |
| **lib/services/steamworks_engine.dart** | **Steamworks 上传引擎**（推荐用的那个）。把发布请求写成 JSON，启动 C# helper 去传，实时读取 helper 打印的进度和结果。 |
| **lib/services/workshop_api.dart** | **Steam 网页 API 调用**。拉取饥荒官方新闻（仪表盘公告栏用），以及通过 Web API Key 拉取账号名下的工坊条目（steamcmd 引擎下用）。也定义了「工坊条目」的数据模型。 |
| **lib/services/draft_store.dart** | **草稿自动保存**。你在发布页填的标题、简介、版本、标签等，会实时存到本地。这样上传失败或关掉软件也不会丢，下次打开自动恢复。 |
| **lib/services/updater.dart** | **软件自动更新**。检查创意工坊和 GitHub 上有没有新版本，能下载更新包、解压替换、自动重启（目前自动更新仅支持 Windows）。 |

### lib/state/ — 全局状态（App 的「大脑 / 总管」）

| 文件 | 作用 |
|------|------|
| **lib/state/app_state.dart** | **全局状态中心**，整个 App 的核心。管着所有数据和操作：当前设置、模组列表、工坊条目列表、日志、发布进度等。界面所有按钮点下去，最终都调这里的方法（扫描模组、发布、刷新、检查更新……）。改动后通知界面刷新。 |

### lib/ui/ — 界面

| 文件 | 作用 |
|------|------|
| **lib/ui/shell.dart** | **应用外壳**。左边的导航栏（仪表盘/工坊/发布/日志/设置）+ 顶部自定义标题栏（含最小化/最大化/关闭按钮、明暗切换）。根据选中项切换右侧页面。 |

#### lib/ui/pages/ — 五个主页面

| 文件 | 作用 |
|------|------|
| **lib/ui/pages/dashboard_page.dart** | **仪表盘**（首页）。显示：新版本提醒、发布环境是否就绪、饥荒官方动态、QQ 交流群、你的模组订阅数排行榜。 |
| **lib/ui/pages/workshop_page.dart** | **工坊页**。列出你账号名下的所有工坊模组，可按标签筛选，点「更新」即可跳到发布页更新该条目。 |
| **lib/ui/pages/publish_page.dart** | **发布页**（最复杂、最核心的界面）。选内容文件夹、填多语言标题/简介（带 BBCode 编辑工具栏和预览）、设版本号（可一键自增）、选可见性、加标签、换预览图、勾选本次更新哪些部分、查看将要上传的文件清单，最后点发布。含草稿自动保存。 |
| **lib/ui/pages/logs_page.dart** | **日志页**。按时间倒序显示所有操作日志（信息/警告/错误三色标签），可筛选、清空。Steam 错误码会自动翻译成中文。 |
| **lib/ui/pages/settings_page.dart** | **设置页**。切换上传引擎、设置 mods 目录、配置 steamcmd 路径和账号、填 Web API Key、换主题色和明暗模式、查看关于信息和检查更新。 |

#### lib/ui/widgets/ — 可复用的小组件

| 文件 | 作用 |
|------|------|
| **lib/ui/widgets/bits.dart** | **通用小零件合集**。如 `SectionCard`（带标题的卡片，几乎每个页面都在用）、状态徽章、文件大小格式化、弹提示条、用 Steam 客户端打开链接等。 |
| **lib/ui/widgets/bbcode.dart** | **BBCode 预览渲染器**。把 Steam 工坊用的 BBCode 标签（`[b]`加粗、`[list]`列表、`[table]`表格、`[img]`图片等）渲染成可视化效果，让你填简介时能所见即所得地预览。 |

---

## 🔗 各部分怎么协作（一次「更新模组」的流程）

1. **设置页** 选好 mods 目录 → `app_state.dart` 扫描文件夹，用 `mod.dart` 解析每个 `modinfo.lua`。
2. **工坊页** 点「从 Steam 拉取」→ `app_state.dart` 启动 helper（`Program.cs` 的 `list` 命令）→ 拿到名下条目列表。
3. 点某条目的「更新」→ 跳到 **发布页**（`publish_page.dart`），自动带出旧信息，草稿由 `draft_store.dart` 实时保存。
4. 点「发布」→ `app_state.dart` 先用 `stager.dart` 清洗打包，再交给 `steamworks_engine.dart`（或 `steamcmd.dart`）上传。
5. `steamworks_engine.dart` 启动 helper（`Program.cs`），helper 用 Steam 原生库真正把内容传上去，进度实时显示在**发布页**和**日志页**。
6. 出错时，错误码经 `eresult.dart` 翻译成中文显示；草稿保留，修好可直接重试。

---

*本文档由代码分析自动生成，用于快速了解项目结构。*
