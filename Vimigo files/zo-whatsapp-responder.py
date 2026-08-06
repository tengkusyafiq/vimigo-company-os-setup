#!/usr/bin/env python3
"""Answers WhatsApp messages, the way the Zo web chat answers.

Pairing a number only makes the bridge sync messages into a database. Nothing
reads them, so nothing replies - which meant a customer's assistant sat there
looking connected and never said a word. This is the missing half.

    someone's phone
        -> the bridge (one per number)
        -> POST to this, on 127.0.0.1
        -> zo, the same engine behind the web chat
        -> back out through the bridge

One of these runs per WhatsApp number. Which assistant answers is decided here,
by ASSISTANT_BRIEF, rather than by anything on Zo's side: Zo binds a persona to
whichever channel the request came from, and there is no way to say "that one"
from outside. Owning the responder makes it exact.

Configured entirely by environment, so no secret is ever written into a command
line where the process list would show it:

    BRIDGE_URL        http://127.0.0.1:8080
    BRIDGE_API_KEY    the instance's own key, from its .env
    LISTEN_PORT       where the bridge posts to, on loopback only
    STATE_DIR         where conversations and seen ids are remembered
    ASSISTANT_NAME    optional, e.g. Zoe
    ASSISTANT_BRIEF   optional, the job description for an AI employee
    OWNER_NUMBERS     optional, comma separated; when set, nobody else is
                      answered - this is what stops a stranger who messages the
                      owner's assistant number from giving it instructions
    ALLOW_GROUPS      "true" to answer in group chats; off by default, because
                      an assistant that replies to every group the number is in
                      is a very fast way to lose a customer

Message text is never logged. The log records that a message arrived and how
long the answer took, and nothing a customer wrote.
"""

import json
import os
import queue
import re
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

BRIDGE_URL = os.environ.get("BRIDGE_URL", "http://127.0.0.1:8080").rstrip("/")
BRIDGE_API_KEY = os.environ.get("BRIDGE_API_KEY", "")
LISTEN_PORT = int(os.environ.get("LISTEN_PORT", "9080"))
STATE_DIR = os.environ.get("STATE_DIR", "/home/workspace/Services/vimigo-setup/responder-state")
ASSISTANT_NAME = os.environ.get("ASSISTANT_NAME", "").strip()
ASSISTANT_BRIEF = os.environ.get("ASSISTANT_BRIEF", "").strip()
ALLOW_GROUPS = os.environ.get("ALLOW_GROUPS", "false").lower() == "true"

OWNER_NUMBERS = {
    re.sub(r"\D", "", part)
    for part in os.environ.get("OWNER_NUMBERS", "").split(",")
    if re.sub(r"\D", "", part)
}

# The owner's own assistant must never take instructions from a stranger who
# happens to have the number. Set for a personal assistant, and then an empty
# allowlist stops the responder from starting at all rather than quietly
# answering the world - a guarantee that survives someone forgetting a flag.
REQUIRE_ALLOWLIST = os.environ.get("REQUIRE_ALLOWLIST", "false").lower() == "true"

# Off unless somebody deliberately turned it on.
#
# This is the default on purpose, and it is the important one. An AI employee
# created by the setup has a job title and nothing else - no products, no
# prices, no policy, no idea what the business actually does. Letting that
# answer a customer the moment it is created is worse than not having it at
# all, because the customer believes what it says.
#
# So a responder installed for an employee accepts messages, records them, and
# says nothing, until the owner has taught it its job and switched it on.
ENABLED = os.environ.get("ENABLED", "false").lower() == "true"

# Added to the end of every reply, so whoever reads it knows they are talking
# to an assistant and not to a person. Set it empty to switch it off.
SIGNATURE = os.environ.get("SIGNATURE", "\n\n— from Zo")

# Answer messages the owner sends to their own chat.
#
# Off by default and deliberately so. It is the one case where a message the
# assistant's own number sent should still be answered, which is how somebody
# with a single number can try this before buying a second SIM - and how notes
# to self can be handed to Zo later. It is also the one case that can loop, so
# it is scoped to the self-chat and guarded by the sent-message ids below.
ANSWER_SELF_CHAT = os.environ.get("ANSWER_SELF_CHAT", "false").lower() == "true"

# Long enough for Zo to think, short enough that a stuck call does not hold a
# customer waiting forever with no reply at all.
ZO_TIMEOUT = 180

# Remembered conversations are per chat, so a follow-up question knows what it
# is following up on - the same as the web chat.
STATE_PATH = os.path.join(STATE_DIR, "conversations.json")
SEEN_LIMIT = 500

_state_lock = threading.Lock()
_state = {"conversations": {}, "seen": [], "sent": []}

# Ids of messages this assistant sent itself.
#
# This is the loop guard, not the signature. A signature can be quoted back,
# copied by a customer, or repeated by the model, and any of those would either
# ignore a real message or start a loop that texts somebody forever. A message
# id is exact: the bridge hands one back for every message sent, and a message
# with that id is one this assistant wrote.
SENT_LIMIT = 200


def log(message):
    print(f"{time.strftime('%Y-%m-%d %H:%M:%S')}  {message}", flush=True)


def load_state():
    global _state
    try:
        with open(STATE_PATH, "r", encoding="utf-8") as handle:
            loaded = json.load(handle)
        _state = {
            "conversations": dict(loaded.get("conversations", {})),
            "seen": list(loaded.get("seen", [])),
            "sent": list(loaded.get("sent", [])),
        }
    except (OSError, ValueError):
        # A missing or unreadable state file is a fresh start, not a failure.
        _state = {"conversations": {}, "seen": [], "sent": []}


def save_state():
    os.makedirs(STATE_DIR, exist_ok=True)
    temporary = STATE_PATH + ".tmp"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(_state, handle)
    os.replace(temporary, STATE_PATH)


def already_answered(message_id):
    """True when this message has been handled, so a retried webhook is not
    answered twice. The bridge redelivers on its own restart."""
    if not message_id:
        return False
    with _state_lock:
        if message_id in _state["seen"]:
            return True
        _state["seen"].append(message_id)
        if len(_state["seen"]) > SEEN_LIMIT:
            del _state["seen"][:-SEEN_LIMIT]
        save_state()
    return False


# ---------------------------------------------------------------------------
# The bridge
# ---------------------------------------------------------------------------

_token = {"value": None}


def bridge_token(force_new=False):
    """A short-lived token for the bridge's own API.

    Login is at /auth/login, outside the /api prefix, and takes the key as a
    bearer header rather than in the body.
    """
    if _token["value"] and not force_new:
        return _token["value"]

    request = urllib.request.Request(
        f"{BRIDGE_URL}/auth/login",
        method="POST",
        headers={"Authorization": f"Bearer {BRIDGE_API_KEY}"},
    )
    with urllib.request.urlopen(request, timeout=15) as response:
        payload = json.load(response)
    _token["value"] = payload.get("token")
    return _token["value"]


def remember_sent(message_id):
    if not message_id:
        return
    with _state_lock:
        _state["sent"].append(message_id)
        if len(_state["sent"]) > SENT_LIMIT:
            del _state["sent"][:-SENT_LIMIT]
        save_state()


def was_sent_by_us(message_id):
    if not message_id:
        return False
    with _state_lock:
        return message_id in _state["sent"]


def set_typing(recipient, on):
    """Shows the "typing..." mark in the chat, or clears it.

    An answer takes twenty seconds or more, because a real one means Zo going
    off and doing something. Twenty seconds of nothing looks like being
    ignored, and the owner - or worse, their customer - sends the message
    again, or gives up. The mark costs one request and removes the doubt.
    """
    body = json.dumps({
        "recipient": recipient,
        "state": "composing" if on else "paused",
    }).encode("utf-8")
    try:
        request = urllib.request.Request(
            f"{BRIDGE_URL}/api/presence",
            data=body,
            method="POST",
            headers={
                "Authorization": f"Bearer {bridge_token()}",
                "Content-Type": "application/json",
            },
        )
        with urllib.request.urlopen(request, timeout=15):
            return True
    except (urllib.error.HTTPError, OSError):
        # Never worth failing an answer over. Silence here is cosmetic.
        return False


def keep_typing(recipient, stop):
    """Re-sends the mark until told to stop.

    WhatsApp clears it after a few seconds, so one request at the start would
    show "typing..." briefly and then nothing - which is worse than never
    showing it, because it looks like the assistant started and gave up.
    """
    while not stop.wait(4):
        if not set_typing(recipient, True):
            return


def send_message(recipient, text):
    body = json.dumps({"recipient": recipient, "message": text}).encode("utf-8")

    for attempt in (1, 2):
        try:
            request = urllib.request.Request(
                f"{BRIDGE_URL}/api/send",
                data=body,
                method="POST",
                headers={
                    "Authorization": f"Bearer {bridge_token(force_new=attempt == 2)}",
                    "Content-Type": "application/json",
                },
            )
            with urllib.request.urlopen(request, timeout=60) as response:
                answer = json.load(response)
                # Recorded before anything else can react to it. In the
                # self-chat this reply comes straight back through the webhook,
                # and this id is what stops it being answered again.
                remember_sent(answer.get("message_id"))
                return answer.get("success", False)
        except urllib.error.HTTPError as error:
            # A token lasts a while but not forever. One silent retry with a
            # fresh one, rather than a customer never getting their answer.
            if error.code in (401, 403) and attempt == 1:
                continue
            log(f"send failed: HTTP {error.code}")
            return False
        except OSError as error:
            log(f"send failed: {error.__class__.__name__}")
            return False
    return False


# ---------------------------------------------------------------------------
# Zo
# ---------------------------------------------------------------------------

def build_prompt(text, sender_name):
    """What Zo is asked.

    Without a brief this is close to a straight pass-through, so the assistant
    answers exactly as it would in the web chat. The one thing always added is
    the medium: a web chat answer with headings, bullet tables and code blocks
    arrives on a phone as unreadable clutter.
    """
    lines = []
    if ASSISTANT_BRIEF:
        who = ASSISTANT_NAME or "an assistant"
        lines.append(f"You are {who}. {ASSISTANT_BRIEF}")
        lines.append("")
    lines.append(
        "You are replying inside a WhatsApp chat. Keep it short and plain - no "
        "headings, no tables, no markdown, no code blocks. Write the way a "
        "person types on their phone. Never mention files, commands, paths or "
        "settings; if something cannot be done, say so in one sentence."
    )
    lines.append("")
    if sender_name:
        lines.append(f"Message from {sender_name}:")
    lines.append(text)
    return "\n".join(lines)


def ask_zo(prompt, conversation_id):
    command = ["zo", prompt]
    if conversation_id:
        command += ["--conversation-id", conversation_id]

    try:
        finished = subprocess.run(
            command, capture_output=True, text=True, timeout=ZO_TIMEOUT
        )
    except subprocess.TimeoutExpired:
        log("zo timed out")
        return None, conversation_id

    if finished.returncode != 0:
        log(f"zo exited {finished.returncode}")
        return None, conversation_id

    # zo answers with {"output": "...", "conversation_id": "..."}. Anything
    # else is treated as the answer itself rather than thrown away.
    raw = (finished.stdout or "").strip()
    try:
        parsed = json.loads(raw)
        return parsed.get("output"), parsed.get("conversation_id") or conversation_id
    except ValueError:
        return (raw or None), conversation_id


# ---------------------------------------------------------------------------
# Handling one message
# ---------------------------------------------------------------------------

work = queue.Queue()


def handle(event):
    chat = event.get("chat_jid") or ""
    text = (event.get("content") or "").strip()
    sender_name = (event.get("push_name") or "").strip()

    started = time.time()
    with _state_lock:
        conversation_id = _state["conversations"].get(chat)

    # "typing..." for as long as it takes, so the wait looks like thinking
    # rather than like nothing happening.
    stop_typing = threading.Event()
    set_typing(chat, True)
    threading.Thread(target=keep_typing, args=(chat, stop_typing), daemon=True).start()
    try:
        answer, conversation_id = ask_zo(build_prompt(text, sender_name), conversation_id)
    finally:
        stop_typing.set()
        set_typing(chat, False)

    if conversation_id:
        with _state_lock:
            _state["conversations"][chat] = conversation_id
            save_state()

    if not answer:
        # One plain sentence rather than silence. Silence reads as broken, and
        # the owner cannot tell the difference between thinking and dead.
        answer = "Sorry, I could not answer that just now. Please try again."

    # Signed, so nobody is left wondering whether they are talking to a person.
    # It identifies the reply; it is not what stops a loop - see remember_sent.
    if SIGNATURE and not answer.rstrip().endswith(SIGNATURE.strip()):
        answer = answer.rstrip() + SIGNATURE

    sent = send_message(chat, answer)
    # The chat is identified by its last three digits and nothing more. A log
    # of who messages a business, kept on disk, is a customer list.
    log(f"answered ...{chat.split('@')[0][-3:]} in {time.time() - started:.1f}s sent={sent}")


def worker():
    while True:
        event = work.get()
        try:
            handle(event)
        except Exception as error:  # noqa: BLE001 - a bad message must not stop the rest
            log(f"failed to answer: {error.__class__.__name__}")
        finally:
            work.task_done()


# ---------------------------------------------------------------------------
# The webhook
# ---------------------------------------------------------------------------

def is_self_chat(event):
    """The owner's own "message yourself" chat.

    The bridge acts as the number it is linked to, so a message from that
    number to that number is the owner talking to themselves - and the only
    place an is_from_me message should ever be answered.
    """
    chat = str(event.get("chat_jid") or "").split("@")[0].split(":")[0]
    sender = str(event.get("sender") or "").split(":")[0]
    return bool(chat) and chat == sender


def should_answer(event):
    # Nothing at all until somebody switched this on.
    if not ENABLED:
        return False, "not switched on yet"

    # A reply this assistant sent. Checked before anything else that could
    # answer, because in the self-chat it arrives back through the webhook
    # looking like a new message, and answering it would text somebody in a
    # loop forever.
    if was_sent_by_us(event.get("message_id")):
        return False, "our own reply"

    if event.get("is_from_me"):
        if not (ANSWER_SELF_CHAT and is_self_chat(event)):
            return False, "own message"
    if event.get("is_group") and not ALLOW_GROUPS:
        return False, "group chat"
    if event.get("message_type") != "text":
        return False, "not text"
    if not (event.get("content") or "").strip():
        return False, "empty"

    if OWNER_NUMBERS:
        sender = re.sub(r"\D", "", str(event.get("sender") or ""))
        if sender not in OWNER_NUMBERS:
            return False, "not the owner"
    return True, ""


class Webhook(BaseHTTPRequestHandler):
    def do_POST(self):  # noqa: N802 - the name is fixed by http.server
        length = int(self.headers.get("Content-Length") or 0)
        raw = self.rfile.read(length) if length else b""

        # Answered immediately and thought about afterwards. The bridge is
        # single threaded on this path, so holding it open while Zo thinks
        # would stall every other message arriving on the number.
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"ok":true}')

        try:
            event = json.loads(raw.decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            return

        wanted, why = should_answer(event)
        if not wanted:
            log(f"skipped ({why})")
            return
        if already_answered(event.get("message_id")):
            log("skipped (already answered)")
            return

        work.put(event)

    def do_GET(self):  # noqa: N802
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        # The pid is here so a restart can be told apart from an old process
        # that never died and is still serving the previous settings.
        self.wfile.write(json.dumps({
            "ok": True,
            "pid": os.getpid(),
            "enabled": ENABLED,
            "assistant": ASSISTANT_NAME or "assistant",
            "allowlisted": len(OWNER_NUMBERS),
            "queued": work.qsize(),
        }).encode("utf-8"))

    def log_message(self, *_args):
        # Silenced deliberately: the default handler writes the request line
        # for every message, and this runs on a customer's own server.
        pass


def main():
    if not BRIDGE_API_KEY:
        print("BRIDGE_API_KEY is required", file=sys.stderr)
        return 2

    if REQUIRE_ALLOWLIST and not OWNER_NUMBERS:
        print(
            "REQUIRE_ALLOWLIST is set but OWNER_NUMBERS is empty. Refusing to "
            "start: this assistant would answer anyone who found the number.",
            file=sys.stderr,
        )
        return 2

    load_state()
    threading.Thread(target=worker, daemon=True).start()

    if not ENABLED:
        log("NOT switched on: messages are accepted and nobody is answered")

    # Loopback only, always. The bridge posts from the same machine, and this
    # endpoint has no authentication of its own - anything that could reach it
    # could put words in the assistant's mouth.
    server = HTTPServer(("127.0.0.1", LISTEN_PORT), Webhook)
    log(f"listening on 127.0.0.1:{LISTEN_PORT}, bridge at {BRIDGE_URL}")
    if OWNER_NUMBERS:
        log(f"answering {len(OWNER_NUMBERS)} known number(s) only")
    else:
        log("answering anyone who messages this number")
    server.serve_forever()
    return 0


if __name__ == "__main__":
    sys.exit(main())
