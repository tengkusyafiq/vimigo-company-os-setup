#!/usr/bin/env bash
#
# Sets up the company second brain on a customer's Zo.
#
# Two halves, because they are good at different things:
#
#   Notes/       plain Markdown, one file per thing worth remembering. This is
#                what a person reads, what Obsidian opens, what survives every
#                tool it outlives, and what an AI reads best.
#
#   Postgres     the index over those notes: what exists, when it changed, who
#                it is about, what it links to. Answers "everything about this
#                customer since March" in one query, which reading files
#                cannot.
#
# Nothing here asks the owner anything. It is a filing cabinet with the drawers
# labelled - empty and ready - so that when their assistant is told to remember
# something, there is somewhere for it to go.
#
# Install to /home/workspace/Services/vimigo-setup/ on the customer's Zo.
#
# Usage:
#   ./zo-second-brain.sh install
#   ./zo-second-brain.sh status

set -uo pipefail

BRAIN=/home/workspace/Notes
PGDATA=/home/workspace/Services/second-brain/pgdata
PGRUN=/home/workspace/Services/second-brain/run
PGPORT=5433
DB=secondbrain

say()  { printf '  %s\n' "$1"; }
good() { printf '  \033[32m%s\033[0m\n' "$1"; }
warn() { printf '  \033[33m%s\033[0m\n' "$1"; }
bad()  { printf '  \033[31m%s\033[0m\n' "$1"; }
step() { printf '\n\033[36m%s\033[0m\n' "$1"; }

pg_bin() {
    # Debian keeps the server binaries out of PATH on purpose, so that several
    # versions can live side by side. Newest wins.
    local d
    for d in $(ls -d /usr/lib/postgresql/*/bin 2>/dev/null | sort -V -r); do
        [ -x "$d/pg_ctl" ] && { printf '%s' "$d"; return 0; }
    done
    return 1
}

# ---------------------------------------------------------------------------
# The notes
# ---------------------------------------------------------------------------

make_folders() {
    step '1. Where things are kept'

    # Named for what a business has, not for what a database has. Somebody
    # opening this on their phone in six months should be able to guess where
    # anything lives.
    local folders='People
Customers
Suppliers
Products
Money
Decisions
Meetings
How we do things
Inbox'

    local created=0 name
    while IFS= read -r name; do
        [ -n "$name" ] || continue
        if [ ! -d "$BRAIN/$name" ]; then
            mkdir -p "$BRAIN/$name" && created=$((created + 1))
        fi
    done <<< "$folders"

    # A README in each, so an empty folder still explains itself - and so
    # Obsidian and every file browser show something rather than nothing.
    write_readme "People"           "One file per person who works here. What they do, what they are good at, what they are working on."
    write_readme "Customers"        "One file per customer. Who they are, what they bought, what they asked for, what went wrong and how it was fixed."
    write_readme "Suppliers"        "One file per supplier. What they supply, what it costs, how long they take, who to call."
    write_readme "Products"         "One file per thing you sell. What it is, what it costs, what people ask about it."
    write_readme "Money"            "Anything about money that is worth remembering. Prices, terms, who pays late."
    write_readme "Decisions"        "What was decided, when, and why. The why is the part everyone forgets."
    write_readme "Meetings"         "What was said and what was agreed. One file per meeting."
    write_readme "How we do things" "The way this business works. Opening hours, refunds, complaints, deliveries."
    write_readme "Inbox"            "Anything you have not filed yet. Send things here and sort them out later."

    good "$([ "$created" -gt 0 ] && echo "Made $created folders." || echo 'Folders already there.')"
    say "Everything lives in plain files, so it opens in anything."
}

write_readme() {
    local file="$BRAIN/$1/README.md"
    [ -f "$file" ] && return 0
    cat > "$file" <<EOF
# $1

$2

Every file in here is plain text, so it opens on a phone, on a computer, in
Obsidian, or in anything else - now and in ten years.
EOF
}

make_obsidian() {
    # Obsidian is a friendly way to read and edit these on a laptop or phone.
    # It is not required and nothing depends on it: this only leaves the
    # settings behind so that opening the folder works nicely if they do.
    local dir="$BRAIN/.obsidian"
    mkdir -p "$dir"
    [ -f "$dir/app.json" ] || cat > "$dir/app.json" <<'EOF'
{
  "attachmentFolderPath": "Inbox",
  "newFileLocation": "folder",
  "newFileFolderPath": "Inbox",
  "alwaysUpdateLinks": true,
  "useMarkdownLinks": true
}
EOF
    [ -f "$dir/core-plugins.json" ] || cat > "$dir/core-plugins.json" <<'EOF'
["file-explorer","global-search","switcher","graph","backlink","outgoing-link","tag-pane","daily-notes","templates","note-composer","command-palette","outline","word-count","file-recovery"]
EOF
}

# ---------------------------------------------------------------------------
# The index
# ---------------------------------------------------------------------------

# The index, on whatever this Zo actually has.
#
# Postgres if it is installed, and SQLite otherwise - which is every Zo today,
# since none of them ship a Postgres server. That is not a compromise: for one
# business's notes, SQLite with full-text search answers the same questions,
# arrives already installed, needs no service, no port and no supervision, and
# is a single file that backs up with the notes it indexes. Postgres earns its
# keep when several things query it at once, which is a problem this does not
# have yet.
#
# Either way the files on disk are the truth and the index can be thrown away
# and rebuilt, so changing our minds later costs nothing.
make_sqlite_index() {
    step '2. The index'

    python3 - "$BRAIN" <<'PY'
import sqlite3, sys, os
brain = sys.argv[1]
os.makedirs(brain, exist_ok=True)
db = sqlite3.connect(os.path.join(brain, '.index.db'))
db.executescript("""
CREATE TABLE IF NOT EXISTS notes (
    id         INTEGER PRIMARY KEY,
    path       TEXT UNIQUE NOT NULL,
    folder     TEXT NOT NULL,
    title      TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE TABLE IF NOT EXISTS note_links (
    from_id  INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    to_title TEXT NOT NULL,
    PRIMARY KEY (from_id, to_title)
);
CREATE TABLE IF NOT EXISTS note_tags (
    note_id INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    tag     TEXT NOT NULL,
    PRIMARY KEY (note_id, tag)
);
CREATE INDEX IF NOT EXISTS notes_folder ON notes (folder);
CREATE INDEX IF NOT EXISTS notes_updated ON notes (updated_at DESC);

-- What makes an index worth having over reading the files: finding a phrase
-- across everything at once, however much of it there is.
CREATE VIRTUAL TABLE IF NOT EXISTS note_search USING fts5(
    title, body, path UNINDEXED
);
""")
db.commit()
db.close()
PY
    if [ $? -ne 0 ]; then
        warn 'The index could not be prepared, so the notes will work without'
        warn 'one. Everything is still saved and readable.'
        return 1
    fi
    good 'Index ready.'
    say 'It is one file beside the notes, so a backup of one is a backup of both.'
    return 0
}

start_postgres() {
    step '2. The index'

    local bin; bin="$(pg_bin)" || {
        warn 'No database is available on this Zo, so the notes will work'
        warn 'without an index. Everything is still saved and searchable.'
        return 1
    }

    if [ ! -s "$PGDATA/PG_VERSION" ]; then
        mkdir -p "$PGDATA" "$PGRUN"
        chmod 700 "$PGDATA"
        # Trust on a unix socket only. There is no password because there is
        # no way in from outside: it never listens on a network address.
        "$bin/initdb" -D "$PGDATA" -U postgres --auth=trust >/dev/null 2>&1 || {
            bad 'The index could not be prepared.'
            return 1
        }
    fi

    # Bound to a socket in its own folder and nothing else. A database on a
    # customer's server that answers the network is a liability nobody asked
    # for.
    cat > "$PGDATA/postgresql.conf" <<EOF
listen_addresses = ''
unix_socket_directories = '$PGRUN'
port = $PGPORT
max_connections = 20
shared_buffers = 64MB
fsync = on
EOF

    if ! "$bin/pg_ctl" -D "$PGDATA" status >/dev/null 2>&1; then
        "$bin/pg_ctl" -D "$PGDATA" -l "$PGDATA/postgres.log" -w -t 30 start >/dev/null 2>&1 || {
            bad 'The index would not start.'
            tail -5 "$PGDATA/postgres.log" 2>/dev/null | sed 's/^/    /'
            return 1
        }
    fi

    "$bin/psql" -h "$PGRUN" -p "$PGPORT" -U postgres -tAc \
        "SELECT 1 FROM pg_database WHERE datname='$DB'" 2>/dev/null | grep -q 1 ||
        "$bin/createdb" -h "$PGRUN" -p "$PGPORT" -U postgres "$DB" >/dev/null 2>&1

    good 'Index ready.'
    return 0
}

make_tables() {
    local bin; bin="$(pg_bin)" || return 1

    # Deliberately small. It indexes the notes; it does not replace them - the
    # file on disk is always the truth, and this can be rebuilt from it at any
    # time. Anything that cannot be rebuilt does not belong in here.
    "$bin/psql" -h "$PGRUN" -p "$PGPORT" -U postgres -d "$DB" >/dev/null 2>&1 <<'EOF'
CREATE TABLE IF NOT EXISTS notes (
    id          BIGSERIAL PRIMARY KEY,
    path        TEXT UNIQUE NOT NULL,
    folder      TEXT NOT NULL,
    title       TEXT NOT NULL,
    body        TEXT NOT NULL DEFAULT '',
    updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS note_links (
    from_id  BIGINT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    to_title TEXT NOT NULL,
    PRIMARY KEY (from_id, to_title)
);

CREATE TABLE IF NOT EXISTS note_tags (
    note_id BIGINT NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
    tag     TEXT NOT NULL,
    PRIMARY KEY (note_id, tag)
);

-- What makes this worth having over reading the files: finding a phrase across
-- everything, instantly, however much there is.
CREATE INDEX IF NOT EXISTS notes_search
    ON notes USING GIN (to_tsvector('english', title || ' ' || body));
CREATE INDEX IF NOT EXISTS notes_folder ON notes (folder);
CREATE INDEX IF NOT EXISTS notes_updated ON notes (updated_at DESC);
EOF
    return 0
}

# ---------------------------------------------------------------------------

cmd_install() {
    step 'Setting up your company memory'
    make_folders
    make_obsidian

    # Postgres only where it already exists. Installing it would add several
    # minutes and a supervised service to every customer's setup, to answer
    # questions the file beside the notes answers just as well.
    if pg_bin >/dev/null 2>&1 && start_postgres; then
        make_tables && good 'Index tables ready.'
        say ''
        say "Register the index as a Zo service so it stays running, with:"
        say "  label      second-brain-index"
        say "  entrypoint $(pg_bin)/postgres -D $PGDATA"
        say "  workdir    $PGDATA"
    else
        make_sqlite_index
    fi
    printf '\n'
    good 'VIMIGO_BRAIN_READY'
    say 'Your Zo now has somewhere to keep what it learns.'
    return 0
}

cmd_status() {
    local folders=0 notes=0 indexed='no'
    [ -d "$BRAIN" ] && folders="$(find "$BRAIN" -mindepth 1 -maxdepth 1 -type d ! -name '.*' 2>/dev/null | wc -l | tr -d ' ')"
    [ -d "$BRAIN" ] && notes="$(find "$BRAIN" -name '*.md' ! -name 'README.md' 2>/dev/null | wc -l | tr -d ' ')"

    local bin; bin="$(pg_bin)" || bin=''
    if [ -n "$bin" ] && "$bin/pg_ctl" -D "$PGDATA" status >/dev/null 2>&1; then
        "$bin/psql" -h "$PGRUN" -p "$PGPORT" -U postgres -d "$DB" -tAc 'SELECT 1' >/dev/null 2>&1 && indexed='yes'
    elif [ -f "$BRAIN/.index.db" ]; then
        # Asked of the file rather than assumed from its existence: an index
        # that cannot be opened is not an index.
        python3 -c "
import sqlite3, sys
try:
    c = sqlite3.connect(sys.argv[1])
    c.execute('SELECT count(*) FROM note_search').fetchone()
    sys.exit(0)
except Exception:
    sys.exit(1)
" "$BRAIN/.index.db" 2>/dev/null && indexed='yes'
    fi

    printf 'VIMIGO_BRAIN folders=%s notes=%s indexed=%s\n' "$folders" "$notes" "$indexed"
}

case "${1:-status}" in
    install) cmd_install ;;
    status)  cmd_status ;;
    *) say 'Use: install | status'; exit 2 ;;
esac
