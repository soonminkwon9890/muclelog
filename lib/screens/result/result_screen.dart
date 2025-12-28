import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../services/supabase_service.dart';
import '../../models/analysis_log.dart';
import '../../models/motion_type.dart';
import '../../models/biomechanics_result.dart';
import '../../utils/safe_calculations.dart';
import '../../utils/muscle_name_mapper.dart';

/// 분석 결과 화면
/// 영상 위에 서버에서 분석 결과를 표시하는 화면
class ResultScreen extends StatefulWidget {
  final String logId; // workout_logs.id (UUID String) - 필수

  const ResultScreen({super.key, required this.logId});

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

  // 🔧 workout_logs 전체 응답 저장 (analysis_result 직접 접근용)
  Map<String, dynamic>? _workoutLogResponse;

  // 🔧 DB에서 불러온 운동 이름 (exerciseName 파라미터 대신 사용)
  String? _exerciseNameFromDb;

  // Context 정보 (운동 맥락)
  String _targetBodyPart = 'WholeBody'; // 'UpperBody', 'LowerBody', 'WholeBody'
  String _contractionType = 'Isotonic'; // 'Isotonic', 'Isometric', 'Isokinetic'

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
  /// 🔧 핵심 원칙: DB에서만 데이터를 로드하여 업로드 직후와 재접속 시 일관성 보장
  Future<void> _loadAnalysisResult() async {
    // 🔧 로컬 상태 초기화 (이전 데이터 잔여 방지)
    // 업로드 직후와 재접속 시 완전히 동일한 화면을 보장하기 위해 이전 상태를 초기화
    _biomechanicsResult = null;
    _rawAnalysisData = null;
    _workoutLogResponse = null;
    _exerciseNameFromDb = null;
    _videoUrl = null;
    _errorMessage = null;

    // 재시도 로직 (최대 3회, 500ms 간격)
    int retryCount = 0;
    const maxRetries = 3;
    const retryDelay = Duration(milliseconds: 500);

    while (retryCount < maxRetries) {
      try {
        setState(() {
          _isLoading = true;
        });

        debugPrint(
          '🟢 [ResultScreen] DB 조회 시작: logId=${widget.logId}, 시도 ${retryCount + 1}/$maxRetries',
        );

        // UUID 유효성 검사
        if (widget.logId.isEmpty) {
          setState(() {
            _isLoading = false;
            _errorMessage = '잘못된 접근입니다. ID가 전달되지 않았습니다.';
          });
          debugPrint('🔴 [ResultScreen] logId가 비어있음');
          return;
        }

        // 1. workout_logs 테이블에서 분석 결과 조회
        // Primary Key: id 사용 (logId 사용)
        // 🔧 중요: workout_logs 테이블의 Primary Key는 'id' 컬럼입니다
        // 🔧 Fix: ai_analysis_result와 analysis_result 모두 조회하여 호환성 확보
        // 🔧 exercise_name도 함께 조회하여 DB에서 최신 데이터 불러오기
        final workoutLogResponse = await SupabaseService.instance.client
            .from('workout_logs')
            .select(
              'ai_analysis_result, analysis_result, video_path, status, exercise_name',
            )
            .eq('id', widget.logId)
            .maybeSingle();

        if (workoutLogResponse != null) {
          final workoutLog = workoutLogResponse;
          _workoutLogResponse = workoutLog;

          // 분석 결과 데이터 추출
          Map<String, dynamic>? analysisData;
          String? dataSource;

          // 1순위: ai_analysis_result 확인
          final aiResult = workoutLog['ai_analysis_result'];
          if (aiResult != null && aiResult is Map<String, dynamic>) {
            analysisData = aiResult;
            dataSource = 'ai_analysis_result';
            debugPrint('✅ [ResultScreen] ai_analysis_result에서 데이터 발견');
          }
          // 2순위: analysis_result 확인 (ai_analysis_result가 없을 때만)
          else {
            final analysisResult = workoutLog['analysis_result'];
            if (analysisResult != null &&
                analysisResult is Map<String, dynamic>) {
              analysisData = analysisResult;
              dataSource = 'analysis_result';
              debugPrint('✅ [ResultScreen] analysis_result에서 데이터 발견');
            }
          }

          if (analysisData != null) {
            // 원본 데이터 저장 (rom_data, motion_data 접근용)
            _rawAnalysisData = analysisData;

            // Context 정보 추출
            _extractContextInfo(analysisData);

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
          }

          // 영상 URL 추출
          final videoPath = workoutLog['video_path']?.toString();
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

          // exercise_name 추출
          _exerciseNameFromDb = workoutLog['exercise_name']?.toString();

          // 비디오 플레이어 초기화
          if (_videoUrl != null) {
            _videoController = VideoPlayerController.networkUrl(
              Uri.parse(_videoUrl!),
            );
            await _videoController!.initialize();
          }

          // 성공 시 루프 종료
          break;
        } else {
          throw Exception('데이터가 null입니다.');
        }
      } catch (e) {
        retryCount++;
        debugPrint(
          '⚠️ [ResultScreen] DB 조회 실패 (시도 $retryCount/$maxRetries): $e',
        );

        if (retryCount < maxRetries) {
          // 재시도 전 대기
          await Future.delayed(retryDelay);
        } else {
          // 최대 재시도 횟수 초과
          setState(() {
            _errorMessage = '데이터를 불러오는데 실패했습니다.';
          });
        }
      } finally {
        if (retryCount >= maxRetries || _biomechanicsResult != null) {
          setState(() {
            _isLoading = false;
          });
        }
      }
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
          title: Text(_exerciseNameFromDb ?? '운동 분석'),
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
        title: Text(_exerciseNameFromDb ?? '운동 분석'),
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

  /// Context 정보 추출
  void _extractContextInfo(Map<String, dynamic> analysisData) {
    try {
      final contextData = analysisData['context'] as Map<String, dynamic>?;
      if (contextData != null) {
        _targetBodyPart = contextData['bodyPart']?.toString() ?? 'WholeBody';
        _contractionType = contextData['contraction']?.toString() ?? 'Isotonic';
        debugPrint(
          '✅ [ResultScreen] Context 정보 추출: bodyPart=$_targetBodyPart, contraction=$_contractionType',
        );
      } else {
        // context가 없으면 기본값 유지
        debugPrint('⚠️ [ResultScreen] context 정보 없음, 기본값 사용');
      }
    } catch (e) {
      debugPrint('⚠️ [ResultScreen] Context 정보 추출 실패: $e');
    }
  }

  /// 근육이 상체 근육인지 확인
  bool _isUpperBodyMuscle(String muscleKey) {
    final lowerKey = muscleKey.toLowerCase();
    return lowerKey.contains('trapezius') ||
        lowerKey.contains('traps') ||
        lowerKey.contains('deltoid') ||
        lowerKey.contains('lat') ||
        lowerKey.contains('pectoralis') ||
        lowerKey.contains('pec') ||
        lowerKey.contains('biceps') ||
        lowerKey.contains('triceps');
  }

  /// 근육이 하체 근육인지 확인
  bool _isLowerBodyMuscle(String muscleKey) {
    final lowerKey = muscleKey.toLowerCase();
    return lowerKey.contains('glute') ||
        lowerKey.contains('quad') ||
        lowerKey.contains('hamstring') ||
        lowerKey.contains('erector') ||
        lowerKey.contains('spine') ||
        lowerKey.contains('calf') ||
        lowerKey.contains('thigh');
  }

  /// 지능형 필터링: 유효한 근육인지 확인
  bool _isValidMuscle(String muscleKey, double score) {
    // 1. 미세 노이즈 필터링 (0.1% 미만)
    if (score < 0.1) {
      return false;
    }

    // 2. Context 기반 필터링
    if (_targetBodyPart == 'LowerBody') {
      // 하체 운동인데 상체 근육이면 숨김
      if (_isUpperBodyMuscle(muscleKey)) {
        // 단, 점수가 비정상적으로 높으면(30% 이상) 오류 감지를 위해 표시
        if (score >= 30.0) {
          debugPrint(
            '⚠️ [ResultScreen] 하체 운동 중 상체 근육($muscleKey) 높은 점수 감지: ${score.toStringAsFixed(1)}%',
          );
          return true; // 오류 감지를 위해 표시
        }
        return false; // 숨김
      }
    } else if (_targetBodyPart == 'UpperBody') {
      // 상체 운동인데 하체 근육이면 숨김
      if (_isLowerBodyMuscle(muscleKey)) {
        // 단, 점수가 비정상적으로 높으면(30% 이상) 오류 감지를 위해 표시
        if (score >= 30.0) {
          debugPrint(
            '⚠️ [ResultScreen] 상체 운동 중 하체 근육($muscleKey) 높은 점수 감지: ${score.toStringAsFixed(1)}%',
          );
          return true; // 오류 감지를 위해 표시
        }
        return false; // 숨김
      }
    }

    // 3. 유효한 근육
    return true;
  }

  /// 비교 분석 카드 (동적 랭킹 방식, 필터링된 데이터만 사용)
  Widget _buildComparisonCard() {
    if (_biomechanicsResult == null) {
      return const SizedBox.shrink();
    }

    final List<String> comparisonTexts = [];

    // 필터링된 근육 데이터 가져오기
    final filteredMuscleData = _getFilteredMuscleData();

    // 근육 비교: 1위 vs 2위 (필터링된 데이터만 사용)
    if (filteredMuscleData.isNotEmpty) {
      final sortedMuscles = filteredMuscleData.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));

      if (sortedMuscles.length >= 2) {
        final first = sortedMuscles[0];
        final second = sortedMuscles[1];
        final firstScore = first.value;
        final secondScore = second.value;

        if (firstScore > 0 && secondScore > 0) {
          final diffPercent = ((firstScore - secondScore) / secondScore * 100)
              .clamp(0.0, 1000.0);
          // 🔧 0.0% 차이는 표시하지 않음 (의미 없는 비교)
          if (diffPercent > 0.1) {
            final firstName = MuscleNameMapper.localize(first.key);
            final secondName = MuscleNameMapper.localize(second.key);
            comparisonTexts.add(
              '현재 동작에서는 $firstName이 $secondName보다 ${diffPercent.toStringAsFixed(1)}% 더 높은 활성도를 보였습니다.',
            );
          }
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
          // 🔧 0.0% 차이는 표시하지 않음 (의미 없는 비교)
          if (diffPercent > 0.1) {
            // 🔧 원본 키를 그대로 전달하여 '왼쪽/오른쪽' 구분 유지
            final firstName = MuscleNameMapper.localize(first.key);
            final secondName = MuscleNameMapper.localize(second.key);
            comparisonTexts.add(
              '현재 동작에서는 $firstName이 $secondName보다 ${diffPercent.toStringAsFixed(1)}% 더 많이 사용되었습니다.',
            );
          }
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

  /// 필터링된 근육 데이터 가져오기
  /// 🔧 우선순위: muscle_usage (VideoRepository에서 저장) > muscleScores (백엔드) > 재계산
  Map<String, double> _getFilteredMuscleData() {
    final muscleData = <String, double>{};

    // 🔧 1순위: analysis_result['muscle_usage'] 직접 사용 (VideoRepository에서 저장한 데이터)
    // _rawAnalysisData는 ai_analysis_result 또는 analysis_result 중 하나만 저장하므로,
    // workout_logs에서 직접 analysis_result를 확인해야 함
    Map<String, dynamic>? muscleUsageRaw;

    // 1-1. _rawAnalysisData에서 확인 (ai_analysis_result 또는 analysis_result)
    if (_rawAnalysisData != null) {
      try {
        muscleUsageRaw =
            _rawAnalysisData!['muscle_usage'] as Map<String, dynamic>?;
        if (muscleUsageRaw != null && muscleUsageRaw.isNotEmpty) {
          debugPrint(
            '✅ [ResultScreen] _rawAnalysisData에서 muscle_usage 발견: ${muscleUsageRaw.length}개',
          );
        }
      } catch (e) {
        debugPrint(
          '⚠️ [ResultScreen] _rawAnalysisData에서 muscle_usage 파싱 실패: $e',
        );
      }
    }

    // 1-2. _rawAnalysisData에 없으면, workout_logs의 analysis_result에서 직접 확인
    // (ai_analysis_result가 우선되어 analysis_result가 _rawAnalysisData에 없을 수 있음)
    if ((muscleUsageRaw == null || muscleUsageRaw.isEmpty) &&
        _workoutLogResponse != null) {
      try {
        final analysisResult =
            _workoutLogResponse!['analysis_result'] as Map<String, dynamic>?;
        if (analysisResult != null) {
          muscleUsageRaw =
              analysisResult['muscle_usage'] as Map<String, dynamic>?;
          if (muscleUsageRaw != null && muscleUsageRaw.isNotEmpty) {
            debugPrint(
              '✅ [ResultScreen] workout_logs.analysis_result에서 muscle_usage 발견: ${muscleUsageRaw.length}개',
            );
          }
        }
      } catch (e) {
        debugPrint(
          '⚠️ [ResultScreen] workout_logs.analysis_result에서 muscle_usage 파싱 실패: $e',
        );
      }
    }

    // 1-3. muscle_usage 데이터 파싱 및 필터링
    if (muscleUsageRaw != null && muscleUsageRaw.isNotEmpty) {
      try {
        for (final entry in muscleUsageRaw.entries) {
          final muscleKey = entry.key;
          final value = entry.value;
          double? score;

          if (value is num) {
            score = value.toDouble();
          } else if (value is String) {
            score = double.tryParse(value);
          }

          if (score != null && score > 0 && !score.isNaN && !score.isInfinite) {
            // 지능형 필터링 적용
            if (_isValidMuscle(muscleKey, score)) {
              muscleData[muscleKey] = score;
            }
          }
        }
        debugPrint(
          '✅ [ResultScreen] muscle_usage에서 ${muscleData.length}개 근육 로드',
        );
      } catch (e) {
        debugPrint('⚠️ [ResultScreen] muscle_usage 파싱 실패: $e');
      }
    } else {
      debugPrint(
        '⚠️ [ResultScreen] muscle_usage를 찾을 수 없음 (_rawAnalysisData와 analysis_result 모두 확인)',
      );
    }

    // 🔧 2순위: muscleScores (백엔드 데이터) - muscle_usage가 없을 때만 사용
    if (muscleData.isEmpty &&
        _biomechanicsResult!.muscleScores != null &&
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
          // 지능형 필터링 적용
          if (_isValidMuscle(muscleKey, finalScore)) {
            muscleData[muscleKey] = finalScore;
          }
        }
      }
      debugPrint('✅ [ResultScreen] muscleScores에서 ${muscleData.length}개 근육 로드');
    }

    return muscleData;
  }

  /// 근육 탭 UI (3단계 폴백 전략, Progress Bar, 색상 코딩, 지능형 필터링)
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

    // 필터링된 근육 데이터 가져오기
    final muscleData = _getFilteredMuscleData();

    // 🔧 muscleData가 비어있으면 로딩을 멈추고 메시지 표시 (무한 로딩 방지)
    if (muscleData.isEmpty) {
      return Container(
        color: Colors.white,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.info_outline, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text(
                  '근육 활성도 데이터가 부족합니다.',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Colors.grey.shade700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  '분석이 완료되지 않았거나 데이터가 없습니다.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                // 0% 막대그래프 시각화 (데이터 없음 표시)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16.0),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '데이터 없음',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: 0.0,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.grey.shade300,
                          ),
                          minHeight: 8,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '0.0%',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
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

  /// 근육 점수 가져오기 (DB에서 직접 사용)
  /// 새 엔진은 이미 DB에 계산된 값을 사용하므로 재계산 불필요
  double? _recalculateMuscleScore(String muscleKey) {
    // DB에서 로드한 muscleScores 데이터를 직접 사용
    final muscleScores = _biomechanicsResult?.muscleScores;
    if (muscleScores != null) {
      final muscleScore = muscleScores[muscleKey];
      if (muscleScore != null && muscleScore.score > 0) {
        return muscleScore.score;
      }
    }

    // analysis_result에서 muscle_usage 확인
    if (_workoutLogResponse != null) {
      final analysisResult =
          _workoutLogResponse!['analysis_result'] as Map<String, dynamic>?;
      if (analysisResult != null) {
        final muscleUsage =
            analysisResult['muscle_usage'] as Map<String, dynamic>?;
        if (muscleUsage != null) {
          final score = muscleUsage[muscleKey];
          if (score != null && score is num && score > 0) {
            return score.toDouble();
          }
        }
      }
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
        final jointKey = entry.key; // 🔧 원본 키 보존
        final jointStat = entry.value;
        // 값이 0이거나 의미 없는 데이터는 필터링
        if (jointStat.romDegrees > 0 ||
            jointStat.contributionScore > 0 ||
            jointStat.stabilityScore > 0) {
          // 🔧 원본 키를 그대로 저장하여 '왼쪽/오른쪽' 구분 유지
          jointData[jointKey] = jointStat;
          debugPrint(
            '✅ [ResultScreen] 관절 데이터 추가: $jointKey -> 기여도: ${jointStat.romDegrees.toStringAsFixed(1)}%',
          );
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

    // 🔧 정렬: romDegrees 기준 내림차순 (주동 관절이 100%로 맨 위에 표시)
    final sorted = jointData.entries.toList()
      ..sort((a, b) => b.value.romDegrees.compareTo(a.value.romDegrees));

    return Container(
      color: Colors.white,
      child: ListView.builder(
        padding: const EdgeInsets.all(16.0),
        physics: const AlwaysScrollableScrollPhysics(),
        itemCount: sorted.length,
        itemBuilder: (context, index) {
          final entry = sorted[index];
          final jointName = entry.key; // 🔧 원본 키 (예: left_hip, hip_L 등)
          final jointStat = entry.value;
          // [주석 추가] jointStat.romDegrees 변수는 실제로는 기여도(%) 값이 들어있음
          final contributionPercent =
              jointStat.romDegrees; // 변수명은 유지하되 의미는 %로 변경

          // Progress 계산: 0~100% 범위로 정규화 (기존 0~180도 대신)
          final contributionProgress = (contributionPercent / 100.0).clamp(
            0.0,
            1.0,
          );

          // [UX 강화] 동적 색상 결정 (기여도에 따라 색상 농도 변경)
          Color getContributionColor(double percent) {
            if (percent == 0.0) {
              return Colors.grey; // 0%: 회색
            } else if (percent < 20.0) {
              return Colors.orange.shade300; // 0~20%: 연한 색 (미미함)
            } else if (percent < 50.0) {
              return Colors.orange.shade700; // 20~50%: 중간 색 (보조 사용됨)
            } else {
              return Colors.orange.shade900; // 50% 이상: 아주 진한 색 (주로 사용됨)
            }
          }

          final contributionColor = getContributionColor(contributionPercent);

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
                          // 🔧 원본 키(jointName)를 그대로 전달하여 '왼쪽/오른쪽' 구분 유지
                          MuscleNameMapper.localize(jointName),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      Text(
                        '${SafeCalculations.formatValueOrNA(contributionPercent)}%',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: contributionColor, // 동적 색상 적용
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: contributionProgress, // 0~100% 기준 (기존 0~180도 대신)
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        contributionColor, // 동적 색상 적용
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
