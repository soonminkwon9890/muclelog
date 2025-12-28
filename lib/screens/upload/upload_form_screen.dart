import 'dart:io';
import 'package:flutter/material.dart';
import '../../repositories/video_repository.dart';
import '../../services/supabase_service.dart';
import '../../models/motion_type.dart';
import '../../models/body_part.dart';
import '../result/result_screen.dart';

/// 영상 업로드 설정 화면
/// 영상 제목과 타겟 부위를 입력받고 업로드 및 분석을 시작합니다.
class UploadFormScreen extends StatefulWidget {
  final File videoFile;

  const UploadFormScreen({super.key, required this.videoFile});

  @override
  State<UploadFormScreen> createState() => _UploadFormScreenState();
}

class _UploadFormScreenState extends State<UploadFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _videoTitleController;
  bool _guideComplied = false;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  BodyPart? _selectedBodyPart; // 운동 부위 (기본값: null, 선택 필수)
  MotionType? _selectedMotionType; // 운동 방식 (기본값: null, 선택 필수)

  @override
  void initState() {
    super.initState();
    _videoTitleController = TextEditingController(
      text: _generateDefaultVideoTitle(),
    );
  }

  @override
  void dispose() {
    _videoTitleController.dispose();
    super.dispose();
  }

  /// 기본 영상 제목 생성
  String _generateDefaultVideoTitle() {
    final now = DateTime.now();
    final hour = now.hour;
    final period = hour < 12 ? '오전' : (hour < 18 ? '오후' : '저녁');
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')} $period 운동';
  }

  /// 업로드 및 분석 시작
  Future<void> _startUpload() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (!_guideComplied) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('가이드 준수 확인을 체크해주세요.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    try {
      final user = SupabaseService.instance.currentUser;
      if (user == null) {
        throw Exception('로그인이 필요합니다.');
      }

      // 영상 제목 확인 (비어있으면 기본값 사용)
      final videoTitle = _videoTitleController.text.trim().isEmpty
          ? _generateDefaultVideoTitle()
          : _videoTitleController.text.trim();

      // 유효성 검사: 운동 부위와 운동 방식 모두 선택되어야 함
      if (_selectedBodyPart == null || _selectedMotionType == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('운동 부위와 운동 방식을 모두 선택해주세요.'),
            backgroundColor: Colors.orange,
          ),
        );
        setState(() {
          _isUploading = false;
        });
        return;
      }

      // VideoRepository를 통해 업로드 및 분석 수행
      // 🔧 Fix: BodyPart를 ExerciseType으로 변환 (하위 호환성)
      final exerciseType = _selectedBodyPart!.toExerciseType();
      // 🔧 Fix: MotionType Enum을 그대로 전달 (VideoRepository가 MotionType Enum을 받도록 설계됨)
      final motionType = _selectedMotionType!;
      // 🔧 Fix: BodyPart Enum을 그대로 전달 (VideoRepository가 BodyPart Enum을 받도록 설계됨)
      // VideoRepository 내부에서 bodyPart.value를 사용하여 DB에 저장하므로 Enum 그대로 전달
      final bodyPart = _selectedBodyPart!;

      debugPrint('🔍 [UploadFormScreen] 파라미터 확인:');
      debugPrint('   - bodyPart: ${bodyPart.name} (value: ${bodyPart.value})');
      debugPrint(
        '   - motionType: ${motionType.name} (value: ${motionType.value})',
      );
      debugPrint('   - exerciseType: ${exerciseType.name}');

      final result = await VideoRepository.instance.uploadVideoAndAnalyze(
        videoFile: widget.videoFile,
        videoTitle: videoTitle,
        exerciseType: exerciseType,
        motionType: motionType,
        bodyPart:
            bodyPart, // 🔧 Fix: BodyPart Enum 그대로 전달 (VideoRepository에서 .value로 변환)
        userId: user.id,
        onProgress: (progress) {
          setState(() {
            _uploadProgress = progress;
          });
        },
      );

      // 🔧 서버 응답에서 생성된 ID 추출 (workout_logs.id)
      // VideoRepository는 {'logId': String, 'videoId': String} 형태로 반환
      final videoId = (result['videoId'] ?? result['id'] ?? '')
          .toString(); // workout_logs.id (UUID String)
      final logId = (result['logId'] ?? result['id'] ?? '')
          .toString(); // workout_logs.id (UUID String)

      debugPrint(
        '✅ [UploadFormScreen] 업로드 완료 - videoId: $videoId, logId: $logId',
      );

      // 🔧 UUID 유효성 검사: 빈 문자열이면 에러 표시
      if (videoId.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('영상 업로드는 완료되었으나 ID를 가져오지 못했습니다. 다시 시도해주세요.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        debugPrint('🔴 [UploadFormScreen] videoId가 비어있음: $result');
        return;
      }

      // 🔧 결과 화면으로 이동 (히스토리 상세 화면과 완전히 동일)
      // 🔧 핵심 원칙: 로컬 데이터를 절대 전달하지 않고, 서버에서 생성된 ID만 전달
      // 🔧 목표: 히스토리 목록에서 클릭해서 들어가는 것과 완전히 똑같은 화면
      // 🔧 ResultScreen은 전달받은 ID를 사용하여 DB에서 최신 데이터를 강제로 로드함
      if (mounted) {
        final finalLogId = logId.isEmpty ? videoId : logId;
        debugPrint('🔄 [UploadFormScreen] ResultScreen (히스토리 상세 화면)으로 이동');
        debugPrint('   📊 videoId=$videoId, logId=$finalLogId');
        debugPrint('   🔧 ID만 전달 - ResultScreen이 DB에서 최신 데이터를 자동으로 조회합니다');
        debugPrint('   🔧 로컬 데이터 전달 없음 - DB 데이터만 사용하여 일관성 보장');
        // 🔧 pushReplacement: 업로드 화면을 히스토리 상세 화면으로 대체
        // 🔧 뒤로 가기 시 업로드 화면으로 돌아가지 않고 이전 화면으로 이동
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => ResultScreen(
              logId: finalLogId, // workout_logs.id (UUID String) - DB 조회용
            ),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('🔴 업로드/분석 실패: $e');
      debugPrint('🔴 스택 트레이스: $stackTrace');
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('오류 발생: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('영상 업로드 설정'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '영상 업로드 및 분석',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '영상 정보를 입력하고 업로드를 시작하세요.',
                  style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                ),
                const SizedBox(height: 32),

                // 영상 제목 입력 (필수)
                TextFormField(
                  controller: _videoTitleController,
                  decoration: const InputDecoration(
                    labelText: '영상 제목 *',
                    hintText: '오늘의 오운완 (예: 스쿼트 100개)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.title),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return '영상 제목을 입력해주세요.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),

                // 운동 부위 선택 섹션 (Choice Chips)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Text(
                              '운동 부위 (Target Area) *',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '*',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.red.shade400,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _buildBodyPartChip(bodyPart: BodyPart.upperBody),
                            _buildBodyPartChip(bodyPart: BodyPart.lowerBody),
                            _buildBodyPartChip(bodyPart: BodyPart.fullBody),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 운동 방식 선택 섹션
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '운동 방식 선택',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '운동의 생체역학적 특성을 선택하세요',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: _buildMotionTypeButton(
                                label: '등장성',
                                subtitle: '반복 운동',
                                motionType: MotionType.isotonic,
                                icon: Icons.repeat,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMotionTypeButton(
                                label: '등척성',
                                subtitle: '자세 유지',
                                motionType: MotionType.isometric,
                                icon: Icons.pause_circle_outline,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildMotionTypeButton(
                                label: '등속성',
                                subtitle: '일정 속도',
                                motionType: MotionType.isokinetic,
                                icon: Icons.speed,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // 가이드 준수 체크박스
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Checkbox(
                              value: _guideComplied,
                              onChanged: (value) {
                                setState(() {
                                  _guideComplied = value ?? false;
                                });
                              },
                            ),
                            const Expanded(
                              child: Text(
                                '촬영 가이드를 준수했습니다 *',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Padding(
                          padding: const EdgeInsets.only(left: 48),
                          child: Text(
                            '• 카메라를 고정하여 촬영했습니다\n'
                            '• 45도 측면 또는 정면에서 촬영했습니다\n'
                            '• 신체가 가려지지 않도록 촬영했습니다',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // 업로드 진행률 표시
                if (_isUploading) ...[
                  const Text(
                    '업로드 및 분석 중...',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(
                    value: _uploadProgress,
                    backgroundColor: Colors.grey.shade300,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      Colors.deepPurple,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${(_uploadProgress * 100).toStringAsFixed(1)}%',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 24),
                ],

                // 업로드 및 분석 시작 버튼
                ElevatedButton(
                  onPressed:
                      (_isUploading ||
                          _selectedBodyPart == null ||
                          _selectedMotionType == null)
                      ? null
                      : _startUpload,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  child: _isUploading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Text(
                          '업로드 및 분석 시작',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// 운동 방식 선택 버튼 위젯
  Widget _buildMotionTypeButton({
    required String label,
    required String subtitle,
    required MotionType motionType,
    required IconData icon,
  }) {
    final isSelected = _selectedMotionType == motionType;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedMotionType = motionType;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.deepPurple.withValues(alpha: 0.1)
              : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? Colors.deepPurple : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: isSelected ? Colors.deepPurple : Colors.grey.shade600,
              size: 24,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                color: isSelected ? Colors.deepPurple : Colors.grey.shade700,
              ),
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                color: isSelected
                    ? Colors.deepPurple.shade300
                    : Colors.grey.shade500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 운동 부위 선택 Chip 위젯
  Widget _buildBodyPartChip({required BodyPart bodyPart}) {
    final isSelected = _selectedBodyPart == bodyPart;
    return ChoiceChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(bodyPart.emoji, style: const TextStyle(fontSize: 18)),
          const SizedBox(width: 6),
          Text(
            bodyPart.displayName,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
      selected: isSelected,
      onSelected: (selected) {
        setState(() {
          _selectedBodyPart = selected ? bodyPart : null;
        });
      },
      selectedColor: Colors.deepPurple.withValues(alpha: 0.2),
      backgroundColor: Colors.grey.shade100,
      labelStyle: TextStyle(
        color: isSelected ? Colors.deepPurple : Colors.grey.shade700,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(
          color: isSelected ? Colors.deepPurple : Colors.grey.shade300,
          width: isSelected ? 2 : 1,
        ),
      ),
    );
  }
}
