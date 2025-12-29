// ignore_for_file: constant_identifier_names

import 'point_3d.dart';
import 'vector_utils.dart';

/// 동작 패턴 열거형
enum MotionPattern {
  /// 안정화 중 (초기 10프레임, 분석 점수 산출 유예)
  STABILIZING,

  /// 수직 움직임
  VERTICAL,

  /// 수평 움직임
  HORIZONTAL,

  /// 수직 밀기 동작
  VERTICAL_PUSH,

  /// 수평 밀기 동작
  HORIZONTAL_PUSH,

  /// 수직 당기기 동작
  VERTICAL_PULL,

  /// 수평 당기기 동작
  HORIZONTAL_PULL,

  /// 무릎 우세 패턴 (Knee Dominant Movement)
  KNEE_DOMINANT,

  /// 고관절 우세 패턴 (Hip Hinge Movement)
  HIP_DOMINANT,
}

/// 운동 상태 열거형
enum MovementState {
  /// 버티며 늘어남 (신장성 수축)
  ECCENTRIC,

  /// 수축함 (단축성 수축)
  CONCENTRIC,

  /// 정지 (등척성 수축)
  ISOMETRIC,
}

/// 동작 패턴 분석 결과 클래스
class MotionAnalysisResult {
  final MotionPattern pattern;
  final MovementState state;

  const MotionAnalysisResult({required this.pattern, required this.state});
}

/// 동작 패턴 분석기 클래스
///
/// Stateful 구현으로 이전 프레임의 상태를 저장하여
/// 현재 프레임과 비교하여 동작 패턴과 운동 상태를 분석합니다.
class MotionAnalyzer {
  /// 분석을 시작하기 위해 필요한 최소 프레임 수 (약 0.3초, 30fps 기준)
  static const int WARMUP_THRESHOLD = 10;

  /// 등척성(정지) 상태 판별을 위한 허용 오차
  /// 정규화된 척추 길이의 0.5% 이내 움직임은 정지 상태로 간주
  static const double ISOMETRIC_THRESHOLD = 0.005;

  /// 분석된 프레임 수 (Warm-up 체크용)
  int _frameCount = 0;

  /// 이전 프레임의 랜드마크 저장
  Map<String, Point3D>? _previousLandmarks;

  /// 수직/수평 판별
  ///
  /// 이동 벡터를 분석하여 수직 움직임인지 수평 움직임인지 판단합니다.
  MotionPattern detectPlane(Point3D start, Point3D end) {
    final delta = end.subtract(start);
    final deltaY = delta.y.abs();
    final deltaXZ = delta.x.abs() + delta.z.abs();

    // Y축 변화량이 X, Z축 변화량보다 크면 수직
    if (deltaY > deltaXZ) {
      return MotionPattern.VERTICAL;
    } else {
      return MotionPattern.HORIZONTAL;
    }
  }

  /// 밈/당김 판별
  ///
  /// 어깨와 손목 사이의 거리 변화를 분석하여 밈 동작인지 당김 동작인지 판단합니다.
  /// 방향성(수직/수평)은 detectPlane과 결합하여 VERTICAL_PUSH/HORIZONTAL_PUSH,
  /// VERTICAL_PULL/HORIZONTAL_PULL로 구분됩니다.
  MotionPattern detectPushPull(
    Point3D shoulder,
    Point3D wrist,
    Point3D prevWrist,
    MotionPattern plane,
  ) {
    final currentDist = shoulder.distanceTo(wrist);
    final prevDist = shoulder.distanceTo(prevWrist);

    final isPush = currentDist > prevDist;
    
    if (isPush) {
      return plane == MotionPattern.VERTICAL 
          ? MotionPattern.VERTICAL_PUSH 
          : MotionPattern.HORIZONTAL_PUSH;
    } else {
      return plane == MotionPattern.VERTICAL 
          ? MotionPattern.VERTICAL_PULL 
          : MotionPattern.HORIZONTAL_PULL;
    }
  }

  /// 무릎 우세/고관절 우세 판별
  ///
  /// 고관절의 수직 이동과 각도 변화량을 분석하여
  /// Knee Dominant Movement인지 Hip Dominant Movement인지 판단합니다.
  MotionPattern detectKneeDominantHipDominant({
    required double hipDeltaY,
    required double kneeAngleDelta,
    required double hipAngleDelta,
  }) {
    // 고관절의 수직 이동이 크면서 무릎의 각도 변화량이 고관절 각도 변화량보다 클 때
    if (hipDeltaY > 0.1 && kneeAngleDelta > hipAngleDelta) {
      return MotionPattern.KNEE_DOMINANT;
    } else if (hipDeltaY < 0.1 && hipAngleDelta > kneeAngleDelta) {
      // 고관절의 수직 이동이 작고 고관절 각도 변화량이 무릎 각도 변화량보다 클 때
      return MotionPattern.HIP_DOMINANT;
    }
    
    // 기본값 (판별 불가)
    return MotionPattern.VERTICAL;
  }

  /// 운동 상태 판별
  ///
  /// 질량 중심의 수직 속도를 이용하여 ECCENTRIC, CONCENTRIC, ISOMETRIC을 판별합니다.
  ///
  /// **중력(Gravity)을 이용한 수축/이완 판별:**
  /// - 질량 중심의 수직 속도(Center of Mass Vertical Velocity) 사용
  /// - spineCenter = (midShoulder + midHip) / 2
  /// - dy = spineCenter.y - prevSpineCenter.y
  ///
  /// **판별 로직 (Isometric Threshold 적용):**
  /// - if (dy.abs() < ISOMETRIC_THRESHOLD): ISOMETRIC (미세한 떨림 무시)
  /// - else if (dy < 0): CONCENTRIC (화면 위로 이동, 중력 반대 방향)
  /// - else (dy > 0): ECCENTRIC (화면 아래로 이동, 중력 방향)
  MovementState detectMovementState(
    Map<String, Point3D> current,
    Map<String, Point3D>? previous,
  ) {
    if (previous == null) {
      return MovementState.ISOMETRIC;
    }

    // 질량 중심 계산
    final leftShoulder = current['left_shoulder'];
    final rightShoulder = current['right_shoulder'];
    final leftHip = current['left_hip'];
    final rightHip = current['right_hip'];

    final prevLeftShoulder = previous['left_shoulder'];
    final prevRightShoulder = previous['right_shoulder'];
    final prevLeftHip = previous['left_hip'];
    final prevRightHip = previous['right_hip'];

    if (leftShoulder == null ||
        rightShoulder == null ||
        leftHip == null ||
        rightHip == null ||
        prevLeftShoulder == null ||
        prevRightShoulder == null ||
        prevLeftHip == null ||
        prevRightHip == null) {
      return MovementState.ISOMETRIC;
    }

    // 현재 프레임의 질량 중심
    final midShoulder = leftShoulder.midpoint(rightShoulder);
    final midHip = leftHip.midpoint(rightHip);
    final spineCenter = midShoulder.midpoint(midHip);

    // 이전 프레임의 질량 중심
    final prevMidShoulder = prevLeftShoulder.midpoint(prevRightShoulder);
    final prevMidHip = prevLeftHip.midpoint(prevRightHip);
    final prevSpineCenter = prevMidShoulder.midpoint(prevMidHip);

    // Y축 변화량 (정규화된 좌표계 기준)
    final dy = spineCenter.y - prevSpineCenter.y;

    // Isometric Threshold 적용
    if (dy.abs() < ISOMETRIC_THRESHOLD) {
      // 미세한 떨림이나 호흡으로 인한 0.005 이내의 움직임은 정지 상태로 간주
      return MovementState.ISOMETRIC;
    } else if (dy < 0) {
      // 화면 위로 이동 (중력 반대 방향) = CONCENTRIC
      return MovementState.CONCENTRIC;
    } else {
      // 화면 아래로 이동 (중력 방향) = ECCENTRIC
      return MovementState.ECCENTRIC;
    }
  }

  /// 통합 분석 메서드
  ///
  /// 현재 프레임의 랜드마크를 분석하여 동작 패턴과 운동 상태를 반환합니다.
  ///
  /// **Re-entry Protocol (재진입 초기화):**
  /// - 메서드 최상단에 가시성 체크 로직
  /// - currentLandmarks가 비어있거나 필수 관절의 visibility < 0.5이면
  ///   _frameCount = 0으로 리셋, previousLandmarks = null로 초기화
  ///
  /// **Warm-up Check (안정화 프로토콜):**
  /// - _frameCount < WARMUP_THRESHOLD일 때 STABILIZING 반환
  ///
  /// **After Warm-up:**
  /// - 정상적인 분석 로직 실행
  MotionAnalysisResult analyze(Map<String, Point3D> currentLandmarks) {
    // Re-entry Protocol (재진입 초기화) - 물리 엔진 폭발 방지
    // 사용자가 프레임에서 사라졌다가 3초 후 다시 나타날 때,
    // 3초 전 좌표와 현재 좌표 사이의 거리를 0.033초만에 이동했다고 착각하여
    // 순간 속도가 시속 1000km로 계산되어 관절 점수가 무한대(Infinity)로 치솟는 것을 방지

    // 가시성 체크
    final leftShoulder = currentLandmarks['left_shoulder'];
    final rightShoulder = currentLandmarks['right_shoulder'];
    final leftHip = currentLandmarks['left_hip'];
    final rightHip = currentLandmarks['right_hip'];

    // 필수 관절의 가시성이 0.5 미만이면 재진입으로 간주
    bool isLowVisibility =
        currentLandmarks.isEmpty ||
        leftShoulder == null ||
        rightShoulder == null ||
        leftHip == null ||
        rightHip == null ||
        (leftShoulder.visibility < 0.5 ||
            rightShoulder.visibility < 0.5 ||
            leftHip.visibility < 0.5 ||
            rightHip.visibility < 0.5);

    if (isLowVisibility) {
      // 재진입 초기화: 다시 Warm-up 모드로 진입
      _frameCount = 0;
      _previousLandmarks = null;
      return const MotionAnalysisResult(
        pattern: MotionPattern.STABILIZING,
        state: MovementState.ISOMETRIC,
      );
    }

    // Warm-up Check (안정화 프로토콜)
    _frameCount++;

    if (_frameCount < WARMUP_THRESHOLD) {
      // 현재 landmarks를 previousLandmarks에 저장만 한다 (데이터 버퍼링)
      _previousLandmarks = Map<String, Point3D>.from(currentLandmarks);

      // 복잡한 연산은 수행하지 않음
      return const MotionAnalysisResult(
        pattern: MotionPattern.STABILIZING,
        state: MovementState.ISOMETRIC,
      );
    }

    // After Warm-up: 정상 분석 진행
    if (_previousLandmarks == null) {
      // 이전 프레임 정보가 없으면 현재 프레임을 저장하고 ISOMETRIC 반환
      _previousLandmarks = Map<String, Point3D>.from(currentLandmarks);
      return const MotionAnalysisResult(
        pattern: MotionPattern.VERTICAL, // 기본값
        state: MovementState.ISOMETRIC,
      );
    }

    // 운동 상태 판별
    final movementState = detectMovementState(
      currentLandmarks,
      _previousLandmarks,
    );

    // 동작 패턴 판별
    MotionPattern pattern = _detectMotionPattern(
      currentLandmarks,
      _previousLandmarks!,
    );

    // 이전 프레임 정보를 내부적으로 저장 (다음 호출을 위해)
    _previousLandmarks = Map<String, Point3D>.from(currentLandmarks);

    return MotionAnalysisResult(pattern: pattern, state: movementState);
  }

  /// 동작 패턴 판별 (내부 헬퍼 메서드)
  /// 
  /// 상체/하체 패턴을 구분하여 적절한 MotionPattern을 반환합니다.
  MotionPattern _detectMotionPattern(
    Map<String, Point3D> current,
    Map<String, Point3D> previous,
  ) {
    // 하체 패턴 판별 (KNEE_DOMINANT / HIP_DOMINANT)
    final lowerBodyPattern = _detectLowerBodyPattern(current, previous);
    if (lowerBodyPattern != null) {
      return lowerBodyPattern;
    }

    // 상체 패턴 판별 (VERTICAL_PUSH / HORIZONTAL_PUSH / VERTICAL_PULL / HORIZONTAL_PULL)
    final upperBodyPattern = _detectUpperBodyPattern(current, previous);
    if (upperBodyPattern != null) {
      return upperBodyPattern;
    }

    // 기본값
    return MotionPattern.VERTICAL;
  }

  /// 하체 패턴 판별 (Knee Dominant / Hip Dominant)
  /// 
  /// 각도 변화량을 계산하여 무릎 우세 패턴인지 고관절 우세 패턴인지 판별합니다.
  MotionPattern? _detectLowerBodyPattern(
    Map<String, Point3D> current,
    Map<String, Point3D> previous,
  ) {
    final leftHip = current['left_hip'];
    final rightHip = current['right_hip'];
    final leftKnee = current['left_knee'];
    final rightKnee = current['right_knee'];
    final leftAnkle = current['left_ankle'];
    final rightAnkle = current['right_ankle'];
    final leftShoulder = current['left_shoulder'];
    final rightShoulder = current['right_shoulder'];

    final prevLeftHip = previous['left_hip'];
    final prevRightHip = previous['right_hip'];
    final prevLeftKnee = previous['left_knee'];
    final prevRightKnee = previous['right_knee'];
    final prevLeftAnkle = previous['left_ankle'];
    final prevRightAnkle = previous['right_ankle'];
    final prevLeftShoulder = previous['left_shoulder'];
    final prevRightShoulder = previous['right_shoulder'];

    // 필수 랜드마크 확인
    if (leftHip == null ||
        rightHip == null ||
        leftKnee == null ||
        rightKnee == null ||
        leftAnkle == null ||
        rightAnkle == null ||
        leftShoulder == null ||
        rightShoulder == null ||
        prevLeftHip == null ||
        prevRightHip == null ||
        prevLeftKnee == null ||
        prevRightKnee == null ||
        prevLeftAnkle == null ||
        prevRightAnkle == null ||
        prevLeftShoulder == null ||
        prevRightShoulder == null) {
      return null;
    }

    // 고관절의 수직 이동 계산 (왼쪽과 오른쪽 평균)
    final leftHipDeltaY = (leftHip.y - prevLeftHip.y).abs();
    final rightHipDeltaY = (rightHip.y - prevRightHip.y).abs();
    final hipDeltaY = (leftHipDeltaY + rightHipDeltaY) / 2.0;

    // 척추 중점 계산 (고관절 각도 계산용)
    final spineMid = leftShoulder.midpoint(rightShoulder);
    final prevSpineMid = prevLeftShoulder.midpoint(prevRightShoulder);

    // 왼쪽 각도 계산
    final leftKneeAngle = VectorUtils.calculateAngle(leftHip, leftKnee, leftAnkle);
    final prevLeftKneeAngle = VectorUtils.calculateAngle(prevLeftHip, prevLeftKnee, prevLeftAnkle);
    final leftKneeAngleDelta = (leftKneeAngle - prevLeftKneeAngle).abs();

    final leftHipAngle = VectorUtils.calculateAngle(spineMid, leftHip, leftKnee);
    final prevLeftHipAngle = VectorUtils.calculateAngle(prevSpineMid, prevLeftHip, prevLeftKnee);
    final leftHipAngleDelta = (leftHipAngle - prevLeftHipAngle).abs();

    // 오른쪽 각도 계산
    final rightKneeAngle = VectorUtils.calculateAngle(rightHip, rightKnee, rightAnkle);
    final prevRightKneeAngle = VectorUtils.calculateAngle(prevRightHip, prevRightKnee, prevRightAnkle);
    final rightKneeAngleDelta = (rightKneeAngle - prevRightKneeAngle).abs();

    final rightHipAngle = VectorUtils.calculateAngle(spineMid, rightHip, rightKnee);
    final prevRightHipAngle = VectorUtils.calculateAngle(prevSpineMid, prevRightHip, prevRightKnee);
    final rightHipAngleDelta = (rightHipAngle - prevRightHipAngle).abs();

    // 평균 각도 변화량
    final kneeAngleDelta = (leftKneeAngleDelta + rightKneeAngleDelta) / 2.0;
    final hipAngleDelta = (leftHipAngleDelta + rightHipAngleDelta) / 2.0;

    // KNEE_DOMINANT / HIP_DOMINANT 판별
    return detectKneeDominantHipDominant(
      hipDeltaY: hipDeltaY,
      kneeAngleDelta: kneeAngleDelta,
      hipAngleDelta: hipAngleDelta,
    );
  }

  /// 상체 패턴 판별 (Push / Pull)
  /// 
  /// 수직/수평 판별과 밀기/당기기 판별을 결합하여 반환합니다.
  MotionPattern? _detectUpperBodyPattern(
    Map<String, Point3D> current,
    Map<String, Point3D> previous,
  ) {
    final leftShoulder = current['left_shoulder'];
    final rightShoulder = current['right_shoulder'];
    final leftWrist = current['left_wrist'];
    final rightWrist = current['right_wrist'];

    final prevLeftWrist = previous['left_wrist'];
    final prevRightWrist = previous['right_wrist'];

    // 필수 랜드마크 확인
    if (leftShoulder == null ||
        rightShoulder == null ||
        leftWrist == null ||
        rightWrist == null ||
        prevLeftWrist == null ||
        prevRightWrist == null) {
      return null;
    }

    // 어깨 중점 계산
    final shoulderMid = leftShoulder.midpoint(rightShoulder);
    final wristMid = leftWrist.midpoint(rightWrist);
    final prevWristMid = prevLeftWrist.midpoint(prevRightWrist);

    // 수직/수평 판별
    final plane = detectPlane(shoulderMid, wristMid);

    // 밀기/당기기 판별
    return detectPushPull(shoulderMid, wristMid, prevWristMid, plane);
  }

  /// 프레임 카운터 리셋 (필요시 사용)
  void reset() {
    _frameCount = 0;
    _previousLandmarks = null;
  }
}
