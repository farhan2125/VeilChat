import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

/// AES-256-GCM + PBKDF2. Iterations reduced 120k→10k for 12x faster mobile perf.
class CryptoService {
  static final CryptoService _instance = CryptoService._internal();
  factory CryptoService() => _instance;
  CryptoService._internal();

  static const int _kdfIterations = 10000; // was 120000 — 12x faster on mobile
  static const int _saltLen = 16, _nonceLen = 16, _macLen = 16;

  final AesGcm _algorithm = AesGcm.with256bits(nonceLength: _nonceLen);
  final Random _rng = Random.secure();

  Uint8List _randomBytes(int n) => Uint8List.fromList(List.generate(n, (_) => _rng.nextInt(256)));

  Future<SecretKey> _deriveKey(String password, List<int> salt) async =>
      Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: _kdfIterations, bits: 256)
          .deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);

  /// Returns [SALT(16)][NONCE(16)][MAC(16)][CIPHERTEXT] or null on error.
  Future<List<int>?> encrypt(String password, String plaintext) async {
    try {
      final salt = _randomBytes(_saltLen);
      final key = await _deriveKey(password, salt);
      final nonce = _algorithm.newNonce();
      final box = await _algorithm.encrypt(utf8.encode(plaintext), secretKey: key, nonce: nonce);
      return [...salt, ...box.nonce, ...box.mac.bytes, ...box.cipherText];
    } catch (e) { debugPrint('❌ Encrypt: $e'); return null; }
  }

  /// Decrypts in background isolate. Returns plaintext or null.
  Future<String?> decrypt(String password, List<int> payload) async {
    try {
      if (payload.length < 48) return null;
      return await compute(_worker, {'password': password, 'payload': payload, 'iter': _kdfIterations});
    } catch (e) { debugPrint('❌ Decrypt: $e'); return null; }
  }

  static Future<String?> _worker(Map<String, dynamic> d) async {
    final password = d['password'] as String;
    final payload  = d['payload']  as List<int>;
    final iter     = d['iter']     as int;
    if (payload.length < 48) return null;
    final salt = payload.sublist(0, 16), nonce = payload.sublist(16, 32),
          mac  = payload.sublist(32, 48), ct    = payload.sublist(48);
    final key = await Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: iter, bits: 256)
        .deriveKey(secretKey: SecretKey(utf8.encode(password)), nonce: salt);
    final clear = await AesGcm.with256bits(nonceLength: 16)
        .decrypt(SecretBox(ct, nonce: nonce, mac: Mac(mac)), secretKey: key);
    return utf8.decode(clear);
  }

  List<int> hexToBytes(String hex) {
    hex = hex.trim(); if (hex.length % 2 != 0) hex = '0$hex';
    return [for (int i = 0; i < hex.length; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
  }

  String bytesToHex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
