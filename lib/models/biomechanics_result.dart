import '../utils/safe_calculations.dart';
import 'package:flutter/foundation.dart';

/// 운동학적 분석 결과
class KinematicAnalysis {
  final String detectedMovementPattern;
  final List<String> activeJoints;
  final List<String> ignoredJoints;

  KinematicAnalysis({
    required this.detectedMovementPattern,
    required this.activeJoints,
    required this.ignoredJoints,
  });

  factory KinematicAnalysis.fromMap(Map<String, dynamic> map) {
    return KinematicAnalysis(
      detectedMovementPattern:
          map['detected_movement_pattern']?.toString() ?? 'Unknown Pattern',
      activeJoints:
          (map['active_joints'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      ignoredJoints:
          (map['ignored_joints'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
    );
  }
}

/// 관절 통계
class JointStat {
  final double romDegrees;
  final double stabilityScore;
  final double contributionScore;

  JointStat({
    required this.romDegrees,
    required this.stabilityScore,
    required this.contributionScore,
  });

  factory JointStat.fromMap(Map<String, dynamic> map) {
    // 🔧 유연한 필드 매칭 + 안전한 형 변환
    final romRaw =
        map['rom_degrees'] ?? map['romDegrees'] ?? map['rom'] ?? map['angle'];
    final stabilityRaw =
        map['stability_score'] ??
        map['stabilityScore'] ??
        map['stability'] ??
        map['stability_percent'];
    final contributionRaw =
        map['contribution_score'] ??
        map['contributionScore'] ??
        map['contribution'] ??
        map['load_share'];

    return JointStat(
      romDegrees: SafeCalculations.sanitizeDouble(
        BiomechanicsResult._safeParseDouble(romRaw),
      ),
      stabilityScore: SafeCalculations.safePercent(
        BiomechanicsResult._safeParseDouble(stabilityRaw),
      ),
      contributionScore: SafeCalculations.safePercent(
        BiomechanicsResult._safeParseDouble(contributionRaw),
      ),
    );
  }
}

/// 근육 점수
class MuscleScore {
  final double score;
  final String? dependencyJoint;

  MuscleScore({required this.score, this.dependencyJoint});

  factory MuscleScore.fromMap(Map<String, dynamic> map) {
    // 🔧 유연한 필드 매칭 + 안전한 형 변환
    final rawScore =
        map['score'] ??
        map['value'] ??
        map['activation'] ??
        map['activationPercent'] ??
        map['percent'];
    final dependency =
        map['dependency_joint'] ?? map['dependencyJoint'] ?? map['joint'];

    return MuscleScore(
      score: SafeCalculations.safePercent(
        BiomechanicsResult._safeParseDouble(rawScore),
      ),
      dependencyJoint: dependency?.toString(),
    );
  }
}

/// 생체역학 분석 결과 모델 (Core Engine 연동)
///
/// Core Engine의 6가지 핵심 요소 결과를 UI에 바인딩하기 위한 데이터 구조
/// Single Source of Truth: 백엔드 데이터(jointStats, muscleScores)만 사용
class BiomechanicsResult {
  /// 생체역학 패턴
  final String biomechPattern;

  /// 6가지 핵심 요소 메타데이터
  final BiomechanicsMetadata metadata;

  /// 운동학적 분석 결과
  final KinematicAnalysis? kinematicAnalysis;

  /// 관절 통계 (백엔드 데이터)
  final Map<String, JointStat>? jointStats;

  /// 근육 점수 (백엔드 데이터)
  final Map<String, MuscleScore>? muscleScores;

  /// 디버그 정보
  final Map<String, dynamic>? debugInfo;

  /// 핵심 메트릭스 (새로운 형식 지원)
  /// core_metrics: rom_score, stability_score, tempo_score, symmetry_score, posture_score, intensity_score
  final Map<String, dynamic>? coreMetrics;

  /// 감지된 결함 목록 (새로운 형식 지원)
  /// detected_faults: ["knee_valgus", "uncontrolled_tempo"] 등
  final List<String>? detectedFaults;

  BiomechanicsResult({
    required this.biomechPattern,
    required this.metadata,
    this.kinematicAnalysis,
    this.jointStats,
    this.muscleScores,
    this.debugInfo,
    this.coreMetrics,
    this.detectedFaults,
  });

  /// Fuzzy Matching으로 근육 점수 조회 (백엔드 데이터만 사용)
  /// 예: "Latissimus" -> "latissimus_dorsi", "lats" 등과 매칭
  /// 백엔드 데이터가 없으면 null 반환 (Fallback 없음)
  double? getMuscleScore(String displayName) {
    if (muscleScores == null || muscleScores!.isEmpty) {
      return null; // 백엔드 데이터가 없으면 null 반환
    }

    final normalized = _normalizeKey(displayName);
    for (final entry in muscleScores!.entries) {
      if (_normalizeKey(entry.key) == normalized ||
          _normalizeKey(entry.key).contains(normalized) ||
          normalized.contains(_normalizeKey(entry.key))) {
        return entry.value.score;
      }
    }

    return null; // 매칭 실패
  }

  /// Fuzzy Matching으로 관절 통계 조회 (백엔드 데이터만 사용)
  /// 백엔드 데이터가 없으면 null 반환 (Fallback 없음)
  JointStat? getJointStat(String displayName) {
    if (jointStats == null || jointStats!.isEmpty) {
      return null; // 백엔드 데이터가 없으면 null 반환
    }

    final normalized = _normalizeKey(displayName);
    for (final entry in jointStats!.entries) {
      if (_normalizeKey(entry.key) == normalized ||
          _normalizeKey(entry.key).contains(normalized) ||
          normalized.contains(_normalizeKey(entry.key))) {
        return entry.value;
      }
    }

    return null; // 매칭 실패
  }

  /// 키 정규화 (대소문자, 공백, 언더스코어 통일)
  String _normalizeKey(String key) {
    return key
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  /// 안전한 double 변환 헬퍼 메서드
  /// 어떤 타입이 들어와도 안전하게 double로 변환
  /// - null -> 0.0
  /// - num -> toDouble()
  /// - String -> double.tryParse() (%, 공백 제거 후)
  /// - 기타 -> 0.0
  static double _safeParseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) {
      // "85.5%" 처럼 %가 붙어있을 경우 제거 후 변환
      final cleanStr = value.replaceAll('%', '').trim();
      return double.tryParse(cleanStr) ?? 0.0;
    }
    return 0.0;
  }

  /// UI에서 근육 점수를 안전하게 표시하기 위한 헬퍼
  String getMuscleScoreDisplay(String displayName) {
    final score = getMuscleScore(displayName);
    return score != null ? '${score.toStringAsFixed(1)}%' : '-';
  }

  /// UI에서 관절 통계를 안전하게 표시하기 위한 헬퍼
  /// metric: 'romDegrees', 'stabilityScore', 'contributionScore'
  String getJointStatDisplay(
    String displayName, {
    String metric = 'romDegrees',
  }) {
    final stat = getJointStat(displayName);
    if (stat == null) return '-';

    switch (metric) {
      case 'romDegrees':
        return '${stat.romDegrees.toStringAsFixed(1)}°';
      case 'stabilityScore':
        return '${stat.stabilityScore.toStringAsFixed(1)}%';
      case 'contributionScore':
        return '${stat.contributionScore.toStringAsFixed(1)}%';
      default:
        return '-';
    }
  }

  /// 백엔드의 EnhancedAnalysisResult에서 파싱
  /// Single Source of Truth: joint_stats, muscle_scores만 사용
  factory BiomechanicsResult.fromAnalysisResult(
    Map<String, dynamic> analysisResult,
  ) {
    try {
      // 🔍 디버그 로깅: 들어오는 JSON 전체 출력
      debugPrint('📥 [BiomechanicsResult] Raw JSON from DB: $analysisResult');
      debugPrint(
        '📥 [BiomechanicsResult] JSON Keys: ${analysisResult.keys.toList()}',
      );

      // 🔧 1. 이중 래핑 처리: JSON 안에 또 JSON이 있는지 확인
      Map<String, dynamic> data = analysisResult;
      if (analysisResult['ai_analysis_result'] != null) {
        debugPrint('🔧 [BiomechanicsResult] 이중 래핑 감지: ai_analysis_result 키 발견');
        final innerData = analysisResult['ai_analysis_result'];
        if (innerData is Map<String, dynamic>) {
          data = innerData;
          debugPrint('📥 [BiomechanicsResult] Unwrapped JSON: $data');
          debugPrint(
            '📥 [BiomechanicsResult] Unwrapped Keys: ${data.keys.toList()}',
          );
        }
      } else if (analysisResult['analysis_result'] != null) {
        debugPrint('🔧 [BiomechanicsResult] 이중 래핑 감지: analysis_result 키 발견');
        final innerData = analysisResult['analysis_result'];
        if (innerData is Map<String, dynamic>) {
          data = innerData;
          debugPrint('📥 [BiomechanicsResult] Unwrapped JSON: $data');
          debugPrint(
            '📥 [BiomechanicsResult] Unwrapped Keys: ${data.keys.toList()}',
          );
        }
      }

      // 🔧 2. 유연한 키 매칭: metadata 찾기
      final metadataRaw =
          data['metadata'] as Map<String, dynamic>? ??
          analysisResult['metadata'] as Map<String, dynamic>? ??
          {};

      debugPrint('📊 [BiomechanicsResult] 파싱 시작 (백엔드 데이터만 사용)');

      // 🔧 새로운 필드 파싱: kinematic_analysis (유연한 키 매칭)
      KinematicAnalysis? kinematicAnalysis;
      final kinematicRaw =
          data['kinematic_analysis'] as Map<String, dynamic>? ??
          data['kinematicAnalysis'] as Map<String, dynamic>? ??
          analysisResult['kinematic_analysis'] as Map<String, dynamic>?;
      if (kinematicRaw != null) {
        try {
          kinematicAnalysis = KinematicAnalysis.fromMap(kinematicRaw);
          debugPrint(
            '✅ [BiomechanicsResult] kinematic_analysis 파싱 완료: ${kinematicAnalysis.detectedMovementPattern}',
          );
          debugPrint(
            '   - 활성 관절: ${kinematicAnalysis.activeJoints.join(", ")}',
          );
          debugPrint(
            '   - 무시된 관절: ${kinematicAnalysis.ignoredJoints.join(", ")}',
          );
        } catch (e) {
          debugPrint('⚠️ [BiomechanicsResult] kinematic_analysis 파싱 실패: $e');
        }
      }

      // 🔧 새로운 필드 파싱: joint_stats (유연한 키 매칭)
      // 로그에서 확인된 실제 키: rom_data (최우선)
      Map<String, JointStat>? jointStats;
      final jointStatsRaw =
          data['rom_data']
              as Map<String, dynamic>? ?? // <--- [NEW] 로그에서 확인된 키 (최우선)
          data['joint_stats'] as Map<String, dynamic>? ??
          data['jointStats'] as Map<String, dynamic>? ??
          data['joint_angles'] as Map<String, dynamic>? ??
          data['pose_data'] as Map<String, dynamic>? ??
          data['joints'] as Map<String, dynamic>? ??
          analysisResult['joint_stats'] as Map<String, dynamic>?;

      debugPrint(
        '🔍 [BiomechanicsResult] joint_stats 검색 결과: ${jointStatsRaw != null ? "${jointStatsRaw.length}개 항목" : "null"}',
      );

      if (jointStatsRaw != null) {
        try {
          jointStats = <String, JointStat>{};
          for (final entry in jointStatsRaw.entries) {
            if (entry.value != null) {
              // 🔧 데이터 형식 변환: 단순 숫자 값도 처리
              if (entry.value is num) {
                // rom_data는 단순 숫자 값일 수 있음 (ROM 각도)
                jointStats[entry.key] = JointStat.fromMap({
                  'rom_degrees': entry.value,
                  'stability_score': 0.0,
                  'contribution_score': 0.0,
                });
                debugPrint(
                  '   📊 [BiomechanicsResult] 관절 통계 (단순 숫자): ${entry.key} -> ROM: ${jointStats[entry.key]!.romDegrees.toStringAsFixed(1)}도',
                );
              } else if (entry.value is Map<String, dynamic>) {
                // 객체 형식 (기존 방식)
                final jointStatMap = entry.value as Map<String, dynamic>;
                jointStats[entry.key] = JointStat.fromMap(jointStatMap);
                debugPrint(
                  '   📊 [BiomechanicsResult] 관절 통계: ${entry.key} -> ROM: ${jointStats[entry.key]!.romDegrees.toStringAsFixed(1)}도, 안정성: ${jointStats[entry.key]!.stabilityScore.toStringAsFixed(1)}점',
                );
              }
            }
          }
          debugPrint(
            '✅ [BiomechanicsResult] joint_stats 파싱 완료: ${jointStats.length}개',
          );
        } catch (e) {
          debugPrint('⚠️ [BiomechanicsResult] joint_stats 파싱 실패: $e');
        }
      }

      // 🔧 새로운 필드 파싱: muscle_scores (유연한 키 매칭)
      // VideoRepository에서 저장한 muscle_usage를 최우선으로 확인
      Map<String, MuscleScore>? muscleScores;
      final muscleScoresRaw =
          data['muscle_usage']
              as Map<
                String,
                dynamic
              >? ?? // <--- [NEW] VideoRepository에서 저장한 키 (최우선)
          data['detailed_muscle_usage']
              as Map<String, dynamic>? ?? // 로그에서 확인된 키
          data['muscle_scores'] as Map<String, dynamic>? ??
          data['muscleScores'] as Map<String, dynamic>? ??
          data['muscles'] as Map<String, dynamic>? ??
          data['detected_muscles'] as Map<String, dynamic>? ??
          analysisResult['muscle_scores'] as Map<String, dynamic>?;

      debugPrint(
        '🔍 [BiomechanicsResult] muscle_scores 검색 결과: ${muscleScoresRaw != null ? "${muscleScoresRaw.length}개 항목" : "null"}',
      );

      if (muscleScoresRaw != null) {
        try {
          muscleScores = <String, MuscleScore>{};
          for (final entry in muscleScoresRaw.entries) {
            if (entry.value != null) {
              // 🔧 데이터 형식 변환: 단순 숫자 값도 처리
              if (entry.value is num) {
                // detailed_muscle_usage는 단순 숫자 값일 수 있음 (활성도 %)
                muscleScores[entry.key] = MuscleScore.fromMap({
                  'score': entry.value,
                });
                debugPrint(
                  '   📊 [BiomechanicsResult] 근육 점수 (단순 숫자): ${entry.key} -> ${muscleScores[entry.key]!.score.toStringAsFixed(1)}점',
                );
              } else if (entry.value is Map<String, dynamic>) {
                // 객체 형식 (기존 방식)
                final muscleScoreMap = entry.value as Map<String, dynamic>;
                muscleScores[entry.key] = MuscleScore.fromMap(muscleScoreMap);
                final dependency = muscleScores[entry.key]!.dependencyJoint;
                debugPrint(
                  '   📊 [BiomechanicsResult] 근육 점수: ${entry.key} -> ${muscleScores[entry.key]!.score.toStringAsFixed(1)}점${dependency != null ? " (의존: $dependency)" : ""}',
                );
              }
            }
          }
          debugPrint(
            '✅ [BiomechanicsResult] muscle_scores 파싱 완료: ${muscleScores.length}개',
          );
        } catch (e) {
          debugPrint('⚠️ [BiomechanicsResult] muscle_scores 파싱 실패: $e');
        }
      }

      // 🔧 새로운 필드 파싱: core_metrics (새로운 형식 지원)
      Map<String, dynamic>? coreMetrics;
      final coreMetricsRaw =
          data['core_metrics'] as Map<String, dynamic>? ??
          data['coreMetrics'] as Map<String, dynamic>? ??
          analysisResult['core_metrics'] as Map<String, dynamic>?;
      if (coreMetricsRaw != null) {
        coreMetrics = Map<String, dynamic>.from(coreMetricsRaw);
        debugPrint(
          '✅ [BiomechanicsResult] core_metrics 파싱 완료: ${coreMetrics.keys.join(", ")}',
        );
      }

      // 🔧 새로운 필드 파싱: detected_faults (새로운 형식 지원)
      List<String>? detectedFaults;
      final detectedFaultsRaw =
          data['detected_faults'] as List<dynamic>? ??
          data['detectedFaults'] as List<dynamic>? ??
          analysisResult['detected_faults'] as List<dynamic>?;
      if (detectedFaultsRaw != null) {
        detectedFaults = detectedFaultsRaw
            .map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList();
        debugPrint(
          '✅ [BiomechanicsResult] detected_faults 파싱 완료: ${detectedFaults.join(", ")}',
        );
      }

      // 🔧 새로운 필드 파싱: debug_info (유연한 키 매칭)
      Map<String, dynamic>? debugInfo;
      final debugInfoRaw =
          data['debug_info'] as Map<String, dynamic>? ??
          data['debugInfo'] as Map<String, dynamic>? ??
          analysisResult['debug_info'] as Map<String, dynamic>?;
      if (debugInfoRaw != null) {
        debugInfo = debugInfoRaw;
        debugPrint(
          '✅ [BiomechanicsResult] debug_info 파싱 완료: ${debugInfo.keys.join(", ")}',
        );
      }

      // 🔧 유연한 키 매칭: biomech_pattern 찾기
      final biomechPattern =
          data['biomech_pattern']?.toString() ??
          data['biomechPattern']?.toString() ??
          analysisResult['biomech_pattern']?.toString() ??
          'UNKNOWN';

      debugPrint('📊 [BiomechanicsResult] 파싱 완료:');
      debugPrint('   - biomechPattern: $biomechPattern');
      debugPrint(
        '   - kinematicAnalysis: ${kinematicAnalysis != null ? "있음" : "없음"}',
      );
      debugPrint('   - jointStats: ${jointStats?.length ?? 0}개');
      debugPrint('   - muscleScores: ${muscleScores?.length ?? 0}개');
      debugPrint('   - debugInfo: ${debugInfo != null ? "있음" : "없음"}');

      return BiomechanicsResult(
        biomechPattern: biomechPattern,
        metadata: BiomechanicsMetadata.fromMap(metadataRaw),
        kinematicAnalysis: kinematicAnalysis,
        jointStats: jointStats,
        muscleScores: muscleScores,
        debugInfo: debugInfo,
        coreMetrics: coreMetrics,
        detectedFaults: detectedFaults,
      );
    } catch (e, stack) {
      debugPrint('❌ [BiomechanicsResult] 파싱 중 치명적 오류 발생: $e');
      debugPrint(stack.toString());
      // 앱 크래시 방지를 위한 최소 기본값 반환
      return BiomechanicsResult(
        biomechPattern: 'UNKNOWN',
        metadata: BiomechanicsMetadata.fromMap({}),
        kinematicAnalysis: null,
        jointStats: null,
        muscleScores: null,
        debugInfo: null,
        coreMetrics: null,
        detectedFaults: null,
      );
    }
  }
}

/// 관절 기여도 데이터
class JointContribution {
  final String jointName;
  final double contributionPercent; // 전체 부하 중 기여도 (%)
  final double torqueNm; // 관절 토크 (Nm)
  final double romScore; // ROM 점수

  JointContribution({
    required this.jointName,
    required this.contributionPercent,
    required this.torqueNm,
    required this.romScore,
  });
}

/// 근육 활성도 데이터
class MuscleActivation {
  final String muscleName;
  final double activationPercent; // 활성도 (%)
  final List<String> reasons; // 활성 원인 태그
  final bool isEccentric; // 신장성 수축 여부
  final String momentArmLength; // 모멘트암 길이 (Long/Short)

  MuscleActivation({
    required this.muscleName,
    required this.activationPercent,
    required this.reasons,
    required this.isEccentric,
    required this.momentArmLength,
  });
}

/// 6가지 핵심 요소 메타데이터
class BiomechanicsMetadata {
  final String? regionDominance;
  final bool? isAntiGravity;
  final double? eccentricMultiplier;
  final double? rhythmRatio;
  final bool? elevationFailure;
  final String? compensation;
  final Map<String, double>? ratios;
  final double? totalROM;
  final double? riskLevel;

  BiomechanicsMetadata({
    this.regionDominance,
    this.isAntiGravity,
    this.eccentricMultiplier,
    this.rhythmRatio,
    this.elevationFailure,
    this.compensation,
    this.ratios,
    this.totalROM,
    this.riskLevel,
  });

  factory BiomechanicsMetadata.fromMap(Map<String, dynamic> map) {
    final ratiosRaw = map['ratios'] as Map<String, dynamic>?;
    final ratios = ratiosRaw != null
        ? Map<String, double>.from(
            ratiosRaw.map((k, v) {
              final value = (v as num).toDouble();
              return MapEntry(k, SafeCalculations.sanitizeDouble(value));
            }),
          )
        : null;

    return BiomechanicsMetadata(
      regionDominance: map['regionDominance']?.toString(),
      isAntiGravity: map['isAntiGravity'] as bool?,
      eccentricMultiplier: SafeCalculations.sanitizeDouble(
        (map['eccentricMultiplier'] as num?)?.toDouble() ?? 1.0,
      ),
      rhythmRatio: SafeCalculations.sanitizeDouble(
        (map['rhythmRatio'] as num?)?.toDouble() ?? 0.0,
      ),
      elevationFailure: map['elevationFailure'] as bool?,
      compensation: map['compensation']?.toString(),
      ratios: ratios,
      totalROM: SafeCalculations.sanitizeDouble(
        (map['totalROM'] as num?)?.toDouble() ?? 0.0,
      ),
      riskLevel: SafeCalculations.sanitizeDouble(
        (map['riskLevel'] as num?)?.toDouble() ?? 0.0,
      ),
    );
  }

  /// Map으로 변환 (오버레이에 전달용)
  Map<String, dynamic> toMap() {
    return {
      'regionDominance': regionDominance,
      'isAntiGravity': isAntiGravity,
      'eccentricMultiplier': eccentricMultiplier,
      'rhythmRatio': rhythmRatio,
      'elevationFailure': elevationFailure,
      'compensation': compensation,
      'ratios': ratios,
      'totalROM': totalROM,
      'riskLevel': riskLevel,
    };
  }

  /// Raw Data View용 문자열
  String toRawDataString() {
    final buffer = StringBuffer();
    buffer.writeln('Region Dominance: ${regionDominance ?? "N/A"}');
    buffer.writeln('Anti-Gravity: ${isAntiGravity ?? false}');
    buffer.writeln('Eccentric Multiplier: ${eccentricMultiplier ?? 1.0}');
    buffer.writeln('Rhythm Ratio: ${rhythmRatio ?? 0.0}');
    buffer.writeln('Elevation Failure: ${elevationFailure ?? false}');
    buffer.writeln('Compensation: ${compensation ?? "none"}');
    buffer.writeln('Total ROM: ${totalROM ?? 0.0}');
    buffer.writeln('Risk Level: ${riskLevel ?? 0.0}');
    if (ratios != null) {
      buffer.writeln(
        'Ratios: ${ratios!.entries.map((e) => "${e.key}: ${e.value.toStringAsFixed(3)}").join(", ")}',
      );
    }
    return buffer.toString();
  }
}
