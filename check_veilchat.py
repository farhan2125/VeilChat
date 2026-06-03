#!/usr/bin/env python3
"""
VeilChat Diagnostic Tool
Scans Dart files for common bugs and analyzes server logs for issues.
"""

import os
import re
import sys
from pathlib import Path

# ----------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------
DART_DIR = "lib"
SERVER_LOG = "server.log"  # optional, if you capture server output

# ----------------------------------------------------------------------
# Code Issue Patterns
# ----------------------------------------------------------------------
CODE_PATTERNS = [
    {
        "name": "Read-only list assignment (missing List.from)",
        "pattern": r'setState\s*\(\s*\(\s*\)\s*\{\s*_messages\s*=\s*[^L]',
        "file_ext": ".dart",
        "description": "Assigning a query result directly to _messages without List.from can cause 'read-only' error.",
        "fix": "Use _messages = List<Map<String, dynamic>>.from(result);"
    },
    {
        "name": "Missing resizeToAvoidBottomInset",
        "pattern": r'Scaffold\s*\(\s*(?!.*resizeToAvoidBottomInset)',
        "file_ext": ".dart",
        "description": "Scaffold missing resizeToAvoidBottomInset: true – may cause keyboard to squish UI.",
        "fix": "Add resizeToAvoidBottomInset: true to Scaffold."
    },
    {
        "name": "Missing SafeArea in top-level Column",
        "pattern": r'Column\s*\(\s*children:\s*\[\s*Padding\(',
        "file_ext": ".dart",
        "negate": r'SafeArea',
        "description": "Top-level Column without SafeArea may cause text to overlap system UI.",
        "fix": "Wrap Column with SafeArea."
    },
    {
        "name": "Hardcoded color instead of VeilTheme.accentColor",
        "pattern": r'Color\(0x[A-F0-9]{6,8}\)',
        "file_ext": ".dart",
        "description": "Hardcoded color found; consider using VeilTheme.accentColor for theming.",
        "fix": "Replace with VeilTheme.accentColor."
    },
    {
        "name": "Conditional themeColor (isDark ? A : B) instead of VeilTheme.accentColor",
        "pattern": r'isDark\s*\?\s*VeilTheme\.\w+\s*:\s*VeilTheme\.\w+',
        "file_ext": ".dart",
        "description": "Using ternary for theme color – better to set VeilTheme.accentColor once in main_screen.",
        "fix": "Set VeilTheme.accentColor in main_screen and use it directly."
    },
    {
        "name": "Possible missing stream listener for group invites",
        "pattern": r'case\s*[\'"]GRP_INV[\'"]\s*:',
        "file_ext": "group_service.dart",
        "description": "GRP_INV handler missing or incomplete – check group_service.dart.",
        "fix": "Ensure GRP_INV case creates group and saves to DB."
    },
    {
        "name": "Possible missing user list listener",
        "pattern": r'userListStream\.listen',
        "file_ext": "chat_list_screen.dart",
        "negate": r'userListStream\.listen',
        "description": "userListStream listener missing – FIND CONTACTS won't work.",
        "fix": "Add listener in chat_list_screen.dart."
    },
]

# ----------------------------------------------------------------------
# Server Log Analysis Patterns
# ----------------------------------------------------------------------
SERVER_PATTERNS = [
    {
        "name": "Socket timeout",
        "pattern": r"timeout",
        "description": "Server is experiencing socket timeouts – may cause disconnections.",
    },
    {
        "name": "Connection reset",
        "pattern": r"reset",
        "description": "Client connections are being reset – check network stability.",
    },
    {
        "name": "Offline message saved",
        "pattern": r"\[OFFLINE\]",
        "description": "Offline messages are being stored – good.",
    },
    {
        "name": "Offline message delivered",
        "pattern": r"\[DELIVERY\]",
        "description": "Offline messages are being delivered – good.",
    },
    {
        "name": "Unknown packet type",
        "pattern": r"\[UNKNOWN TYPE\]",
        "description": "Server received an unrecognized packet – check packet type strings.",
    },
]

# ----------------------------------------------------------------------
# Scan Dart files
# ----------------------------------------------------------------------
def scan_dart_files():
    issues = []
    dart_files = list(Path(DART_DIR).rglob("*.dart"))
    print(f"Scanning {len(dart_files)} Dart files...")

    for file in dart_files:
        with open(file, "r", encoding="utf-8") as f:
            content = f.read()
        for pattern in CODE_PATTERNS:
            # If pattern has 'negate', we check if the negated pattern is missing
            if "negate" in pattern:
                if not re.search(pattern["negate"], content, re.IGNORECASE):
                    # Check if the main pattern exists
                    if re.search(pattern["pattern"], content, re.IGNORECASE):
                        issues.append((file, pattern))
            else:
                if re.search(pattern["pattern"], content, re.IGNORECASE):
                    issues.append((file, pattern))
    return issues

# ----------------------------------------------------------------------
# Analyze server log
# ----------------------------------------------------------------------
def analyze_server_log():
    if not os.path.exists(SERVER_LOG):
        return None
    with open(SERVER_LOG, "r", encoding="utf-8") as f:
        content = f.read()
    findings = []
    for pattern in SERVER_PATTERNS:
        matches = re.findall(pattern["pattern"], content, re.IGNORECASE)
        if matches:
            findings.append((pattern, len(matches)))
    return findings

# ----------------------------------------------------------------------
# Main
# ----------------------------------------------------------------------
def main():
    print("=" * 60)
    print("VeilChat Diagnostic Tool")
    print("=" * 60)

    # Code scan
    print("\n[1] Scanning Dart code...")
    issues = scan_dart_files()
    if issues:
        print(f"Found {len(issues)} potential issue(s):")
        for file, pattern in issues:
            print(f"  📁 {file}")
            print(f"     ⚠️  {pattern['name']}")
            print(f"     💡 {pattern['description']}")
            print(f"     🔧 Suggested fix: {pattern['fix']}\n")
    else:
        print("  ✅ No common code issues detected (patterns may need refinement).")

    # Server log analysis
    print("\n[2] Analyzing server log...")
    findings = analyze_server_log()
    if findings is None:
        print("  ℹ️  No server.log found. Enable server logging to file for analysis.")
    else:
        if findings:
            print("  Found interesting patterns:")
            for pattern, count in findings:
                print(f"     • {pattern['name']}: {count} occurrence(s)")
                print(f"       {pattern['description']}")
        else:
            print("  ✅ No obvious server issues detected.")

    print("\n" + "=" * 60)
    print("Manual checks recommended:")
    print("  • Test FIND CONTACTS: should show dialog with all users.")
    print("  • Create group while user offline; when they log in, group should appear.")
    print("  • Check keyboard on chat screen: UI should not squish.")
    print("  • Verify colors change with theme toggle.")
    print("=" * 60)

if __name__ == "__main__":
    main()