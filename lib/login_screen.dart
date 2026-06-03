import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'veil_theme.dart';
import 'veil_components.dart';
import 'veil_painters.dart';
import 'main_screen.dart';
import 'services/network_service.dart';
import 'services/group_service.dart';
import 'services/media_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  bool isDark = true;
  bool _isPasswordVisible = false;
  bool _isLoading = false;

  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final TextEditingController _keyController = TextEditingController();

  String _serverIP = "192.168.100.6";
  String _serverPort = "5000";

  final _secureStorage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    // Reset accent color to dark default — avoids pink bleed from light theme logout
    VeilTheme.accentColor = VeilTheme.neonBlue;
    _loadSettings();
    GroupService();
  }

  @override
  void dispose() {
    _userController.dispose();
    _passController.dispose();
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _serverIP = prefs.getString('server_ip') ?? "192.168.100.6";
      _serverPort = prefs.getString('server_port') ?? "5000";
      MediaService.updateBaseUrl(_serverIP);
    });
  }

  void _showServerSettings() {
    final ipCtrl = TextEditingController(text: _serverIP);
    final portCtrl = TextEditingController(text: _serverPort);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF0F172A) : Colors.white,
        title: Text(
          "Server Config",
          style: TextStyle(color: isDark ? Colors.white : Colors.black),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ipCtrl,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: const InputDecoration(labelText: "Server IP"),
            ),
            TextField(
              controller: portCtrl,
              style: TextStyle(color: isDark ? Colors.white : Colors.black),
              decoration: const InputDecoration(labelText: "Port"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString('server_ip', ipCtrl.text);
              await prefs.setString('server_port', portCtrl.text);
              setState(() {
                _serverIP = ipCtrl.text;
                _serverPort = portCtrl.text;
              });
              MediaService.updateBaseUrl(ipCtrl.text);
              Navigator.pop(context);
            },
            child: const Text("Save"),
          )
        ],
      ),
    );
  }

  Future<void> _handleAuth(bool isRegister) async {
    if (_userController.text.isEmpty || _passController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Username and password required")),
      );
      return;
    }

    setState(() => _isLoading = true);

    final result = await NetworkService().connectAndAuth(
      _serverIP,
      int.parse(_serverPort),
      _userController.text,
      _passController.text,
      isRegister,
      allowSelfSigned: true,
    );

    setState(() => _isLoading = false);

    if (result['success']) {
      if (isRegister) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Registered! Please login.")),
        );
      } else {
        final sharedKey = _keyController.text.trim();

        // ✅ Load groups from DB now that we know the user
        await GroupService().loadGroups(_userController.text);

        if (mounted) {
          Navigator.pushReplacementNamed(
            context,
            '/main',
            arguments: {
              'isDark': isDark,
              'sharedKey': sharedKey,
              'username': _userController.text,
            },
          );
        }
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("❌ ${result['msg']}")),
      );
    }
  }

  void _handleForgotPassword() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Contact server administrator to reset password.")),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textColor = isDark ? Colors.white : const Color(0xFF222222);
    final themeColor = VeilTheme.accentColor;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Stack(
        fit: StackFit.expand,
        children: [
          Image.asset(
            isDark ? 'assets/images/bg_dark.jpg' : 'assets/images/bg_light.jpg',
            fit: BoxFit.cover,
          ),

          Center(
            child: SingleChildScrollView(
              child: Container(
                width: 340,
                margin: const EdgeInsets.symmetric(horizontal: 20),
                padding: const EdgeInsets.all(30),
                decoration: VeilTheme.glassBox(isDark: isDark),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/logo.png',
                      width: 100,
                      height: 100,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 15),

                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Color(0xFF00d4ff), Color(0xFF7a7cff), Color(0xFFc77dff)],
                      ).createShader(bounds),
                      child: Text(
                        "VeilChat",
                        style: TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 30),

                    _buildCssInput("Username", false, textColor, _userController),
                    const SizedBox(height: 15),

                    _buildCssInput("Password", true, textColor, _passController),
                    const SizedBox(height: 15),

                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        border: Border.all(color: themeColor.withValues(alpha: 0.3)),
                        borderRadius: BorderRadius.circular(10),
                        color: themeColor.withValues(alpha: 0.05),
                      ),
                      child: Column(
                        children: [
                          Text(
                            "SHARED ROOM KEY",
                            style: TextStyle(
                              color: themeColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _keyController,
                            obscureText: true,
                            style: TextStyle(color: textColor),
                            decoration: InputDecoration(
                              hintText: "Enter key (e.g. 'home')",
                              hintStyle: TextStyle(
                                color: isDark ? Colors.white54 : Colors.black45,
                              ),
                              border: InputBorder.none,
                              suffixIcon: Icon(
                                Icons.lock_outline,
                                size: 18,
                                color: isDark ? Colors.white38 : Colors.black38,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 30),

                    _isLoading
                        ? CircularProgressIndicator(color: themeColor)
                        : Row(
                            children: [
                              Expanded(
                                child: Container(
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [themeColor, themeColor.withOpacity(0.7)],
                                    ),
                                    borderRadius: BorderRadius.circular(25),
                                    boxShadow: [
                                      BoxShadow(
                                        color: themeColor.withOpacity(0.3),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: ElevatedButton(
                                    onPressed: () => _handleAuth(false),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.transparent,
                                      shadowColor: Colors.transparent,
                                      padding: const EdgeInsets.symmetric(vertical: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(25),
                                      ),
                                    ),
                                    child: const Text(
                                      "Login",
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 15),
                              Expanded(
                                child: OutlinedButton(
                                  onPressed: () => _handleAuth(true),
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(
                                      color: isDark ? Colors.white30 : Colors.black26,
                                    ),
                                    padding: const EdgeInsets.symmetric(vertical: 16),
                                    shape: const StadiumBorder(),
                                  ),
                                  child: Text(
                                    "Register",
                                    style: TextStyle(color: textColor),
                                  ),
                                ),
                              ),
                            ],
                          ),
                    const SizedBox(height: 20),

                    GestureDetector(
                      onTap: _handleForgotPassword,
                      child: Text(
                        "Forgot password?",
                        style: TextStyle(color: themeColor, fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            top: 50,
            right: 20,
            child: IconButton(
              icon: Icon(Icons.settings, color: isDark ? Colors.white54 : Colors.black54),
              onPressed: _showServerSettings,
            ),
          ),

          Positioned(
            top: 50,
            left: 20,
            child: IconButton(
              icon: Icon(isDark ? Icons.wb_sunny : Icons.nightlight_round),
              color: isDark ? Colors.white : Colors.black,
              onPressed: () => setState(() => isDark = !isDark),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCssInput(
    String hint,
    bool isPass,
    Color textColor,
    TextEditingController controller,
  ) {
    return TextField(
      controller: controller,
      obscureText: isPass && !_isPasswordVisible,
      style: TextStyle(color: textColor),
      decoration: InputDecoration(
        labelText: hint,
        labelStyle: TextStyle(
          color: isDark ? Colors.white54 : Colors.black45,
        ),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: isDark ? Colors.white30 : Colors.black26),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: VeilTheme.neonBlue, width: 2),
        ),
        suffixIcon: (isPass && hint == "Password")
            ? IconButton(
                icon: Icon(
                  _isPasswordVisible ? Icons.visibility : Icons.visibility_off,
                  color: Colors.grey,
                ),
                onPressed: () => setState(() => _isPasswordVisible = !_isPasswordVisible),
              )
            : null,
      ),
    );
  }
}