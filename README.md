# 课格（一起上课）

iPhone 课表应用：给研究生伴侣在本机查看课表、上课提醒和主屏幕小组件。  
学校：中国艺术研究院（登录线索 `https://iam.zgysyjy.org.cn`）。iOS 17+，中文界面。

**首版不做：** Android / Web、多学校、EventKit、成绩选课等其它门户功能、锁屏小组件、App Store 上架。

## 下载本分支 ZIP（本机测试）

不要下 `main`。请下当前功能分支：

1. 打开 https://github.com/lt2236465917-design/yiqishangke/tree/cursor/kege-ios-app-3b30
2. 绿色 **Code** → **Download ZIP**
3. 或直接：https://github.com/lt2236465917-design/yiqishangke/archive/refs/heads/cursor/kege-ios-app-3b30.zip

解压后打开根目录的 `Kege.xcodeproj`。

## 在 Xcode 里打开

1. **Xcode 15 或更新**（建议 Xcode 16 / Swift 6 编译器；工程语言模式仍可编过先前 Swift 6 报错：缺 `return`、MainActor 默认参数）。
2. 打开 `Kege.xcodeproj`。
3. Scheme 选 **Kege**，目标选 **iPhone** 模拟器或真机（iOS 17+）。
4. Target **Kege** → Signing & Capabilities：勾选自己的 Team；App Groups 为 `group.cn.yiqishangke.Kege`。
5. Target **ScheduleWidgets** 用同一 Team、同一 App Group。
6. Product → Run。

| Target | Bundle ID |
|---|---|
| 课格 App | `cn.yiqishangke.Kege` |
| 小组件 | `cn.yiqishangke.Kege.ScheduleWidgets` |
| App Group | `group.cn.yiqishangke.Kege` |

第一次真机若 App Group 未开通，应用退回沙盒，**主屏幕小组件读不到课表**。设置页会提示。

## 建议测试顺序

门户在校园网外经常打不开。**先跑截图导入**，确认今日/本周能出课；门户顺了再测 SSO。

### 1. 截图导入（优先）

1. **设置 → 开发者识图**：填 DeepSeek Key（见下）。没 Key 则走本机 Vision。
2. **导入**：一次选中上午/下午/晚上多张周课表截图。
3. 核对紧凑清单（节次数、门课数、覆盖星期；一行 `周一 09:00-12:00 · 教室 · 课名`）。
4. **识别后不会写入。** 必须点 **写入本机课表**。「导入后替换本机课表」默认关。
5. 看 **今日 / 本周** 是否出现结构化课程。

### 2. 门户（学校网 / VPN 可用时）

1. **设置** 保存学号密码（只进本机钥匙串）。
2. **立即同步课表** → IAM 登录页自动填登录名和密码（**不填验证码、不代点登录**）。
3. 登录后若停在「欢迎您」个人中心，应用会**自动打开一次** `https://iam.zgysyjy.org.cn/portal/#/appList`（hash 路由）。个人中心没有研究生磁贴。
4. 看到应用列表后再点「进入研究生系统」（脚本点磁贴 / 真实 SSO URL）。不要自己打开 `https://wxt.zgysyjy.org.cn:7792/graduate/frameset.jsp`。
5. 磁贴失败或出现「请登录」：关闭，改用截图。应用不会再跳一次裸 frameset。
6. 进入研究生系统后点左侧 **我的课表**，再点 **解析本页**，确认后再 **写入本机课表**。

## 配置 DeepSeek Key（可选，截图更准）

设置页空表默认：

- Base URL：`https://api.deepseek.com`
- 模型：`deepseek-flash`
- 路径：`/chat/completions`

Key / 根路径 / 模型 / 补全路径都可以改；下次请求只读钥匙串。

或复制 `Config/Secrets.example.plist` 为 `Config/Secrets.local.plist`（已 gitignore），填 `AI_API_KEY` 等，加入 App target。启动时吸入钥匙串。

识图请求 **只发课表图片**，不发学校账号、密码或 Cookie。不要把 Key 提交进 git。

## 已知 URL（SSO 注意）

| 用途 | URL | 说明 |
|---|---|---|
| IAM 登录 | `https://iam.zgysyjy.org.cn/am/mLogin/login.html` | 已核实 |
| 登录后应用列表 | `https://iam.zgysyjy.org.cn/portal/#/appList` | 已核实；磁贴在这里。欢迎/个人中心不是此页 |
| 研究生 frameset | `https://wxt.zgysyjy.org.cn:7792/graduate/frameset.jsp` | SSO **落地**页。裸开会「请登录」 |
| 我的课表子菜单 | 未知 | 地址栏可能一直停在 frameset |

详情见 [docs/portal-spike.md](docs/portal-spike.md)。

## 模块

| 模块 | 作用 |
|---|---|
| `CredentialsStore` | 学校账号与可选 AI Key 的钥匙串 CRUD |
| `LoginWebViewSession` | 短暂 WKWebView 会话 + 自动填充（非点击代理） |
| `SchoolParser` / `ZgysyjyParser` | 周课表优先 + 名单表补全；走 frames/iframes |
| `ScheduleStore` | 本机 JSON 课表库（App Group） |
| `SyncCoordinator` | 仅手动同步，写入后重建提醒与小组件 |
| `ScreenshotImporter` | 多图；有 Key 走 DeepSeek JSON，否则 Vision |
| `ReminderScheduler` | 按开启档位排程，课表变更重建 |
| `ScheduleWidgets` | Small / Medium 主屏幕组件 |

## 安全约束（必须保持）

- 学校凭证只放钥匙串，`WhenUnlockedThisDeviceOnly`，不随 iCloud 钥匙串同步。
- 从不上传学校账号密码；无云端代登。
- 不把密码写入日志、不提交 secrets。
- 验证码 / 2FA 不自动绕过。
- 登录 WebView 使用 **非持久** 网站数据，同步结束不留下门户 Cookie。

## 本环境已知阻断

Cloud Agent 访问 `iam.zgysyjy.org.cn` **TCP 超时**；Linux 无法编 Xcode / 跑模拟器。本机测试请用你的 Mac + 校园网或 VPN。
