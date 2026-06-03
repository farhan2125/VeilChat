import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:flutter/foundation.dart';

/// Service for voice recording and playback.
class SoundService {
  static final SoundService _instance = SoundService._internal();
  factory SoundService() => _instance;
  SoundService._internal();

  final AudioPlayer _audioPlayer = AudioPlayer();
  final Record _audioRecorder = Record();

  String? _currentRecordingPath;
  bool _isRecording = false;
  Timer? _recordingTimer;
  int _recordingSeconds = 0;

  final StreamController<int> _recordingTimeController = StreamController<int>.broadcast();
  final StreamController<PlayerState> _playerStateController = StreamController<PlayerState>.broadcast();
  final StreamController<Duration> _playerPositionController = StreamController<Duration>.broadcast();
  final StreamController<Duration> _playerDurationController = StreamController<Duration>.broadcast();

  Stream<int> get recordingTimeStream => _recordingTimeController.stream;
  Stream<PlayerState> get playerStateStream => _playerStateController.stream;
  Stream<Duration> get playerPositionStream => _playerPositionController.stream;
  Stream<Duration> get playerDurationStream => _playerDurationController.stream;

  bool get isRecording => _isRecording;
  int get recordingDuration => _recordingSeconds;

  Future<bool> checkAndRequestPermission() async {
    final status = await Permission.microphone.request();
    return status == PermissionStatus.granted;
  }

  Future<bool> startRecording() async {
    try {
      if (!await checkAndRequestPermission()) return false;
      final tempDir = await getTemporaryDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentRecordingPath = '${tempDir.path}/recording_$timestamp.m4a';
      await _audioRecorder.start(
        path: _currentRecordingPath,
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        samplingRate: 44100,
      );
      _isRecording = true;
      _recordingSeconds = 0;
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        _recordingSeconds++;
        _recordingTimeController.add(_recordingSeconds);
      });
      return true;
    } catch (e) {
      debugPrint('❌ Start recording error: $e');
      return false;
    }
  }

  Future<String?> stopRecording() async {
    try {
      _recordingTimer?.cancel();
      _recordingTimer = null;
      if (_isRecording && _currentRecordingPath != null) {
        await _audioRecorder.stop();
        _isRecording = false;
        if (_recordingSeconds < 1) {
          final file = File(_currentRecordingPath!);
          if (await file.exists()) await file.delete();
          return null;
        }
        return _currentRecordingPath;
      }
      return null;
    } catch (e) {
      debugPrint('❌ Stop recording error: $e');
      return null;
    }
  }

  Future<void> cancelRecording() async {
    try {
      _recordingTimer?.cancel();
      _recordingTimer = null;
      if (_isRecording) {
        await _audioRecorder.stop();
        _isRecording = false;
        if (_currentRecordingPath != null) {
          final file = File(_currentRecordingPath!);
          if (await file.exists()) await file.delete();
        }
      }
    } catch (e) {
      debugPrint('❌ Cancel recording error: $e');
    }
  }

  Future<void> playAudio(String filePath, {bool isAsset = false}) async {
    try {
      await _audioPlayer.stop();
      _audioPlayer.onPlayerStateChanged.listen((state) => _playerStateController.add(state));
      _audioPlayer.onPositionChanged.listen((pos) => _playerPositionController.add(pos));
      _audioPlayer.onDurationChanged.listen((dur) => _playerDurationController.add(dur));
      if (isAsset) {
        await _audioPlayer.play(AssetSource(filePath));
      } else {
        await _audioPlayer.play(DeviceFileSource(filePath));
      }
    } catch (e) {
      debugPrint('❌ Play audio error: $e');
      rethrow;
    }
  }

  Future<void> pauseAudio() async => await _audioPlayer.pause();
  Future<void> resumeAudio() async => await _audioPlayer.resume();
  Future<void> stopAudio() async => await _audioPlayer.stop();
  Future<void> seekAudio(Duration position) async => await _audioPlayer.seek(position);

  String formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<String> convertFileToBase64(String filePath) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      return base64Encode(bytes);
    } catch (e) {
      debugPrint('❌ File to base64 error: $e');
      return '';
    }
  }

  Future<String> saveBase64ToFile(String base64String, String fileName) async {
    try {
      final bytes = base64Decode(base64String);
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/veil_chat_files/$fileName');
      await file.create(recursive: true);
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (e) {
      debugPrint('❌ Save base64 to file error: $e');
      rethrow;
    }
  }

  Future<void> dispose() async {
    _recordingTimer?.cancel();
    if (_isRecording) await _audioRecorder.stop();
    await _audioRecorder.dispose();
    await _audioPlayer.dispose();
    await _recordingTimeController.close();
    await _playerStateController.close();
    await _playerPositionController.close();
    await _playerDurationController.close();
  }
}