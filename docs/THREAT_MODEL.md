# LifeVault Threat Model

## Threats Identified
- Device theft
- Unauthorized access to application files
- Compromised cloud accounts
- Compromised backend administrators
- Database and object-storage exposure
- Lost devices
- Revoked devices
- Forgotten recovery credentials
- Malicious or corrupted synchronization messages
- Backup and deletion limitations

## Security Principles
- Document encryption separate from account authentication
- Use established cryptographic libraries (libsodium/cryptography)
- Authenticated encryption with unique nonces
- Keys protected by platform-backed secure storage
- Zero-knowledge design where possible
- Never log private keys, plaintext documents, auth tokens, or sensitive text
- End-to-end encryption for document contents
