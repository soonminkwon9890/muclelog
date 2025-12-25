import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'dart:ui' as ui;
import '../../services/supabase_service.dart';
import '../../utils/muscle_name_mapper.dart';

/// 개인 분석 화면 (Individual Analysis)
///
/// 철학: [No Teaching, Just Measuring]
/// - 사용자에게 지시나 조언을 하지 않음
/// - 순수 역학적 움직임을 수치화하여 객관적으로 표시
/// - 가치 판단 없이 현상 기술과 수치 제시만 수행
class IndividualAnalysisScreen extends StatefulWidget {
  final String logId; // UUID String
  final String? exerciseName;

  const IndividualAnalysisScreen({
    super.key,
    required this.logId,
    this.exerciseName,
  });

  @override
  State<IndividualAnalysisScreen> createState() =>
      _IndividualAnalysisScreenState();
}

class _IndividualAnalysisScreenState extends State<IndividualAnalysisScreen> {
  VideoPlayerController? _videoController;
  bool _isLoading = true;
  String? _errorMessage;
  String? _videoUrl;

  // Core Biomechanics Data (6가지 핵심 요소)
  String? _biomechPattern;
  Map<String, double>? _muscleUsage;
  Map<String, double>? _romData;
  Map<String, dynamic>? _metadata;

  // UI 상태
  bool _showGravityLine = true;
  bool _showVectors = true;
  bool _showJointAngles = false;
  int _selectedOverlayMode = 0; // 0: 기본, 1: 상세

  @override
  void initState() {
    super.initState();
    _loadAnalysisData();
  }

  /// 분석 데이터 로드
  Future<void> _loadAnalysisData() async {
    try {
      // 분석 로그 조회
      final response = await SupabaseService.instance.client
          .from('workout_logs')
          .select()
          .eq('id', widget.logId)
          .single();

      if (response['status'] != 'COMPLETED') {
        setState(() {
          _errorMessage = '분석이 아직 완료되지 않았습니다.';
          _isLoading = false;
        });
        return;
      }

      // 영상 URL 가져오기
      final videoPath = response['video_path']?.toString();
      if (videoPath == null) {
        throw Exception('영상 경로가 없습니다.');
      }
      _videoUrl = SupabaseService.instance.client.storage
          .from('videos')
          .getPublicUrl(videoPath);

      // 분석 결과 데이터 파싱
      final analysisResult =
          response['analysis_result'] as Map<String, dynamic>?;
      if (analysisResult != null) {
        _biomechPattern = analysisResult['biomech_pattern']?.toString();

        final muscleUsageRaw =
            analysisResult['detailed_muscle_usage'] as Map<String, dynamic>?;
        if (muscleUsageRaw != null) {
          _muscleUsage = {};
          for (final entry in muscleUsageRaw.entries) {
            final value = entry.value;
            if (value is num) {
              _muscleUsage![entry.key] = value.toDouble();
            }
          }
        }

        final romDataRaw = analysisResult['rom_data'] as Map<String, dynamic>?;
        if (romDataRaw != null) {
          _romData = {};
          for (final entry in romDataRaw.entries) {
            final value = entry.value;
            if (value is num) {
              _romData![entry.key] = value.toDouble();
            }
          }
        }

        // 메타데이터 (6가지 핵심 요소 데이터)
        _metadata = analysisResult['metadata'] as Map<String, dynamic>?;
      }

      // 비디오 플레이어 초기화
      if (_videoUrl != null) {
        _videoController = VideoPlayerController.networkUrl(
          Uri.parse(_videoUrl!),
        );
        await _videoController!.initialize();
        _videoController!.setLooping(true);
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('🔴 분석 데이터 로드 실패: $e');
      debugPrint('🔴 스택 트레이스: $stackTrace');
      setState(() {
        _errorMessage = '데이터 로드 실패: $e';
        _isLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('오류')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 64, color: Colors.red),
                const SizedBox(height: 16),
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 16),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('돌아가기'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(
          widget.exerciseName ?? '운동 분석',
          style: const TextStyle(color: Colors.white),
        ),
        backgroundColor: Colors.black87,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // 오버레이 설정 토글
          PopupMenuButton<String>(
            icon: const Icon(Icons.settings, color: Colors.white),
            color: Colors.grey[900],
            onSelected: (value) {
              setState(() {
                switch (value) {
                  case 'gravity':
                    _showGravityLine = !_showGravityLine;
                    break;
                  case 'vectors':
                    _showVectors = !_showVectors;
                    break;
                  case 'angles':
                    _showJointAngles = !_showJointAngles;
                    break;
                }
              });
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'gravity',
                child: Row(
                  children: [
                    Icon(
                      _showGravityLine
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    const Text('중력선', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'vectors',
                child: Row(
                  children: [
                    Icon(
                      _showVectors
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    const Text('벡터', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'angles',
                child: Row(
                  children: [
                    Icon(
                      _showJointAngles
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 8),
                    const Text('관절 각도', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Smart Video Player & Overlay (최상단)
          Expanded(flex: 3, child: _buildVideoPlayerWithOverlay()),
          // 2. 측정 데이터 패널 (하단)
          Expanded(flex: 2, child: _buildMeasurementPanel()),
        ],
      ),
    );
  }

  /// 비디오 플레이어와 오버레이
  Widget _buildVideoPlayerWithOverlay() {
    if (_videoController == null) {
      return const Center(
        child: Text('영상을 불러올 수 없습니다.', style: TextStyle(color: Colors.white)),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        // 비디오 플레이어
        Center(
          child: AspectRatio(
            aspectRatio: _videoController!.value.aspectRatio,
            child: VideoPlayer(_videoController!),
          ),
        ),
        // 재생 컨트롤
        Positioned.fill(
          child: GestureDetector(
            onTap: () {
              setState(() {
                if (_videoController!.value.isPlaying) {
                  _videoController!.pause();
                } else {
                  _videoController!.play();
                }
              });
            },
            child: Container(
              color: Colors.transparent,
              child: Center(
                child: Icon(
                  _videoController!.value.isPlaying
                      ? Icons.pause_circle_outline
                      : Icons.play_circle_outline,
                  size: 64,
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
            ),
          ),
        ),
        // Measurement Overlay
        if (_showGravityLine || _showVectors || _showJointAngles)
          CustomPaint(
            painter: MeasurementOverlayPainter(
              showGravityLine: _showGravityLine,
              showVectors: _showVectors,
              showJointAngles: _showJointAngles,
              metadata: _metadata,
            ),
            child: Container(),
          ),
      ],
    );
  }

  /// 측정 데이터 패널
  Widget _buildMeasurementPanel() {
    return Container(
      color: Colors.grey[900],
      child: Column(
        children: [
          // 탭 선택
          _buildTabSelector(),
          // 데이터 표시 영역
          Expanded(
            child: _selectedOverlayMode == 0
                ? _buildBasicMeasurementView()
                : _buildDetailedMeasurementView(),
          ),
        ],
      ),
    );
  }

  /// 탭 선택기
  Widget _buildTabSelector() {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Colors.grey[800],
        border: Border(bottom: BorderSide(color: Colors.grey[700]!, width: 1)),
      ),
      child: Row(
        children: [
          Expanded(child: _buildTabButton('기본', 0)),
          Expanded(child: _buildTabButton('상세', 1)),
        ],
      ),
    );
  }

  Widget _buildTabButton(String label, int index) {
    final isSelected = _selectedOverlayMode == index;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedOverlayMode = index;
        });
      },
      child: Container(
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue[900] : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: isSelected ? Colors.blue : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[400],
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  /// 기본 측정 뷰
  Widget _buildBasicMeasurementView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 운동 패턴
        if (_biomechPattern != null)
          _buildMeasurementCard(
            title: '운동 패턴',
            value: _formatBiomechPattern(_biomechPattern!),
            icon: Icons.trending_up,
          ),
        const SizedBox(height: 12),
        // 주요 관절 ROM
        if (_romData != null && _romData!.isNotEmpty)
          _buildMeasurementCard(
            title: '주요 관절 가동범위',
            value: _formatTopJoints(_romData!),
            icon: Icons.accessibility_new,
          ),
        const SizedBox(height: 12),
        // 주요 근육 활성도
        if (_muscleUsage != null && _muscleUsage!.isNotEmpty)
          _buildMeasurementCard(
            title: '주요 근육 활성도',
            value: _formatTopMuscles(_muscleUsage!),
            icon: Icons.fitness_center,
          ),
      ],
    );
  }

  /// 상세 측정 뷰
  Widget _buildDetailedMeasurementView() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 6가지 핵심 요소 표시
        if (_metadata != null) ...[
          _buildCoreElementCard('1. 운동 패턴', _metadata!['regionDominance']),
          _buildCoreElementCard('2. 중력 벡터', _metadata!['isAntiGravity']),
          _buildCoreElementCard('3. 상완골 리듬', _metadata!['rhythmRatio']),
          _buildCoreElementCard('4. 동적 관절 가중치', _metadata!['ratios']),
          _buildCoreElementCard('5. 강성 vs 가동범위', _metadata!['isStiffnessMode']),
          _buildCoreElementCard('6. 보상 패턴', _metadata!['compensation']),
        ],
      ],
    );
  }

  /// 측정 카드
  Widget _buildMeasurementCard({
    required String title,
    required String value,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.blue[300], size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 핵심 요소 카드
  Widget _buildCoreElementCard(String title, dynamic data) {
    String displayValue = '측정 불가';
    if (data != null) {
      if (data is bool) {
        displayValue = data ? '감지됨' : '미감지';
      } else if (data is num) {
        displayValue = data.toStringAsFixed(2);
      } else if (data is String) {
        displayValue = data;
      } else if (data is Map) {
        displayValue = '${data.length}개 항목';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[800],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  displayValue,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 생체역학 패턴 포맷팅
  String _formatBiomechPattern(String pattern) {
    const patterns = {
      'LOWER_KNEE_DOMINANT': '하체 무릎 주도',
      'LOWER_HIP_DOMINANT': '하체 고관절 주도',
      'UPPER_PUSH': '상체 밀기',
      'UPPER_PULL': '상체 당기기',
      'UNKNOWN': '미분류',
    };
    return patterns[pattern] ?? pattern;
  }

  /// 상위 관절 포맷팅
  String _formatTopJoints(Map<String, double> romData) {
    final sorted = romData.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top3 = sorted.take(3);
    return top3
        .map((e) => '${_getJointName(e.key)}: ${e.value.toStringAsFixed(1)}%')
        .join(', ');
  }

  /// 상위 근육 포맷팅
  String _formatTopMuscles(Map<String, double> muscleUsage) {
    final sorted = muscleUsage.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top3 = sorted.take(3);
    return top3
        .map((e) => '${_getMuscleName(e.key)}: ${e.value.toStringAsFixed(1)}%')
        .join(', ');
  }

  /// 관절명 한글 변환
  String _getJointName(String key) {
    return MuscleNameMapper.getJointDisplayName(key);
  }

  /// 근육명 한글 변환
  String _getMuscleName(String key) {
    return MuscleNameMapper.localize(key);
  }
}

/// 측정 오버레이 페인터
class MeasurementOverlayPainter extends CustomPainter {
  final bool showGravityLine;
  final bool showVectors;
  final bool showJointAngles;
  final Map<String, dynamic>? metadata;

  MeasurementOverlayPainter({
    required this.showGravityLine,
    required this.showVectors,
    required this.showJointAngles,
    this.metadata,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // 중력선 (파란색 점선)
    if (showGravityLine) {
      paint
        ..color = Colors.blue.withValues(alpha: 0.6)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      final dashPath = ui.Path();
      final dashWidth = 5.0;
      final dashSpace = 5.0;
      final centerX = size.width / 2;

      for (double y = 0; y < size.height; y += dashWidth + dashSpace) {
        dashPath.moveTo(centerX, y);
        dashPath.lineTo(centerX, y + dashWidth);
      }

      canvas.drawPath(dashPath, paint);
    }

    // 벡터 (모멘트 암과 관절 토크)
    // Note: 포즈 랜드마크 데이터가 필요합니다.
    // 프레임별 포즈 좌표를 받아서 Force Vector와 Moment Arm을 계산하여 그려야 합니다.
    if (showVectors && metadata != null) {
      // 포즈 데이터가 추가되면 여기에 벡터 그리기 로직 구현
      // 예: shoulder -> wrist 벡터, hip -> knee 벡터 등
    }

    // 관절 각도
    // Note: 포즈 랜드마크 데이터가 필요합니다.
    // 3점(예: shoulder-elbow-wrist)으로 각도를 계산하여 표시해야 합니다.
    if (showJointAngles && metadata != null) {
      // 포즈 데이터가 추가되면 여기에 관절 각도 표시 로직 구현
      // 예: elbow 각도, knee 각도 등을 텍스트로 표시
    }
  }

  @override
  bool shouldRepaint(MeasurementOverlayPainter oldDelegate) {
    return showGravityLine != oldDelegate.showGravityLine ||
        showVectors != oldDelegate.showVectors ||
        showJointAngles != oldDelegate.showJointAngles ||
        metadata != oldDelegate.metadata;
  }
}
