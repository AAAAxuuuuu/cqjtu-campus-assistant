# 发布构建

## 必须使用 `--split-per-abi`

```bash
cd apps/campus_app
flutter build apk --release --split-per-abi
```

产物（2026-08-22 实测）：

| ABI | 体积 | 适用设备 |
|-----|------|---------|
| `app-arm64-v8a-release.apk` | 24.8MB | 绝大多数现役 Android 手机 |
| `app-armeabi-v7a-release.apk` | 23.3MB | 32 位老设备 |
| `app-x86_64-release.apk` | 26.2MB | 模拟器 / x86 平板 |

**不要用不带参数的 `flutter build apk --release`。** 它产出 79MB 的 universal
APK，把三套 `libflutter.so` + `libapp.so` 全塞进一个包——用户下载两份自己
永远无法执行的原生运行时。

不要试图在 `android/app/build.gradle.kts` 里加 `splits { abi { ... } }` 来让
它变成默认行为：Flutter Gradle 插件已经设置了 `ndk.abiFilters`，Gradle 会直接
报错 `Conflicting configuration ... in ndk abiFilters cannot be present when
splits abi filters are set`。命令行参数是官方支持的唯一路径。

## 体积构成（arm64-v8a，24.8MB）

| 项 | 体积 | 说明 |
|----|------|------|
| `libflutter.so` | 11.3MB | Flutter 引擎，不可压缩 |
| `libapp.so` | 11.1MB | 编译后的 Dart 代码 |
| `NotoSansSC-Subset.ttf` | 2.4MB | PDF 导出用中文字体（见下） |
| `classes.dex` + `classes2.dex` | 2.3MB | Kotlin 原生层（小组件/闹钟/GPS） |
| 其余 | <1MB | 图标、资源表、清单 |

引擎 + Dart 代码占 22.4MB（90%），已接近 Flutter 应用的体积下限。

## 资源体积约束

两条容易回退的地方：

### 1. PDF 导出字体必须保持子集化

`assets/fonts/NotoSansSC-Subset.ttf`（2.4MB）是 Noto Sans SC 的 GB2312 子集，
字重固定为 Regular。

原始 `NotoSansSC-VF.ttf` 是 17.8MB 可变字体（31,036 字形，`wght` 100-900 轴），
曾占 arm64 包的 46.8%。它**不是 UI 字体**——`pubspec.yaml` 把它放在 `assets:`
而非 `fonts:` 下，屏幕上的中文走系统字体。唯一消费者是
`ScheduleExportService`，用于把中文嵌进导出的课表 PDF。

子集范围：ASCII + CJK 标点 + 全角字符 + GB2312 一级/二级汉字，共约 7,589 个
码位，覆盖课程名、教师名、教室、学期标签等课表可能出现的全部文本。

回归保护：`test/features/schedule/schedule_pdf_font_test.dart` 会
- 断言字体文件小于 4MB（防止有人换回完整字体）
- 用真实 `pdf` 包渲染一页中文，确认字形真的嵌进了 PDF 流
- 逐字检查课表样本文本的字形覆盖

如果需要扩大字符集，改 subsetting 脚本的字符集合后重新生成，不要换回完整字体。

### 2. Logo 分辨率与显示尺寸匹配

`assets/campus_app_mark.png` 是 288×288（68KB）。它只在
`login_page.dart` 里以 72×72 显示，288 = 4× 覆盖到 xxxhdpi。

原图是 2048×2048（2.25MB）——28 倍冗余，而且 Flutter 会把整张图解码进内存。
换图时保持 288×288，除非新增了大尺寸展示场景。

## 历史资源

被替换的原始资源保留在仓库根目录 `.trash/`：

- `NotoSansSC-VF.ttf`（17.8MB 完整可变字体）
- `campus_app_mark_2048_original.png`（2048×2048 原图）

需要重新生成子集或更高分辨率图标时从这里取源文件。
