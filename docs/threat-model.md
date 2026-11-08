# VeilChat Threat Model

## 1. System Assumptions and Trust Boundaries

VeilChat operates under a strict trust boundary model:

```
[ User Device Alice ]            [ Network / Internet ]           [ Relay Server / Host ]
┌─────────────────────────┐      ┌─────────────────────────┐      ┌─────────────────────────┐
│ • Mobile OS Sandbox     │      │ • Passive Eavesdroppers │      │ • Port 5000 TCP Relay   │
│ • Hardware / Keypad     │ <==> │ • Active MITM Attackers │ <==> │ • Port 5001 Flask Media │
│ • SQLite veilchat_v9.db │      │ • ISP / Telecom Monitors│      │ • File System Storage   │
└─────────────────────────┘      └─────────────────────────┘      └─────────────────────────┘
     [ Trusted Domain ]                  [ Untrusted ]                [ Semi-Trusted Blind ]
```

### Trust Assumptions
1. **Trusted Device Execution**: The local smartphone OS (Android) sandbox is assumed to be uncompromised by root-level spyware or memory dumpers while active.
2. **Pre-Shared Secret Authenticity**: Communicating parties share their Room Key (passphrase) through an authenticated out-of-band channel.
3. **Untrusted Transit Network**: The network between client devices and servers is assumed to be fully observable by third parties (ISPs, network operators, malicious Wi-Fi routers).
4. **Blind Server Integrity**: The backend relay server is treated as honest-but-curious; it faithfully routes packets but cannot be trusted with plaintext data or cryptographic keys.

---

## 2. Protected Threat Vectors (In-Scope)

### 2.1 Eavesdropping on Network Traffic
* **Threat**: A third party monitors packet traffic on public Wi-Fi or transit routers.
* **Mitigation**: All text messages, group messages, and media files are encrypted client-side using AES-256-GCM before socket transmission. Intercepted traffic contains only high-entropy hex ciphertext with unique salts and nonces.

### 2.2 Tampering and Replay Attacks
* **Threat**: An active attacker intercepts and alters in-flight packets or replays previously sent messages.
* **Mitigation**: AES-GCM includes a 128-bit authentication tag (MAC). Any bit modification causes decryption to abort. Each message uses an ephemeral 16-byte nonce, guaranteeing that identical plaintexts yield completely unique ciphertexts.

### 2.3 Server Database Compromise
* **Threat**: An adversary gains full read access to the backend server's file system (`server_users.json`, `server_offline.json`, `media_uploads/`).
* **Mitigation**:
  * Passwords stored on the server are salted and hashed using `bcrypt` (12 rounds). Plaintext passwords are never persisted.
  * Messages in `server_offline.json` are client-encrypted ciphertext blobs.
  * Files in `media_uploads/` are pre-encrypted `.enc` files that cannot be decrypted without the client's shared room key.

### 2.4 Visual Steganalysis & Shoulder Surfing
* **Threat**: An observer visually inspects images sent or stored on the device.
* **Mitigation**: Randomized LSB steganography scatters data bits across the image using a pseudo-random permutation derived from the key's SHA-256 hash. The resulting image exhibits zero visible artifacts to the human eye. In-app hidden messages can only be revealed by supplying the correct decoy key.

---

## 3. Known Limitations and Non-Goals (Out-of-Scope)

### 3.1 Advanced Statistical Steganalysis
* **Limitation**: While randomized LSB defeats visual detection and naive sequential extraction scripts, high-payload LSB embedding alters the statistical distribution of color frequencies. Advanced chi-square ($\chi^2$) analysis or sample-pair steganalysis can statistically infer that an image carries hidden data if high percentages of pixels are altered.
* **Recommendation**: Use carrier images with substantially higher pixel counts than the payload size to keep embedding ratios under 5% of total capacity.

### 3.2 Perfect Forward Secrecy (PFS) in Shared Room Key Mode
* **Limitation**: VeilChat uses a symmetric Shared Room Key model derived via PBKDF2. If an adversary compromises the shared passphrase, they can decrypt recorded past messages that used that key. VeilChat does not implement the Double Ratchet Algorithm (Signal Protocol) in this release.

### 3.3 Endpoint Compromise
* **Limitation**: If an attacker installs a hardware keylogger, takes screenshots on a rooted device, or captures physical access while the device is unlocked, cryptographic protections at the application layer cannot prevent observation of decrypted screen contents.

### 3.4 Traffic Analysis and Metadata Exposure
* **Limitation**: Although message bodies are completely encrypted, packet arrival times, connection intervals, and approximate payload sizes are visible to network observers and the relay server.
