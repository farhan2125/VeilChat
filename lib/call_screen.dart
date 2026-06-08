import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import 'veil_theme.dart';
import 'services/network_service.dart';
import 'services/webrtc_service.dart';
import 'services/database_service.dart';

class CallScreen extends StatefulWidget {
  final String contactName;
  final bool isIncoming;
  final bool isDark;
  final bool isAudioOnly;
  final Map<dynamic, dynamic>? initialOffer;

  const CallScreen({
    super.key,
    required this.contactName,
    required this.isIncoming,
    required this.isDark,
    this.isAudioOnly = false,
    this.initialOffer,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen>
    with SingleTickerProviderStateMixin {
  final _localRenderer  = RTCVideoRenderer();
  final _remoteRenderer = RTCVideoRenderer();

  // ✅ BUG FIX #1: Fresh instance per call (NOT singleton)
  final _webrtc = WebRTCService();
  final _db     = DatabaseService();

  late AnimationController _pulseController;
  late Animation<double>   _pulseAnimation;
  StreamSubscription? _callSubscription;

  String _callStatus  = 'Initializing...';
  bool _isMuted       = false;
  bool _isCameraOff   = false;
  bool _isSpeakerOn   = false; // audio output: false = earpiece, true = loudspeaker
  bool _isDisposed    = false;
  bool _callEnding    = false;
  bool _offerSent     = false; // ✅ guard against double createOffer
  // ✅ FIX: incoming call must not show "Connected" until user presses Accept
  bool _userAccepted  = false;

  int?  _callStartTime;
  bool  _wasConnected = false;

  // ✅ BUG FIX #3: debounce timer — don't end call on transient ICE states
  Timer? _iceFailTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
        vsync: this, duration: const Duration(seconds: 2))
      ..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut));
    _callStartTime = DateTime.now().millisecondsSinceEpoch;
    _initCall();
  }

  Future<bool> _ensureCallPermissions() async {
    final statuses = await [
      Permission.microphone,
      if (!widget.isAudioOnly) Permission.camera,
    ].request();
    return statuses.values.every((s) => s.isGranted);
  }

  Future<void> _initCall() async {
    try {
      final granted = await _ensureCallPermissions();
      if (!granted) {
        if (mounted && !_isDisposed) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(widget.isAudioOnly
                ? 'Microphone permission is required for calls'
                : 'Camera and microphone permissions are required for video calls')),
          );
          Navigator.pop(context);
        }
        return;
      }

      await _localRenderer.initialize();
      await _remoteRenderer.initialize();

      _webrtc.onLocalStream = (stream) {
        if (mounted && !_isDisposed) {
          setState(() => _localRenderer.srcObject = stream);
        }
      };

      _webrtc.onRemoteStream = (stream) {
        if (mounted && !_isDisposed) {
          // ✅ FIX: Only show connected if user accepted (for incoming) or outgoing call
          if (!widget.isIncoming || _userAccepted) {
            setState(() {
              _remoteRenderer.srcObject = stream;
              _callStatus  = 'Connected';
              _wasConnected = true;
            });
            _iceFailTimer?.cancel();
            _pulseController.stop();
          } else {
            // Store stream for when user accepts
            _remoteRenderer.srcObject = stream;
          }
        }
      };

      // ✅ BUG FIX #3: Smart ICE state handling
      // OLD CODE killed the call on Disconnected/Closed — these are NORMAL
      // transient states during NAT traversal and WebRTC setup.
      // Disconnected = temporary network blip (often self-heals)
      // Closed = fires when we call peerConnection.close() on dispose — causing
      //          _handleEndCall to be called AGAIN after dispose = infinite loop
      // Failed = the only state that means the call truly cannot connect
      _webrtc.onIceConnectionState = (state) {
        if (_isDisposed || _callEnding) return;

        if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
            state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
          _iceFailTimer?.cancel();
          if (mounted && !_wasConnected) {
            setState(() => _callStatus = 'Connected');
            _wasConnected = true;
            _pulseController.stop();
          }
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
          // Give 3s for ICE restart before giving up
          _iceFailTimer?.cancel();
          _iceFailTimer = Timer(const Duration(seconds: 3), () {
            if (!_isDisposed && !_callEnding) {
              if (mounted) setState(() => _callStatus = 'Connection failed');
              _handleEndCall(isRemote: true);
            }
          });
        } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
          // Transient — show status but don't end call
          if (mounted && _wasConnected) {
            setState(() => _callStatus = 'Reconnecting...');
          }
          // Give 10s to reconnect before ending
          _iceFailTimer?.cancel();
          _iceFailTimer = Timer(const Duration(seconds: 10), () {
            if (!_isDisposed && !_callEnding && !_wasConnected) {
              _handleEndCall(isRemote: true);
            }
          });
        }
        // RTCIceConnectionStateClosed: do NOT handle here — fires during dispose
      };

      // ✅ BUG FIX #4: Set sendIceCandidate BEFORE init() so no candidates are lost
      _webrtc.sendIceCandidate = (candidate, _) => _onIceCandidate(candidate);

      await _webrtc.init(isAudioOnly: widget.isAudioOnly);

      // Default audio routing: earpiece for voice calls (prevents the
      // loudspeaker echo where you hear your own voice), speaker for video.
      _isSpeakerOn = !widget.isAudioOnly;
      await _webrtc.setSpeakerphone(_isSpeakerOn);
      if (mounted) setState(() {});

      _setupSignalListener();

      if (widget.isIncoming) {
        setState(() => _callStatus =
            'Incoming ${widget.isAudioOnly ? 'Audio' : 'Video'} Call...');
        if (widget.initialOffer != null) {
          final sdp   = widget.initialOffer!['sdp']?.toString();
          final type2 = widget.initialOffer!['type']?.toString();
          if (sdp != null && type2 != null) {
            try {
              await _webrtc.setRemoteDescription(sdp, type2);
            } catch (e) {
              debugPrint('❌ setRemoteDescription error: $e');
            }
          }
        }
      } else {
        setState(() => _callStatus = 'Calling ${widget.contactName}...');
        if (!_offerSent) {
          _offerSent = true;
          await _webrtc.createOffer(widget.contactName);
        }
      }
    } catch (e) {
      debugPrint('❌ _initCall error: $e');
      if (mounted && !_isDisposed) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Call failed: $e')));
        Navigator.pop(context);
      }
    }
  }

  void _setupSignalListener() {
    _callSubscription = NetworkService().callStream.listen((data) async {
      if (!mounted || _isDisposed || _callEnding) return;
      if (data['sender'] != widget.contactName) return;

      switch (data['type']) {
        case 'OFFER':
          // Already handled via initialOffer — skip
          break;

        case 'ANSWER':
          // ✅ BUG FIX #5: null-safe data access (was crashing if data['data'] null)
          final answerData = data['data'];
          if (answerData == null) break;
          final sdp  = answerData['sdp']?.toString();
          final type = answerData['type']?.toString();
          if (sdp != null && type != null) {
            try {
              await _webrtc.setRemoteDescription(sdp, type);
              if (mounted) setState(() => _callStatus = 'Connecting...');
            } catch (e) {
              debugPrint('❌ setRemoteDescription error: $e');
            }
          }
          break;

        case 'ICE':
          final iceData = data['data'];
          if (iceData != null) {
            try {
              await _webrtc.addCandidate(Map<String, dynamic>.from(iceData));
            } catch (e) {
              debugPrint('❌ addCandidate error: $e');
            }
          }
          break;

        case 'END':
          _handleEndCall(isRemote: true);
          break;
      }
    });
  }

  // Removed didChangeDependencies for sendIceCandidate — now set in _initCall before init()

  void _onIceCandidate(RTCIceCandidate candidate) {
    if (_isDisposed || _callEnding) return;
    NetworkService().sendCallSignal(widget.contactName, 'ICE', {
      'candidate':     candidate.candidate,
      'sdpMid':        candidate.sdpMid,
      'sdpMLineIndex': candidate.sdpMLineIndex,
    });
    debugPrint('📞 Sent ICE to ${widget.contactName}');
  }

  void _acceptCall() async {
    if (_isDisposed) return;
    // ✅ FIX: Mark user as having accepted so remote stream can show
    _userAccepted = true;
    setState(() => _callStatus = 'Connecting...');
    // If remote stream already arrived, show it now
    if (_remoteRenderer.srcObject != null) {
      setState(() {
        _callStatus = 'Connected';
        _wasConnected = true;
      });
      _pulseController.stop();
    }
    try {
      await _webrtc.createAnswer(widget.contactName);
    } catch (e) {
      debugPrint('❌ Accept error: $e');
    }
  }

  void _handleEndCall({bool isRemote = false}) async {
    // ✅ BUG FIX #6: Guard against double-end
    if (_callEnding || _isDisposed) return;
    _callEnding = true;
    _iceFailTimer?.cancel();

    // ✅ BUG FIX #7: Send END signal whenever WE hang up (incoming OR outgoing)
    // OLD CODE only sent END for outgoing calls, so if incoming caller pressed
    // Decline, the other phone kept ringing forever.
    if (!isRemote) {
      NetworkService().sendCallSignal(widget.contactName, 'END', {});
      debugPrint('📞 Sent END to ${widget.contactName}');
    }

    await _saveCallLog();
    _disposeCall();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _saveCallLog() async {
    try {
      final owner = NetworkService().currentUser;
      if (owner == null) return;
      final endTime  = DateTime.now().millisecondsSinceEpoch;
      final start    = _callStartTime ?? endTime;
      final duration = _wasConnected ? ((endTime - start) ~/ 1000) : null;
      await _db.saveCallLog(
        owner:     owner,
        contact:   widget.contactName,
        callType:  widget.isAudioOnly ? 'audio' : 'video',
        direction: widget.isIncoming  ? 'incoming' : 'outgoing',
        startTime: start,
        endTime:   endTime,
        duration:  duration,
        status:    _wasConnected ? 'completed' : 'missed',
      );
    } catch (e) {
      debugPrint('❌ saveCallLog error: $e');
    }
  }

  void _disposeCall() {
    if (_isDisposed) return;
    _isDisposed = true;
    _iceFailTimer?.cancel();
    _callSubscription?.cancel();
    try {
      if (_pulseController.isAnimating) _pulseController.stop();
      _pulseController.dispose();
    } catch (_) {}
    _webrtc.dispose();
    // ✅ FIX: Set srcObject to null BEFORE dispose to prevent Surface.release NPE on Android 8
    try { _localRenderer.srcObject  = null; } catch (_) {}
    try { _remoteRenderer.srcObject = null; } catch (_) {}
    // Delay dispose to let Flutter finish rendering cycle
    Future.delayed(const Duration(milliseconds: 300), () {
      try { _localRenderer.dispose(); } catch (_) {}
      try { _remoteRenderer.dispose(); } catch (_) {}
    });
  }

  void _toggleMute() {
    if (_isDisposed) return;
    _webrtc.toggleMic();
    setState(() => _isMuted = !_isMuted);
  }

  void _toggleCamera() {
    if (_isDisposed || widget.isAudioOnly) return;
    _webrtc.toggleCamera();
    setState(() => _isCameraOff = !_isCameraOff);
  }

  void _switchCamera() {
    if (_isDisposed || widget.isAudioOnly) return;
    _webrtc.switchCamera();
  }

  void _toggleSpeaker() async {
    if (_isDisposed) return;
    _isSpeakerOn = !_isSpeakerOn;
    await _webrtc.setSpeakerphone(_isSpeakerOn);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _disposeCall();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
        if (didPop && !_callEnding) _handleEndCall();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        backgroundColor: Colors.black,
        body: Stack(
          fit: StackFit.expand,
          children: [
            _buildBackground(),
            if (widget.isAudioOnly)
              _buildAudioCallUI()
            else
              _buildVideoCallUI(),
            _buildControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildBackground() {
    // ✅ BUG FIX #9: Don't load bg image asset — use gradient instead
    // (the bg_dark.jpg asset path can cause crash if asset missing)
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: widget.isDark
              ? [const Color(0xFF0D1117), const Color(0xFF1A1F2E)]
              : [const Color(0xFF1A237E), const Color(0xFF0D1117)],
        ),
      ),
    );
  }

  Widget _buildAudioCallUI() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const SizedBox(height: 80),
      ScaleTransition(
        scale: _wasConnected
            ? const AlwaysStoppedAnimation(1.0)
            : _pulseAnimation,
        child: _buildAvatar()),
      const SizedBox(height: 24),
      Text(widget.contactName,
        style: const TextStyle(
            fontSize: 30, color: Colors.white, fontWeight: FontWeight.bold)),
      const SizedBox(height: 10),
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
          widget.isAudioOnly ? Icons.mic : Icons.videocam,
          color: Colors.white54, size: 14),
        const SizedBox(width: 4),
        Text(
          widget.isAudioOnly ? 'Audio Call' : 'Video Call',
          style: const TextStyle(color: Colors.white54, fontSize: 13)),
      ]),
      const SizedBox(height: 6),
      // ✅ FIX: Only show status if not yet connected (avoid "Connected Connected")
      if (!_wasConnected)
        Text(_callStatus,
          style: const TextStyle(
              fontSize: 15,
              color: Colors.white70,
              letterSpacing: 1.2))
      else
        Text('Connected',
          style: const TextStyle(
              fontSize: 15,
              color: Colors.greenAccent,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2)),
    ]),
  );

  Widget _buildVideoCallUI() => Stack(children: [
    Positioned.fill(
      child: _remoteRenderer.srcObject != null
          ? RTCVideoView(_remoteRenderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
          : _buildAudioCallUI(),
    ),
    if (_localRenderer.srcObject != null && !_isCameraOff)
      Positioned(
        right: 16, top: 60, width: 96, height: 144,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white70, width: 1.5),
              borderRadius: BorderRadius.circular(12)),
            child: RTCVideoView(_localRenderer,
              mirror: true,
              objectFit:
                  RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)))),
  ]);

  Widget _buildAvatar() => Container(
    padding: const EdgeInsets.all(4),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(
        color: _wasConnected ? Colors.greenAccent : Colors.blueAccent,
        width: 2.5),
      boxShadow: [BoxShadow(
        color: (_wasConnected ? Colors.greenAccent : Colors.blueAccent)
            .withOpacity(0.35),
        blurRadius: 50, spreadRadius: 2)]),
    child: CircleAvatar(
      radius: 62,
      backgroundColor: Colors.blueGrey[900],
      child: Text(
        widget.contactName[0].toUpperCase(),
        style: const TextStyle(
            fontSize: 48, color: Colors.white, fontWeight: FontWeight.bold))));

  Widget _buildControls() => Positioned(
    bottom: 48, left: 20, right: 20,
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      if (_wasConnected)
        Text(_callStatus,
          style: const TextStyle(color: Colors.greenAccent, fontSize: 13)),
      const SizedBox(height: 16),
      if (widget.isIncoming && !_wasConnected)
        _buildIncomingActions()
      else
        _buildActiveActions(),
    ]));

  Widget _buildIncomingActions() => Row(
    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
    children: [
      Column(mainAxisSize: MainAxisSize.min, children: [
        _circleBtn(Icons.call_end, Colors.red, () => _handleEndCall()),
        const SizedBox(height: 6),
        const Text('Decline',
          style: TextStyle(color: Colors.white70, fontSize: 12)),
      ]),
      Column(mainAxisSize: MainAxisSize.min, children: [
        _pulseButton(Icons.call, Colors.green, _acceptCall),
        const SizedBox(height: 6),
        const Text('Accept',
          style: TextStyle(color: Colors.white70, fontSize: 12)),
      ]),
    ]);

  Widget _buildActiveActions() => Container(
    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.08),
      borderRadius: BorderRadius.circular(32),
      border: Border.all(color: Colors.white12)),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _circleBtn(
          _isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
          _isMuted ? Colors.redAccent : Colors.white,
          _toggleMute),
        _circleBtn(
          _isSpeakerOn ? Icons.volume_up_rounded : Icons.phone_in_talk_rounded,
          _isSpeakerOn ? VeilTheme.accentColor : Colors.white,
          _toggleSpeaker),
        _circleBtn(Icons.call_end_rounded, Colors.red,
          () => _handleEndCall()),
        if (!widget.isAudioOnly) ...[
          _circleBtn(
            _isCameraOff ? Icons.videocam_off_rounded : Icons.videocam_rounded,
            _isCameraOff ? Colors.redAccent : Colors.white,
            _toggleCamera),
          _circleBtn(Icons.cameraswitch_rounded, Colors.white,
            _switchCamera),
        ],
      ]));

  Widget _circleBtn(IconData icon, Color color, VoidCallback onTap) =>
    Material(
      color: color.withOpacity(0.15),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Icon(icon, color: color, size: 28))));

  Widget _pulseButton(IconData icon, Color color, VoidCallback onTap) =>
    ScaleTransition(
      scale: _pulseAnimation,
      child: Material(
        color: color,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: const Padding(
            padding: EdgeInsets.all(16),
            child: Icon(Icons.call, color: Colors.white, size: 32)))));
}
