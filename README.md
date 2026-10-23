# LifeLog（朝夕册）· 个人生活管理 App

自用的个人生活管理 App：**财务管理 + 健康记录 + 外语学习 + AI 助手**。

**数据全部存在手机本地**，除 AI 对话与识图外，所有功能完全离线可用。

> 当前版本：**v0.3.1**（`pubspec.yaml`：`0.3.1+1`）
> 产品与技术方案见 [docs/技术方案.md](docs/技术方案.md)；
> 当前完成度、已知限制与交接说明见 [docs/项目进度.md](docs/项目进度.md)。

## 功能

| 模块 | 能力 |
|---|---|
| 财务管理 | 分类记账、转账、**资产 / 投资 / 负债三类账户**与净资产、投资市值与盈亏、月度预算、**周 / 月 / 年账单**（横滑周期条）、收支趋势与分类占比、收支排行、流水筛选、**支付截图识图记账** |
| 健康管理 | 体重 / 体脂、多部位围度（**综合 2×3 视图 + 雷达图 / 六线对比**）、运动记录、周 / 月 / 年趋势对比、BMI |
| 外语学习 | 内置 **CET-4 / CET-6 / 考研英语 / IT 行业必备词汇** 四本词库（共 13,775 词）、间隔重复（SRS）背词、**看释义拼写 / 听音拼写测验**、词库批量导入、TTS 发音、学习与测验统计 |
| AI 助手 | 「小朝」多轮对话、流式输出、Markdown 渲染、**按住说话（松手直接发送）**、17 个 Function Calling 工具读写本地数据（含删除账户）、识图草稿、用户与助手消息均可复制 |
| 外观 | 6 种主题色（晨绿 / 海蓝 / 靛紫 / 暖橙 / 玫红 / 青碧），即时生效并持久化，跟随系统深色模式 |
| 安全与备份 | PIN / 指纹解锁、启动免 PIN、AES-256-GCM 加密备份包导出导入 |
| 数据管理 | **回收站**（恢复 / 彻底删除 / 清空，词库级联）、**CSV 导出**（流水 / 体重 / 围度 / 运动 / 学习 / 测验） |

## 下载安装

### Android

安装包通过 [GitHub Releases](https://github.com/Jules-jl-l/lifelog/releases) 发布，不放进源码仓库（避免仓库体积随版本膨胀）。
文件名规则为 `lifelog-v<版本>.apk`，按需下载：

| 版本 | 安装包 | 大小 | 说明 |
|---|---|---|---|
| **v0.3.1** | [lifelog-v0.3.1.apk](https://github.com/Jules-jl-l/lifelog/releases/download/v0.3.1/lifelog-v0.3.1.apk) | 约 67 MB | 当前版本，通用包（arm64-v8a / armeabi-v7a / x86_64） |

- 历史版本同样在 [Releases](https://github.com/Jules-jl-l/lifelog/releases) 页面下载。
- **v0.3.0 的安装包因语音识别缺陷已下架**，请使用 v0.3.1。
- 支持 **Android 7.0（API 24）及以上**；包含三种 ABI，真机与模拟器都能装。
- 下载后用文件管理器打开安装；首次安装需允许「安装未知来源应用」。
- 安装包使用 **debug 签名**，开源自用，直接安装即可。
- 升级时直接覆盖安装即可，本地数据会保留（数据库版本会自动迁移）。

### iOS

iOS **不提供预编译安装包**。受 Apple 签名机制限制，`.app` / `.ipa` 无法像 APK 一样直接发给普通用户安装，而且必须在 macOS + Xcode 上构建并签名。

因此项目对 iOS 只提供 **源码与构建文档**，需要自行编译安装：

- 构建步骤见下文 [iOS](#ios)。
- 用免费 Apple ID 即可安装到自己的设备（7 天有效，到期重新签名即可）。
- 需要 iOS 版的人自行编译安装。
- 当前 iOS 端**尚未经过真机验证**，暂不建议直接在日常主力机上使用。

## 技术栈

- **框架**：Flutter 3.47（Dart 3.13），Android + iOS（iOS 工程已配置，**尚未经过 iOS 真机验证**）
- **本地存储**：Drift（SQLite），无服务端、无账号体系
- **状态管理**：Riverpod 3（导航使用原生 Navigator）
- **图表**：fl_chart；**Markdown**：flutter_markdown_plus；**语音**：speech_to_text
- **AI**：DeepSeek 直连（`deepseek-chat` 文本 + `deepseek-flash` 识图）
- **隐私**：PIN / 指纹（local_auth）+ 加密备份包（AES-256-GCM + PBKDF2）

## 目录结构

```
LifeLog/
├─ README.md
├─ LICENSE
├─ .gitignore
├─ docs/
│  ├─ 技术方案.md          # 产品与技术方案
│  └─ 项目进度.md          # 完成度、兼容性结果、已知限制与交接
├─ scripts/
│  └─ scan_secrets.py      # 提交前密钥扫描（pre-commit）
├─ app/                    # Flutter 工程
│  ├─ lib/
│  │  ├─ main.dart / app.dart
│  │  ├─ core/             # 主题、周期、金额/时间、加密
│  │  ├─ data/             # Drift、仓库、统计、AI、备份
│  │  ├─ features/         # finance / health / study / ai / lock / settings / home
│  │  └─ shared/           # 图表、统计卡、周期横滑条
│  ├─ assets/branding/
│  ├─ assets/wordlists/     # CET-4 / CET-6 / 考研 / IT 四本词库 JSON
│  ├─ android/
│  └─ ios/                  # iOS 工程（Bundle ID com.lifelog.lifelog，iOS 15.0）
├─ testcases/              # 本地维护的用例与自动化（已忽略，不入库）
└─ .verify/                # 本地测试截图（已忽略，不入库）
```

## 开发环境

| 组件 | 版本要求 | 本机现状 |
|---|---|---|
| Flutter SDK | 3.x stable | 3.47.7（`D:\apps\flutter`） |
| JDK | 17（不要用 8） | `D:\apps\Java\jdk-17` |
| Android SDK | 含 `cmdline-tools` + platform + build-tools | SDK 37.0.0 |

当前状态：`flutter analyze` 无告警，291 个自动化测试通过（测试代码在本地 `testcases/`，不随仓库发布）。

### 国内网络下的两个必要适配

若 `github.com` 与 `maven.google.com` 不可达，构建会直接失败。仓库已内置以下适配：

1. **Gradle 镜像**：`android/settings.gradle.kts` 与 `android/build.gradle.kts` 优先使用
   `https://dl.google.com/dl/android/maven2`（Google 官方 CDN），绕开被墙的 `maven.google.com`。
2. **sqlite3 预编译库镜像**：`pubspec.yaml` 的 `hooks.user_defines.sqlite3.url_pattern`
   把下载地址指向 GitHub 加速镜像。**若你的网络能直连 GitHub，删掉这段 `hooks` 即可。**
   注意不要用 `dependency_overrides` 把 `sqlite3` 降到 2.x —— drift 依赖 3.x 的 API，会编译失败。

另：本机用 `curl` 下载大文件若报 `CRYPT_E_REVOCATION_OFFLINE`，加 `--ssl-no-revoke`。

## 快速开始

```bash
cd app
flutter pub get
flutter run
```

本机 `flutter` 不在 PATH 时，可用 dart snapshot（`cwd` 必须是 `app/`）：

```powershell
$dart = "D:\apps\flutter\bin\cache\dart-sdk\bin\dart.exe"
$snap = "D:\apps\flutter\bin\cache\flutter_tools.snapshot"

& $dart $snap pub get
& $dart $snap analyze
& $dart $snap build apk --release --target-platform android-x64
```

首次运行后，进入「我的 → DeepSeek API Key」填写自己的 **DeepSeek API Key**
（只存本机 Android Keystore / iOS Keychain，不写入代码、不进入仓库）。未配置时 AI 降级为本地规则记账。

### 打包说明

- 模拟器（x86_64）：`flutter build apk --release --target-platform android-x64`
- 真机（ARM）：去掉 `--target-platform`，或显式 `android-arm64`
- 当前 release 包使用 debug 签名（`CN=Android Debug`），直接安装使用即可
- minSdk 24 / targetSdk 36；已确认 arm64-v8a、armeabi-v7a、x86_64 三套 ABI 与 16KB 页对齐

### iOS

> ⚠️ **iOS 工程已完成配置，但尚未经过 iOS 真机验证。** 本仓库**不提供 iOS 安装包**（`.ipa` / `.app`），只提供源码与构建文档，需要自行在 macOS 上编译并签名。以下内容为代码与工程层面的适配，
> 需要在 macOS + Xcode 中构建并在 iPhone / iPad 上逐项验证后才能认为 iOS 端可用。

- 工程：`app/ios`，Bundle ID `com.lifelog.lifelog`，部署目标 **iOS 15.0**
- 显示名「朝夕册」；已配置 `NSFaceIDUsageDescription`、`NSMicrophoneUsageDescription`、
  `NSSpeechRecognitionUsageDescription`、`NSPhotoLibraryUsageDescription`
- AppIcon 已替换为品牌图标；iPad 分享面板已补 `sharePositionOrigin` 锚点
- 锁屏在 iOS 上显示「面容 ID 解锁」；TTS 使用 `playback` 音频会话（静音开关下也能发音）
- 深色模式锁屏 / 启动页已显式设置状态栏图标颜色
- 卸载重装时按安装标记清理 Keychain 残留 PIN / API Key（老版本升级会保留原凭据）
- 需要在 **macOS + Xcode** 上构建（Windows 无法编译 iOS）：

```bash
cd app
flutter pub get
cd ios && pod install && cd ..
open ios/Runner.xcworkspace   # 在 Xcode 选择自己的 Apple ID Team 后运行到设备
```

> 首次在 Mac 构建时请验证：Face ID / Touch ID 解锁、按住说话权限与语音输入、
> 相册识图、备份与 CSV 分享到「文件」App、TTS 发音、卸载重装后的引导流程，
> 以及真机上的 SQLite 数据目录读写。

## 测试

测试用例、自动化脚本与截图属于本地验证资产，已通过 `.gitignore` 排除：

- `testcases/test-cases.md`：267 条用例
- `testcases/test-report.md`：执行报告、兼容性矩阵、缺陷清单
- `testcases/automation/`：31 个测试文件 / 291 个测试

运行方式（`cwd=app/`）：

```powershell
Get-Process dart, flutter_tester -ErrorAction SilentlyContinue | Stop-Process -Force
& $dart $snap test ..\testcases\automation --reporter compact
```

改数据表后重新生成 Drift 代码：

```powershell
& $dart run build_runner build --delete-conflicting-outputs
```

## 数据与隐私

- 数据只存在手机本地 SQLite，不经过任何自建服务端，也不上传第三方
- 支持 PIN / 指纹解锁；后台超过 5 分钟回前台需重新解锁
- 支持**导出 / 导入加密备份包**（自设密码），换机时用它迁移
- PIN 与 API Key 不在备份包内（存 Android Keystore / iOS Keychain），换机后需重新设置

> ⚠️ **数据只有一份，请定期导出备份。** 换机、丢机或误删且无备份时无法找回；
> 备份密码一旦遗忘，备份包也无法解开。

## 开源与保密

仓库中**不包含任何真实凭据与个人数据**：

- DeepSeek API Key 由使用者在 App 内自行填写，存 `flutter_secure_storage`（Android Keystore / iOS Keychain）
- 签名文件（`*.jks` / `*.keystore` / `key.properties`）、`.env`、本地数据库与备份包均已排除
- 测试用例与截图（`testcases/`、`.verify/`）仅在本地保留，不进入仓库
- 提交前由 `pre-commit` 钩子运行 `scripts/scan_secrets.py` 拦截疑似真实密钥：

  ```bash
  pip install pre-commit && pre-commit install
  ```

- 若密钥曾进入历史提交，请**立即到服务商后台轮换该 Key**，再用 `git filter-repo` 清理历史

## 历史变更

### v0.3.1（2026-10-23）

- 修复真机语音**只识别第一句**、或松手提示「没听清」：改为单次识别会话，并在松手后等待最终识别结果再发送
- 长按语音增加震动反馈：开始拾音中震、进出取消区轻震、松手取消重震
- **下架 v0.3.0 安装包**：该版本语音存在缺陷，请使用 v0.3.1

### v0.3.0（2026-10-23）

- 完成 iOS 工程适配（权限文案、品牌图标、Podfile、面容 ID、TTS 音频会话、状态栏、Keychain 重装清理），**尚未经过 iOS 真机验证**
- AI 助手支持删除账户，用户消息也可复制
- 语音改为松手直接发送

### v0.2.0（2026-10-22）

- 四本内置词库（13,775 词）、拼写 / 听写测验、回收站、CSV 导出
- 围度综合视图（雷达图 / 六线对比）
- 资产 / 投资 / 负债三类账户与净资产口径

### v0.1.0（2026-10-20）

- 首个开源版本：财务、健康、学习、AI 助手、主题色、PIN / 生物识别、加密备份

## 版本与路线

| 版本 | 状态 | 范围 |
|---|---|---|
| **v0.1.0** | 历史版本 | 工程骨架 + 财务 + 健康 + 学习 + AI 助手（流式 / Markdown / 语音 / 16 工具 / 识图 / 离线队列）+ 主题色 + PIN / 指纹 + 加密备份；兼容性验证完成 |
| **v0.2.0** | 历史版本 | 四本内置词库（13,775 词）、拼写 / 听写测验、回收站、CSV 导出、AI 豆包式对话与按住说话、围度综合视图（雷达图 / 六线对比）、资产 / 投资 / 负债三类账户与净资产口径；schema v5 |
| **v0.3.0** | 历史版本 | iOS 工程适配（**未经 iOS 真机验证**）、AI 删除账户与用户消息复制、语音松手直发；**安装包已因语音缺陷下架** |
| **v0.3.1** | 当前版本 | 修复语音只识别第一句 / 松手「没听清」；长按语音震动反馈（开始中震、取消区轻震、取消重震）；291 个自动化测试通过 |
| **iOS 真机验证** | 待进行 | `app/ios` 工程、权限文案、品牌图标、Podfile（iOS 15.0）已就绪；需 macOS + Xcode 构建并在 iPhone / iPad 上验证 |
| 后续 | 计划 | iOS 真机验证、ARM64 真机包验证 |

> 版本号以 `app/pubspec.yaml` 的 `version` 为准，当前为 `0.3.1+1`（显示版本 v0.3.1，构建号 1）。

## 许可证

[MIT](./LICENSE)
