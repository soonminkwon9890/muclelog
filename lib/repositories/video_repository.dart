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
            targetArea: targetArea,
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

  /// 단일 Pose에서 관절의 절대 각도 계산
  /// [pose] 현재 프레임의 Pose
  /// 반환: 관절별 절대 각도 맵 (도 단위)
  Map<String, double?> _calculateJointAbsoluteAngles(Pose pose) {
    final angles = <String, double?>{};

    try {
      // 어깨 각도 (왼쪽 어깨-팔꿈치-손목)
      final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
      final leftElbow = pose.landmarks[PoseLandmarkType.leftElbow];
      final leftWrist = pose.landmarks[PoseLandmarkType.leftWrist];
      if (leftShoulder != null && leftElbow != null && leftWrist != null) {
        angles['shoulder'] = _calculateAngle(
          leftShoulder,
          leftElbow,
          leftWrist,
        );
      }

      // 무릎 각도 (고관절-무릎-발목)
      final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
      final leftKnee = pose.landmarks[PoseLandmarkType.leftKnee];
      final leftAnkle = pose.landmarks[PoseLandmarkType.leftAnkle];
      if (leftHip != null && leftKnee != null && leftAnkle != null) {
        angles['knee'] = _calculateAngle(leftHip, leftKnee, leftAnkle);
      }

      // 고관절 각도 (어깨-고관절-무릎)
      final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
      final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
      final rightKnee = pose.landmarks[PoseLandmarkType.rightKnee];
      if (rightShoulder != null && rightHip != null && rightKnee != null) {
        angles['hip'] = _calculateAngle(rightShoulder, rightHip, rightKnee);
      }

      // 팔꿈치 각도 (어깨-팔꿈치-손목)
      final rightElbow = pose.landmarks[PoseLandmarkType.rightElbow];
      final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];
      if (leftShoulder != null && rightElbow != null && rightWrist != null) {
        angles['elbow'] = _calculateAngle(leftShoulder, rightElbow, rightWrist);
      }

      // 나머지 관절들은 기본값 null
      angles['neck'] = null;
      angles['spine'] = null;
      angles['wrist'] = null;
      angles['ankle'] = null;
    } catch (e) {
      debugPrint('⚠️ [VideoRepository] 절대 각도 계산 오류: $e');
    }

    return angles;
  }

  /// 반복 패턴 감지 (등장성 운동: 증가-감소 패턴)
  /// [angles] 관절 각도 시퀀스
  /// 반환: 반복 패턴이 감지되면 true
  bool _detectRepetitionPattern(List<double> angles) {
    if (angles.length < 3) {
      return false;
    }

    // 🔧 Peak-to-Peak 패턴 감지: 최소 2번 이상 증가-감소 패턴이 있어야 함
    int directionChanges = 0; // 방향 전환 횟수
    bool? prevDirection; // true: 증가, false: 감소, null: 초기

    for (int i = 1; i < angles.length; i++) {
      final diff = angles[i] - angles[i - 1];
      final threshold = 2.0; // 2도 이상 변화만 유의미한 것으로 간주

      if (diff.abs() < threshold) {
        continue; // 미세한 변화는 무시
      }

      final currentDirection = diff > 0; // 증가면 true, 감소면 false

      if (prevDirection != null && prevDirection != currentDirection) {
        // 방향이 바뀌었음 (증가 -> 감소 또는 감소 -> 증가)
        directionChanges++;
      }

      prevDirection = currentDirection;
    }

    // 🔧 방향 전환이 2번 이상이면 반복 패턴으로 간주
    // (예: 증가 -> 감소 -> 증가 = 2번 전환 = 1회 반복)
    return directionChanges >= 2;
  }

  /// [motionType] 운동 방식 타입
  /// [targetArea] 사용자 선택 부위 (UPPER, LOWER, FULL)
  /// 반환: 근육별 활성도 맵 (`Map<String, double>`)
  Future<Map<String, double>> _calculateMuscleUsageFromPoses({
    required List<Pose> poses,
    required List<int> timestamps,
    required MotionType motionType,
    required String targetArea,
  }) async {
    if (poses.length < 2) {
      return {};
    }

    // 🔧 1. 프레임 트리밍: 앞쪽 10%와 뒤쪽 10% 제거 (준비/마무리 동작 제거)
    final totalFrames = poses.length;
    final trimStart = (totalFrames * 0.1).floor();
    final trimEnd = (totalFrames * 0.9).floor();
    final trimmedPoses = poses.sublist(trimStart, trimEnd);

    if (trimmedPoses.length < 2) {
      debugPrint('⚠️ [VideoRepository] 트리밍 후 프레임이 부족함: ${trimmedPoses.length}');
      return {};
    }

    debugPrint(
      '✅ [VideoRepository] 프레임 트리밍: 전체 $totalFrames개 -> 분석 ${trimmedPoses.length}개 (앞 $trimStart개, 뒤 ${totalFrames - trimEnd}개 제거)',
    );

    final muscleUsageMap = <String, double>{};

    // 🔧 2. 각 관절의 각도 시퀀스 계산 (전체 프레임에 대해)
    final jointAnglesMap = <String, List<double>>{};
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
      jointAnglesMap[jointName] = [];
    }

    // 🔧 각 프레임에서 관절 각도 계산 (절대 각도)
    for (final pose in trimmedPoses) {
      final jointAngles = _calculateJointAbsoluteAngles(pose);
      for (final entry in jointAngles.entries) {
        final jointName = entry.key;
        final angle = entry.value;
        if (angle != null) {
          jointAnglesMap[jointName]?.add(angle);
        }
      }
    }

    // 🔧 3. Peak-to-Peak ROM 계산 및 최소 ROM 필터 (15도 미만 제거)
    final jointDeltas = <String, double>{};
    final jointPeakToPeakMap = <String, double>{};

    for (final entry in jointAnglesMap.entries) {
      final jointName = entry.key;
      final angles = entry.value;

      if (angles.isEmpty) {
        jointDeltas[jointName] = 0.0;
        jointPeakToPeakMap[jointName] = 0.0;
        continue;
      }

      // Peak-to-Peak 계산: 최고점 - 최저점
      final maxAngle = angles.reduce((a, b) => a > b ? a : b);
      final minAngle = angles.reduce((a, b) => a < b ? a : b);
      final peakToPeak = maxAngle - minAngle;
      jointPeakToPeakMap[jointName] = peakToPeak;

      // 🔧 최소 ROM 필터: 15도 미만인 관절은 0점 처리
      if (peakToPeak < 15.0) {
        jointDeltas[jointName] = 0.0;
        debugPrint(
          '🔇 [VideoRepository] 관절 $jointName: Peak-to-Peak ${peakToPeak.toStringAsFixed(1)}° < 15° -> 0점 처리 (미세 움직임 무시)',
        );
      } else {
        // 🔧 등장성 패턴 감지: 증가-감소 패턴 확인
        final hasRepetitionPattern = _detectRepetitionPattern(angles);
        if (hasRepetitionPattern) {
          // 반복 패턴이 있으면 Peak-to-Peak을 그대로 사용
          jointDeltas[jointName] = peakToPeak;
          debugPrint(
            '✅ [VideoRepository] 관절 $jointName: Peak-to-Peak ${peakToPeak.toStringAsFixed(1)}° (반복 패턴 감지)',
          );
        } else {
          // 단순히 한 번만 움직인 경우는 점수를 낮춤 (50% 감소)
          jointDeltas[jointName] = peakToPeak * 0.5;
          debugPrint(
            '⚠️ [VideoRepository] 관절 $jointName: Peak-to-Peak ${peakToPeak.toStringAsFixed(1)}° (반복 패턴 없음 -> 50% 감소)',
          );
        }
      }
    }

    // 🔧 4. 대표 프레임 선택 (트리밍된 프레임의 시작과 중간)
    final trimmedMidIndex = (trimmedPoses.length / 2).floor();
    final prevPose = trimmedPoses[0];
    final currPose = trimmedPoses[trimmedMidIndex];

    // MuscleMetricUtils를 사용하여 근육 활성도 계산
    try {
      final analysisResult = MuscleMetricUtils.performPhysicsBasedAnalysis(
        prevPose: prevPose,
        currPose: currPose,
        jointDeltas: jointDeltas,
        targetArea: targetArea,
      );

      // 결과에서 detailed_muscle_usage 추출 (performPhysicsBasedAnalysis의 반환값)
      final muscleUsage =
          analysisResult['detailed_muscle_usage'] as Map<String, double>?;
      if (muscleUsage != null) {
        muscleUsageMap.addAll(muscleUsage);
      }
    } catch (e, stackTrace) {
      debugPrint('⚠️ [VideoRepository] performPhysicsBasedAnalysis 실패: $e');
      debugPrint('⚠️ 스택 트레이스: $stackTrace');
    }

    return muscleUsageMap;
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
