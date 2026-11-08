# Changelog

All notable changes to VeilChat will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [1.0.0] - 2026-11-08

### Added
* **Authenticated Encryption**: Full AES-256-GCM message encryption paired with PBKDF2-HMAC-SHA256 (10,000 iterations) key derivation.
* **Randomized LSB Steganography**: Custom pixel-shuffling engine using SHA-256-seeded PRNG to hide encrypted payloads inside carrier PNG images.
* **Dual-Server Python Backend**:
  * Persistent TCP Socket Relay Server (Port 5000) with 20-byte fixed-header binary packet framing.
  * Flask HTTP Media Server (Port 5001) with streaming download, CORS, and 50MB file size limits.
* **WebRTC Voice & Video Calling**: Real-time peer-to-peer VoIP with Google STUN NAT discovery and TURN relay fallback.
* **Local Sovereign Storage**: SQLite database (`veilchat_v9.db`) with dynamic schema introspection and migration via `PRAGMA table_info`.
* **Glassmorphic UI**: Cyberpunk-inspired frosted glass aesthetic with fluid custom painters and unified haptic feedback.
* **Group Messaging**: Group chat room creation, invitation broadcasts, administrative roles (Kick/Promote/Demote), and member presence.
* **Offline Queuing**: Ephemeral message queue buffering on TCP relay with automatic delivery on recipient reconnection.
* **Release Tooling**: Automated unit tests for cryptography, steganography, and backend socket protocol; GitHub Actions CI workflow.
