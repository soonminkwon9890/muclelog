import 'package:flutter/foundation.dart';
import 'motion_type.dart';
import 'body_part.dart' show BodyPart;

/// 운동 타입 Enum
enum ExerciseType {
  upper('upper'),
  lower('lower'),
  full('full');

  final String value;
  const ExerciseType(this.value);

  /// 문자열에서 ExerciseType으로 변환
  static ExerciseType fromString(String? value) {
    if (value == null) return ExerciseType.full;
    switch (value.toLowerCase()) {
      case 'upper':
        return ExerciseType.upper;
      case 'lower':
        return ExerciseType.lower;
      case 'full':
        return ExerciseType.full;
      default:
        return ExerciseType.full;
    }
  }
}

/// 분석 기록 모델 클래스
/// analysis_logs 테이블의 데이터를 표현합니다.
class AnalysisLog {
  final String logId; // UUID String
  final String userId;
  final String exerciseName;
  final String videoPath;
  final String status;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final double? videoDurationSeconds;

  // analysis_result JSONB에서 추출한 점수들
  final double? agonistAvgScore;
  final double? antagonistAvgScore;
  final double? synergistAvgScore;
  final double? consistencyScore;

  // analysis_result JSONB 전체 (추가 데이터 저장용)
  final Map<String, dynamic>? analysisResult;

  // 분석 타겟 부위 ('UPPER', 'LOWER', 'FULL')
  final String? targetArea;

  // 운동 타입 ('upper', 'lower', 'full')
  final ExerciseType exerciseType;

  // 운동 방식 타입 ('isotonic', 'isometric', 'isokinetic')
  final MotionType motionType;

  // 운동 부위 ('upper_body', 'lower_body', 'full_body')
  final BodyPart? bodyPart;

  // 새로운 데이터 구조 (순수 역학 엔진)
  final Map<String, double> detailedMuscleUsage; // non-nullable, 기본값 {}
  final String biomechPattern; // 기본값 "UNKNOWN"

  // 🔧 VideoRepository에서 저장한 muscle_usage 데이터 (nullable)
  final Map<String, double>? muscleUsage;

  AnalysisLog({
    required this.logId,
    required this.userId,
    required this.exerciseName,
    required this.videoPath,
    required this.status,
    required this.createdAt,
    this.updatedAt,
    this.videoDurationSeconds,
    this.agonistAvgScore,
    this.antagonistAvgScore,
    this.synergistAvgScore,
    this.consistencyScore,
    this.analysisResult,
    this.targetArea,
    ExerciseType? exerciseType,
    MotionType? motionType,
    this.bodyPart,
    Map<String, double>? detailedMuscleUsage,
    String? biomechPattern,
    this.muscleUsage,
  }) : exerciseType = exerciseType ?? ExerciseType.full,
       motionType = motionType ?? MotionType.isotonic,
       detailedMuscleUsage = detailedMuscleUsage ?? {},
       biomechPattern = biomechPattern ?? 'UNKNOWN';

  /// Legacy 데이터를 새 형식으로 변환하는 매핑 함수 (public)
  static Map<String, double> convertLegacyToNew(
    Map<String, dynamic> legacyData,
  ) {
    final converted = <String, double>{};

    // Legacy 키 -> New 키 매핑
    final legacyMapping = {
      // 목/승모근
      '목': 'trapezius',
      'neck': 'trapezius',
      '승모근': 'trapezius',
      'trapezius': 'trapezius',
      // 등/광배근
      '등': 'lats',
      'back': 'lats',
      '광배근': 'lats',
      'lats': 'lats',
      // 가슴/대흉근
      '가슴': 'pectoralis_mid',
      'chest': 'pectoralis_mid',
      '대흉근': 'pectoralis_mid',
      'pectoralis': 'pectoralis_mid',
      // 허리/척추/기립근
      '허리': 'erector_spinae',
      'spine': 'erector_spinae',
      '척추': 'erector_spinae',
      '기립근': 'erector_spinae',
      'erector': 'erector_spinae',
      // 하체/허벅지/대퇴사두근
      '하체': 'quads',
      'leg': 'quads',
      '허벅지': 'quads',
      '대퇴사두근': 'quads',
      'quads': 'quads',
      // 기타 근육들
      'shoulder': 'lateral_deltoid',
      '어깨': 'lateral_deltoid',
      '삼각근': 'lateral_deltoid',
      'deltoid': 'lateral_deltoid',
      'hamstrings': 'hamstrings',
      '햄스트링': 'hamstrings',
      'glutes': 'glutes',
      '둔근': 'glutes',
      'biceps': 'biceps',
      '이두근': 'biceps',
      'triceps': 'triceps',
      '삼두근': 'triceps',
    };

    for (final entry in legacyData.entries) {
      final legacyKey = entry.key.toLowerCase();
      final value = entry.value;

      // 숫자로 변환
      double? numValue;
      if (value is num) {
        numValue = value.toDouble();
      } else if (value is String) {
        numValue = double.tryParse(value);
      }

      if (numValue == null || numValue <= 0) continue;

      // 매핑된 키 찾기
      String? newKey;
      for (final mappingEntry in legacyMapping.entries) {
        if (legacyKey.contains(mappingEntry.key.toLowerCase()) ||
            mappingEntry.key.toLowerCase().contains(legacyKey)) {
          newKey = mappingEntry.value;
          break;
        }
      }

      // 매핑이 없으면 원본 키를 그대로 사용 (이미 새 형식일 수 있음)
      newKey ??= legacyKey;

      // 기존 값이 있으면 더 큰 값으로 업데이트
      if (converted.containsKey(newKey)) {
        converted[newKey] = converted[newKey]! > numValue
            ? converted[newKey]!
            : numValue;
      } else {
        converted[newKey] = numValue;
      }
    }

    return converted;
  }

  /// 운동 종목 기반 biomechPattern 추론 (public)
  static String inferBiomechPattern(String exerciseName) {
    final name = exerciseName.toLowerCase();

    // HINGE 패턴 (데드리프트, 스쿼트 등)
    if (name.contains('데드') ||
        name.contains('deadlift') ||
        name.contains('스쿼트') ||
        name.contains('squat') ||
        name.contains('힙') ||
        name.contains('hip')) {
      return 'STATE_HINGE';
    }

    // PULL 패턴 (풀업, 로우 등)
    if (name.contains('풀') ||
        name.contains('pull') ||
        name.contains('로우') ||
        name.contains('row') ||
        name.contains('랫') ||
        name.contains('lat') ||
        name.contains('등')) {
      return 'STATE_PULL';
    }

    // PUSH 패턴 (푸시업, 벤치프레스 등)
    if (name.contains('푸시') ||
        name.contains('push') ||
        name.contains('벤치') ||
        name.contains('bench') ||
        name.contains('가슴') ||
        name.contains('chest')) {
      return 'STATE_PUSH';
    }

    return 'UNKNOWN';
  }

  /// Map에서 AnalysisLog 생성
  /// analysis_result JSONB에서 점수들을 추출합니다.
  factory AnalysisLog.fromMap(Map<String, dynamic> map) {
    // analysis_result JSONB에서 점수 추출
    final analysisResult = map['analysis_result'] as Map<String, dynamic>?;

    // analysis_result가 null이면 기본값(0.0) 사용
    final agonistAvgScore = analysisResult?['agonist_avg_score'] as double?;
    final antagonistAvgScore =
        analysisResult?['antagonist_avg_score'] as double?;
    final synergistAvgScore = analysisResult?['synergist_avg_score'] as double?;
    final consistencyScore = analysisResult?['consistency_score'] as double?;

    // 날짜 파싱
    DateTime? createdAt;
    try {
      createdAt = DateTime.parse((map['created_at'] ?? '').toString());
    } catch (e) {
      createdAt = DateTime.now();
    }

    DateTime? updatedAt;
    try {
      final updatedAtStr = map['updated_at']?.toString();
      if (updatedAtStr != null) {
        updatedAt = DateTime.parse(updatedAtStr);
      }
    } catch (e) {
      updatedAt = null;
    }

    // target_area 파싱 (기본값: 'FULL')
    final targetArea = map['target_area']?.toString() ?? 'FULL';

    // exercise_type 파싱 (기본값: 'full')
    final exerciseType = ExerciseType.fromString(
      map['exercise_type']?.toString(),
    );

    // motion_type 파싱 (기본값: 'isotonic')
    final motionType = MotionType.fromString(map['motion_type']?.toString());

    // target_part 파싱 (기본값: null)
    final bodyPart = BodyPart.fromString(map['target_part']?.toString());

    // 새로운 데이터 구조 파싱 (우선순위 기반)
    Map<String, double> detailedMuscleUsage = {};
    String biomechPattern = 'UNKNOWN';
    Map<String, double>? muscleUsage; // 🔧 VideoRepository에서 저장한 muscle_usage

    // Priority 1: 신규 데이터 확인
    if (analysisResult != null) {
      // 🔧 muscle_usage (VideoRepository에서 저장한 데이터) 파싱
      try {
        final muscleUsageRaw =
            analysisResult['muscle_usage'] as Map<String, dynamic>?;
        if (muscleUsageRaw != null && muscleUsageRaw.isNotEmpty) {
          muscleUsage = <String, double>{};
          for (final entry in muscleUsageRaw.entries) {
            final value = entry.value;
            if (value is num) {
              muscleUsage[entry.key] = value.toDouble();
            } else if (value is String) {
              // 문자열인 경우 숫자로 변환 시도
              final parsed = double.tryParse(value);
              if (parsed != null) {
                muscleUsage[entry.key] = parsed;
              }
            }
          }
          debugPrint(
            '✅ [AnalysisLog] muscle_usage 파싱 완료: ${muscleUsage.length}개 근육',
          );
        }
      } catch (e) {
        debugPrint('⚠️ [AnalysisLog] muscle_usage 파싱 실패: $e');
        muscleUsage = null;
      }

      final newDetailedMuscleUsage =
          analysisResult['detailed_muscle_usage'] as Map<String, dynamic>?;
      final newBiomechPattern = analysisResult['biomech_pattern']?.toString();

      // muscle_usage가 있으면 detailedMuscleUsage에도 복사
      if (muscleUsage != null && muscleUsage.isNotEmpty) {
        detailedMuscleUsage = Map<String, double>.from(muscleUsage);
        biomechPattern = newBiomechPattern ?? 'UNKNOWN';
        debugPrint(
          '📊 [AnalysisLog] Loaded from muscle_usage: ${detailedMuscleUsage.length} muscles',
        );
      } else if (newDetailedMuscleUsage != null &&
          newDetailedMuscleUsage.isNotEmpty) {
        // detailed_muscle_usage가 있으면 사용
        for (final entry in newDetailedMuscleUsage.entries) {
          final value = entry.value;
          if (value is num) {
            detailedMuscleUsage[entry.key] = value.toDouble();
          }
        }
        biomechPattern = newBiomechPattern ?? 'UNKNOWN';
        debugPrint(
          '📊 [AnalysisLog] Loaded from New JSONB: ${detailedMuscleUsage.length} muscles',
        );
      } else {
        // Priority 2: Legacy 데이터 변환
        final usageDistribution =
            analysisResult['usage_distribution'] as Map<String, dynamic>?;

        if (usageDistribution != null && usageDistribution.isNotEmpty) {
          detailedMuscleUsage = convertLegacyToNew(usageDistribution);
          debugPrint(
            '📊 [AnalysisLog] Loaded from Legacy Data: ${detailedMuscleUsage.length} muscles converted',
          );
        } else {
          // analysis_json도 확인 (하위 호환성)
          final analysisJson = map['analysis_json'] as Map<String, dynamic>?;
          if (analysisJson != null) {
            final jsonUsageDist =
                analysisJson['usage_distribution'] as Map<String, dynamic>?;
            if (jsonUsageDist != null && jsonUsageDist.isNotEmpty) {
              detailedMuscleUsage = convertLegacyToNew(jsonUsageDist);
              debugPrint(
                '📊 [AnalysisLog] Loaded from analysis_json: ${detailedMuscleUsage.length} muscles converted',
              );
            }
          }
        }

        // biomechPattern 추론 (운동 종목 기반)
        if (biomechPattern == 'UNKNOWN') {
          final exerciseName = map['exercise_name']?.toString() ?? '운동';
          biomechPattern = inferBiomechPattern(exerciseName);
          if (biomechPattern != 'UNKNOWN') {
            debugPrint(
              '📊 [AnalysisLog] Inferred biomechPattern: $biomechPattern from exercise: $exerciseName',
            );
          }
        }
      }
    }

    return AnalysisLog(
      logId: (map['log_id'] ?? '').toString(), // 안전 변환: int든 String이든 String으로
      userId: (map['user_id'] ?? '').toString(), // 안전 변환
      exerciseName: map['exercise_name']?.toString() ?? '운동',
      videoPath: (map['video_path'] ?? '').toString(), // 안전 변환
      status: map['status']?.toString() ?? 'UNKNOWN',
      createdAt: createdAt,
      updatedAt: updatedAt,
      videoDurationSeconds: map['video_duration_seconds'] as double?,
      agonistAvgScore: agonistAvgScore,
      antagonistAvgScore: antagonistAvgScore,
      synergistAvgScore: synergistAvgScore,
      consistencyScore: consistencyScore,
      analysisResult: analysisResult,
      targetArea: targetArea,
      exerciseType: exerciseType,
      motionType: motionType,
      bodyPart: bodyPart,
      detailedMuscleUsage: detailedMuscleUsage,
      biomechPattern: biomechPattern,
      muscleUsage: muscleUsage, // 🔧 VideoRepository에서 저장한 muscle_usage
    );
  }

  /// JSON에서 AnalysisLog 생성
  factory AnalysisLog.fromJson(Map<String, dynamic> json) =>
      AnalysisLog.fromMap(json);

  /// Map으로 변환
  Map<String, dynamic> toMap() {
    return {
      'log_id': logId,
      'user_id': userId,
      'exercise_name': exerciseName,
      'video_path': videoPath,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt?.toIso8601String(),
      'video_duration_seconds': videoDurationSeconds,
      'analysis_result': analysisResult,
      'target_area': targetArea,
      'exercise_type': exerciseType.value,
      'motion_type': motionType.value,
      'target_part': bodyPart?.value,
      'detailed_muscle_usage': detailedMuscleUsage,
      'biomech_pattern': biomechPattern,
    };
  }

  /// JSON으로 변환
  Map<String, dynamic> toJson() => toMap();

  /// 복사본 생성 (일부 필드만 변경)
  AnalysisLog copyWith({
    String? logId, // UUID String
    String? userId,
    String? exerciseName,
    String? videoPath,
    String? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    double? videoDurationSeconds,
    double? agonistAvgScore,
    double? antagonistAvgScore,
    double? synergistAvgScore,
    double? consistencyScore,
    Map<String, dynamic>? analysisResult,
    String? targetArea,
    ExerciseType? exerciseType,
    MotionType? motionType,
    BodyPart? bodyPart,
    Map<String, double>? detailedMuscleUsage,
    String? biomechPattern,
  }) {
    return AnalysisLog(
      logId: logId ?? this.logId,
      userId: userId ?? this.userId,
      exerciseName: exerciseName ?? this.exerciseName,
      videoPath: videoPath ?? this.videoPath,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      videoDurationSeconds: videoDurationSeconds ?? this.videoDurationSeconds,
      agonistAvgScore: agonistAvgScore ?? this.agonistAvgScore,
      antagonistAvgScore: antagonistAvgScore ?? this.antagonistAvgScore,
      synergistAvgScore: synergistAvgScore ?? this.synergistAvgScore,
      consistencyScore: consistencyScore ?? this.consistencyScore,
      analysisResult: analysisResult ?? this.analysisResult,
      targetArea: targetArea ?? this.targetArea,
      exerciseType: exerciseType ?? this.exerciseType,
      motionType: motionType ?? this.motionType,
      bodyPart: bodyPart ?? this.bodyPart,
      detailedMuscleUsage: detailedMuscleUsage ?? this.detailedMuscleUsage,
      biomechPattern: biomechPattern ?? this.biomechPattern,
    );
  }
}
