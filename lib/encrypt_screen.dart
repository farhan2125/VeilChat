import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'veil_components.dart';
import 'veil_theme.dart';
import 'services/crypto_service.dart';

class EncryptScreen extends StatefulWidget {
  final bool isDark;
  final VoidCallback toggleTheme;
  final String sharedKey;
  
  const EncryptScreen({
    super.key, 
    required this.isDark, 
    required this.toggleTheme,
    this.sharedKey = "",
  });

  @override
  State<EncryptScreen> createState() => _EncryptScreenState();
}

class _EncryptScreenState extends State<EncryptScreen> {
  final TextEditingController _mainController = TextEditingController();
  final TextEditingController _passController = TextEditingController();
  final CryptoService _crypto = CryptoService();

  void _handleEncrypt() async {
    String text = _mainController.text;
    String pass = _passController.text.isNotEmpty ? _passController.text : widget.sharedKey;
    if (text.isEmpty) return;
    if (pass.isEmpty) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter a password."))); return; }
    List<int>? encrypted = await _crypto.encrypt(pass, text);
    if (encrypted != null) {
      setState(() { _mainController.text = _crypto.bytesToHex(encrypted); });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Encrypted!")));
    }
  }

  void _handleDecrypt() async {
    String hex = _mainController.text;
    String pass = _passController.text.isNotEmpty ? _passController.text : widget.sharedKey;
    if (hex.isEmpty || pass.isEmpty) return;
    try {
      List<int> bytes = _crypto.hexToBytes(hex);
      String? decrypted = await _crypto.decrypt(pass, bytes);
      if (decrypted != null) {
        setState(() { _mainController.text = decrypted; });
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Decrypted!")));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Wrong Password?")));
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid Hex Data")));
    }
  }

  void _copyToClipboard() {
    Clipboard.setData(ClipboardData(text: _mainController.text));
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Copied")));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    
    return SafeArea(
      child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: VeilHeader(title: "Encrypt", isDark: widget.isDark, icon: Icons.lock_outline),
              ),
              IconButton(
                icon: Icon(widget.isDark ? Icons.wb_sunny : Icons.nightlight_round),
                color: widget.isDark ? Colors.white54 : Colors.black54,
                onPressed: widget.toggleTheme,
              ),
            ],
          ),

          const SizedBox(height: 10),

          ConstrainedBox(
            constraints: BoxConstraints(minHeight: size.height * 0.65),
            child: VeilGlassContainer(
              isDark: widget.isDark,
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    children: [
                      VeilTextField(
                        isDark: widget.isDark,
                        label: "Text / Hex",
                        maxLines: 8,
                        controller: _mainController,
                      ),
                      const SizedBox(height: 5),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: _copyToClipboard,
                          icon: Icon(Icons.copy, size: 14, color: widget.isDark ? Colors.white54 : Colors.black54),
                          label: Text("Copy", style: TextStyle(fontSize: 12, color: widget.isDark ? Colors.white54 : Colors.black54)),
                          style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size(50, 30)),
                        ),
                      ),
                      VeilTextField(
                        isDark: widget.isDark,
                        label: "Password",
                        isPassword: true,
                        prefixIcon: Icons.vpn_key_outlined,
                        controller: _passController,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(child: VeilButton(isDark: widget.isDark, label: "Encrypt", gradient:  [VeilTheme.accentColor, VeilTheme.accentColor.withOpacity(0.7)], onTap: _handleEncrypt)),
                      const SizedBox(width: 10),
                      Expanded(child: VeilButton(isDark: widget.isDark, label: "Decrypt", gradient:  [VeilTheme.accentColor, VeilTheme.accentColor.withOpacity(0.7)], isOutlined: true, onTap: _handleDecrypt)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 80),
        ],
      ),
    ),
    );
  }
}