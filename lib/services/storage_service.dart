import 'dart:io';
import 'dart:typed_data';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'supabase_service.dart';

/// Supabase Storage 서비스
/// 영상 파일 업로드 및 관리를 담당합니다.
class StorageService {
  static StorageService? _instance;
  static StorageService get instance {
    _instance ??= StorageService._();
    return _instance!;
  }

  StorageService._();

  /// 영상 파일 업로드
  /// [file] 업로드할 파일
  /// [path] Storage 내 저장 경로 (예: 'videos/user_id/video_name.mp4')
  /// [onProgress] 업로드 진행률 콜백 (0.0 ~ 1.0)
  Future<String> uploadVideo({
    required File file,
    required String path,
    Function(double)? onProgress,
  }) async {
    try {
      final fileSize = await file.length();
      int uploadedBytes = 0;

      final stream = file.openRead();
      final chunks = <List<int>>[];

      await for (final chunk in stream) {
        chunks.add(chunk);
        uploadedBytes += chunk.length;

        if (onProgress != null) {
          onProgress(uploadedBytes / fileSize);
        }
      }

      final bytes = Uint8List.fromList(
        chunks.expand((chunk) => chunk).toList(),
      );

      await SupabaseService.instance.client.storage
          .from('videos')
          .uploadBinary(
            path,
            bytes,
            fileOptions: const FileOptions(
              contentType: 'video/mp4',
              upsert: false,
            ),
          );

      // 공개 URL 가져오기 (비공개 버킷인 경우 서명된 URL 필요)
      final url = SupabaseService.instance.client.storage
          .from('videos')
          .getPublicUrl(path);

      return url;
    } catch (e) {
      throw Exception('영상 업로드 실패: $e');
    }
  }

  /// 파일 삭제
  Future<void> deleteVideo(String path) async {
    try {
      await SupabaseService.instance.client.storage.from('videos').remove([
        path,
      ]);
    } catch (e) {
      throw Exception('파일 삭제 실패: $e');
    }
  }

  /// 사용자별 영상 경로 생성
  String generateVideoPath(String userId, String fileName) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final sanitizedFileName = fileName.replaceAll(
      RegExp(r'[^a-zA-Z0-9._-]'),
      '_',
    );
    return '$userId/$timestamp-$sanitizedFileName';
  }
}
