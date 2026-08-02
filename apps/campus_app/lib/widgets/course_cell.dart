import 'package:flutter/material.dart';
import 'package:core/models/course.dart';
import 'package:campus_app/theme/app_theme.dart';

class CourseCell extends StatelessWidget {
  final Course course;
  final bool isActive;
  final Color? color;
  final VoidCallback? onDelete;
  final double densityScale;

  const CourseCell({
    super.key,
    required this.course,
    this.isActive = true,
    this.color,
    this.onDelete,
    this.densityScale = 1,
  });

  Color get _baseColor => color ?? const Color(0xFFF7ECF2);

  Color get _cellColor => isActive ? _baseColor : AppColors.tintSoft;
  Color get _textColor =>
      isActive ? AppColors.textPrimary : AppColors.textMuted;
  Color get _subColor =>
      isActive ? const Color(0xFF6B4556) : AppColors.textMuted.withValues(alpha: 0.6);
  Color get _borderColor => isActive
      ? HSLColor.fromColor(_baseColor)
            .withLightness(
              (HSLColor.fromColor(_baseColor).lightness - 0.10).clamp(0.0, 1.0),
            )
            .toColor()
      : AppColors.outline;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _showDetail(context),
      child: AnimatedContainer(
        duration: AppMotion.quick,
        curve: AppMotion.easeOutStrong,
        padding: EdgeInsets.symmetric(
          horizontal: 6 * densityScale,
          vertical: 5 * densityScale,
        ),
        decoration: BoxDecoration(
          color: _cellColor,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: _borderColor, width: 1),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: _baseColor.withValues(alpha: 0.3),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              course.name,
              style: TextStyle(
                fontSize: 11.5 * densityScale,
                fontWeight: FontWeight.w700,
                color: _textColor,
                height: 1.15,
              ),
              maxLines: course.slotSpan >= 2 ? 4 : 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (course.slotSpan >= 2) ...[
              const Spacer(),
              Row(
                children: [
                  Icon(
                    Icons.location_on_outlined,
                    size: 10 * densityScale,
                    color: _subColor,
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      course.placeText,
                      style: TextStyle(
                        fontSize: 9.5 * densityScale,
                        color: _subColor,
                        fontWeight: FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.outline,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    course.name,
                    style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (!isActive)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.tintSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '本周无课',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.textMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                if (course.isExam || course.isCustom) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: (course.isExam ? AppColors.primary : AppColors.secondary)
                          .withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      course.isExam ? '考试' : '自定义',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: course.isExam ? AppColors.primary : AppColors.secondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 20),
            if (!course.isExam && course.teacher.trim().isNotEmpty)
              _InfoRow(Icons.person_outline, course.teacher),
            _InfoRow(Icons.access_time_outlined, course.timeStr),
            _InfoRow(Icons.room_outlined, course.classroom),
            if (course.isExam && course.hasSeatNumber)
              _InfoRow(Icons.event_seat_outlined, '座位号：${course.seatNumber}'),
            _InfoRow(
              Icons.calendar_month_outlined,
              '共 ${course.weekList.length} 周 | 第 ${course.timeSlot}–${course.endTimeSlot} 节',
            ),
            if (onDelete != null) ...[
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('删除这门自定义课程'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.danger,
                    side: const BorderSide(color: AppColors.danger),
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    onDelete?.call();
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow(this.icon, this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.tint.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 18, color: AppColors.primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontSize: 14, color: AppColors.textBody),
          ),
        ),
      ],
    ),
  );
}
