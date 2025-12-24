import '../models/biomechanics_result.dart';

/// Delta 계산 유틸리티
/// 과거와 현재 데이터의 변화량을 계산하고 포맷팅합니다.
class DeltaCalculator {
  /// 근육 활성도 변화량 계산
  static double calculateMuscleDelta(
    MuscleActivation? previous,
    MuscleActivation? current,
  ) {
    if (previous == null || current == null) {
      return 0.0;
    }
    return current.activationPercent - previous.activationPercent;
  }

  /// 관절 기여도 변화량 계산
  static double calculateJointDelta(
    JointContribution? previous,
    JointContribution? current,
  ) {
    if (previous == null || current == null) {
      return 0.0;
    }
    return current.contributionPercent - previous.contributionPercent;
  }

  /// 관절 토크 변화량 계산
  static double calculateTorqueDelta(
    JointContribution? previous,
    JointContribution? current,
  ) {
    if (previous == null || current == null) {
      return 0.0;
    }
    return current.torqueNm - previous.torqueNm;
  }

  /// ROM 점수 변화량 계산
  static double calculateRomDelta(
    JointContribution? previous,
    JointContribution? current,
  ) {
    if (previous == null || current == null) {
      return 0.0;
    }
    return current.romScore - previous.romScore;
  }

  /// Delta 값을 포맷팅된 문자열로 변환
  /// "▲ +5.2% 증가" 또는 "▼ -3.1% 감소" 형식
  static String formatDelta(double delta, {String unit = '%'}) {
    final absDelta = delta.abs();
    final formatted = absDelta.toStringAsFixed(1);

    if (delta > 0) {
      return '▲ +$formatted$unit 증가';
    } else if (delta < 0) {
      return '▼ -$formatted$unit 감소';
    } else {
      return '변화 없음';
    }
  }

  /// Delta 값에 따른 색상 반환
  /// 양수=파랑, 음수=회색 (중립적)
  static DeltaColor getDeltaColor(double delta) {
    if (delta > 0) {
      return DeltaColor.positive; // 파랑
    } else if (delta < 0) {
      return DeltaColor.negative; // 회색
    } else {
      return DeltaColor.neutral; // 회색
    }
  }
}

/// Delta 색상 타입
enum DeltaColor {
  positive, // 양수 (파랑)
  negative, // 음수 (회색)
  neutral, // 변화 없음 (회색)
}
