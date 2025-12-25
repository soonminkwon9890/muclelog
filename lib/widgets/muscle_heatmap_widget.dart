import 'package:flutter/material.dart';

/// 실사 해부도 기반 동적 히트맵 위젯
/// ShaderMask를 활용하여 근육별 활성도를 시각화합니다.
class MuscleHeatmapWidget extends StatefulWidget {
  final bool isFront;
  final Map<String, double> muscleData;
  final String mode; // 'MUSCLE' | 'JOINT'
  final String? biomechPattern;
  final String? highlightedMuscle; // 깜빡임 효과를 위한 하이라이트 근육

  const MuscleHeatmapWidget({
    super.key,
    required this.isFront,
    required this.muscleData,
    required this.mode,
    this.biomechPattern,
    this.highlightedMuscle,
  });

  @override
  State<MuscleHeatmapWidget> createState() => _MuscleHeatmapWidgetState();
}

/// 실루엣 드로잉을 위한 CustomPainter
class _SilhouettePainter extends CustomPainter {
  final bool isFront;

  _SilhouettePainter(this.isFront);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade300
      ..style = PaintingStyle.fill;

    final centerX = size.width / 2;
    final headRadius = size.width * 0.08;
    final bodyWidth = size.width * 0.25;
    final bodyHeight = size.height * 0.4;
    final legWidth = size.width * 0.1;
    final legHeight = size.height * 0.3;

    // 머리
    canvas.drawCircle(Offset(centerX, headRadius + 10), headRadius, paint);

    // 몸통
    final bodyTop = headRadius * 2 + 20;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(centerX, bodyTop + bodyHeight / 2),
          width: bodyWidth,
          height: bodyHeight,
        ),
        const Radius.circular(8),
      ),
      paint,
    );

    if (isFront) {
      // 전면: 팔 (양쪽)
      final armY = bodyTop + bodyHeight * 0.3;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(centerX - bodyWidth / 2 - size.width * 0.08, armY),
            width: size.width * 0.06,
            height: bodyHeight * 0.5,
          ),
          const Radius.circular(4),
        ),
        paint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(centerX + bodyWidth / 2 + size.width * 0.08, armY),
            width: size.width * 0.06,
            height: bodyHeight * 0.5,
          ),
          const Radius.circular(4),
        ),
        paint,
      );
    } else {
      // 후면: 등 (어깨 라인)
      final shoulderY = bodyTop + bodyHeight * 0.2;
      canvas.drawLine(
        Offset(centerX - bodyWidth / 2, shoulderY),
        Offset(centerX + bodyWidth / 2, shoulderY),
        paint..strokeWidth = 4,
      );
    }

    // 다리 (양쪽)
    final legTop = bodyTop + bodyHeight;
    final leftLegX = centerX - bodyWidth / 3;
    final rightLegX = centerX + bodyWidth / 3;

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(leftLegX - legWidth / 2, legTop, legWidth, legHeight),
        const Radius.circular(4),
      ),
      paint,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(rightLegX - legWidth / 2, legTop, legWidth, legHeight),
        const Radius.circular(4),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _MuscleHeatmapWidgetState extends State<MuscleHeatmapWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  // 마스크 이미지 제거로 인해 애니메이션 필드 제거
  // late Animation<double> _pulseAnimation;
  // late Animation<double> _flashAnimation;

  @override
  void initState() {
    super.initState();

    // Pulsing 애니메이션 (STATE_PULL, STATE_PUSH용)
    // 마스크 이미지 제거로 인해 애니메이션 로직 단순화
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    // 애니메이션 시작 조건 확인 (필요시 사용)
    // 마스크 이미지 제거로 인해 애니메이션 효과는 비활성화
    // if (widget.biomechPattern == 'STATE_PULL' ||
    //     widget.biomechPattern == 'STATE_PUSH') {
    //   _pulseController.repeat(reverse: true);
    // }

    // 하이라이트가 있으면 한 번 깜빡임
    // 마스크 이미지 제거로 인해 애니메이션 효과는 비활성화
    // if (widget.highlightedMuscle != null) {
    //   _pulseController.forward().then((_) {
    //     _pulseController.reverse();
    //   });
    // }
  }

  @override
  void didUpdateWidget(MuscleHeatmapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);

    // 하이라이트 변경 시 깜빡임
    if (widget.highlightedMuscle != null &&
        widget.highlightedMuscle != oldWidget.highlightedMuscle) {
      _pulseController.reset();
      _pulseController.forward().then((_) {
        _pulseController.reverse();
      });
    }

    // 패턴 변경 시 애니메이션 재시작
    if (widget.biomechPattern != oldWidget.biomechPattern) {
      _pulseController.stop();
      if (widget.biomechPattern == 'STATE_PULL' ||
          widget.biomechPattern == 'STATE_PUSH') {
        _pulseController.repeat(reverse: true);
      }
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  /// Rank 계산 (점수 내림차순 정렬 후 Rank 1, 2 할당)
  Map<String, int> _calculateRanks() {
    final ranks = <String, int>{};
    final sortedEntries = widget.muscleData.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    for (int i = 0; i < sortedEntries.length; i++) {
      final entry = sortedEntries[i];
      if (entry.value > 0) {
        if (i == 0) {
          ranks[entry.key] = 1; // Rank 1
        } else if (i == 1) {
          ranks[entry.key] = 2; // Rank 2
        } else {
          ranks[entry.key] = 3; // 나머지
        }
      }
    }

    return ranks;
  }

  /// 근육/관절 위치 좌표 계산 (실루엣 기준)
  Offset _getMusclePosition(String muscleKey, Size size) {
    final centerX = size.width / 2;
    final bodyTop = size.width * 0.16 + 20;
    final bodyHeight = size.height * 0.4;
    final bodyWidth = size.width * 0.25;

    final lowerKey = muscleKey.toLowerCase();

    // 전면 근육 위치
    if (widget.isFront) {
      if (lowerKey.contains('pectoralis') || lowerKey.contains('chest')) {
        return Offset(centerX, bodyTop + bodyHeight * 0.3);
      }
      if (lowerKey.contains('abs') || lowerKey.contains('abdominal')) {
        return Offset(centerX, bodyTop + bodyHeight * 0.7);
      }
      if (lowerKey.contains('quads') || lowerKey.contains('quad')) {
        return Offset(centerX, bodyTop + bodyHeight + size.height * 0.15);
      }
      if (lowerKey.contains('deltoid') || lowerKey.contains('shoulder')) {
        return Offset(centerX, bodyTop + bodyHeight * 0.2);
      }
      if (lowerKey.contains('biceps')) {
        return Offset(centerX - bodyWidth / 2, bodyTop + bodyHeight * 0.4);
      }
      if (lowerKey.contains('triceps')) {
        return Offset(centerX + bodyWidth / 2, bodyTop + bodyHeight * 0.4);
      }
    } else {
      // 후면 근육 위치
      if (lowerKey.contains('lats') || lowerKey.contains('lat')) {
        return Offset(centerX, bodyTop + bodyHeight * 0.4);
      }
      if (lowerKey.contains('trapezius') || lowerKey.contains('traps')) {
        return Offset(centerX, bodyTop + bodyHeight * 0.15);
      }
      if (lowerKey.contains('erector') || lowerKey.contains('spine')) {
        return Offset(centerX, bodyTop + bodyHeight * 0.5);
      }
      if (lowerKey.contains('glutes') || lowerKey.contains('glute')) {
        return Offset(centerX, bodyTop + bodyHeight * 0.85);
      }
      if (lowerKey.contains('hamstrings') || lowerKey.contains('hamstring')) {
        return Offset(centerX, bodyTop + bodyHeight + size.height * 0.15);
      }
    }

    // 기본 위치 (몸통 중앙)
    return Offset(centerX, bodyTop + bodyHeight / 2);
  }

  /// Rank에 따른 색상 결정
  Color _getColorForRank(int rank, bool isHighlighted) {
    if (isHighlighted) {
      // 깜빡임 효과를 위한 밝은 색상
      return Colors.white;
    }

    switch (rank) {
      case 1:
        return Colors.redAccent;
      case 2:
        return Colors.amber;
      default:
        return Colors.grey.withValues(alpha: 0.5);
    }
  }

  /// 폴백 히트맵 빌드 (이미지 없을 때)
  Widget _buildFallbackHeatmap(Map<String, int> ranks) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return Stack(
          children: [
            // 실루엣 배경
            CustomPaint(
              painter: _SilhouettePainter(widget.isFront),
              size: size,
            ),
            // 히트맵 점 표시
            ...widget.muscleData.entries.map((entry) {
              final muscleKey = entry.key;
              final score = entry.value;
              final rank = ranks[muscleKey] ?? 3;

              if (score <= 0) return const SizedBox.shrink();

              // 전면/후면 구분 확인 (키워드 기반으로 간단히 판단)
              final lowerKey = muscleKey.toLowerCase();
              final shouldShow = widget.isFront
                  ? (lowerKey.contains('pectoralis') ||
                        lowerKey.contains('pec') ||
                        lowerKey.contains('abs') ||
                        lowerKey.contains('quads') ||
                        lowerKey.contains('quad') ||
                        lowerKey.contains('deltoid') ||
                        lowerKey.contains('biceps') ||
                        lowerKey.contains('triceps'))
                  : (lowerKey.contains('lats') ||
                        lowerKey.contains('lat') ||
                        lowerKey.contains('trapezius') ||
                        lowerKey.contains('traps') ||
                        lowerKey.contains('erector') ||
                        lowerKey.contains('spine') ||
                        lowerKey.contains('glutes') ||
                        lowerKey.contains('glute') ||
                        lowerKey.contains('hamstrings') ||
                        lowerKey.contains('hamstring'));

              if (!shouldShow) return const SizedBox.shrink();

              final position = _getMusclePosition(muscleKey, size);
              final color = _getColorForRank(rank, false);
              final isHighlighted = widget.highlightedMuscle == muscleKey;

              return Positioned(
                left: position.dx - 12,
                top: position.dy - 12,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isHighlighted ? Colors.white : color,
                    border: Border.all(
                      color: isHighlighted ? color : Colors.transparent,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 8,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == 'JOINT') {
      // 관절 모드는 아직 구현하지 않음 (추후 확장)
      return const Center(child: Text('관절 모드는 준비 중입니다.'));
    }

    final ranks = _calculateRanks();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Stack(
              children: [
                // Base Layer: 해부도 원본 (회색조 처리) 또는 폴백
                Positioned.fill(
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.mode(
                      Colors.grey,
                      BlendMode.saturation,
                    ),
                    child: Image.asset(
                      'assets/images/anatomy_${widget.isFront ? 'front' : 'back'}.png',
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        // 이미지 로딩 실패 시 폴백 히트맵 표시
                        return _buildFallbackHeatmap(ranks);
                      },
                    ),
                  ),
                ),
                // 히트맵 점 표시 (마스크 이미지 대신 사용)
                ...widget.muscleData.entries.map((entry) {
                  final muscleKey = entry.key;
                  final score = entry.value;
                  final rank = ranks[muscleKey] ?? 3;

                  if (score <= 0) return const SizedBox.shrink();

                  // 전면/후면 구분 확인 (키워드 기반으로 간단히 판단)
                  final lowerKey = muscleKey.toLowerCase();
                  final shouldShow = widget.isFront
                      ? (lowerKey.contains('pectoralis') ||
                            lowerKey.contains('pec') ||
                            lowerKey.contains('abs') ||
                            lowerKey.contains('quads') ||
                            lowerKey.contains('quad') ||
                            lowerKey.contains('deltoid') ||
                            lowerKey.contains('biceps') ||
                            lowerKey.contains('triceps'))
                      : (lowerKey.contains('lats') ||
                            lowerKey.contains('lat') ||
                            lowerKey.contains('trapezius') ||
                            lowerKey.contains('traps') ||
                            lowerKey.contains('erector') ||
                            lowerKey.contains('spine') ||
                            lowerKey.contains('glutes') ||
                            lowerKey.contains('glute') ||
                            lowerKey.contains('hamstrings') ||
                            lowerKey.contains('hamstring'));

                  if (!shouldShow) return const SizedBox.shrink();

                  // 폴백 히트맵 점 표시
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final size = constraints.biggest;
                      final position = _getMusclePosition(muscleKey, size);
                      final color = _getColorForRank(rank, false);
                      final isHighlighted =
                          widget.highlightedMuscle == muscleKey;

                      return Positioned(
                        left: position.dx - 12,
                        top: position.dy - 12,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isHighlighted ? Colors.white : color,
                            border: Border.all(
                              color: isHighlighted ? color : Colors.transparent,
                              width: 3,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(alpha: 0.5),
                                blurRadius: 8,
                                spreadRadius: 2,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                }),
              ],
            ),
          ),
          // 라벨
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Text(
              widget.isFront ? '전면 (Front)' : '후면 (Back)',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
        ],
      ),
    );
  }
}
