import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

/// 웹 전용 카메라 화면
/// 웹 환경에서는 실시간 카메라 대신 영상 파일 업로드 방식을 사용합니다.
class WebCameraScreen extends StatefulWidget {
  const WebCameraScreen({super.key});

  @override
  State<WebCameraScreen> createState() => _WebCameraScreenState();
}

class _WebCameraScreenState extends State<WebCameraScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  bool _isLoading = false;
  XFile? _selectedVideo;
  Uint8List? _videoBytes;

  /// 갤러리에서 영상 선택
  Future<void> _pickVideoFromGallery() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
      );

      if (video != null) {
        final bytes = await video.readAsBytes();
        setState(() {
          _selectedVideo = video;
          _videoBytes = bytes;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('영상 선택 실패: $e')));
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 웹캠으로 영상 촬영
  Future<void> _recordFromWebcam() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.camera,
        maxDuration: const Duration(minutes: 5),
      );

      if (video != null) {
        final bytes = await video.readAsBytes();
        setState(() {
          _selectedVideo = video;
          _videoBytes = bytes;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('웹캠 촬영 실패: $e')));
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 선택한 영상으로 분석 시작
  void _startAnalysis() {
    if (_selectedVideo != null && _videoBytes != null) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => ExerciseSetupScreenWeb(
            videoBytes: _videoBytes!,
            videoName: _selectedVideo!.name,
          ),
        ),
      );
    }
  }

  /// 선택 초기화
  void _clearSelection() {
    setState(() {
      _selectedVideo = null;
      _videoBytes = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('MuscleLog'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: '기록 보기',
            onPressed: () {
              // 기록 보기는 메인 화면(DashboardScreen)에서 처리됩니다
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 안내 텍스트
              const Icon(Icons.videocam, size: 80, color: Colors.deepPurple),
              const SizedBox(height: 24),
              const Text(
                '운동 영상을 업로드하세요',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '웹캠으로 촬영하거나 파일을 선택할 수 있습니다',
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
              ),
              const SizedBox(height: 48),

              // 선택된 영상 표시
              if (_selectedVideo != null) ...[
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green[300]!),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: Colors.green[600],
                        size: 48,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '선택된 영상',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.green[800],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _selectedVideo!.name,
                        style: TextStyle(color: Colors.green[700]),
                        textAlign: TextAlign.center,
                      ),
                      if (_videoBytes != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${(_videoBytes!.length / 1024 / 1024).toStringAsFixed(2)} MB',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green[600],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _clearSelection,
                      icon: const Icon(Icons.refresh),
                      label: const Text('다시 선택'),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: _startAnalysis,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('분석 시작'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                // 영상 선택 버튼들
                if (_isLoading)
                  const CircularProgressIndicator()
                else ...[
                  // 웹캠 촬영 버튼
                  SizedBox(
                    width: 280,
                    child: ElevatedButton.icon(
                      onPressed: _recordFromWebcam,
                      icon: const Icon(Icons.videocam),
                      label: const Text('웹캠으로 촬영'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // 파일 선택 버튼
                  SizedBox(
                    width: 280,
                    child: OutlinedButton.icon(
                      onPressed: _pickVideoFromGallery,
                      icon: const Icon(Icons.folder_open),
                      label: const Text('파일에서 선택'),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 32,
                          vertical: 16,
                        ),
                      ),
                    ),
                  ),
                ],
              ],

              const SizedBox(height: 48),

              // 지원 형식 안내
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700]),
                    const SizedBox(height: 8),
                    Text(
                      '지원 형식: MP4, MOV, AVI',
                      style: TextStyle(
                        color: Colors.blue[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      '최대 파일 크기: 100MB',
                      style: TextStyle(color: Colors.blue[600], fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 웹용 운동 설정 화면
/// 파일 객체 대신 바이트 데이터를 받습니다.
class ExerciseSetupScreenWeb extends StatelessWidget {
  final Uint8List videoBytes;
  final String videoName;

  const ExerciseSetupScreenWeb({
    super.key,
    required this.videoBytes,
    required this.videoName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('운동 설정'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.fitness_center,
                size: 64,
                color: Colors.deepPurple,
              ),
              const SizedBox(height: 24),
              Text(
                '영상: $videoName',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '파일 크기: ${(videoBytes.length / 1024 / 1024).toStringAsFixed(2)} MB',
                style: TextStyle(color: Colors.grey[600]),
              ),
              const SizedBox(height: 32),
              const Text(
                '웹 버전에서는 영상 분석 기능이\n제한적으로 제공됩니다.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              Text(
                '전체 기능을 사용하려면\n모바일 앱을 이용해주세요.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey[600]),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepPurple,
                  foregroundColor: Colors.white,
                ),
                child: const Text('돌아가기'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
