import 'analysis_log.dart' show ExerciseType;

/// 운동 부위 Enum
enum BodyPart {
  /// 상체 (Upper Body)
  upperBody('upper_body'),

  /// 하체 (Lower Body)
  lowerBody('lower_body'),

  /// 전신 (Full Body)
  fullBody('full_body');

  final String value;
  const BodyPart(this.value);

  /// 문자열에서 BodyPart로 변환
  static BodyPart fromString(String? value) {
    if (value == null) return BodyPart.fullBody;
    switch (value.toLowerCase()) {
      case 'upper_body':
      case 'upper':
      case '상체':
        return BodyPart.upperBody;
      case 'lower_body':
      case 'lower':
      case '하체':
        return BodyPart.lowerBody;
      case 'full_body':
      case 'full':
      case '전신':
        return BodyPart.fullBody;
      default:
        return BodyPart.fullBody;
    }
  }

  /// 한글 표시명 반환
  String get displayName {
    switch (this) {
      case BodyPart.upperBody:
        return '상체';
      case BodyPart.lowerBody:
        return '하체';
      case BodyPart.fullBody:
        return '전신';
    }
  }

  /// 이모지 아이콘 반환
  String get emoji {
    switch (this) {
      case BodyPart.upperBody:
        return '💪';
      case BodyPart.lowerBody:
        return '🦵';
      case BodyPart.fullBody:
        return '🧍';
    }
  }

  /// ExerciseType으로 변환 (하위 호환성)
  ExerciseType toExerciseType() {
    switch (this) {
      case BodyPart.upperBody:
        return ExerciseType.upper;
      case BodyPart.lowerBody:
        return ExerciseType.lower;
      case BodyPart.fullBody:
        return ExerciseType.full;
    }
  }
}
