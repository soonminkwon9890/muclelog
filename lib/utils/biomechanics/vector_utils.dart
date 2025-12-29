import 'dart:math' as math;
import 'point_3d.dart';

/// 벡터 유틸리티 클래스
/// 
/// 3D 좌표의 정규화 및 스케일 팩터 계산을 담당합니다.
/// 사람의 크기와 무관하게 좌표를 정규화하여 분석 정확도를 향상시킵니다.
class VectorUtils {
  /// 스케일 팩터 계산
  /// 
  /// 정규화를 위해 사용할 스케일 값을 계산합니다.
  /// 측면 뷰와 정면 뷰 모두에서 안정적으로 작동하도록 설계되었습니다.
  /// 
  /// **로직:**
  /// 1. 척추 길이(Spine Length)를 메인 스케일로 사용 (측면 뷰 대응)
  ///    - midShoulder = (LeftShoulder + RightShoulder) / 2
  ///    - midHip = (LeftHip + RightHip) / 2
  ///    - spineLength = midShoulder.distanceTo(midHip)
  /// 2. 어깨 너비(Shoulder Width)를 보조 기준으로 사용 (정면 뷰)
  ///    - shoulderWidth = LeftShoulder.distanceTo(RightShoulder)
  /// 3. 둘 중 더 큰 값을 스케일 팩터로 사용
  ///    - 측면 뷰일 때는 척추 길이, 정면 뷰일 때는 어깨/척추 중 큰 값 사용
  ///    - 어깨 너비만 사용하면 측면 뷰에서 0에 가까워져 정규화가 깨지는 문제 해결
  static double getScaleFactor(Map<String, Point3D> landmarks) {
    // 필수 랜드마크 확인
    final leftShoulder = landmarks['left_shoulder'];
    final rightShoulder = landmarks['right_shoulder'];
    final leftHip = landmarks['left_hip'];
    final rightHip = landmarks['right_hip'];

    if (leftShoulder == null ||
        rightShoulder == null ||
        leftHip == null ||
        rightHip == null) {
      // 필수 랜드마크가 없으면 기본값 반환 (정규화 불가능)
      return 1.0;
    }

    // 1. 척추 길이 계산
    final midShoulder = leftShoulder.midpoint(rightShoulder);
    final midHip = leftHip.midpoint(rightHip);
    final spineLength = midShoulder.distanceTo(midHip);

    // 2. 어깨 너비 계산
    final shoulderWidth = leftShoulder.distanceTo(rightShoulder);

    // 3. 둘 중 더 큰 값을 스케일 팩터로 사용
    return math.max(spineLength, shoulderWidth);
  }

  /// 랜드마크 정규화
  /// 
  /// 모든 랜드마크 좌표를 스케일 팩터로 나누어 정규화합니다.
  /// 사람의 크기와 무관하게 동일한 스케일로 좌표를 변환합니다.
  /// 
  /// **주의:** visibility는 유지됩니다 (가시성 정보는 정규화하지 않음)
  static Map<String, Point3D> normalizeLandmarks(
    Map<String, Point3D> landmarks,
  ) {
    final scaleFactor = getScaleFactor(landmarks);

    // 스케일 팩터가 0이거나 너무 작으면 정규화하지 않음
    if (scaleFactor <= 0.0 || scaleFactor < 0.01) {
      return Map<String, Point3D>.from(landmarks);
    }

    final normalized = <String, Point3D>{};

    for (final entry in landmarks.entries) {
      final key = entry.key;
      final point = entry.value;

      normalized[key] = Point3D(
        x: point.x / scaleFactor,
        y: point.y / scaleFactor,
        z: point.z / scaleFactor,
        visibility: point.visibility, // visibility는 유지
      );
    }

    return normalized;
  }

  /// 세 점으로 구성된 각도 계산
  /// 
  /// 세 점(a, b, c)으로 구성된 각도를 계산합니다.
  /// b가 꼭짓점, a와 c가 양쪽 끝점입니다.
  /// 
  /// **공식:** $\theta = \arccos(\frac{\vec{BA} \cdot \vec{BC}}{|\vec{BA}| |\vec{BC}|})$
  /// 
  /// **반환값:** 0 ~ π (라디안) 범위의 각도
  static double calculateAngle(Point3D a, Point3D b, Point3D c) {
    // 벡터 BA = a - b, 벡터 BC = c - b
    final ba = a.subtract(b);
    final bc = c.subtract(b);
    
    // Dot product 계산
    final dot = ba.dot(bc);
    
    // 벡터 길이 계산
    final lenBA = math.sqrt(ba.x * ba.x + ba.y * ba.y + ba.z * ba.z);
    final lenBC = math.sqrt(bc.x * bc.x + bc.y * bc.y + bc.z * bc.z);
    
    // 0으로 나누기 방지
    if (lenBA == 0.0 || lenBC == 0.0) {
      return 0.0;
    }
    
    // 코사인 각도 계산
    final cosAngle = dot / (lenBA * lenBC);
    
    // -1 ~ 1 범위로 클램핑 (부동소수점 오차 방지)
    final clampedCos = cosAngle.clamp(-1.0, 1.0);
    
    // arccos를 사용하여 각도 반환 (0 ~ π 라디안)
    return math.acos(clampedCos);
  }
}

