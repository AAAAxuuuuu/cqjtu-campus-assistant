# 测试与覆盖率基线

采集时间：2026-08-13，基准提交 5ebd516（提交于 2026-08-03 00:46 +0800）。
采集命令：各 package 目录下 `flutter test --coverage`，随后对 lcov.info 累加 LF/LH。

## 测试结果

| package | 结果 |
|---------|------|
| packages/core | 49 通过 |
| packages/data | 21 通过 + 5 跳过（live 测试需真实学号密码，默认 skip） |
| packages/platform | 76 通过 |
| apps/campus_app | 138 通过 |

合计：284 通过，5 跳过，0 失败。

## 行覆盖率（lcov）

| package | 覆盖行/总行 | 行覆盖率 |
|---------|------------|---------|
| packages/core | 283/391 | 72.4% |
| packages/data | 553/1,351 | 40.9% |
| packages/platform | 696/1,049 | 66.3% |
| apps/campus_app | 1,953/6,915 | 28.2% |
| 合计 | 3,485/9,706 | 35.9% |

## 与首版基线的对比

| package | 首版（改动前） | 当前 | 变化 |
|---------|--------------|------|------|
| core | 82.3% | 72.0% | -10.3pp（解析器从 app 迁入，分母增大） |
| data | 3.7% | 40.9% | +37.2pp（离线测试 + transport 注入 + 课表/成绩/考试/电费解析） |
| platform | 40.8% | 66.3% | +25.5pp（AppUpdate HTTP/ETag/304/回退 + 通知通道级 + 后台续排路径） |
| app | 20.7% | 28.2% | +7.5pp（刷新合并/账号安全、onData、SessionManager、按钮、重建探针） |
| 合计 | 21.9% | 35.9% | +14.0pp |

CI 门禁：四个 package 全部设覆盖率下限（core 60%、data 35%、platform 50%、
app 25%，tool/check_coverage.dart），任一低于下限 CI 直接失败。