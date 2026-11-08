# Installation and Deployment Guide

This guide provides step-by-step instructions for installing, configuring, and running the VeilChat application and its backend services from source.

---

## 1. System Requirements

### Development Host
* **Operating System**: Windows 10/11 (64-bit), macOS, or Linux.
* **Python**: Python 3.10, 3.11, or 3.12.
* **Flutter SDK**: Flutter 3.19.0 or higher (Tested on Flutter 3.41.2 with Dart 3.11.0).
* **Android SDK**: Android API Level 34+ (Build-Tools 34.0.0+).
* **Java Development Kit**: OpenJDK 17 or 21.

### Target Device
* **Platform**: Android 8.0+ (API Level 26+).
* **Architecture**: arm64-v8a, armeabi-v7a, x86_64.
* **Camera & Microphone**: Required for WebRTC VoIP and Video calling.

---

## 2. Backend Setup & Startup

The VeilChat backend consists of two lightweight Python services that run concurrently:
1. **TCP Socket Relay Server** (Port 5000)
2. **Flask HTTP Media Server** (Port 5001)

### Step 2.1: Python Virtual Environment
Open a terminal in the project root:

```bash
# Navigate to the backend directory
cd server

# Create a virtual environment
python -m venv venv

# Activate the virtual environment
# Windows (PowerShell):
.\venv\Scripts\Activate.ps1
# Windows (CMD):
.\venv\Scripts\activate.bat
# Linux / macOS:
source venv/bin/activate
```

### Step 2.2: Install Dependencies
Install the required Python packages:

```bash
pip install -r requirements.txt
```

*(Core dependencies: `flask>=3.0.0`, `bcrypt>=4.0.0`)*

### Step 2.3: Start the Backend Services

#### Option A: One-Click Startup (Windows)
Double-click `server/run_all.bat` or run:
```cmd
server\run_all.bat
```
This spawns both `server.py` (Port 5000) and `media_server.py` (Port 5001) in separate console windows.

#### Option B: Manual Startup
Open two terminal tabs:

**Terminal 1 — TCP Relay Server:**
```bash
python server/server.py
```
*Output: `[*] TCP Relay Server listening on 0.0.0.0:5000`*

**Terminal 2 — HTTP Media Server:**
```bash
python server/media_server.py
```
*Output: `[MEDIA] Listening on 0.0.0.0:5001`*

---

## 3. Mobile Frontend Setup & Startup

### Step 3.1: Install Flutter Packages
From the repository root:

```bash
flutter pub get
```

### Step 3.2: Verify Toolchain
Run Flutter doctor to verify your Android SDK and JDK setup:

```bash
flutter doctor -v
```

### Step 3.3: Configure Server Connection
VeilChat supports dynamic IP configuration directly inside the mobile app:
1. Launch the app on your Android device or emulator.
2. On the **Login Screen**, tap the **Server Config** icon in the header.
3. Enter your backend host IP:
   * **Android Emulator**: `10.0.2.2` (routes to host machine `127.0.0.1`).
   * **Physical Device over Wi-Fi**: Your development PC's local LAN IP (e.g., `192.168.1.50`).
4. Enter the TCP port (`5000`). The Flask media port (`5001`) is configured automatically.

### Step 3.4: Run the Application

#### Debug Mode (Hot Reload enabled):
```bash
flutter run
```

#### Build Release APK:
```bash
flutter build apk --release
```
The output artifact is generated at:
`build/app/outputs/flutter-apk/app-release.apk`

---

## 4. Running Automated Tests

### Python Backend Unit Tests:
```bash
python -m unittest scratch/test_backend.py
```

### Flutter & Cryptography Unit Tests:
```bash
flutter test test/crypto_stego_test.dart
```

### Static Analysis:
```bash
flutter analyze
```
