#!/usr/bin/env bash
#ddev-generated
# ddev-worktree: shared helper library.
# Sourced (never executed) by the wt-* host commands. All functions must be
# safe under `set -euo pipefail` and portable to bash 3.2 (macOS stock).

# ── Colors & output ───────────────────────────────────────────────────────────
# $'...' so variables hold real escape chars, not the literal string \033.
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
BLUE=$'\033[0;34m'; CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; DIM=$'\033[2m'; NC=$'\033[0m'

info()    { echo -e "${CYAN}  →${NC} $*"; }
success() { echo -e "${GREEN}  ✓${NC} $*"; }
warn()    { echo -e "${YELLOW}  ⚠${NC} $*"; }
error()   { echo -e "${RED}  ✗${NC} $*" >&2; exit 1; }
header()  { echo -e "\n${BOLD}${BLUE}▶ $*${NC}"; }

# ── Paths ─────────────────────────────────────────────────────────────────────

# Portable absolute-path resolver. macOS ships neither GNU `realpath` nor
# `readlink -f`, so resolve via cd + `pwd -P` (works on Linux and macOS).
_wt_realpath() {
  if [[ -d "$1" ]]; then
    ( CDPATH= cd -- "$1" && pwd -P )
  else
    local _d _b
    _d=$(dirname "$1"); _b=$(basename "$1")
    if [[ -d "$_d" ]]; then ( CDPATH= cd -- "$_d" && printf '%s/%s\n' "$(pwd -P)" "$_b" )
    else printf '%s\n' "$1"; fi
  fi
}

# ── Git worktree discovery ────────────────────────────────────────────────────

# Print all registered worktree paths, one per line.
_wt_worktree_paths() {
  { git -C "${1:-.}" worktree list --porcelain 2>/dev/null || true; } \
    | sed -n 's/^worktree //p'
}

# Print the main checkout path (the worktree where .git is a DIRECTORY —
# in every other worktree .git is a file pointing back to the main repo).
# Returns 1 if none is found (not a repo, or a bare-repo layout, which the
# add-on does not support). Callers: MAIN=$(_wt_main_worktree) || error "..."
_wt_main_worktree() {
  local _p
  while IFS= read -r _p; do
    [[ -d "${_p}/.git" ]] && { printf '%s\n' "$_p"; return 0; }
  done < <(_wt_worktree_paths "${1:-.}")
  return 1
}

# Resolve a user-supplied target (name, branch, or path) to a REGISTERED
# worktree path. Branch names use slashes (feature/X) but directories use
# dashes (feature-X), so both forms are tried. Only paths present in
# `git worktree list` are returned — never arbitrary directories, so callers
# can safely run destructive operations on the result.
# Usage: _wt_resolve_worktree <target> <worktrees_dir_abs>
_wt_resolve_worktree() {
  local _target="$1" _wts_dir="$2" _norm _cand _p _bn
  _norm="${_target#origin/}"; _norm="${_norm//\//-}"

  local _registered=()
  while IFS= read -r _p; do _registered+=("$_p"); done < <(_wt_worktree_paths)
  [[ ${#_registered[@]} -eq 0 ]] && return 1

  for _cand in "$_target" "${_wts_dir}/${_norm}" "${_wts_dir}/${_target}" "../${_target}"; do
    [[ -d "$_cand" ]] || continue
    _cand=$(_wt_realpath "$_cand")
    for _p in "${_registered[@]}"; do
      [[ "$(_wt_realpath "$_p")" == "$_cand" ]] && { printf '%s\n' "$_cand"; return 0; }
    done
  done

  for _p in "${_registered[@]}"; do
    _bn=$(basename "$_p")
    [[ "$_bn" == "$_target" || "$_bn" == "$_norm" ]] && { printf '%s\n' "$_p"; return 0; }
  done
  return 1
}

# ── YAML reading (strict subset: top-level scalars + block/flow lists) ────────

# Read a top-level scalar: _wt_yaml_get <file> <key>
_wt_yaml_get() {
  local _file="$1" _key="$2"
  [[ -f "$_file" ]] || return 0
  { grep "^${_key}:" "$_file" 2>/dev/null || true; } | head -1 \
    | sed "s/^${_key}: *//;s/['\"]//g;s/#.*//" | xargs 2>/dev/null || true
}

# Read a top-level list into newline-separated values. Handles the block form
#   key:
#     - val
# and the flow form
#   key: [a, b, c]
# with quotes and trailing comments. Pure bash — no yaml lib.
_wt_yaml_list() {
  local _file="$1" _key="$2" _line _v _rest _e _inlist=0
  [[ -f "$_file" ]] || return 0
  while IFS= read -r _line; do
    if [[ "$_line" == "${_key}:"* ]]; then
      _v="${_line#"${_key}":}"; _v="${_v%%#*}"
      # Flow style: key: [a, b, c] — matched with parameter expansion, not
      # regex, so it behaves identically on bash 3.2 (macOS) and 5.x.
      if [[ "$_v" == *"["*"]"* ]]; then
        _rest="${_v#*\[}"; _rest="${_rest%%\]*},"
        while [[ -n "$_rest" ]]; do
          _e="${_rest%%,*}"; _rest="${_rest#*,}"
          _e=$(printf '%s' "$_e" | xargs 2>/dev/null || true)
          _e="${_e#[\"\']}"; _e="${_e%[\"\']}"
          [[ -n "$_e" ]] && printf '%s\n' "$_e"
        done
        return 0
      fi
      _inlist=1; continue
    fi
    (( _inlist )) || continue
    if [[ "$_line" =~ ^[[:space:]]+-[[:space:]]* ]]; then
      _v="${_line#*- }"; [[ "$_v" == "$_line" ]] && _v="${_line#*-}"
      _v="${_v%%#*}"                          # strip trailing comment
      _v="${_v#"${_v%%[![:space:]]*}"}"       # ltrim
      _v="${_v%"${_v##*[![:space:]]}"}"       # rtrim
      _v="${_v#[\"\']}"; _v="${_v%[\"\']}"    # strip wrapping quote
      [[ -n "$_v" ]] && printf '%s\n' "$_v"
    elif [[ "$_line" =~ ^[^[:space:]#] ]]; then
      _inlist=0                               # next top-level key ends the list
    fi
  done < "$_file"
}

# ── Project configuration ─────────────────────────────────────────────────────

# Load the project's worktree.yaml into globals:
#   WT_PREFIX, WORKTREES_DIR, WORKTREES_DIR_ABS, GENERATED_FILES
# Usage: _wt_load_config <main-worktree-path>
_wt_load_config() {
  local _main="$1" _v
  WT_PREFIX="wt"; WORKTREES_DIR="worktrees"
  _v=$(_wt_yaml_get "${_main}/.ddev/worktree.yaml" worktree_prefix)
  [[ -n "$_v" ]] && WT_PREFIX="$_v"
  _v=$(_wt_yaml_get "${_main}/.ddev/worktree.yaml" worktrees_dir)
  [[ -n "$_v" ]] && WORKTREES_DIR="$_v"
  if [[ "$WORKTREES_DIR" == /* ]]; then
    WORKTREES_DIR_ABS="$WORKTREES_DIR"
  else
    WORKTREES_DIR_ABS="${_main}/${WORKTREES_DIR}"
  fi
  # .ddev entries the project regenerates per-environment (e.g. via a pre-start
  # hook like Dropsolid's ddp). Never symlinked/copied into worktrees.
  GENERATED_FILES="$(_wt_yaml_list "${_main}/.ddev/worktree.yaml" generated_ddev_files)"
}

# True if a .ddev-relative name is in GENERATED_FILES (project-generated, skip it).
_wt_is_generated() {
  [[ -z "${GENERATED_FILES:-}" ]] && return 1
  local _n
  while IFS= read -r _n; do [[ "$_n" == "$1" ]] && return 0; done <<< "$GENERATED_FILES"
  return 1
}

# Generate .ddev/worktree.yaml with a detected project_name.
# Detection order: git remote URL basename → DDEV config name (stripping ds-/
# ddev- prefixes) → directory name. Always writes BLOCK-style lists so every
# parser in the add-on (including the git hooks) can read the result.
# Usage: _wt_generate_config <main-worktree-path> <generator-command-name>
_wt_generate_config() {
  local _main="$1" _by="${2:-ddev-worktree}" _detected="" _remote_url _ddev_name
  _remote_url=$(git -C "$_main" remote get-url origin 2>/dev/null || true)
  [[ -n "$_remote_url" ]] && _detected=$(basename "$_remote_url" .git)
  if [[ -z "$_detected" ]]; then
    _ddev_name=$(_wt_yaml_get "${_main}/.ddev/config.yaml" name)
    _detected=$(printf '%s' "$_ddev_name" | sed 's/^ds-//;s/^ddev-//')
  fi
  [[ -z "$_detected" ]] && _detected=$(basename "$_main")

  cat > "${_main}/.ddev/worktree.yaml" <<EOF
# Auto-generated by ddev ${_by}. Review and adjust as needed.

# Drush alias prefix used for DB sync: @${_detected}.staging etc.
project_name: '${_detected}'

# Default remote environment to sync from
default_env: 'staging'

# SSH key wt-sync loads into DDEV's ssh-agent (ddev auth ssh -f <key>).
# Set this if you have multiple keys in ~/.ssh and get passphrase prompts for
# unrelated ones. Leave commented to load all keys (DDEV default behavior).
# ssh_key: '~/.ssh/id_rsa_dropsolid'

# Branches requiring explicit push confirmation (pre-push hook).
# Entries here EXTEND the built-in defaults (main master develop production staging).
protected_branches:
  - main
  - master
  - develop
  - production
  - staging

# DDEV project name prefix: wt-feature-DS-123.ddev.site
worktree_prefix: 'wt'

# Where worktrees are stored (relative to project root, or absolute path)
worktrees_dir: 'worktrees'

# .ddev/ files & dirs your project regenerates per environment (e.g. via a
# pre-start hook like Dropsolid's 'ddp'). The add-on will NOT symlink/copy these
# into worktrees — the hook recreates them. Uncomment if your project uses one.
# generated_ddev_files:
#   - docker-compose.drupal.yaml
#   - drupal
EOF
  success "Auto-generated .ddev/worktree.yaml  (project_name: ${_detected})"
  warn "Review .ddev/worktree.yaml and adjust project_name if the Drush alias differs."
}

# ── DDEV status ───────────────────────────────────────────────────────────────

# DDEV projects as TSV: approot<TAB>status<TAB>primary_url<TAB>name
# Parsing prefers jq, then python3, and degrades to empty if neither exists —
# callers fall back to "stopped" status and derived URLs.
_wt_ddev_tsv() {
  local _json
  _json=$(ddev list --json-output 2>/dev/null) || return 0
  [[ -z "$_json" ]] && return 0
  if command -v jq &>/dev/null; then
    printf '%s' "$_json" | jq -r '(.raw // [])[]
      | select((.approot // "") != "")
      | [((.approot)|sub("/+$";"")), (.status // ""), (.primary_url // ""), (.name // "")]
      | @tsv' 2>/dev/null || true
  elif command -v python3 &>/dev/null; then
    printf '%s' "$_json" | python3 -c 'import json,sys
try:
 for p in (json.load(sys.stdin).get("raw") or []):
  r=p.get("approot","").rstrip("/")
  if r: print("\t".join([r,p.get("status",""),p.get("primary_url",""),p.get("name","")]))
except Exception: pass' 2>/dev/null || true
  fi
}

# Cache the TSV in WT_DDEV_DATA for the per-row lookups below.
_wt_ddev_data_load() { WT_DDEV_DATA=$(_wt_ddev_tsv); }
_wt_ddev_status_for_path() { printf '%s' "${WT_DDEV_DATA:-}" | awk -F'\t' -v p="$1" '$1==p{print $2;exit}'; }
_wt_ddev_url_for_path()    { printf '%s' "${WT_DDEV_DATA:-}" | awk -F'\t' -v p="$1" '$1==p{print $3;exit}'; }

# Status of a DDEV project by NAME (fresh lookup, no cache).
_wt_ddev_status_by_name() {
  _wt_ddev_tsv | awk -F'\t' -v n="$1" '$4==n{print $2;exit}'
}

# True if the DDEV project of a worktree path is running.
_wt_is_running() {
  local _name
  _name=$(_wt_yaml_get "$1/.ddev/config.local.yaml" name)
  [[ -z "$_name" ]] && _name=$(_wt_yaml_get "$1/.ddev/config.yaml" name)
  [[ -n "$_name" ]] && [[ "$(_wt_ddev_status_by_name "$_name")" == "running" ]]
}

# ── DDEV config application (shared core of wt-add / wt-repair) ───────────────

# DDEV project names become hostnames: lowercase, [a-z0-9-] only, and the
# resulting DNS label must stay under 64 chars. Sanitize what we derive from
# branch/directory names (which may contain _ or uppercase).
# Usage: _wt_ddev_project_name <prefix> <dir-name>
_wt_ddev_project_name() {
  local _n="${1}-${2}"
  _n=$(printf '%s' "$_n" | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/[^a-z0-9-]+/-/g; s/-+/-/g; s/^-+//')
  _n="${_n:0:63}"
  _n=$(printf '%s' "$_n" | sed -E 's/-+$//')
  printf '%s\n' "$_n"
}

# Print local dirs bind-mounted as "./name" in docker-compose overrides.
_wt_compose_dirs() {
  local _ddev_dir="$1" _f
  for _f in "${_ddev_dir}"/docker-compose*.yaml; do
    [[ -f "$_f" ]] || continue
    # `|| true`: grep exits 1 when a compose file has no "./" mount. Under the
    # caller's `set -e` (via process substitution) that would abort the whole
    # scan, silently skipping later files — so swallow the no-match status.
    grep -hoE '"\./[^/":[:space:]]+' "$_f" 2>/dev/null || true
  done | sed -E 's#^"\./##' | sort -u
}

# Create or fix a symlink. Replaces an existing symlink (including a dangling
# one, which `ln -s` alone would trip over with EEXIST) but never overwrites a
# real file or directory. Returns 0 if it changed anything, 1 if skipped.
_wt_ensure_link() {
  local _src="$1" _dst="$2"
  if [[ -L "$_dst" ]]; then
    [[ "$(readlink "$_dst")" == "$_src" && -e "$_dst" ]] && return 1
    rm -f "$_dst"
  elif [[ -e "$_dst" ]]; then
    return 1
  fi
  ln -s "$_src" "$_dst"
}

# Apply (or repair) a worktree's .ddev setup from the main checkout. Idempotent.
# Strategy per item:
#   host-side config files & docker-compose overrides → SYMLINK (updates propagate)
#   compose volume-mount dirs                         → COPY   (Docker needs real files)
#   host/ commands → SYMLINK; container commands      → COPY   (main isn't mounted there)
#   entries in GENERATED_FILES                        → SKIP   (project hook owns them)
# Expects _wt_load_config to have run (GENERATED_FILES, WT_PREFIX).
# Sets WT_CHANGED to the number of changes applied.
# Usage: _wt_apply_ddev_config <main-worktree> <worktree-path>
_wt_apply_ddev_config() {
  local _main="$1" _wt="$2"
  WT_CHANGED=0
  mkdir -p "${_wt}/.ddev"

  # Unique DDEV project name for this worktree, plus a self-scoped wildcard
  # hostname so subdomains work the same way main projects' ds-<name> convention
  # does (additional_hostnames: ["*.ds-<name>"] -> admin.ds-<name>.ddev.site).
  # config.yaml is SYMLINKED into every worktree, so any additional_hostnames
  # entry declared there is stuck with the main project's literal name and can
  # never match a worktree's own hostname — the wildcard has to be generated
  # here, per worktree, from that worktree's own DDEV project name.
  #
  # Fully regenerated (not write-once): this file is add-on-owned and never
  # hand-edited, so re-running wt-repair on an existing worktree picks up
  # additions like this one instead of only ever benefiting new worktrees.
  local _cfg_local="${_wt}/.ddev/config.local.yaml" _ddev_name _cfg_local_new
  _ddev_name=$(_wt_ddev_project_name "$WT_PREFIX" "$(basename "$_wt")")
  _cfg_local_new=$(cat <<EOF
# Auto-generated by ddev-worktree. Do not edit manually — regenerated on
# every wt-add / wt-repair run.
name: ${_ddev_name}
additional_hostnames:
  - "*.${_ddev_name}"
EOF
)
  if [[ "$(cat "$_cfg_local" 2>/dev/null || true)" != "$_cfg_local_new" ]]; then
    printf '%s\n' "$_cfg_local_new" > "$_cfg_local"
    info "Wrote config.local.yaml  (name: ${_ddev_name}, wildcard: *.${_ddev_name})"
    ((WT_CHANGED++)) || true
  fi

  # Host-side DDEV config files → symlink. worktree.yaml is included so the
  # git hooks and wt-sync can read project config from inside the worktree.
  local _item _src _dst
  for _item in config.yaml php apache-site.conf nginx-site.conf config.drupal.yaml worktree.yaml; do
    _wt_is_generated "$_item" && continue
    _src="${_main}/.ddev/${_item}"; _dst="${_wt}/.ddev/${_item}"
    [[ -e "$_src" ]] || continue
    if _wt_ensure_link "$_src" "$_dst"; then
      info "Symlinked .ddev/${_item}"
      ((WT_CHANGED++)) || true
    fi
  done

  # docker-compose override files → symlink
  local _dc_file _dc_name
  for _dc_file in "${_main}/.ddev/docker-compose"*.yaml; do
    [[ -f "$_dc_file" ]] || continue
    _dc_name=$(basename "$_dc_file")
    _wt_is_generated "$_dc_name" && continue
    if _wt_ensure_link "$_dc_file" "${_wt}/.ddev/${_dc_name}"; then
      info "Symlinked .ddev/${_dc_name}"
      ((WT_CHANGED++)) || true
    fi
  done

  # Dirs referenced as ./dirname in compose volume mounts → real copies.
  # Docker bind-mounting a missing path creates an empty directory instead of
  # a file, causing Apache 403 / container exits. Existing copies are refreshed
  # so we always have clean, user-owned files (Docker may have left root-owned
  # ones behind — fall back to sudo for those).
  local _dir
  while IFS= read -r _dir; do
    [[ -z "$_dir" ]] && continue
    _wt_is_generated "$_dir" && continue
    _src="${_main}/.ddev/${_dir}"; _dst="${_wt}/.ddev/${_dir}"
    [[ -d "$_src" ]] || continue
    if [[ -e "$_dst" ]]; then
      if ! rm -rf "$_dst" 2>/dev/null; then
        warn "Removing root-owned Docker leftovers in .ddev/${_dir}/ (needs sudo)..."
        if ! sudo rm -rf "$_dst"; then
          warn "Could not remove .ddev/${_dir}/ even with sudo — skipping."
          continue
        fi
      fi
      cp -r "$_src" "$_dst"
      info "Re-copied .ddev/${_dir}/ (refreshed volume mount source)"
    else
      cp -r "$_src" "$_dst"
      info "Copied .ddev/${_dir}/ (docker volume mount source)"
    fi
    ((WT_CHANGED++)) || true
  done < <(_wt_compose_dirs "${_main}/.ddev")

  # Make every custom command from main available in this worktree.
  #   host/ commands run on the HOST, where a symlink to main resolves → symlink.
  #   web/ (and any service dir) commands run INSIDE a container, where main's
  #   path is NOT mounted — a symlink would dangle there, so copy the real file.
  local _cmd_subdir _subdir_name _has_commands _wt_subdir _cmd _cdst
  if [[ -d "${_main}/.ddev/commands" ]]; then
    for _cmd_subdir in "${_main}/.ddev/commands"/*/; do
      [[ -d "$_cmd_subdir" ]] || continue
      _subdir_name=$(basename "$_cmd_subdir")
      _has_commands=$(find "$_cmd_subdir" -maxdepth 1 -type f ! -name 'README*' ! -name '.gitattributes' | head -1)
      [[ -z "$_has_commands" ]] && continue
      _wt_subdir="${_wt}/.ddev/commands/${_subdir_name}"
      mkdir -p "$_wt_subdir"
      for _cmd in "${_cmd_subdir}"*; do
        [[ -f "$_cmd" ]] || continue
        _cdst="${_wt_subdir}/$(basename "$_cmd")"
        if [[ "$_subdir_name" == "host" ]]; then
          if _wt_ensure_link "$_cmd" "$_cdst"; then
            info "Symlinked command: ${_subdir_name}/$(basename "$_cmd")"
            ((WT_CHANGED++)) || true
          fi
        else
          # Replace a dangling/host-path symlink left by older versions with a copy.
          if [[ ! -e "$_cdst" || -L "$_cdst" ]]; then
            rm -f "$_cdst"
            cp "$_cmd" "$_cdst"
            info "Copied command: ${_subdir_name}/$(basename "$_cmd")"
            ((WT_CHANGED++)) || true
          fi
        fi
      done
    done
  fi
}

# ── Composer helpers ──────────────────────────────────────────────────────────

# True if the worktree needs `composer install` (vendor missing or stale).
_wt_needs_composer() {
  [[ -f "$1/composer.json" ]] || return 1
  [[ ! -f "$1/vendor/autoload.php" ]] && return 0
  [[ "$1/composer.lock" -nt "$1/vendor/autoload.php" ]] && return 0
  return 1
}

# Make sites/default/ writable so composer can scaffold default.settings.php.
# Host chmod may fail on bind-mounted files (root-owned after ddev start) —
# always suppress those errors. Then fix the directory inside the container
# as root, which works regardless of bind-mount ownership on the host.
_wt_unlock_sites_default() {
  local _wt="$1" _sd
  for _sd in docroot/sites web/sites sites; do
    if [[ -d "${_wt}/${_sd}/default" ]]; then
      chmod -R a+w "${_wt}/${_sd}/default" 2>/dev/null || true
      ( cd "$_wt" && ddev exec sudo chmod a+w "/var/www/html/${_sd}/default" 2>/dev/null ) || true
      break
    fi
  done
}

# ── Misc ──────────────────────────────────────────────────────────────────────

# Escape a string for embedding in a JSON double-quoted value.
_wt_json_escape() {
  local _s="$1"
  _s="${_s//\\/\\\\}"; _s="${_s//\"/\\\"}"
  printf '%s' "$_s"
}
