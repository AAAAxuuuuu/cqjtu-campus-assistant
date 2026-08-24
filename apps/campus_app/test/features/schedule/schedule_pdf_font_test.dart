import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdf/pdf.dart' as pdf;
import 'package:pdf/widgets.dart' as pw;

/// The timetable PDF export is the *only* consumer of the bundled CJK font
/// (`schedule_export_service.dart` loads it through `rootBundle`). It is not a
/// UI font — `pubspec.yaml` declares it under `assets:`, not `fonts:`, so on
/// screen the app uses the system Chinese face.
///
/// The original asset was the full variable font: 17.8 MB, 31,036 glyphs, a
/// `wght` axis nobody varied — 46.8% of the arm64 APK for a feature most users
/// never open. It is now pinned to Regular and subset to GB2312, which has to
/// keep rendering real timetable text. This test embeds the shipped asset in an
/// actual PDF document to prove that.
const _fontAsset = 'assets/fonts/NotoSansSC-Subset.ttf';

/// Characters a Chongqing Jiaotong University timetable page actually emits:
/// school and course names, weekday headers, period/room labels, week ranges.
const _timetableSample =
    '重庆交通大学课程表'
    '星期一二三四五六日'
    '第周至节'
    '高等数学线性代数大学物理实验楼教室'
    '单双周体育馆图书馆'
    '教师上课地点备注'
    '0123456789:-() ';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('timetable PDF font asset', () {
    test('is small enough to ship to every user', () async {
      final file = File(_fontAsset);
      expect(
        file.existsSync(),
        isTrue,
        reason: '$_fontAsset must exist relative to the package root',
      );

      final megabytes = file.lengthSync() / (1024 * 1024);
      expect(
        megabytes,
        lessThan(4.0),
        reason:
            'the export font regressed to ${megabytes.toStringAsFixed(1)}MB; '
            're-run the GB2312 subsetting step',
      );
    });

    test('loads as a PDF TrueType face', () async {
      final data = await rootBundle.load(_fontAsset);
      final font = pw.Font.ttf(data);

      expect(font.fontName, isNotEmpty);
    });

    test('renders real timetable text into a PDF document', () async {
      final data = await rootBundle.load(_fontAsset);
      final font = pw.Font.ttf(data);

      final document = pw.Document();
      document.addPage(
        pw.Page(
          build: (_) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                _timetableSample,
                style: pw.TextStyle(font: font, fontSize: 10),
              ),
            ],
          ),
        ),
      );

      final bytes = await document.save();

      expect(String.fromCharCodes(bytes.take(8)), startsWith('%PDF-'));

      // The writer embeds only the glyphs actually drawn, so the document stays
      // small — but an empty/failed embed would collapse to roughly a blank
      // page. Several KB means the CJK outlines really made it into the stream.
      expect(
        bytes.length,
        greaterThan(8000),
        reason: 'CJK glyph outlines do not appear to be embedded',
      );
    });

    test('covers every glyph the sample needs', () async {
      final data = await rootBundle.load(_fontAsset);
      final document = pdf.PdfDocument();
      final font = pdf.PdfTtfFont(document, data);

      final missing = <String>[];
      for (final rune in _timetableSample.runes) {
        final char = String.fromCharCode(rune);
        if (char.trim().isEmpty) continue;
        if (!font.isRuneSupported(rune)) missing.add(char);
      }

      expect(
        missing,
        isEmpty,
        reason: 'subset dropped glyphs still used by the timetable: $missing',
      );
    });
  });
}
