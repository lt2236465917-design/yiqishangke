# 课格（一起上课）

iPhone 本机课表应用：给研究生伴侣查看课表、上课提醒和主屏幕小组件。  
学校：中国艺术研究院（登录 `https://iam.zgysyjy.org.cn`）。iOS 17+，中文界面。

本仓库走 **Xcode 本机 sideload**（模拟器或自己的真机）。**不做** App Store、TestFlight、公证或对外分发。

**首版也不做：** Android / Web、多学校、EventKit、成绩选课等其它门户功能、锁屏小组件。

## 从 main 拿到源码

默认分支是 `main`。陌生人请 clone 或下 main 的 ZIP，不要下已过时的功能分支。

```bash
git clone https://github.com/lt2236465917-design/yiqishangke.git
cd yiqishangke
git checkout main
```

或 ZIP：https://github.com/lt2236465917-design/yiqishangke/archive/refs/heads/main.zip  
解压后打开根目录的 `Kege.xcodeproj`。

逐步勾选见 [docs/release-checklist.md](docs/release-checklist.md)。门户/SSO 细节见 [docs/portal-spike.md](docs/portal-spike.md)。

## 要求

- **Xcode 15 或更新**（建议 Xcode 16 / Swift 6 编译器）
- 目标设备 **iOS 17+**（模拟器或真机）
- Apple Developer **Team**（免费个人 Team 也可 sideload，有效期较短）
- App Group：`group.cn.yiqishangke.Kege`（App 与小组件必须同一 Team、同一 Group）

| Target | Bundle ID |
|---|---|
| 课格 App | `cn.yiqishangke.Kege` |
| 小组件 | `cn.yiqishangke.Kege.ScheduleWidgets` |
| App Group | `group.cn.yiqishangke.Kege` |

## 打开工程并 sideload

1. 打开根目录 **`Kege.xcodeproj`**（不要另开 workspace）。
2. Scheme 选 **Kege**，目标选 iPhone 模拟器或真机。
3. Target **Kege** → Signing & Capabilities：勾选自己的 Team；App Groups 为 `group.cn.yiqishangke.Kege`。
4. Target **ScheduleWidgets**：同一 Team、同一 App Group。
5. Product → Run，装到本机或模拟器。
6. 登录页横幅应出现 `build eedf46d`（或其后文档提交仍用该戳）。若仍是更早戳，先卸掉旧包再装。

第一次真机若 App Group 未开通，应用退回沙盒，**主屏幕小组件读不到课表**。设置页会提示。

## 配置 DeepSeek（可选，只存在本机）

设置 → 开发者识图。空表默认：

- Base URL：`https://api.deepseek.com`
- 模型：`deepseek-flash`
- 路径：`/chat/completions`

Key / 根路径 / 模型 / 补全路径都可改。下次请求只读本机钥匙串。

也可复制 `Config/Secrets.example.plist` 为 `Config/Secrets.local.plist`（已 gitignore），填 `AI_API_KEY` 等，加入 App target。启动时吸入钥匙串。

**不要把 Key、学校密码或 `Secrets.local.plist` 提交进 git。** 识图请求只发课表图片，不发学校账号、密码或 Cookie。

## 使用流程

门户在校园网外经常打不开。可先跑相册截图导入，确认今日/本周能出课；门户通了再测 SSO。

### 门户录入（主路径 = HTML/DOM）

1. **设置** 保存学号和密码（只进本机钥匙串，`WhenUnlockedThisDeviceOnly`）。
2. **立即同步课表** → IAM 登录页自动填登录名和密码（**不填验证码、不代点登录**）。
3. 登录后若停在「欢迎您」个人中心，应用会自动打开一次 `https://iam.zgysyjy.org.cn/portal/#/appList`。个人中心没有研究生磁贴。
4. 在应用列表亲手点 **研究生综合管理**（门户 SSO）。不要自己打开裸 `https://wxt.zgysyjy.org.cn:7792/graduate/frameset.jsp`（会「请登录」）。
5. 进入研究生系统后，点左侧 **我的课表**，等到周课表格子出现。
6. 点右上角 **录入课表**。应用从 frameset **子页面**抽表格（周网格优先，名单表补教室）。横幅可出现 `tables=N frames=M`。
7. 弹出核对清单：摘要为「N 门课 · X 门已排课 · Y 门时间待定」。**不会自动写入。** 点 **写入本机课表** 才落盘。「导入后替换本机课表」默认关。
8. 仍在应用列表/登录页就点录入：报错，不弹空清单。表格仍空才允许一次页面截图识图兜底。

### 相册截图 OCR（备份）

1. **导入**：一次选中上午/下午/晚上等多张「我的课表」截图。
2. 有 DeepSeek Key 走多模态 JSON；没 Key 走本机 Vision。
3. 核对清单同样区分已排课 / 时间待定（导师课空时间、思政自排等显示「时间、地点待定」，不写成假的 09:00–12:00）。
4. **识别后不会写入。** 必须点 **写入本机课表**。时间待定的课只展示，不进入今日课表。

### 提醒与小组件

- 设置里三档可独立开关：提前 **15 分钟 / 3 小时 / 1 天**。写入或改档位后重建通知。
- Small「下一节」、Medium「今日剩余」读 App Group 里同一份课表。通知权限未开时设置页会提示。
- 三档全开 × 多周时，待发通知可能超过系统 pending 上限 60，多出来的会被丢掉（见发布清单）。

## 已知缺口（不是「已核实」）

这些是已接受的债，不是本机 sideload 的 blocker，也**不要**当成商店验收通过：

- 研究生课表在 **frameset 子 frame** 里。抽表依赖 WK 用户脚本 / `postMessage`；仓库内 **没有** 真实课表 HTML 夹具或 XCTest，frameset 是否稳定 **未 golden 测试**。
- 相册 OCR 目标约 23 条有效时段，**未**用真实学生课名/截图在 git 内复核；可能少抽或多抽。
- Cloud / Linux **不能**编 Xcode；校外访问 IAM 常 **TCP 超时**。能否编过、门户能否打开，只能在你的 Mac + 校园网或 VPN 上确认。
- 「我的课表」子菜单准确 URL **未知**；地址栏可能一直停在 `frameset.jsp`。
- 登录页横幅戳 `eedf46d` 对应 RF-109 源码修复；本仓库没有 CI 编译任务。

## 安全约束

- 学校凭证只放钥匙串，不随 iCloud 钥匙串同步。
- 从不上传学校账号密码；无云端代登。
- 不把密码、Token、API Key 写入日志或提交进 git。
- 验证码 / 2FA 不自动绕过。
- 登录 WebView 使用非持久网站数据，同步结束不留下门户 Cookie。
- `Config/Secrets.local.plist`、`.env`、证书已在 `.gitignore`。提交前 `git status` 确认没有这些文件。

## 模块

| 模块 | 作用 |
|---|---|
| `CredentialsStore` | 学校账号与可选 AI Key 的钥匙串 CRUD |
| `LoginWebViewSession` | 短暂 WKWebView + 自动填充（非点击代理） |
| `SchoolParser` / `ZgysyjyParser` | 周课表优先 + 名单表补全；走 frames |
| `ScheduleStore` | 本机 JSON 课表库（App Group） |
| `SyncCoordinator` | 仅手动同步；写入后重建提醒与小组件 |
| `ScreenshotImporter` | 相册多图；有 Key 走 DeepSeek JSON，否则 Vision |
| `ReminderScheduler` | 按开启档位排程 |
| `ScheduleWidgets` | Small / Medium 主屏幕组件 |
