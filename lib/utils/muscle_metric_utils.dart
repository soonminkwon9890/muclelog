import 'dart:math' as math;
import '../models/analysis_log.dart';

/// 물리 기반 생체역학 엔진 (Physics-First Biomechanics Engine)
/// 운동 종목 이름을 사용하지 않고, 오직 비율, 변화량, 벡터 내적만으로 분석
class MuscleMetricUtils {
  /// 데이터 출력 보정 (NaN 방지 및 소수점 정확도)
  /// [value] 원본 값
  /// 반환: 보정된 값 (소수점 1자리)
  static double sanitizeOutput(double? value) {
    if (value == null || value.isNaN || value.isInfinite) {
      return 0.0;
    }
    return double.parse(value.toStringAsFixed(1));
  }

  /// 맵 전체에 대해 출력 보정 적용
  /// [data] 원본 데이터 맵
  /// 반환: 보정된 데이터 맵
  static Map<String, double> sanitizeOutputMap(Map<String, double>? data) {
    if (data == null) return {};
    final sanitized = <String, double>{};
    for (final entry in data.entries) {
      sanitized[entry.key] = sanitizeOutput(entry.value);
    }
    return sanitized;
  }

  // ============================================
  // Module 1: 전신 관절 기여도 분석 (Global Kinematics)
  // ============================================

  // ============================================
  // [수정됨] 전신 관절 기여도 분석 (순수 움직임 총량 비교)
  // ============================================
  /// 전신 관절 기여도 분석 (순수 움직임 총량 비교)
  /// [jointDeltas] 관절별 프레임 간 각도 변화량 절대값 맵
  /// 반환: {'ratios': Map, 'totalROM': double, 'regionDominance': String}
  static Map<String, dynamic> analyzeGlobalJointContribution(
    Map<String, double> jointDeltas,
  ) {
    // 1. 노이즈 필터링 (3도 미만 미세 떨림 무시)
    final filteredDeltas = <String, double>{};
    double totalROM = 0.0;

    for (final entry in jointDeltas.entries) {
      // 값이 3.0 이상일 때만 유의미한 움직임으로 간주
      if (entry.value.abs() > 3.0) {
        filteredDeltas[entry.key] = entry.value.abs();
        totalROM += entry.value.abs();
      }
    }

    if (totalROM == 0.0) {
      return {'regionDominance': 'UNKNOWN', 'ratios': <String, double>{}};
    }

    // 2. 부위별 누적 이동량 합산
    double lowerSum =
        (filteredDeltas['hip'] ?? 0) +
        (filteredDeltas['knee'] ?? 0) +
        (filteredDeltas['ankle'] ?? 0);
    double upperSum =
        (filteredDeltas['shoulder'] ?? 0) +
        (filteredDeltas['elbow'] ?? 0) +
        (filteredDeltas['wrist'] ?? 0);

    // 3. 지배적 부위 판별 (Pure Kinematics)
    // 특정 운동을 가정하지 않고, 단순히 "어디가 더 많이 움직였나"를 20% 격차로 판단
    String regionDominance = 'HYBRID';
    if (lowerSum > upperSum * 1.2) {
      regionDominance = 'LOWER_BODY';
    } else if (upperSum > lowerSum * 1.2) {
      regionDominance = 'UPPER_BODY';
    }

    // 4. 기여도 비율 계산
    final ratios = <String, double>{};
    filteredDeltas.forEach((key, value) {
      ratios[key] = value / totalROM;
    });

    return {
      'ratios': ratios,
      'totalROM': totalROM,
      'regionDominance': regionDominance,
    };
  }

  // ============================================
  // Module 2: 상체 역학 (Upper Body Physics)
  // ============================================

  /// 상완골 리듬 및 안정성 평가
  /// [prevPose] 이전 프레임 포즈
  /// [currPose] 현재 프레임 포즈
  /// 반환: {'rhythmRatio': double, 'elevationFailure': bool, 'protractionFailure': bool, 'penalty': double, 'trapeziusScore': double}
  static Map<String, dynamic> evaluateScapulohumeralRhythm({
    required dynamic prevPose,
    required dynamic currPose,
  }) {
    double rhythmRatio = 0.0;
    bool elevationFailure = false;
    bool protractionFailure = false;
    double penalty = 1.0;
    double trapeziusScore = 0.0;

    try {
      // Arm Abduction 계산 (팔의 상승 각도)
      final prevShoulder =
          prevPose.landmarks['leftShoulder'] ??
          prevPose.landmarks['rightShoulder'];
      final currShoulder =
          currPose.landmarks['leftShoulder'] ??
          currPose.landmarks['rightShoulder'];
      final prevElbow =
          prevPose.landmarks['leftElbow'] ?? prevPose.landmarks['rightElbow'];
      final currElbow =
          currPose.landmarks['leftElbow'] ?? currPose.landmarks['rightElbow'];
      final prevNose = prevPose.landmarks['nose'];
      final currNose = currPose.landmarks['nose'];

      if (prevShoulder != null &&
          currShoulder != null &&
          prevElbow != null &&
          currElbow != null &&
          prevNose != null &&
          currNose != null) {
        // Arm Abduction 변화량
        final prevArmVecX = prevElbow.x - prevShoulder.x;
        final prevArmVecY = prevElbow.y - prevShoulder.y;
        final currArmVecX = currElbow.x - currShoulder.x;
        final currArmVecY = currElbow.y - currShoulder.y;

        final prevArmAngle = math.atan2(prevArmVecY, prevArmVecX);
        final currArmAngle = math.atan2(currArmVecY, currArmVecX);
        final deltaArmAbduction =
            (currArmAngle - prevArmAngle).abs() * 180.0 / math.pi;

        // Shoulder Elevation 변화량 (Nose-Shoulder 거리)
        final prevNoseShoulderDist = math.sqrt(
          math.pow(prevNose.x - prevShoulder.x, 2) +
              math.pow(prevNose.y - prevShoulder.y, 2),
        );
        final currNoseShoulderDist = math.sqrt(
          math.pow(currNose.x - currShoulder.x, 2) +
              math.pow(currNose.y - currShoulder.y, 2),
        );
        final deltaShoulderElevation =
            (prevNoseShoulderDist - currNoseShoulderDist).abs();

        // Elevation Ratio 계산
        if (deltaArmAbduction > 0.1) {
          rhythmRatio = deltaShoulderElevation / deltaArmAbduction;

          // Threshold: 0.3 이상이면 보상작용
          if (rhythmRatio >= 0.3) {
            elevationFailure = true;
            // 승모근 점수 증가
            trapeziusScore = (rhythmRatio / 0.3 * 50.0).clamp(0.0, 100.0);
            // 주동근 점수 차감
            penalty = (1.0 - rhythmRatio * 2.0).clamp(0.0, 1.0);
          }
        }
      }

      // Protraction Vector 감지 (등 풀림)
      final currLeftShoulder = currPose.landmarks['leftShoulder'];
      final currRightShoulder = currPose.landmarks['rightShoulder'];
      final currLeftHip = currPose.landmarks['leftHip'];
      final currRightHip = currPose.landmarks['rightHip'];

      if (currLeftShoulder != null &&
          currRightShoulder != null &&
          currLeftHip != null &&
          currRightHip != null) {
        final shoulderMidZ = (currLeftShoulder.z + currRightShoulder.z) / 2;
        final hipMidZ = (currLeftHip.z + currRightHip.z) / 2;
        final sternumZ = (shoulderMidZ + hipMidZ) / 2.0;

        // Shoulder.z가 Sternum.z보다 앞으로 돌출
        if (shoulderMidZ < sternumZ - 0.02) {
          protractionFailure = true;
          penalty *= 0.5; // 추가 페널티
        }
      }
    } catch (e) {
      // 에러 처리
    }

    return {
      'rhythmRatio': rhythmRatio,
      'elevationFailure': elevationFailure,
      'protractionFailure': protractionFailure,
      'penalty': penalty,
      'trapeziusScore': trapeziusScore,
    };
  }

  /// 벡터 내적 기반 상체 패턴 분석
  /// [shoulderPoint] 어깨 좌표 {x, y, z}
  /// [elbowPoint] 팔꿈치 좌표 {x, y, z}
  /// [wristPoint] 손목 좌표 {x, y, z}
  /// [hipPoint] 골반 좌표 {x, y, z}
  /// 반환: {'pattern': 'PUSH'|'PULL'|'UNKNOWN', 'pectoralis': Map, 'lats': Map, 'deltoid': double, 'triceps': double, 'biceps': double}
  static Map<String, dynamic> analyzeUpperBodyVectorPattern({
    required Map<String, double> shoulderPoint,
    required Map<String, double> elbowPoint,
    required Map<String, double> wristPoint,
    required Map<String, double> hipPoint,
  }) {
    // Force Vector: Wrist - Shoulder
    final forceVecX = wristPoint['x']! - shoulderPoint['x']!;
    final forceVecY = wristPoint['y']! - shoulderPoint['y']!;
    final forceVecZ = wristPoint['z']! - shoulderPoint['z']!;

    // Torso Normal Vector (몸통 전면을 향하는 법선 벡터)
    // Hip에서 Shoulder로 향하는 벡터의 수직 벡터 (근사)
    final torsoVecX = shoulderPoint['x']! - hipPoint['x']!;
    final torsoVecY = shoulderPoint['y']! - hipPoint['y']!;
    final torsoVecZ = shoulderPoint['z']! - hipPoint['z']!;

    // Torso Normal Vector 계산 (외적을 통한 근사)
    final normalVecX = torsoVecY * forceVecZ - torsoVecZ * forceVecY;
    final normalVecY = torsoVecZ * forceVecX - torsoVecX * forceVecZ;
    final normalVecZ = torsoVecX * forceVecY - torsoVecY * forceVecX;

    // Dot Product 계산
    final dotProduct =
        forceVecX * normalVecX +
        forceVecY * normalVecY +
        forceVecZ * normalVecZ;

    String pattern = 'UNKNOWN';
    final pectoralisScores = <String, double>{
      'upper': 0.0,
      'sternal': 0.0,
      'costal': 0.0,
    };
    final latsScores = <String, double>{
      'dynamicPull': 0.0,
      'staticTension': 0.0,
    };
    double deltoidScore = 0.0;
    double tricepsScore = 0.0;
    double bicepsScore = 0.0;

    // Push Pattern: Dot Product > 0 (몸통 밖으로 힘이 나감)
    if (dotProduct > 0) {
      pattern = 'PUSH';

      // Pectoralis Mapping
      final elbowY = elbowPoint['y']!;
      final shoulderY = shoulderPoint['y']!;
      final yDiff = (elbowY - shoulderY).abs();

      // Upper (Clavicular): Elbow가 Shoulder보다 높음
      if (elbowY < shoulderY) {
        // 벡터가 상방 내측
        final armElevation =
            math.atan2(
              shoulderY - elbowY,
              (elbowPoint['x']! - shoulderPoint['x']!).abs(),
            ) *
            180.0 /
            math.pi;

        if (armElevation >= 30.0 && armElevation <= 60.0) {
          final normalized = (armElevation - 30.0) / 30.0;
          pectoralisScores['upper'] =
              (1.0 - (normalized - 0.5).abs() * 2.0) * 100.0;
        }
      }
      // Mid (Sternal): Elbow와 Shoulder 높이가 비슷
      else if (yDiff < 0.05) {
        // 수평 내전: 팔이 몸통 중심선에 가까워질수록 기하급수적 상승
        final sternumX = shoulderPoint['x']!;
        final elbowX = elbowPoint['x']!;
        final horizontalAdduction = (sternumX - elbowX).abs();

        pectoralisScores['sternal'] =
            math.exp(-horizontalAdduction * 10.0) * 100.0;
      }
      // Lower (Costal): Elbow가 Shoulder보다 낮음
      else if (elbowY > shoulderY) {
        // 하방(Depression) 벡터
        final shoulderDepression = shoulderY - elbowY;
        if (shoulderDepression > 0.0) {
          pectoralisScores['costal'] = (shoulderDepression * 50.0).clamp(
            0.0,
            100.0,
          );
        }
      }

      // 삼두근 점수 (Elbow Extension)
      final elbowAngle = _calculateElbowAngle(
        shoulderPoint,
        elbowPoint,
        wristPoint,
      );
      if (elbowAngle < 160.0) {
        tricepsScore = ((160.0 - elbowAngle) / 90.0 * 100.0).clamp(0.0, 100.0);
      }

      // 전면 삼각근 점수
      deltoidScore = (dotProduct * 50.0).clamp(0.0, 100.0);
    }
    // Pull Pattern: Dot Product < 0 (몸통 쪽으로 힘이 들어옴)
    else if (dotProduct < 0) {
      pattern = 'PULL';

      // Lats Scoring
      // 동적 당기기: Elbow가 몸통 뒤로 넘어가는 깊이
      final shoulderX = shoulderPoint['x']!;
      final elbowX = elbowPoint['x']!;
      final retractionDepth = (shoulderX - elbowX).abs();

      if (retractionDepth > 0.0) {
        latsScores['dynamicPull'] = (retractionDepth * 100.0).clamp(0.0, 100.0);
      }

      // 정적 텐션: 팔이 펴진 상태에서 Arm과 Torso 사이 각도
      final elbowAngle = _calculateElbowAngle(
        shoulderPoint,
        elbowPoint,
        wristPoint,
      );
      if (elbowAngle > 160.0) {
        // Arm-Torso Angle 계산
        final armVecX = elbowPoint['x']! - shoulderPoint['x']!;
        final armVecY = elbowPoint['y']! - shoulderPoint['y']!;
        final torsoVecX = hipPoint['x']! - shoulderPoint['x']!;
        final torsoVecY = hipPoint['y']! - shoulderPoint['y']!;

        final armTorsoAngle = _calculateVectorAngle2D(
          armVecX,
          armVecY,
          torsoVecX,
          torsoVecY,
        );

        // 각도가 0도에 수렴할수록 100점
        if (armTorsoAngle <= 15.0) {
          latsScores['staticTension'] = (1.0 - armTorsoAngle / 15.0) * 100.0;
        }
      }

      // 이두근 점수 (Elbow Flexion)
      if (elbowAngle < 160.0) {
        bicepsScore = ((160.0 - elbowAngle) / 90.0 * 100.0).clamp(0.0, 100.0);
      }

      // 후면 삼각근 점수
      deltoidScore = (dotProduct.abs() * 50.0).clamp(0.0, 100.0);
    }

    return {
      'pattern': pattern,
      'pectoralis': pectoralisScores,
      'lats': latsScores,
      'deltoid': deltoidScore,
      'triceps': tricepsScore,
      'biceps': bicepsScore,
    };
  }

  // ============================================
  // Module 3: 하체 역학 (Lower Body Physics)
  // ============================================

  /// 하체 역학 분석: 모멘트 비율 & 중력
  /// [prevPose] 이전 프레임 포즈
  /// [currPose] 현재 프레임 포즈
  /// [jointRatios] 관절 기여도 비율 맵
  /// 반환: {'quadScore': double, 'gluteScore': double, 'hamstringScore': double, 'isAntiGravity': bool, 'eccentricMultiplier': double}
  static Map<String, dynamic> analyzeLowerBodyMechanics({
    required dynamic prevPose,
    required dynamic currPose,
    required Map<String, double> jointRatios,
  }) {
    double quadScore = 0.0;
    double gluteScore = 0.0;
    double hamstringScore = 0.0;
    bool isAntiGravity = false;
    double eccentricMultiplier = 1.0;

    try {
      // 관절 모멘트 상대성 평가
      final kneeRatio = jointRatios['knee'] ?? 0.0;
      final hipRatio = jointRatios['hip'] ?? 0.0;

      // Joint Ratio 계산
      final jointRatio = hipRatio > 0 ? kneeRatio / hipRatio : 0.0;

      // 중력 대항 여부 확인
      final prevHip =
          prevPose.landmarks['leftHip'] ?? prevPose.landmarks['rightHip'];
      final currHip =
          currPose.landmarks['leftHip'] ?? currPose.landmarks['rightHip'];

      if (prevHip != null && currHip != null) {
        // Y축 상승 여부 (중력 대항)
        isAntiGravity = currHip.y < prevHip.y;

        if (!isAntiGravity) {
          // 신장성 수축 (Eccentric): 점수 50% 반영
          eccentricMultiplier = 0.5;
        } else {
          // 단축성 수축 (Concentric): 점수 120% 가중치
          eccentricMultiplier = 1.2;
        }
      }

      // Knee Dominant Logic (대퇴사두근 주도)
      // Condition: Joint_Ratio > 1.2 (무릎이 고관절보다 1.2배 이상 더 움직임)
      if (jointRatio > 1.2) {
        final prevKnee =
            prevPose.landmarks['leftKnee'] ?? prevPose.landmarks['rightKnee'];
        final currKnee =
            currPose.landmarks['leftKnee'] ?? currPose.landmarks['rightKnee'];
        final prevAnkle =
            prevPose.landmarks['leftAnkle'] ?? prevPose.landmarks['rightAnkle'];
        final currAnkle =
            currPose.landmarks['leftAnkle'] ?? currPose.landmarks['rightAnkle'];

        if (prevKnee != null &&
            currKnee != null &&
            prevAnkle != null &&
            currAnkle != null) {
          // Knee Flexion 각도 계산 (모멘트 암)
          final kneeFlexion =
              math.atan2(
                (currKnee.y - currAnkle.y).abs(),
                (currKnee.x - currAnkle.x).abs(),
              ) *
              180.0 /
              math.pi;

          quadScore = (kneeFlexion / 90.0 * 100.0).clamp(0.0, 100.0);
        }
      }

      // Hip Dominant Logic (둔근/햄스트링 주도)
      // Condition: Joint_Ratio < 0.8 (고관절이 무릎보다 더 많이 움직임)
      if (jointRatio < 0.8 && jointRatio > 0.0) {
        final shoulder =
            currPose.landmarks['leftShoulder'] ??
            currPose.landmarks['rightShoulder'];
        final hip =
            currPose.landmarks['leftHip'] ?? currPose.landmarks['rightHip'];

        if (shoulder != null && hip != null) {
          // Torso Inclination 계산 (상체 기울기)
          final torsoInclination =
              math.atan2(
                (shoulder.y - hip.y).abs(),
                (shoulder.x - hip.x).abs(),
              ) *
              180.0 /
              math.pi;

          gluteScore = (torsoInclination / 45.0 * 100.0).clamp(0.0, 100.0);
          hamstringScore = gluteScore * 0.6; // 햄스트링은 둔근의 60%
        }
      }

      // 강성(Stiffness) 평가 (For Isometric Hinge)
      // Condition: Lower_Share > 0.6 이지만 Total_ROM이 매우 작음
      // Note: totalROM은 jointRatios의 합으로 근사 (실제로는 jointDeltas에서 계산되어야 함)
      final totalRatioSum = jointRatios.values.fold<double>(
        0.0,
        (sum, ratio) => sum + ratio,
      );

      if (totalRatioSum < 0.1) {
        // 정적 상태: Spine Angle 중립 유지 확인
        final shoulder =
            currPose.landmarks['leftShoulder'] ??
            currPose.landmarks['rightShoulder'];
        final hip =
            currPose.landmarks['leftHip'] ?? currPose.landmarks['rightHip'];

        if (shoulder != null && hip != null) {
          final spineAngle =
              math.atan2(
                (shoulder.y - hip.y).abs(),
                (shoulder.x - hip.x).abs(),
              ) *
              180.0 /
              math.pi;

          // 중립 상태 (약 90도)에 가까우면 코어/기립근 점수 부여
          final neutralDeviation = (spineAngle - 90.0).abs();
          if (neutralDeviation < 10.0) {
            // Time Under Tension에 따라 점수 부여 (여기서는 간단히 계산)
            gluteScore = (1.0 - neutralDeviation / 10.0) * 100.0;
          }
        }
      }
    } catch (e) {
      // 에러 처리
    }

    return {
      'quadScore': quadScore * eccentricMultiplier,
      'gluteScore': gluteScore * eccentricMultiplier,
      'hamstringScore': hamstringScore * eccentricMultiplier,
      'isAntiGravity': isAntiGravity,
      'eccentricMultiplier': eccentricMultiplier,
    };
  }

  // ============================================
  // Module 4: 척추 안전성 (Safety Veto - 3 Point Analysis)
  // ============================================

  /// 척추 안전성 평가 (3-Point Analysis)
  /// [shoulderPoint] 어깨 좌표 {x, y, z}
  /// [hipPoint] 골반 좌표 {x, y, z}
  /// [kneePoint] 무릎 좌표 {x, y, z}
  /// 반환: {'angle': double, 'compensation': 'none'|'flexion'|'hyperExtension', 'erectorScore': double, 'riskLevel': double, 'veto': bool}
  static Map<String, dynamic> evaluateSpinalSafety({
    required Map<String, double> shoulderPoint,
    required Map<String, double> hipPoint,
    required Map<String, double> kneePoint,
  }) {
    // Vector 1: Shoulder -> Hip
    final vec1X = hipPoint['x']! - shoulderPoint['x']!;
    final vec1Y = hipPoint['y']! - shoulderPoint['y']!;

    // Vector 2: Hip -> Knee
    final vec2X = kneePoint['x']! - hipPoint['x']!;
    final vec2Y = kneePoint['y']! - hipPoint['y']!;

    // 두 벡터 사이의 사잇각 계산
    final angle = _calculateVectorAngle2D(vec1X, vec1Y, vec2X, vec2Y);

    String compensation = 'none';
    double erectorScore = 100.0;
    double riskLevel = 0.0;
    bool veto = false;

    // Neutral: 170° ~ 190°
    if (angle >= 170.0 && angle <= 190.0) {
      compensation = 'none';
      erectorScore = 100.0;
      riskLevel = 0.0;
      veto = false;
    }
    // Flexion (말림): < 165°
    else if (angle < 165.0) {
      compensation = 'flexion';
      erectorScore = 0.0; // 기립근 텐션 점수 즉시 0점 처리
      riskLevel = (165.0 - angle) / 15.0; // 위험도 계산
      veto = true; // 운동 무효화
    }
    // Hyper-Extension (과신전): > 200°
    else if (angle > 200.0) {
      compensation = 'hyperExtension';
      erectorScore = 50.0; // 부분 감점
      riskLevel = (angle - 200.0) / 20.0; // 위험도 계산
      veto = false; // 경고만
    }

    return {
      'angle': angle,
      'compensation': compensation,
      'erectorScore': erectorScore,
      'riskLevel': riskLevel.clamp(0.0, 1.0),
      'veto': veto,
    };
  }

  // ============================================
  // Module 5: 동적 관절 가중치 (Dynamic Joint Scoring)
  // ============================================

  /// 동적 관절 점수 계산
  /// [jointKey] 관절 키
  /// [rawAngle] 원본 각도 값
  /// [jointContributionRatio] 관절 기여도 비율 (0.0 ~ 1.0)
  /// [referenceROM] 참조 ROM 각도 (기본값 180)
  /// 반환: 가중치가 적용된 관절 점수 (0.0 ~ 100.0)
  static double calculateDynamicJointScore({
    required String jointKey,
    required double rawAngle,
    required double jointContributionRatio,
    double referenceROM = 180.0,
  }) {
    // Noise Filter: 5% 미만은 비활성 관절로 간주
    if (jointContributionRatio < 0.05) {
      return 0.0;
    }

    // Quality Score 계산 (Raw Angle 기반)
    final qualityScore = (rawAngle / referenceROM * 100.0).clamp(0.0, 100.0);

    // 동적 가중치 적용: Contribution Ratio를 가중치로 사용
    final finalScore =
        qualityScore * jointContributionRatio * 2.0; // Scale factor

    return finalScore.clamp(0.0, 100.0);
  }

  // ============================================
  // 통합 분석 엔진 (Integrated Analysis Engine)
  // ============================================

  // ============================================
  // [수정됨] 통합 분석 엔진 (참조 ROM 기반 점수화)
  // ============================================
  /// 통합 물리 기반 분석 (참조 ROM 기반 점수화)
  /// [prevPose] 이전 프레임 포즈
  /// [currPose] 현재 프레임 포즈
  /// [jointDeltas] 관절별 각도 변화량 맵
  /// 반환: {'detailed_muscle_usage': Map, 'rom_data': Map, 'biomech_pattern': String}
  static Map<String, dynamic> performPhysicsBasedAnalysis({
    required dynamic prevPose,
    required dynamic currPose,
    required Map<String, double> jointDeltas,
  }) {
    final muscleUsage = <String, double>{};

    // 1. 기여도 및 부위 판별
    final globalAnalysis = analyzeGlobalJointContribution(jointDeltas);
    final regionDominance = globalAnalysis['regionDominance'] as String;

    // 2. 관절별 움직임 데이터 추출 (절대값)
    double kneeROM = jointDeltas['knee']?.abs() ?? 0.0;
    double hipROM = jointDeltas['hip']?.abs() ?? 0.0;

    double shoulderROM = jointDeltas['shoulder']?.abs() ?? 0.0;
    double elbowROM = jointDeltas['elbow']?.abs() ?? 0.0;

    // 3. 순수 역학 기반 점수 계산 (Raw Kinematic Score)
    // 공식: (실제 움직인 각도 / 해당 관절의 기준 가동범위) * 100
    // 기준 가동범위: 무릎(~130도), 고관절(~100도), 어깨(~120도), 팔꿈치(~140도)

    // [하체 근육 매핑]
    // 대퇴사두근: 무릎이 펴지거나 굽혀질 때 활성화
    double quadScore = (kneeROM / 130.0 * 100.0).clamp(0.0, 100.0);
    // 둔근: 고관절이 움직일 때 활성화
    double gluteScore = (hipROM / 100.0 * 100.0).clamp(0.0, 100.0);
    // 햄스트링: 고관절과 무릎이 동시에 관여 (보조)
    double hamScore = ((hipROM * 0.6 + kneeROM * 0.4) / 110.0 * 100.0).clamp(
      0.0,
      100.0,
    );

    // [상체 근육 매핑]
    // 삼각근/광배근: 어깨 관절 움직임 기반
    double shoulderMuscleScore = (shoulderROM / 120.0 * 100.0).clamp(
      0.0,
      100.0,
    );
    // 이두/삼두: 팔꿈치 관절 움직임 기반
    double armMuscleScore = (elbowROM / 140.0 * 100.0).clamp(0.0, 100.0);

    // 4. 부위별 가중치 적용 (Isolation Logic)
    // 많이 움직인 부위는 점수 유지/증폭, 적게 움직인 부위는 노이즈로 간주하여 억제
    if (regionDominance == 'LOWER_BODY') {
      // 하체 집중: 상체 근육 점수를 30%로 억제, 하체 근육 1.5배 증폭
      muscleUsage['quadriceps'] = (quadScore * 1.5).clamp(0.0, 100.0);
      muscleUsage['glutes'] = (gluteScore * 1.5).clamp(0.0, 100.0);
      muscleUsage['hamstrings'] = hamScore;

      muscleUsage['latissimus_dorsi'] = shoulderMuscleScore * 0.3;
      muscleUsage['deltoid'] = shoulderMuscleScore * 0.3;
      muscleUsage['biceps'] = armMuscleScore * 0.3;
      muscleUsage['triceps'] = armMuscleScore * 0.3;
    } else if (regionDominance == 'UPPER_BODY') {
      // 상체 집중: 하체 근육 점수를 30%로 억제, 상체 근육 1.1-1.5배 증폭
      muscleUsage['latissimus_dorsi'] = (shoulderMuscleScore * 1.1).clamp(
        0.0,
        100.0,
      );
      muscleUsage['deltoid'] = (shoulderMuscleScore * 1.5).clamp(0.0, 100.0);
      muscleUsage['biceps'] = (armMuscleScore * 1.5).clamp(0.0, 100.0);
      muscleUsage['triceps'] = (armMuscleScore * 1.5).clamp(0.0, 100.0);

      muscleUsage['quadriceps'] = quadScore * 0.3;
      muscleUsage['glutes'] = gluteScore * 0.3;
      muscleUsage['hamstrings'] = hamScore * 0.3;
    } else {
      // 전신 운동 (Hybrid): 억제 없이 그대로 반영
      muscleUsage['quadriceps'] = quadScore;
      muscleUsage['glutes'] = gluteScore;
      muscleUsage['hamstrings'] = hamScore;
      muscleUsage['latissimus_dorsi'] = shoulderMuscleScore;
      muscleUsage['deltoid'] = shoulderMuscleScore;
      muscleUsage['biceps'] = armMuscleScore;
      muscleUsage['triceps'] = armMuscleScore;
    }

    // 5. 결과 정렬 (점수 높은 순서대로 내림차순)
    // 의미 없는(0점에 가까운) 근육은 하단으로 밀려남
    var sortedEntries = muscleUsage.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final sortedMuscleUsage = Map.fromEntries(sortedEntries);

    return {
      'detailed_muscle_usage': sanitizeOutputMap(sortedMuscleUsage),
      'biomech_pattern': regionDominance,
      'rom_data': sanitizeOutputMap(jointDeltas),
    };
  }

  // ============================================
  // 헬퍼 함수들 (Helper Functions)
  // ============================================

  /// 2D 벡터 각도 계산
  static double _calculateVectorAngle2D(
    double vec1X,
    double vec1Y,
    double vec2X,
    double vec2Y,
  ) {
    final dot = vec1X * vec2X + vec1Y * vec2Y;
    final mag1 = math.sqrt(vec1X * vec1X + vec1Y * vec1Y);
    final mag2 = math.sqrt(vec2X * vec2X + vec2Y * vec2Y);

    if (mag1 == 0.0 || mag2 == 0.0) return 0.0;

    final cosAngle = dot / (mag1 * mag2);
    final clampedCos = cosAngle.clamp(-1.0, 1.0);
    return math.acos(clampedCos) * 180.0 / math.pi;
  }

  /// 팔꿈치 각도 계산
  static double _calculateElbowAngle(
    Map<String, double> shoulderPoint,
    Map<String, double> elbowPoint,
    Map<String, double> wristPoint,
  ) {
    // Vector 1: Shoulder -> Elbow
    final vec1X = elbowPoint['x']! - shoulderPoint['x']!;
    final vec1Y = elbowPoint['y']! - shoulderPoint['y']!;

    // Vector 2: Elbow -> Wrist
    final vec2X = wristPoint['x']! - elbowPoint['x']!;
    final vec2Y = wristPoint['y']! - elbowPoint['y']!;

    return _calculateVectorAngle2D(vec1X, vec1Y, vec2X, vec2Y);
  }

  // ============================================
  // 하위 호환성 유지 (Legacy Support)
  // ============================================

  /// 운동 타입별 근육 이름 반환 (하위 호환성)
  static String getMuscleName(ExerciseType exerciseType, String jointName) {
    const mapping = {
      'neck': '승모근',
      'spine': '기립근/코어',
      'shoulder': '삼각근',
      'elbow': '상완이두근',
      'wrist': '전완근',
      'hip': '둔근',
      'knee': '대퇴사두근',
      'ankle': '비복근',
    };

    return mapping[jointName.toLowerCase()] ?? jointName;
  }

  /// 중력 벡터 각도 계산 (하위 호환성)
  static double calculateGravityVectorAngle(
    Map<String, double> refGravity,
    Map<String, double> currGravity,
  ) {
    // 내적(Dot Product) 계산
    final dot =
        refGravity['x']! * currGravity['x']! +
        refGravity['y']! * currGravity['y']! +
        refGravity['z']! * currGravity['z']!;

    // 벡터 크기(Magnitude) 계산
    final magRef = math.sqrt(
      refGravity['x']! * refGravity['x']! +
          refGravity['y']! * refGravity['y']! +
          refGravity['z']! * refGravity['z']!,
    );
    final magCurr = math.sqrt(
      currGravity['x']! * currGravity['x']! +
          currGravity['y']! * currGravity['y']! +
          currGravity['z']! * currGravity['z']!,
    );

    if (magRef == 0.0 || magCurr == 0.0) return 0.0;

    // 각도 계산 (라디안 → 도)
    final cosAngle = dot / (magRef * magCurr);
    final clampedCos = cosAngle.clamp(-1.0, 1.0);
    return math.acos(clampedCos) * 180.0 / math.pi;
  }

  /// 포즈에서 중력 벡터 추정 (하위 호환성)
  static Map<String, double>? estimateGravityVectorFromPose(
    dynamic pose,
    dynamic leftShoulder,
    dynamic rightShoulder,
    dynamic leftHip,
    dynamic rightHip,
  ) {
    try {
      if (leftShoulder == null ||
          rightShoulder == null ||
          leftHip == null ||
          rightHip == null) {
        return null;
      }

      // 신뢰도 체크
      if (leftShoulder.likelihood < 0.5 ||
          rightShoulder.likelihood < 0.5 ||
          leftHip.likelihood < 0.5 ||
          rightHip.likelihood < 0.5) {
        return null;
      }

      // 중점 계산
      final shoulderMidX = (leftShoulder.x + rightShoulder.x) / 2;
      final shoulderMidY = (leftShoulder.y + rightShoulder.y) / 2;
      final shoulderMidZ = (leftShoulder.z + rightShoulder.z) / 2;

      final hipMidX = (leftHip.x + rightHip.x) / 2;
      final hipMidY = (leftHip.y + rightHip.y) / 2;
      final hipMidZ = (leftHip.z + rightHip.z) / 2;

      // 척추 벡터 (골반 → 어깨)
      final spineVecX = shoulderMidX - hipMidX;
      final spineVecY = shoulderMidY - hipMidY;
      final spineVecZ = shoulderMidZ - hipMidZ;

      // 벡터 크기
      final magnitude = math.sqrt(
        spineVecX * spineVecX + spineVecY * spineVecY + spineVecZ * spineVecZ,
      );

      if (magnitude == 0.0) return null;

      // 정규화된 벡터 반환
      return {
        'x': spineVecX / magnitude,
        'y': spineVecY / magnitude,
        'z': spineVecZ / magnitude,
      };
    } catch (e) {
      return null;
    }
  }

  /// 떨림(Jitter) 수치 계산 (하위 호환성)
  static double calculateJitter(List<double> angleDeviations) {
    if (angleDeviations.isEmpty) return 0.0;
    if (angleDeviations.length == 1) return 0.0;

    // 평균 계산
    final mean =
        angleDeviations.reduce((a, b) => a + b) / angleDeviations.length;

    // 분산 계산
    final variance =
        angleDeviations
            .map((dev) => math.pow(dev - mean, 2))
            .reduce((a, b) => a + b) /
        angleDeviations.length;

    // 표준편차 반환
    return math.sqrt(variance);
  }

  /// 속도 표준편차 계산 (하위 호환성)
  static double calculateVelocityStandardDeviation(
    List<double> velocityValues,
  ) {
    if (velocityValues.isEmpty) return 0.0;
    if (velocityValues.length == 1) return 0.0;

    // 평균 계산
    final mean = velocityValues.reduce((a, b) => a + b) / velocityValues.length;

    // 분산 계산
    final variance =
        velocityValues
            .map((v) => math.pow(v - mean, 2))
            .reduce((a, b) => a + b) /
        velocityValues.length;

    // 표준편차 반환
    return math.sqrt(variance);
  }

  /// 속도 변동률 계산 (하위 호환성)
  static double calculateVelocityVariationCoefficient(
    List<double> velocityValues,
  ) {
    if (velocityValues.isEmpty) return 0.0;

    final mean = velocityValues.reduce((a, b) => a + b) / velocityValues.length;
    if (mean == 0.0) return 0.0;

    final stdDev = calculateVelocityStandardDeviation(velocityValues);

    // 변동계수(CV) = 표준편차 / 평균 * 100
    return (stdDev / mean) * 100.0;
  }

  /// 가상 견갑골 회전량 계산 (하위 호환성)
  static double calculateVirtualScapulaRotation(double armElevation) {
    return (armElevation - 30.0) / 2.0;
  }

  /// 운동 컨텍스트 자동 판단 (하위 호환성)
  /// [jointROMs] 관절별 ROM 맵 {'hip': 45.0, 'elbow': 10.0, ...}
  /// [shoulderExtension] 어깨 신전 각도 (도 단위, null 가능)
  /// [elbowExtension] 팔꿈치 신전 각도 (도 단위, null 가능)
  /// 반환: 'STATE_HINGE', 'STATE_PULL', 'STATE_PUSH', 또는 null
  static String? detectExerciseContext({
    required Map<String, double> jointROMs,
    double? shoulderExtension,
    double? elbowExtension,
  }) {
    final hipROM = jointROMs['hip'] ?? 0.0;
    final kneeROM = jointROMs['knee'] ?? 0.0;
    final elbowROM = jointROMs['elbow'] ?? 0.0;

    // 비율 기반 판단
    final kneeHipRatio = hipROM > 0 ? kneeROM / hipROM : 0.0;

    // Hip Dominant (힌지 패턴): 고관절이 무릎보다 많이 움직임
    if (kneeHipRatio < 0.8 && hipROM > 40.0 && elbowROM < 15.0) {
      return 'STATE_HINGE';
    }

    // Knee Dominant (스쿼트 패턴): 무릎이 고관절보다 많이 움직임
    if (kneeHipRatio > 1.2 && kneeROM > 30.0) {
      return 'STATE_SQUAT';
    }

    // Pull Pattern: Elbow ROM이 크고 Shoulder Extension 존재
    if (elbowROM > 40.0 &&
        shoulderExtension != null &&
        shoulderExtension > 5.0) {
      return 'STATE_PULL';
    }

    // Push Pattern: Elbow Extension 주도
    if (elbowExtension != null && elbowExtension > 5.0) {
      return 'STATE_PUSH';
    }

    return null;
  }

  /// 근육 점수 계산 (하위 호환성)
  /// [muscleKey] 근육 키 (예: 'lats', 'erector_spinae')
  /// [context] 운동 컨텍스트 ('STATE_HINGE', 'STATE_PULL', 'STATE_PUSH')
  /// [angleChange] 각도 변화량 (도 단위, Hinge에서는 변화가 적을수록 고득점)
  /// [maxROM] 최대 가동범위 (도 단위, Pull/Push에서 사용)
  /// [currentROM] 현재 가동범위 (도 단위, Pull/Push에서 사용)
  /// [spineAngleChange] 척추 각도 변화량 (도 단위, Erectors 점수 계산용)
  /// 반환: 근육 활성도 점수 (0.0 ~ 100.0)
  static double calculateMuscleScore({
    required String muscleKey,
    required String? context,
    double? angleChange,
    double? maxROM,
    double? currentROM,
    double? spineAngleChange,
  }) {
    final lowerKey = muscleKey.toLowerCase();

    // Scenario A: IsHinge (버티기)
    if (context == 'STATE_HINGE') {
      // 광배근(Lats): 각도 변화가 없을수록 고득점
      if (lowerKey.contains('lats') || lowerKey.contains('lat')) {
        if (angleChange == null) return 0.0;
        // 변화량이 적을수록 높은 점수 (역비례)
        // 변화량 0도 = 100점, 변화량 20도 이상 = 0점
        final stabilityScore =
            (1.0 - (angleChange / 20.0).clamp(0.0, 1.0)) * 100.0;
        return stabilityScore.clamp(0.0, 100.0);
      }

      // 기립근(Erectors): 척추 각도 변화가 적을수록 고득점
      if (lowerKey.contains('erector') || lowerKey.contains('spine')) {
        if (spineAngleChange == null) return 0.0;
        // 변화량이 적을수록 높은 점수
        // 변화량 0도 = 100점, 변화량 15도 이상 = 0점 (말리면 0점)
        final rigidityScore =
            (1.0 - (spineAngleChange / 15.0).clamp(0.0, 1.0)) * 100.0;
        return rigidityScore.clamp(0.0, 100.0);
      }

      // 기타 근육: 기본 점수
      return angleChange != null
          ? (angleChange / 10.0 * 50.0).clamp(0.0, 100.0)
          : 0.0;
    }

    // Scenario B: IsPull/Push (당기기/밀기)
    if (context == 'STATE_PULL' || context == 'STATE_PUSH') {
      // 삼각근/광배근: ROM 기반 점수
      if (lowerKey.contains('deltoid') ||
          lowerKey.contains('lats') ||
          lowerKey.contains('lat')) {
        if (maxROM == null || maxROM == 0.0 || currentROM == null) {
          return 0.0;
        }
        // Current_ROM / Max_Possible_ROM
        final romScore = (currentROM / maxROM * 100.0).clamp(0.0, 100.0);
        return romScore;
      }

      // 승모근: 어깨 으쓱(Elevation) 페널티 적용
      if (lowerKey.contains('trapezius') || lowerKey.contains('traps')) {
        // Pull/Push에서 어깨가 으쓱하면 주동근 점수 차감 -> 승모근 점수로 이관
        // 여기서는 기본 ROM 기반 점수
        if (maxROM == null || maxROM == 0.0 || currentROM == null) {
          return 0.0;
        }
        return (currentROM / maxROM * 100.0).clamp(0.0, 100.0);
      }

      // 기타 근육: ROM 기반 점수
      if (maxROM != null && maxROM > 0.0 && currentROM != null) {
        return (currentROM / maxROM * 100.0).clamp(0.0, 100.0);
      }
    }

    // 기본 점수 (컨텍스트 없음)
    return angleChange != null
        ? (angleChange / 10.0 * 50.0).clamp(0.0, 100.0)
        : 0.0;
  }

  // ============================================
  // 계층형 하이브리드 계산 모델 (Layered Hybrid Calculation Model)
  // ============================================

  /// 계층형 하이브리드 근육 활성도 계산
  /// Step 1: 기초 운동학 레이어 (Base Kinematics Layer)
  /// Step 2: 정밀 역학 레이어 (Precision Biomechanics Layer)
  /// Step 3: 최종 정규화 (Final Normalization)
  ///
  /// [muscleKey] 근육 키 (예: 'lats', 'pectoralis', 'quadriceps')
  /// [deltaAngle] 프레임 간 관절 각도 변화량 (도 단위)
  /// [timeDelta] 프레임 간 시간 차이 (초 단위, 기본값 0.033초 = 30fps)
  /// [rom] 가동범위 (도 단위)
  /// [isEccentric] 신장성 수축 여부
  /// [gravityVector] 중력 벡터 데이터 {'isAntiGravity': bool, 'eccentricMultiplier': double}
  /// [momentArmLength] 모멘트 암 길이 (정규화된 값, 0.0~1.0)
  /// [lumbarCompensation] 요추 보상작용 감지 여부
  /// [motionType] 운동 방식 ('isotonic', 'isometric', 'isokinetic')
  /// 반환: 최종 활성도 점수 (0.0 ~ 100.0, 절대 0.0%가 나오지 않음)
  static double calculateLayeredActivation({
    required String muscleKey,
    double? deltaAngle,
    double timeDelta = 0.033, // 30fps 기준
    double? rom,
    bool isEccentric = false,
    Map<String, dynamic>? gravityVector,
    double? momentArmLength,
    bool lumbarCompensation = false,
    String? motionType,
  }) {
    // ============================================
    // Step 1: 기초 운동학 레이어 (Base Kinematics Layer)
    // 🔧 저프레임 보정: ROM 점수 비중 강화 (30% -> 60%)
    // ============================================
    double baseScore = 0.0;
    double romScore = 0.0;
    double velocityScore = 0.0;

    // 🔧 1. ROM 점수 계산 (우선순위 높음, 저프레임에서도 정확)
    if (rom != null && rom > 5.0) {
      // ROM 기반 점수: 가동 범위가 크면 근육을 많이 쓴 것으로 간주
      // 비중 60%: (rom / 180.0 * 60.0) -> 최대 60점
      romScore = (rom / 180.0 * 60.0).clamp(0.0, 60.0);
    }

    // 🔧 2. 속도 점수 계산 (보조 지표, 비중 40%)
    if (deltaAngle != null && deltaAngle.abs() > 0.1) {
      // Angular Velocity 계산: (DeltaAngle / Time) * Weight
      final angularVelocity = (deltaAngle.abs() / timeDelta);
      final weight = 1.0; // 기본 가중치
      // 비중 40%: 최대 40점
      velocityScore = (angularVelocity * weight * 0.4).clamp(0.0, 40.0);
    }

    // 🔧 3. 최종 baseScore: ROM 60% + 속도 40% (저프레임 보정)
    if (romScore > 0.0 || velocityScore > 0.0) {
      baseScore = romScore + velocityScore;
      // 최소 10% 보장
      baseScore = baseScore.clamp(10.0, 100.0);
    } else {
      // 등척성 운동: 자세 유지 시간이 길어지면 점수 상승
      if (motionType == 'isometric') {
        baseScore = 15.0; // 등척성 최소 활성도
      } else {
        // 움직임이 미미하지만 감지되면 최소 10% 보장
        baseScore = 10.0;
      }
    }

    // ============================================
    // Step 2: 정밀 역학 레이어 (Precision Biomechanics Layer)
    // ============================================
    double precisionMultiplier = 1.0;

    // 2-1. 중력 벡터 보정
    if (gravityVector != null) {
      final isAntiGravity = gravityVector['isAntiGravity'] as bool? ?? false;
      if (isAntiGravity) {
        // 중력과 역방향(저항)이면 1.5배
        precisionMultiplier *= 1.5;
      }
    }

    // 2-2. 모멘트 암 보정
    if (momentArmLength != null && momentArmLength > 0.0) {
      // 모멘트 암이 길어질수록 점수 상승
      final lengthFactor = momentArmLength.clamp(0.0, 1.0);
      precisionMultiplier *= (1.0 + lengthFactor * 0.5); // 최대 1.5배
    }

    // 2-3. 신장성/단축성 보정
    if (isEccentric) {
      // 신장성 구간에서 제동력 발생 시 1.3배
      precisionMultiplier *= 1.3;
    }

    // 2-4. 요추 보상작용 보정
    if (lumbarCompensation) {
      final lowerKey = muscleKey.toLowerCase();
      // 보상 근육(허리)이면 2.0배, 주동근이면 0.7배
      if (lowerKey.contains('erector') ||
          lowerKey.contains('spine') ||
          lowerKey.contains('lumbar')) {
        precisionMultiplier *= 2.0; // 보상 근육 폭증
      } else {
        precisionMultiplier *= 0.7; // 주동근 점수 감소
      }
    }

    // Step 2 적용
    double finalScore = baseScore * precisionMultiplier;

    // ============================================
    // Step 3: 최종 정규화 (Final Normalization)
    // ============================================
    // 100%를 넘지 않도록 clamp
    finalScore = finalScore.clamp(0.0, 100.0);

    // 노이즈 필터링: 너무 미세한 떨림은 제거하되, 명확한 동작은 유지
    if (finalScore < 5.0 && (deltaAngle == null || deltaAngle.abs() < 2.0)) {
      // 미세한 떨림은 0으로 처리
      finalScore = 0.0;
    } else if (finalScore > 0.0 && finalScore < 10.0) {
      // 명확한 동작은 최소 10% 보장
      finalScore = 10.0;
    }

    return finalScore;
  }

  /// 관절 가중치 기반 점수 정규화 (하위 호환성)
  /// [jointKey] 관절 키 (예: 'hip', 'knee', 'ankle')
  /// [rawROM] 원본 ROM 각도 (도 단위)
  /// [context] 운동 컨텍스트 ('STATE_HINGE', 'STATE_PULL', 'STATE_PUSH')
  /// [referenceROM] 참조 ROM 각도 (도 단위, 기본값 180)
  /// 반환: 가중치가 적용된 관절 점수 (0.0 ~ 100.0)
  static double calculateWeightedJointScore({
    required String jointKey,
    required double rawROM,
    required String? context,
    double referenceROM = 180.0,
  }) {
    // Step 1: 기본 활성도 계산
    final rawScore = (rawROM / referenceROM * 100.0).clamp(0.0, 100.0);

    // Step 2: 중요도 가중치 적용 (기본값)
    double weight = 1.0;

    if (context == 'STATE_HINGE') {
      // Hinge 패턴 가중치
      switch (jointKey.toLowerCase()) {
        case 'hip':
          weight = 1.2;
          break;
        case 'knee':
          weight = 0.8;
          break;
        case 'ankle':
        case 'wrist':
          weight = 0.2;
          break;
        case 'spine':
          weight = 1.5;
          break;
        case 'elbow':
          weight = 0.3;
          break;
        default:
          weight = 0.5;
      }
    } else if (context == 'STATE_PULL') {
      // Pull 패턴 가중치
      switch (jointKey.toLowerCase()) {
        case 'elbow':
        case 'shoulder':
          weight = 1.2;
          break;
        case 'hip':
        case 'knee':
          weight = 0.1;
          break;
        case 'wrist':
          weight = 0.5;
          break;
        default:
          weight = 0.7;
      }
    } else if (context == 'STATE_PUSH') {
      // Push 패턴 가중치
      switch (jointKey.toLowerCase()) {
        case 'elbow':
        case 'shoulder':
          weight = 1.2;
          break;
        case 'hip':
        case 'knee':
          weight = 0.1;
          break;
        case 'wrist':
          weight = 0.5;
          break;
        default:
          weight = 0.7;
      }
    }

    // Step 3: 최종 점수 산출
    final finalScore = (rawScore * weight).clamp(0.0, 100.0);
    return finalScore;
  }

  // ============================================
  // 정밀 채점 알고리즘 (Precision Scoring Matrix)
  // 6대 핵심 생체역학 요소를 변수로 사용하는 수학적 명세 기반 계산
  // ============================================

  /// 운동 방식별 근육 활성도 계산 (정밀 채점 알고리즘)
  /// 사용자 제시 공식에 따라 6대 핵심 요소의 가중치를 다르게 적용
  ///
  /// [motionType] 운동 방식 ('isotonic', 'isometric', 'isokinetic')
  /// [currentROM] 현재 가동 범위 (도)
  /// [maxExpectedROM] 예상 최대 ROM (도, 기본값 180)
  /// [momentArmLength] 모멘트 암 길이 (0.0 ~ 1.0)
  /// [jointAngleVsGravity] 관절 각도 vs 중력 벡터 각도 (라디안)
  /// [eccentricVelocity] 신장성 구간 속도 (도/초)
  /// [concentricVelocity] 단축성 구간 속도 (도/초)
  /// [compensationDetected] 보상 작용 감지 여부 (bool)
  /// [holdDurationSec] 자세 유지 시간 (초, 등척성용)
  /// [targetDuration] 목표 유지 시간 (초, 등척성용, 기본값 60)
  /// [velocityVariance] 속도 분산 (등척성 미세 떨림 측정용)
  ///
  /// 반환: 최종 활성도 점수 (0.0 ~ 100.0, 최소 점수 보장)
  static double calculateMuscleActivationByExerciseType({
    required String motionType,
    double? currentROM,
    double maxExpectedROM = 180.0,
    double? momentArmLength,
    double? jointAngleVsGravity,
    double? eccentricVelocity,
    double? concentricVelocity,
    bool compensationDetected = false,
    double? holdDurationSec,
    double targetDuration = 60.0,
    double? velocityVariance,
  }) {
    // NaN/Infinity 방어: 모든 입력값 검증
    final safeCurrentROM = sanitizeOutput(currentROM);
    final safeMomentArmLength = sanitizeOutput(momentArmLength);
    final safeJointAngleVsGravity = sanitizeOutput(jointAngleVsGravity);
    final safeEccentricVelocity = sanitizeOutput(eccentricVelocity);
    final safeConcentricVelocity = sanitizeOutput(concentricVelocity);
    final safeHoldDurationSec = sanitizeOutput(holdDurationSec);
    final safeVelocityVariance = sanitizeOutput(velocityVariance);

    // 운동 방식별 계산
    switch (motionType.toLowerCase()) {
      case 'isotonic':
        return _calculateIsotonicActivation(
          currentROM: safeCurrentROM,
          maxExpectedROM: maxExpectedROM,
          momentArmLength: safeMomentArmLength,
          jointAngleVsGravity: safeJointAngleVsGravity,
          eccentricVelocity: safeEccentricVelocity,
          concentricVelocity: safeConcentricVelocity,
          compensationDetected: compensationDetected,
        );

      case 'isometric':
        return _calculateIsometricActivation(
          jointAngleVsGravity: safeJointAngleVsGravity,
          holdDurationSec: safeHoldDurationSec,
          targetDuration: targetDuration,
          velocityVariance: safeVelocityVariance,
        );

      case 'isokinetic':
        return _calculateIsokineticActivation(
          currentROM: safeCurrentROM,
          maxExpectedROM: maxExpectedROM,
          momentArmLength: safeMomentArmLength,
          jointAngleVsGravity: safeJointAngleVsGravity,
          velocityVariance: safeVelocityVariance,
          compensationDetected: compensationDetected,
        );

      default:
        // 기본값: 등장성으로 처리
        return _calculateIsotonicActivation(
          currentROM: safeCurrentROM,
          maxExpectedROM: maxExpectedROM,
          momentArmLength: safeMomentArmLength,
          jointAngleVsGravity: safeJointAngleVsGravity,
          eccentricVelocity: safeEccentricVelocity,
          concentricVelocity: safeConcentricVelocity,
          compensationDetected: compensationDetected,
        );
    }
  }

  /// 등장성 운동 활성도 계산
  /// 공식: ROM Score (30%) + Torque Efficiency (40%) + Rhythm/Tempo (20%) - Stability Penalty (10%)
  static double _calculateIsotonicActivation({
    required double currentROM,
    required double maxExpectedROM,
    required double momentArmLength,
    required double jointAngleVsGravity,
    required double eccentricVelocity,
    required double concentricVelocity,
    required bool compensationDetected,
  }) {
    // 1. ROM Score (30%): 전체 가동 범위가 클수록 점수 높음
    // 분모 0 방지
    final safeMaxROM = maxExpectedROM > 0.001 ? maxExpectedROM : 180.0;
    final scoreROM = math.min((currentROM / safeMaxROM) * 100.0, 100.0);

    // 2. Torque Efficiency (40%): 모멘트 암과 중력 벡터의 곱
    // sin(joint_angle_vs_gravity)로 중력과의 각도 계산
    // 관절 각도가 중력 벡터와 수직일 때(90도) 최대 점수
    final gravityAngle = math.sin(jointAngleVsGravity).clamp(-1.0, 1.0);
    // scalingFactor: momentArmLength가 1.0일 때 100점이 되도록 조정
    const scalingFactor = 100.0;
    final scoreTorque =
        (momentArmLength.clamp(0.0, 1.0) * gravityAngle.abs()) * scalingFactor;
    final scoreTorqueClamped = math.min(scoreTorque, 100.0);

    // 3. Rhythm/Tempo (20%): 신장성 구간의 속도 제어 능력
    // 신장성 속도가 단축성 속도보다 낮으면 제어가 잘 되고 있음
    double scoreTempo = 70.0; // 기본값
    if (eccentricVelocity > 0.0 && concentricVelocity > 0.0) {
      scoreTempo = eccentricVelocity < concentricVelocity ? 100.0 : 70.0;
    } else if (eccentricVelocity > 0.0) {
      // 신장성만 있는 경우 (하강 구간)
      scoreTempo = 100.0;
    }

    // 4. Stability Penalty (-10%): 보상 작용 감지 시 차감
    final penalty = compensationDetected ? 20.0 : 0.0;

    // 최종 점수 계산 (최소 15점 보장)
    final finalActivation = math.max(
      (scoreROM * 0.3) +
          (scoreTorqueClamped * 0.4) +
          (scoreTempo * 0.2) -
          penalty,
      15.0,
    );

    return sanitizeOutput(finalActivation).clamp(0.0, 100.0);
  }

  /// 등척성 운동 활성도 계산
  /// 공식: Anti-Gravity Score (50%) + Time under Tension (30%) + Stiffness (20%)
  static double _calculateIsometricActivation({
    required double jointAngleVsGravity,
    required double holdDurationSec,
    required double targetDuration,
    required double velocityVariance,
  }) {
    // 1. Anti-Gravity Score (50%): 관절 각도가 중력 벡터와 90도에 가까울수록 100점
    // sin(joint_angle_vs_gravity)가 1.0에 가까울수록(90도) 최대 점수
    final gravityAngle = math.sin(jointAngleVsGravity).clamp(-1.0, 1.0);
    final scoreGravity = gravityAngle.abs() * 100.0;

    // 2. Time under Tension (30%): 자세 유지 시간
    // 분모 0 방지
    final safeTargetDuration = targetDuration > 0.001 ? targetDuration : 60.0;
    final scoreTime = math.min(
      (holdDurationSec / safeTargetDuration) * 100.0,
      100.0,
    );

    // 3. Stiffness/Micro-Tremor (20%): 미세한 떨림은 높은 근육 활성도로 해석
    // velocity_variance를 점수로 변환 (떨림이 적을수록 높은 점수)
    final scoreStiffness = _mapTremorToScore(velocityVariance);

    // 최종 점수 (움직임 없어도 점수 높게, 최소 20점 보장)
    final finalActivation = math.max(
      (scoreGravity * 0.5) + (scoreTime * 0.3) + (scoreStiffness * 0.2),
      20.0,
    );

    return sanitizeOutput(finalActivation).clamp(0.0, 100.0);
  }

  /// 등속성 운동 활성도 계산
  /// 등장성과 유사하되 속도 일관성(consistency) 점수 추가
  static double _calculateIsokineticActivation({
    required double currentROM,
    required double maxExpectedROM,
    required double momentArmLength,
    required double jointAngleVsGravity,
    required double velocityVariance,
    required bool compensationDetected,
  }) {
    // 등장성과 유사한 계산
    // 분모 0 방지
    final safeMaxROM = maxExpectedROM > 0.001 ? maxExpectedROM : 180.0;
    final scoreROM = math.min((currentROM / safeMaxROM) * 100.0, 100.0);
    final gravityAngle = math.sin(jointAngleVsGravity).clamp(-1.0, 1.0);
    const scalingFactor = 100.0;
    final scoreTorque = math.min(
      (momentArmLength.clamp(0.0, 1.0) * gravityAngle.abs()) * scalingFactor,
      100.0,
    );

    // 속도 일관성 점수: 분산이 낮을수록 높은 점수
    final consistencyScore = _mapVelocityConsistencyToScore(velocityVariance);

    final penalty = compensationDetected ? 20.0 : 0.0;

    // 가중치: ROM (25%) + Torque (35%) + Consistency (30%) - Penalty (10%)
    final finalActivation = math.max(
      (scoreROM * 0.25) +
          (scoreTorque * 0.35) +
          (consistencyScore * 0.3) -
          penalty,
      15.0,
    );

    return sanitizeOutput(finalActivation).clamp(0.0, 100.0);
  }

  /// 미세 떨림을 점수로 변환 (등척성용)
  /// [velocityVariance] 속도 분산 (낮을수록 안정적)
  /// 반환: 0.0 ~ 100.0 (떨림이 적을수록 높은 점수)
  static double _mapTremorToScore(double velocityVariance) {
    // 분산이 0에 가까울수록 높은 점수
    // 분산이 10 이상이면 낮은 점수
    if (velocityVariance <= 0.0) {
      return 100.0; // 완전히 안정적
    } else if (velocityVariance < 1.0) {
      return 90.0; // 매우 안정적
    } else if (velocityVariance < 5.0) {
      return 70.0; // 안정적
    } else if (velocityVariance < 10.0) {
      return 50.0; // 보통
    } else {
      return 30.0; // 불안정 (하지만 여전히 점수 부여)
    }
  }

  /// 속도 일관성을 점수로 변환 (등속성용)
  /// [velocityVariance] 속도 분산 (낮을수록 일관적)
  /// 반환: 0.0 ~ 100.0
  static double _mapVelocityConsistencyToScore(double velocityVariance) {
    // 등속성 운동: 속도가 일정해야 함
    if (velocityVariance <= 0.0) {
      return 100.0; // 완벽하게 일정
    } else if (velocityVariance < 2.0) {
      return 90.0; // 매우 일정
    } else if (velocityVariance < 5.0) {
      return 70.0; // 일정
    } else if (velocityVariance < 10.0) {
      return 50.0; // 보통
    } else {
      return 30.0; // 불일정
    }
  }

  /// 관절 각도와 중력 벡터 사이의 각도 계산
  /// [jointAngle] 관절 각도 (라디안)
  /// [gravityVector] 중력 벡터 맵 {'x': double, 'y': double, 'z': double}
  /// 반환: 각도 (라디안)
  static double calculateJointAngleVsGravity(
    double jointAngle,
    Map<String, double>? gravityVector,
  ) {
    if (gravityVector == null) {
      // 기본값: 중력은 아래 방향 (y축 음수)
      // 관절 각도와 90도(π/2) 차이
      return math.pi / 2.0;
    }

    // 중력 벡터 정규화
    final gx = gravityVector['x'] ?? 0.0;
    final gy = gravityVector['y'] ?? -1.0; // 기본값: 아래 방향
    final gz = gravityVector['z'] ?? 0.0;

    final gravityMagnitude = math.sqrt(gx * gx + gy * gy + gz * gz);
    if (gravityMagnitude < 0.001) {
      return math.pi / 2.0; // Fallback
    }

    // 관절 벡터 (간단화: 관절 각도를 벡터로 변환)
    // 관절 각도가 0도면 수평, 90도면 수직
    final jointVecX = math.cos(jointAngle);
    final jointVecY = math.sin(jointAngle);

    // 내적 계산
    final dotProduct = (jointVecX * gx + jointVecY * gy) / gravityMagnitude;

    // 각도 계산 (0 ~ π)
    final clampedDot = dotProduct.clamp(-1.0, 1.0);
    return math.acos(clampedDot);
  }

  // ============================================
  // 관절 기여도 계산 (절댓값 합계 방식)
  // ============================================

  /// 관절 기여도 계산 (절댓값 합계 방식)
  /// 상대적인 힘의 비율을 구하기 위해 절댓값 합계(Sum of Absolute Torques) 방식 사용
  ///
  /// [jointTorques] 관절별 토크 맵 (`Map<String, double>`)
  /// [targetArea] 타겟 부위 ('upper', 'lower', 'full')
  ///
  /// 반환: 관절별 기여도 맵 (`Map<String, double>`), 각 값은 0.0 ~ 100.0
  static Map<String, double> calculateJointContributionByTorque({
    required Map<String, double> jointTorques,
    String targetArea = 'full',
  }) {
    // Step 1: 각 관절의 순간 토크 계산 (절댓값)
    final absoluteTorques = <String, double>{};
    for (final entry in jointTorques.entries) {
      final torque = sanitizeOutput(entry.value);
      absoluteTorques[entry.key] = torque.abs(); // Dart의 abs() 메서드 사용
    }

    // Step 2: 총 노력(Total Effort) 합산
    double totalEffort = 0.0;
    for (final torque in absoluteTorques.values) {
      totalEffort += torque;
    }

    // Step 3: 기여도(%) 계산 (0으로 나누기 방지)
    if (totalEffort < 0.001) {
      totalEffort = 1.0; // Fallback: 모든 관절에 균등 분배
    }

    final contributionMap = <String, double>{};
    for (final entry in absoluteTorques.entries) {
      final contribution = (entry.value / totalEffort) * 100.0;
      contributionMap[entry.key] = sanitizeOutput(contribution);
    }

    // Step 4: 타겟 부위 가중치 적용
    final targetAreaLower = targetArea.toLowerCase();
    if (targetAreaLower == 'lower') {
      // 하체 운동 선택 시 둔근/대퇴사두근 관련 관절 수치 강조
      if (contributionMap.containsKey('hip')) {
        contributionMap['hip'] = (contributionMap['hip']! * 1.2).clamp(
          0.0,
          100.0,
        );
      }
      if (contributionMap.containsKey('knee')) {
        contributionMap['knee'] = (contributionMap['knee']! * 1.2).clamp(
          0.0,
          100.0,
        );
      }
      if (contributionMap.containsKey('ankle')) {
        contributionMap['ankle'] = (contributionMap['ankle']! * 1.2).clamp(
          0.0,
          100.0,
        );
      }

      // 합이 100을 넘지 않도록 정규화
      final total = contributionMap.values.fold(0.0, (sum, val) => sum + val);
      if (total > 100.0 && total > 0.001) {
        for (final key in contributionMap.keys) {
          contributionMap[key] = (contributionMap[key]! / total) * 100.0;
        }
      }
    } else if (targetAreaLower == 'upper') {
      // 상체 운동 선택 시 상지 관절 수치 강조
      if (contributionMap.containsKey('shoulder')) {
        contributionMap['shoulder'] = (contributionMap['shoulder']! * 1.2)
            .clamp(0.0, 100.0);
      }
      if (contributionMap.containsKey('elbow')) {
        contributionMap['elbow'] = (contributionMap['elbow']! * 1.2).clamp(
          0.0,
          100.0,
        );
      }
      if (contributionMap.containsKey('wrist')) {
        contributionMap['wrist'] = (contributionMap['wrist']! * 1.2).clamp(
          0.0,
          100.0,
        );
      }

      // 합이 100을 넘지 않도록 정규화
      final total = contributionMap.values.fold(0.0, (sum, val) => sum + val);
      if (total > 100.0 && total > 0.001) {
        for (final key in contributionMap.keys) {
          contributionMap[key] = (contributionMap[key]! / total) * 100.0;
        }
      }
    }

    // 최종 검증: NaN/Infinity 방어
    for (final key in contributionMap.keys.toList()) {
      final value = contributionMap[key]!;
      if (value.isNaN || value.isInfinite) {
        contributionMap[key] = 0.0;
      }
    }

    return contributionMap;
  }

  /// 관절별 토크 계산
  /// 모멘트 암 × 힘 (Force) × sin(관절 각도 vs 중력)
  ///
  /// [jointName] 관절명
  /// [rom] 가동 범위 (도)
  /// [momentArmLength] 모멘트 암 길이 (0.0 ~ 1.0)
  /// [jointAngleVsGravity] 관절 각도 vs 중력 벡터 각도 (라디안)
  /// [bodyWeight] 체중 (kg, 기본값 70)
  ///
  /// 반환: 토크 (Nm)
  static double calculateTorque({
    required String jointName,
    required double rom,
    required double momentArmLength,
    required double jointAngleVsGravity,
    double bodyWeight = 70.0,
  }) {
    // NaN/Infinity 방어
    final safeMomentArm = momentArmLength.clamp(0.0, 1.0);
    final safeAngle = sanitizeOutput(jointAngleVsGravity);

    // 중력 가속도 (m/s²)
    const gravityAcceleration = 9.8;

    // 힘 계산: 체중 × 중력 가속도
    final force = bodyWeight * gravityAcceleration;

    // 모멘트 암 길이 (m): 정규화된 값을 실제 길이로 변환 (0.1m ~ 0.5m)
    // 관절별로 다른 기본 길이 사용
    double actualMomentArm = 0.2; // 기본값 0.2m
    switch (jointName.toLowerCase()) {
      case 'hip':
        actualMomentArm = 0.3 + (safeMomentArm * 0.2); // 0.3m ~ 0.5m
        break;
      case 'knee':
        actualMomentArm = 0.2 + (safeMomentArm * 0.15); // 0.2m ~ 0.35m
        break;
      case 'ankle':
        actualMomentArm = 0.1 + (safeMomentArm * 0.1); // 0.1m ~ 0.2m
        break;
      case 'shoulder':
        actualMomentArm = 0.25 + (safeMomentArm * 0.15); // 0.25m ~ 0.4m
        break;
      case 'elbow':
        actualMomentArm = 0.15 + (safeMomentArm * 0.1); // 0.15m ~ 0.25m
        break;
      default:
        actualMomentArm = 0.2 + (safeMomentArm * 0.1); // 0.2m ~ 0.3m
    }

    // 토크 계산: F × r × sin(θ)
    // sin(각도)로 중력과의 관계 반영
    final sinAngle = math.sin(safeAngle).clamp(-1.0, 1.0);
    final torque = force * actualMomentArm * sinAngle.abs();

    return sanitizeOutput(torque);
  }
}
