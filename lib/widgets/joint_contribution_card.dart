import 'package:flutter/material.dart';
import '../models/biomechanics_result.dart';
import '../utils/safe_calculations.dart';
import '../utils/delta_calculator.dart';
import 'joint_contribution_chart.dart';

/// 관절 기여도 카드 위젯
/// 재사용 가능한 관절 아코디언 아이템
class JointContributionCard extends StatelessWidget {
  final JointContribution contribution;
  final bool isHighlighted;
  final bool isExpanded;
  final VoidCallback? onTap;
  final VoidCallback? onExpansionChanged;

  // 비교 모드 관련
  final bool isComparisonMode;
  final JointContribution? previousContribution;
  final Map<String, JointContribution>? allContributions; // 차트용

  const JointContributionCard({
    super.key,
    required this.contribution,
    this.isHighlighted = false,
    this.isExpanded = false,
    this.onTap,
    this.onExpansionChanged,
    this.isComparisonMode = false,
    this.previousContribution,
    this.allContributions,
  });

  String _getJointDisplayName(String jointKey) {
    const mapping = {
      'neck': '목',
      'spine': '척추',
      'shoulder': '어깨',
      'elbow': '팔꿈치',
      'wrist': '손목',
      'hip': '고관절',
      'knee': '무릎',
      'ankle': '발목',
    };
    return mapping[jointKey] ?? jointKey;
  }

  @override
  Widget build(BuildContext context) {
    // Delta 계산 (비교 모드일 때)
    double? contributionDelta;
    double? torqueDelta;
    double? romDelta;

    if (isComparisonMode && previousContribution != null) {
      contributionDelta = DeltaCalculator.calculateJointDelta(
        previousContribution,
        contribution,
      );
      torqueDelta = DeltaCalculator.calculateTorqueDelta(
        previousContribution,
        contribution,
      );
      romDelta = DeltaCalculator.calculateRomDelta(
        previousContribution,
        contribution,
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      elevation: isHighlighted ? 4 : 0,
      // 🔧 배경색 명시적으로 흰색 설정 (회색 배경 방지)
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isHighlighted ? Colors.blue : Colors.grey.shade200,
          width: isHighlighted ? 2 : 1,
        ),
      ),
      child: ExpansionTile(
        initiallyExpanded: isExpanded,
        leading: const Icon(Icons.accessibility_new, size: 20),
        title: Text(
          _getJointDisplayName(contribution.jointName),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: isHighlighted ? Colors.blue : Colors.black87,
          ),
        ),
        trailing: _buildTrailing(contributionDelta),
        onExpansionChanged: (expanded) {
          if (expanded && onExpansionChanged != null) {
            onExpansionChanged!();
          }
        },
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Contribution % 막대
                _buildContributionSection(contributionDelta),
                const SizedBox(height: 16),
                // Torque 정보
                _buildTorqueSection(torqueDelta),
                const SizedBox(height: 8),
                // ROM 점수
                _buildRomSection(romDelta),
                if (allContributions != null) ...[
                  const SizedBox(height: 16),
                  // Contribution 차트 (막대 그래프)
                  const Text(
                    '전체 관절 기여도',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  JointContributionChart(
                    contributions: allContributions!,
                    showAsPieChart: false,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrailing(double? delta) {
    final contributionPercent = SafeCalculations.safePercent(
      contribution.contributionPercent,
    );
    final torqueNm = SafeCalculations.sanitizeDouble(contribution.torqueNm);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${contributionPercent.toStringAsFixed(1)}%',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: isHighlighted ? Colors.blue : Colors.black87,
              ),
            ),
            if (delta != null && delta != 0) ...[
              const SizedBox(width: 8),
              _buildDeltaChip(delta, '%'),
            ],
          ],
        ),
        Text(
          '${torqueNm.toStringAsFixed(2)} Nm',
          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
        ),
      ],
    );
  }

  Widget _buildDeltaChip(double delta, String unit) {
    final deltaColor = DeltaCalculator.getDeltaColor(delta);
    final color = deltaColor == DeltaColor.positive ? Colors.blue : Colors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        DeltaCalculator.formatDelta(delta, unit: unit),
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _buildContributionSection(double? delta) {
    final contributionPercent = SafeCalculations.safePercent(
      contribution.contributionPercent,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '부하 기여도',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${contributionPercent.toStringAsFixed(1)}%',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
                if (delta != null && delta != 0) ...[
                  const SizedBox(width: 8),
                  _buildDeltaChip(delta, '%'),
                ],
              ],
            ),
          ],
        ),
        if (isComparisonMode && previousContribution != null) ...[
          const SizedBox(height: 4),
          Text(
            '(이전: ${SafeCalculations.safePercent(previousContribution!.contributionPercent).toStringAsFixed(1)}%)',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ],
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: SafeCalculations.percentToProgress(contributionPercent),
            backgroundColor: Colors.grey[200],
            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade400),
            minHeight: 8,
          ),
        ),
      ],
    );
  }

  Widget _buildTorqueSection(double? delta) {
    final torqueNm = SafeCalculations.sanitizeDouble(contribution.torqueNm);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              '관절 토크',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${torqueNm.toStringAsFixed(2)} Nm',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange,
                  ),
                ),
                if (delta != null && delta != 0) ...[
                  const SizedBox(width: 8),
                  _buildDeltaChip(delta, ' Nm'),
                ],
              ],
            ),
          ],
        ),
        if (isComparisonMode && previousContribution != null) ...[
          const SizedBox(height: 4),
          Text(
            '(이전: ${SafeCalculations.sanitizeDouble(previousContribution!.torqueNm).toStringAsFixed(2)} Nm)',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ],
      ],
    );
  }

  Widget _buildRomSection(double? delta) {
    final romScore = SafeCalculations.sanitizeDouble(contribution.romScore);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'ROM 점수',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  romScore.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (delta != null && delta != 0) ...[
                  const SizedBox(width: 8),
                  _buildDeltaChip(delta, ''),
                ],
              ],
            ),
          ],
        ),
        if (isComparisonMode && previousContribution != null) ...[
          const SizedBox(height: 4),
          Text(
            '(이전: ${SafeCalculations.sanitizeDouble(previousContribution!.romScore).toStringAsFixed(1)})',
            style: TextStyle(fontSize: 11, color: Colors.grey[600]),
          ),
        ],
      ],
    );
  }
}
