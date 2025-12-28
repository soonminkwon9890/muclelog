import 'dart:math' as math;

class MuscleMetricUtils {
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
  // [Step 0] 상완골 리듬(Scapulohumeral Rhythm) 계산기
  // =======================================================
  static double calculateInstantRhythm({
    required double shoulderY,
    required double earY,
    required double elbowX,
    required double elbowY,
    required double shoulderX,
  }) {
    double neckLength = (shoulderY - earY).abs();
    double armAngleRad = math.atan2(
      (elbowY - shoulderY).abs(),
      (elbowX - shoulderX).abs(),
    );
    double armAngleDeg = armAngleRad * (180 / math.pi);

    // 목 길이가 확보될수록 점수가 높음 (1.0 = 좋음, 0.0 = 으쓱)
    double rhythmScore = (neckLength / 100.0).clamp(0.0, 1.0);

    // 팔을 내리고 있을 때는(30도 미만) 리듬 판단 무의미 -> 1.0 처리
    if (armAngleDeg < 30) return 1.0;

    return rhythmScore;
  }

  // =======================================================
  // [Step 1] 관절 기여도 통계 (Quantity) & Visibility 필터
  // + 요추(Spine) 관절 추가
  // =======================================================
  static Map<String, double> _calculateJointContribution(
    Map<String, double> jointDeltas,
    Map<String, double> visibilityMap,
    String targetArea,
  ) {
    final contribution = <String, double>{};
    double totalMovement = 0.0;

    // 1. 노이즈 및 화면 밖 관절 제거
    jointDeltas.forEach((key, value) {
      double vis = visibilityMap[key] ?? 0.0;
      // Deadzone(15도) & Visibility(0.5)
      if (value.abs() > 15.0 && vis > 0.5) {
        totalMovement += value.abs();
      }
    });

    if (totalMovement == 0.0) return {};

    // 2. 기여도 비율 계산
    jointDeltas.forEach((key, value) {
      double vis = visibilityMap[key] ?? 0.0;
      if (value.abs() > 15.0 && vis > 0.5) {
        contribution[key] = (value.abs() / totalMovement);
      } else {
        contribution[key] = 0.0;
      }
    });

    // 3. 사용자 타겟에 따른 억제 로직
    String target = targetArea.toUpperCase();
    bool suppressUpper = target == 'LOWER';
    bool suppressLower = target == 'UPPER';

    if (target != 'LOWER' && target != 'UPPER') {
      double lowerSum =
          (contribution['leftHip'] ?? 0) +
          (contribution['rightHip'] ?? 0) +
          (contribution['leftKnee'] ?? 0) +
          (contribution['rightKnee'] ?? 0);
      double upperSum =
          (contribution['leftShoulder'] ?? 0) +
          (contribution['rightShoulder'] ?? 0) +
          (contribution['leftElbow'] ?? 0) +
          (contribution['rightElbow'] ?? 0);

      if (lowerSum > upperSum * 1.5) {
        suppressUpper = true;
      } else if (upperSum > lowerSum * 1.5) {
        suppressLower = true;
      }
    }

    // 억제 적용 (요추(spine)는 보상작용 감지를 위해 억제하지 않고 남겨둠)
    contribution.forEach((key, value) {
      bool isLowerJoint =
          key.toLowerCase().contains('knee') ||
          key.toLowerCase().contains('hip') ||
          key.toLowerCase().contains('ankle');
      bool isSpine = key.toLowerCase().contains('spine');

      if (!isSpine) {
        // 요추 제외하고 억제 적용
        if (suppressLower && isLowerJoint) contribution[key] = value * 0.1;
        if (suppressUpper && !isLowerJoint) contribution[key] = value * 0.1;
      }
    });

    return contribution;
  }

  // =======================================================
  // [Step 1.5] Joint-by-Joint 수치 보정 계수 계산
  // =======================================================
  // 이웃 관절의 가동성 데이터를 기반으로 0.5 ~ 1.2 사이의 가중치를 반환 (순수 수치 계산)
  static Map<String, double> _calculateJBJFactors(
    Map<String, double> jointDeltas,
    String targetArea, // 'UPPER', 'LOWER', 'FULL'
  ) {
    final factors = <String, double>{};
    bool calcUpper = targetArea == 'UPPER' || targetArea == 'FULL';
    bool calcLower = targetArea == 'LOWER' || targetArea == 'FULL';

    // 1. Spine JBJ (Core는 항상 계산)
    // 인접 관절: Hip + Shoulder
    double avgHip =
        ((jointDeltas['leftHip'] ?? 0) + (jointDeltas['rightHip'] ?? 0)) / 2.0;
    double avgShoulder =
        ((jointDeltas['leftShoulder'] ?? 0) +
            (jointDeltas['rightShoulder'] ?? 0)) /
        2.0;

    // 이웃 관절 평균 40도 기준. (40도 이상 움직이면 1.0 넘음, 최대 1.5배)
    double spineNeighborMobility = (avgHip + avgShoulder) / 2.0;
    factors['spine'] = (spineNeighborMobility / 40.0).clamp(0.8, 1.5);

    // 2. Knee JBJ (하체 로직)
    // 인접 관절: Hip + Ankle
    if (calcLower) {
      double leftHip = jointDeltas['leftHip'] ?? 0.0;
      double leftAnkle = jointDeltas['leftAnkle'] ?? 0.0;
      double leftKneeMobility = (leftHip + leftAnkle * 2.0) / 2.0; // 발목 가중치 2배
      factors['leftKnee'] = (leftKneeMobility / 60.0).clamp(0.5, 1.2);

      double rightHip = jointDeltas['rightHip'] ?? 0.0;
      double rightAnkle = jointDeltas['rightAnkle'] ?? 0.0;
      double rightKneeMobility = (rightHip + rightAnkle * 2.0) / 2.0;
      factors['rightKnee'] = (rightKneeMobility / 60.0).clamp(0.5, 1.2);
    }

    // 3. Elbow JBJ (상체 로직)
    // 인접 관절: Only Shoulder (손목 제외 - 현실적 운동 패턴 반영)
    if (calcUpper) {
      double leftShoulder = jointDeltas['leftShoulder'] ?? 0.0;
      // 어깨 가동성만으로 팔꿈치 부하 평가 (기준 50.0)
      factors['leftElbow'] = (leftShoulder / 50.0).clamp(0.5, 1.2);

      double rightShoulder = jointDeltas['rightShoulder'] ?? 0.0;
      factors['rightElbow'] = (rightShoulder / 50.0).clamp(0.5, 1.2);
    }

    return factors;
  }

  // =======================================================
  // [Step 2] 6대 핵심 요소 품질 평가 (Quality)
  // =======================================================
  static double _evaluateMovementQuality(
    String jointKey,
    double rom,
    double variance,
    double velocity,
    double duration,
    String motionType,
  ) {
    double score = 0.0;
    bool isSpine = jointKey.toLowerCase().contains('spine');

    // A. 등장성 운동 (Isotonic)
    if (motionType == 'ISOTONIC') {
      if (isSpine) {
        // [요추 특수 로직] 등장성에서 움직임이 크면(>20) 보상작용 -> 낮은 점수 반환
        return rom > 20.0 ? 20.0 : 100.0;
      }

      // 일반 관절
      double romScore = (rom / 130.0 * 100).clamp(0.0, 100.0);
      double velScore = (velocity / 50.0 * 100).clamp(0.0, 100.0);
      double gravScore = rom > 15.0 ? 100.0 : 0.0;
      score = (romScore * 0.5 + velScore * 0.3 + gravScore * 0.2);
    }
    // B. 등척성 운동 (Isometric)
    else {
      // 1. Stability (안정성)
      double stabilityScore = ((10.0 - variance) * 10.0).clamp(0.0, 100.0);

      // 2. TUT (Time Under Tension)
      double tutScore = (duration / 30.0 * 100).clamp(0.0, 100.0);

      // [요추 특수 로직]
      if (isSpine && variance > 5.0) stabilityScore *= 0.2;

      // [보상작용 필터]
      if (rom > 20.0) stabilityScore *= 0.5;

      score = (stabilityScore * 0.6 + tutScore * 0.4);
    }

    return score.clamp(0.0, 100.0);
  }

  // =======================================================
  // [Step 1.5] 복합 관절 시너지 계산 (Compound Synergy)
  // =======================================================
  static Map<String, double> _calculateCompoundSynergy(
    Map<String, double> jointDeltas,
    String targetArea,
    double rhythmScore, // 1.0에 가까울수록 견갑 안정화 (앵커링 잘됨)
    Map<String, double> jbjFactors, // JBJ 기반 관절 협응도
    Map<String, double> jointVariances, // 허리 떨림 확인용
  ) {
    final synergy = <String, double>{};
    bool isUpper = targetArea == 'UPPER' || targetArea == 'FULL';
    bool isLower = targetArea == 'LOWER' || targetArea == 'FULL';

    // 1. 상체 시너지 (Push/Pull) - 앵커링 효과 적용
    if (isUpper) {
      // 왼쪽
      double lShoulder = jointDeltas['leftShoulder'] ?? 0.0;
      double lElbow = jointDeltas['leftElbow'] ?? 0.0;

      // 복합 움직임 감지 (둘 다 30도 이상)
      if (lShoulder > 30 && lElbow > 30) {
        // 기본 파워: 관절 움직임의 합
        double rawPower = (lShoulder + lElbow) / 100.0;

        // [앵커링 로직]
        // RhythmScore(0~1)가 높으면(목이 길면) -> 대흉근/광배근 시너지 상승 (최대 1.5배)
        // RhythmScore가 낮으면(으쓱하면) -> 어깨/승모근 개입, 대흉근 시너지 감소
        double anchorFactor = (0.5 + rhythmScore).clamp(0.5, 1.5); // 0.5 ~ 1.5배

        double currentPec = synergy['pecs_lats'] ?? 1.0;
        double newPec = (rawPower * anchorFactor).clamp(1.0, 2.5);
        synergy['pecs_lats'] = (currentPec + newPec) / 2.0; // 평균 적용
        synergy['delts_traps'] = rawPower.clamp(1.0, 1.2); // 보조근은 소폭 상승
      }

      // 오른쪽 (동일 로직 적용)
      double rShoulder = jointDeltas['rightShoulder'] ?? 0.0;
      double rElbow = jointDeltas['rightElbow'] ?? 0.0;
      if (rShoulder > 30 && rElbow > 30) {
        double rawPower = (rShoulder + rElbow) / 100.0;
        double anchorFactor = (0.5 + rhythmScore).clamp(0.5, 1.5);

        double currentPec = synergy['pecs_lats'] ?? 1.0;
        double newPec = (rawPower * anchorFactor).clamp(1.0, 2.5);
        synergy['pecs_lats'] = (currentPec + newPec) / 2.0; // 평균 적용
      }

      // [New] 승모근 보상 계수 (Compensation Factor)
      // rhythmScore가 낮으면(으쓱하면) -> 승모근 보상 작용 발생
      if (rhythmScore >= 0.7) {
        synergy['traps_comp'] = 1.0; // 자세 좋음, 보상 없음
      } else {
        // rhythmScore가 낮을수록 높은 값
        // 예: rhythmScore = 0.3 -> traps_comp = 1.0 + (0.7 * 1.5) = 2.05 -> clamp(1.2, 1.5) = 1.5
        double compensation = 1.0 + ((1.0 - rhythmScore) * 1.5);
        synergy['traps_comp'] = compensation.clamp(1.2, 1.5);
      }
    }

    // 2. 하체 시너지 (Squat/Lunge) - JBJ & Spine 안정성 적용
    if (isLower) {
      // [JBJ 로직 반영] 둔근은 고관절(Hip)과 발목(Ankle)이 잘 움직일 때 활성화됨
      // 무릎(Knee)만 많이 쓰면 둔근 개입 적음

      double avgHip =
          ((jointDeltas['leftHip'] ?? 0) + (jointDeltas['rightHip'] ?? 0)) /
          2.0;
      double avgAnkle =
          ((jointDeltas['leftAnkle'] ?? 0) + (jointDeltas['rightAnkle'] ?? 0)) /
          2.0;

      // 고관절과 발목이 충분히 움직였는가?
      if (avgHip > 40 && avgAnkle > 10) {
        double jbjScore = (avgHip + avgAnkle * 2.0) / 100.0; // 발목 가중치 2배

        // [허리 안정성 페널티]
        // 허리가 흔들리면(분산 > 10) 둔근 힘 누수 발생
        double spineVar = jointVariances['spine'] ?? 0.0;
        double corePenalty = spineVar > 10.0 ? 0.7 : 1.0; // 불안정하면 30% 감소

        synergy['glutes'] = (jbjScore * corePenalty).clamp(
          1.0,
          2.2,
        ); // 둔근 최대 2.2배 가산
      }
    }

    // 기본값 설정 (시너지가 없을 경우 1.0)
    synergy.putIfAbsent('pecs_lats', () => 1.0);
    synergy.putIfAbsent('delts_traps', () => 1.0);
    synergy.putIfAbsent('traps_comp', () => 1.0);
    synergy.putIfAbsent('glutes', () => 1.0);

    return synergy;
  }

  // =======================================================
  // [Step 3] 근육 매핑 및 요추 안정성 평가 (Mapping)
  // =======================================================
  static Map<String, double> _mapToMuscles(
    Map<String, double> contributions,
    Map<String, double> qualities,
    double rhythmScore,
    String motionType,
    String targetArea, // 'UPPER', 'LOWER', 'FULL'
    Map<String, double> jointDeltas, // 요추 ROM 확인용
    Map<String, double> jointVariances, // 요추 떨림 확인용
    Map<String, double> synergy, // [New] 복합 관절 시너지 계수
  ) {
    final scores = <String, double>{};

    // [1] 타겟 부위에 따른 가중치 설정
    double upperMultiplier = 3.5;
    double lowerMultiplier = 3.5;

    if (targetArea.toUpperCase() == 'UPPER') {
      upperMultiplier = 4.5;
      lowerMultiplier = 1.0;
    } else if (targetArea.toUpperCase() == 'LOWER') {
      upperMultiplier = 1.0;
      lowerMultiplier = 4.5;
    }

    // 기본 계산 함수 (multiplier 적용)
    double calc(String jointKey, double multiplier) {
      double contrib = contributions[jointKey] ?? 0.0;
      double qual = qualities[jointKey] ?? 0.0;
      return (qual * (contrib * multiplier)).clamp(0.0, 100.0);
    }

    // --- 하체 근육 ---
    scores['left_quadriceps'] = calc('leftKnee', lowerMultiplier);
    scores['right_quadriceps'] = calc('rightKnee', lowerMultiplier);

    // 하체 시너지 계수 적용
    double gluteSynergy = synergy['glutes'] ?? 1.0;
    scores['left_glutes'] = (calc('leftHip', lowerMultiplier) * gluteSynergy)
        .clamp(0.0, 100.0);
    scores['right_glutes'] = (calc('rightHip', lowerMultiplier) * gluteSynergy)
        .clamp(0.0, 100.0);
    scores['left_hamstrings'] =
        (calc('leftHip', lowerMultiplier) * 0.5 +
        calc('leftKnee', lowerMultiplier) * 0.5);
    scores['right_hamstrings'] =
        (calc('rightHip', lowerMultiplier) * 0.5 +
        calc('rightKnee', lowerMultiplier) * 0.5);

    // --- 상체 근육 ---
    double shoulderLeftRaw = calc('leftShoulder', upperMultiplier);
    double shoulderRightRaw = calc('rightShoulder', upperMultiplier);

    // 상체 시너지 계수 적용
    double pecSynergy = synergy['pecs_lats'] ?? 1.0;
    double deltSynergy = synergy['delts_traps'] ?? 1.0;
    double trapsCompensation = synergy['traps_comp'] ?? 1.0; // [New] 승모근 보상 계수

    // 승모근: 기존 trapFactor + 보상 계수 적용
    double trapFactor = (1.0 - rhythmScore).clamp(0.0, 1.0);
    scores['trapezius'] =
        ((shoulderLeftRaw + shoulderRightRaw) *
                trapFactor *
                1.5 *
                trapsCompensation)
            .clamp(0.0, 100.0);

    double latsFactor = rhythmScore;

    scores['left_latissimus'] = (shoulderLeftRaw * latsFactor * pecSynergy)
        .clamp(0.0, 100.0);
    scores['right_latissimus'] = (shoulderRightRaw * latsFactor * pecSynergy)
        .clamp(0.0, 100.0);
    scores['left_pectorals'] = (shoulderLeftRaw * latsFactor * 0.9 * pecSynergy)
        .clamp(0.0, 100.0);
    scores['right_pectorals'] =
        (shoulderRightRaw * latsFactor * 0.9 * pecSynergy).clamp(0.0, 100.0);
    scores['left_deltoids'] = (shoulderLeftRaw * deltSynergy).clamp(0.0, 100.0);
    scores['right_deltoids'] = (shoulderRightRaw * deltSynergy).clamp(
      0.0,
      100.0,
    );

    scores['left_biceps'] = calc('leftElbow', upperMultiplier);
    scores['right_biceps'] = calc('rightElbow', upperMultiplier);
    scores['left_triceps'] = calc('leftElbow', upperMultiplier);
    scores['right_triceps'] = calc('rightElbow', upperMultiplier);

    // [2] 기립근(Erector Spinae) = 안정성(Stability) 평가
    double spineRom = jointDeltas['spine'] ?? 0.0;
    double spineVar = jointVariances['spine'] ?? 0.0;
    double instabilityPenalty = 0.0;

    if (motionType == 'ISOTONIC') {
      if (spineRom > 10.0) {
        instabilityPenalty = ((spineRom - 10.0) * 4.0).clamp(0.0, 100.0);
      }
    } else {
      if (spineVar > 5.0) {
        instabilityPenalty = ((spineVar - 5.0) * 10.0).clamp(0.0, 100.0);
      }
    }

    double stabilityScore = (100.0 - instabilityPenalty).clamp(0.0, 100.0);
    scores['erector_spinae'] = stabilityScore;

    // [3] 에너지 누수(Energy Leak) 적용
    double efficiencyFactor = 1.0 - (instabilityPenalty / 250.0);

    if (targetArea.toUpperCase() == 'UPPER') {
      scores['left_latissimus'] =
          (scores['left_latissimus']! * efficiencyFactor);
      scores['right_latissimus'] =
          (scores['right_latissimus']! * efficiencyFactor);
      scores['left_pectorals'] = (scores['left_pectorals']! * efficiencyFactor);
      scores['right_pectorals'] =
          (scores['right_pectorals']! * efficiencyFactor);
    } else if (targetArea.toUpperCase() == 'LOWER') {
      scores['left_glutes'] = (scores['left_glutes']! * efficiencyFactor);
      scores['right_glutes'] = (scores['right_glutes']! * efficiencyFactor);
      scores['left_hamstrings'] =
          (scores['left_hamstrings']! * efficiencyFactor);
      scores['right_hamstrings'] =
          (scores['right_hamstrings']! * efficiencyFactor);
    }

    return scores;
  }

  // =======================================================
  // [Main] 통합 분석 실행 (Entry Point)
  // =======================================================
  static Map<String, dynamic> performAnalysis({
    required Map<String, double> jointDeltas,
    required Map<String, double> jointVariances,
    required Map<String, double> jointVelocities,
    required Map<String, double> visibilityMap,
    required double duration,
    required double averageRhythmScore,
    required String motionType,
    required String targetArea,
  }) {
    // [측면 촬영 보정] 가시성 불균형 감지 및 미러링
    Map<String, double> adjustedJointDeltas = Map.from(jointDeltas);
    Map<String, double> adjustedVisibilityMap = Map.from(visibilityMap);
    Map<String, double> adjustedJointVariances = Map.from(jointVariances);
    Map<String, double> adjustedJointVelocities = Map.from(jointVelocities);

    // 왼쪽/오른쪽 관절 가시성 평균 계산
    double leftVisibilityAvg = 0.0;
    double rightVisibilityAvg = 0.0;
    int leftCount = 0;
    int rightCount = 0;

    visibilityMap.forEach((key, value) {
      if (key.toLowerCase().contains('left')) {
        leftVisibilityAvg += value;
        leftCount++;
      } else if (key.toLowerCase().contains('right')) {
        rightVisibilityAvg += value;
        rightCount++;
      }
    });

    if (leftCount > 0) leftVisibilityAvg /= leftCount;
    if (rightCount > 0) rightVisibilityAvg /= rightCount;

    // 가시성 차이가 0.3(30%) 이상이면 측면 촬영으로 판단
    double visibilityDiff = (leftVisibilityAvg - rightVisibilityAvg).abs();
    bool isSideView = visibilityDiff >= 0.3;

    if (isSideView) {
      // 잘 보이는 쪽 결정
      bool leftSideVisible = leftVisibilityAvg > rightVisibilityAvg;

      // 안 보이는 쪽에 잘 보이는 쪽 데이터 미러링
      if (leftSideVisible) {
        // 왼쪽 → 오른쪽 미러링
        adjustedJointDeltas['rightHip'] = adjustedJointDeltas['leftHip'] ?? 0.0;
        adjustedJointDeltas['rightKnee'] =
            adjustedJointDeltas['leftKnee'] ?? 0.0;
        adjustedJointDeltas['rightAnkle'] =
            adjustedJointDeltas['leftAnkle'] ?? 0.0;
        adjustedJointDeltas['rightShoulder'] =
            adjustedJointDeltas['leftShoulder'] ?? 0.0;
        adjustedJointDeltas['rightElbow'] =
            adjustedJointDeltas['leftElbow'] ?? 0.0;

        adjustedVisibilityMap['rightHip'] =
            adjustedVisibilityMap['leftHip'] ?? 0.0;
        adjustedVisibilityMap['rightKnee'] =
            adjustedVisibilityMap['leftKnee'] ?? 0.0;
        adjustedVisibilityMap['rightAnkle'] =
            adjustedVisibilityMap['leftAnkle'] ?? 0.0;
        adjustedVisibilityMap['rightShoulder'] =
            adjustedVisibilityMap['leftShoulder'] ?? 0.0;
        adjustedVisibilityMap['rightElbow'] =
            adjustedVisibilityMap['leftElbow'] ?? 0.0;

        adjustedJointVariances['rightHip'] =
            adjustedJointVariances['leftHip'] ?? 0.0;
        adjustedJointVariances['rightKnee'] =
            adjustedJointVariances['leftKnee'] ?? 0.0;
        adjustedJointVariances['rightAnkle'] =
            adjustedJointVariances['leftAnkle'] ?? 0.0;
        adjustedJointVariances['rightShoulder'] =
            adjustedJointVariances['leftShoulder'] ?? 0.0;
        adjustedJointVariances['rightElbow'] =
            adjustedJointVariances['leftElbow'] ?? 0.0;

        adjustedJointVelocities['rightHip'] =
            adjustedJointVelocities['leftHip'] ?? 0.0;
        adjustedJointVelocities['rightKnee'] =
            adjustedJointVelocities['leftKnee'] ?? 0.0;
        adjustedJointVelocities['rightAnkle'] =
            adjustedJointVelocities['leftAnkle'] ?? 0.0;
        adjustedJointVelocities['rightShoulder'] =
            adjustedJointVelocities['leftShoulder'] ?? 0.0;
        adjustedJointVelocities['rightElbow'] =
            adjustedJointVelocities['leftElbow'] ?? 0.0;
      } else {
        // 오른쪽 → 왼쪽 미러링
        adjustedJointDeltas['leftHip'] = adjustedJointDeltas['rightHip'] ?? 0.0;
        adjustedJointDeltas['leftKnee'] =
            adjustedJointDeltas['rightKnee'] ?? 0.0;
        adjustedJointDeltas['leftAnkle'] =
            adjustedJointDeltas['rightAnkle'] ?? 0.0;
        adjustedJointDeltas['leftShoulder'] =
            adjustedJointDeltas['rightShoulder'] ?? 0.0;
        adjustedJointDeltas['leftElbow'] =
            adjustedJointDeltas['rightElbow'] ?? 0.0;

        adjustedVisibilityMap['leftHip'] =
            adjustedVisibilityMap['rightHip'] ?? 0.0;
        adjustedVisibilityMap['leftKnee'] =
            adjustedVisibilityMap['rightKnee'] ?? 0.0;
        adjustedVisibilityMap['leftAnkle'] =
            adjustedVisibilityMap['rightAnkle'] ?? 0.0;
        adjustedVisibilityMap['leftShoulder'] =
            adjustedVisibilityMap['rightShoulder'] ?? 0.0;
        adjustedVisibilityMap['leftElbow'] =
            adjustedVisibilityMap['rightElbow'] ?? 0.0;

        adjustedJointVariances['leftHip'] =
            adjustedJointVariances['rightHip'] ?? 0.0;
        adjustedJointVariances['leftKnee'] =
            adjustedJointVariances['rightKnee'] ?? 0.0;
        adjustedJointVariances['leftAnkle'] =
            adjustedJointVariances['rightAnkle'] ?? 0.0;
        adjustedJointVariances['leftShoulder'] =
            adjustedJointVariances['rightShoulder'] ?? 0.0;
        adjustedJointVariances['leftElbow'] =
            adjustedJointVariances['rightElbow'] ?? 0.0;

        adjustedJointVelocities['leftHip'] =
            adjustedJointVelocities['rightHip'] ?? 0.0;
        adjustedJointVelocities['leftKnee'] =
            adjustedJointVelocities['rightKnee'] ?? 0.0;
        adjustedJointVelocities['leftAnkle'] =
            adjustedJointVelocities['rightAnkle'] ?? 0.0;
        adjustedJointVelocities['leftShoulder'] =
            adjustedJointVelocities['rightShoulder'] ?? 0.0;
        adjustedJointVelocities['leftElbow'] =
            adjustedJointVelocities['rightElbow'] ?? 0.0;
      }
    }

    // 1. 관절 기여도 계산 (Quantity)
    final contributions = _calculateJointContribution(
      adjustedJointDeltas, // 미러링된 데이터 사용
      adjustedVisibilityMap, // 미러링된 데이터 사용
      targetArea,
    );

    // [New] JBJ 수치 보정 계수 계산 (텍스트 없음, 오직 숫자)
    final jbjFactors = _calculateJBJFactors(
      adjustedJointDeltas, // 미러링된 데이터 사용
      targetArea.toUpperCase(),
    );

    // 2. 관절별 품질 평가 (JBJ 수치 적용)
    final qualities = <String, double>{};
    for (final key in adjustedJointDeltas.keys) {
      // 미러링된 데이터 사용
      // 기본 품질 점수 계산
      double baseQuality = _evaluateMovementQuality(
        key,
        adjustedJointDeltas[key] ?? 0.0, // 미러링된 데이터 사용
        adjustedJointVariances[key] ?? 0.0, // 미러링된 데이터 사용
        adjustedJointVelocities[key] ?? 0.0, // 미러링된 데이터 사용
        duration,
        motionType.toUpperCase(),
      );

      // JBJ Factor 곱하기 (단순 수치 보정)
      // 이웃 관절이 잘 움직였으면 점수 UP, 아니면 DOWN
      double jbjMultiplier = jbjFactors[key] ?? 1.0;

      qualities[key] = (baseQuality * jbjMultiplier).clamp(0.0, 100.0);
    }

    // [Step 2.5] 복합 관절 시너지 계산
    final synergy = _calculateCompoundSynergy(
      adjustedJointDeltas, // 미러링된 데이터 사용
      targetArea.toUpperCase(),
      averageRhythmScore, // 앵커링 효과 확인용
      jbjFactors, // JBJ 기반 협응도
      adjustedJointVariances, // 허리 떨림 확인용
    );

    // 3. 근육 점수 매핑 (Mapping)
    final muscleScores = _mapToMuscles(
      contributions,
      qualities,
      averageRhythmScore,
      motionType.toUpperCase(),
      targetArea,
      adjustedJointDeltas, // 미러링된 데이터 사용
      adjustedJointVariances, // 미러링된 데이터 사용
      synergy, // [New] 복합 관절 시너지 계수
    );

    // 4. 정렬 (그룹핑 정렬 로직 적용)
    // 로직: 같은 근육(예: 대퇴사두)의 좌/우를 묶고, 그룹 내 최고점을 기준으로 그룹 간 순서를 정함.

    // 4-1. 그룹핑 (좌/우 제거한 이름 기준)
    final grouped = <String, List<MapEntry<String, double>>>{};
    for (var entry in muscleScores.entries) {
      // 'left_', 'right_' 등 접두어를 제거하여 baseName 추출 (대소문자/언더스코어 모두 처리)
      String baseName = entry.key
          .toLowerCase()
          .replaceFirst('left_', '')
          .replaceFirst('right_', '')
          .replaceFirst('left', '')
          .replaceFirst('right', '')
          .trim(); // 공백 제거

      grouped.putIfAbsent(baseName, () => []).add(entry);
    }

    // 4-2. 그룹별 최고점 계산 및 그룹 정렬 (내림차순)
    var sortedBaseNames = grouped.keys.toList();
    sortedBaseNames.sort((a, b) {
      // 각 그룹의 최고 점수 찾기
      double maxA = grouped[a]!.map((e) => e.value).reduce(math.max);
      double maxB = grouped[b]!.map((e) => e.value).reduce(math.max);
      return maxB.compareTo(maxA);
    });

    // 4-3. 최종 리스트 생성 (그룹 순서대로, 그룹 내에서는 점수 높은 순)
    final sortedEntries = <MapEntry<String, double>>[];
    for (var baseName in sortedBaseNames) {
      var entries = grouped[baseName]!;
      // 그룹 내에서도 내림차순 (예: 왼쪽 60, 오른쪽 50이면 왼쪽이 위로)
      entries.sort((a, b) => b.value.compareTo(a.value));
      sortedEntries.addAll(entries);
    }

    // 5. 등척성 경고 메시지
    String stabilityWarning = "";
    if (motionType.toUpperCase() == 'ISOMETRIC') {
      double spineVar = jointVariances['spine'] ?? 0.0;
      if (spineVar > 5.0) {
        stabilityWarning = "허리(요추)의 흔들림이 감지되었습니다. 코어에 더 집중하세요.";
      }
    }

    // [수정] 관절 데이터(rom_data) 생성 로직
    // 전략: 가장 많이 움직인 관절을 100% 기준으로 삼는 '상대적 강도' 방식
    final displayJointData = <String, double>{};

    // 1. 최대 움직임 값 찾기 (Spine 제외)
    double maxDelta = 0.0;
    adjustedJointDeltas.forEach((k, v) {
      if (k != 'spine' && v > maxDelta) maxDelta = v;
    });

    // 2. 안전장치: 최대 움직임이 10도 미만이면 분석 결과 없음 (노이즈)
    if (maxDelta >= 10.0) {
      adjustedJointDeltas.forEach((k, v) {
        if (k == 'spine') return; // 기립근은 관절 탭 제외

        double relativeScore = (v / maxDelta * 100.0);

        // 10% 미만은 주동 관절이 아니라고 판단하여 제외
        if (relativeScore >= 10.0) {
          displayJointData[k] = relativeScore;
        }
      });
    }
    // maxDelta < 10.0이면 displayJointData는 빈 맵으로 반환됨

    return {
      'detailed_muscle_usage': sanitizeOutputMap(
        Map.fromEntries(sortedEntries),
      ),
      'rom_data': sanitizeOutputMap(displayJointData), // 이제 여기엔 %가 들어감
      'biomech_pattern': targetArea,
      'stability_warning': stabilityWarning,
    };
  }
}
