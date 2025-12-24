import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:image/image.dart' as img;
import 'package:video_player/video_player.dart';
import 'package:video_thumbnail/video_thumbnail.dart' as vt;
import 'package:path_provider/path_provider.dart';

/// MediaPipe Pose Detection Service
/// 비디오 파일에서 프레임별 Pose Landmark를 추출하는 서비스
class PoseDetectionService {
  static PoseDetectionService? _instance;
  static PoseDetectionService get instance {
    _instance ??= PoseDetectionService._();
    return _instance!;
  }

  PoseDetectionService._();

  /// 관절 가시성 임계값 (60% 미만이면 보이지 않는 것으로 간주)
  static const double _visibilityThreshold = 0.6;

  /// 비디오 파일에서 Pose Landmark 추출
  ///
  /// [videoFile] 분석할 비디오 파일
  /// [sampleRate] 프레임 샘플링 비율 (예: 5 = 1초에 5프레임)
  /// [onProgress] 진행률 콜백 (0.0 ~ 1.0)
  ///
  /// 반환: 추출된 Pose 리스트와 타임스탬프 정보
  Future<List<Pose>> extractPosesFromVideo({
    required File videoFile,
    int sampleRate = 5, // 기본값: 1초에 5프레임
    Function(double)? onProgress,
  }) async {
    try {
      debugPrint('🎬 [PoseDetectionService] 비디오 Pose 추출 시작');
      debugPrint('   - 파일: ${videoFile.path}');
      debugPrint('   - 샘플링 비율: $sampleRate fps');

      // Pose Detector 초기화
      final poseDetector = PoseDetector(
        options: PoseDetectorOptions(
          mode: PoseDetectionMode.single,
          model: PoseDetectionModel.accurate,
        ),
      );

      // 비디오 플레이어로 프레임 추출
      final videoController = VideoPlayerController.file(videoFile);
      await videoController.initialize();

      final duration = videoController.value.duration;
      final fps = videoController.value.size.height > 0
          ? 30.0 // 기본값 (실제 FPS는 비디오 메타데이터에서 가져와야 함)
          : 30.0;
      final totalFrames = (duration.inMilliseconds / 1000.0 * fps).round();
      final frameInterval = (fps / sampleRate).round(); // 샘플링 간격

      debugPrint('   - 비디오 길이: ${duration.inSeconds}초');
      debugPrint('   - 총 프레임 수: $totalFrames');
      debugPrint('   - 샘플링 간격: $frameInterval 프레임');

      final allPoses = <Pose>[];
      int processedFrames = 0;
      int extractedPoses = 0;

      // 프레임별로 처리
      for (
        int frameIndex = 0;
        frameIndex < totalFrames;
        frameIndex += frameInterval
      ) {
        try {
          // 비디오를 특정 시간으로 이동
          final targetTime = Duration(
            milliseconds: (frameIndex / fps * 1000).round(),
          );
          await videoController.seekTo(targetTime);
          await Future.delayed(const Duration(milliseconds: 100)); // 프레임 로딩 대기

          // 현재 프레임을 이미지로 변환
          final videoImage = videoController.value;
          if (!videoImage.isInitialized || videoImage.size.height == 0) {
            continue;
          }

          // VideoPlayer에서 직접 이미지를 추출할 수 없으므로
          // video_thumbnail 패키지를 사용하여 특정 시간의 프레임 추출
          final tempDir = await getTemporaryDirectory();
          final thumbnailPath = await vt.VideoThumbnail.thumbnailFile(
            video: videoFile.path,
            thumbnailPath: tempDir.path,
            timeMs: targetTime.inMilliseconds,
            imageFormat: vt.ImageFormat.PNG,
            quality: 75,
          );

          if (thumbnailPath == null) {
            debugPrint('⚠️ [PoseDetectionService] 프레임 $frameIndex: 썸네일 생성 실패');
            processedFrames++;
            if (onProgress != null) {
              onProgress(processedFrames / (totalFrames / frameInterval));
            }
            continue;
          }

          // 이미지 파일 읽기
          final imageBytes = await File(thumbnailPath).readAsBytes();
          final image = img.decodeImage(imageBytes);

          if (image == null) {
            debugPrint('⚠️ [PoseDetectionService] 프레임 $frameIndex: 이미지 디코딩 실패');
            processedFrames++;
            if (onProgress != null) {
              onProgress(processedFrames / (totalFrames / frameInterval));
            }
            continue;
          }

          // InputImage 생성 (파일 경로 사용)
          final inputImage = InputImage.fromFilePath(thumbnailPath);

          // Pose 감지
          final poses = await poseDetector.processImage(inputImage);

          if (poses.isNotEmpty) {
            final pose = poses.first;

            // 가시성 필터링: likelihood < 0.6인 관절이 너무 많으면 프레임 제외
            final reliableLandmarks = pose.landmarks.values
                .where(
                  (landmark) => landmark.likelihood >= _visibilityThreshold,
                )
                .length;

            // 최소 10개 이상의 관절이 보여야 유효한 프레임으로 간주
            if (reliableLandmarks >= 10) {
              allPoses.add(pose);
              extractedPoses++;
              debugPrint(
                '✅ [PoseDetectionService] 프레임 $frameIndex: Pose 추출 성공 (신뢰 관절: $reliableLandmarks개)',
              );
            } else {
              debugPrint(
                '⚠️ [PoseDetectionService] 프레임 $frameIndex: 신뢰 관절 부족 ($reliableLandmarks개 < 10개)',
              );
            }
          }

          processedFrames++;
          if (onProgress != null) {
            onProgress(processedFrames / (totalFrames / frameInterval));
          }

          // 임시 파일 삭제
          try {
            await File(thumbnailPath).delete();
          } catch (e) {
            // 삭제 실패는 무시
          }
        } catch (e) {
          debugPrint('⚠️ [PoseDetectionService] 프레임 $frameIndex 처리 실패: $e');
          processedFrames++;
          if (onProgress != null) {
            onProgress(processedFrames / (totalFrames / frameInterval));
          }
        }
      }

      // 리소스 정리
      await videoController.dispose();
      await poseDetector.close();

      debugPrint('✅ [PoseDetectionService] Pose 추출 완료');
      debugPrint('   - 처리된 프레임: $processedFrames개');
      debugPrint('   - 추출된 Pose: $extractedPoses개');

      if (allPoses.isEmpty) {
        throw Exception('비디오에서 Pose를 추출할 수 없습니다. 비디오에 사람이 보이는지 확인해주세요.');
      }

      return allPoses;
    } catch (e, stackTrace) {
      debugPrint('❌ [PoseDetectionService] Pose 추출 실패: $e');
      debugPrint('❌ 스택 트레이스: $stackTrace');
      rethrow;
    }
  }

  /// 더 효율적인 방법: video_thumbnail을 사용하여 프레임 추출
  /// 이 방법은 비디오 전체를 재생하지 않고 특정 시간의 프레임만 추출
  Future<List<Pose>> extractPosesFromVideoOptimized({
    required File videoFile,
    int sampleRate = 5, // 기본값: 1초에 5프레임
    Function(double)? onProgress,
  }) async {
    try {
      debugPrint('🎬 [PoseDetectionService] 비디오 Pose 추출 시작 (최적화 버전)');
      debugPrint('   - 파일: ${videoFile.path}');
      debugPrint('   - 샘플링 비율: $sampleRate fps');

      // Pose Detector 초기화
      final poseDetector = PoseDetector(
        options: PoseDetectorOptions(
          mode: PoseDetectionMode.single,
          model: PoseDetectionModel.accurate,
        ),
      );

      // 비디오 정보 가져오기
      final videoController = VideoPlayerController.file(videoFile);
      await videoController.initialize();

      final duration = videoController.value.duration;
      final totalSeconds = duration.inSeconds;
      await videoController.dispose();

      debugPrint('   - 비디오 길이: $totalSeconds초');

      final allPoses = <Pose>[];
      final tempDir = await getTemporaryDirectory();
      int processedFrames = 0;
      int extractedPoses = 0;

      // 1초마다 샘플링 (sampleRate에 따라 조정)
      final intervalSeconds = 1.0 / sampleRate;
      final totalSamples = (totalSeconds / intervalSeconds).ceil();

      for (int sampleIndex = 0; sampleIndex < totalSamples; sampleIndex++) {
        try {
          final targetTimeMs = (sampleIndex * intervalSeconds * 1000).round();

          // 특정 시간의 프레임 추출
          final thumbnailPath = await vt.VideoThumbnail.thumbnailFile(
            video: videoFile.path,
            thumbnailPath: tempDir.path,
            timeMs: targetTimeMs,
            imageFormat: vt.ImageFormat.PNG,
            quality: 75,
          );

          if (thumbnailPath == null) {
            debugPrint('⚠️ [PoseDetectionService] 샘플 $sampleIndex: 썸네일 생성 실패');
            processedFrames++;
            if (onProgress != null) {
              onProgress(processedFrames / totalSamples);
            }
            continue;
          }

          // 이미지 파일 읽기
          final imageBytes = await File(thumbnailPath).readAsBytes();
          final image = img.decodeImage(imageBytes);

          if (image == null || image.width == 0 || image.height == 0) {
            debugPrint('⚠️ [PoseDetectionService] 샘플 $sampleIndex: 이미지 디코딩 실패');
            processedFrames++;
            if (onProgress != null) {
              onProgress(processedFrames / totalSamples);
            }
            continue;
          }

          // InputImage 생성 (RGB 형식)
          final inputImage = InputImage.fromFilePath(thumbnailPath);

          // Pose 감지
          final poses = await poseDetector.processImage(inputImage);

          if (poses.isNotEmpty) {
            final pose = poses.first;

            // 가시성 필터링: likelihood < 0.6인 관절이 너무 많으면 프레임 제외
            final reliableLandmarks = pose.landmarks.values
                .where(
                  (landmark) => landmark.likelihood >= _visibilityThreshold,
                )
                .length;

            // 최소 10개 이상의 관절이 보여야 유효한 프레임으로 간주
            if (reliableLandmarks >= 10) {
              allPoses.add(pose);
              extractedPoses++;
              debugPrint(
                '✅ [PoseDetectionService] 샘플 $sampleIndex (${(targetTimeMs / 1000).toStringAsFixed(1)}초): Pose 추출 성공 (신뢰 관절: $reliableLandmarks개)',
              );
            } else {
              debugPrint(
                '⚠️ [PoseDetectionService] 샘플 $sampleIndex: 신뢰 관절 부족 ($reliableLandmarks개 < 10개)',
              );
            }
          }

          processedFrames++;
          if (onProgress != null) {
            onProgress(processedFrames / totalSamples);
          }

          // 임시 파일 삭제
          try {
            await File(thumbnailPath).delete();
          } catch (e) {
            // 삭제 실패는 무시
          }
        } catch (e) {
          debugPrint('⚠️ [PoseDetectionService] 샘플 $sampleIndex 처리 실패: $e');
          processedFrames++;
          if (onProgress != null) {
            onProgress(processedFrames / totalSamples);
          }
        }
      }

      // 리소스 정리
      await poseDetector.close();

      debugPrint('✅ [PoseDetectionService] Pose 추출 완료');
      debugPrint('   - 처리된 샘플: $processedFrames개');
      debugPrint('   - 추출된 Pose: $extractedPoses개');

      if (allPoses.isEmpty) {
        throw Exception('비디오에서 Pose를 추출할 수 없습니다. 비디오에 사람이 보이는지 확인해주세요.');
      }

      return allPoses;
    } catch (e, stackTrace) {
      debugPrint('❌ [PoseDetectionService] Pose 추출 실패: $e');
      debugPrint('❌ 스택 트레이스: $stackTrace');
      rethrow;
    }
  }
}
