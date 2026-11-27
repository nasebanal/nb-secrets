# Security policy

## Scope

`nb-secrets` is a single-user tool that keeps secrets in `age` passphrase-encrypted files and hands them to one command (`run`) or one subshell (`shell`) at a time. Read [Terms of use](README.md#terms-of-use) and [Limits](README.md#limits) first. In particular, it does **not** defend against an attacker who already runs code as you; reports that need that are out of scope.

In scope, for example: a way to make a command print or log a value, to bypass the terminal requirement, to leave plaintext on disk, to read or write outside the intended files, or to corrupt or lose an encrypted file.

## Reporting

Please report privately through GitHub: **Security** tab, **Report a vulnerability** (private vulnerability reporting). Do not open a public issue for a vulnerability, and never include a real secret or passphrase in any report.

This is a small project maintained on a best-effort basis; there is no response-time guarantee.
