#!/bin/sh
set -eu

repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
source_dir="$repo_dir/skills/retouch-photo"
test -f "$source_dir/SKILL.md" || { printf '%s\n' "Missing skill: $source_dir/SKILL.md" >&2; exit 1; }

# Optional profile paths allow installation in an isolated or alternate profile.
profile_dir=${1:-"$HOME"}
if [ "$#" -eq 0 ]; then
    legacy_profile=${CODEX_HOME:-"$profile_dir/.codex"}
else
    legacy_profile=${2:-"$profile_dir/.codex"}
fi
skill_dir="$profile_dir/.agents/skills"
dest="$skill_dir/retouch-photo"
legacy="$legacy_profile/skills/retouch-photo"
backup_root="$profile_dir/.agents/skill-backups"

mkdir -p "$skill_dir"
stage_dir=$(mktemp -d "$profile_dir/.agents/retouch-photo-stage.XXXXXXXX")
backup_dir=
installed=
cleanup() {
    status=$?
    if [ -z "$installed" ] && [ -n "$backup_dir" ]; then
        restore "$backup_dir/agents" "$dest"
        restore "$backup_dir/codex" "$legacy"
    fi
    rm -rf -- "$stage_dir"
    exit "$status"
}
restore() {
    if exists "$1" && ! exists "$2"; then
        mv -h -- "$1" "$2" || printf 'Restore manually from %s\n' "$1" >&2
    fi
}
exists() {
    [ -e "$1" ] || [ -L "$1" ]
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

cp -R -- "$source_dir" "$stage_dir/retouch-photo"
test -f "$stage_dir/retouch-photo/SKILL.md"
cp -- "$repo_dir/LICENSE" "$stage_dir/retouch-photo/LICENSE"

if exists "$dest" || exists "$legacy"; then
    mkdir -p "$backup_root"
    backup_dir=$(mktemp -d "$backup_root/retouch-photo.XXXXXXXX")
    if exists "$dest"; then
        mv -h -- "$dest" "$backup_dir/agents"
    fi
    if exists "$legacy"; then
        mv -h -- "$legacy" "$backup_dir/codex"
    fi
fi

mv -h -- "$stage_dir/retouch-photo" "$dest"
installed=1
printf 'Installed %s\n' "$dest"
if [ -n "$backup_dir" ]; then
    printf 'Backed up previous installations in %s\n' "$backup_dir"
fi
