import 'dart:math' as math;
import 'point_3d.dart';

/// 안정성 지표 결과 클래스
/// 
/// StabilityCalculator.calculateStability()의 반환값으로 사용됩니다.
class StabilityMetrics {
  /// 목 길이 비율 (Elevation Factor)
  /// 0.0 ~ 1.0 (1.0 = 완전 으쓱, 목이 짧아짐)
  final double elevationFactor;

  /// 어깨 후인 정도 (Scapula Retraction Factor)
  /// 양수 = 후인 (어깨가 척추보다 뒤에 있음)
  /// 음수 = 라운드 숄더 (어깨가 척추보다 앞에 있음)
  final double retractionFactor;

  /// 무릎 안쪽 쏠림 (Knee Valgus Factor)
  /// 0.0 ~ 1.0 (0 = 정상, 1 = 심한 Valgus)
  final double valgusFactor;

  /// 골반 경사 정도 (Pelvic Tilt Factor)
  /// 0 = 정상 (측면 뷰일 경우 계산하지 않음)
  final double pelvicTiltFactor;

  const StabilityMetrics({
    required this.elevationFactor,
    required this.retractionFactor,
    required this.valgusFactor,
    required this.pelvicTiltFactor,
  });
}

/// 안정성 계산기 클래스
/// 
/// 3D 랜드마크 좌표를 기반으로 신체의 안정성 지표를 계산합니다.
/// 
/// **계산 항목:**
/// - 상체 안정성: 목 길이 비율 (Elevation), 어깨 후인 정도 (Scapula Retraction)
/// - 하체 안정성: 무릎 안쪽 쏠림 (Knee Valgus), 골반 경사 (Pelvic Tilt)
class StabilityCalculator {
  /// 안정성 지표 계산
  /// 
  /// **입력:**
  /// - `landmarks`: 주요 관절의 3D 좌표 맵
  ///   - 어깨: 'left_shoulder', 'right_shoulder'
  ///   - 엉덩이: 'left_hip', 'right_hip'
  ///   - 귀: 'left_ear', 'right_ear' (Elevation 계산용)
  ///   - 무릎: 'left_knee', 'right_knee' (Valgus 계산용)
  ///   - 발목: 'left_ankle', 'right_ankle' (Valgus 계산용)
  /// 
  /// **반환:**
  /// - `StabilityMetrics`: 계산된 안정성 지표
  static StabilityMetrics calculateStability(
    Map<String, Point3D> landmarks,
  ) {
    // 가상 척추 정의
    final leftShoulder = landmarks['left_shoulder'];
    final rightShoulder = landmarks['right_shoulder'];
    final leftHip = landmarks['left_hip'];
    final rightHip = landmarks['right_hip'];

    if (leftShoulder == null ||
        rightShoulder == null ||
        leftHip == null ||
        rightHip == null) {
      // 필수 랜드마크가 없으면 기본값 반환
      return const StabilityMetrics(
        elevationFactor: 0.0,
        retractionFactor: 0.0,
        valgusFactor: 0.0,
        pelvicTiltFactor: 0.0,
      );
    }

    final spineTop = leftShoulder.midpoint(rightShoulder);
    final spineBottom = leftHip.midpoint(rightHip);

    // 상체 안정성 계산
    final elevationFactor = _calculateElevation(landmarks);
    final retractionFactor = _calculateRetraction(spineTop, spineBottom,
        leftShoulder, rightShoulder);

    // 하체 안정성 계산
    final valgusFactor = _calculateValgus(landmarks);
    final pelvicTiltFactor = _calculatePelvicTilt(landmarks, spineTop,
        spineBottom);

    return StabilityMetrics(
      elevationFactor: elevationFactor,
      retractionFactor: retractionFactor,
      valgusFactor: valgusFactor,
      pelvicTiltFactor: pelvicTiltFactor,
    );
  }

  /// 목 길이 비율 (Elevation) 계산
  /// 
  /// 쇄골 길이 대비 목 길이가 짧아지면 으쓱 (Elevation)
  /// 범위: 0.0 ~ 1.0 (1.0은 완전 으쓱)
  static double _calculateElevation(Map<String, Point3D> landmarks) {
    final leftShoulder = landmarks['left_shoulder'];
    final rightShoulder = landmarks['right_shoulder'];
    final leftEar = landmarks['left_ear'];
    final rightEar = landmarks['right_ear'];

    if (leftShoulder == null ||
        rightShoulder == null ||
        leftEar == null ||
        rightEar == null) {
      return 0.0;
    }

    // 쇄골 길이
    final clavicleLength = leftShoulder.distanceTo(rightShoulder);

    // 목 길이 (왼쪽 + 오른쪽 평균)
    final leftNeckLength = leftEar.distanceTo(leftShoulder);
    final rightNeckLength = rightEar.distanceTo(rightShoulder);
    final neckLength = (leftNeckLength + rightNeckLength) / 2.0;

    // 목 길이 비율 계산
    // 목 길이가 짧아지면 elevationFactor 증가
    if (clavicleLength <= 0.0) {
      return 0.0;
    }

    final elevationFactor = 1.0 - (neckLength / (clavicleLength * 0.5));
    return elevationFactor.clamp(0.0, 1.0);
  }

  /// 어깨 후인 정도 (Scapula Retraction) 계산
  /// 
  /// Z축 깊이를 이용하여 어깨가 척추보다 뒤에 있는지 앞에 있는지 판단
  /// 양수 = 후인 (어깨가 척추보다 뒤에 있음)
  /// 음수 = 라운드 숄더 (어깨가 척추보다 앞에 있음)
  /// 
  /// **주의:** Point3D의 z값(깊이) 신뢰도가 낮으므로 주의 필요
  static double _calculateRetraction(
    Point3D spineTop,
    Point3D spineBottom,
    Point3D leftShoulder,
    Point3D rightShoulder,
  ) {
    // 어깨 깊이 (Z축 평균)
    final shoulderDepth = (leftShoulder.z + rightShoulder.z) / 2.0;

    // 척추 깊이 (Z축 평균)
    final spineDepth = (spineTop.z + spineBottom.z) / 2.0;

    // 어깨가 척추보다 뒤에 있으면 양수, 앞에 있으면 음수
    return shoulderDepth - spineDepth;
  }

  /// 무릎 안쪽 쏠림 (Knee Valgus) 계산
  /// 
  /// (Hip-Ankle 직선) 대비 (Knee의 수평 거리)를 측정
  /// valgusFactor = (ankleWidth - kneeWidth) / ankleWidth
  /// 양수면 Valgus 심함, 0이면 정상
  static double _calculateValgus(Map<String, Point3D> landmarks) {
    final leftHip = landmarks['left_hip'];
    final rightHip = landmarks['right_hip'];
    final leftKnee = landmarks['left_knee'];
    final rightKnee = landmarks['right_knee'];
    final leftAnkle = landmarks['left_ankle'];
    final rightAnkle = landmarks['right_ankle'];

    if (leftHip == null ||
        rightHip == null ||
        leftKnee == null ||
        rightKnee == null ||
        leftAnkle == null ||
        rightAnkle == null) {
      return 0.0;
    }

    // 고관절 너비
    final hipWidth = leftHip.distanceTo(rightHip);

    // 무릎 너비 (수평 거리만 고려: X, Y 좌표만 사용)
    final kneeDx = rightKnee.x - leftKnee.x;
    final kneeDy = rightKnee.y - leftKnee.y;
    final kneeWidth = math.sqrt(kneeDx * kneeDx + kneeDy * kneeDy);

    // 발목 너비 (수평 거리만 고려)
    final ankleDx = rightAnkle.x - leftAnkle.x;
    final ankleDy = rightAnkle.y - leftAnkle.y;
    final ankleWidth = math.sqrt(ankleDx * ankleDx + ankleDy * ankleDy);

    if (ankleWidth <= 0.0) {
      return 0.0;
    }

    // Valgus 계산
    // 무릎 너비가 발목 너비보다 현저히 좁을 경우
    final valgusFactor = (ankleWidth - kneeWidth) / ankleWidth;

    // 무릎 너비가 발목 너비의 0.8배보다 작거나, 고관절 너비보다 현저히 좁을 때만 Valgus로 판단
    if (kneeWidth < ankleWidth * 0.8 || kneeWidth < hipWidth * 0.7) {
      return valgusFactor.clamp(0.0, 1.0);
    }

    return 0.0;
  }

  /// 골반 경사 (Pelvic Tilt) 계산
  /// 
  /// 정면 뷰일 때만 계산하고, 측면일 땐 0.0 처리 (오탐 방지)
  /// 정면 뷰 판별: 어깨 너비가 척추 길이의 0.3배 이상일 때 정면으로 간주
  /// pelvicDy = (LeftHip.y - RightHip.y).abs()
  /// 골반의 높낮이 차이가 클수록 불안정
  static double _calculatePelvicTilt(
    Map<String, Point3D> landmarks,
    Point3D spineTop,
    Point3D spineBottom,
  ) {
    final leftHip = landmarks['left_hip'];
    final rightHip = landmarks['right_hip'];
    final leftShoulder = landmarks['left_shoulder'];
    final rightShoulder = landmarks['right_shoulder'];

    if (leftHip == null ||
        rightHip == null ||
        leftShoulder == null ||
        rightShoulder == null) {
      return 0.0;
    }

    // 척추 길이
    final spineLength = spineTop.distanceTo(spineBottom);

    // 어깨 너비
    final shoulderWidth = leftShoulder.distanceTo(rightShoulder);

    // 정면 뷰 판별: 어깨 너비가 척추 길이의 0.3배 이상일 때 정면으로 간주
    if (spineLength <= 0.0 || shoulderWidth < spineLength * 0.3) {
      // 측면 뷰일 경우 계산하지 않음
      return 0.0;
    }

    // 골반 높낮이 차이 (Y축)
    final pelvicDy = (leftHip.y - rightHip.y).abs();

    return pelvicDy;
  }
}

