import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../models/biomechanics_result.dart';
import '../utils/safe_calculations.dart';
import '../utils/muscle_name_mapper.dart';

/// 관절 기여도 차트 위젯
/// Contribution %를 파이 차트나 막대 그래프로 시각화
class JointContributionChart extends StatelessWidget {
  final Map<String, JointContribution> contributions;
  final bool showAsPieChart;

  const JointContributionChart({
    super.key,
    required this.contributions,
    this.showAsPieChart = false,
  });

  @override
  Widget build(BuildContext context) {
    if (contributions.isEmpty) {
      return const Center(
        child: Text('데이터 없음', style: TextStyle(color: Colors.grey)),
      );
    }

    // Contribution % 기준으로 정렬
    final sorted = contributions.values.toList()
      ..sort((a, b) => b.contributionPercent.compareTo(a.contributionPercent));

    if (showAsPieChart) {
      return _buildPieChart(sorted);
    } else {
      return _buildBarChart(sorted);
    }
  }

  /// 파이 차트 빌드
  Widget _buildPieChart(List<JointContribution> sorted) {
    return SizedBox(
      height: 200,
      child: CustomPaint(painter: PieChartPainter(sorted)),
    );
  }

  /// 막대 그래프 빌드
  Widget _buildBarChart(List<JointContribution> sorted) {
    final maxContributionRaw = sorted.isNotEmpty
        ? sorted.first.contributionPercent
        : 100.0;
    final maxContribution = SafeCalculations.safePercent(maxContributionRaw);

    // maxContribution이 0이면 모든 값을 0으로 처리
    if (maxContribution == 0.0) {
      return const Center(
        child: Text('기여도 데이터가 없습니다.', style: TextStyle(color: Colors.grey)),
      );
    }

    return Column(
      children: sorted.map((contribution) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _getJointName(contribution.jointName),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    '${SafeCalculations.safePercent(contribution.contributionPercent).toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              // Contribution % 막대
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: SafeCalculations.safeDivide(
                    SafeCalculations.safePercent(
                      contribution.contributionPercent,
                    ),
                    maxContribution,
                  ).clamp(0.0, 1.0),
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(
                    _getColorForJoint(contribution.jointName),
                  ),
                  minHeight: 8,
                ),
              ),
              const SizedBox(height: 4),
              // Torque 표시
              Text(
                '토크: ${SafeCalculations.sanitizeDouble(contribution.torqueNm).toStringAsFixed(2)} Nm',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _getJointName(String key) {
    return MuscleNameMapper.localize(key);
  }

  Color _getColorForJoint(String key) {
    const colors = {
      'hip': Colors.blue,
      'knee': Colors.green,
      'ankle': Colors.orange,
      'shoulder': Colors.purple,
      'elbow': Colors.red,
      'wrist': Colors.teal,
      'spine': Colors.brown,
      'neck': Colors.grey,
    };
    return colors[key] ?? Colors.blue;
  }
}

/// 파이 차트 페인터
class PieChartPainter extends CustomPainter {
  final List<JointContribution> contributions;
  final List<Color> colors;

  PieChartPainter(this.contributions)
    : colors = [
        Colors.blue,
        Colors.green,
        Colors.orange,
        Colors.purple,
        Colors.red,
        Colors.teal,
        Colors.brown,
        Colors.grey,
      ];

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 20;

    double startAngle = -math.pi / 2; // 12시 방향부터 시작

    for (int i = 0; i < contributions.length; i++) {
      final contribution = contributions[i];
      final percent = SafeCalculations.safePercent(
        contribution.contributionPercent,
      );
      final sweepAngle =
          SafeCalculations.safeDivide(percent, 100.0) * 2 * math.pi;

      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.fill;

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        true,
        paint,
      );

      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(PieChartPainter oldDelegate) {
    return contributions != oldDelegate.contributions;
  }
}
