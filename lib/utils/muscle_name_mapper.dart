class MuscleNameMapper {
  // 1. 핵심 단어 사전 (순수 부위명 -> 한글)
  static const Map<String, String> _dictionary = {
    // [관절]
    'hip': '고관절', 'knee': '무릎', 'ankle': '발목',
    'shoulder': '어깨', 'elbow': '팔꿈치', 'wrist': '손목',
    'neck': '목', 'head': '머리',
    // [근육 - 하체]
    'quadriceps': '대퇴사두근', 'quad': '대퇴사두근', 'quads': '대퇴사두근',
    'hamstrings': '햄스트링', 'hamstring': '햄스트링',
    'gluteus': '둔근', 'glutes': '둔근', 'glute': '둔근',
    'calf': '종아리', 'calves': '종아리',
    // [근육 - 상체]
    'trapezius': '승모근', 'traps': '승모근',
    'latissimus': '광배근', 'latissimusdorsi': '광배근', 'lats': '광배근',
    'erectorspinae': '기립근', 'erector': '기립근', 'spine': '기립근', // 근육 context에선 기립근
    'pectoralis': '대흉근', 'pectorals': '대흉근', 'pecs': '대흉근', 'chest': '대흉근',
    'deltoids': '삼각근', 'deltoid': '삼각근',
    'biceps': '이두근', 'triceps': '삼두근',
    'core': '코어', 'abs': '복근',
  };

  // 2. 통합 번역 함수
  static String localize(String key) {
    if (key.isEmpty) return "-";
    
    // 전처리: 소문자 변환 및 공백 제거 준비
    String normalized = key.trim().toLowerCase();
    String prefix = "";

    // 방향(Side) 추출 로직 (다양한 케이스 대응)
    // 예: leftHip, left_hip, hip_L, Left Hip
    if (normalized.contains('left') || normalized.endsWith('_l')) {
      prefix = "왼쪽 ";
      normalized = normalized.replaceAll('left', '').replaceAll('_l', '');
    } else if (normalized.contains('right') || normalized.endsWith('_r')) {
      prefix = "오른쪽 ";
      normalized = normalized.replaceAll('right', '').replaceAll('_r', '');
    }

    // 잔여 특수문자 제거 (_ , - , 공백, 숫자)
    normalized = normalized.replaceAll(RegExp(r'[_\-\s0-9]'), '');

    // 사전 매핑 시도
    String? name = _dictionary[normalized];
    
    // 매핑 성공 시: "왼쪽 " + "고관절" 리턴
    if (name != null) return "$prefix$name";
    
    // 매핑 실패 시: 원본 키를 깔끔하게 다듬어서 리턴 (디버깅용)
    return key; 
  }
}