// ignore_for_file: constant_identifier_names

import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// 관절 컨트롤러 클래스
///
/// 물리 모델을 기반으로 관절 스트레스를 계산합니다.
///
/// **물리 모델 구성 요소:**
/// - 마찰력 (Friction): Stribeck Effect 적용
/// - 소프트 리미트 (Soft Limit): 관절 가동 범위 초과 시 반발력
/// - 모멘트 암 (Moment Arm): 각도에 따른 근육 효율
/// - 점성 댐핑 (Damping): 회전 속도에 비례한 저항
class JointController {
  /// 관절 가동 범위 (Radian)
  final double angleMin;
  final double angleMax;

  /// 한계 각도 초과 시 반발하는 스프링 강도
  final double stiffness;

  /// 회전 속도에 비례한 저항 계수 (점성 댐핑)
  final double dampingCoefficient;

  /// 정지 상태 마찰력
  final double staticFriction;

  /// 운동 마찰력
  final double kineticFriction;

  /// 각도에 따른 모멘트 암 변화율 (선택적)
  final Map<double, double>? momentArmTable;

  /// 큰 근육 개입 판단 임계값 (0.0~1.0 정규화된 값 기준)
  /// 어깨 스트레스 30점(0.3) 이상이면 개입으로 간주
  final double bigMuscleThreshold;

  /// 큰 근육 개입 시 적용할 높은 Damping (충격 흡수 및 덜렁거림 방지)
  final double safetyDamping;

  /// 절대 안전을 위한 최대 토크 제한
  final double maxTorqueLimit;

  /// Epsilon 값 (0 근처 진동 방지)
  static const double _epsilon = 1e-6;

  /// Sigmoid 정규화 기준값
  ///
  /// Joint Stress Score 계산 시 Sigmoid 함수에서 사용하는 기준 토크 값입니다.
  /// 이 값을 기준으로 점수가 0.0~1.0 범위로 정규화됩니다.
  static const double REFERENCE_MAX_TORQUE = 60.0;

  const JointController({
    required this.angleMin,
    required this.angleMax,
    required this.stiffness,
    required this.dampingCoefficient,
    required this.staticFriction,
    required this.kineticFriction,
    this.momentArmTable,
    this.bigMuscleThreshold = 0.3, // 어깨 스트레스 30점 이상이면 개입으로 간주
    this.safetyDamping = 8.0, // 큰 근육 개입 시 높은 Damping
    this.maxTorqueLimit = 20.0, // 절대 안전 한계치
  });

  /// Degree를 Radian으로 변환하여 생성
  factory JointController.fromDegrees({
    required double angleMinDegrees,
    required double angleMaxDegrees,
    required double stiffness,
    required double dampingCoefficient,
    required double staticFriction,
    required double kineticFriction,
    Map<double, double>? momentArmTable,
    double bigMuscleThreshold = 0.3, // 어깨 스트레스 30점 이상이면 개입으로 간주
    double safetyDamping = 8.0, // 큰 근육 개입 시 높은 Damping
    double maxTorqueLimit = 20.0, // 절대 안전 한계치
  }) {
    return JointController(
      angleMin: angleMinDegrees * math.pi / 180.0,
      angleMax: angleMaxDegrees * math.pi / 180.0,
      stiffness: stiffness,
      dampingCoefficient: dampingCoefficient,
      staticFriction: staticFriction,
      kineticFriction: kineticFriction,
      momentArmTable: momentArmTable,
      bigMuscleThreshold: bigMuscleThreshold,
      safetyDamping: safetyDamping,
      maxTorqueLimit: maxTorqueLimit,
    );
  }

  /// 관절 스트레스 계산
  ///
  /// **Input:**
  /// - `currentAngle`: 현재 관절 각도 (Radian)
  /// - `prevAngle`: 이전 관절 각도 (Radian)
  /// - `dtInSeconds`: 시간 간격 (초)
  /// - `muscleForce`: 근육 힘 (0.0~1.0 범위로 정규화된 값)
  /// - `bigMuscleForce`: 상위 관절에서 들어오는 힘 (0.0~1.0 정규화된 값, 선택적)
  ///
  /// **Output:**
  /// - `stressScore`: 관절 스트레스 점수 (0.0~1.0)
  double calculateJointStress(
    double currentAngle,
    double prevAngle,
    double dtInSeconds,
    double muscleForce, {
    double? bigMuscleForce,
    String? debugName, // ✅ 디버깅용 파라미터 추가
  }) {
    // 1. Damping 결정 (의사결정 로직)
    double effectiveDamping = dampingCoefficient; // 기본값

    if (bigMuscleForce != null && bigMuscleForce.abs() > bigMuscleThreshold) {
      // 큰 근육 개입이 감지되면 Safety Damping 적용
      // 개입 강도(ratio)는 최소 1.0 이상이 됨 (force > threshold 이므로)
      double ratio = bigMuscleForce.abs() / bigMuscleThreshold;

      // 안전장치: 기본 댐핑보다 작아지지 않도록 보장
      // 확실한 억제를 위해 Safety Damping을 최소값으로 보장
      effectiveDamping = math.max(dampingCoefficient, safetyDamping * ratio);

      // ✅ 개입 감지 로그 출력
      if (debugName != null) {
        debugPrint(
          '⚠️ [개입 감지] Joint: $debugName, '
          'Force: ${bigMuscleForce.toStringAsFixed(2)}, '
          'Old Damping: ${dampingCoefficient.toStringAsFixed(2)}, '
          'New Damping: ${effectiveDamping.toStringAsFixed(2)}',
        );
      }
    }
    // 1. dt 클램핑 (Clamping) - 시간 방어 로직
    // 모바일 기기의 성능 저하로 프레임이 튀어서 dt가 갑자기 커지면(예: 0.03초 → 0.5초),
    // angularVelocity가 폭발적으로 증가하여 물리 엔진이 오작동할 수 있음
    // dt가 너무 크거나(렉), 0이면(중복 프레임) 강제로 0.033초(약 30fps 기준)로 보정
    final safeDt = (dtInSeconds <= 0.0 || dtInSeconds > 0.1)
        ? 0.033
        : dtInSeconds;

    // 2. 각속도 계산
    final angularVelocity = (currentAngle - prevAngle) / safeDt;

    // 3. 모멘트 암 계산
    final momentArm = _getMomentArm(currentAngle);

    // 4. 근육 토크 계산
    final muscleTorque = muscleForce * momentArm;

    // 5. 마찰 토크 계산 (결정된 effectiveDamping 사용)
    final frictionTorque = _calculateFriction(
      angularVelocity,
      effectiveDamping,
    );

    // 6. 소프트 리미트 토크 계산
    final limitTorque = _calculateSoftLimitForce(currentAngle);

    // 7. 총 토크 계산
    double totalTorque = muscleTorque + frictionTorque + limitTorque;

    // 7.5. Safety Clamp: 절대 안전 한계치 적용
    // ✅ 토크 제한 로그 출력 (클램핑 전 값이 제한치를 넘었을 때만)
    final absTorqueBeforeClamp = totalTorque.abs();
    if (absTorqueBeforeClamp > maxTorqueLimit) {
      if (debugName != null) {
        debugPrint(
          '🛑 [토크 제한] Joint: $debugName, '
          'Calculated: ${totalTorque.toStringAsFixed(2)}, '
          'Clamped: ${maxTorqueLimit.toStringAsFixed(2)}',
        );
      }
    }
    totalTorque = totalTorque.clamp(-maxTorqueLimit, maxTorqueLimit);

    // 8. 스트레스 점수 정규화 (Sigmoid 함수 사용)
    // Sigmoid 정규화: 점수가 무한히 증가하지 않고 1.0에 점근하도록 함
    // 공식: stressScore = totalTorque.abs() / (totalTorque.abs() + REFERENCE_MAX_TORQUE)
    final absTorque = totalTorque.abs();
    final stressScore = absTorque / (absTorque + REFERENCE_MAX_TORQUE);

    return stressScore.clamp(0.0, 1.0);
  }

  /// 마찰력 계산 (Stribeck Effect 적용)
  ///
  /// 순수 물리 계산만 수행합니다.
  /// - angularVelocity가 매우 작을 때는 staticFriction을 적용
  /// - 움직임이 발생하면 kineticFriction + damping * angularVelocity를 적용
  /// - 속도가 0 근처에서 진동(Jittering)하지 않도록 epsilon 값을 사용하여 0 처리
  /// - `damping` 파라미터: 동적으로 계산된 effectiveDamping 사용
  double _calculateFriction(double angularVelocity, double damping) {
    final absVelocity = angularVelocity.abs();

    if (absVelocity < _epsilon) {
      // 정지 상태: 정지 마찰력
      // 속도가 0이면 마찰력은 0 (움직이지 않으면 마찰 없음)
      return 0.0;
    } else {
      // 운동 상태: 운동 마찰력 + 점성 댐핑
      // 항상 회전 반대 방향으로 작용
      final frictionMagnitude = kineticFriction + (damping * absVelocity);
      return -frictionMagnitude * (angularVelocity / absVelocity);
    }
  }

  /// 소프트 리미트 힘 계산
  ///
  /// 각도가 min이나 max를 넘었을 때,
  /// 넘은 만큼에 비례하여 반대 방향으로 강하게 미는 힘(Restitution Force)을 계산
  ///
  /// 공식: F_limit = k × (θ_current - θ_limit)
  /// 여기서 k는 매우 높은 stiffness 값
  double _calculateSoftLimitForce(double currentAngle) {
    double limitTorque = 0.0;

    // 최소 각도 초과 시
    if (currentAngle < angleMin) {
      final overAngle = angleMin - currentAngle;
      limitTorque = stiffness * overAngle;
    }
    // 최대 각도 초과 시
    else if (currentAngle > angleMax) {
      final overAngle = currentAngle - angleMax;
      limitTorque = -stiffness * overAngle;
    }

    return limitTorque;
  }

  /// 동적 모멘트 암 계산
  ///
  /// 관절 각도에 따라 근육이 힘을 쓰는 효율(레버 암의 길이)이 달라짐을 구현
  ///
  /// - momentArmTable이 있으면 테이블에서 보간하여 반환
  /// - 없으면 간단한 sin(θ) 함수나 보정 계수를 사용하여 동적으로 값을 반환
  double _getMomentArm(double currentAngle) {
    if (momentArmTable != null && momentArmTable!.isNotEmpty) {
      // 테이블에서 보간
      return _interpolateMomentArm(currentAngle);
    } else {
      // 기본값: sin 함수 사용 (0 ~ 1 범위)
      // 각도가 중간 범위일 때 최대 효율
      final normalizedAngle = (currentAngle - angleMin) / (angleMax - angleMin);
      return math.sin(normalizedAngle * math.pi);
    }
  }

  /// 모멘트 암 테이블 보간
  double _interpolateMomentArm(double angle) {
    if (momentArmTable == null || momentArmTable!.isEmpty) {
      return 1.0; // 기본값
    }

    final entries = momentArmTable!.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    // 테이블 범위 밖
    if (angle <= entries.first.key) {
      return entries.first.value;
    }
    if (angle >= entries.last.key) {
      return entries.last.value;
    }

    // 보간
    for (int i = 0; i < entries.length - 1; i++) {
      final a1 = entries[i].key;
      final v1 = entries[i].value;
      final a2 = entries[i + 1].key;
      final v2 = entries[i + 1].value;

      if (angle >= a1 && angle <= a2) {
        final t = (angle - a1) / (a2 - a1);
        return v1 + (v2 - v1) * t;
      }
    }

    return 1.0; // 기본값
  }
}
