# 门户探测：中国艺术研究院 IAM / 课表

探测日期：2026-09-20（Cloud Agent 出口网络）。  
登录线索：`https://iam.zgysyjy.org.cn`（用户提供）。  
课后课表页 URL：**未核实（UNVERIFIED）**。

## 已核实

| 项 | 结论 | 类别 |
|---|---|---|
| 机构 | `zgysyjy.org.cn` 为中国艺术研究院门户 | 已核实 |
| 研究生院公开站 | `https://www.gscaa.cn` 可打开 | 已核实 |
| 「研究生综合管理信息系统」 | 出现在 gscaa 页头，但 `href` 为 `cursor: default`，**不是可点的公开 URL** | 已核实 |
| IAM DNS | `iam.zgysyjy.org.cn` → `219.234.221.204` | 已核实 |
| IAM HTTP/HTTPS | 从本环境访问 80/443 **TCP 超时**（约 8–25s，0 字节） | 已核实 |
| 官网 CDN | `https://www.zgysyjy.org.cn` 可 301 到 `index.html` | 已核实 |
| 常见教务子域 | `jwxt` / `ehall` / `cas` / `yjs` 等 **无 DNS 记录** | 已核实 |
| 登录页 URL | 用户模拟器打开 `https://iam.zgysyjy.org.cn/am/mLogin/login.html`（`/am/mLogin/` 下带 query 的变体同样进入该页） | 已核实（用户模拟器） |
| 登录表单 | tab「用户名密码」；登录名 / 密码 / 图形验证码；蓝色登录按钮 | 已核实（用户模拟器） |
| 登录后课表路径 | 无公开文档、无已登录会话，**未知** | 未核实 |

## 推断（不是事实）

- IAM 很可能只允许校园网、指定出口或 VPN。超时更像防火墙丢包，而不是 DNS 失败。
- gscaa 上的「研究生综合管理信息系统」可能在浏览器里用脚本跳到 IAM，但静态 HTML 没有给出目标。
- 课后课表常见中文研究生系统路径（`wdkb` / `xskb` / `培养管理 → 学生课表查询`）**仅作解析启发式，不是该校核实地址**。

## 对 v1 的影响

主路径实现为：

1. WKWebView 打开 `https://iam.zgysyjy.org.cn/am/mLogin/login.html`
2. 自动填登录名和密码（可用时先切到「用户名密码」tab），**不填验证码、不代点登录**
3. 图形验证码由用户手输后再点登录；仅短信/二次验证页（无密码框）才整页停填
4. 用户进入课表后点「解析本页」，跑 `ZgysyjyParser` 桩

若 IAM 在真机也打不开，或登录后找不到课表页：用 **截图导入**（OCR / 可选识图）。应用不会做云端代登。

## 人工跟进

请在校园网或 VPN 下用 Safari 走完登录，把 **课表页最终 URL**（可打码 query）回填到本文件，并补进 `ZgysyjyParser.candidateTimetableHints`。
