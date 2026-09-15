# ddev-worktree

A DDEV add-on for managing git worktrees — create fully isolated environments for feature branches, MR reviews, and parallel AI-assisted development sessions, each with their own DDEV instance, database, and URL.

## What it does

| Command | Description |
|---|---|
| `ddev wt-add <branch>` | Create worktree + DDEV + composer install. Auto-creates new branch if it doesn't exist. |
| `ddev wt-ai [<branch>]` | Same as above, then opens the worktree in your AI editor (Cursor / VS Code / PhpStorm). Without a branch: picker over existing worktrees. |
| `ddev wt-remove <name>` | Safely stop DDEV and remove the worktree |
| `ddev wt-repair [name] [--all]` | Re-apply DDEV config to existing worktrees |
| `ddev wt-list [--json]` | Terminal table: all worktrees with DDEV status, branch, URL |
| `ddev wt-status` | Detailed overview — dirty files, unpushed commits, DDEV state per worktree |
| `ddev wt-sync [--env=staging]` | Sync DB from remote + deploy |
| `ddev wt-pull [name\|--all]` | Pull latest remote changes in any worktree without leaving the current one |
| `ddev wt-hooks-install` | Install shared git safety hooks |
| `ddev wt-shell-install` | Install the `wt` shell switcher function |

## Requirements

- [DDEV](https://ddev.com) v1.22+
- Git 2.5+

All commands run on plain Bash (3.2+, so stock macOS works) with the tools DDEV and
Git already provide — no extra runtime is required. Two optional tools enhance
specific commands if present:

- [`jq`](https://jqlang.github.io/jq/) or Python 3 — sharper live DDEV status in `wt-list`/`wt-status` (falls back gracefully if neither is installed)
- [`fzf`](https://github.com/junegunn/fzf) — arrow-key navigation in the `wt` switcher (falls back to a numbered list)

## Install

The add-on isn't on the public DDEV registry yet, so `ddev add-on get <owner>/ddev-worktree`
doesn't work — install it from the internal GitLab source instead. `ddev add-on get`
can't fetch an arbitrary git URL directly (it expects a real tarball response, and a
plain `.git` URL doesn't serve one — you'll get `gzip: invalid header` if you try),
so clone first and point it at the local copy:

```bash
#!/usr/bin/env bash
set -euo pipefail

addon_repo="git@internal.dropsolid.com:dropsolid-agency/ddev-addons/ddev-worktree.git"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# -o BatchMode=yes: fail fast instead of hanging on an unanswerable prompt
# (unknown host key, or a passphrase-protected key with no TTY in this context)
GIT_SSH_COMMAND="ssh -o BatchMode=yes -o ConnectTimeout=15" \
  git clone --depth=1 "$addon_repo" "$tmp_dir/addon"

ddev add-on get "$tmp_dir/addon"
ddev restart
ddev wt-hooks-install   # git safety hooks
ddev wt-shell-install   # wt shell switcher
```

To pin a specific release instead of whatever's newest on `master`, add
`--branch v0.2.0` to the `git clone` line (see available tags with
`git ls-remote --tags git@internal.dropsolid.com:dropsolid-agency/ddev-addons/ddev-worktree.git`).

If `git clone` hangs rather than failing, it's almost always the SSH connection, not
the add-on: verify with `ssh -v -o ConnectTimeout=10 -o BatchMode=yes -T git@internal.dropsolid.com`
first — that fails fast and tells you whether it's an unreachable host (check VPN),
an unaccepted host key (connect once interactively to accept it), or a
passphrase-protected key with no terminal to prompt on (`ssh-add` it first).

A `.ddev/worktree.yaml` config file is auto-generated on first use. Review it and adjust `project_name` if the Drush alias differs from the repo name.

### Git status stays clean

The install appends a marker-guarded block to the project's `.gitignore` covering
everything the add-on puts in `.ddev/` (the `wt-*` commands, `worktree-hooks/`,
`worktree-lib/`, `worktree-shell/`, `worktree-templates/`, `worktree.yaml`, and
its own `addon-metadata/ddev-worktree/` entry) — so `ddev add-on get` never
leaves the repo dirty. The add-on is treated as personal developer tooling by
default.

**To ship the add-on with the project instead** (the standard DDEV convention —
teammates then get the commands via git), delete that block from `.gitignore`
and commit the files.

## One-time setup: private Composer credentials

If your projects pull packages from a private GitLab registry (e.g. `gitlab.internal.dropsolid.com`), set this up once on your machine. It will work for every DDEV project — including every new worktree — without any per-project steps.

DDEV mounts `~/.ddev/homeadditions/` into every container's home directory. A symlink from there to your global Composer `auth.json` is all that's needed.

**1. Create the auth file in DDEV's global homeadditions directory:**

```bash
mkdir -p ~/.ddev/homeadditions/.composer
```

Then create `~/.ddev/homeadditions/.composer/auth.json` with your token:

```json
{
    "gitlab-token": {
        "gitlab.internal.dropsolid.com": "YOUR_PERSONAL_ACCESS_TOKEN"
    }
}
```

Get a token at: `https://gitlab.internal.dropsolid.com/-/user_settings/personal_access_tokens`
Required scope: **`read_api`**

**2. Verify it's visible inside containers:**

```bash
# In any running DDEV project
ddev ssh -c "cat ~/.composer/auth.json"
```

The token is stored in one place. Updating the file propagates to all DDEV
containers automatically on next start — no per-project setup ever needed.

> **If you also have Composer installed on the host** (e.g. on macOS via Homebrew),
> you can keep a single source of truth by symlinking instead:
> ```bash
> ln -sf "$(composer config --global home)/auth.json" \
>        ~/.ddev/homeadditions/.composer/auth.json
> ```

## Prerequisites — make DDEV hostname-agnostic

Before using worktrees, make your project portable:

1. **Remove `name:` from `.ddev/config.yaml`** — DDEV uses the directory name automatically.
2. **Loosen `trusted_host_patterns`** so it matches every worktree's hostname, not just
   the main project's — see [Trusted host patterns across worktrees](#trusted-host-patterns-across-worktrees) below.
3. **Replace hardcoded domain strings** with `$_ENV['DDEV_PRIMARY_URL']` or `$_ENV['DDEV_HOSTNAME']`.

### Trusted host patterns across worktrees

Each worktree runs as its own DDEV project — `wt-<branch-name>.ddev.site` — a different
hostname than the main project's. If `trusted_host_patterns` only allows the main
project's exact hostname, every worktree fails at the application layer with:

> The provided host name is not valid for this server.

even though DDEV itself is running fine — this is Drupal rejecting the `Host` header,
not a DDEV or add-on problem.

On Dropsolid projects this setting typically lives in
`etc/drupal/additional_settings.local.php`. That file is gitignored and **copied fresh
into every worktree from the root project's copy** (same per-environment convention as
`.ddev/drupal/`), so fixing it once in the main checkout's copy is enough to cover every
worktree created afterwards. Worktrees that already exist need the same fix applied to
their own copy of the file (or need to be recreated).

```php
// Trusted host
$settings['trusted_host_patterns'] = [
  '^ds\-myproject\.ddev\.site$',   // main project — keep the trailing $ anchor
  '^wt\-.+\.ddev\.site$',          // every worktree (matches worktree_prefix: 'wt')
  '^localhost$',
];
```

The `wt-` prefix matches `worktree_prefix` in `.ddev/worktree.yaml` (default `'wt'`) —
update the pattern if you've changed that setting. No `ddev restart` needed after
editing; just reload the worktree's URL.

## Branch modes

`wt-add` (and `wt-ai`) detect the branch situation automatically:

| Scenario | Command | What happens |
|---|---|---|
| Track existing remote branch | `ddev wt-add feature/VREEMDEVO-57` | Checks out from `origin/feature/VREEMDEVO-57` |
| Create new branch from main | `ddev wt-add feature/DS-123` | Creates new local branch from HEAD |
| Create new branch from develop | `ddev wt-add feature/DS-123 --from=develop` | Creates from `develop` |
| Relative path + branch | `ddev wt-add ../review origin/epic/branch` | Create worktree in `../review` |
| Absolute path + branch | `ddev wt-add /var/www/custom feature/DS-123` | Create worktree at absolute path |
| Custom folder name | `ddev wt-add my-folder feature/DS-123` | Create in existing **empty** `my-folder/` directory |

New branches are local until you push: `git push -u origin feature/DS-123`

### Custom paths and folders

The improved argument parser supports flexible path specifications:

- **Auto-derived paths** (default): `ddev wt-add feature/DS-123` → `worktrees/feature-DS-123/`
- **Relative paths**: `ddev wt-add ../sibling-path origin/branch`
- **Absolute paths**: `ddev wt-add /var/www/external feature/branch`
- **Existing directories**: `ddev wt-add custom-folder feature/branch` (if `custom-folder/` exists and is empty)
- **Absolute `worktrees_dir` in config**: Set `worktrees_dir: '/var/www/worktrees'` in `.ddev/worktree.yaml`

For absolute paths, the parent directory must exist before running `wt-add`.

## Typical workflow

```bash
# New branch (local) — good for starting fresh work
ddev wt-add feature/DS-123
ddev wt-add feature/DS-123 --from=develop    # branch from develop

# Existing remote branch — good for reviews / QA
ddev wt-add feature/VREEMDEVO-57

# Custom locations
ddev wt-add /var/www/external feature/DS-123      # absolute path
ddev wt-add ../sibling-review origin/epic/branch  # relative path

# AI session — creates worktree + opens it in Cursor/VS Code automatically
ddev wt-ai feature/DS-123

# In your main project directory
ddev wt-add feature/DS-123
# → creates worktrees/feature-DS-123/
# → sets up DDEV (wt-feature-DS-123.ddev.site)
# → runs composer install automatically

# Sync the database
ssh-add ~/.ssh/id_rsa_dropsolid       # load SSH key once per session
cd worktrees/feature-DS-123
ddev wt-sync                    # DB from staging
ddev wt-sync --env=live         # DB from live

# Switch between worktrees
wt                                    # interactive picker (arrow keys + Enter)
wt 123                                # partial match
wt main                               # back to main checkout
wt ls                                 # list all with status

# See everything at a glance
ddev wt-list
ddev wt-status                  # per-worktree details

# Remove when done
wt main
ddev wt-remove feature-DS-123
```

## The `wt` shell switcher

Install once, use everywhere:

```bash
ddev wt-shell-install           # auto-detects fish / bash / zsh
```

| Command | Action |
|---|---|
| `wt` | Interactive picker — arrow keys + Enter (requires fzf) or numbered list |
| `wt 57` | Partial match on name or branch → `feature-VREEMDEVO-57` |
| `wt main` | Jump to main checkout |
| `wt 2` | Jump by number |
| `wt ls` | List all worktrees with current indicator |

Install fzf for arrow-key navigation:
```bash
sudo apt install fzf     # or brew install fzf
```

## Project configuration

`.ddev/worktree.yaml` (auto-generated, gitignored):

```yaml
project_name: 'myproject'       # Drush alias prefix: @myproject.staging
default_env: 'staging'          # Default remote for ddev wt-sync
ssh_key: '~/.ssh/id_rsa_dropsolid'  # Only this key is loaded for wt-sync (optional)
protected_branches:             # Push confirmation — entries EXTEND the built-in defaults
  - main
  - master
  - develop
  - production
  - staging
worktree_prefix: 'wt'           # DDEV project name prefix: wt-feature-DS-123
worktrees_dir: 'worktrees'      # Relative to project root, or absolute path like '/var/www/worktrees'

# Optional: .ddev files/dirs your project regenerates per environment via a
# pre-start hook (e.g. Dropsolid's `ddp`). The add-on won't symlink/copy these —
# the hook recreates them in each worktree. Omit if you have no such generator.
generated_ddev_files:
  - docker-compose.drupal.yaml
  - drupal
```

**Notes**:
- `worktrees_dir` supports absolute paths — set it to `/var/www/worktrees` to store worktrees outside the project.
- `generated_ddev_files` prevents conflicts with project generators that **write** `.ddev` files on start. Symlinking a file the generator wants to overwrite breaks it (e.g. ddp's `Failed to copy … docker-compose.drupal.yaml`); listing it here lets the generator own it.

## How `.ddev` is managed in worktrees

`.ddev/` is gitignored so worktrees don't have it. `wt-add` creates it with:

| Item | Strategy | Why |
|---|---|---|
| `config.yaml`, `php/` | **Symlink** to main | PHP version changes propagate automatically |
| `docker-compose.*.yaml` | **Symlink** to main | Service config changes propagate |
| `worktree.yaml` | **Symlink** to main | `wt-sync` and the git hooks read `project_name` / `protected_branches` from inside the worktree |
| `drupal/`, `varnish/` | **Copy** from main | Docker volume sources must be real local files |
| `config.local.yaml` | **Generated** fresh | Unique project name **and** a self-scoped `*.<name>` wildcard hostname per worktree |
| `host/` commands | **Symlink** to main | Run on the host, where a symlink to main resolves; updates propagate automatically |
| `web/` & service commands | **Copy** from main | Run *inside* a container where main's path isn't mounted — a symlink would dangle (`deploy: No such file or directory`) |
| files in `generated_ddev_files` | **Skipped** | The project's pre-start hook (e.g. ddp) regenerates them per worktree |

### Subdomains (admin.*, api.*, …) on a worktree

Dropsolid's main `ds-<project>` DDEV projects typically declare
`additional_hostnames: ["*.ds-<project>"]`, which is why `admin.ds-<project>.ddev.site`
works on the main checkout. `config.yaml` is **symlinked** into every worktree, so
that entry is stuck with the main project's literal name — it can never match a
worktree's own hostname, which is why `admin.wt-<branch>.ddev.site` doesn't work by
default.

`wt-add` and `wt-repair` fix this by generating the equivalent wildcard for each
worktree's *own* name into its `config.local.yaml`:

```yaml
name: wt-feature-DS-123
additional_hostnames:
  - "*.wt-feature-DS-123"
```

So `admin.wt-feature-DS-123.ddev.site`, `api.wt-feature-DS-123.ddev.site`, etc. work
the same way they do on main — no extra config needed for new worktrees.

**Worktrees created before this feature** need one repair + restart to pick it up
(a restart is required either way, so DDEV regenerates the TLS cert to cover the new
hostname pattern):

```bash
ddev wt-repair <name> --restart
```

## Safety hooks

Installed by `ddev wt-hooks-install`. Git hooks live in `.git/hooks/` and are **automatically shared** across all worktrees.

**pre-commit**: Shows a colored context banner (which worktree, which branch) before every commit. Blocks direct commits to `main`/`master`.

**pre-push**:
- Feature branches: requires `y` confirmation
- Protected branches: requires typing the branch name exactly
- Force-push to protected branch: **fully blocked**

Protection is decided per **pushed ref**, not the checked-out branch — so
`git push origin HEAD:main` from a feature branch is caught too. Force pushes are
detected by comparing the remote tip against what you're about to push (a
non-fast-forward update) — not by a fragile flag check — so the block is reliable.
Pushes from a non-interactive context (IDE, CI) skip the prompts but the
force-to-protected block still applies.

The protected list is the built-in defaults (`main master develop production
staging`) **plus** any `protected_branches` entries in `.ddev/worktree.yaml`.

## Sync details

`ddev wt-sync`:

1. Skips `composer install` if `vendor/` is newer than `composer.lock`
2. Runs `ddev auth ssh` to forward SSH keys into the container
3. Dumps env vars via `dxp:env-var:dump` (if the Drush command exists)
4. Syncs DB: `drush sql:sync @project.env @self -y`
5. Runs deploy: `ddev deploy` or `drush updatedb + cache:rebuild`

The environment defaults to `default_env` from `.ddev/worktree.yaml` (falling back
to `staging`); `--env=...` overrides it per run.

### SSH keys

Without configuration, `ddev auth ssh` tries **every** private key in `~/.ssh` and
prompts for each passphrase — declining a prompt for an unrelated key aborts the
auth step and the DB sync fails. If you have multiple keys, tell the add-on which
one this project needs in `.ddev/worktree.yaml`:

```yaml
ssh_key: '~/.ssh/id_rsa_dropsolid'
```

`wt-sync` then runs `ddev auth ssh -f <key>` and you're only ever asked for that
key's passphrase. DDEV's ssh-agent container is shared across all projects and
survives until Docker restarts, so the passphrase is needed at most once per boot.

## AI-assisted parallel development

```
main checkout          worktrees/feature-A     worktrees/feature-B
      │                        │                       │
vreemdelingenrecht.ddev.site   wt-feature-A.ddev.site  wt-feature-B.ddev.site
      │                        │                       │
  Your work               AI agent #1             AI agent #2
```

Open each worktree in a **separate IDE window** so Claude Code and other tools only see the intended branch. `wt-add` is blocked from inside a worktree (nesting prevention via `.git` file vs directory check).

## Claude Code Integration

### Automatic Context Generation

`wt-add` writes a `CLAUDE.local.md` file into the root of every new worktree.
Claude Code loads this file automatically at session start (unlike arbitrary
files in `.claude/`, which it does not read on its own). It contains:

- Which worktree and branch this is (and that it is NOT the main checkout)
- The worktree's DDEV URL and how to sync its database
- Your project instructions (see below)

The file is added to `.git/info/exclude` — which is shared across all worktrees —
so it never shows up in `git status`, regardless of what each branch's
`.gitignore` contains.

Example workflow:
```bash
# Create worktree for AI work
ddev wt-ai feature/DS-123

# Claude automatically knows:
# - It's in worktree: feature-DS-123
# - Commits go to: feature/DS-123
# - DDEV URL: https://wt-feature-DS-123.ddev.site
# - How to sync the DB, run tests, etc.
```

### Customizing Claude Instructions

The project-instructions part of the generated `CLAUDE.local.md` comes from,
in order of priority:

1. **Main project**: `.claude/instructions.md` in the main checkout (create it to customize)
2. **Template**: `.ddev/worktree-templates/claude/instructions.md` (shipped with the add-on)

You can also edit `CLAUDE.local.md` directly in any worktree — it is never
overwritten after creation.

### Best Practices for Claude Code

1. **One worktree per Claude session**
   ```bash
   ddev wt-ai feature/task-1    # Claude works here
   ddev wt-ai feature/task-2    # Another Claude session
   ```

2. **Open each worktree in its own IDE window** so the AI agent only sees the
   intended branch.

3. **Clean up when done**
   ```bash
   ddev wt-remove feature-task-1
   ```

## Troubleshooting

### CLAUDE.local.md not created
**Solution**: Check the template exists at `.ddev/worktree-templates/claude/instructions.md`

The worktree context block is always written; only the project-instructions part
depends on the template (or `.claude/instructions.md` in the main checkout).
Re-run `ddev wt-add` after reinstalling the add-on if the template is missing.

### wt-ai doesn't open editor
**Solution**: Set `WORKTREE_EDITOR` environment variable or install supported editor

```bash
# Set preferred editor
export WORKTREE_EDITOR=cursor    # or code, phpstorm, windsurf

# Or install a supported editor
# cursor: https://cursor.sh
# code: https://code.visualstudio.com
# phpstorm: https://www.jetbrains.com/phpstorm/
```

### Worktree already exists / stale directory in the way
**Solution**: `wt-add` tells you which case you hit:

- Registered worktree → `ddev wt-repair <name>` (re-apply DDEV config) or `ddev wt-remove <name>`
- Leftover non-empty directory → remove it and run `git worktree prune`

### "The provided host name is not valid for this server" on a worktree URL
**Solution**: See [Trusted host patterns across worktrees](#trusted-host-patterns-across-worktrees) —
`trusted_host_patterns` needs a pattern covering `wt-*.ddev.site`, typically in
`etc/drupal/additional_settings.local.php` on Dropsolid projects.

### Custom protected branches don't seem protected
**Solution**: Reinstall the hooks so they pick up the fixed config parser:

```bash
ddev wt-hooks-install --force
```

Entries in `protected_branches` extend the defaults (`main master develop
production staging`); the hooks read them from `.ddev/worktree.yaml` (symlinked
into each worktree).

## Sources

- [DDEV blog: git worktrees for contributor training](https://ddev.com/blog/git-worktree-contributor-training/) — Randy Fay
- [processwire-ddev-worktree](https://github.com/webmanufaktur/processwire-ddev-worktree) — symlink + copy strategy reference
- [Confluence: Running multiple versions with git worktrees and DDEV](https://dropsolid.atlassian.net/wiki/spaces/CKH/pages/3124166672/)
