import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:veilchat_new/services/crypto_service.dart';
import 'package:veilchat_new/services/stego_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('CryptoService Unit Tests', () {
    final crypto = CryptoService();
    const testPassword = 'SecureMasterPassword2026!';
    const testPlaintext = 'VeilChat Confidential Steganography Message';

    test(
      'Encryption produces non-empty payload with at least 48 bytes header',
      () async {
        final encrypted = await crypto.encrypt(testPassword, testPlaintext);
        expect(encrypted, isNotNull);
        expect(encrypted!.length, greaterThanOrEqualTo(48));
      },
    );

    test(
      'Two encryptions of identical plaintext produce distinct ciphertexts (unique salt & nonce)',
      () async {
        final enc1 = await crypto.encrypt(testPassword, testPlaintext);
        final enc2 = await crypto.encrypt(testPassword, testPlaintext);
        expect(enc1, isNotNull);
        expect(enc2, isNotNull);
        expect(enc1, isNot(equals(enc2)));
      },
    );

    test(
      'Decryption with correct password successfully recovers plaintext',
      () async {
        final encrypted = await crypto.encrypt(testPassword, testPlaintext);
        expect(encrypted, isNotNull);

        final hex = crypto.bytesToHex(encrypted!);
        final bytes = crypto.hexToBytes(hex);
        expect(bytes, equals(encrypted));

        final decrypted = await crypto.decrypt(testPassword, encrypted);
        expect(decrypted, equals(testPlaintext));
      },
    );

    test('Decryption with wrong password fails / returns null', () async {
      final encrypted = await crypto.encrypt(testPassword, testPlaintext);
      expect(encrypted, isNotNull);

      final decrypted = await crypto.decrypt('WrongPassword123!', encrypted!);
      expect(decrypted, isNull);
    });

    test(
      'Tampered ciphertext fails authentication (MAC integrity check)',
      () async {
        final encrypted = await crypto.encrypt(testPassword, testPlaintext);
        expect(encrypted, isNotNull);

        final tampered = List<int>.from(encrypted!);
        tampered[tampered.length - 1] ^= 0x01;

        final decrypted = await crypto.decrypt(testPassword, tampered);
        expect(decrypted, isNull);
      },
    );
  });

  group('StegoService Unit Tests', () {
    test('canEmbed and inspectBytes calculate capacity accurately', () {
      final stego = StegoService();
      final tempDir = Directory.systemTemp.createTempSync('stego_test');
      final imageFile = File('${tempDir.path}/test.png');

      final image = img.Image(width: 100, height: 100);
      img.fill(image, color: img.ColorRgb8(200, 100, 50));
      final pngBytes = Uint8List.fromList(img.encodePng(image));
      imageFile.writeAsBytesSync(pngBytes);

      final cap = stego.inspectImage(imageFile);
      expect(cap, isNotNull);
      expect(cap!.width, equals(100));
      expect(cap.height, equals(100));
      expect(cap.totalPixels, equals(10000));
      expect(cap.maxPayloadBytes, equals((10000 - 32) ~/ 8));
      expect(stego.canEmbed(imageFile, 'Short msg'), isTrue);

      tempDir.deleteSync(recursive: true);
    });

    test('Round-trip randomized Red-channel LSB embed & extract in memory', () {
      final stego = StegoService();
      final image = img.Image(width: 80, height: 80);
      img.fill(image, color: img.ColorRgb8(120, 180, 210));
      final carrierBytes = Uint8List.fromList(img.encodePng(image));

      const secret = 'Stealth coordinates: 34.0522° N, 118.2437° W 🔒';
      const password = 'QuantumVeilKey#2026';

      final embeddedPng = stego.embedBytesInMemory(
        imageBytes: carrierBytes,
        message: secret,
        password: password,
      );
      expect(embeddedPng, isNotNull);

      final extracted = stego.extractBytesInMemory(
        imageBytes: embeddedPng!,
        password: password,
      );
      expect(extracted, equals(secret));

      final wrongPassResult = stego.extractBytesInMemory(
        imageBytes: embeddedPng,
        password: 'WrongPassword!',
      );
      expect(wrongPassResult, isNot(equals(secret)));
    });
  });
}
