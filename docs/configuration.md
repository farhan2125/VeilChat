# Configuration & Environment Reference

This document outlines all ports, network endpoints, security parameters, and configuration options used across the VeilChat ecosystem.

---

## 1. Network Ports & Protocols

| Service | Port | Protocol | Default Bind | Purpose |
|---|---|---|---|---|
| **Real-Time Relay Server** | `5000` | TCP | `0.0.0.0:5000` | Real-time signaling, messaging, presence, user auth |
| **Media Transport Server** | `5001` | HTTP / REST | `0.0.0.0:5001` | Encrypted media upload, streaming download, health check |
| **WebRTC Media Stream** | Dynamic | UDP (SRTP) | Direct P2P | Direct peer-to-peer audio and video transmission |

### Firewall Rules
If hosting on a remote server or testing across different LAN subnets, ensure inbound access is allowed on:
* `5000/TCP` (Inbound)
* `5001/TCP` (Inbound)
* Dynamic UDP high ports for WebRTC direct connections.

---

## 2. Server Configuration

### 2.1 Storage Files (`server/`)
The Python TCP server maintains local JSON state files in its working directory:

| Filename | Purpose | Format |
|---|---|---|
| `server_users.json` | Stores user credentials with bcrypt hashes | `{"<username>": "<bcrypt_hash>"}` |
| `server_offline.json` | Ephemeral message queue for offline recipients | `{"<username>": [<pending_packets>]}` |
| `server_groups.json` | Group rosters and metadata | `{"<group_id>": {"id": "...", "members": [...]}}` |
| `server_profiles.json` | Presence tracking and last seen epoch | `{"<username>": {"lastSeen": <epoch_ms>}}` |

> [!NOTE]
> In production and public distribution, these files are automatically created if absent. Templates are provided as `.example` files.

### 2.2 Media Storage (`server/media_uploads/`)
* **Directory**: `server/media_uploads/`
* **File Naming**: `<epoch_ms>_<uuid8>.<ext>` (e.g. `1780501849743_b992302e.enc`)
* **Maximum Upload Size**: `50 MB` (enforced via Flask `MAX_CONTENT_LENGTH`)

---

## 3. Client Configuration (Mobile App)

### 3.1 Network Endpoints
* **In-App Configuration**: Can be adjusted via the Settings / Login modal without recompilation.
* **Storage**: Persisted securely in `SharedPreferences` keys:
  * `server_ip`: Target host IP (default: `10.0.2.2` for emulator or local LAN IP).
  * `server_port`: TCP relay port (default: `5000`).

### 3.2 Firebase Cloud Messaging (FCM) — Optional
VeilChat includes optional background push notification support via Firebase Cloud Messaging:
* Configuration file: `android/app/google-services.json`
* Template: `android/app/google-services.json.example`
* Graceful Fallback: If `google-services.json` is not provided or invalid, `FcmService` catches the initialization exception and VeilChat operates using socket-level notifications and local notification fallback without crashing.

### 3.3 WebRTC ICE Servers
Default ICE configuration is located in `lib/services/webrtc_service.dart`:
```dart
final Map<String, dynamic> _iceConfig = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
    {'urls': 'stun:stun2.l.google.com:19302'},
    {'urls': 'stun:stun3.l.google.com:19302'},
    // Free TURN relay servers for symmetric NAT traversal
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
```
Self-hosted TURN servers (e.g., coturn) can be configured by updating this map.
