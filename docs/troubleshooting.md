# Troubleshooting Guide

This guide covers common issues, root causes, and resolutions for VeilChat mobile and backend services.

---

## 1. Network & Server Connection Issues

### 1.1 "Connection failed: Connection refused"
* **Symptom**: App displays connection error when attempting to register or log in.
* **Root Cause**:
  * TCP server on Port 5000 is not running.
  * Target IP in Server Config dialog is incorrect.
  * Android emulator cannot reach host machine `localhost`.
* **Resolution**:
  1. Verify the TCP server is running: `python server/server.py`.
  2. For Android Emulator: Set Server IP to `10.0.2.2` (port `5000`).
  3. For Physical Android Device: Ensure device is on the same Wi-Fi network and use your PC's LAN IP (e.g. `192.168.1.X`). Ensure Windows Defender Firewall allows inbound connections on TCP 5000 and 5001.

### 1.2 "Media Upload / Download Error"
* **Symptom**: Images or voice notes fail to send or download.
* **Root Cause**: Flask server on Port 5001 is stopped or unreachable.
* **Resolution**:
  1. Verify Flask media service: `python server/media_server.py`.
  2. Test health endpoint from terminal or browser: `http://<server-ip>:5001/health`. Should return `{"status": "ok"}`.

---

## 2. WebRTC Calling Issues

### 2.1 Call fails to connect or audio not heard
* **Symptom**: Caller dials Callee, ringing occurs, but media never connects or audio is silent.
* **Root Cause**:
  * Symmetric NAT blocking direct UDP traffic without a reachable TURN server.
  * Missing Android audio/camera permissions.
* **Resolution**:
  1. Ensure both devices have granted Microphone and Camera permissions.
  2. Check default TURN relays in `lib/services/webrtc_service.dart`. If testing across restricted enterprise networks, configure a dedicated `coturn` server.
  3. Toggle speaker / earpiece button in call interface to verify audio route.

---

## 3. Steganography & Image Encoding Issues

### 3.1 "Message too long for this image"
* **Symptom**: StegoService fails when attempting to encode secret text.
* **Root Cause**:
  * The selected carrier image does not have enough pixels to hold the payload.
  * Required capacity formula: $(32 + 8 \times \text{payloadLength}) \le \text{width} \times \text{height}$.
* **Resolution**: Select an image with higher resolution (e.g., minimum 500×500 pixels for short messages, or 1200×1200 for large encrypted texts).

### 3.2 "No hidden message found (wrong password?)"
* **Symptom**: Extraction fails or produces garbage text.
* **Root Cause**:
  * Password supplied for extraction does not match the encoding password.
  * The image was saved or transmitted over a service that applies lossy JPEG re-compression (e.g. standard WhatsApp, Facebook Messenger), corrupting the LSB bit values.
* **Resolution**: Always save and transfer stego-images as uncompressed PNG files (e.g. as a raw document attachment).

---

## 4. Build & Environment Issues

### 4.1 "File google-services.json is missing"
* **Symptom**: Gradle fails during Android build.
* **Resolution**: Copy `android/app/google-services.json.example` to `android/app/google-services.json`.
