# 登录请求频率风险评估报告

> 请求编号：R1（路径文档）
> 评估对象：向学校系统发送登录请求的全部代码路径
> 评估目标：(1) 复核所有向学校系统发送登录请求的代码路径；(2) 全方位评估持续发送登录请求导致账号被冻结的风险；(3) 给出每小时最高安全登录频率的量化建议与依据
> 证据基线：所有代码路径引用均为 G:\app 工作区内真实文件与行号（可直接核验）；学校侧阈值无法从代码验证的项已在本报告第九节中明确列出。

---

## 一、结论摘要（Executive Summary）

1. **登录请求面**：应用向学校系统发送登录相关请求的路径共有 5 大类：① CAS 密码登录（GET /authserver/login + POST /authserver/login，一次完整密码登录 = 2 个请求）；② CAS Ticket 兑换（1 个请求）；③ 会话有效性探测（POST 教务课表接口 / GET 一卡通入口，会话过期时会 302 到 CAS 登录页）；④ 隐藏 WebView 静默引导（每次引导周期至少 4 次页面加载，CAS 登录页仅在会话失效且频控放行时提交凭据）；⑤ 后台任务（WorkManager 15 分钟周期，白天 4 次/小时）。
2. **现有防护总体有效，但存在 3 个可量化缺口**：
   - 滑动窗口计数上限 10 次/小时（packages\platform\lib\services\session_service.dart:201-215），但无最小间隔约束——10 次可在 1 分钟内打满（最坏 20 个 CAS 请求突发）。
   - 手动登录路径不计入频控：loginWithPassword（direct_school_campus_gateway.dart:2228-2229）、WebView 手动提交均不调用 recordAutoLoginAttempt（测试 direct_gateway_challenger_test.dart:732-754 明确验证 manual login does not call recordAutoLoginAttempt）。
   - 熔断器只对 AuthInvalidFailure（密码错误）触发（direct_school_campus_gateway.dart:2913-2918、:3036-3041）；CaptchaRequiredFailure/BotChallengeFailure（WAF 拦截）等失败会消耗 10 次/小时配额但不触发熔断。
3. **冻结风险评级**：账号级（密码失败触发冻结）风险低——因为 1 次 AuthInvalidFailure 即熔断，连续失败被限制在 1-2 次，远低于学校侧常见阈值（5-10 次连续失败，见第九节，无法验证）。IP/WAF 级风险中——瑞数 WAF 按行为评分（direct_school_campus_gateway.dart:319-377），突发 20 请求/分钟可能触发风控，阈值无法验证。
4. **最高安全频率建议（核心结论）**：
   > 自动登录提交上限收紧为 6 次/小时，且强制相邻两次尝试最小间隔 >= 5 分钟。
   - 量化依据：6 次/小时 × 2 请求/次 = 最坏 12 个 CAS 认证请求/小时（当前最坏 20 个）；任意 10 分钟窗口内最多 2 次尝试；结合熔断器后连续失败 <= 2，对常见"5 次连续失败即冻结"阈值留有 >= 2.5 倍裕度。
   - 若学校侧确认阈值更严（如 3 次失败即冻结），应进一步下调至 4 次/小时（见第七节敏感性分析）。
5. **文档一致性缺陷**：auth_providers.dart:68-69 注释写"1-hour 5-attempts auto-login limit"、silent_zove_token_bootstrapper.dart:353 注释写"最多 5 次"、PROJECT.md:47 写"每小时上限（5次）"，实际代码为 10 次/小时——三处注释均为过时文案，需同步修正（本次仅报告，不修改）。

---

## 二、登录面盘点：涉及学校系统的全部主机与认证入口

| 系统 | 主机 | 认证类型 | 代码位置 |
|---|---|---|---|
| 统一身份认证 CAS | ids.cqjtu.edu.cn | 密码（AES/CBC/PKCS7 加密）+ Ticket | packages\data\lib\src\direct_school\direct_school_campus_gateway.dart:99-100, 782-957 |
| 教务系统（瑞数 WAF 保护） | jwgln.cqjtu.edu.cn | CAS SSO 会话 Cookie | 同上 :101-102 |
| 一卡通 | ecard.cqjtu.edu.cn | CAS SSO + 一卡通会话 | 同上 :111 |
| 移动学工大厅 | zhxg.cqjtu.edu.cn | CAS SSO / h-zove-token | apps\campus_app\lib\widgets\silent_zove_token_bootstrapper.dart:37-38 |
| 体育系统（独立认证，非 CAS） | sport.cqjtu.edu.cn | MD5 密码 + 图形验证码 + token | apps\campus_app\lib\features\running\services\sports_schema_auth_service.dart |

**CAS 密码登录的请求构成**（direct_school_campus_gateway.dart）：
- 第 1 个请求：GET casLoginUrl（获取表单、execution token、pwdEncryptSalt）：:796-799
- 第 2 个请求：POST casLoginUrl（提交加密密码）：:848-860
- 即：每次完整密码登录 = 2 个 HTTP 请求（成功与失败均为 2 个）。
- Ticket 兑换 = 1 个请求：GET casLoginUrl?ticket=...：:963-967

## 三、登录请求触发路径全枚举（含重试、定时器、后台、并发）

### 3.1 前台手动登录（用户显式操作，不计入频控）

| # | 路径 | 触发 | 请求数/次 | 频控 | 代码位置 |
|---|---|---|---|---|---|
| 3.1.1 | 登录页密码登录（本地直连模式） | 用户点击登录按钮 | 2（GET+POST） | 无（手动） | apps\campus_app\lib\pages\login_page.dart:58, 110 -> direct_school_campus_gateway.dart:2228-2229（forceRelogin(isSilent:false)） |
| 3.1.2 | WebView 网页登录（手动） | 用户在 WebView 提交 | 1（POST，由 WebView 发出） | 无 | apps\campus_app\lib\pages\webview_login_page.dart:98-101（仅自动填表，不自动提交） |
| 3.1.3 | Ticket 兑换（网页登录成功后） | WebView 登录成功回调 | 1（GET ticket） | 无（ticket 一次性） | apps\campus_app\lib\features\auth\web_login_binder.dart:83-89；direct_school_campus_gateway.dart:2932-2939 |
| 3.1.4 | 体育系统手动登录 | 用户输入验证码后点击 | 1（POST /do_login） | 无 | apps\campus_app\lib\pages\campus_running_page.dart:77, 142, 202, 222；sports_schema_auth_service.dart |

### 3.2 静默自动登录（计入 10 次/小时频控）

| # | 路径 | 触发 | 请求数/次 | 频控 | 代码位置 |
|---|---|---|---|---|---|
| 3.2.1 | 数据访问前会话保障 ensureAuth | 10 个数据方法调用点 | 会话有效：1 次探测；会话失效：2（登录） | 是：canAttemptAutoLogin + recordAutoLoginAttempt | direct_school_campus_gateway.dart:2847-2930；调用点 :2271, :2304, :2381, :2407, :2546, :2578, :2622, :2647, :2698, :2724 |
| 3.2.2 | 会话过期强制重登 forceRelogin（静默） | 7 个数据方法在响应识别到会话过期后 | 2（登录） | 是：同上 | direct_school_campus_gateway.dart:2979-3041；调用点 :2285, :2389, :2454, :2491, :2507, :2527, :2559 |
| 3.2.3 | 隐藏 WebView 静默引导（CAS 凭据提交） | 25 分钟健康定时器 / 应用恢复 / zoveToken 刷新事件 / 用户名切换 | 会话失效时 2（GET 登录页 + POST 提交） | 是：canAttemptAutoLogin（silent_zove_token_bootstrapper.dart:355）+ recordAutoLoginAttempt（:371）+ 15/30 分钟冷却 + 单次运行守卫 | apps\campus_app\lib\widgets\silent_zove_token_bootstrapper.dart:314-384 |
| 3.2.4 | 后台任务课表同步 | WorkManager 15 分钟周期（白天） | 登录前先查 canAttemptAutoLogin，会话失效时 2 | 是：background_task.dart:581 | packages\platform\lib\services\background_task.dart:573-587 |

### 3.3 会话探测请求（非凭据提交，但属学校系统请求；会话失效时表现为落到 CAS 登录页）

| # | 路径 | 请求 | 位置 |
|---|---|---|---|
| 3.3.1 | 会话有效性探测 isSessionValid | POST scheduleUrl（课表接口，body {xnxq01id:''}） | direct_school_campus_gateway.dart:1017-1048；ensureAuth 内 :2876-2884、:2886-2895 |
| 3.3.2 | 一卡通认证探测 authEcard | GET ecardPayeleUrl（会话失效 -> 302 到 CAS） | direct_school_campus_gateway.dart:1062-1075；重试 ensureEcardAuth 最多 3 次、间隔 500/1000ms：:1077-1081 |
| 3.3.3 | 隐藏 WebView 引导的页面加载 | 每次引导 4 次页面加载：CAS 登录页（:256）、一卡通入口（:274）、学工大厅 ×2（:224,:226） | silent_zove_token_bootstrapper.dart:214-286 |
| 3.3.4 | 后台一卡通余额检查 | getElecBalance / getCampusCardBalance（内部走 ensureEcardAuth 探测） | background_task.dart:301-355 |

### 3.4 自托管（selfHosted）模式：学校侧请求由后端服务器发出

- 手机端在 selfHosted 模式不直接向 CAS 提交凭据，而是调用自有后端 API（createSession、loginWithTicket、injectCookies）：apps\campus_app\lib\providers\runtime_mode.dart:34-38、packages\platform\lib\services\background_task.dart:909-960, 991-1005、packages\data\lib\src\self_hosted\self_hosted_session_manager.dart:43, 86。
- 学校侧看到的登录请求来自后端服务器 IP（可能聚合多用户）。恢复流程带指数退避（30s->10min 上限）：apps\campus_app\lib\providers\session.dart:680-686（(30 * (1 << (count - 1))).clamp(30, 600)）。
- 评估含义：selfHosted 部署的冻结风险集中在后端 IP/账号维度，本报告第七节建议对后端同样施加按账号频控（见 8.5）。

### 3.5 定时器与生命周期触发汇总

| 定时器/事件 | 周期 | 是否可能触发登录 | 位置 |
|---|---|---|---|
| 隐藏 WebView 健康检查 Timer.periodic | 25 分钟（2.4 次/小时） | 是（若 CAS 页出现且频控放行） | silent_zove_token_bootstrapper.dart:42, 112-116 |
| 应用恢复（前台） | 事件驱动 | 是（_maybeStart + 数据刷新） | silent_zove_token_bootstrapper.dart:127-131；main.dart:210-231（10s 冷却） |
| zoveToken 刷新事件 | 事件驱动（登录成功、requestRefresh） | 是（force 引导） | silent_zove_token_bootstrapper.dart:61-63；web_login_binder.dart:36；login_page.dart:55 |
| 用户名切换 | 事件驱动 | 是（force 引导） | silent_zove_token_bootstrapper.dart:586-591 |
| WorkManager 后台任务 | 15 分钟（白天）/ 3 小时（夜间 23:00-6:00） | 是（受限频控） | main.dart:91-97；packages\core\lib\utils\polling_utils.dart:1-7；background_task.dart:581 |
| 初始启动 | 一次 | 是（非 force，按工件新鲜度） | silent_zove_token_bootstrapper.dart:109-111 |
| GPS 跑步计时器 | 1 秒 | 否（纯定位，无网络/认证调用） | apps\campus_app\lib\features\running\services\gps_running_service.dart:146 |

### 3.6 并发与去重机制

- _reloginInFlight 共享 Future 去重：direct_school_campus_gateway.dart:2832-2834, 2848-2849, 2926-2929, 2984-2985——并发数据请求共享同一次重登，已修复历史上"8 个并发请求各自清 cookie 重登"的风暴缺陷（docs\fix-report-2026-08-22.md:613-658；验证：移除守卫后测试观测到 9 次 CAS 登录页请求、恢复守卫后 2 次：:734-745）。
- 成绩查询 fan-out：先 1 次汇总页请求、再 8 个学期并行请求（共 9 个教务请求），若中途会话过期则经 _reloginInFlight 合并为一次重登：direct_school_campus_gateway.dart:2318-2349。
- 跨进程并发注意点：后台任务在独立 isolate 中新建 Gateway（background_task.dart:144, 313, 590），其内存态 _reloginInFlight/_silentLoginAttemptedInSession 与前台进程不共享；但频控计数通过同一 SessionService（FlutterSecureStorage）共享（前台 runtime_mode.dart:42-44、引导器 silent_zove_token_bootstrapper.dart:142/354、后台 background_task.dart:144），因此 10 次/小时为跨前台+后台+WebView 引导的全局限额。缺陷：无最小间隔约束时，前台与后台可几乎同时各消耗配额形成突发（见第五节缺口 G1）。

## 四、请求放大机制

| 机制 | 说明 | 放大倍数/示例 | 位置 |
|---|---|---|---|
| 每次登录 = 2 请求 | GET 表单 + POST 凭据 | ×2（10 次自动登录 = 20 个 CAS 请求） | direct_school_campus_gateway.dart:796-799, 848-860 |
| 滑动窗口无间隔 | 10 次配额可在 1 分钟内打满 | 20 请求/分钟突发 | session_service.dart:189-198（只追加时间戳，无间隔检查） |
| 会话探测 | 每次数据访问先探测再取数 | 每个数据方法 >=1 个额外请求 | direct_school_campus_gateway.dart:2876-2895 |
| 一卡通重试 | ensureEcardAuth 最多 3 次探测 | ×3（间隔 500/1000ms） | direct_school_campus_gateway.dart:1077-1081 |
| 成绩 fan-out | 1 汇总 + 8 学期并行 | 9 请求/次查询（但重登合并为 1 次） | direct_school_campus_gateway.dart:2318-2349 |
| 引导器页面加载 | 每次引导 4 次页面加载 | 25 分钟周期 -> 2.4×4 ≈ 9.6 次/小时 | silent_zove_token_bootstrapper.dart:214-286 |
| 后台任务周期 | 白天 15 分钟 | 4 次/小时（每次含探测 + 可能 1 次登录） | polling_utils.dart:1-7 |
| cookie 清空再登录 | 每次登录前 clearAuthArtifacts（保留瑞数 WAF cookie） | 登录本身成本，不放大次数 | direct_school_campus_gateway.dart:252-268, 3029 |
| 失败反馈回路（已抑制） | 会话过期->重登->若 WAF 拦截->BotChallengeFailure->下次数据访问再试 | 由 10 次/小时配额 + 引导器冷却封顶；BotChallenge 不触发熔断（缺口 G3） | direct_school_campus_gateway.dart:2913-2923；session.dart:659-662 |

## 五、现有防护措施评估

### 5.1 防护清单与完整性

| 防护 | 实现 | 评估 |
|---|---|---|
| 自动登录频控 10 次/小时（滑动窗口） | session_service.dart:189-215；调用点：Gateway :2897-2904, 3012-3020、后台 background_task.dart:581、引导器 :355/371 | 核心防护；跨前台/后台/WebView 全局生效。缺陷：无最小间隔（G1）。 |
| 认证熔断器 | AuthInvalidFailure 一次即熔断，之后静默登录直接抛错；手动登录/绑定成功后复位 | 账号级防护强（连续失败 <= 1-2 次）。缺陷：仅对密码错误类失败触发（G3）。 |
| in-flight 去重 | _reloginInFlight 共享 Future | 防并发风暴（历史缺陷已修复并有回归测试） |
| 单会话静默登录一次守卫 | _silentLoginAttemptedInSession | 防止单会话内反复重登 |
| 引导器冷却与安全检测 | _hasSubmittedCasThisRun（30 分钟）、验证码检测（15 分钟）、致命错误检测（30 分钟）、提交前检查频控 | 防 WebView 自动循环；见 silent_zove_token_bootstrapper.dart:314-367 |
| 自托管恢复退避 | 30s->10min 指数退避 | 防恢复风暴（selfHosted 模式） |
| WebView 手动页不自动提交 | 仅自动填表（登录页/服务页/请假页） | 用户介入才提交 |

### 5.2 缺口清单（影响频率上限的确定）

- G1（频控无最小间隔）：recordAutoLoginAttempt 只做滑动窗口计数（session_service.dart:189-198），canAttemptAutoLogin 只比次数（:201-215）。10 次配额可在 1 分钟内全部消耗 -> 最坏 20 个 CAS 请求突发，且触发"10 分钟内多次失败"类风控（学校侧此类阈值无法验证）。
- G2（手动登录不计频控）：loginWithPassword（:2228-2229，forceRelogin(isSilent:false) 在 :3021-3024 跳过频控与守卫）与 WebView 手动提交均不调用 recordAutoLoginAttempt。用户可无限次手动重试失败密码（测试 direct_gateway_challenger_test.dart:732-754 明确验证该行为是有意为之）。这是账号冻结风险最高的路径（学校侧"连续失败即冻结"正是针对密码失败计数）。
- G3（熔断器覆盖面窄）：BotChallengeFailure/CaptchaRequiredFailure 等安全类失败不触发熔断（direct_school_campus_gateway.dart:2919-2923 只对 AuthInvalidFailure 特判；session.dart:659-662 明确将 botChallenge 排除在可恢复之外但无熔断）。在 WAF 持续拦截场景下，静默登录会反复消耗 10 次/小时配额。
- G4（体育系统无频控）：sport.cqjtu.edu.cn 为独立认证体系，directLogin 无任何应用侧限流（campus_running_page.dart:202）。其冻结阈值完全在学校侧、无法验证。

## 六、风险模型

### 6.1 维度矩阵

| 维度 | 现状 | 风险点 |
|---|---|---|
| 每小时请求率 | 自动登录 <=10 次/小时（=20 CAS 请求）；健康会话实际 0 次 | 突发 20 请求/分钟（G1） |
| 突发模式 | 无间隔约束，可 1 分钟打满 | 触发按分钟/10 分钟窗口计数的风控 |
| 失败反馈回路 | 密码错误 -> 熔断（连续失败 <=1-2）；WAF/验证码失败 -> 不熔断但耗配额 | G3 下每小时最多 10 次安全类失败 |
| IP vs 账号级信号 | 账号级：CAS 密码失败计数（无法验证阈值）；IP 级：瑞数 WAF 行为评分（:319-377） | WAF 对自动化行为的判定阈值无法验证；校园网可能共享出口 IP |
| 时段 | 夜间 3 小时周期降低请求量 | 低 |
| 验证码/挑战响应 | 检测到验证码即中止静默登录（bootstrapper.dart:329-339、gateway.dart:813-815） | 低；若学校侧"出现验证码后仍计数失败"，则 G1/G3 会放大 |

### 6.2 场景评级

| 场景 | 每小时间接登录请求 | 冻结风险 | 评级 |
|---|---|---|---|
| S1 健康会话、正常使用 | 0 次凭据提交；仅探测 | 无 | 低 |
| S2 会话过期但 Cookie 有效 | 0 次凭据提交（cookie 恢复，:2886-2895） | 无 | 低 |
| S3 会话过期需重登（密码正确） | <=10 次（通常 1 次成功即恢复） | 低（成功登录一般不触发失败计数；突发风险见 G1） | 中低 |
| S4 密码错误/被改 | 1 次即熔断，后续为 0 | 低（熔断器生效） | 低 |
| S5 WAF 持续拦截 | <=10 次安全类失败/小时（不熔断） | 中（IP 级 WAF 判定；账号级一般不计数"未到密码校验"的失败） | 中 |
| S6 用户手动反复失败 | 无上限（G2） | 高（学校侧密码失败计数直接命中） | 高 |
| S7 体育系统手动反复失败 | 无上限（G4） | 中-高（独立系统，阈值无法验证） | 高 |
| S8 自托管后端聚合 | 后端 IP 聚合多用户 | 中（需后端侧按账号限流） | 中 |

## 七、最高安全登录频率建议（量化）

### 7.1 建议值

> 自动登录凭据提交：<= 6 次/小时，且相邻两次尝试最小间隔 >= 5 分钟。
> 手动登录：同样纳入频控（独立或共用 5 次/小时上限，见 8.2）。

（当前代码实际为 10 次/小时滑动窗口、无间隔；本建议为收紧，改动点为 session_service.dart:201-215 的默认值与 recordAutoLoginAttempt 增加间隔检查，属配置级改动。）

### 7.2 量化依据

**计算 1：请求率上界**
- 每次完整密码登录 = 2 个 CAS 请求（:796-799, :848-860）。
- 建议上限 6 次/小时 -> 最坏 12 个 CAS 认证请求/小时。
- 对比现状 10 次/小时 -> 最坏 20 个请求/小时；建议值降低 40%。

**计算 2：突发上界**
- 强制 >=5 分钟间隔 -> 任意 10 分钟窗口内最多 2 次尝试（含成功/失败）；任意 60 分钟窗口 <= 6 次。
- 现状：1 分钟 10 次（20 请求突发）。建议值将突发降低 5 倍。

**计算 3：对冻结阈值的裕度**
- 假设学校侧采用常见阈值 T = 5 次连续密码失败 -> 冻结（该值无法验证，见第九节；此处仅作裕度测算）。
- 熔断器保证连续 AuthInvalidFailure <= 1-2 次（:2913-2918）-> 裕度 >= 2.5 倍（T/2）。
- 安全类失败（WAF/验证码）按建议限 6 次/小时、>=5 分钟间隔 -> 任意 10 分钟窗口 <= 2 次 -> 若学校对"任意失败"也计数，裕度仍 >= 2.5 倍。
- 若学校侧阈值更严（T=3）：建议下调为 4 次/小时 + >=10 分钟间隔（任意 10 分钟 <= 1 次，裕度 3 倍）。

**计算 4：后台与引导器自身频率是否达标**
- 后台任务白天 4 次/小时（15 分钟周期，polling_utils.dart:1）：每轮最多 1 次静默登录且受全局 6 次/小时约束 -> 达标。
- 引导器 25 分钟周期（2.4 次/小时，bootstrapper.dart:42）：提交前检查 canAttemptAutoLogin（:355）-> 达标；其 4 次页面加载/周期为探测性质，不属凭据提交。

结论：6 次/小时 + 5 分钟间隔在"最坏请求量（12/h）""突发（10 分钟 <=2 次）""失败裕度（>=2.5 倍）"三个维度均留有安全边际，且不影响正常使用（健康会话下自动登录实际为 0 次/小时；会话过期场景通常 1 次即恢复）。

## 八、代码级加固建议（描述，不实施）

1. R1：频控增加最小间隔——在 recordAutoLoginAttempt（session_service.dart:189）中追加"距上次尝试 >=5 分钟"检查（或 canAttemptAutoLogin 增加 minInterval 参数）；不满足时不记录、直接返回不可尝试。一处修改，Gateway/后台/引导器全部生效。
2. R2：手动登录纳入频控——loginWithPassword（direct_school_campus_gateway.dart:2228-2229）与 WebView 提交后，对失败结果调用 recordAutoLoginAttempt（成功可清空或不清空，由产品定）；建议手动失败独立上限 5 次/小时，超过即强制走 WebView + 人工验证。
3. R3：扩大熔断覆盖面——连续 N 次（如 3 次）BotChallengeFailure/CaptchaRequiredFailure 后进入冷却（复用现有 markAuthCircuitBroken 或引入独立冷却键），防止 WAF 拦截场景下耗尽每小时配额。
4. R4：后台一卡通检查前同样检查频控——runLocalAndroidBalanceChecks（background_task.dart:301）目前不查 canAttemptAutoLogin（仅课表同步在 :581 查）；余额检查的 ensureEcardAuth 探测在会话失效时也会落到 CAS，建议统一前置检查。
5. R5：自托管后端侧限流——后端 /api/auth/loginWithTicket、/api/auth/createSession（api_service.dart:303-313）按账号增加频率上限（如 6 次/小时），防止后端 IP 聚合放大。
6. R6：修复过时注释——auth_providers.dart:68-69（"5 attempts"）、silent_zove_token_bootstrapper.dart:353（"最多 5 次"）、PROJECT.md:47（"（5次）"）均与实际 10 次/小时不符；若采纳本建议收紧为 6，三处注释与错误文案（gateway.dart:2901、main.dart:444、background_task.dart:584）应同步为最终值。
7. R7（可选）：引导器周期降频——_healthCheckInterval 25 分钟（bootstrapper.dart:42）在会话健康时每次引导产生 4 次页面加载；可改为按 _shouldRefreshArtifacts 的新鲜度结果动态跳过（已有 force 分支，bootstrapper.dart:143-149），进一步降低探测量。

## 九、无法验证项（明确声明）

以下项目无法从代码验证，报告中凡引用学校侧阈值处均属"常见行业实践假设"，不应视为已证实事实：

1. 学校侧账号冻结阈值与锁定时长：CAS 密码失败多少次触发冻结、冻结多久——纯学校服务端配置，代码不可见。web_search 未能检索到重庆交通大学公开的锁定策略；ids.cqjtu.edu.cn 在本评估环境解析为非公网 IP（web_fetch 被拒：URL hostname resolves to a non-public IP address），无法在线核验帮助文档。仅能从应用自身错误文案（direct_school_campus_gateway.dart:1142-1163 含 锁定/冻结/已被禁用/account locked）确认学校系统存在此类状态返回。
2. 学校侧是否对"成功登录"计数：部分系统对成功登录也有频率异常检测，无法验证。
3. 瑞数 WAF 行为评分阈值：_isBotChallengeResponse（:319-377）只识别 412/202 挑战页；WAF 对同 IP 高频登录的具体容忍度不可知。
4. 校园网出口 IP 共享情况：同校多用户是否共享出口 IP、WAF 是否按 IP 聚合计数，不可知。
5. 体育系统（sport.cqjtu.edu.cn）冻结策略：独立认证体系（MD5+验证码），无公开信息。
6. 自托管部署的后端实际 IP 与多租户聚合规模：取决于部署方，代码层不可见。
7. 手机端实际网络环境（4G/校园网/VPN）与 CAS 可达性：本环境探测到 CAS 为非公网解析，但无法代表所有用户网络。

## 附录 A：证据命令与关键结果

**执行的检索/读取（grep 命令均为 ripgrep 语法，路径为 G:\app）：**

1. grep (authService|directLogin|fetchCaptcha|Timer|periodic|syncOfficialData) apps\campus_app\lib\pages\campus_running_page.dart -> 命中仅 :77/:142/:222（fetchCaptcha）、:202（directLogin）、:466/:478（syncOfficialData）；无定时器。
2. grep (recordAutoLoginAttempt|canAttemptAutoLogin) -r -> 全仓命中显示定义与调用点共 5 处生产代码：session_service.dart:189/:201、gateway.dart:2898/:2904/:3013/:3019、background_task.dart:581、bootstrapper.dart:355/:371；测试确认手动登录不计数（direct_gateway_challenger_test.dart:732-754）。
3. grep loginWithTicket -r -> 34 处；生产调用点：web_login_binder.dart:85（本地）、web_login_binder.dart:141/session.dart:291（自托管后端）、background_task.dart:934；Gateway 实现 :957, :2202, :2932。
4. grep authserver -r -> 82 处；确认全部 CAS 交互点（网关 :99-100/:796-799/:848-860/:963-967、引导器 :35/:93、WebView 登录页 :35/:98、工具页 :148、请假页 :285、桥接 :38/:130/:168/:178）。
5. grep forceRelogin -r -> 21 处；Gateway 调用点 :2229, :2285, :2389, :2454, :2491, :2507, :2527, :2559。
6. grep Timer\.periodic apps\campus_app\lib -> 仅 bootstrapper.dart:112（25 分钟）与 gps_running_service.dart:146（1 秒，纯 GPS 无网络）。确认无其他自动登录定时器。
7. grep createSession -r -> 21 处；确认 createSession 仅存在于自托管路径（后端 API），本地直连不创建会话。
8. grep DirectSchoolCampusGateway\( -r -> 确认前台 Gateway 经 runtime_mode.dart:42-44 注入 sessionStore: sessionService，与引导器/后台共享频控存储。
9. read 全量/分段读取：session_service.dart（292 行全读）、direct_school_campus_gateway.dart（3116 行分段，含 :782-1081 认证器、:2119-3059 会话与数据方法）、session.dart（752 行关键段，含 :403-751 恢复流程）、background_task.dart（1103 行全读）、silent_zove_token_bootstrapper.dart（632 行全读）、web_login_binder.dart（212 行全读）、login_page.dart（469 行）、webview_login_page.dart（577 行）、main.dart（770 行关键段 :78-101, :210-231, :438-479）、runtime_mode.dart、polling_utils.dart、academic_web_bridge.dart（326 行全读）、webview_session_scope.dart（45 行全读）、campus_service_webview_page.dart（305 行全读）、leave_apply_page.dart（关键段）、sports_schema_auth_service.dart（236 行全读）、sports_token_sync_service.dart（126 行全读）。
10. 测试佐证：session_service_test.dart（10 次/小时滑窗、1 小时后过期、按用户隔离、熔断阻断）、direct_gateway_challenger_test.dart:527-550（9 次可、第 10 次拒绝）、direct_gateway_relogin_storm_test.dart（并发风暴回归）、background_schedule_sync_test.dart:363-404/:971（频控与熔断跳过）、direct_gateway_hardening_test.dart:454（限流时 SessionExpiredFailure）。
11. 文档佐证：docs\fix-report-2026-08-22.md:579-611（成绩 9 串行请求）、:613-658（并发重登风暴与 _reloginInFlight 修复）、:734-745（9 vs 2 次验证）。
12. web_search ×2（学校锁定策略、常见 CAS 阈值、瑞数 WAF）-> 未检索到重庆交通大学公开锁定策略；web_fetch ids.cqjtu.edu.cn 帮助页 -> 被拒（非公网 IP），学校侧阈值列为无法验证项。

**频率/计数计算汇总（公式 + 数字）：**
- 每次密码登录请求数 = 1（GET 表单）+ 1（POST 凭据）= 2。
- 建议上限换算 = 6 次/小时 × 2 = 12 个 CAS 请求/小时（现状 10×2 = 20，建议值 -40%）。
- 突发换算 = 5 分钟间隔 -> 10 分钟窗口 <= 2 次、60 分钟 <= 6 次（现状 1 分钟 10 次，突发 -5 倍）。
- 冻结裕度（假设学校阈值 5 次连续失败，无法验证）= 熔断后连续失败 <=2 -> 裕度 >=2.5 倍；安全类失败 10 分钟窗口 <=2 -> 裕度 >=2.5 倍。
- 引导器页面加载量 = 60/25 分钟 = 2.4 次/小时 × 4 页面 = 约 9.6 次探测/小时（非凭据提交）。
- 后台任务周期 = 白天 60/15 = 4 次/小时，夜间 60/180 = 0.33 次/小时。

---

*报告完。本报告仅创建 G:\app\docs\login-frequency-risk-assessment.md 一个文件，未修改任何其他文件。*
