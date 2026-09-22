# Contributing to ddev-wt

Thanks for considering a contribution. This add-on is maintained as open
source, and PRs are welcome.

## Origin

`ddev-wt` was originally designed and developed by Milan Gurjanov while working
at Dropsolid and is maintained as an open-source project under the Dropsolid
organization.

The project is licensed under the MIT License. See [`LICENSE`](LICENSE) for the
applicable copyright and license terms.

## Reporting bugs / requesting features

Open a GitHub issue. Include your OS (Linux/macOS), DDEV version, and the
relevant section of `.ddev/worktree.yaml` if the issue is config-related.

## Development setup

There's no build step. All commands are plain Bash (kept compatible with
Bash 3.2 for stock macOS) sourcing the shared helpers in `worktree-lib/lib.sh`.

To test changes locally against a real project:

```bash
ddev add-on get /path/to/your/local/ddev-wt
ddev restart
```

Re-run that after every change, since `ddev add-on get` re-copies the files into
`.ddev/`.

## Pull requests

- Keep changes portable: no GNU-only flags, no Bash 4+ syntax (arrays are fine,
  associative arrays and `${var,,}` are not).
- Run `tests/test.bats` if you touch install/uninstall behavior (`bats tests/`).
- Update `README.md` if you change a command's behavior or add a config option.
- Small, focused PRs are easier to review than large ones.

## Code style

- Shared logic goes in `worktree-lib/lib.sh`, not duplicated across `wt-*`
  commands.
- Prefer explicit error messages (`error "..."` from the shared lib) over
  silent failures.
- Comments should explain *why*, not *what*, since the code should already be
  readable for the *what*.
