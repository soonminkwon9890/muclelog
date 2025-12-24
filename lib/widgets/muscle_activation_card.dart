import 'package:flutter/material.dart';
import '../models/biomechanics_result.dart';
import '../utils/muscle_name_mapper.dart';
import '../utils/delta_calculator.dart';
import '../utils/safe_calculations.dart';

/// 근육 활성도 카드 위젯
/// 활성도 수치와 원인 태그를 표시
class MuscleActivationCard extends StatelessWidget {
  final MuscleActivation activation;
  final VoidCallback? onTap;
  final bool isHighlighted;

  // 비교 모드 관련
  final bool isComparisonMode;
  final MuscleActivation? previousActivation;

  const MuscleActivationCard({
    super.key,
    required this.activation,
    this.onTap,
    this.isHighlighted = false,
    this.isComparisonMode = false,
    this.previousActivation,
  });

  @override
  Widget build(BuildContext context) {
    // Delta 계산 (비교 모드일 때)
    double? delta;
    if (isComparisonMode && previousActivation != null) {
      delta = DeltaCalculator.calculateMuscleDelta(
        previousActivation,
        activation,
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8.0),
      elevation: isHighlighted ? 4 : 0,
      // 🔧 배경색 명시적으로 설정 (투명하지 않음)
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isHighlighted ? Colors.blue : Colors.grey.shade200,
          width: isHighlighted ? 2 : 1,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 근육명과 활성도
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    MuscleNameMapper.localize(activation.muscleName),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: isHighlighted ? Colors.blue : Colors.black87,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        SafeCalculations.formatPercentOrNA(
                          SafeCalculations.safePercent(
                            activation.activationPercent,
                          ),
                        ),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: activation.activationPercent > 0
                              ? _getColorForActivation(
                                  activation.activationPercent,
                                )
                              : Colors.grey,
                        ),
                      ),
                      if (delta != null && delta != 0) ...[
                        const SizedBox(width: 8),
                        _buildDeltaChip(delta),
                      ],
                    ],
                  ),
                ],
              ),
              // 이전 값 표시 (비교 모드일 때)
              if (isComparisonMode && previousActivation != null) ...[
                const SizedBox(height: 4),
                Text(
                  '(이전: ${SafeCalculations.safePercent(previousActivation!.activationPercent).toStringAsFixed(1)}%)',
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
              ],
              const SizedBox(height: 12),
              // 원인 태그들
              if (activation.reasons.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: activation.reasons.map((reason) {
                    return Chip(
                      label: Text(reason, style: const TextStyle(fontSize: 11)),
                      backgroundColor: _getColorForReason(reason),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    );
                  }).toList(),
                ),
              const SizedBox(height: 8),
              // 상세 정보
              Row(
                children: [
                  if (activation.isEccentric)
                    _buildInfoChip('신장성', Colors.orange)
                  else
                    _buildInfoChip('단축성', Colors.green),
                  const SizedBox(width: 8),
                  _buildInfoChip(
                    '모멘트암: ${activation.momentArmLength}',
                    Colors.blue,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Color _getColorForActivation(double percent) {
    if (percent >= 70) return Colors.red;
    if (percent >= 40) return Colors.orange;
    if (percent > 0) return Colors.blue;
    return Colors.grey;
  }

  Color _getColorForReason(String reason) {
    if (reason.contains('신장성')) return Colors.orange.withValues(alpha: 0.2);
    if (reason.contains('단축성')) return Colors.green.withValues(alpha: 0.2);
    if (reason.contains('모멘트암')) return Colors.blue.withValues(alpha: 0.2);
    if (reason.contains('보상')) return Colors.red.withValues(alpha: 0.2);
    if (reason.contains('견갑')) return Colors.purple.withValues(alpha: 0.2);
    return Colors.grey.withValues(alpha: 0.2);
  }

  Widget _buildDeltaChip(double delta) {
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
        DeltaCalculator.formatDelta(delta, unit: '%'),
        style: TextStyle(
          fontSize: 10,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}
