# 课格（一起上课）

iPhone 课表应用：给研究生伴侣在本机查看课表、上课提醒和主屏幕小组件。  
学校：中国艺术研究院（登录线索 `https://iam.zgysyjy.org.cn`）。iOS 17+，中文界面。

**首版不做：** Android / Web、多学校、EventKit、成绩选课等其它门户功能、锁屏小组件、App Store 上架。

## 在 Xcode 里打开

1. 用 **Xcode 15 或更新**（需 macOS）。
2. 打开仓库根目录的 `Kege.xcodeproj`。
3. 顶部 Scheme 选 **Kege**，目标选一台 **iPhone** 模拟器或真机（iOS 17+）。
4. 选中 Target **Kege** → Signing & Capabilities：
   - 勾选你自己的 Team
   - 确认 Capability **App Groups** 为 `group.cn.yiqishangke.Kege`
5. Target **ScheduleWidgets** 使用同一 Team 与同一 App Group。
6. Product → Run。

Bundle ID：

| Target | Bundle ID |
|---|---|
| 课格 App | `cn.yiqishangke.Kege` |
| 小组件 | `cn.yiqishangke.Kege.ScheduleWidgets` |
| App Group | `group.cn.yiqishangke.Kege` |

第一次真机运行若 App Group 未在开发者账号开通，应用会退回沙盒目录，**主屏幕小组件读不到课表**。应用内设置页会提示。

## 使用

1. **设置 → 学校账号**：保存学号和密码（只进本机钥匙串，不进 iCloud，不上传）。
2. **立即同步课表**（仅手动）：打开 `https://iam.zgysyjy.org.cn/am/mLogin/login.html` → 自动填登录名和密码（**不填验证码、不代点登录**）→ 你输入图形验证码后点登录。
3. 登录后 **自行进入课表页**，点右上角 **解析本页**。  
   **课后课表 URL 尚未核实**（见 `docs/portal-spike.md`）。解析不到就用截图导入。
4. **导入**：相册可一次多选上午/下午/晚上截图，合并去重后写入今日/本周。有开发者识图 Key 时走多模态；否则本机 Vision 按表格位置识别。
5. **上课提醒**：三档独立开关，可多开——提前 15 分钟 / 3 小时 / 1 天。改课表后全量重建通知。
6. **主屏幕小组件**：小尺寸「下一节课」、中尺寸「今日剩余」。锁屏组件首版不做。

## 开发者识图 Key（可选）

不要提交 Key。任选其一：

- 设置页写入钥匙串。空表默认 DeepSeek：`https://api.deepseek.com` + `deepseek-flash`（官方识图）。Key / 根路径 / 模型三项可改，运行时只读钥匙串。
- 复制 `Config/Secrets.example.plist` 为 `Config/Secrets.local.plist`（已 gitignore），填 `AI_API_KEY`，再把该文件加进 App target。启动时会吸入钥匙串。

识图请求 **只发课表图片**，不发学校账号、密码或 Cookie。

## 模块

| 模块 | 作用 |
|---|---|
| `CredentialsStore` | 学校账号与可选 AI Key 的钥匙串 CRUD |
| `LoginWebViewSession` | 短暂 WKWebView 会话 + 自动填充（非点击代理） |
| `SchoolParser` / `ZgysyjyParser` | zgysyjy 课表解析桩 + 通用表格/JSON/文本启发式 |
| `ScheduleStore` | 本机 JSON 课表库（App Group） |
| `SyncCoordinator` | 仅手动同步，写入后重建提醒与小组件 |
| `ScreenshotImporter` | 多图 Vision 网格解析；有 Key 时优先多模态 |
| `ReminderScheduler` | 按开启档位排程，课表变更重建 |
| `ScheduleWidgets` | Small / Medium 主屏幕组件 |

## 安全约束（必须保持）

- 学校凭证只放钥匙串，`WhenUnlockedThisDeviceOnly`，不随 iCloud 钥匙串同步。
- 从不上传学校账号密码；无云端代登。
- 不把密码写入日志、不提交 secrets。
- 验证码 / 2FA 不自动绕过。
- 登录 WebView 使用 **非持久** 网站数据，同步结束不留下门户 Cookie。

## 已知阻断

见 [docs/portal-spike.md](docs/portal-spike.md)。核心点：本环境访问 `iam.zgysyjy.org.cn` TCP 超时；登录后课表 URL **未核实**。验收上以 **截图导入可用** 作为主路径受阻时的完成条件。
