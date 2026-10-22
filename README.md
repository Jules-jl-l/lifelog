# LifeLog（朝夕册）· 个人生活管理 App

自用的个人生活管理 App：**财务管理 + 健康记录 + 外语学习 + AI 助手**。

**数据全部存在手机本地**，除 AI 对话与识图外，所有功能完全离线可用。

> 当前版本：**v0.1.0**（`pubspec.yaml`：`0.1.0+1`）
> 产品与技术方案见 [docs/技术方案.md](docs/技术方案.md)；
> 当前完成度、已知限制与交接说明见 [docs/项目进度.md](docs/项目进度.md)。

## 功能

| 模块 | 能力 |
|---|---|
| 财务管理 | 分类记账、转账、账户与资产、月度预算、**周 / 月 / 年账单**（横滑周期条）、收支趋势与分类占比、收支排行、流水筛选、**支付截图识图记账** |
| 健康管理 | 体重 / 体脂、多部位围度、运动记录、周 / 月 / 年趋势对比、BMI |
| 外语学习 | 内置英语词库、间隔重复（SRS）背词、词库批量导入、TTS 发音、学习统计 |
| AI 助手 | 「小朝」多轮对话、流式输出、Markdown 渲染、语音输入、16 个 Function Calling 工具读写本地数据、识图草稿 |
| 外观 | 6 种主题色（晨绿 / 海蓝 / 靛紫 / 暖橙 / 玫红 / 青碧），即时生效并持久化，跟随系统深色模式 |
| 安全与备份 | PIN / 指纹解锁、启动免 PIN、AES-256-GCM 加密备份包导出导入 |

## 技术栈

- **框架**：Flutter 3.47（Dart 3.13），单端 Android
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
│  └─ android/
├─ testcases/              # 本地维护的用例与自动化（已忽略，不入库）
└─ .verify/                # 本地测试截图（已忽略，不入库）
```

## 开发环境

| 组件 | 版本要求 | 本机现状 |
|---|---|---|
| Flutter SDK | 3.x stable | 3.47.7（`D:\apps\flutter`） |
| JDK | 17（不要用 8） | `D:\apps\Java\jdk-17` |
| Android SDK | 含 `cmdline-tools` + platform + build-tools | SDK 37.0.0 |

当前状态：`flutter analyze` 无告警，226 个自动化测试通过（测试代码在本地 `testcases/`，不随仓库发布）。

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
（只存本机 Android Keystore，不写入代码、不进入仓库）。未配置时 AI 降级为本地规则记账。

### 打包说明

- 模拟器（x86_64）：`flutter build apk --release --target-platform android-x64`
- 真机（ARM）：去掉 `--target-platform`，或显式 `android-arm64`
- 当前 release 包使用 debug 签名（`CN=Android Debug`），**上架或正式分发前必须配置正式签名**
- minSdk 24 / targetSdk 36；已确认 arm64-v8a、armeabi-v7a、x86_64 三套 ABI 与 16KB 页对齐

## 测试

测试用例、自动化脚本与截图属于本地验证资产，已通过 `.gitignore` 排除：

- `testcases/test-cases.md`：231 条用例
- `testcases/test-report.md`：执行报告、兼容性矩阵、缺陷清单
- `testcases/automation/`：24 个测试文件 / 226 个测试

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
- PIN 与 API Key 不在备份包内（存 Android Keystore），换机后需重新设置

> ⚠️ **数据只有一份，请定期导出备份。** 换机、丢机或误删且无备份时无法找回；
> 备份密码一旦遗忘，备份包也无法解开。

## 开源与保密

仓库中**不包含任何真实凭据与个人数据**：

- DeepSeek API Key 由使用者在 App 内自行填写，存 `flutter_secure_storage`（Android Keystore）
- 签名文件（`*.jks` / `*.keystore` / `key.properties`）、`.env`、本地数据库与备份包均已排除
- 测试用例与截图（`testcases/`、`.verify/`）仅在本地保留，不进入仓库
- 提交前由 `pre-commit` 钩子运行 `scripts/scan_secrets.py` 拦截疑似真实密钥：

  ```bash
  pip install pre-commit && pre-commit install
  ```

- 若密钥曾进入历史提交，请**立即到服务商后台轮换该 Key**，再用 `git filter-repo` 清理历史

## 版本与路线

| 版本 | 状态 | 范围 |
|---|---|---|
| **v0.1.0** | 当前版本 | 工程骨架 + 财务 + 健康 + 学习 + AI 助手（流式 / Markdown / 语音 / 16 工具 / 识图 / 离线队列）+ 主题色 + PIN / 指纹 + 加密备份；已完成兼容性验证 |
| **v1.1.0** | 计划 | 完成**扩充内置词库、单词听写与拼写测验、iOS 适配、回收站与 CSV 导出**后正式发布 |

> 版本号以 `app/pubspec.yaml` 的 `version` 为准，当前为 `0.1.0+1`（显示版本 v0.1.0，构建号 1）。

## 许可证

[MIT](./LICENSE)
