# Integration check against the real age

`test/run.sh` uses a test double of `age`, so it cannot catch a wrong `age` flag or a change in how `age` behaves. Run this by hand after changing how `nb-secrets` calls `age`, and after upgrading `age`. It uses a throw-away directory and dummy values only; it never touches `~/.secrets`.

```bash
export NB_SECRETS_DIR="$(mktemp -d)"; chmod 700 "$NB_SECRETS_DIR"
NBS="$PWD/bin/nb-secrets"; F="$NB_SECRETS_DIR/it.env.age"
```

Passphrase prompts: use a throw-away one (for example `test`) everywhere, except where stated.

1. Create: `echo 'export TEST1=a' | age -p -o "$F"` (the passphrase twice).
2. List: `$NBS list "$F"` shows `TEST1` and a `-` date. `$NBS list` shows `it.env.age`.
3. Add: `$NBS set "$F" TEST2`: current passphrase, type a value (nothing is echoed), the same passphrase twice. Expect `added: TEST2` and `TEST1`, `TEST2` in the list, with today's date on `TEST2`.
4. Replace: run step 3 again; expect `replaced: TEST2`.
5. Pipe: `echo piped | $NBS set "$F" TEST3`; expect `added: TEST3`.
6. Run: `$NBS run "$F" -- sh -c 'echo "T2=${#TEST2} T3=${#TEST3}"'` prints the value lengths (not the values). Then `echo ${#TEST2}` in your shell prints `0`.
7. Only: `$NBS run --only TEST3 "$F" -- sh -c 'echo "T2=${TEST2:-unset} T3=${TEST3:-unset}"'` prints `T2=unset T3=<value>`.
8. Wrong passphrase: run step 6 and type a wrong passphrase; expect `decrypt failed; command not run` and no output from the command.
9. Delete: `$NBS delete "$F" TEST1`, answer `y`; expect `deleted: TEST1`.
10. Passwd: `$NBS passwd "$F"`: current, new twice (for example `test2`), new once more. Expect `passphrase changed`. Then `$NBS list "$F"` with `test` fails and with `test2` works.
11. Stale: `$NBS list --stale 90 "$F"` flags nothing older (all dated today) but exits 1 for any undated line; `echo $?` after it.
12. Compare: `printf 'export TEST2=<the value you typed>\n' > old.env`, then `$NBS compare old.env "$F"` shows `TEST2  OK`. Delete `old.env`.
13. Doctor: `$NBS doctor` (with `NB_SECRETS_DIR` still set) is clean for the directory.
14. Modes: `ls -ld "$NB_SECRETS_DIR"; ls -l "$F"` show `drwx------` and `-rw-------`; no `it.env.age.new` is left.
15. Clean up: `rm -r "$NB_SECRETS_DIR"; unset NB_SECRETS_DIR`.

Any step that differs from what is written here is a bug: report it with the step number (never with a value).
