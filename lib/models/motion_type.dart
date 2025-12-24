/// 운동 방식 타입 Enum
/// 운동의 생체역학적 특성에 따라 분류합니다.
enum MotionType {
  /// 등장성 운동 (Isotonic)
  /// 관절 각도가 변하며 근육 길이가 변하는 운동
  /// 예: 스쿼트, 팔굽혀펴기, 덤벨 컬
  isotonic('isotonic'),

  /// 등척성 운동 (Isometric)
  /// 관절 각도가 고정되고 근육 길이가 변하지 않는 운동
  /// 예: 플랭크, 월 시트, 홀드 자세
  isometric('isometric'),

  /// 등속성 운동 (Isokinetic)
  /// 일정한 속도로 움직이는 운동
  /// 예: 등속성 운동 기구 사용
  isokinetic('isokinetic');

  final String value;
  const MotionType(this.value);

  /// 문자열에서 MotionType으로 변환
  static MotionType fromString(String? value) {
    if (value == null) return MotionType.isotonic;
    switch (value.toLowerCase()) {
      case 'isotonic':
      case '등장성':
        return MotionType.isotonic;
      case 'isometric':
      case '등척성':
        return MotionType.isometric;
      case 'isokinetic':
      case '등속성':
        return MotionType.isokinetic;
      default:
        return MotionType.isotonic;
    }
  }

  /// 한글 표시명 반환
  String get displayName {
    switch (this) {
      case MotionType.isotonic:
        return '등장성';
      case MotionType.isometric:
        return '등척성';
      case MotionType.isokinetic:
        return '등속성';
    }
  }

  /// 영어 표시명 반환
  String get englishName {
    switch (this) {
      case MotionType.isotonic:
        return 'Isotonic';
      case MotionType.isometric:
        return 'Isometric';
      case MotionType.isokinetic:
        return 'Isokinetic';
    }
  }
}
