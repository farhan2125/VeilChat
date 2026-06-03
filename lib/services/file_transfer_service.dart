import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:math';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/foundation.dart';
import 'network_service.dart';

/// Status of a file transfer.
enum TransferStatus {
  pending,
  uploading,
  downloading,
  completed,
  cancelled,
  failed,
}

/// Represents a single file transfer.
class FileTransfer {
  final String id; // Unique ID for this transfer
  final String fileName;
  final String filePath; // Local path
  final int totalBytes;
  final String toUser; // Recipient
  final bool isOutgoing;
  TransferStatus status;
  int bytesTransferred;
  String? error;
  DateTime createdAt;
  DateTime? completedAt;

  FileTransfer({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.totalBytes,
    required this.toUser,
    required this.isOutgoing,
    this.status = TransferStatus.pending,
    this.bytesTransferred = 0,
    this.error,
    DateTime? createdAt,
    this.completedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  double get progress => totalBytes == 0 ? 0 : bytesTransferred / totalBytes;
}

/// Singleton service for handling file transfers.
/// Supports picking files, sending with progress, receiving and saving.
class FileTransferService {
  static final FileTransferService _instance = FileTransferService._internal();
  factory FileTransferService() => _instance;
  FileTransferService._internal();

  // Active transfers (both outgoing and incoming)
  final Map<String, FileTransfer> _transfers = {};

  // Stream controllers
  final _transferController = StreamController<FileTransfer>.broadcast();
  final _progressController = StreamController<FileTransfer>.broadcast();
  final _completeController = StreamController<FileTransfer>.broadcast();
  final _errorController = StreamController<FileTransfer>.broadcast();

  // Subscriptions
  StreamSubscription? _networkProgressSub;

  // Getters
  Stream<FileTransfer> get onTransferUpdate => _transferController.stream;
  Stream<FileTransfer> get onProgress => _progressController.stream;
  Stream<FileTransfer> get onComplete => _completeController.stream;
  Stream<FileTransfer> get onError => _errorController.stream;

  List<FileTransfer> get activeTransfers => _transfers.values.toList();

  // ------------------------------------------------------------------------
  //                           INITIALIZATION
  // ------------------------------------------------------------------------

  /// Initialize the service – listen to network progress events.
  void init() {
    _networkProgressSub ??= NetworkService().fileTransferStream.listen(
      _handleNetworkProgress,
      onError: (e) => debugPrint('❌ File transfer stream error: $e'),
    );
  }

  void _handleNetworkProgress(Map<String, dynamic> data) {
    final fileId = data['file_id'];
    if (fileId == null) return;

    final transfer = _transfers[fileId];
    if (transfer == null) return;

    transfer.bytesTransferred = data['bytes_transferred'] ?? 0;
    transfer.status = TransferStatus.uploading;

    _progressController.add(transfer);
    _transferController.add(transfer);
  }

  // ------------------------------------------------------------------------
  //                           PICKING FILES
  // ------------------------------------------------------------------------

  /// Open file picker for any file type.
  Future<FilePickerResult?> pickFile({
    List<String>? allowedExtensions,
    FileType type = FileType.any,
  }) async {
    try {
      return await FilePicker.platform.pickFiles(
        type: type,
        allowedExtensions: allowedExtensions,
        allowMultiple: false,
      );
    } catch (e) {
      debugPrint('❌ File pick error: $e');
      return null;
    }
  }

  /// Open image picker (gallery).
  Future<FilePickerResult?> pickImage() async {
    return await pickFile(type: FileType.image);
  }

  /// Open video picker.
  Future<FilePickerResult?> pickVideo() async {
    return await pickFile(type: FileType.video);
  }

  /// Open audio picker.
  Future<FilePickerResult?> pickAudio() async {
    return await pickFile(type: FileType.audio);
  }

  // ------------------------------------------------------------------------
  //                           ENCODING
  // ------------------------------------------------------------------------

  /// Encode a PlatformFile to base64 string.
  Future<String> encodeFile(PlatformFile file) async {
    try {
      final bytes = file.bytes ?? await File(file.path!).readAsBytes();
      return base64Encode(bytes);
    } catch (e) {
      debugPrint('❌ File encode error: $e');
      rethrow;
    }
  }

  /// Encode a File object to base64 string.
  Future<String> encodeFileFromPath(String filePath) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      return base64Encode(bytes);
    } catch (e) {
      debugPrint('❌ File encode error: $e');
      rethrow;
    }
  }

  // ------------------------------------------------------------------------
  //                           SENDING
  // ------------------------------------------------------------------------

  /// Send a file to a contact.
  /// Returns the transfer ID if successful, null otherwise.
  Future<String?> sendFile({
    required String toUser,
    required File file,
    String? customFileName,
    String? messageId,
  }) async {
    try {
      if (!await file.exists()) {
        throw Exception('File does not exist');
      }

      final fileName = customFileName ?? file.path.split('/').last;
      final fileSize = await file.length();
      final transferId = _generateTransferId();

      // Create transfer record
      final transfer = FileTransfer(
        id: transferId,
        fileName: fileName,
        filePath: file.path,
        totalBytes: fileSize,
        toUser: toUser,
        isOutgoing: true,
        status: TransferStatus.pending,
      );
      _transfers[transferId] = transfer;
      _transferController.add(transfer);

      // Encode file to base64
      final base64Data = await encodeFileFromPath(file.path);

      // Prepare metadata
      final metadata = {
        'filename': fileName,
        'size': fileSize,
        'mimeType': _getMimeType(fileName),
        'transferId': transferId,
      };

      // Send message via NetworkService
      NetworkService().sendMessage(
        toUser,
        'FILE',
        base64Data,
        metadata: metadata,
        messageId: messageId ?? transferId,
      );

      // Update status
      transfer.status = TransferStatus.uploading;
      _transferController.add(transfer);

      return transferId;
    } catch (e) {
      debugPrint('❌ Send file error: $e');
      return null;
    }
  }

  /// Cancel an ongoing outgoing transfer.
  Future<void> cancelTransfer(String transferId) async {
    final transfer = _transfers[transferId];
    if (transfer == null) return;

    transfer.status = TransferStatus.cancelled;
    transfer.completedAt = DateTime.now();
    _transferController.add(transfer);
    _completeController.add(transfer);
    _transfers.remove(transferId);
  }

  // ------------------------------------------------------------------------
  //                           RECEIVING
  // ------------------------------------------------------------------------

  /// Save a received base64-encoded file to disk.
  /// Returns the local file path.
  Future<String> saveReceivedFile({
    required String base64Data,
    required String fileName,
    required String fromUser,
    String? transferId,
    int? fileSize,
  }) async {
    try {
      final bytes = base64Decode(base64Data);
      final dir = await getApplicationDocumentsDirectory();
      final subDir = Directory('${dir.path}/veil_chat_files');
      if (!await subDir.exists()) await subDir.create(recursive: true);

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final safeFileName = fileName.replaceAll(RegExp(r'[^\w\-_.]'), '_');
      final filePath = '${subDir.path}/${timestamp}_$safeFileName';

      final file = File(filePath);
      await file.writeAsBytes(bytes);

      // Create transfer record for incoming file
      final id = transferId ?? _generateTransferId();
      final transfer = FileTransfer(
        id: id,
        fileName: fileName,
        filePath: filePath,
        totalBytes: fileSize ?? bytes.length,
        toUser: fromUser,
        isOutgoing: false,
        status: TransferStatus.completed,
        bytesTransferred: fileSize ?? bytes.length,
        completedAt: DateTime.now(),
      );
      _transfers[id] = transfer;
      _transferController.add(transfer);
      _completeController.add(transfer);

      debugPrint('💾 Received file saved: $filePath');
      return filePath;
    } catch (e) {
      debugPrint('❌ Save received file error: $e');
      rethrow;
    }
  }

  // ------------------------------------------------------------------------
  //                           UTILITIES
  // ------------------------------------------------------------------------

  /// Get transfer by ID.
  FileTransfer? getTransfer(String id) => _transfers[id];

  /// Remove completed/failed/cancelled transfer from memory.
  void removeTransfer(String id) {
    _transfers.remove(id);
  }

  /// Clear all completed transfers older than [age] (default 1 hour).
  void cleanOldTransfers({Duration age = const Duration(hours: 1)}) {
    final cutoff = DateTime.now().subtract(age);
    _transfers.removeWhere((id, transfer) {
      if (transfer.completedAt != null && transfer.completedAt!.isBefore(cutoff)) {
        return true;
      }
      return false;
    });
  }

  // ------------------------------------------------------------------------
  //                           PRIVATE
  // ------------------------------------------------------------------------

  String _generateTransferId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random.secure().nextInt(10000);
    return '${timestamp}_$random';
  }

  String _getMimeType(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'jpg': case 'jpeg': return 'image/jpeg';
      case 'png': return 'image/png';
      case 'gif': return 'image/gif';
      case 'mp4': return 'video/mp4';
      case 'mp3': return 'audio/mpeg';
      case 'm4a': return 'audio/mp4';
      case 'pdf': return 'application/pdf';
      case 'doc': case 'docx': return 'application/msword';
      case 'xls': case 'xlsx': return 'application/vnd.ms-excel';
      case 'zip': return 'application/zip';
      default: return 'application/octet-stream';
    }
  }

  String getMimeType(String fileName) => _getMimeType(fileName);

  // ------------------------------------------------------------------------
  //                           DISPOSAL
  // ------------------------------------------------------------------------

  void dispose() {
    _networkProgressSub?.cancel();
    _transferController.close();
    _progressController.close();
    _completeController.close();
    _errorController.close();
    _transfers.clear();
  }
}