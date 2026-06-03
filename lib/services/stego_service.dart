import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:convert';
import 'package:image/image.dart' as img;
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:gal/gal.dart';
import 'package:flutter/foundation.dart';

class StegoResult {
  final bool success;
  final String? message;
  final File? file;
  final String? error;

  StegoResult.success(this.file, {this.message})
      : success = true,
        error = null;
  StegoResult.failure(this.error)
      : success = false,
        message = null,
        file = null;
}

class StegoService {
  static final StegoService _instance = StegoService._internal();
  factory StegoService() => _instance;
  StegoService._internal();

  bool canEmbed(File imageFile, String message) {
    try {
      final bytes = imageFile.readAsBytesSync();
      final image = img.decodeImage(bytes);
      if (image == null) return false;
      return (32 + utf8.encode(message).length * 8) <= image.width * image.height;
    } catch (_) {
      return false;
    }
  }

  Future<StegoResult> embedMessage({
    required File imageFile,
    required String message,
    required String password,
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      img.Image? image = img.decodeImage(bytes);
      if (image == null) return StegoResult.failure('Failed to decode image');

      // Convert RGBA to RGB if needed
      if (image.numChannels == 4) {
        final n = img.Image(
            width: image.width, height: image.height, numChannels: 3);
        for (var px in image) n.setPixelRgb(px.x, px.y, px.r, px.g, px.b);
        image = n;
      }

      final msgBytes = utf8.encode(message);
      final payload =
          _intToBinary32(msgBytes.length) + _bytesToBinary(msgBytes);

      if (payload.length > image.width * image.height) {
        return StegoResult.failure('Message too long for this image');
      }

      final indices = _shuffledIndices(image.width, image.height, password);
      for (int i = 0; i < payload.length; i++) {
        final pi = indices[i];
        final x = pi % image.width;
        final y = pi ~/ image.width;
        final px = image.getPixel(x, y);
        image.setPixelRgb(
          x, y,
          (px.r.toInt() & 0xFE) | int.parse(payload[i]),
          px.g, px.b,
        );
      }

      final pngBytes = img.encodePng(image);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final filename = 'stego_$timestamp.png';

      // Save to app documents (always works — used for extract later)
      final appDir = await getApplicationDocumentsDirectory();
      final appFile = File('${appDir.path}/$filename');
      await appFile.writeAsBytes(pngBytes);

      // Save to gallery using gal package (handles all Android versions)
      bool savedToGallery = false;
      try {
        // Request access if needed (gal handles this internally)
        final hasAccess = await Gal.hasAccess(toAlbum: true);
        if (!hasAccess) {
          await Gal.requestAccess(toAlbum: true);
        }
        // Save to gallery album named VeilChat
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

  Future<StegoResult> extractMessage({
    required File imageFile,
    required String password,
  }) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      if (image == null) return StegoResult.failure('Failed to decode image');

      final indices = _shuffledIndices(image.width, image.height, password);

      // Read message length (first 32 bits)
      String binLen = '';
      for (int i = 0; i < 32; i++) {
        final pi = indices[i];
        binLen += (image
                .getPixel(pi % image.width, pi ~/ image.width)
                .r
                .toInt() &
            1)
            .toString();
      }

      final msgLen = int.tryParse(binLen, radix: 2);
      if (msgLen == null || msgLen <= 0 || msgLen > 10000) {
        return StegoResult.failure(
            'No hidden message found (wrong password?)');
      }

      // Read message bits
      String binMsg = '';
      for (int i = 0; i < msgLen * 8; i++) {
        final pi = indices[i + 32];
        binMsg += (image
                .getPixel(pi % image.width, pi ~/ image.width)
                .r
                .toInt() &
            1)
            .toString();
      }

      return StegoResult.success(null, message: _binaryToUtf8(binMsg));
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
