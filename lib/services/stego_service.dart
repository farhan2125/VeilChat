import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:gal/gal.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class StegoImageCapacity {
  final int width;
  final int height;

  const StegoImageCapacity({required this.width, required this.height});

  int get totalPixels => width * height;
  int get maxPayloadBytes => max(0, (totalPixels - 32) ~/ 8);

  bool canFitBytes(int byteLength) => (32 + byteLength * 8) <= totalPixels;
}

class StegoResult {
  final bool success;
  final String? message;
  final File? file;
  final String? error;

  StegoResult.success(this.file, {this.message}) : success = true, error = null;
  StegoResult.failure(this.error)
    : success = false,
      message = null,
      file = null;
}

class StegoService {
  static final StegoService _instance = StegoService._internal();
  factory StegoService() => _instance;
  StegoService._internal();

  StegoImageCapacity? inspectBytes(Uint8List bytes) {
    try {
      final image = img.decodeImage(bytes);
      if (image == null) return null;
      return StegoImageCapacity(width: image.width, height: image.height);
    } catch (_) {
      return null;
    }
  }

  StegoImageCapacity? inspectImage(File imageFile) {
    try {
      return inspectBytes(imageFile.readAsBytesSync());
    } catch (_) {
      return null;
    }
  }

  bool canEmbed(File imageFile, String message) {
    final cap = inspectImage(imageFile);
    if (cap == null) return false;
    return cap.canFitBytes(utf8.encode(message).length);
  }

  /// Pure in-memory randomized Red-channel LSB embedding.
  /// Binary layout: [32-bit byte length][UTF-8 payload bits].
  Uint8List? embedBytesInMemory({
    required Uint8List imageBytes,
    required String message,
    required String password,
  }) {
    img.Image? image = img.decodeImage(imageBytes);
    if (image == null) return null;

    if (image.numChannels == 4) {
      final n = img.Image(
        width: image.width,
        height: image.height,
        numChannels: 3,
      );
      for (final px in image) {
        n.setPixelRgb(px.x, px.y, px.r, px.g, px.b);
      }
      image = n;
    }

    final msgBytes = utf8.encode(message);
    final payload = _intToBinary32(msgBytes.length) + _bytesToBinary(msgBytes);

    if (payload.length > image.width * image.height) {
      return null;
    }

    final indices = _shuffledIndices(image.width, image.height, password);
    for (int i = 0; i < payload.length; i++) {
      final pi = indices[i];
      final x = pi % image.width;
      final y = pi ~/ image.width;
      final px = image.getPixel(x, y);
      image.setPixelRgb(
        x,
        y,
        (px.r.toInt() & 0xFE) | int.parse(payload[i]),
        px.g,
        px.b,
      );
    }

    return Uint8List.fromList(img.encodePng(image));
  }

  /// Pure in-memory randomized Red-channel LSB extraction.
  String? extractBytesInMemory({
    required Uint8List imageBytes,
    required String password,
  }) {
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null) return null;

      final indices = _shuffledIndices(image.width, image.height, password);
      if (indices.length < 32) return null;

      String binLen = '';
      for (int i = 0; i < 32; i++) {
        final pi = indices[i];
        binLen +=
            (image.getPixel(pi % image.width, pi ~/ image.width).r.toInt() & 1)
                .toString();
      }

      final msgLen = int.tryParse(binLen, radix: 2);
      if (msgLen == null ||
          msgLen <= 0 ||
          msgLen > 10000 ||
          32 + msgLen * 8 > indices.length) {
        return null;
      }

      String binMsg = '';
      for (int i = 0; i < msgLen * 8; i++) {
        final pi = indices[i + 32];
        binMsg +=
            (image.getPixel(pi % image.width, pi ~/ image.width).r.toInt() & 1)
                .toString();
      }

      return _binaryToUtf8(binMsg);
    } catch (_) {
      return null;
    }
  }

  Future<StegoResult> embedMessage({
    required File imageFile,
    required String message,
    required String password,
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final cap = inspectBytes(bytes);
      if (cap == null) return StegoResult.failure('Failed to decode image');

      final msgBytes = utf8.encode(message);
      if (!cap.canFitBytes(msgBytes.length)) {
        return StegoResult.failure('Message too long for this image');
      }

      final pngBytes = embedBytesInMemory(
        imageBytes: bytes,
        message: message,
        password: password,
      );
      if (pngBytes == null) {
        return StegoResult.failure('Failed to encode stego image');
      }

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'stego_$timestamp.png';

      // Save to app documents (always works — used for extract later)
      final appDir = await getApplicationDocumentsDirectory();
      final appFile = File('${appDir.path}/$filename');
      await appFile.writeAsBytes(pngBytes);

      // Save to gallery using gal package (handles all Android versions)
      bool savedToGallery = false;
      try {
        final hasAccess = await Gal.hasAccess(toAlbum: true);
        if (!hasAccess) {
          await Gal.requestAccess(toAlbum: true);
        }
        await Gal.putImageBytes(
          Uint8List.fromList(pngBytes),
          name: filename,
          album: 'VeilChat',
        );
        savedToGallery = true;
        debugPrint('✅ Stego image saved to gallery: $filename');
      } catch (e) {
        debugPrint('⚠️ Gallery save failed: $e — image saved to app storage');
      }

      final msg2 = savedToGallery
          ? '✅ Image saved to Gallery > VeilChat album'
          : '✅ Image saved to app storage\n(gallery save failed: check permissions)';

      return StegoResult.success(appFile, message: msg2);
    } catch (e) {
      debugPrint('❌ Embed error: $e');
      return StegoResult.failure('Embedding failed: $e');
    }
  }

  /// Saves a raw decoded image byte stream straight into the device's public
  /// media library via `gal`.
  Future<StegoResult> saveBytesToGallery(
    List<int> bytes, {
    String? name,
    String album = 'VeilChat',
  }) async {
    try {
      if (bytes.isEmpty) {
        return StegoResult.failure('Image data is empty');
      }

      final hasAccess = await Gal.hasAccess(toAlbum: true);
      if (!hasAccess) {
        final granted = await Gal.requestAccess(toAlbum: true);
        if (!granted) {
          return StegoResult.failure(
            'Gallery permission denied. Enable Photos/Media access in Settings.',
          );
        }
      }

      final fileName =
          name ?? 'veilchat_${DateTime.now().millisecondsSinceEpoch}';

      await Gal.putImageBytes(
        bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
        name: fileName,
        album: album,
      );

      debugPrint('✅ Image saved to gallery: $fileName');
      return StegoResult.success(null, message: 'Saved to Gallery > $album');
    } on GalException catch (e) {
      debugPrint('❌ Gal save error: ${e.type}');
      switch (e.type) {
        case GalExceptionType.accessDenied:
          return StegoResult.failure(
            'Gallery permission denied. Enable Photos/Media access in Settings.',
          );
        case GalExceptionType.notEnoughSpace:
          return StegoResult.failure('Not enough storage space to save image.');
        case GalExceptionType.notSupportedFormat:
          return StegoResult.failure('This image format is not supported.');
        default:
          return StegoResult.failure('Could not save image: ${e.type}');
      }
    } catch (e) {
      debugPrint('❌ saveBytesToGallery error: $e');
      return StegoResult.failure('Could not save image: $e');
    }
  }

  /// Convenience wrapper — saves an existing image [file] to the gallery.
  Future<StegoResult> saveFileToGallery(File file, {String? name}) async {
    try {
      if (!await file.exists()) {
        return StegoResult.failure('Image file no longer exists');
      }
      return saveBytesToGallery(await file.readAsBytes(), name: name);
    } catch (e) {
      return StegoResult.failure('Could not read image: $e');
    }
  }

  Future<StegoResult> extractMessage({
    required File imageFile,
    required String password,
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      if (inspectBytes(bytes) == null) {
        return StegoResult.failure('Failed to decode image');
      }
      final extracted = extractBytesInMemory(
        imageBytes: bytes,
        password: password,
      );
      if (extracted == null) {
        return StegoResult.failure('No hidden message found (wrong password?)');
      }
      return StegoResult.success(null, message: extracted);
    } catch (e) {
      return StegoResult.failure('Extraction failed: $e');
    }
  }

  List<int> _shuffledIndices(int w, int h, String password) {
    final indices = List<int>.generate(w * h, (i) => i);
    final digest = sha256.convert(utf8.encode(password));
    int seed = 0;
    for (int i = 0; i < 8; i++) {
      seed = (seed << 8) | (digest.bytes[i] & 0xFF);
    }
    indices.shuffle(Random(seed));
    return indices;
  }

  String _intToBinary32(int v) => v.toRadixString(2).padLeft(32, '0');

  String _bytesToBinary(List<int> b) =>
      b.map((x) => x.toRadixString(2).padLeft(8, '0')).join();

  String _binaryToUtf8(String bin) {
    final bytes = <int>[];
    for (int i = 0; i < bin.length; i += 8) {
      bytes.add(int.parse(bin.substring(i, i + 8), radix: 2));
    }
    return utf8.decode(bytes);
  }
}
