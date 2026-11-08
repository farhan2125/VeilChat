import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'branding/veil_brand.dart';
import 'veil_feedback.dart';
import 'veil_theme.dart';
import 'services/database_service.dart';
import 'services/network_service.dart';
import 'call_screen.dart';

/// ─────────────────────────────────────────────────────────────
/// VeilChat — Call History
///
/// ✅ HEADER BUG FIX
/// The previous implementation used `extendBodyBehindAppBar: true` with a
/// transparent [AppBar] whose blur lived in `flexibleSpace`. Because
/// `flexibleSpace` is laid out *inside* the toolbar box, the blur never covered
/// the status-bar strip — producing the clipped/overlapping artifact where the
/// "Call History" title and the All/Audio/Video/Missed chips rendered behind
/// the system bar.
///
/// The rewrite uses:
///   • [NestedScrollView] + [SliverOverlapAbsorber] / [SliverOverlapInjector]
///   • a pinned [SliverAppBar] so the header never leaves the viewport
///   • the [BackdropFilter] wrapped in a [ClipRect] sized to
///     `statusBar + toolbar + filterBar`, so the blur genuinely spans the
///     safe-area inset
///   • `systemOverlayStyle` so status-bar icons stay legible on both themes
/// ─────────────────────────────────────────────────────────────
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

  static const List<String> _filters = ['all', 'audio', 'video', 'missed'];
  static const List<String> _filterLabels = ['All', 'Audio', 'Video', 'Missed'];

  /// Height of the custom filter bar pinned under the toolbar.
  static const double _filterBarHeight = 56;

  List<Map<String, dynamic>> _allCalls = [];
  bool _isLoading = true;
  int _index = 0;

  late final TabController _tabController;


  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _filters.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadCallLogs();
  }

  @override
  void dispose() {
    // ✅ Leak fix: always detach the listener before disposing the controller.
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (!mounted || _tabController.index == _index) return;
    setState(() => _index = _tabController.index);
  }

  // ── Data ────────────────────────────────────────────────────
  Future<void> _loadCallLogs() async {
    final currentUser = _network.currentUser;
    if (currentUser == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    try {
      final logs = await _db.getAllCallLogs(currentUser);
      if (!mounted) return;
      setState(() {
        _allCalls = logs;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      VeilFeedback.error(context, 'Could not load call history');
      debugPrint('❌ loadCallLogs: $e');
    }
  }

  /// Pure filter — no nested `setState`, null-safe on every column.
  List<Map<String, dynamic>> _callsFor(String filter) {
    switch (filter) {
      case 'audio':
        return _allCalls
            .where((c) => (c['callType']?.toString() ?? '') == 'audio')
            .toList();
      case 'video':
        return _allCalls
            .where((c) => (c['callType']?.toString() ?? '') == 'video')
            .toList();
      case 'missed':
        return _allCalls
            .where((c) => (c['status']?.toString() ?? '') == 'missed')
            .toList();
      default:
        return List<Map<String, dynamic>>.from(_allCalls);
    }
  }

  int _countFor(String filter) => _callsFor(filter).length;

  Future<void> _deleteCall(Map<String, dynamic> call) async {
    final id = (call['id'] as num?)?.toInt();
    if (id == null) return;
    try {
      await _db.deleteCallLog(id);
      if (!mounted) return;
      setState(() => _allCalls.removeWhere((c) => c['id'] == call['id']));
      VeilFeedback.success(context, 'Call log removed');
    } catch (e) {
      if (!mounted) return;
      VeilFeedback.error(context, 'Could not delete call log');
    }
  }

  Future<void> _clearHistory() async {
    final user = _network.currentUser;
    if (user == null) return;

    final ok = await VeilFeedback.confirm(
      context,
      title: 'Clear call history?',
      message:
          'All ${_allCalls.length} call records on this device will be permanently deleted. This cannot be undone.',
      confirmLabel: 'Clear all',
      icon: Icons.delete_sweep_rounded,
      destructive: true,
    );
    if (!ok || !mounted) return;

    try {
      await _db.clearCallLogs(user);
      if (!mounted) return;
      setState(() => _allCalls = []);
      VeilFeedback.success(context, 'Call history cleared');
    } catch (e) {
      if (!mounted) return;
      VeilFeedback.error(context, 'Could not clear history');
    }
  }

  void _placeCall(String contact, bool isAudioOnly) {
    HapticFeedback.selectionClick();
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

  // ── Build ───────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final accent = VeilTheme.accentColor;
    final isDark = widget.isDark;
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: isDark ? VeilBrand.veilVoid : const Color(0xFFF6F8FE),
      body: NestedScrollView(
        headerSliverBuilder: (context, innerScrolled) => [
          SliverOverlapAbsorber(
            handle:
                NestedScrollView.sliverOverlapAbsorberHandleFor(context),
            sliver: SliverAppBar(
              // ✅ pinned keeps the header locked above the content instead of
              // letting rows paint over it.
              pinned: true,
              floating: false,
              forceElevated: innerScrolled,
              elevation: 0,
              scrolledUnderElevation: 0,
              backgroundColor: Colors.transparent,
              surfaceTintColor: Colors.transparent,
              // ✅ Keeps status-bar glyphs readable over the blur.
              systemOverlayStyle: isDark
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark,
              toolbarHeight: kToolbarHeight,
              // ✅ The blur is painted across statusBar + toolbar + filter bar,
              // which is what actually eliminates the clipping artifact.
              flexibleSpace: _BlurBackdrop(
                isDark: isDark,
                height: topInset + kToolbarHeight + _filterBarHeight,
              ),
              leading: IconButton(
                tooltip: 'Back',
                icon: Icon(
                  Icons.arrow_back_ios_new_rounded,
                  size: 20,
                  color: isDark ? Colors.white : VeilBrand.veilInk,
                ),
                onPressed: () => Navigator.maybePop(context),
              ),
              titleSpacing: 0,
              title: Text(
                'Call History',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.3,
                  color: isDark ? Colors.white : VeilBrand.veilInk,
                ),
              ),
              actions: [
                if (_allCalls.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear history',
                    icon: Icon(
                      Icons.delete_sweep_rounded,
                      size: 22,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    onPressed: _clearHistory,
                  ),
                const SizedBox(width: 4),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(_filterBarHeight),
                child: _FilterBar(
                  height: _filterBarHeight,
                  labels: _filterLabels,
                  counts: [
                    for (final f in _filters) _countFor(f),
                  ],
                  selected: _index,
                  accent: accent,
                  isDark: isDark,
                  onSelect: (i) {
                    HapticFeedback.selectionClick();
                    _tabController.animateTo(i);
                    setState(() => _index = i);
                  },
                ),
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            for (final f in _filters)
              _CallListView(
                key: PageStorageKey<String>('calls_$f'),
                filter: f,
                calls: _callsFor(f),
                isLoading: _isLoading,
                isDark: isDark,
                accent: accent,
                onRefresh: _loadCallLogs,
                onDelete: _deleteCall,
                onCallBack: _placeCall,
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Header backdrop
// ─────────────────────────────────────────────────────────────

/// Blur + gradient scrim that spans the full header, **including** the status
/// bar. Sized explicitly so it never clips at the safe-area boundary.
class _BlurBackdrop extends StatelessWidget {
  final bool isDark;
  final double height;

  const _BlurBackdrop({required this.isDark, required this.height});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          height: height,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [
                      VeilBrand.veilVoid.withValues(alpha: 0.92),
                      VeilBrand.veilInk.withValues(alpha: 0.72),
                    ]
                  : [
                      Colors.white.withValues(alpha: 0.94),
                      Colors.white.withValues(alpha: 0.74),
                    ],
            ),
            border: Border(
              bottom: BorderSide(
                color: (isDark ? Colors.white : Colors.black)
                    .withValues(alpha: 0.07),
                width: 0.6,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Filter bar
// ─────────────────────────────────────────────────────────────

/// Horizontally scrollable pill filter bar.
///
/// ✅ RenderFlex fix: the row is wrapped in a horizontal [ListView] so four
/// chips + count badges can never overflow on narrow devices (the old fixed
/// [TabBar] overflowed at ≤340dp and in landscape).
class _FilterBar extends StatelessWidget {
  final double height;
  final List<String> labels;
  final List<int> counts;
  final int selected;
  final Color accent;
  final bool isDark;
  final ValueChanged<int> onSelect;

  const _FilterBar({
    required this.height,
    required this.labels,
    required this.counts,
    required this.selected,
    required this.accent,
    required this.isDark,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final isSelected = i == selected;
          return VeilTapScale(
            onTap: () => onSelect(i),
            child: AnimatedContainer(
              duration: VeilBrand.normal,
              curve: VeilBrand.smooth,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: isSelected
                    ? accent.withValues(alpha: isDark ? 0.20 : 0.14)
                    : (isDark ? Colors.white : Colors.black)
                        .withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(VeilBrand.rMd),
                border: Border.all(
                  color: isSelected
                      ? accent.withValues(alpha: 0.65)
                      : Colors.transparent,
                  width: 1.2,
                ),
                boxShadow: isSelected
                    ? VeilBrand.glow(accent, blur: 14)
                    : const <BoxShadow>[],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    labels[i],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: isSelected
                          ? accent
                          : (isDark ? Colors.white60 : Colors.black54),
                    ),
                  ),
                  if (counts[i] > 0) ...[
                    const SizedBox(width: 6),
                    AnimatedContainer(
                      duration: VeilBrand.fast,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? accent.withValues(alpha: 0.25)
                            : (isDark ? Colors.white : Colors.black)
                                .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${counts[i]}',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          color: isSelected
                              ? accent
                              : (isDark ? Colors.white54 : Colors.black45),
                        ),
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
}

// ─────────────────────────────────────────────────────────────
// List view per tab
// ─────────────────────────────────────────────────────────────

class _CallListView extends StatelessWidget {
  final String filter;
  final List<Map<String, dynamic>> calls;
  final bool isLoading;
  final bool isDark;
  final Color accent;
  final Future<void> Function() onRefresh;
  final Future<void> Function(Map<String, dynamic>) onDelete;
  final void Function(String contact, bool isAudioOnly) onCallBack;

  const _CallListView({
    super.key,
    required this.filter,
    required this.calls,
    required this.isLoading,
    required this.isDark,
    required this.accent,
    required this.onRefresh,
    required this.onDelete,
    required this.onCallBack,
  });

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (context) {
        return RefreshIndicator(
          onRefresh: onRefresh,
          color: accent,
          backgroundColor: isDark ? VeilBrand.veilSlate : Colors.white,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              // ✅ Injects the exact overlap consumed by the pinned header, so
              // the first row starts *below* it instead of under it.
              SliverOverlapInjector(
                handle:
                    NestedScrollView.sliverOverlapAbsorberHandleFor(context),
              ),

              if (isLoading)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: CircularProgressIndicator(color: accent),
                  ),
                )
              else if (calls.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyState(filter: filter, isDark: isDark),
                )
              else
                ..._buildGroupedSlivers(context),

              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          ),
        );
      },
    );
  }

  /// Groups the calls into Today / Yesterday / explicit dates and emits a
  /// sticky-ish section header before each block.
  List<Widget> _buildGroupedSlivers(BuildContext context) {
    final Map<String, List<Map<String, dynamic>>> buckets = {};
    for (final call in calls) {
      buckets.putIfAbsent(_bucketLabel(call), () => []).add(call);
    }

    final slivers = <Widget>[];
    buckets.forEach((label, rows) {
      slivers.add(
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
            child: Text(
              label.toUpperCase(),
              style: VeilBrand.sectionLabel(isDark, accent),
            ),
          ),
        ),
      );
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          sliver: SliverList.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _CallTile(
              call: rows[i],
              isDark: isDark,
              accent: accent,
              onDelete: () => onDelete(rows[i]),
              onCallBack: onCallBack,
            ),
          ),
        ),
      );
    });
    return slivers;
  }

  String _bucketLabel(Map<String, dynamic> call) {
    final ts = (call['startTime'] as num?)?.toInt() ?? 0;
    if (ts <= 0) return 'Earlier';
    final date = DateTime.fromMillisecondsSinceEpoch(ts);
    final now = DateTime.now();
    final d0 = DateTime(date.year, date.month, date.day);
    final n0 = DateTime(now.year, now.month, now.day);
    final diff = n0.difference(d0).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return DateFormat('EEEE').format(date);
    return DateFormat('MMMM d, yyyy').format(date);
  }
}

// ─────────────────────────────────────────────────────────────
// Row
// ─────────────────────────────────────────────────────────────

class _CallTile extends StatelessWidget {
  final Map<String, dynamic> call;
  final bool isDark;
  final Color accent;
  final VoidCallback onDelete;
  final void Function(String contact, bool isAudioOnly) onCallBack;

  const _CallTile({
    required this.call,
    required this.isDark,
    required this.accent,
    required this.onDelete,
    required this.onCallBack,
  });

  static String _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return '--:--';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    final mm = m.toString().padLeft(2, '0');
    final ss = s.toString().padLeft(2, '0');
    return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
  }

  @override
  Widget build(BuildContext context) {
    final status = call['status']?.toString() ?? '';
    final isMissed = status == 'missed';
    final isDeclined = status == 'declined';
    final isIncoming = (call['direction']?.toString() ?? '') == 'incoming';
    final isAudio = (call['callType']?.toString() ?? '') == 'audio';
    final contact = call['contact']?.toString() ?? 'Unknown';
    final ts = (call['startTime'] as num?)?.toInt() ?? 0;
    final duration = (call['duration'] as num?)?.toInt();

    final timeStr = ts > 0
        ? DateFormat('hh:mm a').format(DateTime.fromMillisecondsSinceEpoch(ts))
        : '--:--';

    final Color statusColor = isMissed
        ? VeilBrand.danger
        : isDeclined
            ? VeilBrand.warning
            : accent;

    final IconData directionIcon = isMissed
        ? (isIncoming ? Icons.call_missed_rounded : Icons.call_missed_outgoing_rounded)
        : (isIncoming ? Icons.call_received_rounded : Icons.call_made_rounded);

    return Dismissible(
      key: ValueKey('call_${call['id'] ?? '${contact}_$ts'}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: VeilBrand.danger.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(VeilBrand.rLg),
        ),
        child: const Icon(Icons.delete_rounded, color: VeilBrand.danger),
      ),
      confirmDismiss: (_) async {
        HapticFeedback.mediumImpact();
        return true;
      },
      onDismissed: (_) => onDelete(),
      child: VeilTapScale(
        onTap: () => onCallBack(contact, isAudio),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: VeilTheme.ultraGlass(
            isDark: isDark,
            radius: VeilBrand.rLg,
          ),
          child: Row(
            children: [
              // Avatar / type badge
              Hero(
                tag: 'call_avatar_$contact$ts',
                child: Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        statusColor.withValues(alpha: 0.26),
                        statusColor.withValues(alpha: 0.08),
                      ],
                    ),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Icon(
                    isAudio ? Icons.call_rounded : Icons.videocam_rounded,
                    size: 21,
                    color: statusColor,
                  ),
                ),
              ),
              const SizedBox(width: 13),

              // ✅ RenderFlex fix: the flexible middle column absorbs all
              // remaining width; long usernames now ellipsize instead of
              // overflowing (the old ListTile subtitle Row was unbounded).
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      contact,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                        color: isMissed
                            ? VeilBrand.danger
                            : (isDark ? Colors.white : VeilBrand.veilInk),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          directionIcon,
                          size: 13,
                          color: isMissed
                              ? VeilBrand.danger
                              : (isIncoming
                                  ? VeilBrand.success
                                  : VeilBrand.info),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            _subtitleFor(status, isIncoming),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              color:
                                  isDark ? Colors.white54 : Colors.black45,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '·',
                          style: TextStyle(
                            color: isDark ? Colors.white24 : Colors.black26,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          timeStr,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isDark ? Colors.white38 : Colors.black38,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // Trailing: duration + call-back button (fixed intrinsic width)
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (status == 'completed')
                    Text(
                      _formatDuration(duration),
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: isDark ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  const SizedBox(height: 4),
                  VeilTapScale(
                    pressedScale: 0.88,
                    onTap: () => onCallBack(contact, isAudio),
                    child: Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        isAudio ? Icons.call_rounded : Icons.videocam_rounded,
                        size: 17,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitleFor(String status, bool isIncoming) {
    switch (status) {
      case 'missed':
        return isIncoming ? 'Missed' : 'No answer';
      case 'declined':
        return isIncoming ? 'Declined' : 'Rejected';
      default:
        return isIncoming ? 'Incoming' : 'Outgoing';
    }
  }
}

// ─────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final String filter;
  final bool isDark;

  const _EmptyState({required this.filter, required this.isDark});

  (String, String, IconData) get _copy => switch (filter) {
        'audio' => (
            'No Audio Calls',
            'Your encrypted voice calls will appear here',
            Icons.call_rounded,
          ),
        'video' => (
            'No Video Calls',
            'Your encrypted video calls will appear here',
            Icons.videocam_rounded,
          ),
        'missed' => (
            'No Missed Calls',
            'You are all caught up',
            Icons.call_missed_rounded,
          ),
        _ => (
            'No Call History',
            'Calls you make or receive will appear here',
            Icons.history_rounded,
          ),
      };

  @override
  Widget build(BuildContext context) {
    final (title, subtitle, icon) = _copy;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              duration: VeilBrand.slow,
              curve: VeilBrand.springIn,
              tween: Tween(begin: 0.8, end: 1),
              builder: (_, s, child) => Transform.scale(scale: s, child: child),
              child: Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      VeilBrand.veilIndigo.withValues(alpha: 0.14),
                      VeilBrand.veilTeal.withValues(alpha: 0.06),
                    ],
                  ),
                ),
                child: Icon(
                  icon,
                  size: 44,
                  color: isDark ? Colors.white24 : Colors.black26,
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white70 : Colors.black54,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: isDark ? Colors.white30 : Colors.black38,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
