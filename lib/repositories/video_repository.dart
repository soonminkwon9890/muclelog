import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';
import '../services/muscle_usage_analysis_service.dart';
import '../services/pose_detection_service.dart';
import '../services/gemini_workout_service.dart';
import '../models/analysis_log.dart';
import '../models/motion_type.dart';
import '../models/body_part.dart';
import '../utils/muscle_metric_utils.dart';

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

      // 5. Pose 데이터 기반 근육 활성도 계산 및 analysis_result에 추가
      Map<String, double> muscleUsage = {};
      List<Pose> poses = [];
      List<int> timestamps = [];

      try {
        // 비디오에서 Pose 추출 (timestamp 포함)
        final poseResult = await PoseDetectionService.instance
            .extractPosesFromVideoOptimized(
              videoFile: videoFile,
              sampleRate: 5, // 1초에 5프레임
              onProgress: (progress) {
                if (onProgress != null) {
                  onProgress(0.95 + (progress * 0.02)); // 95% ~ 97%
                }
              },
            );

        poses = poseResult.poses;
        timestamps = poseResult.timestamps;

        debugPrint('✅ [VideoRepository] Pose 추출 완료: ${poses.length}개');
        debugPrint(
          '✅ [VideoRepository] Timestamp 추출 완료: ${timestamps.length}개',
        );

        // 근육 활성도 계산 (Pose 데이터 사용)
        if (poses.length >= 2) {
          debugPrint('💪 [VideoRepository] 근육 활성도 계산 시작');
          muscleUsage = await _calculateMuscleUsageFromPoses(
            poses: poses,
            timestamps: timestamps,
            motionType: motionType,
          );
          debugPrint(
            '✅ [VideoRepository] 근육 활성도 계산 완료: ${muscleUsage.length}개 근육',
          );

          // localResult에 muscle_usage 추가
          localResult['muscle_usage'] = muscleUsage;
          debugPrint(
            '📊 [VideoRepository] analysis_result에 muscle_usage 추가 완료',
          );
        } else {
          debugPrint('⚠️ [VideoRepository] Pose 데이터가 부족하여 근육 활성도 계산 건너뜀');
        }
      } catch (e, stackTrace) {
        // 근육 활성도 계산 실패는 치명적이지 않으므로 로그만 남기고 계속 진행
        debugPrint('⚠️ [VideoRepository] 근육 활성도 계산 실패 (계속 진행): $e');
        debugPrint('⚠️ 스택 트레이스: $stackTrace');
      }

      // 6. analysis_result 업데이트 (muscle_usage 포함)
      if (muscleUsage.isNotEmpty) {
        await SupabaseService.instance.client
            .from('workout_logs')
            .update({
              'analysis_result': localResult, // muscle_usage 포함된 최신 데이터
            })
            .eq('id', videoId);
        debugPrint(
          '📝 [VideoRepository] analysis_result 업데이트 완료 (muscle_usage 포함)',
        );
      }

      // 7. Gemini 백엔드 분석 수행 (Pose 데이터 기반)
      if (onProgress != null) onProgress(0.97);
      debugPrint('🤖 [VideoRepository] Gemini 백엔드 분석 시작');

      try {
        // Pose 데이터는 이미 추출되어 있음 (위에서 사용)

        // Gemini 백엔드로 분석 요청 (timestamp 포함)
        final geminiResult = await GeminiWorkoutService.instance
            .analyzeWorkoutWithGemini(
              poses: poses,
              timestamps: timestamps,
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

  /// Pose 리스트를 사용하여 근육 활성도 계산
  /// [poses] 추출된 Pose 리스트
  /// [timestamps] 각 Pose에 해당하는 timestamp 리스트
  /// [motionType] 운동 방식 타입
  /// 반환: 근육별 활성도 맵 (`Map<String, double>`)
  Future<Map<String, double>> _calculateMuscleUsageFromPoses({
    required List<Pose> poses,
    required List<int> timestamps,
    required MotionType motionType,
  }) async {
    if (poses.length < 2) {
      return {};
    }

    final muscleUsageMap = <String, double>{};
    final jointDeltasMap = <String, List<double>>{};

    // 모든 관절에 대해 초기화
    final jointNames = [
      'neck',
      'spine',
      'shoulder',
      'elbow',
      'wrist',
      'hip',
      'knee',
      'ankle',
    ];
    for (final jointName in jointNames) {
      jointDeltasMap[jointName] = [];
    }

    // Pose 리스트를 순회하면서 관절 각도 변화 계산
    for (int i = 1; i < poses.length; i++) {
      final prevPose = poses[i - 1];
      final currPose = poses[i];

      // 각 관절의 각도 변화 계산
      final angleChanges = _calculateJointAngleChanges(prevPose, currPose);

      // 관절별로 변화량 누적
      for (final entry in angleChanges.entries) {
        final jointName = entry.key;
        final delta = entry.value;
        if (delta != null && delta.abs() > 0.1) {
          // 유의미한 변화만 저장
          jointDeltasMap[jointName]?.add(delta.abs());
        }
      }
    }

    // 관절별 평균 변화량 계산 (jointDeltas)
    final jointDeltas = <String, double>{};
    for (final entry in jointDeltasMap.entries) {
      final jointName = entry.key;
      final deltas = entry.value;
      if (deltas.isNotEmpty) {
        final avgDelta = deltas.reduce((a, b) => a + b) / deltas.length;
        jointDeltas[jointName] = avgDelta;
      } else {
        jointDeltas[jointName] = 0.0;
      }
    }

    // 대표 프레임 선택 (첫 번째와 중간 프레임)
    final midIndex = (poses.length / 2).floor();
    final prevPose = poses[0];
    final currPose = poses[midIndex];

    // MuscleMetricUtils를 사용하여 근육 활성도 계산
    try {
      final analysisResult = MuscleMetricUtils.performPhysicsBasedAnalysis(
        prevPose: prevPose,
        currPose: currPose,
        jointDeltas: jointDeltas,
      );

      // 결과에서 muscleUsage 추출
      final muscleUsage = analysisResult['muscleUsage'] as Map<String, double>?;
      if (muscleUsage != null) {
        muscleUsageMap.addAll(muscleUsage);
      }
    } catch (e, stackTrace) {
      debugPrint('⚠️ [VideoRepository] performPhysicsBasedAnalysis 실패: $e');
      debugPrint('⚠️ 스택 트레이스: $stackTrace');
    }

    return muscleUsageMap;
  }

  /// 두 Pose 간의 관절 각도 변화 계산
  /// [prevPose] 이전 프레임의 Pose
  /// [currPose] 현재 프레임의 Pose
  /// 반환: 관절별 각도 변화 맵
  Map<String, double?> _calculateJointAngleChanges(
    Pose prevPose,
    Pose currPose,
  ) {
    final angleChanges = <String, double?>{};

    // 각 관절의 각도 변화 계산
    // MuscleUsageAnalysisService의 로직을 참고하여 간단하게 구현
    try {
      // 어깨 각도 변화
      final prevLeftShoulder =
          prevPose.landmarks[PoseLandmarkType.leftShoulder];
      final prevRightShoulder =
          prevPose.landmarks[PoseLandmarkType.rightShoulder];
      final currLeftShoulder =
          currPose.landmarks[PoseLandmarkType.leftShoulder];
      final currRightShoulder =
          currPose.landmarks[PoseLandmarkType.rightShoulder];

      if (prevLeftShoulder != null &&
          prevRightShoulder != null &&
          currLeftShoulder != null &&
          currRightShoulder != null) {
        final prevAngle = _calculateAngle(
          prevLeftShoulder,
          prevRightShoulder,
          prevLeftShoulder,
        );
        final currAngle = _calculateAngle(
          currLeftShoulder,
          currRightShoulder,
          currLeftShoulder,
        );
        angleChanges['shoulder'] = (currAngle - prevAngle).abs();
      }

      // 무릎 각도 변화
      final prevLeftKnee = prevPose.landmarks[PoseLandmarkType.leftKnee];
      final prevLeftHip = prevPose.landmarks[PoseLandmarkType.leftHip];
      final prevLeftAnkle = prevPose.landmarks[PoseLandmarkType.leftAnkle];
      final currLeftKnee = currPose.landmarks[PoseLandmarkType.leftKnee];
      final currLeftHip = currPose.landmarks[PoseLandmarkType.leftHip];
      final currLeftAnkle = currPose.landmarks[PoseLandmarkType.leftAnkle];

      if (prevLeftKnee != null &&
          prevLeftHip != null &&
          prevLeftAnkle != null &&
          currLeftKnee != null &&
          currLeftHip != null &&
          currLeftAnkle != null) {
        final prevAngle = _calculateAngle(
          prevLeftHip,
          prevLeftKnee,
          prevLeftAnkle,
        );
        final currAngle = _calculateAngle(
          currLeftHip,
          currLeftKnee,
          currLeftAnkle,
        );
        angleChanges['knee'] = (currAngle - prevAngle).abs();
      }

      // 고관절 각도 변화
      final prevRightHip = prevPose.landmarks[PoseLandmarkType.rightHip];
      final currRightHip = currPose.landmarks[PoseLandmarkType.rightHip];
      final prevRightKnee = prevPose.landmarks[PoseLandmarkType.rightKnee];
      final currRightKnee = currPose.landmarks[PoseLandmarkType.rightKnee];

      if (prevRightHip != null &&
          prevRightKnee != null &&
          currRightHip != null &&
          currRightKnee != null) {
        final prevAngle = _calculateAngle(
          prevRightHip,
          prevRightKnee,
          prevRightHip,
        );
        final currAngle = _calculateAngle(
          currRightHip,
          currRightKnee,
          currRightHip,
        );
        angleChanges['hip'] = (currAngle - prevAngle).abs();
      }

      // 팔꿈치 각도 변화
      final prevLeftElbow = prevPose.landmarks[PoseLandmarkType.leftElbow];
      final prevLeftWrist = prevPose.landmarks[PoseLandmarkType.leftWrist];
      final currLeftElbow = currPose.landmarks[PoseLandmarkType.leftElbow];
      final currLeftWrist = currPose.landmarks[PoseLandmarkType.leftWrist];

      if (prevLeftElbow != null &&
          prevLeftWrist != null &&
          currLeftElbow != null &&
          currLeftWrist != null) {
        final prevAngle = _calculateAngle(
          prevLeftElbow,
          prevLeftWrist,
          prevLeftElbow,
        );
        final currAngle = _calculateAngle(
          currLeftElbow,
          currLeftWrist,
          currLeftElbow,
        );
        angleChanges['elbow'] = (currAngle - prevAngle).abs();
      }

      // 나머지 관절들도 유사하게 계산 (간단화를 위해 기본값 0.0)
      angleChanges['neck'] = 0.0;
      angleChanges['spine'] = 0.0;
      angleChanges['wrist'] = 0.0;
      angleChanges['ankle'] = 0.0;
    } catch (e) {
      debugPrint('⚠️ [VideoRepository] 관절 각도 계산 오류: $e');
      // 오류 발생 시 모든 관절을 0.0으로 설정
      for (final jointName in [
        'neck',
        'spine',
        'shoulder',
        'elbow',
        'wrist',
        'hip',
        'knee',
        'ankle',
      ]) {
        angleChanges[jointName] = 0.0;
      }
    }

    return angleChanges;
  }

  /// 세 점을 사용하여 각도 계산 (도 단위)
  /// [point1] 첫 번째 점
  /// [point2] 중간 점 (각도의 꼭짓점)
  /// [point3] 세 번째 점
  /// 반환: 각도 (도 단위)
  double _calculateAngle(
    PoseLandmark point1,
    PoseLandmark point2,
    PoseLandmark point3,
  ) {
    // 벡터 계산
    final v1x = point1.x - point2.x;
    final v1y = point1.y - point2.y;
    final v2x = point3.x - point2.x;
    final v2y = point3.y - point2.y;

    // 내적과 크기 계산
    final dot = v1x * v2x + v1y * v2y;
    final mag1 = math.sqrt(v1x * v1x + v1y * v1y);
    final mag2 = math.sqrt(v2x * v2x + v2y * v2y);

    if (mag1 == 0.0 || mag2 == 0.0) {
      return 0.0;
    }

    // 각도 계산 (라디안 → 도)
    final cosAngle = dot / (mag1 * mag2);
    final angleRad = math.acos(cosAngle.clamp(-1.0, 1.0));
    return angleRad * 180.0 / math.pi;
  }
}
