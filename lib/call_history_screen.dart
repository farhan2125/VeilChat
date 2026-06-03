import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'veil_theme.dart';
import 'veil_components.dart';
import 'services/database_service.dart';
import 'services/network_service.dart';
import 'call_screen.dart';

/// Screen to display call history.
/// Shows all calls (audio/video, incoming/outgoing, missed/completed/declined).
/// Allows filtering and placing a new call.
class CallHistoryScreen extends StatefulWidget {
  final bool isDark;
  final VoidCallback toggleTheme;

  const CallHistoryScreen({
    super.key,
    required this.isDark,
    required this.toggleTheme,
  });

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen>
    with SingleTickerProviderStateMixin {
  final DatabaseService _db = DatabaseService();
  final NetworkService _network = NetworkService();

  List<Map<String, dynamic>> _allCalls = [];
  List<Map<String, dynamic>> _filteredCalls = [];
  bool _isLoading = true;
  String _filter = 'all'; // all, audio, video, missed
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadCallLogs();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    setState(() {
      switch (_tabController.index) {
        case 0:
          _filter = 'all';
          break;
        case 1:
          _filter = 'audio';
          break;
        case 2:
          _filter = 'video';
          break;
        case 3:
          _filter = 'missed';
          break;
      }
      _applyFilter();
    });
  }

  Future<void> _loadCallLogs() async {
    final currentUser = _network.currentUser;
    if (currentUser == null) return;
    final logs = await _db.getAllCallLogs(currentUser);
    if (mounted) {
      setState(() {
        _allCalls = logs;
        _applyFilter();
        _isLoading = false;
      });
    }
  }

  void _applyFilter() {
    setState(() {
      if (_filter == 'all') {
        _filteredCalls = List.from(_allCalls);
      } else if (_filter == 'audio') {
        _filteredCalls = _allCalls.where((c) => c['callType'] == 'audio').toList();
      } else if (_filter == 'video') {
        _filteredCalls = _allCalls.where((c) => c['callType'] == 'video').toList();
      } else if (_filter == 'missed') {
        _filteredCalls = _allCalls.where((c) => c['status'] == 'missed').toList();
      }
    });
  }

  Future<void> _placeCall(String contact, bool isAudioOnly) async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CallScreen(
          contactName: contact,
          isIncoming: false,
          isDark: widget.isDark,
          isAudioOnly: isAudioOnly,
        ),
      ),
    );
  }

  String _formatDuration(int? seconds) {
    if (seconds == null) return '--:--';
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = VeilTheme.accentColor;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              color: (widget.isDark ? Colors.black : Colors.white).withOpacity(0.2),
            ),
          ),
        ),
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios_new_rounded,
            color: widget.isDark ? Colors.white : Colors.black,
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Call History',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: widget.isDark ? Colors.white : Colors.black,
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: themeColor,
          labelColor: themeColor,
          unselectedLabelColor: widget.isDark ? Colors.white60 : Colors.black45,
          tabs: const [
            Tab(text: 'All'),
            Tab(text: 'Audio'),
            Tab(text: 'Video'),
            Tab(text: 'Missed'),
          ],
        ),
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator(color: themeColor))
          : _filteredCalls.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.call_end,
                        size: 60,
                        color: widget.isDark ? Colors.white24 : Colors.black26,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'No call history',
                        style: TextStyle(
                          fontSize: 18,
                          color: widget.isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Your calls will appear here',
                        style: TextStyle(
                          fontSize: 14,
                          color: widget.isDark ? Colors.white30 : Colors.black38,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(15, 20, 15, 30),
                  itemCount: _filteredCalls.length,
                  itemBuilder: (ctx, i) {
                    final call = _filteredCalls[i];
                    final isMissed = call['status'] == 'missed';
                    final isIncoming = call['direction'] == 'incoming';
                    final isAudio = call['callType'] == 'audio';
                    final contact = call['contact'];
                    final timestamp = call['startTime'];
                    final duration = call['duration'];
                    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
                    final timeStr = DateFormat('hh:mm a').format(date);
                    final dateStr = DateFormat('MMM d, yyyy').format(date);

                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      decoration: VeilTheme.ultraGlass(isDark: widget.isDark, radius: 20),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        leading: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isMissed
                                ? Colors.red.withOpacity(0.1)
                                : themeColor.withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            isAudio ? Icons.call : Icons.videocam,
                            color: isMissed ? Colors.red : themeColor,
                          ),
                        ),
                        title: Text(
                          contact,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: isMissed
                                ? Colors.red
                                : (widget.isDark ? Colors.white : Colors.black),
                          ),
                        ),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  isIncoming
                                      ? Icons.call_received
                                      : Icons.call_made,
                                  size: 12,
                                  color: isIncoming
                                      ? Colors.green
                                      : (isMissed ? Colors.red : Colors.blue),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isIncoming ? 'Incoming' : 'Outgoing',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: widget.isDark
                                        ? Colors.white60
                                        : Colors.black54,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Icon(
                                  Icons.access_time,
                                  size: 12,
                                  color: widget.isDark
                                      ? Colors.white38
                                      : Colors.black38,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  timeStr,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: widget.isDark
                                        ? Colors.white38
                                        : Colors.black38,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              dateStr,
                              style: TextStyle(
                                fontSize: 11,
                                color: widget.isDark
                                    ? Colors.white24
                                    : Colors.black26,
                              ),
                            ),
                          ],
                        ),
                        trailing: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            if (call['status'] == 'completed')
                              Text(
                                _formatDuration(duration),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: widget.isDark
                                      ? Colors.white54
                                      : Colors.black54,
                                ),
                              ),
                            const SizedBox(height: 8),
                            IconButton(
                              icon: Icon(
                                isAudio ? Icons.call : Icons.videocam,
                                size: 20,
                                color: themeColor,
                              ),
                              onPressed: () => _placeCall(contact, isAudio),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}