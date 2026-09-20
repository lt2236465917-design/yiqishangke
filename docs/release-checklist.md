---
artifact: release-checklist
project: 一起上课 / 课格 (yiqishangke)
change_id: PR #1 merged to main (merge 96f511b)
channel: local zip / Xcode sideload ONLY
status: draft for human use
explicit: App Store / TestFlight NOT authorized
known_risk_acceptance: |
  用户已接受审查债，本清单不把它当成阻塞：
  - frameset 抽表无 golden fixture（仓库内无 XCTest / 无真实课表 HTML 夹具；已在当前 main 核实）
  - 约 23 节课表会话 NOT_VERIFIED（仓库未提交学生课名/真实截图，无法在 git 内复核；按已接受债记录）
  - 本机验收已跳过（Cloud Agent 无法编 Xcode / 跑模拟器；IAM 从该出口 TCP 超时）
  - RF-109 编译修复：当前 main tip `96f511b` **已包含**。
    核实：`Kege/Import/ScreenshotImporter.swift` AI 分支有
    `let merged = WeeklyGridOCRParser.mergeAndDedupe(pair.0)`（引入提交 `eedf46d`）；
    登录页横幅戳 `SchoolLoginView.loginSheetStamp = "eedf46d"`。
    本环境未跑 Xcode 编译，编译是否在你的 Mac 上通过需本机确认。
---

# 课格本地 sideload 发布清单（PR #1 / main `96f511b`）

给人类用的草稿。渠道仅限本机 ZIP 或 clone 后 Xcode 安装。  
**未授权** App Store、TestFlight、公证、生产部署。机器人不得代发。

对照 tip：`96f511b714cc765d83123fdbb2f7faa0d2331caf`（Merge pull request #1）。  
登录页可见戳应为 `build eedf46d`；若仍是更早戳，先卸掉旧包再装本 tip。

## 1. 范围 / 非目标

本渠道 **做**：

- [ ] 从 **main** ZIP 或 clone 在开发者本机用 Xcode 编过、装到自己的模拟器或真机（iOS 17+）
- [ ] 本机课表查看、截图导入、门户录入（校园网/VPN 可用时）、三档提醒、主屏幕小组件
- [ ] 在已接受审查债的前提下做人工冒烟，不把「未核实」当成必须先修的 blocker

本渠道 **不做 / 禁止**：

- [ ] **不上架** App Store
- [ ] **不提交** TestFlight / ASC
- [ ] **不公证**、不打面向外人的分发包
- [ ] **机器人不部署** 到任何生产或共享设备
- [ ] 不改签名证书、不换 Bundle ID、不把 `Secrets.local.plist` 提交进 git

## 2. 构建与安装

源必须是 **已合并的 main**，不要再用 PR #1 功能分支 ZIP（README 里旧的 `cursor/kege-ios-app-3b30` 链接已过时）。

- [ ] 下载 ZIP：https://github.com/lt2236465917-design/yiqishangke/archive/refs/heads/main.zip  
      或 `git clone` 后 `git checkout main` 且 `git rev-parse HEAD` 为 `96f511b…`（或其后只含文档的 tip）
- [ ] 解压/克隆后打开根目录 **`Kege.xcodeproj`**（不要另开 workspace）
- [ ] Xcode 15+（建议 16 / Swift 6 编译器）；Scheme **Kege**；目标 iPhone 模拟器或真机 **iOS 17+**
- [ ] Target **Kege**：Signing 勾自己的 Team；Capabilities App Groups = `group.cn.yiqishangke.Kege`
- [ ] Target **ScheduleWidgets**：同一 Team、同一 App Group
- [ ] Bundle ID 保持：`cn.yiqishangke.Kege` / `cn.yiqishangke.Kege.ScheduleWidgets`
- [ ] Product → Run。登录页横幅有 `build eedf46d`
- [ ] 真机第一次：若 App Group 未开通，应用会退回沙盒，**小组件读不到课表**；设置页应出现提示

可选识图 Key：设置页粘贴，或复制 `Config/Secrets.example.plist` → `Config/Secrets.local.plist`（已 gitignore）后加入 App target。不要提交真实 Key。

## 3. Sideload 验收清单

在已接受审查债、且本机验收先前被跳过的前提下，由人在本机勾。失败记现象，不要为勾选去改代码。

### 3.1 导入失败路径

- [ ] **相册 OCR / DeepSeek**：选无法识别的图或空图 → 出现「导入失败」，**不**静默写成 0 节课表
- [ ] 无 Key：走本机 Vision；有 Key：走多模态 JSON（RF-109 绑定已在源码；本机确认能编过）
- [ ] **门户 frameset 抽表**：还在应用列表 / 欢迎页就点「录入课表」→ 提示先打开「我的课表」周视图，**不弹空核对清单**
- [ ] 磁贴失败或研究生页「请登录」→ 提示改用截图，**不再**裸开 `frameset.jsp`
- [ ] 横幅可出现 `tables=N frames=M`（子 frame 抽表，不是只读外壳）

### 3.2 0 节 / 空课表

- [ ] 未写入前：今日显示「今天没有课」，本周各日为空；**页仍可见**，不是白屏崩溃
- [ ] 门户页上格子可见但录入仍 0 节：记为已知债（无 golden fixture）；改走截图，或记下 `tables=` / `frames=` 后停手
- [ ] 写入后若今日仍 0：核对是否全是「时间待定」、是否星期/周次不覆盖今天，而不是 UI 丢了课表页

### 3.3 显式写入门闩

- [ ] 识别/抽表完成后 **不会自动落盘**
- [ ] 「写入本机课表」在仅有时间待定、或已写入后为禁用
- [ ] 「导入后替换本机课表」默认关；关着时应合并，开着才整表替换
- [ ] 必须点「写入本机课表」后，今日/本周才出现已排课

### 3.4 `timePending` 不进今日

- [ ] 核对清单区分「已排课」与「时间待定」（导师课空时间、思政自排/坏行等）
- [ ] 时间待定 **不** 变成假上午时段，**不** 写入 `ClassSession`，今日列表里看不到
- [ ] 仅时间待定时无法点写入

### 3.5 门户 HTML 路径 vs 截图 OCR

- [ ] **门户主路径**：IAM 登录（只填登录名/密码，不填验证码、不代点登录）→ 若落到「欢迎您」会自动去 `#/appList` → 亲手点「研究生综合管理」→ 左侧「我的课表」周网格出现 → 右上角「录入课表」→ HTML/DOM 抽表 → 核对 → 写入
- [ ] 表格仍空才允许 **一次** 门户截图识图兜底
- [ ] 相册多图 DeepSeek **只在「导入」页**，不要和门户录入混成同一步

### 3.6 小组件 App Group

- [ ] App 与 Widget 都是 `group.cn.yiqishangke.Kege`
- [ ] 写入课表后，Small「下一节」/ Medium「今日剩余」能读到同一份课表
- [ ] App Group 未开通时设置页有提示，小组件空或不更新（已知，不是发版去修的 blocker）

### 3.7 提醒三档

- [ ] 设置里三档可独立开关、可同时开：提前 15 分钟 / 3 小时 / 1 天
- [ ] 写入或改档位后会重建通知；未开通知权限时有提示
- [ ] 三档全开 × 多周：生成数可能超过 pending 上限 **60**，多出来的会被静默丢掉（见第 4 节）

## 4. 首周可观测观察项

装上后第一周人工看这些，不要等商店后台。

| 观察项 | 看什么 | 记录 |
|---|---|---|
| 导入失败（门户 frameset 抽表） | 周视图已开仍失败；横幅 `tables=` / `frames=`；是否误走截图兜底 | - [ ] 已看 / 现象： |
| 导入失败（相册 OCR） | 有/无 DeepSeek Key；「导入失败」文案；是否写坏本机课表 | - [ ] 已看 / 现象： |
| 0 节（页可见仍 0） | 今日/本周页在，课数为 0；门户格子可见却抽空 | - [ ] 已看 / 现象： |
| 提醒截断 | 三档全开 × 多周；Console/`SafeLog`：`scheduled N / generated M`，N≤60 且 M>N 即静默丢 | - [ ] 已看 / 现象： |
| Key 泄露面 | 设置页粘贴 DeepSeek Key；截屏/共用机；`Secrets.local.plist` 勿进 git；`SafeLog` 不写密码/Key | - [ ] 已看 / 现象： |

Key 泄露面操作约定：

- [ ] 共用机演示后删除钥匙串里的识图 Key 与学校密码
- [ ] `git status` 确认没有 `Config/Secrets.local.plist` / `Config/Secrets.plist`
- [ ] 日志里用户名应是打码，不应出现明文密码或 Bearer Key

## 5. 回滚

本渠道没有商店版本可撤。两手都要能做，**给用机的人优先重装上一份 zip/IPA**。

### 5.1 用户侧（优先）

- [ ] 合并前保留一份已知可用的 IPA / Xcode Archive / 上一份 ZIP，或打 git tag
- [ ] 出问题：卸载「课格」，再装上一份构建（钥匙串里的学校账号/Key 可能还在，按需在设置里删）
- [ ] 不要把「重装旧包」理解成商店下架——本渠道本来就没有商店包

### 5.2 仓库侧（修复分支，给开发者）

- [ ] 需要撤代码时：从 main 拉修复分支，对 **merge commit** `96f511b` 做 `git revert`（merge 用 `-m 1`），不要在 main 上强制推
- [ ] 示例（只在修复分支、且已确认要撤 PR #1 整体时）：  
      `git revert -m 1 96f511b`
- [ ] 用户设备仍以重装上一份 zip/IPA 为准；revert 只恢复源码，不会自动卸掉已装的 App

## 6. 本渠道 Go / No-go

| 渠道 | 结论 |
|---|---|
| 本机 ZIP / Xcode sideload | **Go（带债）**：允许在上述风险接受下装自己的设备。frameset 无夹具、约 23 节 NOT_VERIFIED、本机验收跳过，不构成本渠道 no-go。RF-109 源码已在 `96f511b`，本机仍须确认能编过。 |
| App Store / TestFlight / 对外分发 | **BLOCKED**。未授权。本清单不得被解读成上架许可。 |

Go 前最少勾完：

- [ ] 安装源是 main `96f511b`（或其后仅文档提交），登录戳 `eedf46d`
- [ ] Team + App Group `group.cn.yiqishangke.Kege` 已配对
- [ ] 显式写入门闩有效；时间待定不进今日
- [ ] 未做、也不会做 App Store / TestFlight 操作

勾完后仍是 **draft for human use**。通过本清单 ≠ 生产发布。
