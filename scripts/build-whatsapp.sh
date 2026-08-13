#!/usr/bin/env bash
#
# Builds the macOS WhatsApp bridge/MCP binaries from the pinned upstream
# commit as UNIVERSAL binaries (x86_64 + arm64) and stages them - with the
# manifest and the setup script - into
# dist/whatsapp/vimigo-whatsapp-mac-v1.0.zip.
#
# The mirror image of scripts/build-whatsapp.ps1: same manifest shape, same
# wipe-the-stage-first behaviour, same "the zip must contain the doer" rule.
#
#   bash scripts/build-whatsapp.sh            build
#   bash scripts/build-whatsapp.sh --verify   re-check an existing build
#
# Runs on macOS only. Both Go modules pin mattn/go-sqlite3, which is cgo, so
# an Apple toolchain is required and there is no honest way around it. The
# Mac does not have to be one anybody owns:
# .github/workflows/build-whatsapp-mac.yml runs this on a GitHub-hosted macOS
# runner, which is free for a public repository.
#
# One file for both machines is deliberate. A participant must never be asked
# which Mac they own, and half the room owning the wrong one is the same
# failure as shipping nothing.
set -eu

# ---------------------------------------------------------------------------
# The upstream pin.
#
# KEEP IN STEP WITH scripts/build-whatsapp.ps1 lines 38-39, and with the
# UPSTREAM_URL / UPSTREAM_SHA env block at the top of
# .github/workflows/build-whatsapp-mac.yml. Those are the only three places
# the pin is written down; do not scatter a fourth.
#
# Both are overridable from the environment so CI can be pointed elsewhere
# without editing a tracked file.
#
# The pin is the FORK, not vimigo-lee/whatsapp-mcp-go, and deliberately so.
# OWNER_MODE lives on tengkusyafiq/whatsapp-mcp-go at this commit, which is two
# commits ahead of vimigo-lee's 6b8571c9 and zero behind it - a clean
# fast-forward, so nothing upstream is being skipped. Building from the fork is
# what removes a person from the critical path: waiting on a review to be
# merged before the event would have meant shipping binaries where OWNER_MODE
# is inert, and an inert OWNER_MODE is Claude Desktop answering a 60-plus owner
# with raw chat IDs.
# ---------------------------------------------------------------------------
UPSTREAM_SHA="${UPSTREAM_SHA_OVERRIDE:-913934ab801d44327fe3eeb94d89a96d318183e9}"
UPSTREAM_URL="${UPSTREAM_URL_OVERRIDE:-https://github.com/tengkusyafiq/whatsapp-mcp-go.git}"
VERSION='v1.2'

# Without this, clang stamps the BUILD machine's own macOS version as the
# binary's minimum. A runner on macOS 15 would then produce something that
# refuses to launch on a participant's older Mac, and the only symptom is a
# dialog nobody in the room can act on. 12.0 (Monterey, 2021) is the floor we
# build for: old enough for any Mac still in daily use, and within what the
# pinned Go toolchain supports.
export MACOSX_DEPLOYMENT_TARGET='12.0'

# scripts/build-whatsapp.sh in this repository; build-whatsapp.sh may also sit
# one level up in a published tree, so derive the root from where this file
# actually is rather than assuming.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ "$(basename "$SCRIPT_DIR")" = 'scripts' ]; then
    REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
else
    REPO_ROOT="$SCRIPT_DIR"
fi

OUT="$REPO_ROOT/dist/whatsapp"
STAGE="$OUT/stage-mac"
SRC="$OUT/src"
MANIFEST="$OUT/manifest-mac.json"
ZIP="$OUT/vimigo-whatsapp-mac-$VERSION.zip"

# The binaries this build produces. Used by BOTH the build path (what gets
# hashed into the manifest) and the verify path (what the manifest's binaries
# object is required to contain), so the two cannot drift apart. Same reason
# $ExpectedBinaries exists in the Windows builder.
EXPECTED_BINARIES='whatsapp-bridge whatsapp-mcp'

# Where the doer might be. This repository keeps it under scripts/setup; the
# published tree flattens that to "Vimigo files" at the root, and the workflow
# has to work in whichever repository it was copied into.
DOER_CANDIDATES="scripts/setup/Vimigo files/vimigo-whatsapp.sh
Vimigo files/vimigo-whatsapp.sh"

# The repair skill, and where it might be. Same two-layout problem as the doer,
# with different names on each side: this repository keeps the authored copy
# under scripts/, and publish-release.py emits it into the published tree as
# skill-whatsapp/. The workflow that runs this script is meant to live in the
# PUBLIC repository, so the second candidate is the one that matters in
# production and the first is the one that matters here.
SKILL_ENTRY='whatsapp-mcp-setup/SKILL.md'
SKILL_CANDIDATES="scripts/public-skill-whatsapp/whatsapp-mcp-setup/SKILL.md
skill-whatsapp/whatsapp-mcp-setup/SKILL.md"

usage() {
    printf 'usage: bash %s [--verify]\n' "$0"
}

need_tool() {
    if ! command -v "$1" >/dev/null 2>&1; then
        printf 'build stopped: %s is not installed. %s\n' "$1" "$2" >&2
        exit 1
    fi
}

find_doer() {
    local candidate
    # A here-string, not a pipe: a `while` on the right of a pipe runs in a
    # subshell, and everything decided in there is thrown away on exit.
    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        if [ -f "$REPO_ROOT/$candidate" ]; then
            printf '%s\n' "$REPO_ROOT/$candidate"
            return 0
        fi
    done <<< "$DOER_CANDIDATES"
    return 1
}

# Called FIRST, before the clone and before a ten-minute compile. A build that
# discovers the missing doer at the end has already burnt the runner's time
# and, worse, invites somebody to ship the zip it very nearly produced.
require_doer() {
    local found candidate
    # `|| true` is load-bearing: under `set -eu` an assignment from a command
    # substitution that fails takes the shell down on the spot, and the whole
    # point of this function is the message below.
    found="$(find_doer || true)"
    if [ -n "$found" ]; then
        printf '%s\n' "$found"
        return 0
    fi

    {
        printf '\n'
        printf 'BUILD STOPPED: vimigo-whatsapp.sh was not found.\n'
        printf '\n'
        printf 'The release zip is the ONLY thing the one-liner downloads. A zip\n'
        printf 'without vimigo-whatsapp.sh inside it means every participant waits\n'
        printf 'through a ~28 MB download and then reads "That download did not\n'
        printf 'contain the setup." - a 100%% failure at the door, on every Mac, with\n'
        printf 'nothing to fall back to. This build refuses to produce that zip.\n'
        printf '\n'
        printf 'Looked in:\n'
        while IFS= read -r candidate; do
            [ -n "$candidate" ] || continue
            printf '  %s\n' "$REPO_ROOT/$candidate"
        done <<< "$DOER_CANDIDATES"
        printf '\n'
        printf 'The macOS doer is built by Task 11. Until it exists there is nothing\n'
        printf 'worth shipping.\n'
        printf '\n'
    } >&2
    exit 1
}

find_skill() {
    local candidate
    while IFS= read -r candidate; do
        [ -n "$candidate" ] || continue
        if [ -f "$REPO_ROOT/$candidate" ]; then
            printf '%s\n' "$REPO_ROOT/$candidate"
            return 0
        fi
    done <<< "$SKILL_CANDIDATES"
    return 1
}

# Called beside require_doer, before the clone, and refuses just as hard.
#
# The zip is the only thing that reaches a participant's Mac. The skill is what
# tells their assistant that four repair verbs exist and that it may not show
# them a path or a command; without it, an owner whose WhatsApp stops working
# gets an assistant improvising at a 60-plus business owner - which is one of
# the four failures this project exists to fix. Publishing the skill to the
# public repository is not installing it; the doer installs it, out of this zip.
require_skill() {
    local found candidate
    found="$(find_skill || true)"
    if [ -n "$found" ]; then
        printf '%s\n' "$found"
        return 0
    fi

    {
        printf '\n'
        printf 'BUILD STOPPED: the repair skill was not found.\n'
        printf '\n'
        printf 'It ships inside the zip and the setup copies it into the folder every\n'
        printf 'AI app on the Mac reads. Without it, an owner whose WhatsApp breaks is\n'
        printf 'talking to an assistant that has never heard of the repair verbs and\n'
        printf 'will start improvising at somebody who has never opened a terminal.\n'
        printf '\n'
        printf 'Looked in:\n'
        while IFS= read -r candidate; do
            [ -n "$candidate" ] || continue
            printf '  %s\n' "$REPO_ROOT/$candidate"
        done <<< "$SKILL_CANDIDATES"
        printf '\n'
    } >&2
    exit 1
}

sha256_of() {
    shasum -a 256 "$1" | awk '{print $1}'
}

# Every dylib the binary imports, across every slice of a universal file.
# otool -L prints one indented line per import under a per-architecture
# header, so match on the indent rather than skipping a fixed line count.
linked_dylibs() {
    otool -L "$1" | awk '/^[[:space:]]/ {print $1}'
}

build_one() {
    # $1 module directory under $SRC, $2 output binary name
    local module="$1" name="$2" arch clang_arch

    ( cd "$SRC/$module" && go mod download )

    for arch in amd64 arm64; do
        if [ "$arch" = 'amd64' ]; then clang_arch='x86_64'; else clang_arch='arm64'; fi

        # CGO_ENABLED=1 is not the default when GOARCH differs from the host,
        # and go-sqlite3 without cgo does not build at all. CC carries the
        # -arch flag rather than CGO_CFLAGS because CGO_CFLAGS REPLACES the
        # default -g -O2, which would quietly ship an unoptimised sqlite; the
        # linker needs the same flag, and it reads CC too.
        #
        # x86_64 is cross-compiled from an Apple Silicon host on purpose. The
        # macOS SDK carries both slices, so Apple's clang targets x86_64 with
        # nothing extra installed. GitHub's free macos-latest runner is arm64;
        # its Intel images are separate x64 labels, and building each slice on
        # its own runner would mean two jobs, an artifact hand-off and a third
        # job to lipo them - for a result this produces in one. The x86_64
        # slice cannot be EXECUTED on an arm64 host (no Rosetta on the
        # runners): lipo -archs, otool and codesign are what prove it here,
        # and a human on an Intel Mac is what finally runs it.
        ( cd "$SRC/$module" \
          && CGO_ENABLED=1 GOOS=darwin GOARCH="$arch" \
             CC="clang -arch $clang_arch" \
             CXX="clang++ -arch $clang_arch" \
             go build -trimpath -ldflags '-s -w' -o "$STAGE/$name.$arch" . )
    done

    lipo -create -output "$STAGE/$name" "$STAGE/$name.amd64" "$STAGE/$name.arm64"
    rm -f "$STAGE/$name.amd64" "$STAGE/$name.arm64"
    chmod 0755 "$STAGE/$name"

    # Ad-hoc signature, re-applied AFTER lipo. Go signs each thin arm64
    # binary itself, but macOS on Apple Silicon refuses to execute an
    # arm64 image whose signature does not cover the file it is in - it is
    # killed outright, with "Killed: 9" and nothing else. Re-signing the
    # combined file is one line here and the difference between a working
    # install and an unexplainable one on every M-series Mac in the room.
    #
    # --all-architectures on the check, because codesign verifies only the
    # native slice by default. On an arm64 build host that would leave the
    # x86_64 half - the half nobody here can execute - entirely unchecked.
    codesign --force --sign - "$STAGE/$name"
    codesign --verify --strict --all-architectures "$STAGE/$name"
}

checkout_upstream() {
    # A cached clone that points at a different remote would silently build
    # the OLD repository under the NEW sha's name. Expected to matter: the
    # fork for OWNER_MODE changes the URL, not just the commit.
    if [ -d "$SRC/.git" ]; then
        local current
        current="$(git -C "$SRC" remote get-url origin 2>/dev/null || printf '')"
        if [ "$current" != "$UPSTREAM_URL" ]; then
            printf 'upstream url changed; re-cloning\n'
            rm -rf "$SRC"
        fi
    fi

    [ -d "$SRC/.git" ] || git clone "$UPSTREAM_URL" "$SRC"
    git -C "$SRC" fetch --all --tags --force
    git -C "$SRC" checkout --detach "$UPSTREAM_SHA"

    # An abbreviated sha, a branch name, or a tag would all check out
    # successfully and then be recorded in the manifest as the full pin.
    local head
    head="$(git -C "$SRC" rev-parse HEAD)"
    if [ "$head" != "$UPSTREAM_SHA" ]; then
        printf 'build stopped: asked for %s but HEAD is %s\n' "$UPSTREAM_SHA" "$head" >&2
        exit 1
    fi
}

main() {
    local doer skill bridge_sha mcp_sha

    # require_doer prints and exits, but it does so inside a command
    # substitution, so make the exit explicit here rather than leaning on
    # `set -e` to notice.
    doer="$(require_doer)" || exit 1
    skill="$(require_skill)" || exit 1

    need_tool git 'Install the Xcode command line tools.'
    need_tool go 'Install Go 1.25 or later.'
    need_tool clang 'Install the Xcode command line tools.'
    need_tool lipo 'Install the Xcode command line tools.'
    need_tool codesign 'Install the Xcode command line tools.'
    need_tool otool 'Install the Xcode command line tools.'
    need_tool zip 'Expected at /usr/bin/zip on any macOS.'
    need_tool shasum 'Expected at /usr/bin/shasum on any macOS.'

    # Wipe the stage rather than mkdir -p over it. Without this, a build that
    # dies partway through leaves the PREVIOUS run's binaries in place and the
    # next run hashes those stale files into a manifest stamped with the NEW
    # upstream_sha. Since re-pinning and rebuilding is the entire mechanism
    # for tracking upstream, that ships stale binaries under a truthful
    # looking manifest. Same reasoning as build-whatsapp.ps1.
    rm -rf "$STAGE"
    mkdir -p "$STAGE" "$OUT"

    checkout_upstream

    build_one whatsapp-bridge whatsapp-bridge
    build_one whatsapp-mcp-server whatsapp-mcp

    bridge_sha="$(sha256_of "$STAGE/whatsapp-bridge")"
    mcp_sha="$(sha256_of "$STAGE/whatsapp-mcp")"

    {
        printf '{\n'
        printf '  "upstream_sha": "%s",\n' "$UPSTREAM_SHA"
        printf '  "built": "%s",\n' "$(date -u +%Y-%m-%d)"
        printf '  "binaries": {\n'
        printf '    "whatsapp-bridge": "%s",\n' "$bridge_sha"
        printf '    "whatsapp-mcp": "%s"\n' "$mcp_sha"
        printf '  }\n'
        printf '}\n'
    } > "$MANIFEST"

    cp "$MANIFEST" "$STAGE/manifest.json"

    # The doer ships inside the zip because the zip is the only thing the
    # one-liner fetches (audit 12.1). Mode 0755, or macOS opens it in TextEdit
    # instead of running it. The manifest deliberately still lists only the
    # two binaries: it is a corruption check on compiled output, and the
    # script is covered by the zip-wide SHA256 the one-liner pins.
    cp "$doer" "$STAGE/vimigo-whatsapp.sh"
    chmod 0755 "$STAGE/vimigo-whatsapp.sh"

    # And the skill, in the folder shape an AI client will actually load: a
    # directory whose name is the skill's name, holding SKILL.md. fresh_install
    # lifts this one member back out of the zip and writes it under the owner's
    # own home, which needs no password and reaches all three apps at once.
    mkdir -p "$STAGE/$(dirname "$SKILL_ENTRY")"
    cp "$skill" "$STAGE/$SKILL_ENTRY"
    chmod 0644 "$STAGE/$SKILL_ENTRY"

    # rm first: zip UPDATES an existing archive rather than replacing it, so a
    # rename upstream would leave the old member sitting alongside the new one.
    # An explicit file list, not `.`, so a stray .DS_Store or a leftover
    # per-arch object can never ride along.
    rm -f "$ZIP"
    ( cd "$STAGE" && zip -q -X "$ZIP" \
        whatsapp-bridge whatsapp-mcp manifest.json vimigo-whatsapp.sh "$SKILL_ENTRY" )

    # Printed so Task 13 can pin it, and so a rebuild that forgets to re-pin is
    # obvious rather than silent.
    printf 'built %s\n' "$ZIP"
    printf 'zip sha256: %s\n' "$(sha256_of "$ZIP")"
}

verify() {
    local stage="$1" manifest="$2"
    local fail=0
    local name want actual keys bad

    if [ ! -f "$manifest" ]; then
        printf 'manifest not found: %s\n' "$manifest" >&2
        return 1
    fi

    # The manifest's binaries key set must match EXACTLY. Iterating whatever
    # keys happen to be present lets an empty or half-written manifest skip
    # the loop body entirely and still reach "OK" - a verify that proves
    # nothing. The Windows builder was fixed for exactly this.
    keys="$(awk '/"binaries"/ {flag=1; next} flag && /}/ {flag=0} flag {print}' "$manifest" \
            | sed -n 's/^[[:space:]]*"\([^"]*\)"[[:space:]]*:.*/\1/p' \
            | sort | tr '\n' ' ')"
    if [ "$keys" != "$(printf '%s\n' $EXPECTED_BINARIES | sort | tr '\n' ' ')" ]; then
        printf 'manifest binaries do not match the expected set. Expected: [%s]. Found: [%s].\n' \
            "$EXPECTED_BINARIES" "$keys" >&2
        fail=1
    fi

    for name in $EXPECTED_BINARIES; do
        if [ ! -f "$stage/$name" ]; then
            printf 'missing binary: %s\n' "$stage/$name" >&2
            fail=1
            continue
        fi

        want="$(sed -n "s/.*\"$name\": *\"\([0-9a-f]\{64\}\)\".*/\1/p" "$manifest")"
        actual="$(sha256_of "$stage/$name")"
        if [ -z "$want" ]; then
            printf 'no sha256 for %s in the manifest\n' "$name" >&2
            fail=1
        elif [ "$want" != "$actual" ]; then
            printf 'hash mismatch: %s\n' "$name" >&2
            fail=1
        fi

        # Both architectures must be present or half the room gets nothing.
        lipo -archs "$stage/$name" | grep -q 'x86_64' || { printf 'no x86_64: %s\n' "$name" >&2; fail=1; }
        lipo -archs "$stage/$name" | grep -q 'arm64'  || { printf 'no arm64: %s\n' "$name" >&2;  fail=1; }

        # The macOS mirror of the Windows "no MSYS2 DLL" check, and the same
        # point: nothing outside the OS may be imported. A Homebrew libsqlite3
        # or libicu picked up from the build machine links fine here and then
        # dies on a participant's Mac, which has no /opt/homebrew at all.
        bad="$(linked_dylibs "$stage/$name" | grep -v '^/usr/lib/' | grep -v '^/System/' || true)"
        if [ -n "$bad" ]; then
            printf 'not self-contained: %s imports %s\n' "$name" "$(printf '%s' "$bad" | tr '\n' ' ')" >&2
            fail=1
        fi

        # Unsigned or stale-signed arm64 is killed on sight by macOS on Apple
        # Silicon, with no message anyone can act on. --all-architectures, or
        # only the build host's own slice gets looked at.
        codesign --verify --strict --all-architectures "$stage/$name" 2>/dev/null \
            || { printf 'signature invalid: %s\n' "$name" >&2; fail=1; }
    done

    # Checked against the ZIP that actually ships, not just the stage
    # directory, so a packaging regression is caught here rather than by
    # unzipping the published asset after the fact.
    if [ ! -f "$ZIP" ]; then
        printf 'release zip not found: %s\n' "$ZIP" >&2
        fail=1
    else
        local members
        members="$(unzip -Z1 "$ZIP")"
        for name in vimigo-whatsapp.sh manifest.json $EXPECTED_BINARIES; do
            printf '%s\n' "$members" | grep -qx "$name" || {
                printf 'release zip is missing %s - the one-liner would download it and find nothing to run\n' "$name" >&2
                fail=1
            }
        done
        # Checked against the zip, exactly like the doer above, because the
        # same thing is true of it: what is not in this file never reaches the
        # laptop, and nothing downstream would notice it was gone.
        printf '%s\n' "$members" | grep -qx "$SKILL_ENTRY" || {
            printf 'release zip is missing %s - an owner whose WhatsApp breaks would have no skill telling their assistant what to do\n' "$SKILL_ENTRY" >&2
            fail=1
        }
    fi

    if [ "$fail" -eq 0 ]; then
        echo OK
        return 0
    fi
    return 1
}

case "${1:-}" in
    '')        main ;;
    --verify)  verify "$STAGE" "$MANIFEST" ;;
    -h|--help) usage ;;
    *)         printf 'unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
esac
