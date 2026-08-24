# 性能实验基线（Measured-First 清单）

本文档对应改进意见报告中"需测量后再决策"的各项。每项在实施前必须先建立
可复现的实验基线；基线确认问题存在后才实施，实施后复测对比。

## 通用方法

- 帧率/重绘：Flutter DevTools Performance 页（UI/Raster 线程帧时间、Repaint
  Rainbow 重绘彩虹）。
- 启动耗时：`flutter run --profile` 后使用 DevTools "App start-up" 时间线，
  或 Android 上 `adb shell am start -W` 三次取中位数（cold/warm 各测）。
- 流量：HTTP 抓包（Charles/mitmproxy）统计单次刷新请求/响应体大小。
- 电量：Battery Historian / 系统电池用量页，固定场景脚本对比。

## 1. RepaintBoundary

- 实验：打开 Repaint Rainbow，在课表页切换周次，记录重绘区域与 Raster 帧时间。
- 2026-08-13 结构性证据（test/perf/schedule_grid_rebuild_probe_test.dart，
  宿主 VM 可复现）：一次周次切换重建 640 个 Widget / 73 种类型，其中
  Container=157、Positioned=144（课程格）、Text=56、_SlotCell=13（时间列，
  内容不随周次变化）、星期头相关 Text 等。结论：课程格随周切换重建属预期；
  时间列（_SlotCell×13 与其他静态装饰）内容与周次无关却每次重建/参与重绘，
  构成"静态区域随课程格一起重绘"的结构性证据。
- 已实施（定点，非批量）：时间列覆盖层包 RepaintBoundary
  （schedule_grid.dart，IgnorePointer 内层）。该边界隔离的是绘制而非重建，
  重建计数不变属预期；Raster 收益需真机复测。
- 复测：真机 DevTools Raster 帧时间对比；同时关注 layer 数量。若真机复测
  无收益或 layer 成本更高，回退该改动。
- 未实施（证据不足）：批量给每个课程格包 RepaintBoundary——课程格内容随
  周次变化，且批量边界会增加 layer/显存成本，报告明确判定为反模式。

## 2. ListView itemExtent/prototypeItem

- 2026-08-13 结构分类（静态证据）：全 app 仅 tools/exams_section.dart:76
  使用 ListView.builder；其余均为普通 ListView(children:)。关键发现：
  成绩列表（tools/grades_section.dart:67-91）用 spread 展开全部成绩行
  （...result.grades.map(GradeItem.new)），"查全部"学期下会一次性 eager
  构建数百行（元素树全部建出，布局/绘制仍是惰性）；成绩明细与考试页
  内容量小，profile/工具首页为固定少量卡片，不需要 itemExtent。
- 结论：结构风险集中在成绩列表的首屏构建规模与内存，而非滚动帧率
  （SliverChildListDelegate 布局惰性）。按报告判定条件（低端设备可感知
  掉帧）尚缺帧级证据，**暂不实施** ListView.builder 改造。
- 实验：真机/低端模拟（CPU throttling）打开"查全部"成绩页，DevTools
  记录首屏构建耗时与滚动帧时间；若可感知卡顿，将成绩列表改为
  ListView.builder + 固定行高（GradeItem 行高固定可量）并复测。

## 3. gzip/请求压缩

- 实验：对直连模式（jwgln/ecard/ids）与自部署后端分别抓包，确认响应是否
  带 Content-Encoding: gzip，及传输大小。
- 2026-08-13 探测结果：jwgln.cqjtu.edu.cn:443 TCP 可通，但 curl TLS 握手
  失败（exit 35），本环境无法完成抓包。属环境阻塞，需在能完成 TLS 握手
  的网络（如校园网/真机代理）中重试；自部署后端按部署配置确认。
- 触发实施的条件：抓包确认服务端支持 gzip 且当前未启用压缩。
- 复测：启用后对比传输字节数。

## 4. 网络失败自动重试

- 实验：在校园网弱网/CAS 故障时段统计失败率与恢复时间分布（可用后台日志
  debug_logs/ 中的记录）。
- 触发实施的条件：失败为短时抖动（秒级恢复）且重试不会放大服务器压力。
- 边界：重试必须指数退避、上限 3 次，先做连通性探测；CAS 大范围故障时
  不得自动重试。

## 5. 冷启动链（已实施代码变更 + 模拟器 A/B 基线）

- 现状：通知与 WorkManager 初始化已延迟到首帧之后（main.dart
  initializeBackgroundServices）。
- 2026-08-13 模拟器 A/B（Medium_Phone_API_36.1 无头模式，profile APK，
  `am start -W` TotalTime，各 5 次冷启动）：
  - 基线（5ebd516 原样）：5,983 / 4,747 / 3,732 / 4,430 / 5,580 ms，
    均值 4,894 ms，中位数 4,747 ms。
  - 改动后：4,717 / 3,950 / 6,275 / 4,113 / 5,079 ms，
    均值 4,827 ms，中位数 4,717 ms。
  - 结论：TotalTime 均值 -1.4%，中位数 -0.6%，均在模拟器噪声范围内，
    **不构成可声称的提升**。TotalTime 以 Activity 启动完成为准，受引擎
    初始化主导，无法反映"首帧前插件初始化后移"的收益。
- 处置：改动保留（机制上严格减少首帧前工作、测试证明时序正确、A/B 无
  回归），但**不做任何性能收益声明**；感知首帧收益需真机 DevTools
  frame 时间线对比（见"通用方法"），属外部设备条件。
- 复测方法：`adb shell am force-stop <pkg> && adb shell am start -W
  -n <pkg>/.MainActivity`，≥5 次取中位数。

## 附：WorkManager 后台提醒的真机验证清单

第三轮已修复后台隔离区的代码层缺陷（时区/插件懒初始化、关提醒清 seed、
legacy 清理 best-effort），并有通道级 mock 测试。但 mock 测试不等于真实
后台运行，以下验证必须在 Android 真机/模拟器上完成：

1. WorkManager 独立 FlutterEngine 是否注册了所需插件（flutter_local_
   notifications 的 dart_plugin_registrant 在后台引擎生效）。
2. 原生 ClassReminderManager 是否真正创建 alarm（dumpsys alarm 查看）。
3. fallback 到 flutter_local_notifications 时 class_reminder_v2 通道是否
   存在（Android 8+ 无通道则通知被丢弃）。
4. 进程重启/设备重启后提醒是否保留（BootReceiver 路径）。

验证方法：真机安装后 adb 触发 WorkManager 任务（或等待 15 分钟周期），
观察 logcat [BG] class reminders replenished from seed；再改系统时间到
窗口过期边界复测。

## 6. 前后台余额重叠请求（已实施回填，待统计频率）

- 现状：后台余额检查结果已回填前台缓存（background_task.dart
  backfillBalanceCaches），并记录 bg_elec_checked_at_ms/bg_card_checked_at_ms
  时间戳。
- 待测：读取这些时间戳与前台缓存 updatedAt，统计真实重叠频率；若频率高，
  再评估共享 in-flight 去重。