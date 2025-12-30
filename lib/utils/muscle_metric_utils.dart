import 'dart:math' as math;
import 'biomechanics/point_3d.dart';
import 'biomechanics/vector_utils.dart';
import 'biomechanics/stability_calculator.dart';
import 'biomechanics/motion_analyzer.dart';
import 'biomechanics/energy_leak_engine.dart';
import 'biomechanics/joint_controller.dart';

/// 생체역학 분석 유틸리티 클래스 (Facade Pattern)
///
/// 새로운 순수 역학 기반 엔진 컴포넌트들을 조율하고,
/// 결과를 기존 UI가 기대하는 형식으로 변환하는 역할을 수행합니다.
class MuscleMetricUtils {
  // =======================================================
  // [Static Members] 정적 멤버
  // =======================================================

  /// 측면 뷰 감지 임계값 (정규화된 좌표 기준)
  /// 어깨 또는 고관절의 X 좌표 차이가 이 값 미만이면 측면 뷰로 간주
  static const double sideViewThreshold = 0.15;

  /// MotionAnalyzer 정적 인스턴스 (상태 유지)
  /// Stateful 클래스이므로 정적 인스턴스를 사용하여 프레임 간 상태가 유지됩니다.
  static final MotionAnalyzer _motionAnalyzer = MotionAnalyzer();

  /// 관절별 JointController 맵 (미리 정의)
  static final Map<String, JointController> _jointControllers = {
    // ✅ 어깨 관절 컨트롤러 추가 (orderedJoints 순서에 맞게 먼저 정의)
    'left_shoulder': JointController.fromDegrees(
      angleMinDegrees: 0,
      angleMaxDegrees: 180, // 어깨 가동 범위 (0~180도)
      stiffness: 20.0,
      dampingCoefficient: 1.0,
      staticFriction: 0.1,
      kineticFriction: 0.05,
    ),
    'right_shoulder': JointController.fromDegrees(
      angleMinDegrees: 0,
      angleMaxDegrees: 180,
      stiffness: 20.0,
      dampingCoefficient: 1.0,
      staticFriction: 0.1,
      kineticFriction: 0.05,
    ),

    // 기존 컨트롤러들...
    'left_knee': JointController.fromDegrees(
      angleMinDegrees: 0,
      angleMaxDegrees: 135,
      stiffness: 20.0, // 50.0 → 20.0 (인대 유연성 현실화)
      dampingCoefficient: 1.0, // 5.0 → 1.0 (과도한 저항 제거)
      staticFriction: 0.1,
      kineticFriction: 0.05,
    ),
    'right_knee': JointController.fromDegrees(
      angleMinDegrees: 0,
      angleMaxDegrees: 135,
      stiffness: 20.0, // 50.0 → 20.0 (인대 유연성 현실화)
      dampingCoefficient: 1.0, // 5.0 → 1.0 (과도한 저항 제거)
      staticFriction: 0.1,
      kineticFriction: 0.05,
    ),
    'left_elbow': JointController.fromDegrees(
      angleMinDegrees: 0,
      angleMaxDegrees: 150,
      stiffness: 15.0, // 부드러운 반응을 위한 낮은 Stiffness
      dampingCoefficient: 1.0, // 5.0 → 1.0 (과도한 저항 제거)
      staticFriction: 0.1,
      kineticFriction: 0.05,
    ),
    'right_elbow': JointController.fromDegrees(
      angleMinDegrees: 0,
      angleMaxDegrees: 150,
      stiffness: 15.0, // 부드러운 반응을 위한 낮은 Stiffness
      dampingCoefficient: 1.0, // 5.0 → 1.0 (과도한 저항 제거)
      staticFriction: 0.1,
      kineticFriction: 0.05,
    ),
    'left_hip': JointController.fromDegrees(
      angleMinDegrees: 0,
      angleMaxDegrees: 120,
      stiffness: 20.0, // 50.0 → 20.0 (인대 유연성 현실화)
      dampingCoefficient: 1.0, // 5.0 → 1.0 (과도한 저항 제거)
      staticFriction: 0.1,
      kineticFriction: 0.05,
    ),
    'right_hip': JointController.fromDegrees(
      angleMinDegrees: 0,
      angleMaxDegrees: 120,
      stiffness: 20.0, // 50.0 → 20.0 (인대 유연성 현실화)
      dampingCoefficient: 1.0, // 5.0 → 1.0 (과도한 저항 제거)
      staticFriction: 0.1,
      kineticFriction: 0.05,
    ),
    'left_ankle': JointController.fromDegrees(
      angleMinDegrees: -45, // 족배굴곡
      angleMaxDegrees: 45, // 족저굴곡
      stiffness: 20.0,
      dampingCoefficient: 1.0,
      staticFriction: 0.1,
      kineticFriction: 0.05,
    ),
    'right_ankle': JointController.fromDegrees(
      angleMinDegrees: -45, // 족배굴곡
      angleMaxDegrees: 45, // 족저굴곡
      stiffness: 20.0,
      dampingCoefficient: 1.0,
      staticFriction: 0.1,
      kineticFriction: 0.05,
    ),
  };

  /// 이전 각도 저장용 Map (JointController의 calculateJointStress 호출 시 사용)
  static final Map<String, double> _previousAngles = {};

  /// 이전 프레임 랜드마크 저장용 Map (동적 의도 감지에 사용)
  static final Map<String, Point3D> _previousLandmarks = {};

  // =======================================================
  // [Helper] 데이터 정제 및 포맷팅
  // =======================================================
  static double sanitizeOutput(double? value) {
    if (value == null || value.isNaN || value.isInfinite) return 0.0;
    return double.parse(value.toStringAsFixed(1));
  }

  static Map<String, double> sanitizeOutputMap(Map<String, double>? data) {
    if (data == null) return {};
    final sanitized = <String, double>{};
    for (final entry in data.entries) {
      sanitized[entry.key] = sanitizeOutput(entry.value);
    }
    return sanitized;
  }

  // =======================================================
  // [Helper] Stability Warning 변환
  // =======================================================

  /// StabilityMetrics 객체를 UI용 String 메시지로 변환
  static String _convertStabilityMetricsToWarning(StabilityMetrics metrics) {
    final warnings = <String>[];

    if (metrics.elevationFactor > 0.5) {
      warnings.add("어깨가 으쓱했습니다");
    }
    if (metrics.valgusFactor > 0.3) {
      warnings.add("무릎이 안쪽으로 쏠렸습니다");
    }
    if (metrics.retractionFactor < -0.05) {
      warnings.add("라운드 숄더가 감지되었습니다");
    }
    if (metrics.pelvicTiltFactor > 0.2) {
      warnings.add("골반 경사가 감지되었습니다");
    }

    return warnings.isEmpty ? "" : warnings.join(". ");
  }

  // =======================================================
  // [Helper] 빈 결과 반환
  // =======================================================

  static Map<String, dynamic> _emptyResult() {
    return {
      'detailed_muscle_usage': <String, double>{},
      'rom_data': <String, double>{},
      'biomech_pattern': 'UNKNOWN',
      'stability_warning': '',
    };
  }

  // =======================================================
  // [Helper] 관절 각도 계산 (3점 각도)
  // =======================================================

  /// 세 점(a, b, c)으로 구성된 각도 계산 (라디안)
  /// b가 꼭짓점, a와 c가 양쪽 끝점
  static double _calculateAngle(Point3D a, Point3D b, Point3D c) {
    final v1 = a.subtract(b);
    final v2 = c.subtract(b);

    final dot = v1.dot(v2);
    final len1 = math.sqrt(v1.x * v1.x + v1.y * v1.y + v1.z * v1.z);
    final len2 = math.sqrt(v2.x * v2.x + v2.y * v2.y + v2.z * v2.z);

    if (len1 == 0.0 || len2 == 0.0) return 0.0;

    final cosAngle = dot / (len1 * len2);
    final clampedCos = cosAngle.clamp(-1.0, 1.0);
    return math.acos(clampedCos);
  }

  /// 무릎 각도 계산 (깊이 보정 포함)
  ///
  /// 전/후면 뷰에서 단축 현상(Foreshortening)을 역이용하여 각도를 추정합니다.
  /// 투영 기하학(Projective Geometry) 원리를 사용하여 2D 카메라의 한계를 보완합니다.
  static double _calculateKneeAngleWithDepthCorrection(
    Map<String, Point3D> landmarks,
    String side, {
    bool isSideView = false, // [NEW] 측면 뷰 플래그
  }) {
    final hipKey = '${side}_hip';
    final kneeKey = '${side}_knee';
    final ankleKey = '${side}_ankle';

    final hip = landmarks[hipKey];
    final knee = landmarks[kneeKey];
    final ankle = landmarks[ankleKey];

    // null 체크
    if (hip == null || knee == null || ankle == null) {
      return 0.0;
    }

    // [NEW] 측면 뷰일 때는 복잡한 투영 보정을 끄고 단순 2D 각도 사용
    // 측면에서는 2D 각도가 곧 실제 각도임
    if (isSideView) {
      return _calculateAngle(hip, knee, ankle);
    }

    // 기존 로직: 뷰 판별 및 깊이 복원 (측면 뷰가 아닐 때만 실행)
    // 뷰 판별: leftHip.x와 rightHip.x의 차이로 측면/전면 구분
    final leftHip = landmarks['left_hip'];
    final rightHip = landmarks['right_hip'];

    bool isSideViewLocal = false;
    if (leftHip != null && rightHip != null) {
      final hipXDiff = (leftHip.x - rightHip.x).abs();
      isSideViewLocal = hipXDiff < 0.1; // 0.1 미만이면 측면 뷰
    }

    // 측면 뷰: 기존 3점 각도 계산 사용
    if (isSideViewLocal) {
      return _calculateAngle(hip, knee, ankle);
    }

    // 비측면 뷰 (Front/Back View): 깊이 복원 로직 적용
    // 단축 현상(Foreshortening)을 역이용하여 각도 추정
    final thighLen = hip.distanceTo(knee); // Hip과 Knee 사이의 2D 거리
    final shinLen = knee.distanceTo(ankle); // Knee와 Ankle 사이의 2D 거리

    // 0으로 나누기 방지
    if (shinLen == 0.0) {
      return 0.0;
    }

    // depthRatio: 앉을수록 허벅지 투영 길이가 짧아짐
    final depthRatio = thighLen / shinLen;

    // depthScore: 0.0 (서 있을 때) ~ 1.0 (깊게 앉을 때)
    final depthScore = ((1.0 - depthRatio) / 0.6).clamp(0.0, 1.0);

    // 각도 변환: depthScore를 라디안 각도로 변환 (0 ~ π 범위)
    final angle = (1.0 - (depthScore * 0.5)) * math.pi;

    return angle;
  }

  /// 동적 움직임 의도 계산
  ///
  /// 거리 변화(Reach Delta)와 Z축 속도(Depth Velocity)를 기반으로
  /// -1.0 (완벽한 당기기) ~ +1.0 (완벽한 밀기) 범위의 값을 반환합니다.
  static double _calculateDynamicMovementIntent(
    Map<String, Point3D> currentLandmarks,
    Map<String, Point3D> previousLandmarks,
  ) {
    // 필요한 랜드마크 확인
    final leftShoulder = currentLandmarks['left_shoulder'];
    final rightShoulder = currentLandmarks['right_shoulder'];
    final leftElbow = currentLandmarks['left_elbow'];
    final rightElbow = currentLandmarks['right_elbow'];
    final leftWrist = currentLandmarks['left_wrist'];
    final rightWrist = currentLandmarks['right_wrist'];

    final prevLeftShoulder = previousLandmarks['left_shoulder'];
    final prevRightShoulder = previousLandmarks['right_shoulder'];
    final prevLeftElbow = previousLandmarks['left_elbow'];
    final prevRightElbow = previousLandmarks['right_elbow'];
    final prevLeftWrist = previousLandmarks['left_wrist'];
    final prevRightWrist = previousLandmarks['right_wrist'];

    // null 체크
    if (leftShoulder == null ||
        rightShoulder == null ||
        leftElbow == null ||
        rightElbow == null ||
        leftWrist == null ||
        rightWrist == null ||
        prevLeftShoulder == null ||
        prevRightShoulder == null ||
        prevLeftElbow == null ||
        prevRightElbow == null ||
        prevLeftWrist == null ||
        prevRightWrist == null) {
      return 0.0;
    }

    // 1. 양쪽 어깨-손목 거리 변화량 계산 (Reach Delta)
    final currLeftDist = leftShoulder.distanceTo(leftWrist);
    final prevLeftDist = prevLeftShoulder.distanceTo(prevLeftWrist);
    final currRightDist = rightShoulder.distanceTo(rightWrist);
    final prevRightDist = prevRightShoulder.distanceTo(prevRightWrist);

    final reachDelta =
        ((currLeftDist - prevLeftDist) + (currRightDist - prevRightDist)) / 2.0;
    // 양수(+) = 멀어짐 (Push 성향), 음수(-) = 가까워짐 (Pull 성향)
    final reachScore = (reachDelta / 0.1).clamp(-1.0, 1.0);

    // 2. Z축 속도 계산 (Depth Velocity)
    final leftElbowZDelta = leftElbow.z - prevLeftElbow.z;
    final rightElbowZDelta = rightElbow.z - prevRightElbow.z;
    final zVelocity = ((leftElbowZDelta + rightElbowZDelta) / 2.0) * -1.0;
    // 음수 = 앞으로 = Push, 양수 = 뒤로 = Pull
    final zScore = (zVelocity / 0.05).clamp(-1.0, 1.0);

    // 3. 정적 상태 보정 (Hold)
    if (reachDelta.abs() < 0.001 && zVelocity.abs() < 0.001) {
      // 정적 상태: 어깨와 팔꿈치 Z좌표 비교
      final avgElbowZ = (leftElbow.z + rightElbow.z) / 2.0;
      final avgShoulderZ = (leftShoulder.z + rightShoulder.z) / 2.0;

      if (avgElbowZ > avgShoulderZ) {
        // 팔꿈치가 어깨보다 뒤에 있으면 Push 준비로 간주
        return 0.5;
      } else {
        // 팔꿈치가 몸통 옆이면 Pull 유지로 간주
        return -0.5;
      }
    }

    // 4. 가중 합산 (Reach 60%, Z축 속도 40%)
    final dynamicIntent = reachScore * 0.6 + zScore * 0.4;

    return dynamicIntent.clamp(-1.0, 1.0);
  }

  // =======================================================
  // [Main] 통합 분석 실행 (Entry Point)
  // =======================================================

  /// 생체역학 분석 수행
  ///
  /// **주의:** 기존 파라미터(jointDeltas, jointVariances 등)는 호환성을 위해 유지되지만,
  /// 내부 로직에서는 사용하지 않고 오직 landmarks와 dt로만 계산합니다.
  static Map<String, dynamic> performAnalysis({
    required Map<String, Point3D> landmarks,
    required double dt, // [Critical] 물리 엔진용 시간 변화량 (초 단위)
    // 아래는 호환성을 위해 유지하되 내부에서는 사용하지 않음
    required Map<String, double> jointDeltas, // ignore: unused_parameter
    required Map<String, double> jointVariances, // ignore: unused_parameter
    required Map<String, double> jointVelocities, // ignore: unused_parameter
    required Map<String, double> visibilityMap, // ignore: unused_parameter
    required double duration, // ignore: unused_parameter
    required double averageRhythmScore, // ignore: unused_parameter
    required String motionType,
    required String targetArea,
  }) {
    // 1. 정규화
    final normalizedLandmarks = VectorUtils.normalizeLandmarks(landmarks);

    // [NEW] 1.1. 범용 측면 뷰 감지 (운동 종목 무관, 좌표 패턴 기반)
    bool isSideView = false;
    final leftShoulder = normalizedLandmarks['left_shoulder'];
    final rightShoulder = normalizedLandmarks['right_shoulder'];
    final leftHip = normalizedLandmarks['left_hip'];
    final rightHip = normalizedLandmarks['right_hip'];

    if (leftShoulder != null &&
        rightShoulder != null &&
        leftHip != null &&
        rightHip != null) {
      // 상체와 하체 중 하나라도 "좌우가 겹친다"면 측면 뷰로 간주
      bool isShoulderOverlapped =
          (leftShoulder.x - rightShoulder.x).abs() < sideViewThreshold;
      bool isHipOverlapped = (leftHip.x - rightHip.x).abs() < sideViewThreshold;

      // 상체나 하체 중 하나라도 확실히 겹쳐 보이면 '측면'으로 판단
      isSideView = isShoulderOverlapped || isHipOverlapped;
    }

    // 1.5. 동적 의도 계산 (에너지 계산 전, 이전 프레임이 있는 경우에만)
    double dynamicIntent = 0.0;
    if (_previousLandmarks.isNotEmpty) {
      dynamicIntent = _calculateDynamicMovementIntent(
        normalizedLandmarks,
        _previousLandmarks,
      );
    }

    // 2. 각도 계산 (라디안 단위)
    final calculatedAngles = <String, double>{};

    // ✅ 어깨 각도 계산 (Spine Mid, Shoulder, Elbow)
    // Spine Mid(척추 중부)를 양쪽 어깨의 중점으로 가정
    if (normalizedLandmarks.containsKey('left_shoulder') &&
        normalizedLandmarks.containsKey('right_shoulder')) {
      final leftShoulder = normalizedLandmarks['left_shoulder']!;
      final rightShoulder = normalizedLandmarks['right_shoulder']!;
      final spineMid = leftShoulder.midpoint(
        rightShoulder,
      ); // Point3D의 midpoint 메서드 사용

      // 왼쪽 어깨 각도 계산 (spine mid, left shoulder, left elbow)
      if (normalizedLandmarks.containsKey('left_elbow')) {
        calculatedAngles['left_shoulder'] = _calculateAngle(
          spineMid,
          leftShoulder,
          normalizedLandmarks['left_elbow']!,
        );
      }

      // 오른쪽 어깨 각도 계산 (spine mid, right shoulder, right elbow)
      if (normalizedLandmarks.containsKey('right_elbow')) {
        calculatedAngles['right_shoulder'] = _calculateAngle(
          spineMid,
          rightShoulder,
          normalizedLandmarks['right_elbow']!,
        );
      }
    }

    // 무릎 각도 (깊이 보정 포함)
    if (normalizedLandmarks.containsKey('left_hip') &&
        normalizedLandmarks.containsKey('left_knee') &&
        normalizedLandmarks.containsKey('left_ankle')) {
      calculatedAngles['left_knee'] = _calculateKneeAngleWithDepthCorrection(
        normalizedLandmarks,
        'left',
        isSideView: isSideView, // [NEW] 측면 뷰 플래그 전달
      );
    }
    if (normalizedLandmarks.containsKey('right_hip') &&
        normalizedLandmarks.containsKey('right_knee') &&
        normalizedLandmarks.containsKey('right_ankle')) {
      calculatedAngles['right_knee'] = _calculateKneeAngleWithDepthCorrection(
        normalizedLandmarks,
        'right',
        isSideView: isSideView, // [NEW] 측면 뷰 플래그 전달
      );
    }

    // 팔꿈치 각도 (shoulder, elbow, wrist)
    if (normalizedLandmarks.containsKey('left_shoulder') &&
        normalizedLandmarks.containsKey('left_elbow') &&
        normalizedLandmarks.containsKey('left_wrist')) {
      calculatedAngles['left_elbow'] = _calculateAngle(
        normalizedLandmarks['left_shoulder']!,
        normalizedLandmarks['left_elbow']!,
        normalizedLandmarks['left_wrist']!,
      );
    }
    if (normalizedLandmarks.containsKey('right_shoulder') &&
        normalizedLandmarks.containsKey('right_elbow') &&
        normalizedLandmarks.containsKey('right_wrist')) {
      calculatedAngles['right_elbow'] = _calculateAngle(
        normalizedLandmarks['right_shoulder']!,
        normalizedLandmarks['right_elbow']!,
        normalizedLandmarks['right_wrist']!,
      );
    }

    // 고관절 각도 (spine mid, hip, knee)
    if (normalizedLandmarks.containsKey('left_shoulder') &&
        normalizedLandmarks.containsKey('right_shoulder') &&
        normalizedLandmarks.containsKey('left_hip') &&
        normalizedLandmarks.containsKey('left_knee')) {
      final spineMid = normalizedLandmarks['left_shoulder']!.midpoint(
        normalizedLandmarks['right_shoulder']!,
      );
      calculatedAngles['left_hip'] = _calculateAngle(
        spineMid,
        normalizedLandmarks['left_hip']!,
        normalizedLandmarks['left_knee']!,
      );
    }
    if (normalizedLandmarks.containsKey('right_shoulder') &&
        normalizedLandmarks.containsKey('left_shoulder') &&
        normalizedLandmarks.containsKey('right_hip') &&
        normalizedLandmarks.containsKey('right_knee')) {
      final spineMid = normalizedLandmarks['right_shoulder']!.midpoint(
        normalizedLandmarks['left_shoulder']!,
      );
      calculatedAngles['right_hip'] = _calculateAngle(
        spineMid,
        normalizedLandmarks['right_hip']!,
        normalizedLandmarks['right_knee']!,
      );
    }

    // 발목 각도 (knee, ankle, foot_index)
    if (normalizedLandmarks.containsKey('left_knee') &&
        normalizedLandmarks.containsKey('left_ankle') &&
        normalizedLandmarks.containsKey('left_foot_index')) {
      calculatedAngles['left_ankle'] = _calculateAngle(
        normalizedLandmarks['left_knee']!,
        normalizedLandmarks['left_ankle']!,
        normalizedLandmarks['left_foot_index']!,
      );
    }
    if (normalizedLandmarks.containsKey('right_knee') &&
        normalizedLandmarks.containsKey('right_ankle') &&
        normalizedLandmarks.containsKey('right_foot_index')) {
      calculatedAngles['right_ankle'] = _calculateAngle(
        normalizedLandmarks['right_knee']!,
        normalizedLandmarks['right_ankle']!,
        normalizedLandmarks['right_foot_index']!,
      );
    }

    // 3. 안정성/패턴 분석
    final stability = StabilityCalculator.calculateStability(
      normalizedLandmarks,
      isSideView: isSideView, // [NEW] 측면 뷰 플래그 전달
    );
    final motionResult = _motionAnalyzer.analyze(normalizedLandmarks);
    final pattern = motionResult.pattern;
    final movementState = motionResult.state;

    // 4. Stabilization Check
    if (pattern == MotionPattern.STABILIZING) {
      return _emptyResult();
    }

    // 5. 물리 엔진 계산 (Joint Loop)
    final jointStressScores = <String, double>{};
    double totalForce = 0.0;

    // 관절 계산 순서를 정의 (상위 관절이 먼저 오도록)
    // MVP: 현재 프로젝트의 모든 관절 키를 명시적으로 포함하여 누락 방지
    final orderedJoints = [
      'left_shoulder', 'right_shoulder', // 상위 관절 먼저 (팔꿈치 계산에 필요)
      'left_elbow', 'right_elbow', // 팔꿈치는 어깨 다음
      'left_hip', 'right_hip',
      'left_knee', 'right_knee',
      'left_ankle', 'right_ankle',
    ];

    for (String jointName in orderedJoints) {
      final controller = _jointControllers[jointName];
      if (controller == null) continue;

      final currentAngle = calculatedAngles[jointName];
      if (currentAngle == null) continue;

      final prevAngle = _previousAngles[jointName] ?? currentAngle;
      final muscleForce = 1.0; // 기본값 (추후 실제 근육 힘 계산 로직 추가 가능)

      // 팔꿈치일 때 상위 관절(어깨) 스트레스 가져오기
      double? bigMuscleForce;
      if (jointName == 'left_elbow') {
        final shoulderScore = jointStressScores['left_shoulder'];
        if (shoulderScore != null) {
          // 점수를 0.0~1.0 비율로 변환 (스트레스 점수는 0.0~1.0 범위이므로 그대로 사용)
          bigMuscleForce = shoulderScore;
        }
      } else if (jointName == 'right_elbow') {
        final shoulderScore = jointStressScores['right_shoulder'];
        if (shoulderScore != null) {
          // 점수를 0.0~1.0 비율로 변환 (스트레스 점수는 0.0~1.0 범위이므로 그대로 사용)
          bigMuscleForce = shoulderScore;
        }
      }

      final stressScore = controller.calculateJointStress(
        currentAngle,
        prevAngle,
        dt,
        muscleForce,
        bigMuscleForce: bigMuscleForce, // 선택적 파라미터로 전달 (0.0~1.0 범위)
        debugName: jointName, // ✅ 디버깅을 위해 관절 이름 전달
      );

      jointStressScores[jointName] = stressScore;
      _previousAngles[jointName] = currentAngle; // 다음 프레임을 위해 저장
      totalForce += stressScore;
    }

    // 6. 에너지 누수 계산
    final energyResult = EnergyLeakEngine.calculateEnergyLeak(
      totalForce: totalForce,
      stability: stability,
      pattern: pattern,
      movementState: movementState,
      targetArea: targetArea,
      isSideView: isSideView, // [NEW] 측면 뷰 플래그 전달
    );

    // 6.5. 하체 보상 작용 로직 (Glute Inhibition Compensation)
    final gluteCompensationScores =
        energyResult['effectiveMuscleScores'] as Map<String, double>?;
    if (gluteCompensationScores != null) {
      final glutesScore = gluteCompensationScores['glutes'] ?? 0.0;

      // 둔근 점수가 0.4 미만인 경우 보상 작용 적용
      if (glutesScore < 0.4) {
        // 대퇴사두근 점수 증가 (과도한 무릎 사용 반영)
        if (gluteCompensationScores.containsKey('quadriceps')) {
          gluteCompensationScores['quadriceps'] =
              (gluteCompensationScores['quadriceps']! * 1.3).clamp(0.0, 1.0);
        }

        // 내전근 점수 감소 (안정성 기여 실패 반영)
        if (gluteCompensationScores.containsKey('adductors')) {
          gluteCompensationScores['adductors'] =
              (gluteCompensationScores['adductors']! * 0.7).clamp(0.0, 1.0);
        }
      }
    }

    // 7. 결과 매핑 (Data Scaling 적용)
    // Score Scaling: 0.0~1.0 → 0~100
    final romData = <String, double>{};

    // jointStressScores와 energyResult의 jointStressScores를 합침
    final allJointStresses = <String, double>{};
    allJointStresses.addAll(jointStressScores);
    final energyJointStresses =
        energyResult['jointStressScores'] as Map<String, double>?;
    if (energyJointStresses != null) {
      energyJointStresses.forEach((joint, stress) {
        allJointStresses[joint] = (allJointStresses[joint] ?? 0.0) + stress;
      });
    }

    // Target Filtering: 타겟 부위에 따라 관절 점수 필터링
    final upperBodyJoints = {
      'left_shoulder',
      'right_shoulder',
      'left_elbow',
      'right_elbow',
    };
    final lowerBodyJoints = {
      'left_knee',
      'right_knee',
      'left_hip',
      'right_hip',
      'left_ankle',
      'right_ankle',
    };

    allJointStresses.forEach((joint, stressScore) {
      double filteredScore = stressScore;

      // UPPER 타겟: 하체 관절 점수에 0.1 곱하기
      if (targetArea.toUpperCase() == 'UPPER' &&
          lowerBodyJoints.contains(joint)) {
        filteredScore = stressScore * 0.1;
      }
      // LOWER 타겟: 상체 관절 점수에 0.1 곱하기
      else if (targetArea.toUpperCase() == 'LOWER' &&
          upperBodyJoints.contains(joint)) {
        filteredScore = stressScore * 0.1;
      }
      // FULL 타겟 또는 기타: 필터링 없음

      romData[joint] = (filteredScore * 100).round().toDouble();
    });

    // 무릎 관절 점수 억제 로직 (Kinetic Chain AND 조건)
    // romData 생성 직후, muscleUsage 생성 전에 추가
    // 왼쪽 무릎 억제
    final leftHipScore =
        romData['left_hip'] ?? 0.0; // muscleUsage는 아직 생성 전이므로 romData 사용
    final leftAnkleScore = romData['left_ankle'] ?? 0.0;
    final leftKneeScore = romData['left_knee'] ?? 0.0;

    bool isLeftHipGood = leftHipScore > 40.0; // 고관절 기준: 40점 이상
    bool isLeftAnkleGood = leftAnkleScore > 20.0; // 발목 기준: 20점 이상

    if (isLeftHipGood && isLeftAnkleGood) {
      // 둘 다 좋으면 무릎은 편안함 -> 점수 억제 (0.7배)
      romData['left_knee'] = leftKneeScore * 0.7;
    }
    // else: 하나라도 안 좋으면 무릎이 고생함 -> 억제 없음 (높은 점수 유지)

    // 오른쪽 무릎도 동일하게 적용
    final rightHipScore = romData['right_hip'] ?? 0.0;
    final rightAnkleScore = romData['right_ankle'] ?? 0.0;
    final rightKneeScore = romData['right_knee'] ?? 0.0;

    bool isRightHipGood = rightHipScore > 40.0;
    bool isRightAnkleGood = rightAnkleScore > 20.0;

    if (isRightHipGood && isRightAnkleGood) {
      romData['right_knee'] = rightKneeScore * 0.7;
    }

    final muscleUsage = <String, double>{};
    final effectiveScores =
        energyResult['effectiveMuscleScores'] as Map<String, double>?;
    if (effectiveScores != null) {
      effectiveScores.forEach((muscle, score) {
        // Double Prefix 방지: 이미 'left_'나 'right_'로 시작하면 그대로 사용 (중복 방지)
        final scaledScore = (score * 100).clamp(
          0.0,
          100.0,
        ); // 가중치로 인한 100% 초과 방지
        if (muscle.startsWith('left_') || muscle.startsWith('right_')) {
          muscleUsage[muscle] = scaledScore;
        } else {
          // 순수 근육명이면 좌우로 분리하여 할당
          muscleUsage['left_$muscle'] = scaledScore;
          muscleUsage['right_$muscle'] = scaledScore;
        }
      });
    }

    // compensationMuscleScores도 추가 (보상 근육)
    final compensationScores =
        energyResult['compensationMuscleScores'] as Map<String, double>?;
    if (compensationScores != null) {
      compensationScores.forEach((muscle, score) {
        // Double Prefix 방지: 이미 'left_'나 'right_'로 시작하면 그대로 사용 (중복 방지)
        final scaledScore = (score * 100).clamp(
          0.0,
          100.0,
        ); // 가중치로 인한 100% 초과 방지
        if (muscle.startsWith('left_') || muscle.startsWith('right_')) {
          muscleUsage[muscle] = ((muscleUsage[muscle] ?? 0.0) + scaledScore)
              .clamp(0.0, 100.0);
        } else {
          // 순수 근육명이면 좌우로 분리하여 할당
          muscleUsage['left_$muscle'] =
              ((muscleUsage['left_$muscle'] ?? 0.0) + scaledScore).clamp(
                0.0,
                100.0,
              );
          muscleUsage['right_$muscle'] =
              ((muscleUsage['right_$muscle'] ?? 0.0) + scaledScore).clamp(
                0.0,
                100.0,
              );
        }
      });
    }

    // [NEW] 측면 뷰일 때 대칭 미러링 적용 (잘 보이는 쪽의 데이터를 양쪽에 동기화)
    if (isSideView) {
      // 대칭되는 근육 쌍 정의
      final symmetricPairs = [
        // 상체
        ['left_pectorals', 'right_pectorals'],
        ['left_latissimus', 'right_latissimus'],
        ['left_deltoids', 'right_deltoids'],
        ['left_biceps', 'right_biceps'],
        ['left_triceps', 'right_triceps'],
        // 하체
        ['left_quadriceps', 'right_quadriceps'],
        ['left_hamstrings', 'right_hamstrings'],
        ['left_glutes', 'right_glutes'],
        ['left_adductors', 'right_adductors'],
        ['left_calves', 'right_calves'],
      ];

      // 각 쌍에 대해 더 높은 점수를 양쪽에 적용
      for (final pair in symmetricPairs) {
        final leftKey = pair[0];
        final rightKey = pair[1];

        // 키 존재 여부 확인 (trapezius는 좌우 분리되지 않을 수 있음)
        if (!muscleUsage.containsKey(leftKey) ||
            !muscleUsage.containsKey(rightKey)) {
          continue; // 한쪽이라도 없으면 스킵
        }

        final leftScore = muscleUsage[leftKey] ?? 0.0;
        final rightScore = muscleUsage[rightKey] ?? 0.0;

        // 더 높은 점수를 찾아 양쪽에 덮어씌우기
        final maxScore = math.max(leftScore, rightScore);

        if (maxScore > 0.0) {
          muscleUsage[leftKey] = maxScore;
          muscleUsage[rightKey] = maxScore;
        }
      }

      // trapezius는 좌우 분리되지 않을 수 있으므로 별도 처리
      // [명확화] 좌우 키(left_trapezius, right_trapezius)가 모두 존재할 때만 비교 및 동기화
      // 단일 키(trapezius)가 있는 경우는 이미 통합된 점수이므로 건드리지 않음 (별도 처리 불필요)
      if (muscleUsage.containsKey('left_trapezius') &&
          muscleUsage.containsKey('right_trapezius')) {
        final leftTrap = muscleUsage['left_trapezius'] ?? 0.0;
        final rightTrap = muscleUsage['right_trapezius'] ?? 0.0;
        final maxTrap = math.max(leftTrap, rightTrap);
        if (maxTrap > 0.0) {
          muscleUsage['left_trapezius'] = maxTrap;
          muscleUsage['right_trapezius'] = maxTrap;
        }
      }
      // 참고: 단일 'trapezius' 키가 있는 경우는 별도 처리하지 않음 (통합 점수로 간주)
      // 한쪽만 존재하는 경우(left_trapezius만 있거나 right_trapezius만 있는 경우)도 동기화하지 않음
    }

    // 7.4. 자세 기반 장력 추론 (Pose-Based Tension Estimation)
    // A. 등 근육 역학 (Back Biomechanics)

    // 1. Shoulder Adduction (수직 당기기 패턴)
    // leftShoulder, rightShoulder는 이미 위에서 정의되었으므로 재사용
    final leftElbow = normalizedLandmarks['left_elbow'];
    final rightElbow = normalizedLandmarks['right_elbow'];

    if (leftShoulder != null &&
        rightShoulder != null &&
        leftElbow != null &&
        rightElbow != null) {
      // SpineVector 계산: 양쪽 어깨의 중점을 기준으로 한 척추 방향 벡터
      final spineMid = leftShoulder.midpoint(rightShoulder);
      final leftHip = normalizedLandmarks['left_hip'];
      final rightHip = normalizedLandmarks['right_hip'];
      if (leftHip != null && rightHip != null) {
        final spineBottom = leftHip.midpoint(rightHip);
        final spineVector = spineBottom.subtract(spineMid).normalize();

        // ArmVector 계산: 어깨에서 팔꿈치로의 벡터 (좌우 각각)
        final leftArmVector = leftElbow.subtract(leftShoulder).normalize();
        final rightArmVector = rightElbow.subtract(rightShoulder).normalize();

        // 내적(Dot Product) 계산: SpineVector와 ArmVector의 내적
        final leftDot = spineVector.dot(leftArmVector);
        final rightDot = spineVector.dot(rightArmVector);

        // 두 벡터가 평행에 가까울수록(겨드랑이 각도가 0도에 수렴) 광배근 점수 지수적으로 증가 (최대 3.0배)
        // dot product가 1.0에 가까울수록 평행 (최대 3.0배)
        final leftLatBoost = (1.0 + leftDot.abs() * 2.0).clamp(1.0, 3.0);
        final rightLatBoost = (1.0 + rightDot.abs() * 2.0).clamp(1.0, 3.0);

        if (muscleUsage.containsKey('left_latissimus')) {
          muscleUsage['left_latissimus'] =
              (muscleUsage['left_latissimus']! * leftLatBoost).clamp(
                0.0,
                100.0,
              );
        }
        if (muscleUsage.containsKey('right_latissimus')) {
          muscleUsage['right_latissimus'] =
              (muscleUsage['right_latissimus']! * rightLatBoost).clamp(
                0.0,
                100.0,
              );
        }

        // 동시에 상부 승모근 점수는 0.5배로 억제
        if (muscleUsage.containsKey('trapezius')) {
          muscleUsage['trapezius'] = (muscleUsage['trapezius']! * 0.5).clamp(
            0.0,
            100.0,
          );
        }
      }

      // 2. Scapular Retraction (수평 당기기 패턴)
      // Elbow.z > Shoulder.z (팔꿈치가 어깨보다 더 멀리 있음 = 뒤쪽/Posterior) 조건 확인
      // 주의: MediaPipe 좌표계에서 Z값은 카메라에 가까울수록 음수(-), 멀수록 양수(+)일 수 있음
      // WorldLandmarks를 사용하는 것이 권장되지만, 불가능한 경우 임계값을 넉넉하게 설정 (0.05)
      final leftElbowPosterior = leftElbow.z > leftShoulder.z + 0.05;
      final rightElbowPosterior = rightElbow.z > rightShoulder.z + 0.05;

      if (leftElbowPosterior || rightElbowPosterior) {
        // 조건 만족 시: 중/하부 승모근 및 능형근 점수를 1.5배 부스팅
        // 능형근(rhomboids)은 현재 muscleUsage에 없을 수 있으므로, trapezius에 반영
        if (muscleUsage.containsKey('trapezius')) {
          // Shoulder Adduction에서 0.5배로 억제된 것을 1.5배로 보정 (실제로는 0.75배)
          // 하지만 Scapular Retraction이 감지되면 중/하부 승모근이 활성화되므로 1.5배 적용
          muscleUsage['trapezius'] = (muscleUsage['trapezius']! * 1.5).clamp(
            0.0,
            100.0,
          );
        }
        // 능형근은 별도 키가 없으므로 trapezius에 포함 (또는 나중에 추가 가능)
      }
    }

    // B. 가슴 근육 역학 (Chest Biomechanics)
    if (leftShoulder != null &&
        rightShoulder != null &&
        leftElbow != null &&
        rightElbow != null) {
      // 1. Horizontal Adduction (모으는 패턴)
      final elbowDistance = leftElbow.distanceTo(rightElbow);
      final shoulderDistance = leftShoulder.distanceTo(rightShoulder);

      if (shoulderDistance > 0.0) {
        // 팔꿈치 간 거리가 어깨 간 거리보다 작아질수록 대흉근 점수 최대 2.5배 부스팅
        final adductionRatio = (1.0 - (elbowDistance / shoulderDistance)).clamp(
          0.0,
          1.0,
        );
        final pectoralBoost = (1.0 + adductionRatio * 1.5).clamp(1.0, 2.5);

        if (muscleUsage.containsKey('left_pectorals')) {
          muscleUsage['left_pectorals'] =
              (muscleUsage['left_pectorals']! * pectoralBoost).clamp(
                0.0,
                100.0,
              );
        }
        if (muscleUsage.containsKey('right_pectorals')) {
          muscleUsage['right_pectorals'] =
              (muscleUsage['right_pectorals']! * pectoralBoost).clamp(
                0.0,
                100.0,
              );
        }

        // 삼두근 개입 낮추기 (점수에 0.8배 적용)
        if (muscleUsage.containsKey('left_triceps')) {
          muscleUsage['left_triceps'] = (muscleUsage['left_triceps']! * 0.8)
              .clamp(0.0, 100.0);
        }
        if (muscleUsage.containsKey('right_triceps')) {
          muscleUsage['right_triceps'] = (muscleUsage['right_triceps']! * 0.8)
              .clamp(0.0, 100.0);
        }
      }

      // 2. Anterior Projection (미는 패턴)
      final leftWrist = normalizedLandmarks['left_wrist'];
      final rightWrist = normalizedLandmarks['right_wrist'];

      if (leftWrist != null) {
        // 손목(Wrist)의 Z좌표가 어깨보다 전방(Anterior, Z값이 작음 = Wrist.z < Shoulder.z)에 위치하고
        // 팔꿈치가 완전히 펴지지 않은 상태(Elbow 각도 > 30도)인지 확인
        // 주의: MediaPipe 좌표계에서 Z값은 카메라에 가까울수록 음수(-), 멀수록 양수(+)일 수 있음
        // WorldLandmarks를 사용하는 것이 권장되지만, 불가능한 경우 임계값을 넉넉하게 설정 (0.05)
        final leftWristAnterior = leftWrist.z < leftShoulder.z - 0.05;
        final leftElbowAngle = calculatedAngles['left_elbow'] ?? 0.0;
        final leftElbowNotLocked =
            leftElbowAngle > (30.0 * math.pi / 180.0); // 30도

        if (leftWristAnterior && leftElbowNotLocked) {
          // 조건 만족 시: 움직임이 없더라도 '버티는 장력'으로 간주하여 대흉근 점수 1.5배 상향 조정
          if (muscleUsage.containsKey('left_pectorals')) {
            muscleUsage['left_pectorals'] =
                (muscleUsage['left_pectorals']! * 1.5).clamp(0.0, 100.0);
          }
        }
      }

      if (rightWrist != null) {
        final rightWristAnterior = rightWrist.z < rightShoulder.z - 0.05;
        final rightElbowAngle = calculatedAngles['right_elbow'] ?? 0.0;
        final rightElbowNotLocked =
            rightElbowAngle > (30.0 * math.pi / 180.0); // 30도

        if (rightWristAnterior && rightElbowNotLocked) {
          if (muscleUsage.containsKey('right_pectorals')) {
            muscleUsage['right_pectorals'] =
                (muscleUsage['right_pectorals']! * 1.5).clamp(0.0, 100.0);
          }
        }
      }
    }

    // 7.5. 상호 억제 로직 적용 (Reciprocal Inhibition)
    if (dynamicIntent > 0.2) {
      // Push 상태: 주동근 유지, 길항근 억제
      final inhibitionFactor = (1.0 - dynamicIntent).clamp(0.0, 1.0);

      // 억제 대상: latissimus, trapezius, biceps
      final inhibitedMuscles = ['latissimus', 'trapezius', 'biceps'];
      for (final muscle in inhibitedMuscles) {
        final leftKey = 'left_$muscle';
        final rightKey = 'right_$muscle';

        if (muscleUsage.containsKey(leftKey)) {
          muscleUsage[leftKey] = (muscleUsage[leftKey]! * inhibitionFactor)
              .clamp(0.0, 100.0);
        }
        if (muscleUsage.containsKey(rightKey)) {
          muscleUsage[rightKey] = (muscleUsage[rightKey]! * inhibitionFactor)
              .clamp(0.0, 100.0);
        }
      }
    } else if (dynamicIntent < -0.2) {
      // Pull 상태: 주동근 유지, 길항근 억제
      final inhibitionFactor = (1.0 - dynamicIntent.abs()).clamp(0.0, 1.0);

      // 억제 대상: pectorals, triceps
      final inhibitedMuscles = ['pectorals', 'triceps'];
      for (final muscle in inhibitedMuscles) {
        final leftKey = 'left_$muscle';
        final rightKey = 'right_$muscle';

        if (muscleUsage.containsKey(leftKey)) {
          muscleUsage[leftKey] = (muscleUsage[leftKey]! * inhibitionFactor)
              .clamp(0.0, 100.0);
        }
        if (muscleUsage.containsKey(rightKey)) {
          muscleUsage[rightKey] = (muscleUsage[rightKey]! * inhibitionFactor)
              .clamp(0.0, 100.0);
        }
      }
    }
    // 중립 상태 (-0.2 <= dynamicIntent <= 0.2): 억제 없음

    // Thresholding: 최종 점수가 0.05 미만이면 0.0으로 처리
    final threshold = 0.05;
    romData.forEach((joint, score) {
      if (score < threshold) {
        romData[joint] = 0.0;
      }
    });
    muscleUsage.forEach((muscle, score) {
      if (score < threshold) {
        muscleUsage[muscle] = 0.0;
      }
    });

    // Warning Formatting
    final warnings = _convertStabilityMetricsToWarning(stability);
    final stabilityWarning = warnings.isEmpty ? "" : warnings;

    // MotionPattern → String 변환
    final biomechPattern = pattern.toString().split('.').last;

    // Target Area Noise Gate 필터링 (return 직전)
    final targetAreaUpper = targetArea.toUpperCase();
    if (targetAreaUpper == 'UPPER') {
      // Upper Body Mode: 하체 관절과 근육에 Gain 0.15 적용
      // 하체 관절
      final lowerBodyJoints = [
        'left_hip',
        'right_hip',
        'left_knee',
        'right_knee',
        'left_ankle',
        'right_ankle',
      ];
      for (final joint in lowerBodyJoints) {
        if (romData.containsKey(joint)) {
          romData[joint] = (romData[joint]! * 0.15).clamp(0.0, 100.0);
        }
      }
      // 하체 근육
      final lowerBodyMuscles = [
        'left_quadriceps',
        'right_quadriceps',
        'left_hamstrings',
        'right_hamstrings',
        'left_glutes',
        'right_glutes',
        'left_calves',
        'right_calves',
      ];
      for (final muscle in lowerBodyMuscles) {
        if (muscleUsage.containsKey(muscle)) {
          muscleUsage[muscle] = (muscleUsage[muscle]! * 0.15).clamp(0.0, 100.0);
        }
      }
    } else if (targetAreaUpper == 'LOWER') {
      // Lower Body Mode: 상체 관절과 근육에 Gain 0.15 적용
      // 상체 관절
      final upperBodyJoints = [
        'left_shoulder',
        'right_shoulder',
        'left_elbow',
        'right_elbow',
      ];
      for (final joint in upperBodyJoints) {
        if (romData.containsKey(joint)) {
          romData[joint] = (romData[joint]! * 0.15).clamp(0.0, 100.0);
        }
      }
      // 상체 근육
      final upperBodyMuscles = [
        'left_latissimus',
        'right_latissimus',
        'left_pectorals',
        'right_pectorals',
        'left_deltoids',
        'right_deltoids',
        'left_biceps',
        'right_biceps',
        'left_triceps',
        'right_triceps',
        'trapezius',
      ];
      for (final muscle in upperBodyMuscles) {
        if (muscleUsage.containsKey(muscle)) {
          muscleUsage[muscle] = (muscleUsage[muscle]! * 0.15).clamp(0.0, 100.0);
        }
      }
    }
    // Full Body Mode: 감쇠 없음 (원본 신호 유지)

    // 이전 프레임 랜드마크 저장 (다음 프레임을 위해)
    _previousLandmarks.clear();
    _previousLandmarks.addAll(normalizedLandmarks);

    return {
      'detailed_muscle_usage': sanitizeOutputMap(muscleUsage),
      'rom_data': sanitizeOutputMap(romData),
      'biomech_pattern': biomechPattern,
      'stability_warning': stabilityWarning,
    };
  }
}
