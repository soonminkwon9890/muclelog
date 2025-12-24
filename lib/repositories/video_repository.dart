import 'dart:io';
import 'package:flutter/foundation.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';
import '../services/muscle_usage_analysis_service.dart';
import '../services/pose_detection_service.dart';
import '../services/gemini_workout_service.dart';
import '../models/analysis_log.dart';
import '../models/motion_type.dart';
import '../models/body_part.dart';

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
      // 1. 로컬 분석 수행
      if (onProgress != null) onProgress(0.1);
      debugPrint('📊 로컬 영상 분석 시작 (타겟 부위: $targetArea)');

      final localResult = await MuscleUsageAnalysisService.instance
          .analyzeVideo(
            videoFile,
            targetArea: targetArea,
            motionType: motionType,
            onProgress: (progress) {
              if (onProgress != null) {
                onProgress(0.1 + (progress * 0.6)); // 10% ~ 70%
              }
            },
          );
      debugPrint('🟢 로컬 영상 분석 완료: $localResult');

      // 2. 영상 파일명 생성 및 Storage 업로드
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.mp4';
      final storagePath = StorageService.instance.generateVideoPath(
        userId,
        fileName,
      );

      if (onProgress != null) onProgress(0.7);
      final videoUrl = await StorageService.instance.uploadVideo(
        file: videoFile,
        path: storagePath,
        onProgress: (progress) {
          if (onProgress != null) {
            onProgress(0.7 + (progress * 0.2)); // 70% ~ 90%
          }
        },
      );

      // 3. workout_logs 테이블에 영상 메타데이터 저장
      // 🔧 중요: videos 테이블이 삭제되고 workout_logs로 통합됨
      if (onProgress != null) onProgress(0.9);
      final videoResponse = await SupabaseService.instance.client
          .from('workout_logs')
          .insert({
            'user_id': userId,
            'video_path': videoUrl, // video_url -> video_path
            'exercise_name': videoTitle, // video_title -> exercise_name
            'body_part': bodyPart
                .value, // target_area -> body_part (BodyPart enum value)
            'motion_type': motionType.value, // 운동 방식 타입 저장
            'contraction_type': motionType.value, // contraction_type 추가
            'analysis_result': localResult, // 로컬 분석 결과 저장 (하위 호환성)
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

      // 4. workout_logs 테이블 업데이트 (추가 분석 데이터 저장)
      // 이미 workout_logs에 기본 정보가 저장되어 있으므로, 추가 데이터만 update
      // reference_gravity 추출 (ISOMETRIC일 때만)
      List<double>? referenceGravity;
      if (motionType == MotionType.isometric &&
          localResult['reference_gravity'] != null) {
        referenceGravity = List<double>.from(
          localResult['reference_gravity'] as List,
        );
      }

      // analysis_raw_data 구성 (운동 타입별 Raw Data)
      Map<String, dynamic>? analysisRawData;
      switch (motionType) {
        case MotionType.isometric:
          analysisRawData = {
            'gravity_angle_deviations': localResult['raw_data'] ?? [],
            'reference_gravity': referenceGravity,
          };
          break;
        case MotionType.isokinetic:
          analysisRawData = {
            'angular_velocities': localResult['raw_data'] ?? [],
            'timestamps': localResult['timestamps'] ?? [],
          };
          break;
        case MotionType.isotonic:
          analysisRawData = {
            'usage_distribution': localResult['usage_distribution'] ?? {},
            'total_activity_score': localResult['total_activity_score'] ?? 0.0,
          };
          break;
      }

      // workout_logs 테이블 업데이트 (추가 필드)
      await SupabaseService.instance.client
          .from('workout_logs')
          .update({
            'status': 'COMPLETED',
            'analysis_result': localResult, // 기존 형식 (하위 호환성)
            'reference_gravity': referenceGravity, // 등척성 운동용 중력 벡터
            'analysis_raw_data': analysisRawData, // 원본 측정 데이터
          })
          .eq('id', videoId);

      final logId = videoId; // workout_logs.id와 동일

      // 🔧 UUID 유효성 재확인
      if (logId.isEmpty) {
        throw Exception('workout_logs 테이블 업데이트 실패: ID가 유효하지 않습니다.');
      }

      debugPrint('📝 workout_logs 테이블 업데이트 완료: $logId');

      // 5. Gemini 백엔드 분석 수행 (Pose 데이터 기반)
      if (onProgress != null) onProgress(0.95);
      debugPrint('🤖 [VideoRepository] Gemini 백엔드 분석 시작');

      try {
        // 비디오에서 Pose 추출
        final poses = await PoseDetectionService.instance
            .extractPosesFromVideoOptimized(
              videoFile: videoFile,
              sampleRate: 5, // 1초에 5프레임
              onProgress: (progress) {
                if (onProgress != null) {
                  onProgress(0.99 + (progress * 0.01)); // 99% ~ 100%
                }
              },
            );

        debugPrint('✅ [VideoRepository] Pose 추출 완료: ${poses.length}개');

        // Gemini 백엔드로 분석 요청
        final geminiResult = await GeminiWorkoutService.instance
            .analyzeWorkoutWithGemini(
              poses: poses,
              bodyPart: bodyPart,
              motionType: motionType,
              exerciseName: videoTitle,
              userId: userId,
              logId: videoId, // videoId (UUID) 사용
            );

        debugPrint('✅ [VideoRepository] Gemini 분석 완료');
        debugPrint(
          '   - Overall Score: ${geminiResult['scores']?['overall_score']}',
        );
        debugPrint('   - Applied Logics: ${geminiResult['applied_logics']}');

        // 참고: Gemini 분석 결과는 백엔드(analyze-workout.ts)에서 이미
        // Supabase의 analysis_core_results 테이블에 저장됩니다.
        // 추가 저장 로직이 필요하지 않습니다.
      } catch (e, stackTrace) {
        // Gemini 분석 실패는 치명적이지 않으므로 로그만 남기고 계속 진행
        debugPrint('⚠️ [VideoRepository] Gemini 분석 실패 (계속 진행): $e');
        debugPrint('⚠️ 스택 트레이스: $stackTrace');
      }

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
}
