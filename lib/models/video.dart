/// 영상 모델 클래스
/// videos 테이블의 데이터를 표현합니다.
class Video {
  final String id;
  final String userId;
  final String videoUrl;
  final String? thumbnailUrl;
  final String videoTitle;
  final String? targetArea; // 'UPPER', 'LOWER', 'FULL'
  final Map<String, dynamic>? analysisResult;
  final DateTime createdAt;

  Video({
    required this.id,
    required this.userId,
    required this.videoUrl,
    this.thumbnailUrl,
    required this.videoTitle,
    this.targetArea,
    this.analysisResult,
    required this.createdAt,
  });

  /// Map에서 Video 생성
  factory Video.fromMap(Map<String, dynamic> map) {
    // 날짜 파싱
    DateTime createdAt;
    try {
      final createdAtStr = map['created_at']?.toString();
      if (createdAtStr != null) {
        createdAt = DateTime.parse(createdAtStr);
      } else {
        createdAt = DateTime.now();
      }
    } catch (e) {
      createdAt = DateTime.now();
    }

    return Video(
      id: (map['id'] ?? '').toString(), // 안전 변환: int든 String이든 String으로
      userId: (map['user_id'] ?? '').toString(), // 안전 변환
      videoUrl: (map['video_url'] ?? '').toString(), // 안전 변환
      thumbnailUrl: map['thumbnail_url']?.toString(), // nullable 안전 변환
      videoTitle: map['video_title']?.toString() ?? '',
      targetArea: map['target_area']?.toString(), // nullable 안전 변환
      analysisResult: map['analysis_result'] as Map<String, dynamic>?,
      createdAt: createdAt,
    );
  }

  /// JSON에서 Video 생성
  factory Video.fromJson(Map<String, dynamic> json) => Video.fromMap(json);

  /// Map으로 변환
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'user_id': userId,
      'video_url': videoUrl,
      'thumbnail_url': thumbnailUrl,
      'video_title': videoTitle,
      'target_area': targetArea,
      'analysis_result': analysisResult,
      'created_at': createdAt.toIso8601String(),
    };
  }

  /// JSON으로 변환
  Map<String, dynamic> toJson() => toMap();

  /// 복사본 생성 (일부 필드만 변경)
  Video copyWith({
    String? id,
    String? userId,
    String? videoUrl,
    String? thumbnailUrl,
    String? videoTitle,
    String? targetArea,
    Map<String, dynamic>? analysisResult,
    DateTime? createdAt,
  }) {
    return Video(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      videoUrl: videoUrl ?? this.videoUrl,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      videoTitle: videoTitle ?? this.videoTitle,
      targetArea: targetArea ?? this.targetArea,
      analysisResult: analysisResult ?? this.analysisResult,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
