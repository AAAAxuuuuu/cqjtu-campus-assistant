import 'package:flutter/material.dart';
import 'package:core/models/grade.dart';
import 'package:campus_app/theme/app_theme.dart';

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
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: onTap,
        title: Text(
          grade.courseName,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          '${grade.semester}  ${grade.credits} 学分  绩点 ${grade.gradePoint}',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
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
      ),
    );
  }
}
