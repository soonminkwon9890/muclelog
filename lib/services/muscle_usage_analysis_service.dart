// ignore_for_file: unused_element
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:image/image.dart' as img;
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import '../models/motion_type.dart';
import '../utils/muscle_metric_utils.dart';

/// 신체 부위별 움직임 기여도 분석 서비스
/// 영상 파일에서 각 신체 부위의 움직임 비율을 계산합니다.
class MuscleUsageAnalysisService {
  static MuscleUsageAnalysisService? _instance;
  static MuscleUsageAnalysisService get instance {
    _instance ??= MuscleUsageAnalysisService._();
    return _instance!;
  }

  Map<String, double>? _landmarkToMap(PoseLandmark? landmark) {
    if (!_isLandmarkReliable(landmark)) return null;
    return {'x': landmark!.x, 'y': landmark.y, 'z': landmark.z};
  }

  Map<String, double>? _midPointIfReliable(PoseLandmark? a, PoseLandmark? b) {
    if (!_areLandmarksReliable(a, b)) return null;
    return {'x': (a!.x + b!.x) / 2, 'y': (a.y + b.y) / 2, 'z': (a.z + b.z) / 2};
  }

  MuscleUsageAnalysisService._();

  /// 랜드마크 신뢰도 임계값 (ML Kit likelihood)
  static const double _confidenceThreshold = 0.75;

  /// 프레임 레벨 신뢰도 임계값 (Visibility Check)
  static const double _frameConfidenceThreshold = 0.5;

  /// 유령 움직임 방지: 관절별 visibility 임계값
  /// 0.65 미만인 관절은 INVALID 처리하여 계산에서 제외
  static const double _jointVisibilityThreshold = 0.65;

  /// 랜드마크의 likelihood가 임계값 이상인지 확인
  bool _isLandmarkReliable(PoseLandmark? landmark) {
    if (landmark == null) return false;
    return landmark.likelihood >= _confidenceThreshold;
  }

  /// 이전/현재 랜드마크 모두 신뢰 가능한지 확인
  bool _areLandmarksReliable(PoseLandmark? prev, PoseLandmark? curr) {
    return _isLandmarkReliable(prev) && _isLandmarkReliable(curr);
  }

  /// 프레임 레벨 신뢰도 체크 (모든 관절의 likelihood >= 0.5인지 확인)
  /// Low Confidence 프레임은 계산에서 제외하기 위해 사용
  bool _isFrameReliable(Pose pose) {
    // 주요 관절들의 likelihood 체크
    final requiredLandmarks = [
      PoseLandmarkType.nose,
      PoseLandmarkType.leftShoulder,
      PoseLandmarkType.rightShoulder,
      PoseLandmarkType.leftElbow,
      PoseLandmarkType.rightElbow,
      PoseLandmarkType.leftWrist,
      PoseLandmarkType.rightWrist,
      PoseLandmarkType.leftHip,
      PoseLandmarkType.rightHip,
      PoseLandmarkType.leftKnee,
      PoseLandmarkType.rightKnee,
      PoseLandmarkType.leftAnkle,
      PoseLandmarkType.rightAnkle,
    ];

    // 모든 주요 관절이 0.5 이상의 신뢰도를 가져야 함
    for (final landmarkType in requiredLandmarks) {
      final landmark = pose.landmarks[landmarkType];
      if (landmark == null || landmark.likelihood < _frameConfidenceThreshold) {
        return false;
      }
    }
    return true;
  }

  /// 두 벡터 사이의 각도 계산 (라디안)
  /// [point1], [point2], [point3]: 세 점으로 이루어진 각도 (point2가 꼭짓점)
  double _calculateAngle(
    Map<String, double>? point1,
    Map<String, double>? point2,
    Map<String, double>? point3,
  ) {
    if (point1 == null || point2 == null || point3 == null) return 0.0;

    // 벡터 계산
    final v1x = point1['x']! - point2['x']!;
    final v1y = point1['y']! - point2['y']!;
    final v2x = point3['x']! - point2['x']!;
    final v2y = point3['y']! - point2['y']!;

    // 내적과 크기 계산
    final dot = v1x * v2x + v1y * v2y;
    final mag1 = math.sqrt(v1x * v1x + v1y * v1y);
    final mag2 = math.sqrt(v2x * v2x + v2y * v2y);

    if (mag1 == 0.0 || mag2 == 0.0) return 0.0;

    // 각도 계산 (라디안 → 도)
    final cosAngle = dot / (mag1 * mag2);
    final clampedCos = cosAngle.clamp(-1.0, 1.0);
    return math.acos(clampedCos) * 180.0 / math.pi;
  }

  /// 영상 분석 수행
  /// [videoFile] 분석할 영상 파일
  /// [targetArea] 분석 타겟 부위 ('UPPER', 'LOWER', 'FULL') - 하위 호환성 유지
  /// [motionType] 운동 방식 타입 (ISOTONIC, ISOMETRIC, ISOKINETIC)
  /// [onProgress] 진행률 콜백 (0.0 ~ 1.0)
  ///
  /// 반환값: analysis_result JSONB 형식의 Map
  Future<Map<String, dynamic>> analyzeVideo(
    File videoFile, {
    String targetArea = 'FULL',
    MotionType motionType = MotionType.isotonic,
    Function(double)? onProgress,
  }) async {
    debugPrint('📊 영상 분석 시작: ${videoFile.path}');

    try {
      // Pose Detector 초기화
      final poseDetector = PoseDetector(
        options: PoseDetectorOptions(
          mode: PoseDetectionMode.single,
          model: PoseDetectionModel.accurate,
        ),
      );

      // 영상에서 프레임 추출 및 포즈 감지
      final frames = await _extractFramesFromVideo(
        videoFile,
        onProgress: onProgress,
      );
      debugPrint('📊 추출된 프레임 수: ${frames.length}');

      if (frames.isEmpty) {
        throw Exception('영상에서 프레임을 추출할 수 없습니다.');
      }

      // 각 프레임에서 포즈 감지 및 각도 변화 계산
      // 유령 움직임 방지: 관절별로 유효한 프레임의 각도만 저장
      final angleData = <String, List<double>>{
        'neck': [],
        'spine': [],
        'shoulder': [],
        'elbow': [],
        'wrist': [],
        'hip': [],
        'knee': [],
        'ankle': [],
      };

      // 관절별 유효 프레임 수 추적 (INVALID 제외)
      final validFrameCounts = <String, int>{
        'neck': 0,
        'spine': 0,
        'shoulder': 0,
        'elbow': 0,
        'wrist': 0,
        'hip': 0,
        'knee': 0,
        'ankle': 0,
      };

      // 관절별 INVALID 프레임 수 추적 (유령 움직임 방지)
      final invalidFrameCounts = <String, int>{
        'neck': 0,
        'spine': 0,
        'shoulder': 0,
        'elbow': 0,
        'wrist': 0,
        'hip': 0,
        'knee': 0,
        'ankle': 0,
      };

      // 관절별 전체 프레임 수 추적
      final totalFrameCounts = <String, int>{
        'neck': 0,
        'spine': 0,
        'shoulder': 0,
        'elbow': 0,
        'wrist': 0,
        'hip': 0,
        'knee': 0,
        'ankle': 0,
      };

      // 관절별 각도 값 저장 (ROM 계산용: Min/Max)
      final jointAngleValues = <String, List<double>>{
        'neck': [],
        'spine': [],
        'shoulder': [],
        'elbow': [],
        'wrist': [],
        'hip': [],
        'knee': [],
        'ankle': [],
      };

      Pose? previousPose;
      final allPoses = <Pose>[]; // 모든 포즈 저장 (물리적 상태 감지용)
      int processedFrames = 0;
      int skippedFrames = 0; // Low Confidence로 제외된 프레임 수

      // 운동 타입별 초기화
      Map<String, double>? refGravity; // 등척성: 초기 중력 벡터
      final gravityAngleDeviations = <double>[]; // 등척성: 각도 편차 리스트
      final angularVelocities = <double>[]; // 등속성: 각속도 리스트
      final frameTimestamps = <int>[]; // 등속성: 프레임 타임스탬프

      for (final frame in frames) {
        try {
          final inputImage = await _createInputImageFromImage(frame);
          final poses = await poseDetector.processImage(inputImage);

          if (poses.isNotEmpty) {
            final currentPose = poses.first;

            // 프레임 레벨 신뢰도 체크 (Visibility Check)
            // 모든 주요 관절의 likelihood >= 0.5인지 확인
            final isFrameReliable = _isFrameReliable(currentPose);

            if (!isFrameReliable) {
              skippedFrames++;
              debugPrint(
                '⚠️ Frame #${processedFrames + 1}: Low Confidence - 제외됨',
              );
              processedFrames++;
              if (onProgress != null) {
                onProgress(processedFrames / frames.length);
              }
              continue; // 이 프레임은 계산에서 제외
            }

            // 운동 타입별 분석
            switch (motionType) {
              case MotionType.isometric:
                // 등척성 운동: 중력 벡터 각도 분석
                // 첫 프레임에서 초기 중력 벡터 저장
                if (refGravity == null) {
                  refGravity = _extractGravityVector(currentPose);
                } else {
                  // 이후 프레임에서 각도 편차 계산
                  _analyzeIsometricMotion(
                    currentPose,
                    refGravity,
                    gravityAngleDeviations,
                  );
                }
                break;

              case MotionType.isokinetic:
                // 등속성 운동: 각속도 분석
                if (previousPose != null) {
                  _analyzeIsokineticMotion(
                    previousPose,
                    currentPose,
                    processedFrames,
                    angularVelocities,
                    frameTimestamps,
                  );
                }
                break;

              case MotionType.isotonic:
                // 등장성 운동: ROM 기반 분석 (유령 움직임 방지 적용)
                if (previousPose != null) {
                  // 각 관절별 visibility 추출
                  final jointVisibilities = _extractJointVisibilities(
                    currentPose,
                  );

                  // 각 관절별 각도 계산 및 유효성 검사
                  final angleChanges = _calculateAngleChangesWithValidation(
                    previousPose,
                    currentPose,
                    jointVisibilities,
                  );

                  // 각 관절별로 유효한 각도만 저장
                  for (final entry in angleChanges.entries) {
                    final jointName = entry.key;
                    final angleInfo =
                        entry.value; // {angle: double?, isValid: bool}

                    totalFrameCounts[jointName] =
                        (totalFrameCounts[jointName] ?? 0) + 1;

                    if (angleInfo['isValid'] == true) {
                      final angle = angleInfo['angle'] as double?;
                      if (angle != null && angle > 0) {
                        angleData[jointName]!.add(angle);
                        validFrameCounts[jointName] =
                            (validFrameCounts[jointName] ?? 0) + 1;
                      }
                    } else {
                      // INVALID 프레임 카운트 증가
                      invalidFrameCounts[jointName] =
                          (invalidFrameCounts[jointName] ?? 0) + 1;
                    }

                    // ROM 계산용: 유효한 각도 값 저장
                    if (angleInfo['isValid'] == true) {
                      final currentAngle = _getJointAngle(
                        currentPose,
                        jointName,
                      );
                      if (currentAngle != null) {
                        jointAngleValues[jointName]!.add(currentAngle);
                      }
                    }
                  }

                  // 디버그 로그는 생략 (성능 최적화)
                }
                break;
            }

            previousPose = currentPose;
            allPoses.add(currentPose); // 모든 포즈 저장
          }

          processedFrames++;
          if (onProgress != null) {
            onProgress(processedFrames / frames.length);
          }
        } catch (e) {
          debugPrint('⚠️ 프레임 처리 오류: $e');
          continue;
        }
      }

      debugPrint(
        '📊 분석 완료: 총 ${frames.length}프레임 중 $skippedFrames개 프레임 제외 (Low Confidence)',
      );

      // Pose Detector 정리
      await poseDetector.close();

      // 운동 타입별 결과 생성
      Map<String, dynamic> result;
      switch (motionType) {
        case MotionType.isometric:
          // 등척성 운동 결과
          result = _buildIsometricResult(
            refGravity,
            gravityAngleDeviations,
            poses: allPoses,
            timeDelta: 0.033, // 30fps 기준
          );
          break;

        case MotionType.isokinetic:
          // 등속성 운동 결과
          result = _buildIsokineticResult(angularVelocities, frameTimestamps);
          break;

        case MotionType.isotonic:
          // 등장성 운동 결과 (순수 역학 기반)
          result = _buildIsotonicResult(
            angleData,
            validFrameCounts,
            invalidFrameCounts,
            totalFrameCounts,
            jointAngleValues,
            allPoses,
            refGravity,
          );
          break;
      }

      debugPrint('🟢 영상 분석 완료 (타입: ${motionType.displayName})');
      debugPrint('📊 결과: $result');

      return result;
    } catch (e, stackTrace) {
      debugPrint('🔴 영상 분석 실패: $e');
      debugPrint('🔴 스택 트레이스: $stackTrace');
      rethrow;
    }
  }

  /// 영상에서 프레임 추출
  /// video_thumbnail을 사용하여 1초당 1프레임 샘플링
  Future<List<img.Image>> _extractFramesFromVideo(
    File videoFile, {
    Function(double)? onProgress,
  }) async {
    final frames = <img.Image>[];

    try {
      // 영상 정보 가져오기
      final controller = VideoPlayerController.file(videoFile);
      await controller.initialize();
      final duration = controller.value.duration;
      final totalSeconds = duration.inSeconds.clamp(1, 100); // 최대 100초
      await controller.dispose();

      debugPrint('📊 영상 정보: duration=$totalSeconds초');

      // 임시 디렉토리 생성
      final tempDir = await getTemporaryDirectory();
      final tempDirPath = tempDir.path;

      // video_thumbnail으로 여러 시간대의 썸네일 추출 (1초당 1프레임)
      for (int second = 0; second < totalSeconds; second++) {
        try {
          final thumbnailPath = await vt.VideoThumbnail.thumbnailFile(
            video: videoFile.path,
            thumbnailPath: tempDirPath,
            timeMs: second * 1000, // 밀리초 단위
            quality: 100, // 최고 품질
            imageFormat: vt.ImageFormat.PNG,
          );

          if (thumbnailPath != null) {
            final bytes = await File(thumbnailPath).readAsBytes();
            final image = img.decodeImage(bytes);

            if (image != null) {
              frames.add(image);
            }

            // 임시 파일 삭제
            try {
              await File(thumbnailPath).delete();
            } catch (e) {
              debugPrint('⚠️ 임시 파일 삭제 실패: $e');
            }
          }

          if (onProgress != null) {
            onProgress((second + 1) / totalSeconds);
          }
        } catch (e) {
          debugPrint('⚠️ $second초 프레임 추출 실패: $e');
          continue; // 개별 프레임 실패는 무시하고 계속 진행
        }
      }

      debugPrint('📊 총 추출된 프레임 수: ${frames.length}');

      if (frames.isEmpty) {
        throw Exception('영상에서 프레임을 추출할 수 없습니다.');
      }

      return frames;
    } catch (e, stackTrace) {
      debugPrint('🔴 프레임 추출 실패: $e');
      debugPrint('🔴 스택 트레이스: $stackTrace');
      rethrow;
    }
  }

  /// 두 포즈 간의 각도 변화 계산 (유령 움직임 방지 포함)
  /// [previousPose] 이전 프레임 포즈
  /// [currentPose] 현재 프레임 포즈
  /// [jointVisibilities] 관절별 visibility 맵
  /// 반환: 관절명 -> {angle: double?, isValid: bool} 맵
  Map<String, Map<String, dynamic>> _calculateAngleChangesWithValidation(
    Pose previousPose,
    Pose currentPose,
    Map<String, double> jointVisibilities,
  ) {
    final results = <String, Map<String, dynamic>>{};

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
      final visibility = jointVisibilities[jointName] ?? 0.0;

      // 유령 움직임 방지: visibility < 0.65인 관절은 INVALID 처리
      if (visibility < _jointVisibilityThreshold) {
        results[jointName] = {'angle': null, 'isValid': false};
        continue;
      }

      // 유효한 관절만 각도 변화 계산
      double? angleChange;
      switch (jointName) {
        case 'neck':
          angleChange = _calculateNeckAngleChange(previousPose, currentPose);
          break;
        case 'spine':
          angleChange = _calculateSpineAngleChange(previousPose, currentPose);
          break;
        case 'shoulder':
          angleChange = _calculateShoulderAngleChange(
            previousPose,
            currentPose,
          );
          break;
        case 'elbow':
          angleChange = _calculateElbowAngleChange(previousPose, currentPose);
          break;
        case 'wrist':
          angleChange = _calculateWristAngleChange(previousPose, currentPose);
          break;
        case 'hip':
          angleChange = _calculateHipAngleChange(previousPose, currentPose);
          break;
        case 'knee':
          angleChange = _calculateKneeAngleChange(previousPose, currentPose);
          break;
        case 'ankle':
          angleChange = _calculateAnkleAngleChange(previousPose, currentPose);
          break;
      }

      results[jointName] = {
        'angle': angleChange,
        'isValid': angleChange != null,
      };
    }

    return results;
  }

  /// 관절의 현재 각도 값 반환 (ROM 계산용)
  /// [pose] 현재 포즈
  /// [jointName] 관절명
  /// 반환: 관절 각도 (도 단위) 또는 null
  double? _getJointAngle(Pose pose, String jointName) {
    switch (jointName) {
      case 'neck':
        return _calculateNeckAngle(pose);
      case 'spine':
        return _calculateSpineAngle(pose);
      case 'shoulder':
        return _calculateShoulderAngle(pose);
      case 'elbow':
        return _calculateElbowAngleCurrent(pose);
      case 'wrist':
        return _calculateWristAngle(pose);
      case 'hip':
        return _calculateHipAngle(pose);
      case 'knee':
        return _calculateKneeAngle(pose);
      case 'ankle':
        return _calculateAnkleAngle(pose);
      default:
        return null;
    }
  }

  /// 두 포즈 간의 각도 변화 계산 (ROM 기반) - 기존 메서드 유지 (호환성)
  /// 각 관절의 각도 변화폭을 계산하여 반환
  Map<String, double?> _calculateAngleChanges(
    Pose previousPose,
    Pose currentPose,
  ) {
    return {
      'neck': _calculateNeckAngleChange(previousPose, currentPose),
      'spine': _calculateSpineAngleChange(previousPose, currentPose),
      'shoulder': _calculateShoulderAngleChange(previousPose, currentPose),
      'elbow': _calculateElbowAngleChange(previousPose, currentPose),
      'wrist': _calculateWristAngleChange(previousPose, currentPose),
      'hip': _calculateHipAngleChange(previousPose, currentPose),
      'knee': _calculateKneeAngleChange(previousPose, currentPose),
      'ankle': _calculateAnkleAngleChange(previousPose, currentPose),
    };
  }

  /// Neck 현재 각도 계산 (ROM 계산용)
  double? _calculateNeckAngle(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final nose = pose.landmarks[PoseLandmarkType.nose];

    if (!_areLandmarksReliable(nose, leftShoulder) ||
        !_areLandmarksReliable(nose, rightShoulder)) {
      return null;
    }

    final midShoulder = _midPointIfReliable(leftShoulder, rightShoulder);
    if (midShoulder == null) return null;

    // 코를 중심으로 한 각도 계산
    return _calculateAngle(midShoulder, _landmarkToMap(nose), midShoulder);
  }

  /// Spine 현재 각도 계산 (ROM 계산용)
  double? _calculateSpineAngle(Pose pose) {
    final shoulderMid = _midPointIfReliable(
      pose.landmarks[PoseLandmarkType.leftShoulder],
      pose.landmarks[PoseLandmarkType.rightShoulder],
    );
    final hipMid = _midPointIfReliable(
      pose.landmarks[PoseLandmarkType.leftHip],
      pose.landmarks[PoseLandmarkType.rightHip],
    );

    if (shoulderMid == null || hipMid == null) return null;

    // 수직선(0, -1)과의 각도 계산
    final vecX = hipMid['x']! - shoulderMid['x']!;
    final vecY = hipMid['y']! - shoulderMid['y']!;
    return math.atan2(vecY, vecX) * 180.0 / math.pi;
  }

  /// Shoulder 현재 각도 계산 (ROM 계산용)
  double? _calculateShoulderAngle(Pose pose) {
    final leftAngle = _calculateElbowAngleFromLandmarks(
      pose.landmarks[PoseLandmarkType.leftShoulder],
      pose.landmarks[PoseLandmarkType.leftElbow],
      pose.landmarks[PoseLandmarkType.leftWrist],
    );
    final rightAngle = _calculateElbowAngleFromLandmarks(
      pose.landmarks[PoseLandmarkType.rightShoulder],
      pose.landmarks[PoseLandmarkType.rightElbow],
      pose.landmarks[PoseLandmarkType.rightWrist],
    );

    if (leftAngle == null && rightAngle == null) return null;
    if (leftAngle == null) return rightAngle;
    if (rightAngle == null) return leftAngle;
    return (leftAngle + rightAngle) / 2.0;
  }

  /// Elbow 현재 각도 계산 (ROM 계산용)
  double? _calculateElbowAngleCurrent(Pose pose) {
    return _calculateShoulderAngle(pose); // 동일한 각도
  }

  /// Wrist 현재 각도 계산 (ROM 계산용)
  double? _calculateWristAngle(Pose pose) {
    final leftVec = _calculateVectorAngle(
      pose.landmarks[PoseLandmarkType.leftElbow],
      pose.landmarks[PoseLandmarkType.leftWrist],
    );
    final rightVec = _calculateVectorAngle(
      pose.landmarks[PoseLandmarkType.rightElbow],
      pose.landmarks[PoseLandmarkType.rightWrist],
    );

    if (leftVec == null && rightVec == null) return null;
    if (leftVec == null) return rightVec;
    if (rightVec == null) return leftVec;
    return (leftVec + rightVec) / 2.0;
  }

  /// Hip 현재 각도 계산 (ROM 계산용)
  double? _calculateHipAngle(Pose pose) {
    final leftAngle = _calculateElbowAngleFromLandmarks(
      pose.landmarks[PoseLandmarkType.leftShoulder],
      pose.landmarks[PoseLandmarkType.leftHip],
      pose.landmarks[PoseLandmarkType.leftKnee],
    );
    final rightAngle = _calculateElbowAngleFromLandmarks(
      pose.landmarks[PoseLandmarkType.rightShoulder],
      pose.landmarks[PoseLandmarkType.rightHip],
      pose.landmarks[PoseLandmarkType.rightKnee],
    );

    if (leftAngle == null && rightAngle == null) return null;
    if (leftAngle == null) return rightAngle;
    if (rightAngle == null) return leftAngle;
    return (leftAngle + rightAngle) / 2.0;
  }

  /// Knee 현재 각도 계산 (ROM 계산용)
  double? _calculateKneeAngle(Pose pose) {
    final leftAngle = _calculateElbowAngleFromLandmarks(
      pose.landmarks[PoseLandmarkType.leftHip],
      pose.landmarks[PoseLandmarkType.leftKnee],
      pose.landmarks[PoseLandmarkType.leftAnkle],
    );
    final rightAngle = _calculateElbowAngleFromLandmarks(
      pose.landmarks[PoseLandmarkType.rightHip],
      pose.landmarks[PoseLandmarkType.rightKnee],
      pose.landmarks[PoseLandmarkType.rightAnkle],
    );

    if (leftAngle == null && rightAngle == null) return null;
    if (leftAngle == null) return rightAngle;
    if (rightAngle == null) return leftAngle;
    return (leftAngle + rightAngle) / 2.0;
  }

  /// Ankle 현재 각도 계산 (ROM 계산용)
  double? _calculateAnkleAngle(Pose pose) {
    final leftVec = _calculateVectorAngle(
      pose.landmarks[PoseLandmarkType.leftKnee],
      pose.landmarks[PoseLandmarkType.leftAnkle],
    );
    final rightVec = _calculateVectorAngle(
      pose.landmarks[PoseLandmarkType.rightKnee],
      pose.landmarks[PoseLandmarkType.rightAnkle],
    );

    if (leftVec == null && rightVec == null) return null;
    if (leftVec == null) return rightVec;
    if (rightVec == null) return leftVec;
    return (leftVec + rightVec) / 2.0;
  }

  /// 세 점으로 이루어진 각도 계산 헬퍼 (현재 각도용)
  double? _calculateElbowAngleFromLandmarks(
    PoseLandmark? point1,
    PoseLandmark? point2,
    PoseLandmark? point3,
  ) {
    if (!_areLandmarksReliable(point1, point2) ||
        !_areLandmarksReliable(point2, point3)) {
      return null;
    }

    return _calculateAngle(
      _landmarkToMap(point1),
      _landmarkToMap(point2),
      _landmarkToMap(point3),
    );
  }

  /// 두 점으로 이루어진 벡터의 각도 계산 헬퍼 (현재 각도용)
  double? _calculateVectorAngle(PoseLandmark? from, PoseLandmark? to) {
    if (!_areLandmarksReliable(from, to)) return null;

    final vecX = to!.x - from!.x;
    final vecY = to.y - from.y;
    return math.atan2(vecY, vecX) * 180.0 / math.pi;
  }

  /// Neck 각도 변화 계산: 좌/우 어깨-코-어깨 각도
  double? _calculateNeckAngleChange(Pose prevPose, Pose currPose) {
    final prevLeftShoulder = prevPose.landmarks[PoseLandmarkType.leftShoulder];
    final prevRightShoulder =
        prevPose.landmarks[PoseLandmarkType.rightShoulder];
    final prevNose = prevPose.landmarks[PoseLandmarkType.nose];
    final currLeftShoulder = currPose.landmarks[PoseLandmarkType.leftShoulder];
    final currRightShoulder =
        currPose.landmarks[PoseLandmarkType.rightShoulder];
    final currNose = currPose.landmarks[PoseLandmarkType.nose];

    if (!_areLandmarksReliable(prevNose, currNose) ||
        !_areLandmarksReliable(prevLeftShoulder, currLeftShoulder) ||
        !_areLandmarksReliable(prevRightShoulder, currRightShoulder)) {
      return null;
    }

    final prevMidShoulder = _midPointIfReliable(
      prevLeftShoulder,
      prevRightShoulder,
    );
    final currMidShoulder = _midPointIfReliable(
      currLeftShoulder,
      currRightShoulder,
    );
    if (prevMidShoulder == null || currMidShoulder == null) return null;

    final prevAngle = _calculateAngle(
      prevMidShoulder,
      _landmarkToMap(prevNose),
      prevMidShoulder,
    );
    final currAngle = _calculateAngle(
      currMidShoulder,
      _landmarkToMap(currNose),
      currMidShoulder,
    );

    return (currAngle - prevAngle).abs();
  }

  /// Spine 각도 변화 계산: 어깨 중점-힙 중점 벡터의 각도 변화
  double? _calculateSpineAngleChange(Pose prevPose, Pose currPose) {
    final prevShoulderMid = _midPointIfReliable(
      prevPose.landmarks[PoseLandmarkType.leftShoulder],
      prevPose.landmarks[PoseLandmarkType.rightShoulder],
    );
    final prevHipMid = _midPointIfReliable(
      prevPose.landmarks[PoseLandmarkType.leftHip],
      prevPose.landmarks[PoseLandmarkType.rightHip],
    );
    final currShoulderMid = _midPointIfReliable(
      currPose.landmarks[PoseLandmarkType.leftShoulder],
      currPose.landmarks[PoseLandmarkType.rightShoulder],
    );
    final currHipMid = _midPointIfReliable(
      currPose.landmarks[PoseLandmarkType.leftHip],
      currPose.landmarks[PoseLandmarkType.rightHip],
    );

    if (prevShoulderMid == null ||
        prevHipMid == null ||
        currShoulderMid == null ||
        currHipMid == null) {
      return null;
    }

    // 수직선(0, -1)과의 각도 계산
    final prevVecX = prevHipMid['x']! - prevShoulderMid['x']!;
    final prevVecY = prevHipMid['y']! - prevShoulderMid['y']!;
    final currVecX = currHipMid['x']! - currShoulderMid['x']!;
    final currVecY = currHipMid['y']! - currShoulderMid['y']!;

    final prevAngle = math.atan2(prevVecY, prevVecX) * 180.0 / math.pi;
    final currAngle = math.atan2(currVecY, currVecX) * 180.0 / math.pi;

    return (currAngle - prevAngle).abs();
  }

  /// Shoulder 각도 변화 계산: 어깨-팔꿈치-손목 각도 (좌/우 평균)
  double? _calculateShoulderAngleChange(Pose prevPose, Pose currPose) {
    final leftAngle = _calculateElbowAngleChangeHelper(
      prevPose.landmarks[PoseLandmarkType.leftShoulder],
      prevPose.landmarks[PoseLandmarkType.leftElbow],
      prevPose.landmarks[PoseLandmarkType.leftWrist],
      currPose.landmarks[PoseLandmarkType.leftShoulder],
      currPose.landmarks[PoseLandmarkType.leftElbow],
      currPose.landmarks[PoseLandmarkType.leftWrist],
    );
    final rightAngle = _calculateElbowAngleChangeHelper(
      prevPose.landmarks[PoseLandmarkType.rightShoulder],
      prevPose.landmarks[PoseLandmarkType.rightElbow],
      prevPose.landmarks[PoseLandmarkType.rightWrist],
      currPose.landmarks[PoseLandmarkType.rightShoulder],
      currPose.landmarks[PoseLandmarkType.rightElbow],
      currPose.landmarks[PoseLandmarkType.rightWrist],
    );

    if (leftAngle == null && rightAngle == null) return null;
    if (leftAngle == null) return rightAngle;
    if (rightAngle == null) return leftAngle;
    return (leftAngle + rightAngle) / 2.0;
  }

  /// Elbow 각도 변화 계산: 어깨-팔꿈치-손목 각도 (좌/우 평균)
  double? _calculateElbowAngleChange(Pose prevPose, Pose currPose) {
    return _calculateShoulderAngleChange(prevPose, currPose); // 동일한 각도
  }

  /// Wrist 각도 변화 계산: 팔꿈치-손목 벡터의 각도 변화
  double? _calculateWristAngleChange(Pose prevPose, Pose currPose) {
    final leftAngle = _calculateVectorAngleChange(
      prevPose.landmarks[PoseLandmarkType.leftElbow],
      prevPose.landmarks[PoseLandmarkType.leftWrist],
      currPose.landmarks[PoseLandmarkType.leftElbow],
      currPose.landmarks[PoseLandmarkType.leftWrist],
    );
    final rightAngle = _calculateVectorAngleChange(
      prevPose.landmarks[PoseLandmarkType.rightElbow],
      prevPose.landmarks[PoseLandmarkType.rightWrist],
      currPose.landmarks[PoseLandmarkType.rightElbow],
      currPose.landmarks[PoseLandmarkType.rightWrist],
    );

    if (leftAngle == null && rightAngle == null) return null;
    if (leftAngle == null) return rightAngle;
    if (rightAngle == null) return leftAngle;
    return (leftAngle + rightAngle) / 2.0;
  }

  /// Hip 각도 변화 계산: 어깨-힙-무릎 각도 (좌/우 평균)
  double? _calculateHipAngleChange(Pose prevPose, Pose currPose) {
    final leftAngle = _calculateElbowAngleChangeHelper(
      prevPose.landmarks[PoseLandmarkType.leftShoulder],
      prevPose.landmarks[PoseLandmarkType.leftHip],
      prevPose.landmarks[PoseLandmarkType.leftKnee],
      currPose.landmarks[PoseLandmarkType.leftShoulder],
      currPose.landmarks[PoseLandmarkType.leftHip],
      currPose.landmarks[PoseLandmarkType.leftKnee],
    );
    final rightAngle = _calculateElbowAngleChangeHelper(
      prevPose.landmarks[PoseLandmarkType.rightShoulder],
      prevPose.landmarks[PoseLandmarkType.rightHip],
      prevPose.landmarks[PoseLandmarkType.rightKnee],
      currPose.landmarks[PoseLandmarkType.rightShoulder],
      currPose.landmarks[PoseLandmarkType.rightHip],
      currPose.landmarks[PoseLandmarkType.rightKnee],
    );

    if (leftAngle == null && rightAngle == null) return null;
    if (leftAngle == null) return rightAngle;
    if (rightAngle == null) return leftAngle;
    return (leftAngle + rightAngle) / 2.0;
  }

  /// Knee 각도 변화 계산: 힙-무릎-발목 각도 (좌/우 평균)
  double? _calculateKneeAngleChange(Pose prevPose, Pose currPose) {
    final leftAngle = _calculateElbowAngleChangeHelper(
      prevPose.landmarks[PoseLandmarkType.leftHip],
      prevPose.landmarks[PoseLandmarkType.leftKnee],
      prevPose.landmarks[PoseLandmarkType.leftAnkle],
      currPose.landmarks[PoseLandmarkType.leftHip],
      currPose.landmarks[PoseLandmarkType.leftKnee],
      currPose.landmarks[PoseLandmarkType.leftAnkle],
    );
    final rightAngle = _calculateElbowAngleChangeHelper(
      prevPose.landmarks[PoseLandmarkType.rightHip],
      prevPose.landmarks[PoseLandmarkType.rightKnee],
      prevPose.landmarks[PoseLandmarkType.rightAnkle],
      currPose.landmarks[PoseLandmarkType.rightHip],
      currPose.landmarks[PoseLandmarkType.rightKnee],
      currPose.landmarks[PoseLandmarkType.rightAnkle],
    );

    if (leftAngle == null && rightAngle == null) return null;
    if (leftAngle == null) return rightAngle;
    if (rightAngle == null) return leftAngle;
    return (leftAngle + rightAngle) / 2.0;
  }

  /// Ankle 각도 변화 계산: 무릎-발목 벡터의 각도 변화
  double? _calculateAnkleAngleChange(Pose prevPose, Pose currPose) {
    final leftAngle = _calculateVectorAngleChange(
      prevPose.landmarks[PoseLandmarkType.leftKnee],
      prevPose.landmarks[PoseLandmarkType.leftAnkle],
      currPose.landmarks[PoseLandmarkType.leftKnee],
      currPose.landmarks[PoseLandmarkType.leftAnkle],
    );
    final rightAngle = _calculateVectorAngleChange(
      prevPose.landmarks[PoseLandmarkType.rightKnee],
      prevPose.landmarks[PoseLandmarkType.rightAnkle],
      currPose.landmarks[PoseLandmarkType.rightKnee],
      currPose.landmarks[PoseLandmarkType.rightAnkle],
    );

    if (leftAngle == null && rightAngle == null) return null;
    if (leftAngle == null) return rightAngle;
    if (rightAngle == null) return leftAngle;
    return (leftAngle + rightAngle) / 2.0;
  }

  /// 세 점으로 이루어진 각도 변화 계산 헬퍼 함수 (각도 변화용)
  /// [prev1], [prev2], [prev3]: 이전 프레임의 세 점 (prev2가 꼭짓점)
  /// [curr1], [curr2], [curr3]: 현재 프레임의 세 점 (curr2가 꼭짓점)
  double? _calculateElbowAngleChangeHelper(
    PoseLandmark? prev1,
    PoseLandmark? prev2,
    PoseLandmark? prev3,
    PoseLandmark? curr1,
    PoseLandmark? curr2,
    PoseLandmark? curr3,
  ) {
    if (!_areLandmarksReliable(prev1, curr1) ||
        !_areLandmarksReliable(prev2, curr2) ||
        !_areLandmarksReliable(prev3, curr3)) {
      return null;
    }

    final prevAngle = _calculateAngle(
      _landmarkToMap(prev1),
      _landmarkToMap(prev2),
      _landmarkToMap(prev3),
    );
    final currAngle = _calculateAngle(
      _landmarkToMap(curr1),
      _landmarkToMap(curr2),
      _landmarkToMap(curr3),
    );

    return (currAngle - prevAngle).abs();
  }

  /// 두 점으로 이루어진 벡터의 각도 변화 계산 헬퍼 함수
  double? _calculateVectorAngleChange(
    PoseLandmark? prevFrom,
    PoseLandmark? prevTo,
    PoseLandmark? currFrom,
    PoseLandmark? currTo,
  ) {
    if (!_areLandmarksReliable(prevFrom, currFrom) ||
        !_areLandmarksReliable(prevTo, currTo)) {
      return null;
    }

    final prevVecX = prevTo!.x - prevFrom!.x;
    final prevVecY = prevTo.y - prevFrom.y;
    final currVecX = currTo!.x - currFrom!.x;
    final currVecY = currTo.y - currFrom.y;

    final prevAngle = math.atan2(prevVecY, prevVecX) * 180.0 / math.pi;
    final currAngle = math.atan2(currVecY, currVecX) * 180.0 / math.pi;

    return (currAngle - prevAngle).abs();
  }

  /// img.Image를 InputImage로 변환
  Future<InputImage> _createInputImageFromImage(img.Image image) async {
    // 임시 파일로 저장 후 InputImage 생성
    final tempDir = await getTemporaryDirectory();
    final tempFile = File(
      path.join(
        tempDir.path,
        'frame_${DateTime.now().millisecondsSinceEpoch}.jpg',
      ),
    );

    // JPEG로 저장
    final jpegBytes = img.encodeJpg(image, quality: 90);
    await tempFile.writeAsBytes(jpegBytes);

    // 파일 경로로 InputImage 생성
    return InputImage.fromFilePath(tempFile.path);
  }

  // ============================================
  // 운동 타입별 분석 함수들
  // ============================================

  /// 등척성 운동 분석 (중력 벡터 각도 분석)
  void _analyzeIsometricMotion(
    Pose currentPose,
    Map<String, double>? refGravity,
    List<double> gravityAngleDeviations,
  ) {
    if (refGravity == null) return;

    final currGravity = _extractGravityVector(currentPose);
    if (currGravity == null) return;

    // 각도 편차 계산
    final angleDeviation = MuscleMetricUtils.calculateGravityVectorAngle(
      refGravity,
      currGravity,
    );

    gravityAngleDeviations.add(angleDeviation);
  }

  /// 등속성 운동 분석 (각속도 분석)
  void _analyzeIsokineticMotion(
    Pose previousPose,
    Pose currentPose,
    int frameIndex,
    List<double> angularVelocities,
    List<int> frameTimestamps,
  ) {
    // 프레임 간 각도 변화 계산
    final angleChanges = _calculateAngleChanges(previousPose, currentPose);

    // 전체 관절의 평균 각도 변화 계산
    final validChanges = angleChanges.values
        .whereType<double>()
        .where((v) => v > 0)
        .toList();

    if (validChanges.isEmpty) return;

    final avgAngleChange =
        validChanges.reduce((a, b) => a + b) / validChanges.length;

    // 각속도 추정 (도/프레임 → rad/s 변환은 프레임레이트 필요)
    // 현재는 프레임 간 각도 변화를 속도로 사용
    angularVelocities.add(avgAngleChange);
    frameTimestamps.add(frameIndex);
  }

  /// 포즈에서 중력 벡터 추출
  Map<String, double>? _extractGravityVector(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];

    return MuscleMetricUtils.estimateGravityVectorFromPose(
      pose,
      leftShoulder,
      rightShoulder,
      leftHip,
      rightHip,
    );
  }

  /// 등척성 운동 결과 생성 (중력 벡터 기반 안정성 측정)
  Map<String, dynamic> _buildIsometricResult(
    Map<String, double>? refGravity,
    List<double> gravityAngleDeviations, {
    List<Pose>? poses,
    double timeDelta = 0.033,
  }) {
    // reference_gravity를 Float Array로 변환
    List<double>? referenceGravityArray;
    if (refGravity != null) {
      referenceGravityArray = [
        refGravity['x'] ?? 0.0,
        refGravity['y'] ?? 0.0,
        refGravity['z'] ?? 0.0,
      ];
    }

    if (gravityAngleDeviations.isEmpty) {
      return {
        'motion_type': 'isometric',
        'angle_deviation': 0.0,
        'jitter': 0.0,
        'raw_data': [],
        'reference_gravity': referenceGravityArray,
      };
    }

    // 평균 각도 편차
    final avgDeviation =
        gravityAngleDeviations.reduce((a, b) => a + b) /
        gravityAngleDeviations.length;

    // 떨림 수치 (표준편차)
    final jitter = MuscleMetricUtils.calculateJitter(gravityAngleDeviations);

    // 등척성 운동 메트릭 계산 (holdDurationSec, velocityVariance)
    double holdDurationSec = 0.0;
    double velocityVariance = 0.0;
    if (poses != null && poses.isNotEmpty) {
      final isometricMetrics = _calculateIsometricMetrics(
        poses: poses,
        timeDelta: timeDelta,
        refGravity: refGravity,
      );
      holdDurationSec = isometricMetrics['holdDurationSec'] ?? 0.0;
      velocityVariance = isometricMetrics['velocityVariance'] ?? 0.0;
    }

    return {
      'motion_type': 'isometric',
      'angle_deviation': (avgDeviation * 10).round() / 10.0,
      'jitter': (jitter * 10).round() / 10.0,
      'raw_data': gravityAngleDeviations,
      'reference_gravity': referenceGravityArray,
      'hold_duration_sec': holdDurationSec,
      'velocity_variance': velocityVariance,
    };
  }

  /// 등속성 운동 결과 생성
  Map<String, dynamic> _buildIsokineticResult(
    List<double> angularVelocities,
    List<int> frameTimestamps,
  ) {
    if (angularVelocities.isEmpty) {
      return {
        'motion_type': 'isokinetic',
        'avg_velocity': 0.0,
        'velocity_std_dev': 0.0,
        'velocity_variation_coefficient': 0.0,
        'raw_data': [],
      };
    }

    // 평균 속도
    final avgVelocity =
        angularVelocities.reduce((a, b) => a + b) / angularVelocities.length;

    // 속도 표준편차
    final stdDev = MuscleMetricUtils.calculateVelocityStandardDeviation(
      angularVelocities,
    );

    // 속도 변동률
    final variationCoeff =
        MuscleMetricUtils.calculateVelocityVariationCoefficient(
          angularVelocities,
        );

    return {
      'motion_type': 'isokinetic',
      'avg_velocity': (avgVelocity * 10).round() / 10.0,
      'velocity_std_dev': (stdDev * 10).round() / 10.0,
      'velocity_variation_coefficient': (variationCoeff * 10).round() / 10.0,
      'raw_data': angularVelocities,
      'timestamps': frameTimestamps,
    };
  }

  /// 관절별 visibility 추출 (MediaPipe likelihood 기반)
  /// [pose] 현재 포즈
  /// 반환: 관절명 -> 평균 visibility 점수 맵
  Map<String, double> _extractJointVisibilities(Pose pose) {
    final visibilities = <String, double>{};

    // Neck: 어깨와 코의 평균 visibility
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final nose = pose.landmarks[PoseLandmarkType.nose];
    if (leftShoulder != null && rightShoulder != null && nose != null) {
      visibilities['neck'] =
          (leftShoulder.likelihood +
              rightShoulder.likelihood +
              nose.likelihood) /
          3.0;
    }

    // Spine: 어깨와 골반의 평균 visibility
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];
    if (leftShoulder != null &&
        rightShoulder != null &&
        leftHip != null &&
        rightHip != null) {
      visibilities['spine'] =
          (leftShoulder.likelihood +
              rightShoulder.likelihood +
              leftHip.likelihood +
              rightHip.likelihood) /
          4.0;
    }

    // Shoulder: 좌우 어깨의 평균 visibility
    if (leftShoulder != null && rightShoulder != null) {
      visibilities['shoulder'] =
          (leftShoulder.likelihood + rightShoulder.likelihood) / 2.0;
    }

    // Elbow: 좌우 팔꿈치의 평균 visibility
    final leftElbow = pose.landmarks[PoseLandmarkType.leftElbow];
    final rightElbow = pose.landmarks[PoseLandmarkType.rightElbow];
    if (leftElbow != null && rightElbow != null) {
      visibilities['elbow'] =
          (leftElbow.likelihood + rightElbow.likelihood) / 2.0;
    }

    // Wrist: 좌우 손목의 평균 visibility
    final leftWrist = pose.landmarks[PoseLandmarkType.leftWrist];
    final rightWrist = pose.landmarks[PoseLandmarkType.rightWrist];
    if (leftWrist != null && rightWrist != null) {
      visibilities['wrist'] =
          (leftWrist.likelihood + rightWrist.likelihood) / 2.0;
    }

    // Hip: 좌우 골반의 평균 visibility
    if (leftHip != null && rightHip != null) {
      visibilities['hip'] = (leftHip.likelihood + rightHip.likelihood) / 2.0;
    }

    // Knee: 좌우 무릎의 평균 visibility
    final leftKnee = pose.landmarks[PoseLandmarkType.leftKnee];
    final rightKnee = pose.landmarks[PoseLandmarkType.rightKnee];
    if (leftKnee != null && rightKnee != null) {
      visibilities['knee'] = (leftKnee.likelihood + rightKnee.likelihood) / 2.0;
    }

    // Ankle: 좌우 발목의 평균 visibility
    final leftAnkle = pose.landmarks[PoseLandmarkType.leftAnkle];
    final rightAnkle = pose.landmarks[PoseLandmarkType.rightAnkle];
    if (leftAnkle != null && rightAnkle != null) {
      visibilities['ankle'] =
          (leftAnkle.likelihood + rightAnkle.likelihood) / 2.0;
    }

    return visibilities;
  }

  // ============================================
  // 순수 역학 기반 물리적 상태 감지
  // ============================================

  /// 물리적 상태 감지 (통합 함수) - MuscleMetricUtils로 대체됨
  /// [jointROMs] 관절별 ROM 맵
  /// [poses] 모든 포즈 리스트
  /// 반환: "STATE_HINGE", "STATE_PULL", "STATE_PUSH", 또는 null
  String? _detectPhysicsState(Map<String, double> jointROMs, List<Pose> poses) {
    // STATE_HINGE 감지
    if (_detectStateHinge(jointROMs)) {
      return 'STATE_HINGE';
    }

    // STATE_PULL 또는 STATE_PUSH 감지 (최소 2개 포즈 필요)
    if (poses.length >= 2) {
      for (int i = 1; i < poses.length; i++) {
        if (_detectStatePull(poses[i - 1], poses[i])) {
          return 'STATE_PULL';
        }
        if (_detectStatePush(poses[i - 1], poses[i])) {
          return 'STATE_PUSH';
        }
      }
    }

    return null;
  }

  /// STATE_HINGE 감지 (접고 버티기)
  /// 조건: Hip_ROM > 40° AND Elbow_ROM < 15°
  bool _detectStateHinge(Map<String, double> jointROMs) {
    final hipROM = jointROMs['hip'] ?? 0.0;
    final elbowROM = jointROMs['elbow'] ?? 0.0;
    return hipROM > 40.0 && elbowROM < 15.0;
  }

  /// STATE_PULL 감지 (당겨오기)
  /// 조건: Elbow_Flexion 발생 AND Shoulder_Extension 발생
  bool _detectStatePull(Pose previousPose, Pose currentPose) {
    // 팔꿈치 굽힘 감지
    final elbowFlexion = _calculateElbowAngleChange(previousPose, currentPose);
    if (elbowFlexion == null || elbowFlexion < 5.0) return false;

    // 어깨 신전 감지 (몸통 쪽으로 당김)
    final shoulderExtension = _calculateShoulderExtension(
      previousPose,
      currentPose,
    );
    if (shoulderExtension == null || shoulderExtension < 5.0) return false;

    return true;
  }

  /// STATE_PUSH 감지 (밀어내기)
  /// 조건: Elbow_Extension 발생 AND 팔이 몸통 중심에서 멀어지는 벡터
  bool _detectStatePush(Pose previousPose, Pose currentPose) {
    // 팔꿈치 펴기 감지
    final elbowExtension = _calculateElbowExtension(previousPose, currentPose);
    if (elbowExtension == null || elbowExtension < 5.0) return false;

    // 팔이 몸통 중심에서 멀어지는 벡터 감지
    final armAwayFromTorso = _calculateArmAwayFromTorso(
      previousPose,
      currentPose,
    );
    if (armAwayFromTorso == null || armAwayFromTorso < 5.0) return false;

    return true;
  }

  /// 어깨 신전 계산 (몸통 쪽으로 당김)
  double? _calculateShoulderExtension(Pose prevPose, Pose currPose) {
    final prevShoulderMid = _midPointIfReliable(
      prevPose.landmarks[PoseLandmarkType.leftShoulder],
      prevPose.landmarks[PoseLandmarkType.rightShoulder],
    );
    final currShoulderMid = _midPointIfReliable(
      currPose.landmarks[PoseLandmarkType.leftShoulder],
      currPose.landmarks[PoseLandmarkType.rightShoulder],
    );
    final prevElbowMid = _midPointIfReliable(
      prevPose.landmarks[PoseLandmarkType.leftElbow],
      prevPose.landmarks[PoseLandmarkType.rightElbow],
    );
    final currElbowMid = _midPointIfReliable(
      currPose.landmarks[PoseLandmarkType.leftElbow],
      currPose.landmarks[PoseLandmarkType.rightElbow],
    );

    if (prevShoulderMid == null ||
        currShoulderMid == null ||
        prevElbowMid == null ||
        currElbowMid == null) {
      return null;
    }

    // 어깨-팔꿈치 벡터와 어깨-골반 벡터 사이 각도 변화
    final prevHipMid = _midPointIfReliable(
      prevPose.landmarks[PoseLandmarkType.leftHip],
      prevPose.landmarks[PoseLandmarkType.rightHip],
    );
    final currHipMid = _midPointIfReliable(
      currPose.landmarks[PoseLandmarkType.leftHip],
      currPose.landmarks[PoseLandmarkType.rightHip],
    );

    if (prevHipMid == null || currHipMid == null) return null;

    // 이전 각도
    final prevArmVecX = prevElbowMid['x']! - prevShoulderMid['x']!;
    final prevArmVecY = prevElbowMid['y']! - prevShoulderMid['y']!;
    final prevTorsoVecX = prevHipMid['x']! - prevShoulderMid['x']!;
    final prevTorsoVecY = prevHipMid['y']! - prevShoulderMid['y']!;
    final prevAngle = _calculateVectorAngle2D(
      prevArmVecX,
      prevArmVecY,
      prevTorsoVecX,
      prevTorsoVecY,
    );

    // 현재 각도
    final currArmVecX = currElbowMid['x']! - currShoulderMid['x']!;
    final currArmVecY = currElbowMid['y']! - currShoulderMid['y']!;
    final currTorsoVecX = currHipMid['x']! - currShoulderMid['x']!;
    final currTorsoVecY = currHipMid['y']! - currShoulderMid['y']!;
    final currAngle = _calculateVectorAngle2D(
      currArmVecX,
      currArmVecY,
      currTorsoVecX,
      currTorsoVecY,
    );

    // 각도가 감소하면 몸통 쪽으로 당김 (신전)
    return prevAngle - currAngle;
  }

  /// 팔꿈치 펴기 계산
  double? _calculateElbowExtension(Pose prevPose, Pose currPose) {
    final prevAngle = _calculateShoulderAngle(prevPose);
    final currAngle = _calculateShoulderAngle(currPose);
    if (prevAngle == null || currAngle == null) return null;
    // 각도가 증가하면 팔꿈치 펴기
    return currAngle - prevAngle;
  }

  /// 팔이 몸통 중심에서 멀어지는 벡터 계산
  double? _calculateArmAwayFromTorso(Pose prevPose, Pose currPose) {
    final prevShoulderMid = _midPointIfReliable(
      prevPose.landmarks[PoseLandmarkType.leftShoulder],
      prevPose.landmarks[PoseLandmarkType.rightShoulder],
    );
    final currShoulderMid = _midPointIfReliable(
      currPose.landmarks[PoseLandmarkType.leftShoulder],
      currPose.landmarks[PoseLandmarkType.rightShoulder],
    );
    final prevElbowMid = _midPointIfReliable(
      prevPose.landmarks[PoseLandmarkType.leftElbow],
      prevPose.landmarks[PoseLandmarkType.rightElbow],
    );
    final currElbowMid = _midPointIfReliable(
      currPose.landmarks[PoseLandmarkType.leftElbow],
      currPose.landmarks[PoseLandmarkType.rightElbow],
    );

    if (prevShoulderMid == null ||
        currShoulderMid == null ||
        prevElbowMid == null ||
        currElbowMid == null) {
      return null;
    }

    // 어깨-팔꿈치 거리 변화
    final prevDist = math.sqrt(
      math.pow(prevElbowMid['x']! - prevShoulderMid['x']!, 2) +
          math.pow(prevElbowMid['y']! - prevShoulderMid['y']!, 2),
    );
    final currDist = math.sqrt(
      math.pow(currElbowMid['x']! - currShoulderMid['x']!, 2) +
          math.pow(currElbowMid['y']! - currShoulderMid['y']!, 2),
    );

    // 거리가 증가하면 멀어짐
    return currDist - prevDist;
  }

  /// 2D 벡터 사이 각도 계산 헬퍼
  double _calculateVectorAngle2D(
    double v1x,
    double v1y,
    double v2x,
    double v2y,
  ) {
    final dot = v1x * v2x + v1y * v2y;
    final mag1 = math.sqrt(v1x * v1x + v1y * v1y);
    final mag2 = math.sqrt(v2x * v2x + v2y * v2y);
    if (mag1 == 0.0 || mag2 == 0.0) return 0.0;
    final cosAngle = dot / (mag1 * mag2);
    final clampedCos = cosAngle.clamp(-1.0, 1.0);
    return math.acos(clampedCos) * 180.0 / math.pi;
  }

  // ============================================
  // 등 근육 역학 분석: 리듬 & 텐션
  // ============================================

  /// STATE_HINGE 감지 시: 광배근 강성 평가
  /// 팔이 중력 방향으로 떨어지지 않고 몸통에 딱 붙어있는가?
  double _evaluateLatsRigidity(Pose pose, Map<String, double>? refGravity) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final leftElbow = pose.landmarks[PoseLandmarkType.leftElbow];
    final rightElbow = pose.landmarks[PoseLandmarkType.rightElbow];
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];

    if (leftShoulder == null ||
        rightShoulder == null ||
        leftElbow == null ||
        rightElbow == null ||
        leftHip == null ||
        rightHip == null) {
      return 0.0;
    }

    final shoulderMid = _midPointIfReliable(leftShoulder, rightShoulder);
    final elbowMid = _midPointIfReliable(leftElbow, rightElbow);
    final hipMid = _midPointIfReliable(leftHip, rightHip);

    if (shoulderMid == null || elbowMid == null || hipMid == null) {
      return 0.0;
    }

    // 어깨-팔꿈치 벡터와 어깨-골반 벡터 사이 각도 계산
    final armVecX = elbowMid['x']! - shoulderMid['x']!;
    final armVecY = elbowMid['y']! - shoulderMid['y']!;
    final torsoVecX = hipMid['x']! - shoulderMid['x']!;
    final torsoVecY = hipMid['y']! - shoulderMid['y']!;

    final angle = _calculateVectorAngle2D(
      armVecX,
      armVecY,
      torsoVecX,
      torsoVecY,
    );

    // 각도가 작을수록 (팔이 몸통에 붙어있을수록) 높은 점수
    // 0~30도: 100점, 30~60도: 70점, 60~90도: 40점, 90도 이상: 0점
    if (angle <= 30.0) return 100.0;
    if (angle <= 60.0) return 70.0;
    if (angle <= 90.0) return 40.0;
    return 0.0;
  }

  /// STATE_HINGE 감지 시: 기립근 중립성 평가
  /// 척추가 중립(Neutral) 상태인가?
  double _evaluateErectorsNeutrality(Pose pose) {
    final shoulderMid = _midPointIfReliable(
      pose.landmarks[PoseLandmarkType.leftShoulder],
      pose.landmarks[PoseLandmarkType.rightShoulder],
    );
    final hipMid = _midPointIfReliable(
      pose.landmarks[PoseLandmarkType.leftHip],
      pose.landmarks[PoseLandmarkType.rightHip],
    );

    if (shoulderMid == null || hipMid == null) return 0.0;

    // 척추 벡터와 수직선 사이 각도 계산
    final vecX = hipMid['x']! - shoulderMid['x']!;
    final vecY = hipMid['y']! - shoulderMid['y']!;
    final angle = math.atan2(vecY, vecX) * 180.0 / math.pi;

    // 중립 상태는 약 90도 (수직)
    final deviation = (angle - 90.0).abs();

    // 편차가 작을수록 높은 점수
    // 0~5도: 100점, 5~15도: 80점, 15~30도: 50점, 30도 이상: 0점
    if (deviation <= 5.0) return 100.0;
    if (deviation <= 15.0) return 80.0;
    if (deviation <= 30.0) return 50.0;
    return 0.0;
  }

  /// STATE_PULL 감지 시: 광배근 리듬 평가
  /// 팔이 180°→0°로 내려오며 날개뼈가 하방 회전할 때 활성도 증가
  /// @Deprecated: Use MuscleMetricUtils.calculateMuscleScore instead
  double _evaluateLatsRhythm(List<Pose> poses, List<double> scapulaRotations) {
    if (poses.length < 2 || scapulaRotations.length < 2) return 0.0;

    // 팔 상승 각도 변화 추적
    final armElevations = <double>[];
    for (final pose in poses) {
      final elevation = _calculateArmElevation(pose);
      if (elevation != null) {
        armElevations.add(elevation);
      }
    }

    if (armElevations.isEmpty) return 0.0;

    // 팔이 내려오는 패턴 감지 (180°→0°)
    double score = 0.0;
    for (int i = 1; i < armElevations.length; i++) {
      final prevElevation = armElevations[i - 1];
      final currElevation = armElevations[i];
      final elevationChange = prevElevation - currElevation;

      // 팔이 내려오고 있고, 날개뼈가 하방 회전하면 점수 증가
      if (elevationChange > 0 && i - 1 < scapulaRotations.length) {
        final prevScapula = scapulaRotations[i - 1];
        final currScapula = scapulaRotations[i];
        if (currScapula < prevScapula) {
          // 하방 회전
          score += elevationChange * 2.0;
        }
      }
    }

    // 정규화 (0~100점)
    return (score / 10.0).clamp(0.0, 100.0);
  }

  /// 팔 상승 각도 계산
  double? _calculateArmElevation(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final leftElbow = pose.landmarks[PoseLandmarkType.leftElbow];
    final rightElbow = pose.landmarks[PoseLandmarkType.rightElbow];

    if (leftShoulder == null ||
        rightShoulder == null ||
        leftElbow == null ||
        rightElbow == null) {
      return null;
    }

    final shoulderMid = _midPointIfReliable(leftShoulder, rightShoulder);
    final elbowMid = _midPointIfReliable(leftElbow, rightElbow);

    if (shoulderMid == null || elbowMid == null) return null;

    // 어깨-팔꿈치 벡터와 수평선 사이 각도
    final vecX = elbowMid['x']! - shoulderMid['x']!;
    final vecY = elbowMid['y']! - shoulderMid['y']!;
    return math.atan2(-vecY, vecX) * 180.0 / math.pi + 90.0;
  }

  /// STATE_PULL 감지 시: 승모/능형근 평가
  /// Retraction_Depth (팔꿈치가 어깨보다 얼마나 뒤로 갔는가)
  double _evaluateTrapeziusRhomboids(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final leftElbow = pose.landmarks[PoseLandmarkType.leftElbow];
    final rightElbow = pose.landmarks[PoseLandmarkType.rightElbow];

    if (leftShoulder == null ||
        rightShoulder == null ||
        leftElbow == null ||
        rightElbow == null) {
      return 0.0;
    }

    // z축 기준으로 팔꿈치가 어깨보다 뒤로 갔는지 확인
    final leftRetraction = leftElbow.z - leftShoulder.z;
    final rightRetraction = rightElbow.z - rightShoulder.z;
    final avgRetraction = (leftRetraction + rightRetraction) / 2.0;

    // 후방 이동 거리에 따라 점수 할당
    // 0.05 이상: 100점, 0.03~0.05: 70점, 0.01~0.03: 40점, 0.01 미만: 0점
    if (avgRetraction >= 0.05) return 100.0;
    if (avgRetraction >= 0.03) return 70.0;
    if (avgRetraction >= 0.01) return 40.0;
    return 0.0;
  }

  /// 보상 작용 감지 (Throwing)
  /// 당기는 순간 몸통이 15° 이상 뒤로 젖혀지면
  bool _detectCompensationThrow(Pose previousPose, Pose currentPose) {
    final prevSpineAngle = _calculateSpineAngle(previousPose);
    final currSpineAngle = _calculateSpineAngle(currentPose);

    if (prevSpineAngle == null || currSpineAngle == null) return false;

    // 척추 각도 변화 (뒤로 젖혀지면 각도 증가)
    final angleChange = currSpineAngle - prevSpineAngle;
    return angleChange >= 15.0;
  }

  // ============================================
  // 대흉근 역학 분석: 벡터 & 앵커
  // ============================================

  /// 전인(Protraction) 감지
  /// Shoulder.z가 Sternum.z보다 앞으로 튀어나옴
  bool _detectShoulderProtraction(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final leftHip = pose.landmarks[PoseLandmarkType.leftHip];
    final rightHip = pose.landmarks[PoseLandmarkType.rightHip];

    if (leftShoulder == null ||
        rightShoulder == null ||
        leftHip == null ||
        rightHip == null) {
      return false;
    }

    // 흉골 위치 추정 (어깨와 골반 중점)
    final shoulderMid = _midPointIfReliable(leftShoulder, rightShoulder);
    final hipMid = _midPointIfReliable(leftHip, rightHip);

    if (shoulderMid == null || hipMid == null) return false;

    final sternumZ = (shoulderMid['z']! + hipMid['z']!) / 2.0;
    final shoulderZ = (leftShoulder.z + rightShoulder.z) / 2.0;

    // 어깨가 앞으로 튀어나옴
    return shoulderZ < sternumZ - 0.02; // 임계값: 0.02
  }

  /// 거상(Elevation) 감지
  /// Distance(Nose, Shoulder) 감소 (Shrug)
  bool _detectShoulderElevation(Pose pose) {
    final nose = pose.landmarks[PoseLandmarkType.nose];
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];

    if (nose == null || leftShoulder == null || rightShoulder == null) {
      return false;
    }

    // 어깨 중점 계산
    final shoulderMid = _midPointIfReliable(leftShoulder, rightShoulder);
    if (shoulderMid == null) return false;

    // 코와 어깨 중점 사이 거리 계산
    final dist = math.sqrt(
      math.pow(nose.x - shoulderMid['x']!, 2) +
          math.pow(nose.y - shoulderMid['y']!, 2),
    );

    // 거리가 너무 작으면 거상 (임계값: 0.12)
    return dist < 0.12;
  }

  /// 대흉근 상부 매핑
  /// 몸통 수직축 기준 30°~60° 위로 미는 벡터
  double _mapPectoralisUpper(Pose pose) {
    final angle = _calculateArmPushAngle(pose);
    if (angle == null) return 0.0;
    if (angle >= 30.0 && angle <= 60.0) return 100.0;
    return 0.0;
  }

  /// 대흉근 중부 매핑
  /// 몸통과 수직(80°~100°) 방향 벡터
  double _mapPectoralisSternal(Pose pose) {
    final angle = _calculateArmPushAngle(pose);
    if (angle == null) return 0.0;
    if (angle >= 80.0 && angle <= 100.0) return 100.0;
    return 0.0;
  }

  /// 대흉근 하부 매핑
  /// 아래쪽(-15°~-45°)으로 미는 벡터
  double _mapPectoralisCostal(Pose pose) {
    final angle = _calculateArmPushAngle(pose);
    if (angle == null) return 0.0;
    if (angle >= -45.0 && angle <= -15.0) return 100.0;
    return 0.0;
  }

  /// 팔 미는 각도 계산 (수직축 기준)
  double? _calculateArmPushAngle(Pose pose) {
    final leftShoulder = pose.landmarks[PoseLandmarkType.leftShoulder];
    final rightShoulder = pose.landmarks[PoseLandmarkType.rightShoulder];
    final leftElbow = pose.landmarks[PoseLandmarkType.leftElbow];
    final rightElbow = pose.landmarks[PoseLandmarkType.rightElbow];

    if (leftShoulder == null ||
        rightShoulder == null ||
        leftElbow == null ||
        rightElbow == null) {
      return null;
    }

    final shoulderMid = _midPointIfReliable(leftShoulder, rightShoulder);
    final elbowMid = _midPointIfReliable(leftElbow, rightElbow);

    if (shoulderMid == null || elbowMid == null) return null;

    // 어깨-팔꿈치 벡터와 수직축 사이 각도
    final vecX = elbowMid['x']! - shoulderMid['x']!;
    final vecY = elbowMid['y']! - shoulderMid['y']!;
    return math.atan2(-vecY, vecX) * 180.0 / math.pi;
  }

  /// 등장성 운동 결과 생성 (순수 역학 기반)
  /// [angleData] 각 관절별 각도 변화 데이터
  /// [validFrameCounts] 유효한 프레임 수
  /// [invalidFrameCounts] INVALID 프레임 수 (유령 움직임 방지)
  /// [totalFrameCounts] 전체 프레임 수
  /// [jointAngleValues] 관절별 각도 값 리스트 (ROM 계산용)
  /// [poses] 모든 포즈 리스트
  /// [refGravity] 초기 중력 벡터
  Map<String, dynamic> _buildIsotonicResult(
    Map<String, List<double>> angleData,
    Map<String, int> validFrameCounts,
    Map<String, int> invalidFrameCounts,
    Map<String, int> totalFrameCounts,
    Map<String, List<double>> jointAngleValues,
    List<Pose> poses,
    Map<String, double>? refGravity,
  ) {
    // ============================================
    // A. ROM 계산 (패턴 감지용)
    // ============================================
    final jointROMs = <String, double>{};
    for (final entry in jointAngleValues.entries) {
      final jointName = entry.key;
      final angles = entry.value;
      if (angles.isEmpty) {
        jointROMs[jointName] = 0.0;
        continue;
      }

      // ROM 계산: Max Angle - Min Angle (보존)
      final minAngle = angles.reduce((a, b) => a < b ? a : b);
      final maxAngle = angles.reduce((a, b) => a > b ? a : b);
      final rom = maxAngle - minAngle;
      jointROMs[jointName] = rom;
    }

    // ============================================
    // B. 물리적 상태 감지 (MuscleMetricUtils 사용)
    // ============================================
    // 어깨 신전 및 팔꿈치 신전 각도 계산
    double? shoulderExtension;
    double? elbowExtension;
    if (poses.length >= 2) {
      shoulderExtension = _calculateShoulderExtension(poses[0], poses.last);
      elbowExtension = _calculateElbowExtension(poses[0], poses.last);
    }

    final biomechPattern = MuscleMetricUtils.detectExerciseContext(
      jointROMs: jointROMs,
      shoulderExtension: shoulderExtension,
      elbowExtension: elbowExtension,
    );
    debugPrint('🔍 감지된 물리적 상태: $biomechPattern');

    // ============================================
    // C. 상태별 근육 분석
    // ============================================
    final detailedMuscleUsage = <String, double>{
      'pectoralis_upper': 0.0,
      'pectoralis_sternal': 0.0,
      'pectoralis_costal': 0.0,
      'lats': 0.0,
      'erector_spinae': 0.0,
      'erector_spinae_bad': 0.0,
      'trapezius': 0.0,
      'rhomboids': 0.0,
      'anterior_deltoid': 0.0,
      'triceps': 0.0,
    };

    // 각도 변화량 계산 (근육 점수 계산용)
    double? latsAngleChange;
    double? spineAngleChange;
    if (poses.length >= 2) {
      // 광배근 각도 변화량 (어깨-팔꿈치 벡터 변화)
      latsAngleChange = _calculateShoulderAngleChange(poses[0], poses.last);
      // 척추 각도 변화량
      spineAngleChange = _calculateSpineAngleChange(poses[0], poses.last);
    }

    if (biomechPattern == 'STATE_HINGE') {
      // 등 근육: 강성 평가 (새로운 로직 사용)
      if (poses.isNotEmpty) {
        // 광배근: 각도 변화가 적을수록 고득점
        final latsScore = MuscleMetricUtils.calculateMuscleScore(
          muscleKey: 'lats',
          context: biomechPattern,
          angleChange: latsAngleChange?.abs(),
        );
        detailedMuscleUsage['lats'] = latsScore;

        // 기립근: 척추 각도 변화가 적을수록 고득점
        final erectorsScore = MuscleMetricUtils.calculateMuscleScore(
          muscleKey: 'erector_spinae',
          context: biomechPattern,
          angleChange: latsAngleChange?.abs(),
          spineAngleChange: spineAngleChange?.abs(),
        );
        detailedMuscleUsage['erector_spinae'] = erectorsScore;
      }
    } else if (biomechPattern == 'STATE_PULL') {
      // 등 근육: 리듬 평가 (ROM 기반)
      if (poses.length >= 2) {
        // 어깨 ROM 계산 (jointAngleValues에서 가져오기)
        final shoulderAngles = jointAngleValues['shoulder'] ?? [];
        final maxShoulderROM = shoulderAngles.isNotEmpty
            ? shoulderAngles.reduce((a, b) => a > b ? a : b) -
                  shoulderAngles.reduce((a, b) => a < b ? a : b)
            : jointROMs['shoulder'] ?? 0.0;
        final currentShoulderROM = shoulderAngles.isNotEmpty
            ? shoulderAngles.last - shoulderAngles.first
            : jointROMs['shoulder'] ?? 0.0;

        // 광배근: ROM 기반 점수
        final latsScore = MuscleMetricUtils.calculateMuscleScore(
          muscleKey: 'lats',
          context: biomechPattern,
          maxROM: maxShoulderROM > 0 ? maxShoulderROM : 180.0,
          currentROM: currentShoulderROM.abs(),
        );
        detailedMuscleUsage['lats'] = latsScore;

        // 삼각근: ROM 기반 점수
        final deltoidScore = MuscleMetricUtils.calculateMuscleScore(
          muscleKey: 'lateral_deltoid',
          context: biomechPattern,
          maxROM: maxShoulderROM > 0 ? maxShoulderROM : 180.0,
          currentROM: currentShoulderROM.abs(),
        );
        detailedMuscleUsage['anterior_deltoid'] = deltoidScore * 0.7;

        // 승모근: 어깨 으쓱 페널티 적용 (기존 로직 유지)
        final trapRhombScore = _evaluateTrapeziusRhomboids(poses.last);
        detailedMuscleUsage['trapezius'] = trapRhombScore * 0.5;
        detailedMuscleUsage['rhomboids'] = trapRhombScore * 0.5;

        // 보상 작용 감지
        for (int i = 1; i < poses.length; i++) {
          if (_detectCompensationThrow(poses[i - 1], poses[i])) {
            // 등 점수 감소
            detailedMuscleUsage['lats'] = (detailedMuscleUsage['lats']! * 0.7)
                .clamp(0.0, 100.0);
            // 기립근_bad 점수 증가
            detailedMuscleUsage['erector_spinae_bad'] = 60.0;
            break;
    }
        }
      }
    } else if (biomechPattern == 'STATE_PUSH') {
      // 대흉근: 벡터 & 앵커 (ROM 기반 점수 추가)
      if (poses.isNotEmpty) {
        final pose = poses.last;

        // 팔꿈치 ROM 계산
        final elbowAngles = jointAngleValues['elbow'] ?? [];
        final maxElbowROM = elbowAngles.isNotEmpty
            ? elbowAngles.reduce((a, b) => a > b ? a : b) -
                  elbowAngles.reduce((a, b) => a < b ? a : b)
            : jointROMs['elbow'] ?? 0.0;
        final currentElbowROM = elbowAngles.isNotEmpty
            ? elbowAngles.last - elbowAngles.first
            : jointROMs['elbow'] ?? 0.0;

        // 앵커 안정성 검사
        bool anchorStable = true;
        double penalty = 1.0;

        if (_detectShoulderProtraction(pose)) {
          anchorStable = false;
          penalty *= 0.6; // -40% 페널티
          detailedMuscleUsage['anterior_deltoid'] = 30.0; // 소흉근/전면삼각근 개입
        }

        if (_detectShoulderElevation(pose)) {
          anchorStable = false;
          penalty *= 0.7; // -30% 페널티
          detailedMuscleUsage['trapezius'] = 40.0; // 승모근 개입
        }

        if (anchorStable) {
          // 벡터 기반 부위 매핑 (기존 로직 유지)
          final upperScore = _mapPectoralisUpper(pose);
          final sternalScore = _mapPectoralisSternal(pose);
          final costalScore = _mapPectoralisCostal(pose);

          // ROM 기반 점수와 기존 점수 결합
          final romBasedScore = MuscleMetricUtils.calculateMuscleScore(
            muscleKey: 'pectoralis_mid',
            context: biomechPattern,
            maxROM: maxElbowROM > 0 ? maxElbowROM : 180.0,
            currentROM: currentElbowROM.abs(),
          );

          detailedMuscleUsage['pectoralis_upper'] =
              (upperScore * 0.5 + romBasedScore * 0.5) * penalty;
          detailedMuscleUsage['pectoralis_sternal'] =
              (sternalScore * 0.5 + romBasedScore * 0.5) * penalty;
          detailedMuscleUsage['pectoralis_costal'] =
              (costalScore * 0.5 + romBasedScore * 0.5) * penalty;

          // 삼두근: ROM 기반 점수
          final tricepsScore = MuscleMetricUtils.calculateMuscleScore(
            muscleKey: 'triceps',
            context: biomechPattern,
            maxROM: maxElbowROM > 0 ? maxElbowROM : 180.0,
            currentROM: currentElbowROM.abs(),
          );
          detailedMuscleUsage['triceps'] = tricepsScore * penalty;
        }
      }
    }

    // ============================================
    // D. 속도 데이터 계산 (정밀 채점 알고리즘용)
    // ============================================
    final velocityData = <String, dynamic>{};
    if (poses.length >= 2) {
      final velocities = _calculateEccentricConcentricVelocities(
        poses: poses,
        timeDelta: 0.033, // 30fps 기준
      );
      velocityData['eccentric_velocities'] = velocities['eccentricVelocities'];
      velocityData['concentric_velocities'] =
          velocities['concentricVelocities'];
      velocityData['avg_eccentric_velocity'] =
          velocities['avgEccentricVelocity'];
      velocityData['avg_concentric_velocity'] =
          velocities['avgConcentricVelocity'];
    }

    // ============================================
    // E. 결과 반환
    // ============================================
    return {
      'motion_type': 'isotonic',
      'biomech_pattern': biomechPattern,
      'detailed_muscle_usage': MuscleMetricUtils.sanitizeOutputMap(
        detailedMuscleUsage,
      ),
      'rom_data': _calculateWeightedJointScores(
        jointROMs,
        biomechPattern,
      ), // 가중치 적용된 관절 점수
      'velocity_data': velocityData, // 신장성/단축성 속도 데이터
    };
  }

  /// 가중치 기반 관절 점수 계산
  /// [jointROMs] 원본 ROM 각도 맵
  /// [context] 운동 컨텍스트 ('STATE_HINGE', 'STATE_PULL', 'STATE_PUSH')
  /// 반환: 가중치가 적용된 관절 점수 맵
  Map<String, double> _calculateWeightedJointScores(
    Map<String, double> jointROMs,
    String? context,
  ) {
    final weightedScores = <String, double>{};
    for (final entry in jointROMs.entries) {
      final score = MuscleMetricUtils.calculateWeightedJointScore(
        jointKey: entry.key,
        rawROM: entry.value,
        context: context,
      );
      weightedScores[entry.key] = MuscleMetricUtils.sanitizeOutput(score);
    }
    return weightedScores;
    }

  // ============================================
  // 프레임 간 속도 계산 (정밀 채점 알고리즘용)
  // ============================================

  /// 프레임 간 속도 계산 및 신장성/단축성 구간 판별
  /// [previousPose] 이전 프레임 포즈
  /// [currentPose] 현재 프레임 포즈
  /// [timeDelta] 프레임 간 시간 간격 (초, 기본값 0.033 = 30fps)
  /// [jointName] 관절명 (선택적, null이면 전체 관절 평균)
  ///
  /// 반환: {
  ///   'velocity': double (도/초),
  ///   'isEccentric': bool (신장성 여부),
  ///   'isConcentric': bool (단축성 여부),
  ///   'angleChange': double (각도 변화량, 도)
  /// }
  Map<String, dynamic> _calculateVelocityFromFrames({
    required Pose? previousPose,
    required Pose currentPose,
    double timeDelta = 0.033, // 30fps 기준
    String? jointName,
  }) {
    if (previousPose == null) {
      return {
        'velocity': 0.0,
        'isEccentric': false,
        'isConcentric': false,
        'angleChange': 0.0,
      };
    }

    // 관절별 각도 변화 계산
    final angleChanges = _calculateAngleChanges(previousPose, currentPose);

    double angleChange = 0.0;
    if (jointName != null) {
      // 특정 관절의 각도 변화
      angleChange = angleChanges[jointName] ?? 0.0;
    } else {
      // 전체 관절의 평균 각도 변화
      final validChanges = angleChanges.values
          .whereType<double>()
          .where((v) => v.abs() > 0.1)
          .toList();
      if (validChanges.isNotEmpty) {
        angleChange =
            validChanges.reduce((a, b) => a + b) / validChanges.length;
      }
    }

    // 속도 계산 (도/초)
    final velocity = timeDelta > 0.001 ? angleChange.abs() / timeDelta : 0.0;

    // 신장성/단축성 판별
    // 각도가 감소하면 신장성 (Eccentric), 증가하면 단축성 (Concentric)
    final isEccentric = angleChange < 0.0;
    final isConcentric = angleChange > 0.0;

    return {
      'velocity': velocity,
      'isEccentric': isEccentric,
      'isConcentric': isConcentric,
      'angleChange': angleChange,
    };
  }

  /// 등장성 운동: 관절별 신장성/단축성 속도 계산
  /// [poses] 모든 포즈 리스트
  /// [timeDelta] 프레임 간 시간 간격 (초)
  ///
  /// 반환: {
  ///   'eccentricVelocities': `Map<String, double>` (관절별 신장성 속도),
  ///   'concentricVelocities': `Map<String, double>` (관절별 단축성 속도),
  ///   'avgEccentricVelocity': double (평균 신장성 속도),
  ///   'avgConcentricVelocity': double (평균 단축성 속도)
  /// }
  Map<String, dynamic> _calculateEccentricConcentricVelocities({
    required List<Pose> poses,
    double timeDelta = 0.033,
  }) {
    final eccentricVelocities = <String, List<double>>{
      'hip': [],
      'knee': [],
      'ankle': [],
      'shoulder': [],
      'elbow': [],
      'wrist': [],
    };
    final concentricVelocities = <String, List<double>>{
      'hip': [],
      'knee': [],
      'ankle': [],
      'shoulder': [],
      'elbow': [],
      'wrist': [],
    };

    // 모든 프레임 쌍에 대해 속도 계산
    for (int i = 1; i < poses.length; i++) {
      final prevPose = poses[i - 1];
      final currPose = poses[i];

      for (final jointName in eccentricVelocities.keys) {
        final velocityData = _calculateVelocityFromFrames(
          previousPose: prevPose,
          currentPose: currPose,
          timeDelta: timeDelta,
          jointName: jointName,
        );

        final velocity = velocityData['velocity'] as double;
        final isEccentric = velocityData['isEccentric'] as bool;
        final isConcentric = velocityData['isConcentric'] as bool;

        if (isEccentric && velocity > 0.0) {
          eccentricVelocities[jointName]!.add(velocity);
        } else if (isConcentric && velocity > 0.0) {
          concentricVelocities[jointName]!.add(velocity);
        }
      }
    }

    // 평균 속도 계산
    final avgEccentricVelocities = <String, double>{};
    final avgConcentricVelocities = <String, double>{};

    for (final entry in eccentricVelocities.entries) {
      final velocities = entry.value;
      if (velocities.isNotEmpty) {
        avgEccentricVelocities[entry.key] =
            velocities.reduce((a, b) => a + b) / velocities.length;
      } else {
        avgEccentricVelocities[entry.key] = 0.0;
      }
    }

    for (final entry in concentricVelocities.entries) {
      final velocities = entry.value;
      if (velocities.isNotEmpty) {
        avgConcentricVelocities[entry.key] =
            velocities.reduce((a, b) => a + b) / velocities.length;
      } else {
        avgConcentricVelocities[entry.key] = 0.0;
      }
    }

    // 전체 평균
    final allEccentric = avgEccentricVelocities.values
        .where((v) => v > 0.0)
        .toList();
    final allConcentric = avgConcentricVelocities.values
        .where((v) => v > 0.0)
        .toList();

    final avgEccentric = allEccentric.isNotEmpty
        ? allEccentric.reduce((a, b) => a + b) / allEccentric.length
        : 0.0;
    final avgConcentric = allConcentric.isNotEmpty
        ? allConcentric.reduce((a, b) => a + b) / allConcentric.length
        : 0.0;

    return {
      'eccentricVelocities': avgEccentricVelocities,
      'concentricVelocities': avgConcentricVelocities,
      'avgEccentricVelocity': avgEccentric,
      'avgConcentricVelocity': avgConcentric,
    };
  }

  /// 등척성 운동: 자세 유지 시간 및 미세 떨림 계산
  /// [poses] 모든 포즈 리스트
  /// [timeDelta] 프레임 간 시간 간격 (초)
  /// [refGravity] 초기 중력 벡터
  ///
  /// 반환: {
  ///   'holdDurationSec': double (자세 유지 시간, 초),
  ///   'velocityVariance': double (속도 분산, 미세 떨림 측정)
  /// }
  Map<String, double> _calculateIsometricMetrics({
    required List<Pose> poses,
    required double timeDelta,
    Map<String, double>? refGravity,
  }) {
    if (poses.isEmpty) {
      return {'holdDurationSec': 0.0, 'velocityVariance': 0.0};
    }

    // 자세 유지 시간: 전체 프레임 수 × 시간 간격
    final holdDurationSec = poses.length * timeDelta;

    // 미세 떨림 측정: 각속도의 표준편차 계산
    final angularVelocities = <double>[];
    if (refGravity != null) {
      for (int i = 1; i < poses.length; i++) {
        final prevPose = poses[i - 1];
        final currPose = poses[i];

        // 중력 벡터 각도 변화 계산
        final prevGravity = _extractGravityVector(prevPose);
        final currGravity = _extractGravityVector(currPose);

        if (prevGravity != null && currGravity != null) {
          final angleDeviation = MuscleMetricUtils.calculateGravityVectorAngle(
            refGravity,
            currGravity,
          );
          // 각속도 계산 (도/초)
          final angularVelocity = angleDeviation / timeDelta;
          angularVelocities.add(angularVelocity);
        }
      }
    }

    // 속도 분산 계산
    double velocityVariance = 0.0;
    if (angularVelocities.length > 1) {
      final mean =
          angularVelocities.reduce((a, b) => a + b) / angularVelocities.length;
      final variance =
          angularVelocities
              .map((v) => (v - mean) * (v - mean))
              .reduce((a, b) => a + b) /
          angularVelocities.length;
      velocityVariance = variance;
    }

    return {
      'holdDurationSec': holdDurationSec,
      'velocityVariance': velocityVariance,
    };
  }
}
