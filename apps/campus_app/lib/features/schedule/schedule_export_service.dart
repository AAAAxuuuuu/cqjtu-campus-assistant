import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:core/models/course.dart';
import 'package:core/models/schedule_calendar_rules.dart';
import 'package:core/utils/schedule_time_utils.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

/// Builds shareable schedule files from the locally loaded course data.
class ScheduleExportService {
  /// GB2312 subset of Noto Sans SC, pinned to Regular.
  ///
  /// This font exists only to embed Chinese glyphs in exported PDFs; the app UI
  /// uses the system face. Shipping the full 17.8 MB variable font (31k glyphs,
  /// an unused `wght` axis) made it 46.8% of the arm64 APK, so it is subset to
  /// the ~7.6k characters a timetable can contain. See
  /// test/features/schedule/schedule_pdf_font_test.dart for the coverage guard.
  static const _fontAsset = 'assets/fonts/NotoSansSC-Subset.ttf';

  static Future<void> shareWeekPdf({
    required List<Course> courses,
    required DateTime semesterStart,
    required int selectedWeek,
    required bool sundayFirst,
    required String semesterLabel,
    int totalWeeks = 20,
    ScheduleCalendarRules calendarRules = ScheduleCalendarRules.empty,
  }) async {
    final document = pw.Document();
    final font = await _loadChineseFont();
    final weekStart = _weekStartOf(
      semesterStart,
      selectedWeek,
      sundayFirst: sundayFirst,
    );
    final orderedWeekdays = _orderedWeekdays(sundayFirst: sundayFirst);
    final activeCourses = _coursesForWeek(
      occurrences: _resolveOccurrences(
        courses: courses,
        semesterStart: semesterStart,
        totalWeeks: totalWeeks,
        calendarRules: calendarRules,
      ),
      semesterStart: semesterStart,
      week: selectedWeek,
      calendarRules: calendarRules,
    );
    final colorMap = _buildPdfColorMap(courses);

    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4.landscape,
        margin: const pw.EdgeInsets.all(20),
        theme: pw.ThemeData.withFont(base: font, bold: font),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              '$semesterLabel 第$selectedWeek周课程表',
              style: pw.TextStyle(
                font: font,
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              '${_dateLabel(weekStart)} - ${_dateLabel(weekStart.add(const Duration(days: 6)))}',
              style: pw.TextStyle(
                font: font,
                fontSize: 9,
                color: PdfColors.grey700,
              ),
            ),
            pw.SizedBox(height: 14),
            _weekGrid(
              font: font,
              courses: activeCourses,
              orderedWeekdays: orderedWeekdays,
              weekStart: weekStart,
              colorMap: colorMap,
            ),
            pw.Spacer(),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Text(
                '由重庆交通大学校园助手生成',
                style: pw.TextStyle(
                  font: font,
                  fontSize: 8,
                  color: PdfColors.grey600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    await _shareBytes(
      bytes: await document.save(),
      fileName: '课程表_${_fileDate(weekStart)}_第$selectedWeek周.pdf',
      subject: '第$selectedWeek周课程表',
    );
  }

  static Future<void> shareAllWeeksPdf({
    required List<Course> courses,
    required DateTime semesterStart,
    required int totalWeeks,
    required bool sundayFirst,
    required String semesterLabel,
    ScheduleCalendarRules calendarRules = ScheduleCalendarRules.empty,
  }) async {
    final document = pw.Document();
    final font = await _loadChineseFont();
    final orderedWeekdays = _orderedWeekdays(sundayFirst: sundayFirst);
    final colorMap = _buildPdfColorMap(courses);
    final weekCount = totalWeeks < 1 ? 1 : totalWeeks;
    final occurrences = _resolveOccurrences(
      courses: courses,
      semesterStart: semesterStart,
      totalWeeks: totalWeeks,
      calendarRules: calendarRules,
    );

    for (var week = 1; week <= weekCount; week++) {
      final weekStart = _weekStartOf(
        semesterStart,
        week,
        sundayFirst: sundayFirst,
      );
      final activeCourses = _coursesForWeek(
        occurrences: occurrences,
        semesterStart: semesterStart,
        week: week,
        calendarRules: calendarRules,
      );

      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4.landscape,
          margin: const pw.EdgeInsets.all(20),
          theme: pw.ThemeData.withFont(base: font, bold: font),
          build: (context) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '$semesterLabel 第 $week 周课程表',
                style: pw.TextStyle(
                  font: font,
                  fontSize: 18,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                '${_dateLabel(weekStart)} - ${_dateLabel(weekStart.add(const Duration(days: 6)))}',
                style: pw.TextStyle(
                  font: font,
                  fontSize: 9,
                  color: PdfColors.grey700,
                ),
              ),
              pw.SizedBox(height: 14),
              _weekGrid(
                font: font,
                courses: activeCourses,
                orderedWeekdays: orderedWeekdays,
                weekStart: weekStart,
                colorMap: colorMap,
              ),
              pw.Spacer(),
              pw.Align(
                alignment: pw.Alignment.centerRight,
                child: pw.Text(
                  '第 $week / $weekCount 周 · 由重庆交通大学校园助手生成',
                  style: pw.TextStyle(
                    font: font,
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    await _shareBytes(
      bytes: await document.save(),
      fileName: '课程表_${_safeFilePart(semesterLabel)}_全学期周课表.pdf',
      subject: '$semesterLabel 全学期周课表',
    );
  }

  static Future<void> shareCourseListPdf({
    required List<Course> courses,
    required DateTime semesterStart,
    required int totalWeeks,
    required String semesterLabel,
    ScheduleCalendarRules calendarRules = ScheduleCalendarRules.empty,
  }) async {
    final document = pw.Document();
    final font = await _loadChineseFont();
    final sorted =
        _resolveOccurrences(
          courses: courses,
          semesterStart: semesterStart,
          totalWeeks: totalWeeks,
          calendarRules: calendarRules,
        )..sort((a, b) {
          final date = a.scheduledDate.compareTo(b.scheduledDate);
          return date != 0
              ? date
              : a.course.timeSlot.compareTo(b.course.timeSlot);
        });
    final rows = sorted.map((occurrence) {
      final course = occurrence.course;
      final week = calendarRules.weekOf(
        occurrence.scheduledDate,
        semesterStart,
      );
      return [
        '${_dateLabel(occurrence.scheduledDate)} ${_weekdayLabel(occurrence.scheduledDate.weekday)}',
        '第$week周',
        '第${course.timeSlot}-${course.endTimeSlot}节\n${_courseTimeLabel(course)}',
        course.name,
        course.teacher.trim().isEmpty ? '-' : course.teacher,
        course.placeText.trim().isEmpty ? '-' : course.placeText,
      ];
    }).toList();

    document.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        theme: pw.ThemeData.withFont(base: font, bold: font),
        header: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              '$semesterLabel 课程清单',
              style: pw.TextStyle(
                font: font,
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 10),
          ],
        ),
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '${context.pageNumber} / ${context.pagesCount}',
            style: pw.TextStyle(
              font: font,
              fontSize: 8,
              color: PdfColors.grey600,
            ),
          ),
        ),
        build: (context) => [
          if (rows.isEmpty)
            pw.Padding(
              padding: const pw.EdgeInsets.only(top: 40),
              child: pw.Text('当前学期没有可导出的课程。', style: pw.TextStyle(font: font)),
            )
          else
            pw.TableHelper.fromTextArray(
              headers: const ['日期', '周次', '时间', '课程', '教师', '地点'],
              data: rows,
              headerStyle: pw.TextStyle(
                font: font,
                fontWeight: pw.FontWeight.bold,
                fontSize: 9,
              ),
              cellStyle: pw.TextStyle(
                font: font,
                fontSize: 8.2,
                lineSpacing: 2,
              ),
              headerDecoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFEAF0F6),
              ),
              cellAlignment: pw.Alignment.centerLeft,
              cellPadding: const pw.EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 5,
              ),
              columnWidths: const {
                0: pw.FixedColumnWidth(36),
                1: pw.FixedColumnWidth(38),
                2: pw.FixedColumnWidth(70),
                3: pw.FlexColumnWidth(1.4),
                4: pw.FlexColumnWidth(0.9),
                5: pw.FlexColumnWidth(1.15),
              },
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.45),
            ),
          pw.SizedBox(height: 12),
          pw.Text(
            '共 ${sorted.length} 门课程',
            style: pw.TextStyle(
              font: font,
              fontSize: 9,
              color: PdfColors.grey700,
            ),
          ),
        ],
      ),
    );
    await _shareBytes(
      bytes: await document.save(),
      fileName: '课程清单_${_safeFilePart(semesterLabel)}.pdf',
      subject: '$semesterLabel 课程清单',
    );
  }

  static Future<void> shareIcs({
    required List<Course> courses,
    required DateTime semesterStart,
    required int totalWeeks,
    required bool sundayFirst,
    required String semesterLabel,
    ScheduleCalendarRules calendarRules = ScheduleCalendarRules.empty,
  }) async {
    final stamp = _icsUtc(DateTime.now().toUtc());
    final lines = <String>[
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//CQJTU Campus App//Schedule//CN',
      'CALSCALE:GREGORIAN',
      'METHOD:PUBLISH',
      'X-WR-CALNAME:${_icsEscape('$semesterLabel 课程表')}',
    ];

    for (final occurrence in _resolveOccurrences(
      courses: courses,
      semesterStart: semesterStart,
      totalWeeks: totalWeeks,
      calendarRules: calendarRules,
    )) {
      final course = occurrence.course;
      final date = occurrence.scheduledDate;
      final week = calendarRules.weekOf(date, semesterStart);
      final range = _courseTimeRange(course);
      final start = DateTime(
        date.year,
        date.month,
        date.day,
      ).add(Duration(minutes: range.start));
      final end = DateTime(
        date.year,
        date.month,
        date.day,
      ).add(Duration(minutes: range.end));
      final identity =
          '${course.name}|${course.dayOfWeek}|$week|${range.start}|${range.end}|${course.classroom}';
      lines.addAll([
        'BEGIN:VEVENT',
        'UID:${_stableHash(identity)}-${_fileDate(date)}@cqjtu-campus-app',
        'DTSTAMP:$stamp',
        'DTSTART:${_icsUtc(start.toUtc())}',
        'DTEND:${_icsUtc(end.toUtc())}',
        'SUMMARY:${_icsEscape(course.name)}',
        if (course.placeText.trim().isNotEmpty)
          'LOCATION:${_icsEscape(course.placeText)}',
        'DESCRIPTION:${_icsEscape(_courseDescription(course, week))}',
        'END:VEVENT',
      ]);
    }
    lines.add('END:VCALENDAR');
    await _shareBytes(
      bytes: _encodeIcs(lines),
      fileName: '课程表_${_safeFilePart(semesterLabel)}.ics',
      subject: '$semesterLabel 课程表日历',
    );
  }

  static Future<pw.Font> _loadChineseFont() async {
    final data = await rootBundle.load(_fontAsset);
    return pw.Font.ttf(data);
  }

  static List<ScheduleCourseOccurrence> _resolveOccurrences({
    required List<Course> courses,
    required DateTime semesterStart,
    required int totalWeeks,
    required ScheduleCalendarRules calendarRules,
  }) => calendarRules.resolveOccurrences(
    courses: courses,
    semesterStart: semesterStart,
    totalWeeks: totalWeeks,
  );

  static List<Course> _coursesForWeek({
    required List<ScheduleCourseOccurrence> occurrences,
    required DateTime semesterStart,
    required int week,
    required ScheduleCalendarRules calendarRules,
  }) => occurrences
      .where(
        (occurrence) =>
            calendarRules.weekOf(occurrence.scheduledDate, semesterStart) ==
            week,
      )
      .map((occurrence) => occurrence.asCourseForWeek(week))
      .toList();

  static pw.Widget _weekGrid({
    required pw.Font font,
    required List<Course> courses,
    required List<int> orderedWeekdays,
    required DateTime weekStart,
    required Map<String, PdfColor> colorMap,
  }) {
    const timeWidth = 54.0;
    const dayWidth = 103.0;
    const slotHeight = 27.5;
    final height = slotHeight * 13;
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: 0.7),
      ),
      child: pw.Column(
        children: [
          pw.Row(
            children: [
              pw.SizedBox(width: timeWidth, height: 32),
              for (var i = 0; i < 7; i++)
                pw.Container(
                  width: dayWidth,
                  height: 32,
                  alignment: pw.Alignment.center,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      left: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
                    ),
                    color: PdfColor.fromInt(0xFFF5F7FA),
                  ),
                  child: pw.Column(
                    mainAxisAlignment: pw.MainAxisAlignment.center,
                    children: [
                      pw.Text(
                        '周${_weekdayLabel(orderedWeekdays[i]).replaceFirst('周', '')}',
                        style: pw.TextStyle(
                          font: font,
                          fontSize: 9,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.Text(
                        _dateLabel(weekStart.add(Duration(days: i))),
                        style: pw.TextStyle(
                          font: font,
                          fontSize: 7.2,
                          color: PdfColors.grey700,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: timeWidth,
                height: height,
                child: pw.Stack(
                  children: [
                    for (var slot = 1; slot <= 13; slot++)
                      pw.Positioned(
                        top: (slot - 1) * slotHeight,
                        left: 0,
                        right: 0,
                        child: pw.SizedBox(
                          height: slotHeight,
                          child: pw.Container(
                            alignment: pw.Alignment.center,
                            decoration: const pw.BoxDecoration(
                              border: pw.Border(
                                top: pw.BorderSide(
                                  color: PdfColors.grey300,
                                  width: 0.4,
                                ),
                              ),
                            ),
                            child: pw.Text(
                              '$slot\n${_slotLabel(slot)}',
                              textAlign: pw.TextAlign.center,
                              style: pw.TextStyle(
                                font: font,
                                fontSize: 6.5,
                                lineSpacing: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              for (final weekday in orderedWeekdays)
                _pdfDayColumn(
                  font: font,
                  courses: courses
                      .where((course) => course.dayOfWeek == weekday)
                      .toList(),
                  colorMap: colorMap,
                  dayWidth: dayWidth,
                  slotHeight: slotHeight,
                  height: height,
                ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _pdfDayColumn({
    required pw.Font font,
    required List<Course> courses,
    required Map<String, PdfColor> colorMap,
    required double dayWidth,
    required double slotHeight,
    required double height,
  }) => pw.Container(
    width: dayWidth,
    height: height,
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        left: pw.BorderSide(color: PdfColors.grey400, width: 0.5),
      ),
    ),
    child: pw.Stack(
      children: [
        for (var slot = 1; slot <= 13; slot++)
          pw.Positioned(
            top: (slot - 1) * slotHeight,
            left: 0,
            right: 0,
            child: pw.Container(height: 0.4, color: PdfColors.grey300),
          ),
        for (final course in courses)
          pw.Positioned(
            top: (course.timeSlot.clamp(1, 13) - 1) * slotHeight + 1,
            left: 2,
            right: 2,
            child: pw.SizedBox(
              height:
                  ((course.endTimeSlot.clamp(course.timeSlot, 13) -
                                  course.timeSlot +
                                  1) *
                              slotHeight -
                          2)
                      .clamp(18, double.infinity),
              child: pw.Container(
                padding: const pw.EdgeInsets.all(3),
                decoration: pw.BoxDecoration(
                  color: colorMap[_courseColorKey(course)] ?? PdfColors.grey200,
                  border: pw.Border.all(color: PdfColors.grey500, width: 0.45),
                  borderRadius: pw.BorderRadius.circular(2),
                ),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      course.name,
                      maxLines: course.slotSpan >= 2 ? 3 : 1,
                      overflow: pw.TextOverflow.clip,
                      style: pw.TextStyle(
                        font: font,
                        fontSize: 7.2,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    if (course.slotSpan >= 2 &&
                        course.placeText.trim().isNotEmpty)
                      pw.Spacer(),
                    if (course.slotSpan >= 2 &&
                        course.placeText.trim().isNotEmpty)
                      pw.Text(
                        course.placeText,
                        maxLines: 1,
                        overflow: pw.TextOverflow.clip,
                        style: pw.TextStyle(font: font, fontSize: 6.2),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );

  static Future<void> _shareBytes({
    required Uint8List bytes,
    required String fileName,
    required String subject,
  }) async {
    final directory = await getTemporaryDirectory();
    final file = File('${directory.path}${Platform.pathSeparator}$fileName');
    await file.writeAsBytes(bytes, flush: true);
    await Share.shareXFiles([XFile(file.path)], subject: subject);
  }

  static List<int> _orderedWeekdays({required bool sundayFirst}) => sundayFirst
      ? const [DateTime.sunday, 1, 2, 3, 4, 5, 6]
      : const [1, 2, 3, 4, 5, 6, DateTime.sunday];

  static DateTime _weekStartOf(
    DateTime semesterStart,
    int week, {
    required bool sundayFirst,
  }) {
    final day = DateTime(
      semesterStart.year,
      semesterStart.month,
      semesterStart.day,
    );
    final offset = sundayFirst ? day.weekday % 7 : day.weekday - 1;
    return day
        .subtract(Duration(days: offset))
        .add(Duration(days: (week - 1) * 7));
  }

  static ({int start, int end}) _courseTimeRange(Course course) {
    if (course.exactStartMinutes != null &&
        course.exactEndMinutes != null &&
        course.exactEndMinutes! > course.exactStartMinutes!) {
      return (start: course.exactStartMinutes!, end: course.exactEndMinutes!);
    }
    return (
      start: slotMinuteRanges[course.timeSlot]!.start,
      end: slotMinuteRanges[course.endTimeSlot]!.end,
    );
  }

  static String _courseTimeLabel(Course course) {
    final range = _courseTimeRange(course);
    return '${_clock(range.start)}-${_clock(range.end)}';
  }

  static String _courseDescription(Course course, int week) {
    final fields = <String>[
      '第$week周',
      '第${course.timeSlot}-${course.endTimeSlot}节',
    ];
    if (course.teacher.trim().isNotEmpty) {
      fields.add('教师：${course.teacher.trim()}');
    }
    if (course.isExam && course.hasSeatNumber) {
      fields.add('座位号：${course.seatNumber.trim()}');
    }
    return fields.join('\\n');
  }

  static String _slotLabel(int slot) =>
      '${_clock(slotMinuteRanges[slot]!.start)}-${_clock(slotMinuteRanges[slot]!.end)}';
  static String _clock(int minutes) =>
      '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';
  static String _dateLabel(DateTime value) => '${value.month}/${value.day}';
  static String _fileDate(DateTime value) =>
      '${value.year}${value.month.toString().padLeft(2, '0')}${value.day.toString().padLeft(2, '0')}';
  static String _safeFilePart(String value) =>
      value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  static String _weekdayLabel(int weekday) =>
      const {
        1: '周一',
        2: '周二',
        3: '周三',
        4: '周四',
        5: '周五',
        6: '周六',
        7: '周日',
      }[weekday] ??
      '周?';
  static String _courseColorKey(Course course) =>
      course.name.trim().replaceAll(RegExp(r'\\s+'), ' ');
  static int _stableHash(String value) {
    var hash = 0x811C9DC5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash;
  }

  static Map<String, PdfColor> _buildPdfColorMap(List<Course> courses) {
    final colors = [
      const PdfColor.fromInt(0xFFE5F1FF),
      const PdfColor.fromInt(0xFFE4F5E9),
      const PdfColor.fromInt(0xFFFFF0D8),
      const PdfColor.fromInt(0xFFFDE5E7),
      const PdfColor.fromInt(0xFFE8EEF9),
      const PdfColor.fromInt(0xFFE8F4F3),
    ];
    final names =
        courses
            .map(_courseColorKey)
            .where((name) => name.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    return {
      for (final name in names) name: colors[_stableHash(name) % colors.length],
    };
  }

  static String _icsLocal(DateTime value) =>
      '${_fileDate(value)}T${value.hour.toString().padLeft(2, '0')}${value.minute.toString().padLeft(2, '0')}00';
  static String _icsUtc(DateTime value) => '${_icsLocal(value)}Z';
  static String _icsEscape(String value) => value
      .replaceAll('\\', r'\\')
      .replaceAll(';', r'\;')
      .replaceAll(',', r'\,')
      .replaceAll('\n', r'\n');
  static Uint8List _encodeIcs(List<String> lines) {
    final bytes = BytesBuilder(copy: false);
    for (final line in lines) {
      bytes.add(_foldIcsLineBytes(line));
      bytes.add(const [13, 10]);
    }
    return bytes.takeBytes();
  }

  /// RFC 5545 limits physical content lines to 75 octets, not characters.
  static Uint8List _foldIcsLineBytes(String line) {
    const maxLineBytes = 75;
    final bytes = BytesBuilder(copy: false);
    var currentLineBytes = 0;

    for (final rune in line.runes) {
      final characterBytes = utf8.encode(String.fromCharCode(rune));
      if (currentLineBytes > 0 &&
          currentLineBytes + characterBytes.length > maxLineBytes) {
        bytes.add(const [13, 10, 32]);
        currentLineBytes = 1;
      }
      bytes.add(characterBytes);
      currentLineBytes += characterBytes.length;
    }
    return bytes.takeBytes();
  }
}
