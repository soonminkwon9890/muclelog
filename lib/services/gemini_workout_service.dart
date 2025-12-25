import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import '../config/env.dart';
import '../models/motion_type.dart';
import '../models/body_part.dart';

/// Next.js Gemini Workout Analysis Service
/// Flutter에서 Motion Data를 Next.js 백엔드로 전송하여 Gemini 분석 수행
class GeminiWorkoutService {
  static GeminiWorkoutService? _instance;
  static GeminiWorkoutService get instance {
    _instance ??= GeminiWorkoutService._();
    return _instance!;
  }

  GeminiWorkoutService._();

  /// Next.js API Base URL
  /// 환경 변수에서 가져오거나 기본값 사용
  String get _apiBaseUrl {
    return Env.nextJsApiUrl;
  }

  /// 관절 가시성 임계값 (60% 미만이면 보이지 않는 것으로 간주)
  static const double _visibilityThreshold = 0.6;

  /// Landmark 타입을 관절명으로 변환 (중요 관절만)
  String? _landmarkToJointName(PoseLandmarkType type) {
    switch (type) {
      case PoseLandmarkType.leftShoulder:
      case PoseLandmarkType.rightShoulder:
        return 'shoulder';
      case PoseLandmarkType.leftElbow:
      case PoseLandmarkType.rightElbow:
        return 'elbow';
      case PoseLandmarkType.leftWrist:
      case PoseLandmarkType.rightWrist:
        return 'wrist';
      case PoseLandmarkType.leftHip:
      case PoseLandmarkType.rightHip:
        return 'hip';
      case PoseLandmarkType.leftKnee:
      case PoseLandmarkType.rightKnee:
        return 'knee';
      case PoseLandmarkType.leftAnkle:
      case PoseLandmarkType.rightAnkle:
        return 'ankle';
      case PoseLandmarkType.nose:
        return 'neck';
      default:
        return null; // 중요 관절이 아닌 경우
    }
  }

  /// Pose 리스트를 Motion Data JSON 형식으로 변환
  /// 🔧 AI Hallucination 방지: likelihood < 0.6인 관절은 제외
  /// [poses] 분석할 포즈 리스트
  /// [timestamps] 각 포즈에 해당하는 timestamp 리스트 (밀리초). null이면 인덱스 기반으로 계산
  Map<String, dynamic> _convertPosesToMotionData(
    List<Pose> poses, {
    List<int>? timestamps,
  }) {
    final frames = <Map<String, dynamic>>[];
    final allVisibleJoints = <String>{};

    for (int i = 0; i < poses.length; i++) {
      final pose = poses[i];
      final landmarks = <Map<String, dynamic>>[];
      final frameVisibleJoints = <String>{};

      // MediaPipe Pose Landmark 타입을 순회하며 변환
      for (final landmarkType in PoseLandmarkType.values) {
        final landmark = pose.landmarks[landmarkType];

        // 🔧 가시성 필터링: likelihood < 0.6인 관절은 제외
        if (landmark != null && landmark.likelihood >= _visibilityThreshold) {
          landmarks.add({
            'type': _getLandmarkTypeName(landmarkType),
            'x': landmark.x,
            'y': landmark.y,
            'z': landmark.z,
            'likelihood': landmark.likelihood,
          });

          // 관절명 추출 (중요 관절만)
          final jointName = _landmarkToJointName(landmarkType);
          if (jointName != null) {
            frameVisibleJoints.add(jointName);
            allVisibleJoints.add(jointName);
          }
        } else if (landmark != null &&
            landmark.likelihood < _visibilityThreshold) {
          // 🔍 디버그: 필터링된 관절 로그
          final jointName = _landmarkToJointName(landmarkType);
          if (jointName != null) {
            debugPrint(
              '⚠️ [GeminiWorkoutService] 관절 필터링: $jointName (likelihood: ${landmark.likelihood.toStringAsFixed(2)} < $_visibilityThreshold)',
            );
          }
        }
      }

      // timestamp 계산: timestamps가 제공되면 사용, 없으면 인덱스 기반으로 계산
      final timestamp = timestamps != null && i < timestamps.length
          ? timestamps[i] /
                1000.0 // 밀리초를 초로 변환
          : i * 0.033; // 30fps 기준 (대략적, fallback)

      frames.add({'timestamp': timestamp, 'landmarks': landmarks});
    }

    // 🔍 디버그: 보이는 관절 목록 출력
    debugPrint(
      '✅ [GeminiWorkoutService] 보이는 관절 목록: ${allVisibleJoints.toList().join(", ")}',
    );
    debugPrint(
      '📊 [GeminiWorkoutService] 총 ${allVisibleJoints.length}개 관절이 감지됨 (likelihood >= $_visibilityThreshold)',
    );

    return {
      'frames': frames,
      'visible_joints': allVisibleJoints.toList(), // 🔧 명시적 보이는 관절 목록
    };
  }

  /// PoseLandmarkType을 문자열로 변환
  String _getLandmarkTypeName(PoseLandmarkType type) {
    switch (type) {
      case PoseLandmarkType.nose:
        return 'nose';
      case PoseLandmarkType.leftEyeInner:
        return 'leftEyeInner';
      case PoseLandmarkType.leftEye:
        return 'leftEye';
      case PoseLandmarkType.leftEyeOuter:
        return 'leftEyeOuter';
      case PoseLandmarkType.rightEyeInner:
        return 'rightEyeInner';
      case PoseLandmarkType.rightEye:
        return 'rightEye';
      case PoseLandmarkType.rightEyeOuter:
        return 'rightEyeOuter';
      case PoseLandmarkType.leftEar:
        return 'leftEar';
      case PoseLandmarkType.rightEar:
        return 'rightEar';
      case PoseLandmarkType.leftMouth:
        return 'leftMouth';
      case PoseLandmarkType.rightMouth:
        return 'rightMouth';
      case PoseLandmarkType.leftShoulder:
        return 'leftShoulder';
      case PoseLandmarkType.rightShoulder:
        return 'rightShoulder';
      case PoseLandmarkType.leftElbow:
        return 'leftElbow';
      case PoseLandmarkType.rightElbow:
        return 'rightElbow';
      case PoseLandmarkType.leftWrist:
        return 'leftWrist';
      case PoseLandmarkType.rightWrist:
        return 'rightWrist';
      case PoseLandmarkType.leftPinky:
        return 'leftPinky';
      case PoseLandmarkType.rightPinky:
        return 'rightPinky';
      case PoseLandmarkType.leftIndex:
        return 'leftIndex';
      case PoseLandmarkType.rightIndex:
        return 'rightIndex';
      case PoseLandmarkType.leftThumb:
        return 'leftThumb';
      case PoseLandmarkType.rightThumb:
        return 'rightThumb';
      case PoseLandmarkType.leftHip:
        return 'leftHip';
      case PoseLandmarkType.rightHip:
        return 'rightHip';
      case PoseLandmarkType.leftKnee:
        return 'leftKnee';
      case PoseLandmarkType.rightKnee:
        return 'rightKnee';
      case PoseLandmarkType.leftAnkle:
        return 'leftAnkle';
      case PoseLandmarkType.rightAnkle:
        return 'rightAnkle';
      case PoseLandmarkType.leftHeel:
        return 'leftHeel';
      case PoseLandmarkType.rightHeel:
        return 'rightHeel';
      case PoseLandmarkType.leftFootIndex:
        return 'leftFootIndex';
      case PoseLandmarkType.rightFootIndex:
        return 'rightFootIndex';
    }
  }

  /// Next.js API를 호출하여 운동 분석 수행
  ///
  /// [poses] 분석할 포즈 리스트
  /// [timestamps] 각 포즈에 해당하는 timestamp 리스트 (밀리초). null이면 인덱스 기반으로 계산
  /// [bodyPart] 운동 부위
  /// [motionType] 운동 방식
  /// [exerciseName] 운동 이름
  /// [userId] 사용자 ID
  /// [logId] 분석 로그 ID
  ///
  /// 반환: 분석 결과 (AnalysisResult 형식)
  Future<Map<String, dynamic>> analyzeWorkoutWithGemini({
    required List<Pose> poses,
    List<int>? timestamps,
    required BodyPart bodyPart,
    required MotionType motionType,
    required String exerciseName,
    required String userId,
    required String logId,
  }) async {
    try {
      debugPrint('🚀 [GeminiWorkoutService] Next.js API 호출 시작');

      // Motion Data 변환 (timestamp 포함)
      final motionData = _convertPosesToMotionData(
        poses,
        timestamps: timestamps,
      );
      debugPrint(
        '📊 [GeminiWorkoutService] Motion Data 변환 완료: ${poses.length}개 프레임',
      );

      // Context 생성
      final context = {
        'bodyPart': _convertBodyPart(bodyPart),
        'contraction': _convertMotionType(motionType),
        'exerciseName': exerciseName,
      };

      // Request Body 생성
      final requestBody = {
        'context': context,
        'motionData': motionData,
        'userId': userId,
        'logId': logId,
      };

      // HTTP POST 요청
      final url = Uri.parse('$_apiBaseUrl/api/analyze-workout');
      debugPrint('🌐 [GeminiWorkoutService] API URL: $url');

      final response = await http
          .post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(requestBody),
          )
          .timeout(
            const Duration(seconds: 60), // Gemini API 응답 대기 시간
          );

      debugPrint('📥 [GeminiWorkoutService] 응답 상태 코드: ${response.statusCode}');

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body) as Map<String, dynamic>;

        if (responseData['success'] == true && responseData['data'] != null) {
          debugPrint('✅ [GeminiWorkoutService] 분석 완료');
          return responseData['data'] as Map<String, dynamic>;
        } else {
          final error = responseData['error']?.toString() ?? 'Unknown error';
          throw Exception('Analysis failed: $error');
        }
      } else {
        final errorBody = jsonDecode(response.body) as Map<String, dynamic>?;
        final error =
            errorBody?['error']?.toString() ??
            'HTTP ${response.statusCode}: ${response.reasonPhrase}';
        throw Exception('API request failed: $error');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ [GeminiWorkoutService] 분석 실패: $e');
      debugPrint('❌ 스택 트레이스: $stackTrace');
      rethrow;
    }
  }

  /// BodyPart를 Next.js 형식으로 변환
  String _convertBodyPart(BodyPart bodyPart) {
    switch (bodyPart) {
      case BodyPart.upperBody:
        return 'UpperBody';
      case BodyPart.lowerBody:
        return 'LowerBody';
      case BodyPart.fullBody:
        return 'FullBody';
    }
  }

  /// MotionType을 Next.js 형식으로 변환
  String _convertMotionType(MotionType motionType) {
    switch (motionType) {
      case MotionType.isotonic:
        return 'Isotonic';
      case MotionType.isometric:
        return 'Isometric';
      case MotionType.isokinetic:
        return 'Isokinetic';
    }
  }
}
