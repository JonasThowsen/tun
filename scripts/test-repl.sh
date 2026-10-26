#!/usr/bin/env bash
# Exercise bin/repl: Slynk answers on 127.0.0.1, a busy port and a bad
# command line fail with their exit codes.
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/tun-repl.XXXXXX")"
repl=""
trap '[ -n "$repl" ] && kill "$repl" 2>/dev/null; rm -rf "$work"' EXIT

expect_exit() {
  local expected="$1" status=0
  shift
  "$@" </dev/null >"$work/output" 2>&1 || status=$?
  if [ "$status" -ne "$expected" ]; then
    cat "$work/output" >&2
    echo "expected exit $expected, got $status" >&2
    exit 1
  fi
}

port="$(python3 -c '
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
print(s.getsockname()[1])')"

# The smallest system keeps the check fast; without a terminal bin/repl
# stays up until it is stopped.
"$here/bin/repl" --port "$port" tun/core </dev/null >"$work/repl.log" 2>&1 &
repl=$!
for _ in $(seq 1 300); do
  grep -q 'bin/repl: tun/core loaded' "$work/repl.log" && break
  kill -0 "$repl" 2>/dev/null || { cat "$work/repl.log" >&2; echo "bin/repl exited" >&2; exit 1; }
  sleep 0.5
done
grep -q 'bin/repl: tun/core loaded' "$work/repl.log" || { cat "$work/repl.log" >&2; exit 1; }

# The first request SLY sends on connecting, in Slynk's wire format: six hex
# digits of length, then the message.
python3 - "$port" <<'PY'
import socket, sys
connection = socket.create_connection(("127.0.0.1", int(sys.argv[1])), timeout=30)
request = b'(:emacs-rex (slynk:connection-info) "COMMON-LISP-USER" t 1)'
connection.sendall(b"%06x" % len(request) + request)

def receive(n):
    data = b""
    while len(data) < n:
        chunk = connection.recv(n - len(data))
        assert chunk, "Slynk closed the connection"
        data += chunk
    return data

while True:
    reply = receive(int(receive(6), 16)).decode()
    if reply.startswith("(:return"):
        break
assert reply.startswith("(:return (:ok (:pid "), reply[:200]
assert ':lisp-implementation (:type "SBCL"' in reply, reply[:200]
assert ":version " in reply, reply[:200]
PY

# Slynk binds the loopback interface only: the kernel's table of listening
# sockets has the port on 127.0.0.1 (0100007F) and nowhere else.
python3 - "$port" <<'PY'
import sys
port = "%04X" % int(sys.argv[1])
listening = [fields[1].split(":")[0]
             for table in ("/proc/net/tcp", "/proc/net/tcp6")
             for fields in (line.split() for line in open(table).readlines()[1:])
             if fields[1].endswith(":" + port) and fields[3] == "0A"]
assert listening == ["0100007F"], listening
PY

expect_exit 1 "$here/bin/repl" --port "$port" tun/core
grep -q 'cannot listen on 127.0.0.1' "$work/output"
expect_exit 2 "$here/bin/repl" --port nonsense
expect_exit 2 "$here/bin/repl" --verbose
echo "== REPL CLI checks passed"
