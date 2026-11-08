# Contributing to VeilChat

Thank you for your interest in contributing to VeilChat! We welcome contributions that improve code quality, strengthen security, expand test coverage, and enhance user experience.

---

## 1. Code of Conduct

All contributors and participants are expected to adhere to the [Code of Conduct](CODE_OF_CONDUCT.md).

---

## 2. Development Workflow

1. **Fork the Repository**: Create a fork under your GitHub account.
2. **Branching**: Create a feature branch off `main`:
   ```bash
   git checkout -b feature/your-feature-name
   ```
3. **Local Setup**:
   * Follow the steps in [docs/installation.md](docs/installation.md) to set up the Python backend and Flutter mobile client.
4. **Code Quality**:
   * Ensure Flutter code conforms to project analysis rules:
     ```bash
     flutter analyze
     ```
   * Run unit tests:
     ```bash
     flutter test
     python -m unittest scratch/test_backend.py
     ```
5. **Commit Conventions**: Use conventional commits (`feat: ...`, `fix: ...`, `docs: ...`, `test: ...`, `refactor: ...`).
6. **Submit a Pull Request**: Provide a clear description of changes, motivation, and verification steps in the pull request description.

---

## 3. Cryptography Guidelines

VeilChat enforces strict standards on security modules:
* Do not alter cryptographic parameters (`_kdfIterations`, salt/nonce lengths, cipher modes) without prior architectural review and backward compatibility testing.
* Avoid logging plaintext secrets, keys, or decrypted byte streams.
* Use background isolates (`compute`) for CPU-heavy cryptographic operations.
