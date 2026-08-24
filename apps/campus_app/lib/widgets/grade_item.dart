import 'package:flutter/material.dart';
import 'package:core/models/grade.dart';
import 'package:campus_app/theme/app_theme.dart';
import 'package:campus_app/widgets/app_card.dart';

class GradeItem extends StatelessWidget {
  final Grade grade;
  final VoidCallback? onTap;

  const GradeItem({super.key, required this.grade, this.onTap});

  Color get _scoreColor {
    final n = double.tryParse(grade.score);
    if (n == null) return AppColors.info;
    if (n >= 90) return AppColors.success;
    if (n >= 75) return AppColors.info;
    if (n >= 60) return AppColors.warning;
    return AppColors.danger;
  }

  @override
  Widget build(BuildContext context) {
    // onTap 交给 AppCard，这样成绩行也有统一的按压缩放反馈
    // （裸 Card + ListTile 只有涟漪，没有卡片整体的按压感）。
    return AppCard(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(grade.courseName, style: AppType.rowTitle),
                const SizedBox(height: 4),
                Text(
                  '${grade.semester}  ${grade.credits} 学分  '
                  '绩点 ${grade.gradePoint}',
                  style: AppType.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            grade.score,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: _scoreColor,
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: 4),
            Icon(Icons.chevron_right, color: _scoreColor, size: 20),
          ],
        ],
      ),
    );
  }
}
