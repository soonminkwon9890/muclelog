import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../upload/upload_form_screen.dart';

/// 운동 영상 촬영 화면
/// 기본 시스템 카메라를 사용하여 비디오를 촬영합니다.
class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  final ImagePicker _imagePicker = ImagePicker();

  @override
  void initState() {
    super.initState();
    // 앱이 재실행되었을 때 잃어버린 데이터 복구 (안드로이드 앱 튕김 방지)
    _retrieveLostData();
  }

  /// 앱이 강제 종료되었다가 재실행되었을 때 촬영한 비디오 복구
  Future<void> _retrieveLostData() async {
    final LostDataResponse response = await _imagePicker.retrieveLostData();
    if (response.isEmpty) return;

    final List<XFile>? files = response.files;
    if (files != null && files.isNotEmpty && mounted) {
      // 비디오 파일 복구 성공
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => UploadFormScreen(
            videoFile: File(files.first.path),
          ),
        ),
      );
    }
  }

  /// 카메라에서 비디오 촬영
  Future<void> _pickVideoFromCamera() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.camera,
      );
      if (video != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => UploadFormScreen(
              videoFile: File(video.path),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('영상 촬영 실패: $e')),
        );
      }
    }
  }

  /// 갤러리에서 비디오 선택
  Future<void> _pickVideoFromGallery() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
      );
      if (video != null && mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => UploadFormScreen(
              videoFile: File(video.path),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('영상 선택 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('운동 영상 촬영'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: _pickVideoFromCamera,
              icon: const Icon(Icons.videocam),
              label: const Text('운동 영상 촬영하기'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _pickVideoFromGallery,
              icon: const Icon(Icons.photo_library),
              label: const Text('갤러리에서 선택'),
            ),
          ],
        ),
      ),
    );
  }
}
