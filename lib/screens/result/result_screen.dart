import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../services/supabase_service.dart';
import '../../models/analysis_log.dart';
import '../../models/motion_type.dart';
import '../../models/biomechanics_result.dart';
import '../../utils/safe_calculations.dart';
import '../../utils/muscle_name_mapper.dart';
import '../../utils/muscle_metric_utils.dart';

/// 분석 결과 화면
/// 영상 위에 서버에서 분석 결과를 표시하는 화면
class ResultScreen extends StatefulWidget {
  final String videoId; // videos.id (UUID String) - 필수
  final String? logId; // workout_logs.id (UUID String) - 하위 호환성 (선택)
  final String exerciseName;

  const ResultScreen({
    super.key,
    required this.videoId,
    this.logId, // 선택적 파라미터로 변경
    required this.exerciseName,
  });

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen>
    with SingleTickerProviderStateMixin {
  VideoPlayerController? _videoController;
  bool _isLoading = true;
  String? _errorMessage;
  String? _videoUrl;

  // Core Engine 데이터 (BiomechanicsResult 모델 사용)
  BiomechanicsResult? _biomechanicsResult;

  // 원본 분석 데이터 (rom_data, motion_data 접근용)
  Map<String, dynamic>? _rawAnalysisData;

  // UI 상태
  int _currentMode = 0; // 0: 근육, 1: 관절

  // 🔧 TabController 명시적 관리
  late TabController _tabController;

  // 하위 호환성 (기존 데이터) - analysis_json 파싱 시에만 사용
  // ignore: unused_field
  String? _exerciseType;
  // ignore: unused_field
  ExerciseType? _dbExerciseType;
  // ignore: unused_field
  MotionType? _motionType;

  @override
  void initState() {
    super.initState();
    // 🔧 TabController 초기화
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: _currentMode,
    );
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {
          _currentMode = _tabController.index;
        });
      }
    });
    _loadAnalysisResult();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  /// 분석 결과 로드
  /// Single Source of Truth: workout_logs.ai_analysis_result만 사용
  Future<void> _loadAnalysisResult() async {
    try {
      debugPrint(
        '🟢 [ResultScreen] 분석 결과 로드 시작: videoId=${widget.videoId}, logId=${widget.logId}',
      );

      // 🔧 UUID 선택 로직:
      // 1순위: logId가 null이 아니고 빈 문자열이 아닐 때 -> logId 사용
      // 2순위: 그 외에는 항상 videoId 사용 (필수 파라미터)
      final queryId = (widget.logId != null && widget.logId!.isNotEmpty)
          ? widget.logId!
          : widget.videoId;

      // 🔧 UUID 유효성 검사: 최종 선택된 queryId가 빈 문자열이면 에러 표시
      if (queryId.isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMessage = '잘못된 접근입니다. ID가 전달되지 않았습니다.';
        });
        debugPrint(
          '🔴 [ResultScreen] queryId가 비어있음: videoId=${widget.videoId}, logId=${widget.logId}',
        );

        // 2초 후 이전 화면으로 돌아가기
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
        return;
      }

      // 1. workout_logs 테이블에서 분석 결과 조회
      // Primary Key: id 사용 (logId가 있으면 우선 사용, 없으면 videoId 사용)
      // 🔧 중요: workout_logs 테이블의 Primary Key는 'id' 컬럼입니다 (log_id 아님)
      // 🔧 Fix: ai_analysis_result와 analysis_result 모두 조회하여 호환성 확보
      final workoutLogResponse = await SupabaseService.instance.client
          .from('workout_logs')
          .select('ai_analysis_result, analysis_result, video_path, status')
          .eq('id', queryId)
          .maybeSingle();

      // 🔧 Fix: status가 PENDING 또는 ANALYZING인 경우 분석 중 메시지 표시
      if (workoutLogResponse != null) {
        final status = workoutLogResponse['status']?.toString() ?? 'UNKNOWN';
        debugPrint('🔍 [ResultScreen] 분석 상태 확인: status=$status');
        if (status == 'PENDING' || status == 'ANALYZING') {
          setState(() {
            _isLoading = false;
            _errorMessage = '분석이 진행 중입니다. 잠시 후 다시 시도해주세요.';
          });
          debugPrint('⚠️ [ResultScreen] 분석 진행 중: status=$status');
          return;
        }
      }

      // 분석 결과 데이터 확인 (우선순위: ai_analysis_result > analysis_result)
      Map<String, dynamic>? analysisData;
      String? dataSource;

      if (workoutLogResponse != null) {
        // 1순위: ai_analysis_result 확인
        final aiResult = workoutLogResponse['ai_analysis_result'];
        if (aiResult != null && aiResult is Map<String, dynamic>) {
          analysisData = aiResult;
          dataSource = 'ai_analysis_result';
          debugPrint('✅ [ResultScreen] ai_analysis_result에서 데이터 발견');
        }
        // 2순위: analysis_result 확인 (ai_analysis_result가 없을 때만)
        else {
          final analysisResult = workoutLogResponse['analysis_result'];
          if (analysisResult != null &&
              analysisResult is Map<String, dynamic>) {
            analysisData = analysisResult;
            dataSource = 'analysis_result';
            debugPrint('✅ [ResultScreen] analysis_result에서 데이터 발견');
          }
        }
      }

      if (analysisData != null) {
        // 원본 데이터 저장 (rom_data, motion_data 접근용)
        _rawAnalysisData = analysisData;

        // EnhancedAnalysisResult 형식으로 파싱
        try {
          _biomechanicsResult = BiomechanicsResult.fromAnalysisResult(
            analysisData,
          );
          debugPrint('✅ [ResultScreen] workout_logs.$dataSource에서 로드 완료');
          debugPrint(
            '   - jointStats: ${_biomechanicsResult!.jointStats?.length ?? 0}개',
          );
          debugPrint(
            '   - muscleScores: ${_biomechanicsResult!.muscleScores?.length ?? 0}개',
          );
        } catch (e, stackTrace) {
          debugPrint('⚠️ [ResultScreen] BiomechanicsResult 파싱 실패: $e');
          debugPrint('   스택: $stackTrace');
          _biomechanicsResult = null;
        }

        // 영상 URL 가져오기
        if (workoutLogResponse != null) {
          final videoPath = workoutLogResponse['video_path']?.toString();
          if (videoPath != null && videoPath.isNotEmpty) {
            // 🔧 video_path가 전체 URL인지 경로인지 확인
            if (videoPath.startsWith('http://') ||
                videoPath.startsWith('https://')) {
              // 이미 전체 URL이면 그대로 사용
              _videoUrl = videoPath;
            } else {
              // 경로만 있으면 Public URL로 변환
              _videoUrl = SupabaseService.instance.client.storage
                  .from('videos')
                  .getPublicUrl(videoPath);
            }
          }
        }
      } else {
        // 백엔드 데이터가 없으면 null로 설정 (레거시 Fallback 없음)
        _biomechanicsResult = null;
        _rawAnalysisData = null;
        debugPrint(
          '⚠️ [ResultScreen] workout_logs에서 분석 결과를 찾을 수 없음 (ai_analysis_result, analysis_result 모두 null)',
        );

        // workout_logs 테이블에서 영상 경로 조회
        final videoResponse = await SupabaseService.instance.client
            .from('workout_logs')
            .select('video_path')
            .eq('id', widget.videoId)
            .maybeSingle();

        if (videoResponse != null) {
          final videoPath = videoResponse['video_path']?.toString();
          if (videoPath != null) {
            // 🔧 video_path가 전체 URL인지 경로인지 확인
            if (videoPath.startsWith('http://') ||
                videoPath.startsWith('https://')) {
              // 이미 전체 URL이면 그대로 사용
              _videoUrl = videoPath;
            } else {
              // 경로만 있으면 Public URL로 변환
              _videoUrl = SupabaseService.instance.client.storage
                  .from('videos')
                  .getPublicUrl(videoPath);
            }
          }
        }
      }

      // 비디오 플레이어 초기화
      if (_videoUrl != null) {
        _videoController = VideoPlayerController.networkUrl(
          Uri.parse(_videoUrl!),
        );
        await _videoController!.initialize();
      }

      debugPrint('🟢 [ResultScreen] 분석 결과 로드 완료');
      setState(() {
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      debugPrint('🔴 분석 결과 로드 실패: $e');
      debugPrint('🔴 스택 트레이스: $stackTrace');
      setState(() {
        _errorMessage = '결과 로드 실패: $e';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        appBar: null,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('오류'),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
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

    // 데이터 확인 (Core Engine 데이터 없음)
    if (_biomechanicsResult == null) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.exerciseName),
          backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.info_outline, size: 64, color: Colors.grey),
                const SizedBox(height: 16),
                const Text(
                  '분석 데이터가 없습니다',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 8),
                Text(
                  '분석 결과를 기다리는 중이거나\n데이터가 아직 생성되지 않았습니다.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () {
                    // 새로고침: 분석 결과 다시 로드
                    setState(() {
                      _isLoading = true;
                      _biomechanicsResult = null;
                    });
                    _loadAnalysisResult();
                  },
                  icon: const Icon(Icons.refresh),
                  label: const Text('새로고침'),
                ),
                const SizedBox(height: 12),
                TextButton(
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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.exerciseName),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            tooltip: '기록 저장',
            onPressed: _saveResult,
          ),
        ],
      ),
      // 🔧 레이아웃: 비디오 플레이어 아래, 비교 분석 카드, 탭
      body: Column(
        children: [
          // [Area 1] Video Section (Fixed Header)
          Expanded(flex: 2, child: _buildVideoPlayer()),

          // [Area 2] Comparison Card (비디오 플레이어 아래, 탭 위)
          _buildComparisonCard(),

          // [Area 3] Tab & Content Section (Expanded Body)
          Expanded(
            flex: 3,
            child: Column(
              children: [
                // TabBar 추가 (명시적 탭 전환)
                TabBar(
                  controller: _tabController,
                  tabs: const [
                    Tab(text: '근육 분석'),
                    Tab(text: '관절 분석'),
                  ],
                  labelColor: Colors.black87,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: Colors.blue,
                ),
                // TabBarView (데이터 리스트만)
                Expanded(
                  child: Container(
                    color: Colors.white,
                    child: TabBarView(
                      controller: _tabController,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        // 근육 탭: 리스트만
                        _buildMuscleTab(),
                        // 관절 탭: 리스트만
                        _buildJointTab(),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 비디오 플레이어 빌드
  Widget _buildVideoPlayer() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return Container(
        color: Colors.black,
        child: const Center(
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: VideoPlayer(_videoController!),
        ),
        // 재생/일시정지 버튼만 (미니멀 컨트롤)
        GestureDetector(
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
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            padding: const EdgeInsets.all(16),
            child: Icon(
              _videoController!.value.isPlaying
                  ? Icons.pause
                  : Icons.play_arrow,
              color: Colors.white,
              size: 48,
            ),
          ),
        ),
      ],
    );
  }

  /// 비교 분석 카드 (동적 랭킹 방식)
  Widget _buildComparisonCard() {
    if (_biomechanicsResult == null) {
      return const SizedBox.shrink();
    }

    final List<String> comparisonTexts = [];

    // 근육 비교: 1위 vs 2위
    if (_biomechanicsResult!.muscleScores != null &&
        _biomechanicsResult!.muscleScores!.isNotEmpty) {
      final sortedMuscles = _biomechanicsResult!.muscleScores!.entries.toList()
        ..sort((a, b) => b.value.score.compareTo(a.value.score));

      if (sortedMuscles.length >= 2) {
        final first = sortedMuscles[0];
        final second = sortedMuscles[1];
        final firstScore = first.value.score;
        final secondScore = second.value.score;

        if (firstScore > 0 && secondScore > 0) {
          final diffPercent = ((firstScore - secondScore) / secondScore * 100)
              .clamp(0.0, 1000.0);
          final firstName = MuscleNameMapper.localize(first.key);
          final secondName = MuscleNameMapper.localize(second.key);
          comparisonTexts.add(
            '현재 동작에서는 $firstName이 $secondName보다 ${diffPercent.toStringAsFixed(1)}% 더 높은 활성도를 보였습니다.',
          );
        }
      }
    }

    // 관절 비교: 1위 vs 2위
    if (_biomechanicsResult!.jointStats != null &&
        _biomechanicsResult!.jointStats!.isNotEmpty) {
      final sortedJoints = _biomechanicsResult!.jointStats!.entries.toList()
        ..sort(
          (a, b) =>
              b.value.contributionScore.compareTo(a.value.contributionScore),
        );

      if (sortedJoints.length >= 2) {
        final first = sortedJoints[0];
        final second = sortedJoints[1];
        final firstScore = first.value.contributionScore;
        final secondScore = second.value.contributionScore;

        if (firstScore > 0 && secondScore > 0) {
          final diffPercent = ((firstScore - secondScore) / secondScore * 100)
              .clamp(0.0, 1000.0);
          final firstName = MuscleNameMapper.getJointDisplayName(first.key);
          final secondName = MuscleNameMapper.getJointDisplayName(second.key);
          comparisonTexts.add(
            '현재 동작에서는 $firstName이 $secondName보다 ${diffPercent.toStringAsFixed(1)}% 더 많이 사용되었습니다.',
          );
        }
      }
    }

    if (comparisonTexts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.all(16.0),
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics, color: Colors.blue.shade700),
              const SizedBox(width: 8),
              Text(
                '비교 분석',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...comparisonTexts.map(
            (text) => Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade800,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 근육 탭 UI (3단계 폴백 전략, Progress Bar, 색상 코딩)
  Widget _buildMuscleTab() {
    if (_biomechanicsResult == null) {
      return Container(
        color: Colors.white,
        child: const Center(
          child: Text(
            'N/A',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }

    // 백엔드의 muscle_scores만 사용 (Fallback 없음)
    final muscleData = <String, double>{};

    if (_biomechanicsResult!.muscleScores != null &&
        _biomechanicsResult!.muscleScores!.isNotEmpty) {
      for (final entry in _biomechanicsResult!.muscleScores!.entries) {
        final muscleKey = entry.key;
        final dbScore = entry.value.score;

        // 3단계 폴백 전략으로 최종 점수 계산
        double finalScore = dbScore;

        // 1순위: 재계산 시도
        if (dbScore == 0.0 || dbScore.isNaN || dbScore.isInfinite) {
          final recalculatedScore = _recalculateMuscleScore(muscleKey);
          if (recalculatedScore != null && recalculatedScore > 0) {
            finalScore = recalculatedScore;
          }
        }

        // 2순위: DB 값 사용 (이미 finalScore에 할당됨)

        // 3순위: 포맷팅 (값이 없으면 "-" 표시하도록 필터링)
        if (finalScore > 0 && !finalScore.isNaN && !finalScore.isInfinite) {
          muscleData[muscleKey] = finalScore;
        }
      }
    }

    // muscleData가 비어있으면 N/A 표시
    if (muscleData.isEmpty) {
      return Container(
        color: Colors.white,
        child: const Center(
          child: Text(
            'N/A',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }

    // 정렬 및 표시
    final sorted = muscleData.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      color: Colors.white,
      child: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: sorted.length,
        itemBuilder: (context, index) {
          final entry = sorted[index];
          final muscleKey = entry.key;
          final score = entry.value;

          return Card(
            margin: const EdgeInsets.only(bottom: 12.0),
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.accessibility,
                        size: 24,
                        color: _getScoreColor(score),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          MuscleNameMapper.localize(muscleKey),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      Text(
                        SafeCalculations.formatPercentOrNA(score),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: _getScoreColor(score),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: SafeCalculations.percentToProgress(score),
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _getScoreColor(score),
                      ),
                      minHeight: 8,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 근육 점수 재계산 (1순위: calculateLayeredActivation 호출)
  double? _recalculateMuscleScore(String muscleKey) {
    if (_rawAnalysisData == null) {
      return null;
    }

    try {
      // rom_data에서 rom 추출 시도
      final romData = _rawAnalysisData!['rom_data'] as Map<String, dynamic>?;
      double? rom;
      if (romData != null) {
        // 관절 키를 근육 키로 매핑 시도 (예: 'knee' -> 'quadriceps')
        final jointKey = _getJointKeyForMuscle(muscleKey);
        if (jointKey != null) {
          final romValue = romData[jointKey];
          if (romValue != null && romValue is num) {
            rom = romValue.toDouble();
          }
        }
      }

      // motion_data에서 deltaAngle 계산 시도
      // (간단화: rom이 있으면 deltaAngle로 사용)
      double? deltaAngle = rom;

      // calculateLayeredActivation 호출
      if (rom != null || deltaAngle != null) {
        final recalculated = MuscleMetricUtils.calculateLayeredActivation(
          muscleKey: muscleKey,
          deltaAngle: deltaAngle,
          rom: rom,
          timeDelta: 0.033,
        );
        if (recalculated > 0 && !recalculated.isNaN) {
          return recalculated;
        }
      }
    } catch (e) {
      debugPrint('⚠️ [ResultScreen] 근육 점수 재계산 실패: $e');
    }

    return null;
  }

  /// 근육 키에 해당하는 관절 키 반환 (간단한 매핑)
  String? _getJointKeyForMuscle(String muscleKey) {
    final lowerKey = muscleKey.toLowerCase();
    if (lowerKey.contains('quad') || lowerKey.contains('hamstring')) {
      return 'knee';
    } else if (lowerKey.contains('glute')) {
      return 'hip';
    } else if (lowerKey.contains('bicep') || lowerKey.contains('tricep')) {
      return 'elbow';
    } else if (lowerKey.contains('deltoid') || lowerKey.contains('pec')) {
      return 'shoulder';
    }
    return null;
  }

  /// 점수에 따른 색상 반환 (80↑ 초록, 50↑ 노랑, 그 외 회색)
  Color _getScoreColor(double score) {
    if (score >= 80) {
      return Colors.green.shade600;
    } else if (score >= 50) {
      return Colors.orange.shade600;
    } else {
      return Colors.grey.shade600;
    }
  }

  /// 관절 탭 UI (ROM 시각화, 데이터 필터링)
  Widget _buildJointTab() {
    if (_biomechanicsResult == null) {
      return Container(
        color: Colors.white,
        child: const Center(
          child: Text(
            'N/A',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }

    // 백엔드의 joint_stats만 사용 (Fallback 없음)
    final jointData = <String, JointStat>{};

    if (_biomechanicsResult!.jointStats != null &&
        _biomechanicsResult!.jointStats!.isNotEmpty) {
      for (final entry in _biomechanicsResult!.jointStats!.entries) {
        final jointStat = entry.value;
        // 값이 0이거나 의미 없는 데이터는 필터링
        if (jointStat.romDegrees > 0 ||
            jointStat.contributionScore > 0 ||
            jointStat.stabilityScore > 0) {
          jointData[entry.key] = jointStat;
        }
      }
    }

    // jointData가 비어있으면 N/A 표시
    if (jointData.isEmpty) {
      return Container(
        color: Colors.white,
        child: const Center(
          child: Text(
            'N/A',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
        ),
      );
    }

    // 정렬 및 표시
    final sorted = jointData.entries.toList()
      ..sort(
        (a, b) =>
            b.value.contributionScore.compareTo(a.value.contributionScore),
      );

    return Container(
      color: Colors.white,
      child: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: sorted.length,
        itemBuilder: (context, index) {
          final entry = sorted[index];
          final jointName = entry.key;
          final jointStat = entry.value;
          final romDegrees = jointStat.romDegrees;

          // ROM을 0~180도 범위로 정규화하여 progress 값 계산
          final romProgress = (romDegrees / 180.0).clamp(0.0, 1.0);

          return Card(
            margin: const EdgeInsets.only(bottom: 12.0),
            elevation: 0,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: Colors.grey.shade200, width: 1),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.accessibility_new,
                        size: 24,
                        color: Colors.blue.shade700,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          MuscleNameMapper.getJointDisplayName(jointName),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      Text(
                        '${SafeCalculations.formatValueOrNA(romDegrees)}°',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: romDegrees > 0
                              ? Colors.orange.shade700
                              : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: romProgress,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Colors.orange.shade600,
                      ),
                      minHeight: 8,
                    ),
                  ),
                  if (jointStat.contributionScore > 0) ...[
                    const SizedBox(height: 8),
                    Text(
                      '부하 기여도: ${SafeCalculations.formatPercentOrNA(jointStat.contributionScore)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// 결과 저장
  Future<void> _saveResult() async {
    // 이미 저장된 상태이므로 성공 메시지만 표시
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('기록이 저장되었습니다.')));
  }
}
