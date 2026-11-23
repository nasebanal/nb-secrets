# CLAUDE.md - nb-secrets

One bash script, `bin/nb-secrets`, on top of `age`. MIT (`Copyright (c) 2026 NASEBANAL`). User docs and the terms of use: `README.md`.

## Rules

- **Never write a secret value anywhere**: not in output, tests, fixtures, commit messages or docs. Tests use a test double of `age` (`test/shim/age`) and dummy values only.
- **No `get`.** Do not add a command that prints a value. `compare` (hash) is the way to check one.
- **Do not weaken the terminal requirement** (no `--no-tty`, no environment bypass): the human typing the passphrase is the protection. Tests get a pseudo-terminal from `test/pty.py` instead.
- Keep it dependency-light: bash, `age`, and ordinary POSIX tools. No new runtime dependency without a reason that outweighs "the whole script can be read in one sitting".
- Every command answers `-h` (the usage is the comment block after the shebang). Run `bin/nb-secrets -h`, `test/run.sh` and `shellcheck bin/nb-secrets test/run.sh test/shim/age` before proposing a change; after changing how `age` is called, also run the manual check in `test/INTEGRATION.md` (the test double cannot catch a wrong `age` flag).
- Assistants that cannot run real `age` (for example when `Bash(age:*)` is denied) say so and hand the integration check to the user; they do not look for a way around it.
- Docs are English. Plain ASCII numbering (no circled digits).
- Changes go through pull requests; CI (`test`, `shellcheck`) must pass. Never merge on the user's behalf.
