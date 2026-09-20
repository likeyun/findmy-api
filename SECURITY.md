# Security Policy

## Sensitive data

This project handles highly sensitive Apple Find My runtime data.

Never attach or paste any of the following into a public GitHub issue, pull request, discussion, log, screenshot, or public file:

- account.json
- devices/*.json
- .env
- API tokens
- Apple ID passwords
- 2FA codes
- device passcodes
- iCloud Keychain / escrow credentials

The repository .gitignore excludes the common runtime secret files, but you are still responsible for reviewing changes before committing.

## Reporting a security issue

If you discover a vulnerability, do not publish real credentials, private keys, account sessions, or real location data in a public issue.

When demonstrating a problem, use redacted or synthetic data whenever possible.
