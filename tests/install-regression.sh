#!/bin/sh
set -eu

root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/retouch-photo-install-test.XXXXXXXX")
trap 'rm -rf -- "$tmp"' EXIT
profile="$tmp/user profile"
old_profile="$profile/.codex"
dest="$profile/.agents/skills/retouch-photo"
legacy="$old_profile/skills/retouch-photo"
backups="$profile/.agents/skill-backups"
run_install() {
    sh "$root/install.sh" "$profile" "$old_profile"
}

run_install
cmp "$root/skills/retouch-photo/SKILL.md" "$dest/SKILL.md"
cmp "$root/LICENSE" "$dest/LICENSE"

mkdir -p "$legacy"
printf 'previous current install\n' > "$dest/SKILL.md"
printf 'legacy install\n' > "$legacy/SKILL.md"
run_install
cmp "$root/skills/retouch-photo/SKILL.md" "$dest/SKILL.md"
cmp "$root/LICENSE" "$dest/LICENSE"
test "$(find "$profile/.agents/skills" "$old_profile/skills" -name SKILL.md -print)" = "$dest/SKILL.md"
set -- "$backups"/retouch-photo.*
test "$#" -eq 1
test "$(cat "$1/agents/SKILL.md")" = 'previous current install'
test "$(cat "$1/codex/SKILL.md")" = 'legacy install'

run_install
set -- "$backups"/retouch-photo.*
test "$#" -eq 2

mkdir -p "$legacy" "$tmp/missing source" "$tmp/failing commands"
printf 'keep legacy in place\n' > "$legacy/SKILL.md"
cp "$root/install.sh" "$tmp/missing source/install.sh"
if sh "$tmp/missing source/install.sh" "$profile" "$old_profile"; then
    echo 'Missing source was accepted' >&2
    exit 1
fi
cmp "$root/skills/retouch-photo/SKILL.md" "$dest/SKILL.md"
test "$(cat "$legacy/SKILL.md")" = 'keep legacy in place'

cat > "$tmp/failing commands/cp" <<'SH'
#!/bin/sh
# Simulate a copy that has begun writing but cannot complete.
mkdir -p "$4"
printf 'incomplete copy\n' > "$4/SKILL.md"
exit 1
SH
chmod +x "$tmp/failing commands/cp"
if (PATH="$tmp/failing commands:$PATH"; export PATH; run_install); then
    echo 'Failed copy was accepted' >&2
    exit 1
fi
cmp "$root/skills/retouch-photo/SKILL.md" "$dest/SKILL.md"
test "$(cat "$legacy/SKILL.md")" = 'keep legacy in place'
test -z "$(find "$profile/.agents" -name 'retouch-photo-stage.*' -print)"
set -- "$backups"/retouch-photo.*
test "$#" -eq 2
echo 'Install regression passed'
