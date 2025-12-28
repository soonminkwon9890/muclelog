import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../../services/supabase_service.dart';
import '../camera/camera_screen.dart';
import '../upload/upload_form_screen.dart';
import '../history/comparison_screen.dart';
import '../result/result_screen.dart';

/// 메인 대시보드 화면
/// 최근 기록을 보여주고 새로운 분석을 시작할 수 있는 메인 화면입니다.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  // body_part 기준으로 그룹화: 'UpperBody', 'LowerBody', 'WholeBody'
  Map<String, List<Map<String, dynamic>>> _groupedLogs = {};
  bool _isLoading = true;
  bool _isSelectionMode = false; // 선택 모드 상태
  final Set<String> _selectedVideoIds = {}; // 선택된 비디오 ID들 (String으로 저장)

  @override
  void initState() {
    super.initState();
    _loadRecentLogs();
  }

  /// 모든 기록 로드 및 exerciseType별로 그룹화
  Future<void> _loadRecentLogs() async {
    try {
      final user = SupabaseService.instance.currentUser;
      if (user == null) {
        if (!mounted) return;
        setState(() {
          _isLoading = false;
        });
        return;
      }

      final response = await SupabaseService.instance.client
          .from('workout_logs')
          .select()
          .eq('user_id', user.id)
          .order('created_at', ascending: false);

      if (!mounted) return;

      // body_part별로 그룹화
      final grouped = <String, List<Map<String, dynamic>>>{
        'UpperBody': [],
        'LowerBody': [],
        'WholeBody': [],
      };

      for (final log in response) {
        final bodyPartStr = log['body_part']?.toString() ?? '';
        // body_part 값에 따라 분류 (대소문자 무시)
        String category;
        if (bodyPartStr.toLowerCase() == 'upperbody' ||
            bodyPartStr.toLowerCase() == 'upper_body') {
          category = 'UpperBody';
        } else if (bodyPartStr.toLowerCase() == 'lowerbody' ||
            bodyPartStr.toLowerCase() == 'lower_body') {
          category = 'LowerBody';
        } else if (bodyPartStr.toLowerCase() == 'wholebody' ||
            bodyPartStr.toLowerCase() == 'whole_body' ||
            bodyPartStr.toLowerCase() == 'fullbody' ||
            bodyPartStr.toLowerCase() == 'full_body') {
          category = 'WholeBody';
        } else {
          // 매칭되지 않으면 "전신"으로 분류
          category = 'WholeBody';
        }
        grouped[category]?.add(log);
      }

      setState(() {
        _groupedLogs = grouped;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('기록 로드 실패: $e');
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// 갤러리에서 영상 선택
  Future<void> _pickVideoFromGallery() async {
    try {
      final XFile? video = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
      );

      if (!mounted) return;
      if (video != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => UploadFormScreen(videoFile: File(video.path)),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('영상 선택 실패: $e')));
    }
  }

  /// 카메라로 촬영
  void _openCamera() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (context) => const CameraScreen()));
  }

  /// 영상 선택 다이얼로그 표시
  void _showVideoSourceDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.videocam),
              title: const Text('카메라로 촬영'),
              onTap: () {
                Navigator.pop(context);
                _openCamera();
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('갤러리에서 선택'),
              onTap: () {
                Navigator.pop(context);
                _pickVideoFromGallery();
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 로그아웃 확인 다이얼로그 표시
  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('로그아웃'),
        content: const Text('정말 로그아웃하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () async {
              if (!mounted) return;
              Navigator.pop(context);
              await _handleLogout();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('로그아웃'),
          ),
        ],
      ),
    );
  }

  /// 로그아웃 처리
  Future<void> _handleLogout() async {
    try {
      await SupabaseService.instance.signOut();
      debugPrint('🟢 로그아웃 완료');
      // AuthGate가 자동으로 세션 변경을 감지하여 로그인 화면으로 전환합니다.
    } catch (e) {
      debugPrint('🔴 로그아웃 실패: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('로그아웃 중 오류가 발생했습니다: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  /// 이름 편집 다이얼로그 표시
  void _showEditNameDialog(String logId, String currentName) {
    final controller = TextEditingController(text: currentName);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('운동 이름 수정'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: '운동 이름',
            hintText: '운동 이름을 입력하세요',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () async {
              final newName = controller.text.trim();
              if (newName.isEmpty) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('운동 이름을 입력해주세요.')));
                return;
              }

              Navigator.pop(dialogContext);

              try {
                await SupabaseService.instance.updateExerciseName(
                  logId: logId,
                  newName: newName,
                );
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('운동 이름이 수정되었습니다.')),
                );
                _loadRecentLogs();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('이름 수정 실패: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  /// 삭제 확인 다이얼로그 표시
  void _showDeleteDialog(String logId) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('기록 삭제'),
        content: const Text('정말 이 기록을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(dialogContext);

              try {
                await SupabaseService.instance.deleteAnalysisLog(logId);
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('기록이 삭제되었습니다.')));
                _loadRecentLogs();
              } catch (e) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('삭제 실패: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('MuscleLog'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(_isSelectionMode ? Icons.close : Icons.history),
            tooltip: _isSelectionMode ? '선택 모드 종료' : '비교 모드',
            onPressed: () {
              setState(() {
                if (_isSelectionMode) {
                  // 선택 모드 종료
                  _isSelectionMode = false;
                  _selectedVideoIds.clear();
                } else {
                  // 선택 모드 시작
                  _isSelectionMode = true;
                }
              });
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '로그아웃',
            onPressed: _showLogoutDialog,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadRecentLogs,
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _isAllLogsEmpty()
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.fitness_center,
                      size: 80,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 24),
                    Text(
                      '아직 분석 기록이 없습니다',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '하단 (+) 버튼을 눌러\n새로운 분석을 시작하세요',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  // 운동 부위별 아코디언 섹션
                  _buildBodyPartSection('UpperBody'),
                  const SizedBox(height: 8),
                  _buildBodyPartSection('LowerBody'),
                  const SizedBox(height: 8),
                  _buildBodyPartSection('WholeBody'),
                ],
              ),
      ),
      floatingActionButton: _isSelectionMode && _selectedVideoIds.length == 2
          ? FloatingActionButton.extended(
              onPressed: _navigateToComparison,
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.compare_arrows),
              label: const Text('비교 분석 시작하기'),
            )
          : FloatingActionButton.extended(
              onPressed: _showVideoSourceDialog,
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('새 분석'),
            ),
    );
  }

  /// 모든 기록이 비어있는지 확인
  bool _isAllLogsEmpty() {
    return _groupedLogs.values.every((logs) => logs.isEmpty);
  }

  /// 운동 부위별 섹션 헤더 라벨
  String _getBodyPartLabel(String bodyPart) {
    switch (bodyPart) {
      case 'UpperBody':
        return '상체 운동';
      case 'LowerBody':
        return '하체 운동';
      case 'WholeBody':
        return '전신 운동';
      default:
        return '전신 운동';
    }
  }

  /// 운동 부위별 아이콘
  IconData _getBodyPartIcon(String bodyPart) {
    switch (bodyPart) {
      case 'UpperBody':
        return Icons.accessibility_new;
      case 'LowerBody':
        return Icons.directions_walk;
      case 'WholeBody':
        return Icons.person;
      default:
        return Icons.person;
    }
  }

  /// 운동 부위별 아코디언 섹션 위젯
  Widget _buildBodyPartSection(String bodyPart) {
    final logs = _groupedLogs[bodyPart] ?? [];
    final count = logs.length;

    // 기록이 없으면 섹션을 표시하지 않음
    if (count == 0) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        leading: Icon(_getBodyPartIcon(bodyPart), color: Colors.deepPurple),
        title: Text(
          _getBodyPartLabel(bodyPart),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        trailing: _buildCountBadge(count),
        childrenPadding: const EdgeInsets.only(bottom: 8),
        children: [
          ...logs.map(
            (log) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8.0),
              child: _buildLogCard(log),
            ),
          ),
        ],
      ),
    );
  }

  /// 기록 개수 뱃지 위젯
  Widget _buildCountBadge(int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.deepPurple,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        count.toString(),
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  /// 비교 화면으로 이동
  void _navigateToComparison() {
    if (_selectedVideoIds.length != 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('비교하려면 정확히 2개를 선택해주세요.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // 선택된 로그들을 찾아서 리스트로 변환
    final selectedLogs = <Map<String, dynamic>>[];
    for (final logs in _groupedLogs.values) {
      for (final log in logs) {
        final logIdStr = log['log_id'].toString();
        if (_selectedVideoIds.contains(logIdStr)) {
          selectedLogs.add(log);
        }
      }
    }

    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) => ComparisonScreen(selectedLogs: selectedLogs),
          ),
        )
        .then((_) {
          // 비교 화면에서 돌아왔을 때 선택 모드 종료
          setState(() {
            _isSelectionMode = false;
            _selectedVideoIds.clear();
          });
        });
  }

  /// 선택 토글
  void _toggleSelection(String logIdStr, bool? checked) {
    if (checked == null) return;

    setState(() {
      if (checked) {
        if (_selectedVideoIds.length >= 2) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('비교는 2개까지만 가능합니다'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
          return;
        }
        _selectedVideoIds.add(logIdStr);
      } else {
        _selectedVideoIds.remove(logIdStr);
        if (_selectedVideoIds.isEmpty) {
          _isSelectionMode = false;
        }
      }
    });
  }

  /// 기록 카드 위젯
  Widget _buildLogCard(Map<String, dynamic> log) {
    // 🔧 workout_logs 테이블의 Primary Key: id (UUID String)
    final logId = (log['id'] ?? '').toString(); // UUID String
    final logIdStr = logId; // 이미 String이므로 toString() 불필요
    final exerciseName = log['exercise_name']?.toString() ?? '운동';
    final status = log['status']?.toString() ?? 'UNKNOWN';
    final createdAt = log['created_at']?.toString() ?? '';

    // analysis_result JSONB에서 점수 추출
    final analysisResult = log['analysis_result'] as Map<String, dynamic>?;
    final agonistScore = analysisResult?['agonist_avg_score'] as double?;
    final consistencyScore = analysisResult?['consistency_score'] as double?;

    // 날짜 포맷팅
    DateTime? date;
    try {
      date = DateTime.parse(createdAt);
    } catch (e) {
      date = null;
    }

    final isSelected = _selectedVideoIds.contains(logIdStr);

    return Card(
      margin: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
      color: _isSelectionMode && isSelected ? Colors.deepPurple.shade50 : null,
      child: ListTile(
        leading: _isSelectionMode
            ? Checkbox(
                value: isSelected,
                onChanged: (checked) => _toggleSelection(logIdStr, checked),
              )
            : _getStatusIcon(status),
        title: Text(
          exerciseName,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: _isSelectionMode && isSelected ? Colors.deepPurple : null,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (date != null)
              Text(
                '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
                '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            if (agonistScore != null || consistencyScore != null)
              const SizedBox(height: 4),
            if (agonistScore != null)
              Text(
                '주동근: ${agonistScore.toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 12),
              ),
            if (consistencyScore != null)
              Text(
                '일관성: ${consistencyScore.toStringAsFixed(1)}%',
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                if (value == 'edit') {
                  _showEditNameDialog(logId, exerciseName);
                } else if (value == 'delete') {
                  _showDeleteDialog(logId);
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 20),
                      SizedBox(width: 8),
                      Text('이름 수정'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete, size: 20, color: Colors.red),
                      SizedBox(width: 8),
                      Text('삭제', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
            if (status == 'COMPLETED')
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () {
                  if (mounted) {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => ResultScreen(logId: logId),
                      ),
                    );
                  }
                },
              ),
            if (status != 'COMPLETED') _getStatusChip(status),
          ],
        ),
        onTap: _isSelectionMode
            ? () => _toggleSelection(logIdStr, !isSelected)
            : (status == 'COMPLETED'
                  ? () {
                      if (mounted) {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => ResultScreen(logId: logId),
                          ),
                        );
                      }
                    }
                  : null),
      ),
    );
  }

  /// 상태 아이콘
  Widget _getStatusIcon(String status) {
    switch (status) {
      case 'COMPLETED':
        return const Icon(Icons.check_circle, color: Colors.green);
      case 'PROCESSING':
        return const Icon(Icons.hourglass_empty, color: Colors.orange);
      case 'FAILED':
        return const Icon(Icons.error, color: Colors.red);
      default:
        return const Icon(Icons.upload, color: Colors.grey);
    }
  }

  /// 상태 칩
  Widget _getStatusChip(String status) {
    Color color;
    String text;

    switch (status) {
      case 'PROCESSING':
        color = Colors.orange;
        text = '분석 중';
        break;
      case 'FAILED':
        color = Colors.red;
        text = '실패';
        break;
      default:
        color = Colors.grey;
        text = '업로드 중';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
