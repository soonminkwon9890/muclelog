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
      angleMaxDegrees: 45,   // 족저굴곡
      stiffness: 20.0,
      dampingCoefficient: 1.0,
      staticFriction: 0.1,
      kineticFriction: 0.05,
    ),
    'right_ankle': JointController.fromDegrees(
      angleMinDegrees: -45, // 족배굴곡
      angleMaxDegrees: 45,   // 족저굴곡
      stiffness: 20.0,
      dampingCoefficient: 1.0,
      staticFriction: 0.1,
      kineticFriction: 0.05,
    ),
  };
  
  /// 이전 각도 저장용 Map (JointController의 calculateJointStress 호출 시 사용)
  static final Map<String, double> _previousAngles = {};

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
  static double _calculateAngle(
    Point3D a,
    Point3D b,
    Point3D c,
  ) {
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
    
    // 2. 각도 계산 (라디안 단위)
    final calculatedAngles = <String, double>{};
    
    // ✅ 어깨 각도 계산 (Spine Mid, Shoulder, Elbow)
    // Spine Mid(척추 중부)를 양쪽 어깨의 중점으로 가정
    if (normalizedLandmarks.containsKey('left_shoulder') &&
        normalizedLandmarks.containsKey('right_shoulder')) {
      
      final leftShoulder = normalizedLandmarks['left_shoulder']!;
      final rightShoulder = normalizedLandmarks['right_shoulder']!;
      final spineMid = leftShoulder.midpoint(rightShoulder); // Point3D의 midpoint 메서드 사용

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
    
    // 무릎 각도 (hip, knee, ankle)
    if (normalizedLandmarks.containsKey('left_hip') &&
        normalizedLandmarks.containsKey('left_knee') &&
        normalizedLandmarks.containsKey('left_ankle')) {
      calculatedAngles['left_knee'] = _calculateAngle(
        normalizedLandmarks['left_hip']!,
        normalizedLandmarks['left_knee']!,
        normalizedLandmarks['left_ankle']!,
      );
    }
    if (normalizedLandmarks.containsKey('right_hip') &&
        normalizedLandmarks.containsKey('right_knee') &&
        normalizedLandmarks.containsKey('right_ankle')) {
      calculatedAngles['right_knee'] = _calculateAngle(
        normalizedLandmarks['right_hip']!,
        normalizedLandmarks['right_knee']!,
        normalizedLandmarks['right_ankle']!,
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
    final stability = StabilityCalculator.calculateStability(normalizedLandmarks);
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
      'left_shoulder', 'right_shoulder',  // 상위 관절 먼저 (팔꿈치 계산에 필요)
      'left_elbow', 'right_elbow',        // 팔꿈치는 어깨 다음
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
    );

    // 7. 결과 매핑 (Data Scaling 적용)
    // Score Scaling: 0.0~1.0 → 0~100
    final romData = <String, double>{};
    
    // jointStressScores와 energyResult의 jointStressScores를 합침
    final allJointStresses = <String, double>{};
    allJointStresses.addAll(jointStressScores);
    final energyJointStresses = energyResult['jointStressScores'] as Map<String, double>?;
    if (energyJointStresses != null) {
      energyJointStresses.forEach((joint, stress) {
        allJointStresses[joint] = (allJointStresses[joint] ?? 0.0) + stress;
      });
    }
    
    // Target Filtering: 타겟 부위에 따라 관절 점수 필터링
    final upperBodyJoints = {'left_shoulder', 'right_shoulder', 'left_elbow', 'right_elbow'};
    final lowerBodyJoints = {'left_knee', 'right_knee', 'left_hip', 'right_hip', 'left_ankle', 'right_ankle'};
    
    allJointStresses.forEach((joint, stressScore) {
      double filteredScore = stressScore;
      
      // UPPER 타겟: 하체 관절 점수에 0.1 곱하기
      if (targetArea.toUpperCase() == 'UPPER' && lowerBodyJoints.contains(joint)) {
        filteredScore = stressScore * 0.1;
      }
      // LOWER 타겟: 상체 관절 점수에 0.1 곱하기
      else if (targetArea.toUpperCase() == 'LOWER' && upperBodyJoints.contains(joint)) {
        filteredScore = stressScore * 0.1;
      }
      // FULL 타겟 또는 기타: 필터링 없음
      
      romData[joint] = (filteredScore * 100).round().toDouble();
    });
    
    final muscleUsage = <String, double>{};
    final effectiveScores = energyResult['effectiveMuscleScores'] as Map<String, double>?;
    if (effectiveScores != null) {
      effectiveScores.forEach((muscle, score) {
        // Double Prefix 방지: 이미 'left_'나 'right_'로 시작하면 그대로 사용 (중복 방지)
        final scaledScore = (score * 100).clamp(0.0, 100.0); // 가중치로 인한 100% 초과 방지
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
    final compensationScores = energyResult['compensationMuscleScores'] as Map<String, double>?;
    if (compensationScores != null) {
      compensationScores.forEach((muscle, score) {
        // Double Prefix 방지: 이미 'left_'나 'right_'로 시작하면 그대로 사용 (중복 방지)
        final scaledScore = (score * 100).clamp(0.0, 100.0); // 가중치로 인한 100% 초과 방지
        if (muscle.startsWith('left_') || muscle.startsWith('right_')) {
          muscleUsage[muscle] = ((muscleUsage[muscle] ?? 0.0) + scaledScore).clamp(0.0, 100.0);
        } else {
          // 순수 근육명이면 좌우로 분리하여 할당
          muscleUsage['left_$muscle'] = ((muscleUsage['left_$muscle'] ?? 0.0) + scaledScore).clamp(0.0, 100.0);
          muscleUsage['right_$muscle'] = ((muscleUsage['right_$muscle'] ?? 0.0) + scaledScore).clamp(0.0, 100.0);
        }
      });
    }
    
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

    return {
      'detailed_muscle_usage': sanitizeOutputMap(muscleUsage),
      'rom_data': sanitizeOutputMap(romData),
      'biomech_pattern': biomechPattern,
      'stability_warning': stabilityWarning,
    };
  }
}
