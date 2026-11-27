# NASEBANAL Secrets

Keep secrets in passphrase-encrypted files and hand them to a command only when you type the passphrase. One small bash script on top of [age](https://github.com/FiloSottile/age); no server, no account, no key files.

## 📋 Table of Contents

- [Overview](#overview)
- [Requirements](#requirements)
- [Terms of use](#terms-of-use)
- [Getting Started](#getting-started)
- [Commands](#commands)
- [File format](#file-format)
- [Limits](#limits)
- [Testing](#testing)
- [Security](#security)
- [License](#license)

## 🚀 Overview

Plaintext `.env` files and shell profiles are where secrets leak: into a repository, a backup, a screen share, or a tool (an AI coding agent, an editor plugin) that can read your files. `nb-secrets` moves them into files that are useless without a passphrase, and makes every use a deliberate step:

- **Encrypted at rest**: each secret file is `age -p` (passphrase, scrypt) encrypted, one passphrase per file, kept in your password manager. The plaintext never touches the disk when you create or change a file.
- **Used by hand**: `nb-secrets run` decrypts in memory, exports the variables to one command only, and leaves nothing in your shell. It refuses to run without an interactive terminal, because the passphrase is asked for there.
- **A shell for longer tasks**: `nb-secrets shell` asks once and opens a subshell that has the variables until you `exit`. Your current shell is never changed.
- **No way to print a value**: there is deliberately no `get`. A value on screen ends up in terminal logs and screen shares. To check a value, `compare` its hash with the old source.
- **Least privilege**: `run --only NAME,...` passes a command just the variables it needs.
- **Rotation reminders**: `set` stamps each line with the date; `list --stale 90` flags the old and undated ones.
- **Health check**: `doctor` verifies permissions, stray plaintext and a few related settings without decrypting anything.

## 📦 Requirements

### Platform
- macOS or Linux

### Commands
- [`age`](https://github.com/FiloSottile/age) 1.1 or later (passphrase mode); developed with 1.3.2. **Required**: `nb-secrets` does the file handling, `age` does the cryptography. `brew install age`, or your distribution's package.
- `bash` 4 or later is recommended; developed and tested with 5.3. (macOS ships bash 3.2 as `/bin/bash`: use `brew install bash`.)
- Ordinary tools: `sed`, `awk`, `grep`, `sort`, `comm`, `cut`, `date`, `stat`, and `shasum` or `sha256sum`.
- `git` (optional): only `doctor` uses it, to check `credential.helper`.

### Environment
- `NB_SECRETS_DIR` (optional): where `list` looks and `doctor` checks. Default `~/.secrets`.

## ⚖️ Terms of use

`nb-secrets` is only as safe as the way it is used. It assumes all of the following:

1. **A person types the passphrase on an interactive terminal.** Commands that decrypt refuse to run without a tty. Do not work around that (for example by feeding the passphrase from a script): the human step is the protection.
2. **One passphrase per file, kept in a password manager.** There is no recovery: a lost passphrase is a lost file. Keep the master copy of every value in the password manager; the encrypted files are working copies for pushing values to where they are used.
3. **The directory is private**: `~/.secrets` mode `700`, files `600` (`nb-secrets doctor` checks it). Do not put plaintext files in it.
4. **You trust the commands you run with `run`**, and everything you start inside `shell`. They receive the variables in their environment, and any child process they start does too.
5. **You trust the files you `source`.** A secret file is shell code; `run` and `compare` execute it. Do not use a file you did not write or a value you do not control.
6. **You understand the [Limits](#limits).** This protects against accidents and casual reads. It does not protect against an attacker who already runs as you.

## 🛠 Getting Started

```bash
# 1. install age (once)
brew install age

# 2. put the script on your PATH
git clone https://github.com/nasebanal/nb-secrets.git
nb-secrets/bin/nb-secrets --install      # links it into ~/.local/bin (or a directory you name); put that on your PATH
                                         # (nb-secrets --uninstall removes that link again)

# 3. create a secret file: paste the lines, then press Ctrl-D (the plaintext never touches the disk)
mkdir -m 700 -p ~/.secrets
age -p -o ~/.secrets/deploy.env.age
#   export API_TOKEN='xxxxxxxx'
#   export DB_PASSWORD='yyyyyyyy'
chmod 600 ~/.secrets/deploy.env.age

# 4. use it
nb-secrets list ~/.secrets/deploy.env.age                      # names and dates, never values
nb-secrets run ~/.secrets/deploy.env.age -- ./deploy.sh        # the command gets the variables
nb-secrets run --only API_TOKEN ~/.secrets/deploy.env.age -- ./call-api.sh
nb-secrets shell ~/.secrets/deploy.env.age                     # a subshell with the variables; exit to leave
nb-secrets set ~/.secrets/deploy.env.age NEW_TOKEN             # add or replace (the value is typed hidden)
nb-secrets doctor
```

With the [`nb` command](https://github.com/nasebanal/nb-cli) (0.15.0 or later) installed, every command above also runs as `nb secrets ...` (`nb` runs `nb-<name>` from your PATH), and `nb -h` lists it: `nb secrets list ~/.secrets/deploy.env.age` is the same as `nb-secrets list ~/.secrets/deploy.env.age`. `nb-secrets` itself needs neither `nb` nor Node. Tab completion (`nb secrets <TAB>`, and the `.age` files after `run` / `list` / `set`) needs one line in `~/.zshrc`, after `compinit`: `source <(nb completion zsh)` (nb 1.1.0 or later; see [Tab completion](https://github.com/nasebanal/nb-cli#tab-completion)). It lists names only: nothing is decrypted.

Moving from a plaintext shell file you already use: encrypt it (`age -p -o ~/.secrets/x.env.age < old.env`), then `nb-secrets compare old.env ~/.secrets/x.env.age` and expect `OK` on every line before you delete the old file.

## 📖 Commands

Every command answers `-h` / `--help` (`nb-secrets run -h`) with its own usage; no passphrase is asked. Only the word right after the command counts, so in `run <file.age> -- <command> -h` the `-h` goes to `<command>`.

| Command | What it does |
|---|---|
| `run [--only NAME,...] <file.age> -- <command>` | Decrypt in memory and run the command with the variables exported to it only. Stops if decryption fails or the file is empty. `--only` passes just the named variables and stops if one is missing |
| `shell [--only NAME,...] <file.age>` | Open `$SHELL` as a subshell that has the variables; `exit` drops them. For several commands in a row without retyping the passphrase. Refuses to nest. See [The secrets shell](#the-secrets-shell) |
| `list [--stale DAYS] [file.age]` | Without a file: the `.age` files in the directory (no passphrase). With a file: variable names and the date each was last written; `--stale` flags older or undated ones and exits 1 |
| `set <file.age> NAME` | Add or replace one variable. The value is typed hidden, or read from the first line of stdin when piped; never an argument. Creates the file if it does not exist |
| `delete <file.age> NAME` | Remove one variable after a y/N prompt |
| `passwd <file.age>` | Change the passphrase: current, new twice, new once more to verify; replaces the file only if the re-read content matches |
| `compare <old-shell-file> <file.age>` | Per variable: `OK` / `DIFF` / `MISSING-IN-OLD` by SHA-256 of the values; prints no value |
| `--install [DIR]` | Link this script into `DIR` (default `~/.local/bin`) so `nb-secrets` is on your PATH. A symlink, so `git pull` updates it; it never replaces a file or link it did not make, and prints the line to add to your shell if `DIR` is not on your PATH |
| `--uninstall [DIR]` | Remove that link from `DIR` (default `~/.local/bin`). It removes only a link that points to this script, never a file or another program's link, and says so when there is nothing to remove. Your encrypted files are not touched. |
| `doctor` | Check permissions, stray plaintext, leftover temp files, `~/.secrets.env`, Claude Code deny rules (if installed) and git `credential.helper`, without decrypting |

`nb-secrets -h` lists the commands and the options of every command; a command's own options and its full description are in `nb-secrets <command> -h`. There is deliberately no `get`: a value on screen ends up in terminal logs and screen shares (to check a value, compare it with its source with `compare`).

`set`, `delete` and `passwd` re-encrypt the file, so `age` asks for a passphrase again. Use the file's usual one with `set` / `delete`, or the file's passphrase silently changes; `passwd` is the way to change it. The new file is written next to the old one and moved over it only on success, so a failure leaves the original untouched.

### The secrets shell

`run` gives the variables to one command. `shell` widens that to **everything you run until you `exit`**, including package install scripts, editors and AI coding agents started from it. Prefer `run`; when you use `shell`, pass `--only` where you can, exit when the task is done, and do not start tools in it that have no need for the values.

Your shell's startup files run as usual, so an `export` of the same name in them replaces the value from the file.

`NB_SECRETS_ACTIVE` holds the file's name without `.age` / `.env` (characters other than letters, digits, `.`, `_` and `-` become `_`). To show it in a zsh prompt, add this to `~/.zshrc`, after your prompt theme if you use one:

```bash
[[ -n $NB_SECRETS_ACTIVE ]] && PROMPT="(🔐 $NB_SECRETS_ACTIVE) $PROMPT"
```

## 🗂 File format

A secret file is a shell env file, encrypted:

```bash
# deploy credentials
export API_TOKEN='xxxxxxxx'  # updated=2026-11-22
export DB_PASSWORD='yyyyyyyy'
```

- `export NAME=value` or `NAME=value` lines and `#` comments; the content is `source`d, so quote values containing spaces, `$` or `#`.
- `set` appends `# updated=YYYY-MM-DD` to the lines it writes. It is an ordinary comment when sourced; `list` reads it. Lines written by hand have no date (`-`).
- Do not store `PATH`, `HOME`, `SHELL` or `USER` (they would break the command that receives the variables). `set` refuses them; `compare` skips them with a warning.
- Do not keep commented-out old values: they stay encrypted but are still a leak if the file and passphrase ever are.

## ⚠️ Limits

Read this before you trust it:

- **It is not a defence against code already running as you.** A process with your privileges can allocate a pseudo-terminal, read your shell's memory, or watch the process environment of a command or shell started with `run` / `shell`. The terminal requirement and the passphrase stop accidents and casual reads, and they make an unattended read impossible without your passphrase; they do not stop a determined attacker on your account.
- **Values reach the command in its environment.** Anything that can read that process's environment (same user, `ps eww` on some systems, a crash dump) can see them while it runs. With `shell`, that lasts until you `exit`.
- **`age` passphrase mode is only as strong as the passphrase.** Use a long random one from a password manager.
- **No audit trail, no sharing, no access control.** It is a single-user tool for one machine. For teams use a secrets manager.
- **Values already leaked stay leaked.** Deleting a repository or rewriting history does not un-leak a value that was once pushed: rotate it.

## 🧪 Testing

```bash
test/run.sh
```

Needs `python3` (a small pseudo-terminal helper, `test/pty.py`). Runs the whole suite against a test double of `age` (`test/shim/age`: it records the passphrase in the file, it does **not** encrypt) inside a pseudo-terminal, so no real secret and no real passphrase is involved. It covers every command, the refusals (no terminal, wrong passphrase, bad names) and that values never appear in the output.

Cryptography itself is `age`'s. A short manual check against the real `age` is in `test/INTEGRATION.md`; run it after changing how `nb-secrets` calls `age`.

## 🔐 Security

See [SECURITY.md](SECURITY.md) for what is in scope and how to report a vulnerability privately.

## 📄 License

MIT. See [LICENSE](LICENSE).
