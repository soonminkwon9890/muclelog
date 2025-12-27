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
    scores['left_glutes'] = calc('leftHip', lowerMultiplier);
    scores['right_glutes'] = calc('rightHip', lowerMultiplier);
    scores['left_hamstrings'] =
        (calc('leftHip', lowerMultiplier) * 0.5 +
        calc('leftKnee', lowerMultiplier) * 0.5);
    scores['right_hamstrings'] =
        (calc('rightHip', lowerMultiplier) * 0.5 +
        calc('rightKnee', lowerMultiplier) * 0.5);

    // --- 상체 근육 ---
    double shoulderLeftRaw = calc('leftShoulder', upperMultiplier);
    double shoulderRightRaw = calc('rightShoulder', upperMultiplier);

    double trapFactor = (1.0 - rhythmScore).clamp(0.0, 1.0);
    scores['trapezius'] =
        ((shoulderLeftRaw + shoulderRightRaw) * trapFactor * 1.5).clamp(
          0.0,
          100.0,
        );

    double latsFactor = rhythmScore;

    scores['left_latissimus'] = (shoulderLeftRaw * latsFactor).clamp(
      0.0,
      100.0,
    );
    scores['right_latissimus'] = (shoulderRightRaw * latsFactor).clamp(
      0.0,
      100.0,
    );
    scores['left_pectorals'] = (shoulderLeftRaw * latsFactor * 0.9).clamp(
      0.0,
      100.0,
    );
    scores['right_pectorals'] = (shoulderRightRaw * latsFactor * 0.9).clamp(
      0.0,
      100.0,
    );
    scores['left_deltoids'] = shoulderLeftRaw;
    scores['right_deltoids'] = shoulderRightRaw;

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
    // 1. 관절 기여도 계산 (Quantity)
    final contributions = _calculateJointContribution(
      jointDeltas,
      visibilityMap,
      targetArea,
    );

    // 2. 관절별 품질 평가 (Quality)
    final qualities = <String, double>{};
    for (final key in jointDeltas.keys) {
      double quality = _evaluateMovementQuality(
        key,
        jointDeltas[key] ?? 0.0,
        jointVariances[key] ?? 0.0,
        jointVelocities[key] ?? 0.0,
        duration,
        motionType.toUpperCase(),
      );
      qualities[key] = quality;
    }

    // 3. 근육 점수 매핑 (Mapping)
    final muscleScores = _mapToMuscles(
      contributions,
      qualities,
      averageRhythmScore,
      motionType.toUpperCase(),
      targetArea,
      jointDeltas,
      jointVariances,
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

    // UI 표시용 ROM 데이터
    final displayRomData = <String, double>{};
    jointDeltas.forEach((k, v) {
      double contrib = contributions[k] ?? 0.0;
      displayRomData[k] = contrib > 0.01 ? v : 0.0;
    });

    return {
      'detailed_muscle_usage': sanitizeOutputMap(
        Map.fromEntries(sortedEntries),
      ),
      'rom_data': sanitizeOutputMap(displayRomData),
      'biomech_pattern': targetArea,
      'stability_warning': stabilityWarning,
    };
  }
}
