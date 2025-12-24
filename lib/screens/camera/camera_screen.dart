import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';
import 'package:image_picker/image_picker.dart';
import '../upload/upload_form_screen.dart';

/// MediaPipe 카메라 화면
/// 후면 카메라를 전체 화면으로 표시하고 실시간 포즈 감지를 수행합니다.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  List<CameraDescription>? _cameras;
  bool _isInitialized = false;
  bool _isDetecting = false;
  PoseDetector? _poseDetector;
  List<Pose> _poses = [];
  final ImagePicker _imagePicker = ImagePicker();
  bool _isRecording = false;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initializePoseDetector();
  }

  /// 카메라 초기화
  Future<void> _initializeCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras == null || _cameras!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('카메라를 찾을 수 없습니다.')));
        }
        return;
      }

      // 후면 카메라 찾기
      CameraDescription? backCamera;
      for (var camera in _cameras!) {
        if (camera.lensDirection == CameraLensDirection.back) {
          backCamera = camera;
          break;
        }
      }

      // 후면 카메라가 없으면 첫 번째 카메라 사용
      backCamera ??= _cameras!.first;

      _controller = CameraController(
        backCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.yuv420
            : ImageFormatGroup.bgra8888,
      );

      await _controller!.initialize();

      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
        _startImageStream();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('카메라 초기화 실패: $e')));
      }
    }
  }

  /// 포즈 감지기 초기화
  void _initializePoseDetector() {
    final options = PoseDetectorOptions(
      mode: PoseDetectionMode.stream,
      model: PoseDetectionModel.accurate,
    );
    _poseDetector = PoseDetector(options: options);
  }

  /// 이미지 스트림 시작 (실시간 포즈 감지)
  void _startImageStream() {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }

    _controller!.startImageStream((CameraImage image) {
      if (_isDetecting) return;
      _isDetecting = true;

      _processImage(image)
          .then((_) {
            _isDetecting = false;
          })
          .catchError((e) {
            _isDetecting = false;
            debugPrint('포즈 감지 오류: $e');
          });
    });
  }

  /// 이미지 처리 및 포즈 감지
  Future<void> _processImage(CameraImage image) async {
    if (_poseDetector == null) return;

    final inputImage = _inputImageFromCameraImage(image);
    if (inputImage == null) return;

    try {
      final poses = await _poseDetector!.processImage(inputImage);
      if (mounted) {
        setState(() {
          _poses = poses;
        });
      }
    } catch (e) {
      debugPrint('포즈 처리 오류: $e');
    }
  }

  /// 갤러리에서 영상 선택
  Future<void> _pickVideoFromGallery() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
      );

      if (video != null && mounted) {
        _navigateToUploadForm(File(video.path));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('영상 선택 실패: $e')));
      }
    }
  }

  /// 영상 촬영 시작
  Future<void> _startRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }

    try {
      await _controller!.startVideoRecording();
      setState(() {
        _isRecording = true;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('촬영 시작 실패: $e')));
      }
    }
  }

  /// 영상 촬영 중지
  Future<void> _stopRecording() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      return;
    }

    try {
      final XFile video = await _controller!.stopVideoRecording();
      setState(() {
        _isRecording = false;
      });

      if (mounted) {
        // UploadFormScreen으로 이동
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => UploadFormScreen(videoFile: File(video.path)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('촬영 중지 실패: $e')));
      }
      setState(() {
        _isRecording = false;
      });
    }
  }

  /// 업로드 설정 화면으로 이동
  void _navigateToUploadForm(File videoFile) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => UploadFormScreen(videoFile: videoFile),
      ),
    );
  }

  /// CameraImage를 InputImage로 변환
  InputImage? _inputImageFromCameraImage(CameraImage image) {
    if (_controller == null) return null;

    final camera = _controller!.description;
    final imageRotation = InputImageRotation.values.firstWhere(
      (rotation) => rotation.rawValue == camera.sensorOrientation,
      orElse: () => InputImageRotation.rotation0deg,
    );

    final format = InputImageFormat.yuv420;
    final plane = image.planes[0];

    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: imageRotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _poseDetector?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            // 카메라 프리뷰
            if (_isInitialized && _controller != null)
              Positioned.fill(child: CameraPreview(_controller!))
            else
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),

            // 포즈 오버레이
            if (_isInitialized && _poses.isNotEmpty)
              CustomPaint(
                painter: PosePainter(
                  poses: _poses,
                  imageSize: Size(
                    _controller!.value.previewSize?.height ?? 0,
                    _controller!.value.previewSize?.width ?? 0,
                  ),
                ),
                child: Container(),
              ),

            // 상단 정보 바
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'MuscleLog',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.history, color: Colors.white),
                      tooltip: '기록 보기',
                      onPressed: () {
                        // 기록 보기는 메인 화면(DashboardScreen)에서 처리됩니다
                        Navigator.of(context).pop();
                      },
                    ),
                    if (_poses.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.8),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text(
                          '포즈 감지 중',
                          style: TextStyle(color: Colors.white, fontSize: 12),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // 하단 컨트롤 바
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // 갤러리 선택 버튼
                    IconButton(
                      icon: const Icon(
                        Icons.photo_library,
                        color: Colors.white,
                        size: 32,
                      ),
                      onPressed: _isRecording ? null : _pickVideoFromGallery,
                    ),

                    // 촬영 버튼
                    GestureDetector(
                      onTap: _isRecording ? _stopRecording : _startRecording,
                      child: Container(
                        width: 70,
                        height: 70,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _isRecording ? Colors.red : Colors.white,
                            width: 4,
                          ),
                          color: _isRecording
                              ? Colors.red.withValues(alpha: 0.3)
                              : Colors.transparent,
                        ),
                        child: Icon(
                          _isRecording ? Icons.stop : Icons.circle,
                          color: _isRecording ? Colors.red : Colors.white,
                          size: 50,
                        ),
                      ),
                    ),

                    // 빈 공간 (레이아웃 균형)
                    const SizedBox(width: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 포즈를 화면에 그리는 CustomPainter
class PosePainter extends CustomPainter {
  final List<Pose> poses;
  final Size imageSize;

  PosePainter({required this.poses, required this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.cyan
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke;

    final pointPaint = Paint()
      ..color = Colors.yellow
      ..style = PaintingStyle.fill;

    for (final pose in poses) {
      // 뼈대 그리기 (주요 관절 연결)
      _drawSkeleton(canvas, pose, paint, size);

      // 관절 점 그리기
      for (final landmark in pose.landmarks.values) {
        final point = _scalePoint(Offset(landmark.x, landmark.y), size);
        canvas.drawCircle(point, 5, pointPaint);
      }
    }
  }

  /// 뼈대 그리기
  void _drawSkeleton(Canvas canvas, Pose pose, Paint paint, Size size) {
    // 주요 연결선 정의
    final connections = [
      // 어깨
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.rightShoulder],
      // 왼팔
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftElbow],
      [PoseLandmarkType.leftElbow, PoseLandmarkType.leftWrist],
      // 오른팔
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
      [PoseLandmarkType.rightElbow, PoseLandmarkType.rightWrist],
      // 몸통
      [PoseLandmarkType.leftShoulder, PoseLandmarkType.leftHip],
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
      [PoseLandmarkType.leftHip, PoseLandmarkType.rightHip],
      // 왼다리
      [PoseLandmarkType.leftHip, PoseLandmarkType.leftKnee],
      [PoseLandmarkType.leftKnee, PoseLandmarkType.leftAnkle],
      // 오른다리
      [PoseLandmarkType.rightHip, PoseLandmarkType.rightKnee],
      [PoseLandmarkType.rightKnee, PoseLandmarkType.rightAnkle],
    ];

    for (final connection in connections) {
      final startLandmark = pose.landmarks[connection[0]];
      final endLandmark = pose.landmarks[connection[1]];

      if (startLandmark != null && endLandmark != null) {
        final start = _scalePoint(
          Offset(startLandmark.x, startLandmark.y),
          size,
        );
        final end = _scalePoint(Offset(endLandmark.x, endLandmark.y), size);
        canvas.drawLine(start, end, paint);
      }
    }
  }

  /// 좌표를 화면 크기에 맞게 스케일링
  Offset _scalePoint(Offset point, Size size) {
    // 카메라 이미지 크기를 화면 크기에 맞게 변환
    final scaleX = size.width / imageSize.width;
    final scaleY = size.height / imageSize.height;

    return Offset(point.dx * scaleX, point.dy * scaleY);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
