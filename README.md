# VeilChat — Confidential Steganography Chat

<p align="center">
  <img src="assets/branding/veilchat_logo.svg" alt="VeilChat Logo" width="220" />
</p>

<p align="center">
  <strong>A privacy-focused Android messaging application combining AES-256-GCM authenticated encryption, randomized LSB image steganography, and WebRTC peer-to-peer communication.</strong>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Android-green.svg" alt="Platform" />
  <img src="https://img.shields.io/badge/Flutter-3.41.2-blue.svg" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.11.0-0175C2.svg" alt="Dart" />
  <img src="https://img.shields.io/badge/Python-3.10%20%7C%203.11%20%7C%203.12-yellow.svg" alt="Python" />
  <img src="https://img.shields.io/badge/License-MIT-purple.svg" alt="License" />
</p>

---

## 1. Product Overview

In contemporary digital messaging, traditional encryption alone signals to network observers that sensitive data is being transmitted. **VeilChat** bridges this critical gap by fusing cryptography with **image-based steganography**, concealing not only the message content but also the very existence of confidential communication.

Built using **Flutter** for the mobile client and a **dual-service Python backend**, VeilChat guarantees strict local data sovereignty: messages and private keys exist only on the user's physical device, while the central relay infrastructure acts as a blind postman.

---

## 2. Key Features

* **Authenticated Encryption (AES-256-GCM)**: All messages and file payloads are encrypted client-side using 256-bit AES in Galois/Counter Mode with 128-bit MAC verification.
* **PBKDF2 Key Derivation**: Symmetric keys are derived using PBKDF2 with HMAC-SHA256 and 10,000 iterations from a shared Room Key, balancing brute-force resistance with smooth mobile performance.
* **Randomized LSB Steganography**: Embeds secret text or encrypted payloads into carrier images by non-linearly shuffling Red-channel pixel indices using a SHA-256-seeded PRNG, defeating linear steganalysis scripts.
* **Decoupled Dual-Server Backend**:
  * **TCP Relay Server (Port 5000)**: Ultra-fast socket relay with a custom 20-byte fixed header framing protocol for real-time messaging, presence, and WebRTC signaling.
  * **Flask Media Server (Port 5001)**: Out-of-band transport for heavy pre-encrypted image, voice, and document transfers up to 50MB.
* **WebRTC Voice & Video Calling**: True peer-to-peer VoIP and video connections over direct UDP streams, utilizing Google STUN servers and openrelay TURN relays for symmetric NAT traversal.
* **Local Sovereign SQLite Database**: SQLite database (`veilchat_v9.db`) with automatic schema introspection and zero-downtime column migrations.
* **Glassmorphic Cyberpunk UI**: Translucent frosted-glass aesthetics, custom canvas vector painters, and unified haptic feedback.
* **Ephemeral Offline Queuing**: Offline messages are buffered on the relay server in memory and purged immediately upon delivery.
* **Group Messaging with Admin Controls**: Create encrypted rooms, invite members, promote/demote admins, and manage custom room wallpapers.

---

## 3. High-Level Architecture

VeilChat separates lightweight real-time control traffic from heavy binary transfers to ensure smooth mobile performance and zero server-side bottlenecks.

```mermaid
flowchart TB
    subgraph ClientA["Sender (Flutter Mobile App)"]
        UI_A["Glassmorphic UI"]
        Crypto_A["CryptoService (AES-256-GCM)"]
        Stego_A["StegoService (Randomized LSB)"]
        DB_A[("SQLite (veilchat_v9.db)")]
        Net_A["NetworkService (TCP 20B Framing)"]
        WebRTC_A["WebRTC Engine"]
    end

    subgraph Backend["VeilChat Dual-Server Backend"]
        subgraph TCPServer["TCP Relay Server (Port 5000)"]
            SockMux["Socket Multiplexer"]
            BcryptAuth["Bcrypt Authenticator"]
            Presence["Presence & Heartbeats"]
            OffQueue["Ephemeral Offline Queue"]
        end

        subgraph MediaServer["Flask HTTP Server (Port 5001)"]
            UploadAPI["POST /upload"]
            DownloadAPI["GET /download/<file>"]
            DiskStore[("media_uploads/")]
        end
    end

    subgraph ClientB["Recipient (Flutter Mobile App)"]
        Net_B["NetworkService (TCP 20B Framing)"]
        Crypto_B["CryptoService (AES-256-GCM)"]
        DB_B[("SQLite (veilchat_v9.db)")]
        UI_B["Glassmorphic UI"]
        WebRTC_B["WebRTC Engine"]
    end

    %% Communication routes
    Net_A <-->|"TCP (Port 5000: Control & Messages)"| SockMux
    SockMux <-->|"TCP (Port 5000: Control & Messages)"| Net_B

    Net_A -->|"HTTP POST (Port 5001: Encrypted Blobs)"| UploadAPI
    UploadAPI --> DiskStore
    DownloadAPI -->|"HTTP GET (Port 5001)"| Net_B

    WebRTC_A <===>|"Direct P2P UDP Media Stream (SRTP)"| WebRTC_B
    WebRTC_A -.->|"Signaling via TCP 5000"| SockMux
    SockMux -.->|"Signaling via TCP 5000"| WebRTC_B
```

### Why Two Separate Backend Services?
1. **Thread Concurrency**: Instant messaging demands sub-millisecond socket responsiveness. Routing a 20MB encrypted image over the persistent TCP socket would block the event loop and introduce noticeable typing/signaling latency for other users.
2. **Failure Isolation**: An HTTP upload timeout or disk I/O burst on the media server has zero impact on live real-time chats or active WebRTC calls.
3. **Bandwidth Optimization**: The Flask media server can be scaled, cached, or placed behind a reverse proxy (e.g. Nginx) independently of the stateful TCP connection pool.

---

## 4. Security & Cryptographic Workflow

```mermaid
sequenceDiagram
    autonumber
    actor Alice as Alice
    participant Crypto as CryptoService (Mobile)
    participant Relay as TCP Relay (Server)
    actor Bob as Bob

    Note over Alice,Bob: Shared Secret Room Key established out-of-band
    Alice->>Crypto: encrypt(password, plaintext)
    Crypto->>Crypto: Generate 16-byte cryptographically secure random Salt
    Crypto->>Crypto: PBKDF2 (HMAC-SHA256, 10,000 iters) -> 256-bit Key
    Crypto->>Crypto: Generate 16-byte random Nonce
    Crypto->>Crypto: AES-256-GCM Encrypt
    Crypto->>Crypto: Package [Salt(16) | Nonce(16) | MAC(16) | Ciphertext]
    Crypto-->>Alice: Return Hex Encrypted Payload
    Alice->>Relay: Send 20-byte Header + Hex Payload
    Note over Relay: Server inspects ONLY packet routing.<br/>Payload is completely unreadable.
    Relay->>Bob: Forward Packet
    Bob->>Crypto: decrypt(password, payload)
    Crypto->>Crypto: Extract Salt, Nonce, MAC, Ciphertext
    Crypto->>Crypto: Derive Key via PBKDF2
    Crypto->>Crypto: Verify AES-GCM MAC Tag
    alt MAC Verification Passed
        Crypto-->>Bob: Plaintext Restored
    else MAC Verification Failed (Tampered or Bad Key)
        Crypto-->>Bob: Reject Payload (null)
    end
```

### Payload Structure
```
+----------------+----------------+----------------+--------------------------+
|  Salt (16 B)   |  Nonce (16 B)  |   MAC (16 B)   |   Ciphertext (Variable)  |
+----------------+----------------+----------------+--------------------------+
```
* **Total Prefix**: 48 bytes.
* **Integrity Enforcement**: Any bit flip in transit invalidates the GCM authentication tag, causing immediate rejection.

---

## 5. Steganography Workflow

VeilChat embeds secret data into standard images using **Randomized Least Significant Bit (LSB)** steganography:

```mermaid
flowchart LR
    Cover["Cover Image"] --> Dec["Decode RGB"]
    Key["Stego Key"] --> Hash["SHA-256 Digest"]
    Hash --> Seed["64-bit Seed"]
    Seed --> Shuffle["Shuffle Pixel Indices (PRNG)"]
    Dec --> Shuffle
    Secret["Encrypted Payload"] --> Bits["32-bit Length + Bit Stream"]
    Shuffle --> Embed["Embed in Red LSB: (px.r & 0xFE) | bit"]
    Bits --> Embed
    Embed --> PNG["Lossless PNG Output"]
```

1. The user selects a carrier image and provides a secret passphrase.
2. The SHA-256 digest of the passphrase generates a 64-bit seed.
3. The image's pixel indices are pseudo-randomly shuffled using this seed.
4. The 32-bit payload length prefix and data bits are embedded into the Red channel's least significant bit.
5. The output is saved strictly as a lossless PNG to preserve pixel values.

---

## 6. Installation & Quick Start

### 6.1 Prerequisites
* **Python**: 3.10+
* **Flutter**: 3.19.0+ (Tested with Flutter 3.41.2 / Dart 3.11.0)
* **Android SDK**: API Level 34+
* **JDK**: OpenJDK 17 or 21

---

### 6.2 Backend Startup
In a terminal, navigate to the `server/` directory:

```bash
cd server
python -m venv venv

# Windows:
.\venv\Scripts\activate
# Linux/macOS:
source venv/bin/activate

pip install -r requirements.txt
```

Launch both servers:
* **Windows**: Run `server\run_all.bat`
* **Manual**:
  ```bash
  # Terminal 1: Real-time TCP Relay
  python server/server.py

  # Terminal 2: HTTP Media Server
  python server/media_server.py
  ```

---

### 6.3 Mobile App Startup
From the project root:

```bash
# Fetch Flutter packages
flutter pub get

# Run on connected Android device or emulator
flutter run
```

#### Server IP Configuration:
1. Tap the **Server Config** icon on the Login Screen.
2. Enter your host IP:
   * **Android Emulator**: `10.0.2.2`
   * **Physical Device**: Your computer's local Wi-Fi IP (e.g., `192.168.1.50`).
3. Set TCP port to `5000` (HTTP media server on port `5001` is resolved automatically).

---

### 6.4 Build Release APK
```bash
flutter build apk --release
```
The compiled package will be located at:
`build/app/outputs/flutter-apk/app-release.apk`

---

## 7. Automated Testing

### Backend Unit Tests
```bash
python -m unittest scratch/test_backend.py
```

### Flutter & Cryptography Tests
```bash
flutter test test/crypto_stego_test.dart
```

### Static Analysis
```bash
flutter analyze
```

---

## 8. Documentation Index

Detailed engineering documentation is available in the [`docs/`](docs/) directory:

* [System Architecture](docs/architecture.md) — Comprehensive mobile-to-backend system design.
* [Installation Guide](docs/installation.md) — Step-by-step development and deployment setup.
* [Configuration Reference](docs/configuration.md) — Ports, endpoints, and environment settings.
* [Security Model](docs/security-model.md) — AES-256-GCM, PBKDF2 parameters, and steganography specifications.
* [Threat Model](docs/threat-model.md) — Protected vectors, trust boundaries, and known limitations.
* [Networking & Wire Protocol](docs/networking.md) — 20-byte TCP header specification and REST endpoints.
* [Database Schema](docs/database.md) — SQLite tables, indexing, and migration logic.
* [Troubleshooting](docs/troubleshooting.md) — Solutions for common connectivity, media, and build issues.

---

## 9. Security Notice & Limitations

* **Plausible Deniability**: LSB steganography is visually imperceptible. However, high embedding ratios alter color frequency statistics. Keep payload sizes below 5% of the carrier image's pixel capacity to avoid statistical detection.
* **Shared Room Key**: VeilChat employs pre-shared symmetric keys. If a counterparty exposes their shared key, previous messages encrypted with that key become readable. Future versions will incorporate the Double Ratchet Algorithm for forward secrecy.
* **Responsible Disclosure**: Please review our [Security Policy](SECURITY.md) before reporting security findings.

---

## 10. Contributing

We welcome community contributions! Please review [CONTRIBUTING.md](CONTRIBUTING.md) and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) before submitting a pull request.

---

## 11. Authors & Acknowledgments

### Core Contributors
* **Asma Zarbab**
* **Bushra Allah Ditta**
* **Sehar Ashfaq**
* **Tooba Fatima**
* **Farhan Ashraf**
* **Haiz**

### Academic Supervision
* **Ms. Huma Zahid**, Lecturer, Department of Computer Science, Govt Islamia Graduate College (W) Cooper Road, Lahore (affiliated with Lahore College for Women University).

---

## 12. License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.
