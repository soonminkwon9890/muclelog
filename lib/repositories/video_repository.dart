import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../services/storage_service.dart';
import '../services/supabase_service.dart';
import '../services/pose_detection_service.dart';
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

    // 1. 관심 관절 정의 (요추 'spine' 포함)
    final interestJoints = [
      'leftHip',
      'rightHip',
      'leftKnee',
      'rightKnee',
      'leftAnkle', // [New] 발목 추가
      'rightAnkle', // [New] 발목 추가
      'leftShoulder',
      'rightShoulder',
      'leftElbow',
      'rightElbow',
      'spine',
    ];

    Map<String, double> jointDeltas = {};
    Map<String, double> jointVariances = {};
    Map<String, double> jointVelocities = {};
    Map<String, double> visibilityMap = {};

    double totalRhythmScore = 0.0;
    int validRhythmFrames = 0;

    // 2. 관절 데이터 추출 루프
    for (String joint in interestJoints) {
      List<double> angles = [];
      double totalDelta = 0.0;
      double totalVis = 0.0;

      for (int i = 0; i < poses.length; i++) {
        double angle = 0.0;
        double vis = 0.0;

        try {
          if (joint == 'spine') {
            // [Spine Special Logic] 어깨 중점과 골반 중점을 잇는 각도 계산
            final leftShoulder =
                poses[i].landmarks[PoseLandmarkType.leftShoulder]!;
            final rightShoulder =
                poses[i].landmarks[PoseLandmarkType.rightShoulder]!;
            final leftHip = poses[i].landmarks[PoseLandmarkType.leftHip]!;
            final rightHip = poses[i].landmarks[PoseLandmarkType.rightHip]!;

            double midShoulderX = (leftShoulder.x + rightShoulder.x) / 2;
            double midShoulderY = (leftShoulder.y + rightShoulder.y) / 2;
            double midHipX = (leftHip.x + rightHip.x) / 2;
            double midHipY = (leftHip.y + rightHip.y) / 2;

            angle =
                (math.atan2(midHipY - midShoulderY, midHipX - midShoulderX) *
                        180 /
                        math.pi)
                    .abs();
            // 4개 점의 평균 신뢰도 사용
            vis =
                (leftShoulder.likelihood +
                    rightShoulder.likelihood +
                    leftHip.likelihood +
                    rightHip.likelihood) /
                4;
          } else {
            // [General Joint Logic]
            angle = _extractJointAngle(poses[i], joint);
            vis = _extractJointVisibility(poses[i], joint);
          }
        } catch (e) {
          continue;
        }

        angles.add(angle);
        totalVis += vis;

        if (i > 0) {
          double d = (angles[i] - angles[i - 1]).abs();
          if (d < 30.0) totalDelta += d; // 급격한 튀는 값 필터링
        }
      }

      // 결과 저장
      jointDeltas[joint] = totalDelta;
      jointVelocities[joint] = totalDelta / duration;
      visibilityMap[joint] = angles.isNotEmpty
          ? (totalVis / angles.length)
          : 0.0;

      // 분산(Variance) 계산 - 등척성 안정성 분석용
      if (angles.isNotEmpty) {
        double mean = angles.reduce((a, b) => a + b) / angles.length;
        double variance =
            angles.map((a) => (a - mean) * (a - mean)).reduce((a, b) => a + b) /
            angles.length;
        jointVariances[joint] = variance;
      } else {
        jointVariances[joint] = 100.0; // 데이터 없으면 매우 불안정으로 간주
      }
    }

    // 3. 상완골 리듬 평균 계산
    for (var pose in poses) {
      try {
        double rhythm = MuscleMetricUtils.calculateInstantRhythm(
          shoulderY: pose.landmarks[PoseLandmarkType.leftShoulder]!.y,
          earY: pose.landmarks[PoseLandmarkType.leftEar]!.y,
          elbowX: pose.landmarks[PoseLandmarkType.leftElbow]!.x,
          elbowY: pose.landmarks[PoseLandmarkType.leftElbow]!.y,
          shoulderX: pose.landmarks[PoseLandmarkType.leftShoulder]!.x,
        );
        totalRhythmScore += rhythm;
        validRhythmFrames++;
      } catch (e) {
        // 상완골 리듬 계산 실패 시 해당 프레임은 무시하고 계속 진행
      }
    }
    double avgRhythm = validRhythmFrames > 0
        ? totalRhythmScore / validRhythmFrames
        : 1.0;

    // 4. 통합 분석 엔진 호출 (7개 파라미터 전달)
    final analysisResult = MuscleMetricUtils.performAnalysis(
      jointDeltas: jointDeltas,
      jointVariances: jointVariances,
      jointVelocities: jointVelocities,
      visibilityMap: visibilityMap,
      duration: duration,
      averageRhythmScore: avgRhythm,
      motionType: motionType.toString().split('.').last,
      targetArea: targetArea,
    );

    // 전체 결과 반환 (MuscleMetricUtils에서 이미 %로 계산된 rom_data 포함)
    return analysisResult;
  }

  // [Helper 1] 관절 각도 추출
  double _extractJointAngle(Pose pose, String joint) {
    double getAngle(
      PoseLandmarkType a,
      PoseLandmarkType b,
      PoseLandmarkType c,
    ) {
      final first = pose.landmarks[a]!;
      final mid = pose.landmarks[b]!;
      final last = pose.landmarks[c]!;
      double radians =
          math.atan2(last.y - mid.y, last.x - mid.x) -
          math.atan2(first.y - mid.y, first.x - mid.x);
      double angle = (radians * 180.0 / math.pi).abs();
      if (angle > 180.0) angle = 360.0 - angle;
      return angle;
    }

    switch (joint) {
      case 'leftKnee':
        return getAngle(
          PoseLandmarkType.leftHip,
          PoseLandmarkType.leftKnee,
          PoseLandmarkType.leftAnkle,
        );
      case 'rightKnee':
        return getAngle(
          PoseLandmarkType.rightHip,
          PoseLandmarkType.rightKnee,
          PoseLandmarkType.rightAnkle,
        );
      case 'leftHip':
        return getAngle(
          PoseLandmarkType.leftShoulder,
          PoseLandmarkType.leftHip,
          PoseLandmarkType.leftKnee,
        );
      case 'rightHip':
        return getAngle(
          PoseLandmarkType.rightShoulder,
          PoseLandmarkType.rightHip,
          PoseLandmarkType.rightKnee,
        );
      case 'leftShoulder':
        return getAngle(
          PoseLandmarkType.leftHip,
          PoseLandmarkType.leftShoulder,
          PoseLandmarkType.leftElbow,
        );
      case 'rightShoulder':
        return getAngle(
          PoseLandmarkType.rightHip,
          PoseLandmarkType.rightShoulder,
          PoseLandmarkType.rightElbow,
        );
      case 'leftElbow':
        return getAngle(
          PoseLandmarkType.leftShoulder,
          PoseLandmarkType.leftElbow,
          PoseLandmarkType.leftWrist,
        );
      case 'rightElbow':
        return getAngle(
          PoseLandmarkType.rightShoulder,
          PoseLandmarkType.rightElbow,
          PoseLandmarkType.rightWrist,
        );
      case 'leftAnkle':
        return getAngle(
          PoseLandmarkType.leftKnee,
          PoseLandmarkType.leftAnkle,
          PoseLandmarkType.leftHeel, // 발끝이 없으면 발뒤꿈치 사용
        );
      case 'rightAnkle':
        return getAngle(
          PoseLandmarkType.rightKnee,
          PoseLandmarkType.rightAnkle,
          PoseLandmarkType.rightHeel, // 발끝이 없으면 발뒤꿈치 사용
        );
      default:
        return 0.0;
    }
  }

  // [Helper 2] 관절 신뢰도 추출
  double _extractJointVisibility(Pose pose, String joint) {
    switch (joint) {
      case 'leftKnee':
        return pose.landmarks[PoseLandmarkType.leftKnee]!.likelihood;
      case 'rightKnee':
        return pose.landmarks[PoseLandmarkType.rightKnee]!.likelihood;
      case 'leftHip':
        return pose.landmarks[PoseLandmarkType.leftHip]!.likelihood;
      case 'rightHip':
        return pose.landmarks[PoseLandmarkType.rightHip]!.likelihood;
      case 'leftShoulder':
        return pose.landmarks[PoseLandmarkType.leftShoulder]!.likelihood;
      case 'rightShoulder':
        return pose.landmarks[PoseLandmarkType.rightShoulder]!.likelihood;
      case 'leftElbow':
        return pose.landmarks[PoseLandmarkType.leftElbow]!.likelihood;
      case 'rightElbow':
        return pose.landmarks[PoseLandmarkType.rightElbow]!.likelihood;
      case 'leftAnkle':
        return pose.landmarks[PoseLandmarkType.leftAnkle]!.likelihood;
      case 'rightAnkle':
        return pose.landmarks[PoseLandmarkType.rightAnkle]!.likelihood;
      default:
        return 0.0;
    }
  }
}
