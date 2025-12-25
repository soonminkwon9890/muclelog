// 파일 경로: lib/utils/muscle_name_mapper.dart

class MuscleNameMapper {
  // 1. 근육명 매핑 테이블 (여기에만 존재해야 함)
  static const Map<String, String> _muscleMap = {
    // 상체
    'trapezius': '승모근', 'traps': '승모근',
    'deltoid': '삼각근', 'lateraldeltoid': '삼각근', 'anteriordeltoid': '삼각근',
    'latissimusdorsi': '광배근', 'lats': '광배근', 'lat': '광배근',
    'pectoralis': '대흉근', 'pectoralisupper': '대흉근(상부)',
    'pectoralissternal': '대흉근(중부)', 'pectoraliscostal': '대흉근(하부)', 'pec': '대흉근',
    'biceps': '이두근', 'triceps': '삼두근',
    // 하체
    'gluteus': '대둔근', 'glutes': '대둔근', 'glute': '대둔근',
    'quadriceps': '대퇴사두근', 'quads': '대퇴사두근', 'quad': '대퇴사두근',
    'hamstrings': '햄스트링', 'hamstring': '햄스트링',
    'erectorspinae': '기립근', 'erector': '기립근', 'spine': '기립근',
    // 기타
    'thigh': '허벅지', 'calf': '종아리', 'abs': '복근', 'core': '코어',
  };

  // 2. 근육 키워드 목록 (필터링용)
  static const List<String> muscleKeywords = [
    // 상체 근육
    'trapezius', 'traps',
    'deltoid', 'lateral_deltoid', 'anterior_deltoid',
    'latissimus_dorsi', 'lats', 'lat',
    'pectoralis',
    'pectoralis_upper',
    'pectoralis_sternal',
    'pectoralis_costal',
    'pec',
    'biceps', 'triceps',
    // 하체 근육
    'gluteus', 'glutes', 'glute',
    'quadriceps', 'quads', 'quad',
    'hamstrings', 'hamstring',
    'erector_spinae', 'erector', 'spine',
  ];

  // 3. 관절 데이터 매핑 테이블
  static const Map<String, String> jointMappingTable = {
    // 좌우 구분 관절
    'left_hip': '왼쪽 고관절',
    'right_hip': '오른쪽 고관절',
    'left_knee': '왼쪽 무릎',
    'right_knee': '오른쪽 무릎',
    'left_ankle': '왼쪽 발목',
    'right_ankle': '오른쪽 발목',
    'left_shoulder': '왼쪽 어깨',
    'right_shoulder': '오른쪽 어깨',
    'left_elbow': '왼쪽 팔꿈치',
    'right_elbow': '오른쪽 팔꿈치',
    'left_wrist': '왼쪽 손목',
    'right_wrist': '오른쪽 손목',
    // 기본 관절 키 (hip_L, knee_R 등 처리용)
    'hip': '고관절',
    'knee': '무릎',
    'ankle': '발목',
    'shoulder': '어깨',
    'elbow': '팔꿈치',
    'wrist': '손목',
    // 기존 관절 키 (하위 호환성)
    'neck': '경추',
    'spine': '척추',
  };

  // 4. 근육명 한글화 (외부에서 이걸 호출)
  static String localize(String englishKey) {
    if (englishKey.isEmpty) return "-";

    // 소문자 변환
    final lowerKey = englishKey.toLowerCase();

    // 1. left/right 접두어 추출 및 제거
    String prefix = '';
    String remainingKey = lowerKey;

    if (remainingKey.contains('left')) {
      prefix = '왼쪽 ';
      remainingKey = remainingKey.replaceAll('left', '');
    } else if (remainingKey.contains('right')) {
      prefix = '오른쪽 ';
      remainingKey = remainingKey.replaceAll('right', '');
    }

    // 2. 남은 문자열에서 _와 공백 제거하여 순수한 근육명 키 추출
    final normalizedKey = remainingKey
        .replaceAll('_', '')
        .replaceAll(' ', '')
        .trim();

    // 3. _muscleMap에서 해당 키를 찾아, 찾으면 "접두어 + 한글명" 반환
    final koreanName = _muscleMap[normalizedKey];
    if (koreanName != null) {
      return prefix + koreanName;
    }

    // 4. 못 찾으면 원래 englishKey 반환
    return englishKey;
  }

  // 5. 관절명 한글화 (muscle_joint_mapper에서 통합)
  /// 🔧 hip_L, knee_R 같은 형식도 처리
  static String getJointDisplayName(String jointKey) {
    if (jointKey.isEmpty) return "-";

    final lowerKey = jointKey.toLowerCase();

    // 1. 직접 매핑 확인 (left_hip, right_knee 등)
    final directMatch = jointMappingTable[lowerKey];
    if (directMatch != null) {
      return directMatch;
    }

    // 2. hip_L, knee_R 같은 형식 처리
    // 패턴: {joint}_{L|R} 또는 {joint}_{left|right}
    String? jointName;
    String? side;

    // _L 또는 _R로 끝나는 경우
    if (lowerKey.endsWith('_l') || lowerKey.endsWith('_left')) {
      side = '왼쪽 ';
      jointName = lowerKey.replaceAll(RegExp(r'_l$|_left$'), '');
    } else if (lowerKey.endsWith('_r') || lowerKey.endsWith('_right')) {
      side = '오른쪽 ';
      jointName = lowerKey.replaceAll(RegExp(r'_r$|_right$'), '');
    } else {
      // 접두어가 있는 경우 (left_hip, right_knee)
      if (lowerKey.startsWith('left_')) {
        side = '왼쪽 ';
        jointName = lowerKey.replaceAll('left_', '');
      } else if (lowerKey.startsWith('right_')) {
        side = '오른쪽 ';
        jointName = lowerKey.replaceAll('right_', '');
      } else {
        jointName = lowerKey;
      }
    }

    // 3. 관절명 매핑 확인
    final koreanJointName = jointMappingTable[jointName];
    if (koreanJointName != null) {
      return side != null ? side + koreanJointName : koreanJointName;
    }

    // 4. 매핑 없으면 원본 반환
    return jointKey;
  }

  // 6. 근육인지 확인 (muscle_joint_mapper에서 통합)
  static bool isMuscle(String key) {
    final lowerKey = key.toLowerCase();
    return muscleKeywords.any(
      (muscleKey) => lowerKey.contains(muscleKey.toLowerCase()),
    );
  }

  // 7. 관절인지 확인 (muscle_joint_mapper에서 통합)
  static bool isJoint(String key) {
    final lowerKey = key.toLowerCase();
    return jointMappingTable.containsKey(lowerKey) ||
        [
          'neck',
          'shoulder',
          'elbow',
          'wrist',
          'spine',
          'hip',
          'knee',
          'ankle',
        ].any((jointKey) => lowerKey.contains(jointKey));
  }

  // 8. 근육 데이터만 필터링 (muscle_joint_mapper에서 통합)
  static Map<String, dynamic> filterMuscles(Map<String, dynamic> data) {
    final filtered = <String, dynamic>{};
    for (final entry in data.entries) {
      if (isMuscle(entry.key)) {
        filtered[entry.key] = entry.value;
      }
    }
    return filtered;
  }

  // 9. 관절 데이터만 필터링 (muscle_joint_mapper에서 통합)
  static Map<String, dynamic> filterJoints(Map<String, dynamic> data) {
    final filtered = <String, dynamic>{};
    for (final entry in data.entries) {
      if (isJoint(entry.key)) {
        filtered[entry.key] = entry.value;
      }
    }
    return filtered;
  }
}
