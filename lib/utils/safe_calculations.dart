/// 안전한 수치 계산 유틸리티
/// NaN, Infinity, 0으로 나누기 등의 예외 상황을 처리합니다.
class SafeCalculations {
  /// 안전한 나눗셈
  /// 분모가 0이거나 NaN/Infinity면 0.0을 반환합니다.
  static double safeDivide(double a, double b) {
    if (b == 0.0 || b.isNaN || b.isInfinite) {
      return 0.0;
    }
    if (a.isNaN || a.isInfinite) {
      return 0.0;
    }
    final result = a / b;
    if (result.isNaN || result.isInfinite) {
      return 0.0;
    }
    return result;
  }

  /// 안전한 Clamp
  /// NaN/Infinity를 체크한 후 clamp를 적용합니다.
  static double safeClamp(double value, double min, double max) {
    if (value.isNaN || value.isInfinite) {
      return min.clamp(min, max);
    }
    return value.clamp(min, max);
  }

  /// Double 값 정제
  /// NaN/Infinity를 0.0으로 치환합니다.
  static double sanitizeDouble(double value) {
    if (value.isNaN || value.isInfinite) {
      return 0.0;
    }
    return value;
  }

  /// 안전한 퍼센트 계산
  /// 0~100 범위로 clamp된 퍼센트 값을 반환합니다.
  static double safePercent(double value) {
    final sanitized = sanitizeDouble(value);
    return sanitized.clamp(0.0, 100.0);
  }

  /// 안전한 Progress Indicator Value
  /// 0.0~1.0 범위로 clamp된 값을 반환합니다.
  static double safeProgressValue(double value) {
    final sanitized = sanitizeDouble(value);
    return sanitized.clamp(0.0, 1.0);
  }

  /// 안전한 퍼센트를 Progress Value로 변환
  /// 퍼센트(0~100)를 Progress Indicator value(0.0~1.0)로 변환합니다.
  static double percentToProgress(double percent) {
    final sanitized = sanitizeDouble(percent);
    return safeDivide(sanitized, 100.0).clamp(0.0, 1.0);
  }

  /// 값이 0.0인 경우 "-"로 표시 (데이터 없음 vs 실제 0% 구분)
  /// [value] 표시할 값
  /// [decimalPlaces] 소수점 자릿수
  /// 반환: 값이 0.0이면 "-", 아니면 포맷된 문자열
  static String formatValueOrNA(double value, {int decimalPlaces = 1}) {
    if (value == 0.0 || value.isNaN || value.isInfinite) {
      return '-';
    }
    return value.toStringAsFixed(decimalPlaces);
  }

  /// 퍼센트 값 포맷팅 (0.0%는 "-"로 표시)
  static String formatPercentOrNA(double percent, {int decimalPlaces = 1}) {
    if (percent == 0.0 || percent.isNaN || percent.isInfinite) {
      return '-';
    }
    return '${percent.toStringAsFixed(decimalPlaces)}%';
  }
}
