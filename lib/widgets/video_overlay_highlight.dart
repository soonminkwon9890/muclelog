import 'package:flutter/material.dart';
import 'dart:ui' as ui;

/// 비디오 오버레이 하이라이트 위젯
/// 클릭된 근육/관절에 대한 벡터와 모멘트암을 표시
class VideoOverlayHighlight extends StatelessWidget {
  final String? highlightedMuscle;
  final String? highlightedJoint;
  final Map<String, dynamic>? metadata;

  const VideoOverlayHighlight({
    super.key,
    this.highlightedMuscle,
    this.highlightedJoint,
    this.metadata,
  });

  @override
  Widget build(BuildContext context) {
    if (highlightedMuscle == null && highlightedJoint == null) {
      return const SizedBox.shrink();
    }

    return CustomPaint(
      painter: HighlightPainter(
        highlightedMuscle: highlightedMuscle,
        highlightedJoint: highlightedJoint,
        metadata: metadata,
      ),
      child: Container(),
    );
  }
}

/// 하이라이트 페인터
class HighlightPainter extends CustomPainter {
  final String? highlightedMuscle;
  final String? highlightedJoint;
  final Map<String, dynamic>? metadata;

  HighlightPainter({
    this.highlightedMuscle,
    this.highlightedJoint,
    this.metadata,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // 근육 하이라이트: 벡터 그리기
    if (highlightedMuscle != null) {
      final paint = Paint()
        ..color = Colors.red.withValues(alpha: 0.6)
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke;

      // 예시: 어깨 -> 팔꿈치 벡터 (실제 포즈 데이터가 있으면 계산)
      final centerX = size.width / 2;
      final centerY = size.height / 2;

      // 벡터 화살표 그리기 (예시)
      final path = ui.Path();
      path.moveTo(centerX - 50, centerY);
      path.lineTo(centerX + 50, centerY);

      // 화살표 머리
      path.moveTo(centerX + 50, centerY);
      path.lineTo(centerX + 40, centerY - 10);
      path.moveTo(centerX + 50, centerY);
      path.lineTo(centerX + 40, centerY + 10);

      canvas.drawPath(path, paint);
    }

    // 관절 하이라이트: 모멘트암 선 그리기
    if (highlightedJoint != null) {
      final paint = Paint()
        ..color = Colors.blue.withValues(alpha: 0.6)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      // 예시: 관절 중심에서 모멘트암 표시 (실제 포즈 데이터가 있으면 계산)
      final centerX = size.width / 2;
      final centerY = size.height / 2;

      // 모멘트암 선 (예시)
      canvas.drawLine(
        Offset(centerX, centerY - 30),
        Offset(centerX, centerY + 30),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(HighlightPainter oldDelegate) {
    return highlightedMuscle != oldDelegate.highlightedMuscle ||
        highlightedJoint != oldDelegate.highlightedJoint;
  }
}
