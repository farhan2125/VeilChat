# Security Policy

## 1. Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 1.0.x   | :white_check_mark: |
| < 1.0   | :x:                |

---

## 2. Reporting a Vulnerability

VeilChat takes communication security and privacy seriously. If you discover a potential security vulnerability, cryptographic weakness, or information disclosure issue in this project, please report it responsibly.

### How to Report
* **Do NOT report security vulnerabilities via public GitHub issues, discussions, or pull requests.**
* Please submit reports privately by creating a [GitHub Private Security Advisory](../../security/advisories/new) or contacting the maintainers directly via email.
* Include a detailed technical description of the vulnerability, step-by-step reproduction instructions, and proof-of-concept payloads or scripts where applicable.

### Response Timeline
* **Initial Acknowledgment**: Within 48 hours of receipt.
* **Triage & Assessment**: Within 5 business days.
* **Patch & Disclosure**: Coordinated release schedule following verification.

---

## 3. Cryptographic Implementation Details

* **End-to-End Encryption**: AES-256-GCM authenticated encryption.
* **Key Derivation**: PBKDF2 with HMAC-SHA256, 10,000 iterations, 16-byte random salt.
* **Steganography**: SHA-256 seeded pseudo-random pixel index shuffling for Red-channel LSB manipulation.
* **Server Knowledge**: Zero-knowledge routing; the central relay acts as a blind postman.

Please review [docs/security-model.md](docs/security-model.md) and [docs/threat-model.md](docs/threat-model.md) for full architectural assumptions.
