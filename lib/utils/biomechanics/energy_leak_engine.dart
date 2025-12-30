import 'motion_analyzer.dart';
import 'stability_calculator.dart';

/// 에너지 누수 엔진 클래스
/// 
/// 안정성 지표와 동작 패턴을 기반으로 에너지 누수를 계산하고,
/// 효율적인 근육 활성도와 보상 근육 점수를 산출합니다.
/// 
/// **Efficiency Formula:**
/// Efficiency = 1.0 - (StabilityPenalty + PatternPenalty)
/// 
/// **EffectiveForce = RawForce * Efficiency**
/// **LeakedEnergy = RawForce * (1 - Efficiency)**
/// 
/// LeakedEnergy는 보상 근육(승모, 허리 등)의 스트레스로 가산됨
class EnergyLeakEngine {
  /// 에너지 누수 계산
  /// 
  /// **입력:**
  /// - `totalForce`: 해당 관절의 움직임 총량 (Joint Delta, Raw Force)
  /// - `stability`: 안정성 지표
  /// - `pattern`: 동작 패턴
  /// - `movementState`: 운동 상태 (ECCENTRIC/CONCENTRIC/ISOMETRIC)
  /// - `targetArea`: 타겟 부위 (UPPER/LOWER/FULL)
  /// 
  /// **출력:**
  /// - `effectiveMuscleScores`: 효율적으로 사용된 근육 점수
  /// - `compensationMuscleScores`: 보상 근육 점수 (누수된 에너지)
  /// - `jointStressScores`: 관절 스트레스 점수 (누수로 인한 관절 부하)
  static Map<String, dynamic> calculateEnergyLeak({
    required double totalForce,
    required StabilityMetrics stability,
    required MotionPattern pattern,
    required MovementState movementState,
    required String targetArea,
    bool isSideView = false, // [NEW] 측면 뷰 플래그
  }) {
    final effectiveMuscleScores = <String, double>{};
    final compensationMuscleScores = <String, double>{};
    final jointStressScores = <String, double>{};

    // Efficiency 계산
    final stabilityPenalty = _calculateStabilityPenalty(stability);
    final patternPenalty = _calculatePatternPenalty(pattern, movementState);
    final efficiency = (1.0 - (stabilityPenalty + patternPenalty)).clamp(0.0, 1.0);

    // EffectiveForce와 LeakedEnergy 계산
    final effectiveForce = totalForce * efficiency;
    final leakedEnergy = totalForce * (1.0 - efficiency);

    // 타겟 부위에 따라 에너지 누수 처리
    final isUpper = targetArea.toUpperCase() == 'UPPER' || targetArea.toUpperCase() == 'FULL';
    final isLower = targetArea.toUpperCase() == 'LOWER' || targetArea.toUpperCase() == 'FULL';

    if (isUpper) {
      // 상체 누수 로직
      final upperLeaks = _calculateUpperBodyLeaks(
        totalForce: totalForce,
        stability: stability,
        effectiveForce: effectiveForce,
        leakedEnergy: leakedEnergy,
        pattern: pattern,
        targetArea: targetArea,
        isSideView: isSideView, // [권장] 확장성을 위해 전달 (현재는 사용하지 않지만 향후 팔꿈치 벌어짐 등 오판 방지 로직 추가 가능)
      );

      effectiveMuscleScores.addAll(upperLeaks['effective'] as Map<String, double>);
      compensationMuscleScores.addAll(upperLeaks['compensation'] as Map<String, double>);
      jointStressScores.addAll(upperLeaks['jointStress'] as Map<String, double>);
    }

    if (isLower) {
      // 하체 누수 로직
      final lowerLeaks = _calculateLowerBodyLeaks(
        totalForce: totalForce,
        stability: stability,
        pattern: pattern,
        effectiveForce: effectiveForce,
        leakedEnergy: leakedEnergy,
        targetArea: targetArea,
        isSideView: isSideView, // [NEW] 전달
      );

      effectiveMuscleScores.addAll(lowerLeaks['effective'] as Map<String, double>);
      compensationMuscleScores.addAll(lowerLeaks['compensation'] as Map<String, double>);
      jointStressScores.addAll(lowerLeaks['jointStress'] as Map<String, double>);
    }

    return {
      'effectiveMuscleScores': effectiveMuscleScores,
      'compensationMuscleScores': compensationMuscleScores,
      'jointStressScores': jointStressScores,
      'efficiency': efficiency,
    };
  }

  /// 안정성 페널티 계산
  /// 
  /// StabilityPenalty = elevationFactor * 0.2 + valgusFactor * 0.3 + ...
  static double _calculateStabilityPenalty(StabilityMetrics stability) {
    double penalty = 0.0;

    // 으쓱 (elevationFactor): 0.2 감점
    penalty += stability.elevationFactor * 0.2;

    // 무릎 안쪽 (valgusFactor): 0.3 감점
    penalty += stability.valgusFactor * 0.3;

    // 골반 경사 (pelvicTiltFactor): 정규화된 값에 비례하여 감점
    // pelvicTiltFactor는 실제 거리 값이므로 정규화 필요
    penalty += (stability.pelvicTiltFactor * 0.1).clamp(0.0, 0.2);

    return penalty.clamp(0.0, 1.0);
  }

  /// 패턴 페널티 계산
  /// 
  /// 동작 패턴에 따른 추가 감점
  static double _calculatePatternPenalty(
    MotionPattern pattern,
    MovementState movementState,
  ) {
    // STABILIZING일 때는 패널티 없음
    if (pattern == MotionPattern.STABILIZING) {
      return 0.0;
    }

    // 기본적으로 패턴 페널티는 없음 (필요시 확장 가능)
    return 0.0;
  }

  /// 운동 패턴에 따른 근육 가중치 반환
  /// 
  /// 동작 패턴에 따라 각 근육의 활성도 가중치를 반환합니다.
  /// 반환되는 키는 통합 근육명입니다 (예: 'quadriceps', 'glutes').
  /// 
  /// **가중치 정의:**
  /// - KNEE_DOMINANT: 무릎 우세 패턴에서 대퇴사두근 가중치 상승
  /// - HIP_DOMINANT: 고관절 우세 패턴에서 햄스트링과 둔근 가중치 상승
  /// - VERTICAL_PUSH/HORIZONTAL_PUSH: 밀기 동작에서 삼각근, 삼두근 가중치 상승
  /// - VERTICAL_PULL/HORIZONTAL_PULL: 당기기 동작에서 광배근, 이두근 가중치 상승
  static Map<String, double> _getMuscleWeights(
    MotionPattern pattern,
    String targetArea,
  ) {
    final weights = <String, double>{};

    // 하체 패턴
    if (pattern == MotionPattern.KNEE_DOMINANT) {
      weights['quadriceps'] = 1.2;
      weights['glutes'] = 0.8;
      weights['hamstrings'] = 0.3;
    } else if (pattern == MotionPattern.HIP_DOMINANT) {
      weights['hamstrings'] = 1.2;
      weights['glutes'] = 1.2;
      weights['quadriceps'] = 0.2;
    }

    // 상체 패턴
    if (pattern == MotionPattern.VERTICAL_PUSH) {
      weights['deltoids'] = 2.5; // 삼각근이 주동근
      weights['triceps'] = 1.5;
      weights['pectorals'] = 0.4;
      weights['trapezius'] = 0.6;
    } else if (pattern == MotionPattern.HORIZONTAL_PUSH) {
      weights['pectorals'] = 2.5; // 대흉근이 중력에 가장 크게 저항하는 주동근
      weights['triceps'] = 1.2;
      weights['deltoids'] = 0.8;
      weights['serratus'] = 0.6;
    } else if (pattern == MotionPattern.VERTICAL_PULL) {
      weights['latissimus'] = 2.5; // 광배근의 기여도 대폭 상향
      weights['biceps'] = 1.0;
      weights['trapezius'] = 0.8;
      weights['rhomboids'] = 0.7;
    } else if (pattern == MotionPattern.HORIZONTAL_PULL) {
      weights['trapezius'] = 2.0; // 등 상부 근육이 주동
      weights['rhomboids'] = 2.0;
      weights['latissimus'] = 1.5;
      weights['biceps'] = 1.2;
      weights['deltoids'] = 0.5;
    }

    // 기본값: 패턴이 감지되지 않았거나 다른 패턴인 경우
    if (weights.isEmpty) {
      // 타겟 부위에 따라 기본 가중치 설정
      if (targetArea.toUpperCase() == 'UPPER') {
        weights['deltoids'] = 1.0;
        weights['triceps'] = 1.0;
        weights['pectorals'] = 0.8;
        weights['latissimus'] = 0.8;
        weights['biceps'] = 0.8;
      } else if (targetArea.toUpperCase() == 'LOWER') {
        weights['quadriceps'] = 1.0;
        weights['glutes'] = 1.0;
        weights['hamstrings'] = 0.8;
      } else {
        // FULL: 모든 근육에 균등한 가중치
        weights['quadriceps'] = 1.0;
        weights['glutes'] = 1.0;
        weights['hamstrings'] = 1.0;
        weights['deltoids'] = 1.0;
        weights['triceps'] = 1.0;
        weights['pectorals'] = 1.0;
        weights['latissimus'] = 1.0;
        weights['biceps'] = 1.0;
      }
    }

    return weights;
  }

  /// 상체 누수 로직
  /// 
  /// - 승모근 누수 (Trap Leak): elevationFactor가 높을 때
  /// - 팔 누수 (Arm Dominance): retractionFactor가 낮을 때 (라운드 숄더)
  static Map<String, dynamic> _calculateUpperBodyLeaks({
    required double totalForce,
    required StabilityMetrics stability,
    required double effectiveForce,
    required double leakedEnergy,
    required MotionPattern pattern,
    required String targetArea,
    // ignore: unused_element
    bool isSideView = false, // [NEW] 측면 뷰 플래그 (확장성: 향후 팔꿈치 벌어짐 등 오판 방지 로직 추가 가능)
  }) {
    final effective = <String, double>{};
    final compensation = <String, double>{};
    final jointStress = <String, double>{};

    // TODO: 향후 상체 측면 오판 방지 로직 추가 시 isSideView 활용
    // 현재는 isSideView를 사용하지 않지만, 향후 확장을 위해 파라미터로 받아둠

    // 패턴 기반 가중치 가져오기
    final weights = _getMuscleWeights(pattern, targetArea);

    // 가중치 합계 계산
    final totalWeight = weights.values.fold(0.0, (sum, weight) => sum + weight);

    // 안전장치: 가중치가 없거나 합계가 0이면 기본 분배 사용
    if (totalWeight == 0.0 || weights.isEmpty) {
      // 기본 분배: 광배근과 가슴 근육에 균등 분배
      effective['latissimus'] = effectiveForce * 0.5;
      effective['pectorals'] = effectiveForce * 0.4;
    } else {
      // 가중치 비율로 effectiveForce 분배 (통합 근육명 사용)
      weights.forEach((muscle, weight) {
        effective[muscle] = effectiveForce * weight / totalWeight;
      });
    }

    // 승모근 누수 (Trap Leak)
    // elevationFactor가 높을 때 (으쓱할 때) 승모근으로 힘이 샘
    final trapLeak = totalForce * stability.elevationFactor * 1.5;
    compensation['trapezius'] = trapLeak;

    // 팔 누수 (Arm Dominance)
    // retractionFactor가 낮으면(라운드 숄더) 척추가 고정되지 않은 것임
    if (stability.retractionFactor < 0) {
      final armLeak = totalForce * 0.4; // 힘의 40%가 팔로 샜다고 가정

      compensation['biceps'] = armLeak * 0.3;
      compensation['triceps'] = armLeak * 0.2;

      // 등/가슴 점수 하락
      effective['latissimus'] = (effective['latissimus'] ?? 0) * 0.6;
      effective['pectorals'] = (effective['pectorals'] ?? 0) * 0.6;
    }

    // 순수 근육명만 반환 (좌우 분리는 MuscleMetricUtils에서 수행)
    return {
      'effective': effective,
      'compensation': compensation,
      'jointStress': jointStress,
    };
  }

  /// 하체 누수 로직
  /// 
  /// - 내전근 누수 (Adductor Leak via Valgus): valgusFactor가 높을 때
  /// - 대퇴사두 보상 (Quad Dominance via Poor Hinge): HIP_DOMINANT 패턴이어야 하는데 무릎이 앞으로 많이 밀릴 때
  static Map<String, dynamic> _calculateLowerBodyLeaks({
    required double totalForce,
    required StabilityMetrics stability,
    required MotionPattern pattern,
    required double effectiveForce,
    required double leakedEnergy,
    required String targetArea,
    bool isSideView = false, // [NEW] 측면 뷰 플래그
  }) {
    final effective = <String, double>{};
    final compensation = <String, double>{};
    final jointStress = <String, double>{};

    // 패턴 기반 가중치 가져오기
    final weights = _getMuscleWeights(pattern, targetArea);

    // 가중치 합계 계산
    final totalWeight = weights.values.fold(0.0, (sum, weight) => sum + weight);

    // 안전장치: 가중치가 없거나 합계가 0이면 기본 분배 사용
    if (totalWeight == 0.0 || weights.isEmpty) {
      // 기본 분배: 둔근과 햄스트링에 균등 분배
      effective['glutes'] = effectiveForce * 0.5;
      effective['hamstrings'] = effectiveForce * 0.3;
    } else {
      // 가중치 비율로 effectiveForce 분배 (통합 근육명 사용)
      weights.forEach((muscle, weight) {
        effective[muscle] = (effective[muscle] ?? 0.0) + effectiveForce * weight / totalWeight;
      });
    }

    // [NEW] 측면 뷰일 때는 Valgus 로직 비활성화
    // 내전근 누수 (Adductor Leak via Valgus)
    if (!isSideView && stability.valgusFactor > 0.0) {
      // 기존 Valgus 로직 유지
      final valgusLeak = totalForce * stability.valgusFactor * 2.0;

      // 무릎 관절 점수는 valgusLeak만큼 더해준다 (관절 스트레스 증가)
      jointStress['left_knee'] = valgusLeak * 0.5;
      jointStress['right_knee'] = valgusLeak * 0.5;

      // 둔근 점수는 valgusLeak만큼 뺀다 (힘이 내전근으로 샘)
      if (effective.containsKey('glutes')) {
        effective['glutes'] = (effective['glutes']! - valgusLeak * 0.5).clamp(0.0, double.infinity);
      }

      // 둔근 활성도가 낮은 상태(glutes < 0.3)에서 Valgus가 감지되면 내전근 점수에 1.5배 가중치 적용
      final glutesScore = effective['glutes'] ?? 0.0;
      if (glutesScore < 0.3) {
        final adductorScore = valgusLeak * 1.5;
        compensation['adductors'] = adductorScore;
      } else {
        final adductorScore = valgusLeak;
        compensation['adductors'] = adductorScore;
      }
    } else if (!isSideView) {
      // Valgus가 감지되지 않으면 내전근 점수 0.0
      compensation['adductors'] = 0.0;
    }
    // 측면 뷰일 때는 Valgus 로직을 완전히 스킵 (내전근 점수는 패턴 기반 가중치로만 계산)

    // 대퇴사두 보상 (Quad Dominance via Poor Hinge)
    // HIP_DOMINANT 패턴이어야 하는데 무릎이 앞으로 많이 밀리면(Knee Forward),
    // 둔근 힘이 대퇴사두로 이동
    if (pattern == MotionPattern.HIP_DOMINANT) {
      // 간단한 구현: 하체 에너지의 일부가 대퇴사두로 이동
      final quadDominance = leakedEnergy * 0.3;

      compensation['quadriceps'] = quadDominance;

      // 둔근 점수 하락
      if (effective.containsKey('glutes')) {
        effective['glutes'] = (effective['glutes']! - quadDominance * 0.5).clamp(0.0, double.infinity);
      }
    }

    // 음수 방지
    effective.forEach((key, value) {
      effective[key] = value.clamp(0.0, double.infinity);
    });

    // 순수 근육명만 반환 (좌우 분리는 MuscleMetricUtils에서 수행)
    return {
      'effective': effective,
      'compensation': compensation,
      'jointStress': jointStress,
    };
  }
}

