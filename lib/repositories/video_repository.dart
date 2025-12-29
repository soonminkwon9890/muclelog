import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';
import '../services/pose_detection_service.dart';
import '../models/analysis_log.dart';
import '../models/motion_type.dart';
import '../models/body_part.dart';
import '../utils/muscle_metric_utils.dart';
import '../utils/biomechanics/point_3d.dart';

/// 영상 업로드 및 분석 Repository
/// 영상 업로드, 분석, DB 저장을 통합 처리합니다.
class VideoRepository {
  static VideoRepository? _instance;
  static VideoRepository get instance => _instance ??= VideoRepository._();
  VideoRepository._();

  /// 영상 업로드 및 분석 수행
  /// [videoFile] 업로드할 영상 파일
  /// [videoTitle] 영상 제목
  /// [exerciseType] 운동 타입 (ExerciseType) - Single Source of Truth
  /// [motionType] 운동 방식 타입 (MotionType) - 생체역학적 특성
  /// [bodyPart] 운동 부위 (BodyPart) - 분석 최적화용
  /// [userId] 사용자 ID
  /// [onProgress] 진행률 콜백 (0.0 ~ 1.0)
  ///
  /// 반환: {'logId': String (UUID), 'videoId': String (UUID)}
  Future<Map<String, dynamic>> uploadVideoAndAnalyze({
    required File videoFile,
    required String videoTitle,
    required ExerciseType exerciseType,
    required MotionType motionType,
    required BodyPart bodyPart,
    required String userId,
    Function(double)? onProgress,
  }) async {
    // ExerciseType을 targetArea 문자열로 변환 (대문자)
    final targetArea = exerciseType.value.toUpperCase(); // 'upper' -> 'UPPER'
    try {
      // 1. 영상 파일명 생성 및 Storage 업로드
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.mp4';
      final storagePath = StorageService.instance.generateVideoPath(
        userId,
        fileName,
      );

      if (onProgress != null) onProgress(0.3);
      final videoUrl = await StorageService.instance.uploadVideo(
        file: videoFile,
        path: storagePath,
        onProgress: (progress) {
          if (onProgress != null) {
            onProgress(0.3 + (progress * 0.2)); // 30% ~ 50%
          }
        },
      );

      // 2. Pose 데이터 기반 생체역학 분석 수행
      Map<String, dynamic> analysisResult = {
        'detailed_muscle_usage': <String, double>{},
        'rom_data': <String, double>{},
        'biomech_pattern': targetArea,
        'stability_warning': '',
      };
      List<Pose> poses = [];
      List<int> timestamps = [];

      if (onProgress != null) onProgress(0.5);
      try {
        // 비디오에서 Pose 추출 (timestamp 포함)
        final poseResult = await PoseDetectionService.instance
            .extractPosesFromVideoOptimized(
              videoFile: videoFile,
              sampleRate: 5, // 1초에 5프레임
              onProgress: (progress) {
                if (onProgress != null) {
                  onProgress(0.5 + (progress * 0.4)); // 50% ~ 90%
                }
              },
            );

        poses = poseResult.poses;
        timestamps = poseResult.timestamps;

        debugPrint('✅ [VideoRepository] Pose 추출 완료: ${poses.length}개');
        debugPrint(
          '✅ [VideoRepository] Timestamp 추출 완료: ${timestamps.length}개',
        );

        // 생체역학 분석 수행 (Pose 데이터 사용)
        if (poses.length >= 2) {
          debugPrint('💪 [VideoRepository] 생체역학 분석 시작');
          analysisResult = await _calculateMuscleUsageFromPoses(
            poses: poses,
            timestamps: timestamps,
            motionType: motionType,
            targetArea: targetArea,
          );
          debugPrint(
            '✅ [VideoRepository] 생체역학 분석 완료: ${(analysisResult['detailed_muscle_usage'] as Map).length}개 근육',
          );
          debugPrint(
            '✅ [VideoRepository] ROM 데이터: ${(analysisResult['rom_data'] as Map).length}개 관절',
          );
        } else {
          debugPrint('⚠️ [VideoRepository] Pose 데이터가 부족하여 생체역학 분석 건너뜀');
        }
      } catch (e, stackTrace) {
        // 생체역학 분석 실패는 치명적이지 않으므로 로그만 남기고 계속 진행
        debugPrint('⚠️ [VideoRepository] 생체역학 분석 실패 (계속 진행): $e');
        debugPrint('⚠️ 스택 트레이스: $stackTrace');
      }

      // 4. workout_logs 테이블에 영상 메타데이터 저장
      if (onProgress != null) onProgress(0.9);

      // stability_warning 길이 제한 (DB VARCHAR 제한 대응)
      final stabilityWarning =
          analysisResult['stability_warning'] as String? ?? '';
      final truncatedWarning = _truncateWarning(
        stabilityWarning,
        maxLength: 500,
      );
      analysisResult['stability_warning'] = truncatedWarning;

      final videoResponse = await SupabaseService.instance.client
          .from('workout_logs')
          .insert({
            'user_id': userId,
            'video_path': videoUrl,
            'exercise_name': videoTitle,
            'body_part': bodyPart.value,
            'motion_type': motionType.value,
            'contraction_type': motionType.value,
            'status': 'COMPLETED',
            'analysis_result': analysisResult,
          })
          .select()
          .single();

      final videoId = (videoResponse['id'] ?? '')
          .toString(); // 안전 변환 (workout_logs.id)

      // 🔧 UUID 유효성 검사: 빈 문자열이면 예외 발생
      if (videoId.isEmpty) {
        throw Exception('workout_logs 테이블 저장 실패: ID가 반환되지 않았습니다.');
      }

      debugPrint('📹 workout_logs 테이블 저장 완료: $videoId');

      final logId = videoId; // workout_logs.id와 동일

      if (onProgress != null) onProgress(1.0);

      // 🔧 최종 UUID 유효성 검사: 반환 전에 한 번 더 확인
      if (videoId.isEmpty || logId.isEmpty) {
        throw Exception(
          '영상 업로드 완료되었으나 ID가 유효하지 않습니다. videoId=$videoId, logId=$logId',
        );
      }

      return {'logId': logId, 'videoId': videoId};
    } catch (e, stackTrace) {
      debugPrint('🔴 영상 업로드/분석 실패: $e');
      debugPrint('🔴 스택 트레이스: $stackTrace');
      rethrow;
    }
  }

  /// [motionType] 운동 방식 타입
  /// [targetArea] 사용자 선택 부위 (UPPER, LOWER, FULL)
  /// 반환: 전체 분석 결과 (`Map<String, dynamic>`) - detailed_muscle_usage, rom_data, biomech_pattern, stability_warning 포함
  // [Main Function] 포즈 데이터로부터 근육 활성도 계산
  Future<Map<String, dynamic>> _calculateMuscleUsageFromPoses({
    required List<Pose> poses,
    required List<int> timestamps,
    required MotionType motionType,
    required String targetArea,
  }) async {
    if (poses.isEmpty) {
      return {
        'detailed_muscle_usage': <String, double>{},
        'rom_data': <String, double>{},
        'biomech_pattern': targetArea,
        'stability_warning': '',
      };
    }

    double duration = (timestamps.last - timestamps.first) / 1000.0;
    if (duration <= 0) duration = 1.0;

    // 레거시 변수들 (호환성을 위해 유지하되 실제로는 사용하지 않음)
    // 새로운 엔진에서는 performAnalysis가 landmarks와 dt만 사용합니다
    Map<String, double> jointDeltas = {};
    Map<String, double> jointVariances = {};
    Map<String, double> jointVelocities = {};
    Map<String, double> visibilityMap = {};
    double avgRhythm = 1.0; // 기본값

    // 4. 통합 분석 엔진 호출 (새로운 엔진: 프레임별 처리)
    // 프레임별로 landmarks를 추출하고 performAnalysis를 호출하여 결과를 누적
    final accumulatedMuscleUsage = <String, double>{};
    final accumulatedRomData = <String, double>{};
    String? biomechPattern;
    final accumulatedWarnings = <String>{};

    // 프레임별 처리
    for (int i = 0; i < poses.length; i++) {
      final pose = poses[i];
      final landmarks = extractLandmarks(pose);

      if (landmarks.isEmpty) continue;

      // dt 계산 (초 단위)
      double dt = 0.033; // 기본값 (30fps 기준)
      if (i > 0 && timestamps.length > i) {
        dt = (timestamps[i] - timestamps[i - 1]) / 1000.0;
        if (dt <= 0.0 || dt > 0.1) dt = 0.033; // 안전 장치
      }

      // performAnalysis 호출
      final frameResult = MuscleMetricUtils.performAnalysis(
        landmarks: landmarks,
        dt: dt,
        jointDeltas: jointDeltas, // 호환성을 위해 전달 (내부에서는 ignore)
        jointVariances: jointVariances,
        jointVelocities: jointVelocities,
        visibilityMap: visibilityMap,
        duration: duration,
        averageRhythmScore: avgRhythm,
        motionType: motionType.toString().split('.').last,
        targetArea: targetArea,
      );

      // 결과 누적 (평균화)
      final frameMuscleUsage =
          frameResult['detailed_muscle_usage'] as Map<String, double>? ?? {};
      frameMuscleUsage.forEach((muscle, score) {
        accumulatedMuscleUsage[muscle] =
            (accumulatedMuscleUsage[muscle] ?? 0.0) + score;
      });

      final frameRomData =
          frameResult['rom_data'] as Map<String, double>? ?? {};
      frameRomData.forEach((joint, score) {
        accumulatedRomData[joint] = (accumulatedRomData[joint] ?? 0.0) + score;
      });

      // biomech_pattern은 첫 번째 유효한 프레임에서 가져옴
      biomechPattern ??= frameResult['biomech_pattern'] as String?;

      // warning은 중복 제거하여 누적
      final warning = frameResult['stability_warning'] as String? ?? '';
      if (warning.isNotEmpty) {
        accumulatedWarnings.add(warning);
      }
    }

    // 평균 계산
    final frameCount = poses.length;
    if (frameCount > 0) {
      accumulatedMuscleUsage.forEach((muscle, sum) {
        accumulatedMuscleUsage[muscle] = sum / frameCount;
      });
      accumulatedRomData.forEach((joint, sum) {
        accumulatedRomData[joint] = sum / frameCount;
      });
    }

    // 최종 결과 구성
    final analysisResult = {
      'detailed_muscle_usage': accumulatedMuscleUsage,
      'rom_data': accumulatedRomData,
      'biomech_pattern': biomechPattern ?? targetArea,
      'stability_warning': accumulatedWarnings.join('. '),
      'engine_version': 'v2_biomechanics', // 새 엔진 사용 표시
    };

    // 전체 결과 반환
    return analysisResult;
  }

  // [Helper] Warning 문자열 길이 제한 (DB VARCHAR 제한 대응)
  String _truncateWarning(String warning, {int maxLength = 500}) {
    if (warning.length <= maxLength) {
      return warning;
    }

    // 핵심 경고 1개만 추출 (첫 번째 문장)
    final firstSentence = warning.split('.').first;
    if (firstSentence.length <= maxLength) {
      return '$firstSentence.';
    }

    // 그래도 길면 자르기
    return '${warning.substring(0, maxLength - 3)}...';
  }

  /// 랜드마크 추출 (PoseLandmark → Point3D)
  ///
  /// 현재 프레임의 PoseLandmark에서 필요한 주요 관절의 x, y, z, visibility를 추출하여
  /// Point3D 객체로 변환합니다.
  ///
  /// **반환:** `Map<String, Point3D>` 형태의 랜드마크 맵
  /// - 키: 'left_shoulder', 'right_shoulder', 'left_hip', 'right_hip' 등
  Map<String, Point3D> extractLandmarks(Pose pose) {
    final landmarks = <String, Point3D>{};

    // 주요 관절 추출
    final landmarkTypes = {
      'left_shoulder': PoseLandmarkType.leftShoulder,
      'right_shoulder': PoseLandmarkType.rightShoulder,
      'left_hip': PoseLandmarkType.leftHip,
      'right_hip': PoseLandmarkType.rightHip,
      'left_knee': PoseLandmarkType.leftKnee,
      'right_knee': PoseLandmarkType.rightKnee,
      'left_ankle': PoseLandmarkType.leftAnkle,
      'right_ankle': PoseLandmarkType.rightAnkle,
      'left_elbow': PoseLandmarkType.leftElbow,
      'right_elbow': PoseLandmarkType.rightElbow,
      'left_wrist': PoseLandmarkType.leftWrist,
      'right_wrist': PoseLandmarkType.rightWrist,
      'left_ear': PoseLandmarkType.leftEar,
      'right_ear': PoseLandmarkType.rightEar,
      'left_foot_index': PoseLandmarkType.leftFootIndex,
      'right_foot_index': PoseLandmarkType.rightFootIndex,
    };

    for (final entry in landmarkTypes.entries) {
      final key = entry.key;
      final type = entry.value;

      final landmark = pose.landmarks[type];
      if (landmark != null) {
        landmarks[key] = Point3D.fromPoseLandmark(landmark);
      }
    }

    return landmarks;
  }
}
