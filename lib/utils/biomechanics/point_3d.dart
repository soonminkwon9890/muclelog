import 'dart:math' as math;

/// 3D 좌표 및 가시성을 나타내는 클래스
/// 
/// MediaPipe PoseLandmark를 Point3D로 변환하여
/// 벡터 연산 및 정규화 처리에 사용됩니다.
class Point3D {
  final double x;
  final double y;
  final double z;
  final double visibility; // 0.0 ~ 1.0 (가시성 신뢰도)

  const Point3D({
    required this.x,
    required this.y,
    required this.z,
    required this.visibility,
  });

  /// MediaPipe PoseLandmark로부터 Point3D 생성
  /// 
  /// MediaPipe의 PoseLandmark는 x, y, z, likelihood 속성을 가지고 있으며,
  /// likelihood를 visibility로 사용합니다.
  factory Point3D.fromPoseLandmark(dynamic landmark) {
    return Point3D(
      x: landmark.x.toDouble(),
      y: landmark.y.toDouble(),
      z: landmark.z?.toDouble() ?? 0.0,
      visibility: landmark.likelihood?.toDouble() ?? 0.0,
    );
  }

  /// 두 점 사이의 유클리드 거리 계산
  double distanceTo(Point3D other) {
    final dx = x - other.x;
    final dy = y - other.y;
    final dz = z - other.z;
    return math.sqrt(dx * dx + dy * dy + dz * dz);
  }

  /// 벡터 뺄셈 (this - other)
  Point3D subtract(Point3D other) {
    return Point3D(
      x: x - other.x,
      y: y - other.y,
      z: z - other.z,
      visibility: visibility, // visibility는 유지
    );
  }

  /// 벡터 덧셈 (this + other)
  Point3D add(Point3D other) {
    return Point3D(
      x: x + other.x,
      y: y + other.y,
      z: z + other.z,
      visibility: visibility, // visibility는 유지
    );
  }

  /// 스칼라 곱
  Point3D multiply(double factor) {
    return Point3D(
      x: x * factor,
      y: y * factor,
      z: z * factor,
      visibility: visibility,
    );
  }

  /// 단위 벡터 반환 (정규화)
  Point3D normalize() {
    final length = distanceTo(const Point3D(x: 0, y: 0, z: 0, visibility: 0));
    if (length == 0.0) {
      return this;
    }
    return multiply(1.0 / length);
  }

  /// 내적(Dot Product) 계산
  double dot(Point3D other) {
    return x * other.x + y * other.y + z * other.z;
  }

  /// 두 점의 중점 반환
  Point3D midpoint(Point3D other) {
    return Point3D(
      x: (x + other.x) / 2.0,
      y: (y + other.y) / 2.0,
      z: (z + other.z) / 2.0,
      visibility: (visibility + other.visibility) / 2.0,
    );
  }

  /// 선형 보간 (Linear Interpolation)
  /// 
  /// t는 0.0 ~ 1.0 사이의 값
  /// t=0.0일 때 a 반환, t=1.0일 때 b 반환
  /// 노이즈 제거 및 부드러운 전환에 사용
  static Point3D lerp(Point3D a, Point3D b, double t) {
    // t를 0.0~1.0 범위로 클램핑
    final clampedT = t.clamp(0.0, 1.0);
    
    return Point3D(
      x: a.x + (b.x - a.x) * clampedT,
      y: a.y + (b.y - a.y) * clampedT,
      z: a.z + (b.z - a.z) * clampedT,
      visibility: a.visibility + (b.visibility - a.visibility) * clampedT,
    );
  }

  @override
  String toString() {
    return 'Point3D(x: $x, y: $y, z: $z, visibility: $visibility)';
  }
}

