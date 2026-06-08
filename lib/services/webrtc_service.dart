import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'network_service.dart';

typedef StreamStateCallback = void Function(MediaStream stream);
typedef IceConnectionStateCallback = void Function(RTCIceConnectionState state);
typedef SendIceCandidateCallback = void Function(RTCIceCandidate candidate, String contactName);

class WebRTCService {
  // ✅ BUG FIX #1: REMOVED singleton pattern.
  // The singleton was the ROOT CAUSE of calls failing:
  // After call #1 ended, dispose() set _peerConnection=null.
  // Call #2 got the SAME instance — init() created a new peerConnection,
  // but the OLD ICE state callbacks from the closed connection still fired
  // through the singleton, immediately triggering _handleEndCall on the new call.
  WebRTCService();

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  bool _disposed = false;
  bool _isAudioOnly = false;

  StreamStateCallback? onLocalStream;
  StreamStateCallback? onRemoteStream;
  IceConnectionStateCallback? onIceConnectionState;
  SendIceCandidateCallback? sendIceCandidate;

  String? _currentContactName;

  final Map<String, dynamic> _iceConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      // Free TURN servers for NAT traversal (required for calls across different networks)
      {
        'urls': 'turn:openrelay.metered.ca:80',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turn:openrelay.metered.ca:443',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turns:openrelay.metered.ca:443?transport=tcp',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
    'iceCandidatePoolSize': 10,
  };

  Future<void> init({required bool isAudioOnly}) async {
    if (_disposed) return;
    _isAudioOnly = isAudioOnly;
    try {
      // ✅ BUG FIX #2: video: false for audio-only calls.
      // Before: _constraints hardcoded OfferToReceiveVideo: true for ALL calls.
      // That's why pressing voice call icon opened the camera anyway.
      _localStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': true,
          'autoGainControl': true,
        },
        'video': isAudioOnly
            ? false
            : {
                'facingMode': 'user',
                'width': {'ideal': 640},
                'height': {'ideal': 480},
              },
      });
      onLocalStream?.call(_localStream!);

      _peerConnection = await createPeerConnection(_iceConfig, {});

      for (final track in _localStream!.getTracks()) {
        await _peerConnection!.addTrack(track, _localStream!);
      }

      _peerConnection!.onTrack = (RTCTrackEvent event) {
        if (_disposed) return;
        if (event.streams.isNotEmpty) {
          onRemoteStream?.call(event.streams[0]);
        }
      };

      _peerConnection!.onIceCandidate = (candidate) {
        if (_disposed) return;
        if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
          if (_currentContactName != null) {
            sendIceCandidate?.call(candidate, _currentContactName!);
          }
        }
      };

      _peerConnection!.onIceConnectionState = (state) {
        if (_disposed) return;
        debugPrint('ICE state: $state');
        onIceConnectionState?.call(state);
      };
    } catch (e) {
      debugPrint('❌ WebRTC init error: $e');
      rethrow;
    }
  }

  Future<void> createOffer(String contactName) async {
    if (_disposed || _peerConnection == null) return;
    _currentContactName = contactName;
    // ✅ Offer constraints match call type
    final constraints = {
      'mandatory': {
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': !_isAudioOnly,
      },
      'optional': [],
    };
    final offer = await _peerConnection!.createOffer(constraints);
    await _peerConnection!.setLocalDescription(offer);
    NetworkService().sendCallSignal(contactName, 'OFFER', {
      'sdp': offer.sdp,
      'type': offer.type,
    });
    debugPrint('📞 Sent OFFER to $contactName');
  }

  Future<void> createAnswer(String contactName) async {
    if (_disposed || _peerConnection == null) return;
    _currentContactName = contactName;
    // ✅ Answer constraints match call type
    final constraints = {
      'mandatory': {
        'OfferToReceiveAudio': true,
        'OfferToReceiveVideo': !_isAudioOnly,
      },
      'optional': [],
    };
    final answer = await _peerConnection!.createAnswer(constraints);
    await _peerConnection!.setLocalDescription(answer);
    NetworkService().sendCallSignal(contactName, 'ANSWER', {
      'sdp': answer.sdp,
      'type': answer.type,
    });
    debugPrint('📞 Sent ANSWER to $contactName');
  }

  Future<void> setRemoteDescription(String sdp, String type) async {
    if (_disposed || _peerConnection == null) return;
    await _peerConnection!.setRemoteDescription(RTCSessionDescription(sdp, type));
  }

  Future<void> addCandidate(Map<String, dynamic> candidateMap) async {
    if (_disposed || _peerConnection == null) return;
    try {
      await _peerConnection!.addCandidate(RTCIceCandidate(
        candidateMap['candidate'],
        candidateMap['sdpMid'],
        candidateMap['sdpMLineIndex'],
      ));
    } catch (e) {
      debugPrint('❌ addCandidate error: $e');
    }
  }

  void toggleMic() {
    final tracks = _localStream?.getAudioTracks() ?? [];
    if (tracks.isNotEmpty) tracks[0].enabled = !tracks[0].enabled;
  }

  void toggleCamera() {
    final tracks = _localStream?.getVideoTracks() ?? [];
    if (tracks.isNotEmpty) tracks[0].enabled = !tracks[0].enabled;
  }

  void switchCamera() {
    final tracks = _localStream?.getVideoTracks() ?? [];
    if (tracks.isNotEmpty) Helper.switchCamera(tracks[0]);
  }

  /// Route call audio to the loudspeaker (true) or the phone earpiece (false).
  /// Using the earpiece for audio-only calls greatly reduces the
  /// "I can hear my own voice" echo caused by the mic picking up the speaker.
  Future<void> setSpeakerphone(bool enabled) async {
    try {
      await Helper.setSpeakerphoneOn(enabled);
    } catch (e) {
      debugPrint('❌ setSpeakerphone error: $e');
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _currentContactName = null;
    onLocalStream = null;
    onRemoteStream = null;
    onIceConnectionState = null;
    sendIceCandidate = null;
    try {
      _localStream?.getTracks().forEach((t) {
        t.stop();
        t.dispose();
      });
      _localStream?.dispose();
      _localStream = null;
      _peerConnection?.close();
      _peerConnection = null;
    } catch (e) {
      debugPrint('❌ WebRTC dispose error: $e');
    }
  }
}
