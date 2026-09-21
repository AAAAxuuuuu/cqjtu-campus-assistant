# 登录频率冻结风险 — 详细修复方案 v2（仅方案，不实施）

> 请求编号：R1-FIX v2
> 依据：G:/app/docs/login-frequency-risk-assessment.md（已通过独立文档审计 VICTORY CONFIRMED）
> 代码核实：本版补读了 6 个真实源文件，所有方法名/存储键/行号均来自实际代码（见附录 A），供实施时直接对照。
> 性质：本文件只描述修复设计，**不修改任何代码**。实施为独立任务。
> 版本：v2（v1 的详细化；新增 §2 代码地图、§6 存储设计、§7 文案 UX、§8 可观测性、§10 机制交互矩阵）。

---

## 1. 修复项总览（按优先级）

| 编号 | 对应缺口 | 修复内容 | 优先级 | 主要改动文件 |
|---|---|---|---|---|
| F1 | G1 | 自动登录频控：上限 10→6 次/小时 + 强制 ≥5 分钟最小间隔 | P0 | packages/platform/lib/services/session_service.dart |
| F2 | G2 | 手动登录失败纳入频控（独立键位 5 次/小时，成功清零） | P0 | session_service.dart + direct_school_campus_gateway.dart |
| F3 | G3 | 熔断/冷却覆盖安全类失败（WAF/验证码，连续 3 次 → 冷却 30 分钟） | P1 | session_service.dart + gateway 失败分支 |
| F4 | G4 | 体育系统独立限流（5 次/小时） | P1 | apps/campus_app/lib/features/running/services/sports_schema_auth_service.dart |
| F5 | R4 | 后台余额检查前门统一查频控 | P1 | packages/platform/lib/services/background_task.dart |
| F6 | R5 | selfHosted 后端按账号限流（6 次/小时 + 429） | P1 | 后端 + packages/data/lib/src/api_service.dart |
| F7 | R6 | 修正过时文案（5 次→6 次/小时，含间隔说明） | P2 | 见 §9 文案清单 |
| F8 | R7 | 引导器周期动态跳过（可选优化） | P2 | apps/campus_app/lib/widgets/silent_zove_token_bootstrapper.dart |

---

## 2. 现状代码地图（实施前必读，全部来自真实代码）

### 2.1 频控核心 — SessionService（packages/platform/lib/services/session_service.dart）

- 存储：FlutterSecureStorage（encryptedSharedPreferences），按用户隔离，键前缀：
  - `auto_login_attempts_<user>`：JSON 数组，元素为毫秒时间戳（loadAutoLoginAttempts :167-176 / saveAutoLoginAttempts :178-186）
  - `auth_circuit_broken_<user>`：字符串 'true'（isAuthCircuitBroken :134-138 / markAuthCircuitBroken :140-143 / resetAuthCircuitBreaker :145-148）
- 关键方法（真实签名）：
  - `Future<void> recordAutoLoginAttempt(String username, {DateTime? now})` :189-198 —— 剪掉 1 小时外的时间戳后**追加当前时间戳**，无间隔检查。
  - `Future<bool> canAttemptAutoLogin(String username, {DateTime? now, int maxAttemptsPerHour = 10})` :201-216 —— 先查熔断（:206），再数 1 小时窗口内次数 < maxAttemptsPerHour（:215）。**默认值 10 内联在参数里**。
  - `Future<int> getRemainingAutoLoginAttempts(String username, {DateTime? now, int maxAttemptsPerHour = 10})` :219-235。
  - `Future<void> clearAutoLoginAttempts(String username)` :238-240 —— 删除键（已存在，F2 成功清零可直接复用思路）。
- 结论：所有"限流"逻辑集中在这一个类，F1/F2/F3 的新逻辑都加在这里即可被全端共享（前台 Gateway、后台 isolate、WebView 引导器共用同一 SecureStorage）。

### 2.2 调用链（谁在什么时机计数）

| 调用方 | 代码位置 | 行为 |
|---|---|---|
| Gateway _Session.ensureAuth | direct_school_campus_gateway.dart:2897-2904 | canAttemptAutoLogin → 不通过抛 SessionExpiredFailure('自动登录已达每小时上限（10次）…')；通过则 recordAutoLoginAttempt |
| Gateway _Session.forceRelogin（isSilent:true） | 同上 :3012-3019 | 同上 |
| Gateway forceRelogin（isSilent:false，手动） | 同上 :3021-3024 | **跳过频控与守卫**（重置 _silentLoginAttemptedInSession、_lastSilentLoginFailure）|
| 隐藏 WebView 引导器 _handleCasLoginPage | silent_zove_token_bootstrapper.dart:355（检查）/ :371（记录） | 检查不通过 → 30 分钟冷却；记录后自动填表提交 |
| 后台课表同步 | background_task.dart:581 | canAttemptAutoLogin 不通过 → 跳过本轮同步 |
| 后台余额检查 runLocalAndroidBalanceChecks | background_task.dart:319-325 | **只查熔断，不查频控**（R4 缺口）|

### 2.3 熔断器现状（G3 缺口的位置）

- ensureAuth：`on AuthInvalidFailure` → isInMemoryCircuitBroken + markCircuitBroken（:2913-2918）；**其他异常（含 BotChallengeFailure/CaptchaRequiredFailure）只 rethrow，不熔断**（:2919-2923）。
- forceRelogin 同构（:3036-3041 / :3042-3046）。
- 手动路径成功后 resetAuthCircuitBreaker：loginWithPassword :2230、loginWithTicket :2208、loginWithCookies :2260、resetLoginSession :2223。
- 注意：安全类失败已经 recordAutoLoginAttempt（消耗 6/h 配额）但不熔断 —— 这就是 G3。

### 2.4 手动登录现状（G2 缺口的位置）

- `Future<void> loginWithPassword(String username, String password)` :2228-2231 —— `await _session(username).forceRelogin(username, password, isSilent: false); await resetAuthCircuitBreaker(username);`
- `Future<void> loginWithTicket(String username, String ticket)` :2202-2209 —— WebView 网页登录成功后兑换，一次性 ticket，不计数合理。
- WebView 手动提交（apps/campus_app/lib/pages/webview_login_page.dart:98-101）仅自动填表，提交由用户触发；失败计数需在 CAS 错误页检测（见 F2 可选方案）。
- 测试佐证：direct_gateway_challenger_test.dart:732-754 明确验证 manual login 不调用 recordAutoLoginAttempt（**F2 将改变这一行为**，需同步改测试）。

### 2.5 体育系统（G4）

- SportsSchemaAuthService（apps/campus_app/lib/features/running/services/sports_schema_auth_service.dart:134-232）：
  - `Future<CaptchaData?> fetchCaptcha()` :154-176（GET /captcha，不涉及凭据）
  - `Future<({bool success, String message, String? token})> directLogin({required String username, required String password, required String captcha, required String key})` :179-231（POST /do_login，MD5 密码）
  - 无任何频控；provider：sportsSchemaAuthProvider :234-236。

### 2.6 selfHosted 后端（R5）

- ApiService（packages/data/lib/src/api_service.dart —— 注意路径不是 self_hosted 子目录）：
  - `Future<String> createSession(String username)` :32-43（POST /api/auth/createSession?username=...）
  - `Future<void> loginWithTicket(String username, String ticket, {required String sessionId})` :303-321（POST /api/auth/loginWithTicket?username=&ticket=&sessionId=）
  - 手机端只负责调用；频控需后端实现。

### 2.7 并发与去重（不能破坏的既有机制）

- `_reloginInFlight` 共享 Future：gateway :2834 / :2848-2849 / :2926-2929 / :2984-2985 / :3049-3052 —— 并发重登合并为一次（历史风暴修复，docs/fix-report-2026-08-22.md:613-658）。
- `_silentLoginAttemptedInSession` 单会话守卫：ensureAuth :2865 / forceRelogin :3001。
- 引导器冷却：_hasSubmittedCasThisRun → 30 分钟；验证码 → 15 分钟；致命错误 → 30 分钟（bootstrapper.dart:314-351）。

---

## 3. F1（P0，G1）：自动登录上限收紧 + 最小间隔

### 3.1 目标行为

自动登录（前台数据访问/后台/WebView 引导三类静默路径）凭据提交 **≤ 6 次/小时**，且**相邻两次间隔 ≥ 5 分钟**；间隔不足时不记录、直接拒绝尝试。

### 3.2 实现要点（全部落在 session_service.dart）

1. **常量集中**（文件顶部，替换 :204/:222 的内联默认值）：
   - `static const int maxAutoLoginAttemptsPerHour = 6;`
   - `static const Duration minAutoLoginInterval = Duration(minutes: 5);`
2. **canAttemptAutoLogin 扩展**（:201-216）：
   - 签名：`Future<bool> canAttemptAutoLogin(String username, {DateTime? now, int maxAttemptsPerHour = maxAutoLoginAttemptsPerHour, Duration minInterval = minAutoLoginInterval})`
   - 逻辑顺序：熔断 → 剪枝（>1h 去掉）→ **间隔检查**：`attempts.isNotEmpty && now - DateTime.fromMillisecondsSinceEpoch(attempts.last) < minInterval → false` → 次数检查：`attempts.length < maxAttemptsPerHour`。
   - 向后兼容：默认参数变化即可让 gateway :2897、:3012、bootstrapper :355、background_task :581 全部生效，**零调用点改动**。
3. **recordAutoLoginAttempt 增加防竞态二次检查**（:189-198）：
   - 加参数 `Duration minInterval = minAutoLoginInterval`；写入前若距最近时间戳 < minInterval 则**不写入、直接返回**（防止两个并发调用都通过 canAttempt 后双双记录；SecureStorage 无跨进程锁，这是唯一能兜底的地方）。
   - 保持"剪枝+追加"语义不变。
4. **文案同步**：gateway :2901 / :3016 的 '自动登录已达每小时上限（10次）' 中的 10 改为动态或常量文案 '6 次/小时'（属 F7 文案项，此处一并落实）。

### 3.3 边界与竞态

| 场景 | 处理 |
|---|---|
| 前后台两个 isolate 并发通过 canAttempt | record 内二次间隔检查兜底；极端情况下次数上限仍可能 +1（窗口临界），可接受 |
| 时钟回拨（now 参数用于测试，生产用 DateTime.now()） | 间隔基于差值，回拨 5 分钟内会拒绝一次，安全方向 |
| 用户切换账号 | 键按用户隔离（`auto_login_attempts_<user>`），互不影响 |
| 已有存量数据（10/h 时代写入的时间戳） | 剪枝逻辑不变，自动降级为新上限，无需迁移 |
| 成功登录后 | 现有 resetCircuitBreaker 逻辑不动；间隔从**上一次尝试**起算（含成功）——保守方向 |

### 3.4 测试用例（新增/修改）

| 用例 | 输入 | 期望 |
|---|---|---|
| 间隔拒绝 | 记录 t=0，t+3min 调 canAttempt | false；record 不写入 |
| 间隔放行 | 记录 t=0，t+5min 调 canAttempt | true |
| 次数边界 | 6 次记录后调 canAttempt | false；第 7 次（1h 后）→ true |
| 并发兜底 | 两次 record 几乎同时（间隔 3min） | 第二次不写入，列表仍 1 条 |
| 熔断优先 | 熔断 true + 窗口空 | false（熔断优先于间隔/次数）|
| 回归 | session_service_test 现有 10/h 用例 | 迁移为 6/h 后全部通过 |

### 3.5 验收标准

- 任意 60 分钟窗口内凭据提交 ≤ 6 次；任意 10 分钟窗口 ≤ 2 次（6/h 且 ≥5min 间隔的推论）。
- gateway/后台/引导器三处调用点零改动即生效（单测验证三处入口）。
- direct_gateway_relogin_storm_test 仍为 **2 次 CAS 请求**（风暴回归不破）。

---

## 4. F2（P0，G2）：手动登录失败纳入频控

### 4.1 目标行为

手动密码登录（loginWithPassword）与 WebView 手动提交的**失败**计入独立频控：**5 次失败/小时**；成功登录**清零**；超限给出友好提示且不硬阻断（可引导网页登录）。

### 4.2 实现要点

1. **SessionService 新增方法**（仿照 :167-240 的现成模式）：
   - 新键：`manual_login_attempts_<user>`（JSON 毫秒时间戳数组）
   - `Future<bool> canAttemptManualLogin(String username, {DateTime? now, int maxManualAttemptsPerHour = 5})` —— 只数窗口不查熔断（手动登录是熔断的复位途径，不能被熔断锁死）
   - `Future<void> recordManualLoginAttempt(String username, {DateTime? now})`
   - `Future<void> clearManualLoginAttempts(String username)`（对照 clearAutoLoginAttempts :238-240）
   - **clearLoginArtifacts :151-165 增加删除新键**（退出登录/切换账号时清理，防止残留键堆积）
2. **Gateway loginWithPassword**（:2228-2231）改造：
   - 入口：`if (!await _sessionStore?.canAttemptManualLogin(username)) throw ManualLoginRateLimitedFailure('密码错误次数过多，请稍后再试或使用网页登录');`
   - 成功：`await resetAuthCircuitBreaker(username); await _sessionStore?.clearManualLoginAttempts(username);`
   - 失败：`on AuthInvalidFailure { await _sessionStore?.recordManualLoginAttempt(username); rethrow; }` —— **仅密码类失败计数**；网络错误/超时/服务异常不计数（避免网络抖动误伤）。
   - 新异常类型：`ManualLoginRateLimitedFailure extends CampusFailure`（放在 gateway 异常定义处，参照 SessionExpiredFailure）。
3. **WebView 手动提交（可选，P1.5）**：webview_login_page.dart 提交后的 CAS 错误页检测（错误文案含 错误/锁定/无效，参照 bootstrapper._checkCasPageSecurity :386-425 的 JS 检测思路）→ 命中即 recordManualLoginAttempt；超过 5 次弹出确认对话框（不硬阻断）。列为可选项，因为 WebView 内计数依赖页面结构，脆弱。
4. **UI 联动**：登录页（apps/campus_app/lib/pages/login_page.dart:58/:110）捕获 ManualLoginRateLimitedFailure → 提示"密码错误次数过多，请 30 分钟后再试或使用网页登录"；新增 Riverpod provider `manualLoginRateLimitedProvider`（对照 autoLoginRateLimitedProvider，auth_providers.dart:68-69）供登录页显示状态。

### 4.3 边界与竞态

| 场景 | 处理 |
|---|---|
| 手动成功是否清自动登录窗口？ | 否 —— 手动与自动键位独立（F2 设计意图），避免手动成功把自动配额清零造成突发 |
| 熔断激活时手动登录 | 手动路径不受熔断阻断（复位熔断正是手动登录的职责，:2230 现有逻辑）；但受 5/h 失败上限约束 |
| 用户多次输错同一密码 | 第 6 次被拦 → 提示网页登录 → loginWithTicket 一次成功清零 |
| WebView 路径未实现计数时 | 至少 loginWithPassword 覆盖主入口（测试已验证用户主路径）|

### 4.4 测试用例

| 用例 | 输入 | 期望 |
|---|---|---|
| 手动失败计数 | 5 次 AuthInvalidFailure 后第 6 次 loginWithPassword | 抛 ManualLoginRateLimitedFailure，未发请求 |
| 成功清零 | 2 次失败后成功登录 | 计数清零，下次失败从 1 起算 |
| 不计数类型 | 网络异常（非 AuthInvalidFailure）| 不记录 |
| 独立于自动 | 手动 5 次打满后 canAttemptAutoLogin | 仍 true（互不影响）|
| **行为变更** | 现有 direct_gateway_challenger_test.dart:732-754（断言 manual 不计数）| 改为断言"失败才计数、成功清零" |

### 4.5 验收标准

- 连续 5 次密码错误后第 6 次被拦，提示友好；改用网页登录成功后可继续。
- 自动登录频控不受手动失败影响（6/h 独立）。

---

## 5. F3（P1，G3）：安全类失败熔断/冷却

### 5.1 目标行为

BotChallengeFailure / CaptchaRequiredFailure（瑞数 WAF 412/202、验证码）**连续 3 次** → 进入 30 分钟冷却；冷却期内静默登录直接跳过（不消耗 6/h 配额）；成功登录后复位。

### 5.2 实现要点

1. **SessionService 新增键与方法**：
   - 新键：`security_failure_state_<user>`，值 JSON `{"count": n, "untilMs": ms}`（untilMs 为冷却截止，0 表示无冷却）
   - `Future<void> recordSecurityFailure(String username, {DateTime? now})` —— count+1；count ≥ 3 → untilMs = now + 30min，count 置 0（避免永久累积）
   - `Future<bool> isInSecurityCooldown(String username, {DateTime? now})` —— untilMs > now
   - `Future<void> resetSecurityFailures(String username)` —— 删除键
   - **clearLoginArtifacts :151-165 增加删除新键**
2. **Gateway 失败分支改造**（ensureAuth :2919-2923 与 forceRelogin :3042-3046 两处通用 catch）：
   - 在 `catch (e)` 内：`if (e is BotChallengeFailure || e is CaptchaRequiredFailure) { await _sessionStore?.recordSecurityFailure(username); if (await _sessionStore?.isInSecurityCooldown(username)) { _silentLoginAttemptedInSession = true; } } rethrow;`
   - 在 canAttemptAutoLogin 之前（:2897 前 / :3012 前）加：`if (await _sessionStore?.isInSecurityCooldown(username)) { _silentLoginAttemptedInSession = true; throw const SessionExpiredFailure('触发安全防护，请稍后手动登录'); }`
3. **成功复位**：ensureAuth :2912 / forceRelogin :3035 的 resetCircuitBreaker 旁追加 `await _sessionStore?.resetSecurityFailures(username);`（手动路径 loginWithPassword/loginWithTicket 成功后同样复位）。

### 5.3 边界

| 场景 | 处理 |
|---|---|
| WAF 持续拦截 | 3 次后冷却 30min，静默路径全部跳过，配额不再被耗尽 |
| 混合失败（1 安全 + 2 密码错误） | 安全计数与熔断器独立，分别累计 |
| 冷却期用户手动登录 | 手动不受冷却影响（冷却只挡静默）|
| 成功登录复位 | 冷却与熔断一起复位 |

### 5.4 测试用例

- 连续 3 次 BotChallengeFailure → 第 4 次 ensureAuth 抛 SessionExpiredFailure（冷却文案），未调用 login。
- 冷却期 canAttemptAutoLogin 返回 true 但 isInSecurityCooldown 拦截（验证分层）。
- 1 次成功登录 → 冷却清零，第 4 次尝试恢复计数。
- 与 F1 间隔共存：冷却期不写 attempt 时间戳（验证配额不被消耗）。

---

## 6. F4（P1，G4）：体育系统独立限流

### 6.1 目标行为

sport.cqjtu.edu.cn 的 directLogin **≤ 5 次/小时**（滑动窗口）；fetchCaptcha 不计数；超限直接返回失败文案，不发请求。

### 6.2 实现要点

1. **复用 SessionService 泛化**（推荐，与 F2 的手动键位同构）：
   - 新增专用键 `sports_login_attempts_<user>`（体育系统独立认证，语义清晰，且不占手动登录的 5/h 名额），常量 `maxSportsLoginAttemptsPerHour = 5`。
2. **SportsSchemaAuthService 改造**（sports_schema_auth_service.dart:179-231）：
   - 构造时经 `ref.read(sessionServiceProvider)` 获取 SessionService（现有 provider :234-236 可注入）。
   - directLogin 入口：`if (!await session.canAttemptSportsLogin(username)) return (success: false, message: '登录尝试过于频繁，请稍后再试', token: null);`
   - **失败才计数，成功清零**（与 F2 一致）；fetchCaptcha 不计数。
3. **UI**：campus_running_page.dart:202 的 directLogin 调用处无需改动（失败 message 已透出）。

### 6.3 测试用例

- 5 次失败后第 6 次 directLogin → 返回 (false, '登录尝试过于频繁…')，断言 _dio.post 未被调用（可注入 mock Dio）。
- fetchCaptcha 连续调用不消耗配额。

---

## 7. F5（P1，R4）：后台余额检查前门频控

### 7.1 目标行为

runLocalAndroidBalanceChecks 在熔断检查（background_task.dart:319-325）之后追加频控检查；窗口打满时**整批跳过**，不发探测/取数请求。

### 7.2 实现要点

- 在 :325 的熔断检查块后加：
  `if (!await session.canAttemptAutoLogin(username)) { debugPrint('[BG] auto-login rate limit exceeded for <user>, skipping balance checks'); return false; }`
- 无需改 getElecBalance / getCampusCardBalance 内部（它们走 gateway.ensureAuth，已有频控；前门检查只是提前短路，减少探测请求量）。
- 注释 :573 的 "(<= 10 attempts per hour)" 属 F7 文案项，一并改为 6。

### 7.3 测试

- background 测试：预置 6 次 attempt → runLocalAndroidBalanceChecks 返回 false，且无通知（_notifyElecIfNeeded / _notifyCardIfNeeded 未触发）。

---

## 8. F6（P1，R5）：selfHosted 后端按账号限流

### 8.1 目标行为

后端 /api/auth/createSession（api_service.dart:32-43）与 /api/auth/loginWithTicket（:303-321）按账号 **≤ 6 次/小时**，超限返回 HTTP 429 + Retry-After；手机端识别 429 后走现有指数退避（session.dart:680-686，30s→10min 上限）延后重试。

### 8.2 实现要点（后端独立实施，手机端配合）

- 后端：按 username 的滑动窗口（内存 + Redis/DB 持久化），窗口 1 小时上限 6；429 body 含 retryAfterSec。
- 手机端 ApiService：`createSession` / `loginWithTicket` 捕获 `res.statusCode == 429` → 抛 `ApiException(429, '登录过于频繁，请稍后再试')`；上层恢复流程（session.dart:680-686 已有退避）捕获后按 retryAfter 延后。
- 说明：createSession/loginWithTicket 是**会话建立**接口（一次成功登录后长期复用会话），6/h 不误伤正常使用；手机端本地直连模式不经过此接口（仅 selfHosted）。

### 8.3 测试

- 后端：压测 7 次/h → 第 7 次 429。
- 手机端：mock Dio 返回 429 → ApiException(429) 抛出；上层退避逻辑单测。

---

## 9. F7（P2，R6）：文案修正清单

| 位置 | 现值 | 改为 |
|---|---|---|
| apps/campus_app/lib/features/auth/auth_providers.dart:68-69 | "1-hour 5-attempts auto-login limit" | "1-hour 6-attempts auto-login limit, min 5-min interval" |
| apps/campus_app/lib/widgets/silent_zove_token_bootstrapper.dart:353 | 注释 "最多 5 次" | "最多 6 次，间隔 5 分钟" |
| 同上 :358 | debugPrint "(10 attempts)" | "(6/hr, 5-min interval)" |
| direct_school_campus_gateway.dart:2901 / :3016 | '自动登录已达每小时上限（10次）…' | '自动登录已达每小时上限（6次），请稍后重试或手动登录' |
| main.dart:444 | 提示文案中的 5/10 数字 | 6 次/小时 |
| background_task.dart:573 / :584 | 注释与日志 "(<= 10 attempts per hour)" / "(10/hr)" | 6/hr |
| PROJECT.md:47 | "每小时上限（5次）" | "每小时上限（6次），最小间隔 5 分钟" |

验收：`grep -i "5-attempts|最多 5 次|（5次）|(10/hr)|（10次）"` 全仓 0 命中。

---

## 10. 机制交互矩阵（新增）

| 机制 | 触发条件 | 与 F1-F8 的关系 | 冲突风险 |
|---|---|---|---|
| 自动频控 F1 | 静默路径尝试 | F3 冷却期跳过 → 不耗配额；F5 前门短路 → 更早退出 | 无 |
| 手动频控 F2 | 手动失败 | 与自动键位独立；熔断复位不受限 | 手动成功清零仅清手动键 |
| 密码熔断器 | AuthInvalidFailure | F3 与其并行（安全类走冷却、密码类走熔断）；成功登录同时复位两者 | 无 |
| _reloginInFlight | 并发重登 | 所有频控检查都在 attempt 内部 → 并发合并后只消耗 1 次配额 | 无（勿改动 :2834 结构）|
| _silentLoginAttemptedInSession | 单会话 | F3 冷却期置 true → 与单会话守卫协同双保险 | 无 |
| 引导器冷却（30/15min） | CAS 页异常 | 与 F1 间隔互补：引导器冷却管"页面层"，F1 管"凭据提交层" | 双冷却叠加更保守，安全方向 |
| clearLoginArtifacts | 退出登录/切换 | 需新增删除 manual/sports/security 三个新键 | 遗漏会导致跨账号残留 |
| autoLoginRateLimitedProvider | 频控命中 UI 态 | F2 新增 manualLoginRateLimitedProvider 同构 | 无 |

---

## 11. 配置化与发布灰度

1. **常量集中**：F1-F4 的所有阈值（6/h、5min、5/h 手动、3 次、30min 冷却、5/h 体育）集中在 session_service.dart 顶部（体育键可放 sports service 顶部），便于评审与回滚。
2. **发布顺序**：P0（F1+F2）→ 观察 1 个版本（确认无用户投诉"登录被拦"）→ P1（F3+F4+F5+F6）→ P2（F7 文案、F8 优化）。
3. **灰度**：阈值属常量，无 feature flag 必要；若担心误伤，可先发 F1 的间隔 5min→3min 过渡版（保守起见直接 5min，风险低）。
4. **回滚**：所有改动独立成提交；回滚 = 恢复 session_service.dart 顶部常量 + revert 对应提交；F1 一处即可整体回退。
5. **验证**：每次发布跑 §12 全量回归。

---

## 12. 测试与回归验证清单

| 测试文件 | 涉及修复 | 说明 |
|---|---|---|
| session_service_test.dart | F1/F2/F3 | 新增间隔/手动键/安全冷却用例；现有 10/h 用例迁移 6/h |
| direct_gateway_challenger_test.dart | F2 | :732-754 行为变更：手动失败才计数 |
| direct_gateway_relogin_storm_test.dart | F1 回归 | 必须仍为 2 次 CAS 请求（对照 fix-report-2026-08-22.md:734-745）|
| direct_gateway_hardening_test.dart | F1/F3 | :454 限流时 SessionExpiredFailure 用例保持 |
| background_schedule_sync_test.dart | F1/F5 | :363-404 频控跳过用例更新 10→6；新增余额前门短路用例 |
| bootstrapper 测试（如有）| F1/F8 | 引导器冷却与频控交互 |
| sports_schema_auth_service 测试 | F4 | mock Dio：第 6 次 directLogin 不发请求 |
| api_service 测试 | F6 | 429 → ApiException |
| 手动 e2e | F2 | 5 次错误 → 第 6 次拦截 → 网页登录成功 → 恢复 |

---

## 13. 风险与回滚（更新）

| 风险 | 缓解 |
|---|---|
| 5 分钟间隔误伤真实用户（会话反复失效） | 成功登录后立即放行下一次（间隔从上次**失败**起算的口径需产品确认）；间隔只约束尝试不约束成功 |
| 手动 5/h 过严 | 超限仅提示不硬阻断（WebView 路径）；成功清零 |
| WebView 错误页检测脆弱（F2 可选） | 标记 P1.5 可选；主入口 loginWithPassword 已覆盖 |
| 并发窗口 +1 | record 内二次检查兜底，极端可接受 |
| 新键清理遗漏 | clearLoginArtifacts 必须同步扩展（§6 存储设计）|

---

## 附录 A：涉及文件与行号索引（v2 核实基准）

| 文件 | 关键行 |
|---|---|
| packages/platform/lib/services/session_service.dart | 键前缀 :15-27；recordAutoLoginAttempt :189-198；canAttemptAutoLogin :201-216；getRemaining :219-235；clearAutoLoginAttempts :238-240；clearLoginArtifacts :151-165 |
| packages/data/lib/src/direct_school/direct_school_campus_gateway.dart | loginWithPassword :2228-2231；loginWithTicket :2202-2209；loginWithCookies :2247-2261；ensureAuth :2847-2930；forceRelogin :2979-3053；_reloginInFlight :2834/:2926-2929/:3049-3052；熔断分支 :2913-2923/:3036-3046；错误文案 :2901/:3016 |
| apps/campus_app/lib/widgets/silent_zove_token_bootstrapper.dart | 25min 定时器 :42/:112-116；_handleCasLoginPage :314-384；频控检查 :355 记录 :371；冷却 30/15min :319/:333/:345/:361；安全检测 JS :386-425 |
| packages/platform/lib/services/background_task.dart | 余额检查 :301-379（熔断 :319-325）；课表同步 :560-614（频控 :581）|
| apps/campus_app/lib/features/running/services/sports_schema_auth_service.dart | fetchCaptcha :154-176；directLogin :179-231；provider :234-236 |
| packages/data/lib/src/api_service.dart | createSession :32-43；loginWithTicket :303-321 |
| 文案 | auth_providers.dart:68-69；bootstrapper.dart:353/:358；gateway.dart:2901/:3016；main.dart:444；background_task.dart:573/:584；PROJECT.md:47 |
| 测试 | direct_gateway_challenger_test.dart:732-754；direct_gateway_relogin_storm_test.dart；direct_gateway_hardening_test.dart:454；background_schedule_sync_test.dart:363-404/:971 |

---

*方案完（v2）。本文件仅更新 G:/app/docs/login-frequency-fix-plan.md，未修改任何代码文件。*
