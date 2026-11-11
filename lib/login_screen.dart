import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'branding/veil_brand.dart';
import 'services/group_service.dart';
import 'services/media_service.dart';
import 'services/network_service.dart';
import 'veil_components.dart';
import 'veil_feedback.dart';
import 'veil_theme.dart';

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

  @override
  void initState() {
    super.initState();
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
    if (!mounted) return;
    setState(() {
      _serverIP = prefs.getString('server_ip') ?? "192.168.100.6";
      _serverPort = prefs.getString('server_port') ?? "5000";
      MediaService.updateBaseUrl(_serverIP);
    });
  }

  void _showServerSettings() {
    final ipCtrl = TextEditingController(text: _serverIP);
    final portCtrl = TextEditingController(text: _serverPort);
    String? pingStatus;
    bool pinging = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: isDark ? VeilBrand.veilSlate : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            "Server Config",
            style: TextStyle(color: isDark ? Colors.white : Colors.black),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: ipCtrl,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  decoration: const InputDecoration(labelText: "Server IP"),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: portCtrl,
                  keyboardType: TextInputType.number,
                  style: TextStyle(color: isDark ? Colors.white : Colors.black),
                  decoration: const InputDecoration(labelText: "Port"),
                ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: pinging
                      ? null
                      : () async {
                          setDialogState(() {
                            pinging = true;
                            pingStatus = 'Testing TCP socket...';
                          });
                          final sw = Stopwatch()..start();
                          try {
                            final port =
                                int.tryParse(portCtrl.text.trim()) ?? 5000;
                            final sock = await Socket.connect(
                              ipCtrl.text.trim(),
                              port,
                              timeout: const Duration(milliseconds: 2500),
                            );
                            sw.stop();
                            sock.destroy();
                            setDialogState(() {
                              pinging = false;
                              pingStatus =
                                  '✅ Reachable (${sw.elapsedMilliseconds} ms)';
                            });
                          } catch (_) {
                            setDialogState(() {
                              pinging = false;
                              pingStatus =
                                  '❌ Unreachable — check IP/port & firewall';
                            });
                          }
                        },
                  icon: const Icon(Icons.network_check_rounded, size: 16),
                  label: Text(pinging ? "Pinging..." : "Test Connection"),
                ),
                if (pingStatus != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    pingStatus!,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: pingStatus!.startsWith('✅')
                          ? VeilBrand.success
                          : VeilBrand.warning,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () async {
                final prefs = await SharedPreferences.getInstance();
                final nextIp = ipCtrl.text.trim();
                final nextPort = portCtrl.text.trim();
                await prefs.setString('server_ip', nextIp);
                await prefs.setString('server_port', nextPort);
                if (mounted) {
                  setState(() {
                    _serverIP = nextIp;
                    _serverPort = nextPort;
                  });
                }
                MediaService.updateBaseUrl(nextIp);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text("Save"),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleAuth(bool isRegister) async {
    if (_userController.text.isEmpty || _passController.text.isEmpty) {
      VeilFeedback.warning(context, "Username and password required");
      return;
    }

    setState(() => _isLoading = true);

    final result = await NetworkService().connectAndAuth(
      _serverIP,
      int.tryParse(_serverPort) ?? 5000,
      _userController.text,
      _passController.text,
      isRegister,
      allowSelfSigned: true,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (result['success'] == true) {
      if (isRegister) {
        VeilFeedback.success(context, "Registered! Please login.");
      } else {
        final sharedKey = _keyController.text.trim();
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
      VeilFeedback.error(context, "${result['msg']}");
    }
  }

  void _handleForgotPassword() {
    VeilFeedback.info(
      context,
      "Contact server administrator to reset password.",
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
                      width: 90,
                      height: 90,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 12),
                    ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [
                          Color(0xFF00d4ff),
                          Color(0xFF7a7cff),
                          Color(0xFFc77dff),
                        ],
                      ).createShader(bounds),
                      child: const Text(
                        "VeilChat",
                        style: TextStyle(
                          fontSize: 34,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    GestureDetector(
                      onTap: _showServerSettings,
                      child: VeilBadge(
                        label: 'RELAY: $_serverIP:$_serverPort',
                        icon: Icons.dns_outlined,
                        color: themeColor,
                        isDark: isDark,
                      ),
                    ),
                    const SizedBox(height: 22),
                    _buildCssInput(
                      "Username",
                      false,
                      textColor,
                      _userController,
                    ),
                    const SizedBox(height: 15),
                    _buildCssInput(
                      "Password",
                      true,
                      textColor,
                      _passController,
                    ),
                    const SizedBox(height: 15),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: themeColor.withValues(alpha: 0.3),
                        ),
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
                    const SizedBox(height: 26),
                    _isLoading
                        ? CircularProgressIndicator(color: themeColor)
                        : Row(
                            children: [
                              Expanded(
                                child: VeilButton(
                                  isDark: isDark,
                                  label: "Login",
                                  gradient: [
                                    themeColor,
                                    themeColor.withValues(alpha: 0.7),
                                  ],
                                  onTap: () => _handleAuth(false),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: VeilButton(
                                  isDark: isDark,
                                  label: "Register",
                                  isOutlined: true,
                                  gradient: [
                                    themeColor,
                                    themeColor.withValues(alpha: 0.7),
                                  ],
                                  onTap: () => _handleAuth(true),
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
              icon: Icon(
                Icons.settings,
                color: isDark ? Colors.white54 : Colors.black54,
              ),
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
        labelStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black45),
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(
            color: isDark ? Colors.white30 : Colors.black26,
          ),
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
                onPressed: () =>
                    setState(() => _isPasswordVisible = !_isPasswordVisible),
              )
            : null,
      ),
    );
  }
}
