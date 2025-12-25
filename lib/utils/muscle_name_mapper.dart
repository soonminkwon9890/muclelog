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
    'neck': '경추',
    'shoulder': '견관절',
    'elbow': '주관절',
    'wrist': '수근관절',
    'spine': '척추',
    'hip': '고관절',
    'knee': '슬관절',
    'ankle': '족관절',
  };

  // 4. 근육명 한글화 (외부에서 이걸 호출)
  static String localize(String englishKey) {
    if (englishKey.isEmpty) return "-";

    // 소문자 변환 및 _ 제거 (검색 확률 높이기)
    final normalizedKey = englishKey
        .toLowerCase()
        .replaceAll('_', '')
        .replaceAll(' ', '')
        .trim();

    // 맵에서 찾고, 없으면 원래 영어 키 반환
    return _muscleMap[normalizedKey] ?? englishKey;
  }

  // 5. 관절명 한글화 (muscle_joint_mapper에서 통합)
  static String getJointDisplayName(String jointKey) {
    final lowerKey = jointKey.toLowerCase();
    return jointMappingTable[lowerKey] ?? jointKey; // 매핑 없으면 원본 반환
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
