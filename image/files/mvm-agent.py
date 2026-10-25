#!/usr/bin/env python3
"""mvm-agent: the MicroVM entrypoint.

  :9000  lifecycle hooks (POST /aws/lambda-microvms/runtime/v1/<hook>)
  :2222  WebSocket -> 127.0.0.1:22 bridge (websocat, one TCP stream per WebSocket)

Both listen on all interfaces because the platform delivers hooks and endpoint traffic from outside
the VM's loopback. The only inbound path is the MicroVM endpoint, which admits a connection only with
a CreateMicrovmAuthToken token (IAM, SigV4) for that port. That token is enough to reach :9000, so
/run is accepted once; :2222 additionally needs the SSH key. sshd itself listens on 127.0.0.1 only.

The image snapshot is taken when /ready returns, so nothing unique per VM (host key,
authorized key, environment) may exist before /run. /run creates them from runHookPayload.
"""

import base64
import json
import os
import pwd
import re
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOOK_PREFIX = "/aws/lambda-microvms/runtime/v1/"
USER = "dev"
HOME = f"/home/{USER}"
HOST_KEY = "/etc/ssh/ssh_host_ed25519_key"
WEBSOCAT = ["/usr/local/bin/websocat", "--binary", "--exit-on-eof", "ws-l:0.0.0.0:2222", "tcp:127.0.0.1:22"]
SSHD = ["/usr/sbin/sshd", "-D", "-e"]
# Only these variables may come from runHookPayload; values must be printable.
ENV_ALLOWED = {"AWS_REGION", "AWS_DEFAULT_REGION", "TZ"}
ENV_VALUE = re.compile(r"^[\x20-\x7e]{0,256}$")
MAX_BODY = 64 * 1024

children = {}
children_lock = threading.Lock()
sshd_wanted = threading.Event()
# The hooks port is also reachable through the VM endpoint by anyone who can mint an auth token for
# port 9000, so /run (which installs the SSH key) is accepted exactly once: the platform's call.
run_lock = threading.Lock()
run_done = False


def log(*args):
    print(time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "[mvm-agent]", *args, flush=True)


def supervise(name, argv, wanted=None):
    """Keep argv running (restart after 1 s if it exits) while `wanted` is set (always if None)."""
    while True:
        if wanted is not None:
            wanted.wait()
        proc = subprocess.Popen(argv, stdin=subprocess.DEVNULL)
        with children_lock:
            children[name] = proc
        log(name, "started pid", proc.pid)
        code = proc.wait()
        log(name, "exited", code)
        time.sleep(1)


def reap_orphans():
    """As PID 1, collect exited orphans (e.g. git's credential-cache daemon after ssh sessions end).
    A supervised child reaped here makes its Popen.wait() return 0, which still triggers a restart."""
    while True:
        try:
            while os.waitpid(-1, os.WNOHANG)[0]:
                pass
        except ChildProcessError:
            pass
        time.sleep(5)


def unwrap(raw, depth=0):
    """/run delivers {"microvmId", "runHookPayload": "<string given to RunMicrovm>"}; the inner
    string may be JSON or base64(JSON). Unwrap until we reach the config object."""
    if depth > 4:
        return {}
    value = raw
    if isinstance(value, (bytes, str)):
        text = value.decode() if isinstance(value, bytes) else value
        text = text.strip()
        if not text:
            return {}
        try:
            value = json.loads(text)
        except ValueError:
            try:
                return unwrap(base64.b64decode(text, validate=True), depth + 1)
            except ValueError:
                return {}
        if isinstance(value, str):
            return unwrap(value, depth + 1)
    if not isinstance(value, dict):
        return {}
    if isinstance(value.get("runHookPayload"), str):
        inner = unwrap(value["runHookPayload"], depth + 1)
        if isinstance(value.get("microvmId"), str):
            inner.setdefault("microvmId", value["microvmId"])
        return inner
    return value


def write_file(path, content, mode, uid=0, gid=0):
    """Atomically replace path. mkstemp (O_EXCL) plus fchown/fchmod never follow a symlink planted
    in a user-owned directory, and rename replaces a symlink at `path` instead of following it."""
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".mvm-")
    try:
        os.fchown(fd, uid, gid)
        os.fchmod(fd, mode)
        with os.fdopen(fd, "w") as f:
            f.write(content)
        os.replace(tmp, path)
    except BaseException:
        os.unlink(tmp)
        raise


def on_run(cfg):
    log("run", cfg.get("microvmId", ""), "keys:", ",".join(sorted(cfg)))

    # Per-VM host key. Remove anything that may have come from the image so no two VMs share one.
    for suffix in ("", ".pub"):
        try:
            os.remove(HOST_KEY + suffix)
        except FileNotFoundError:
            pass
    subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", HOST_KEY], check=True)

    pw = pwd.getpwnam(USER)
    keys = cfg.get("authorizedKeys")
    lines = [l.strip() for l in keys.splitlines() if l.strip().startswith(("ssh-", "ecdsa-", "sk-"))] if isinstance(keys, str) else []
    if not lines:
        raise ValueError("runHookPayload has no authorizedKeys")
    if lines:
        ssh_dir = f"{HOME}/.ssh"
        if os.path.islink(ssh_dir):
            raise RuntimeError(f"{ssh_dir} is a symlink")
        os.makedirs(ssh_dir, mode=0o700, exist_ok=True)
        os.lchown(ssh_dir, pw.pw_uid, pw.pw_gid)
        write_file(f"{HOME}/.ssh/authorized_keys", "\n".join(lines) + "\n", 0o600, pw.pw_uid, pw.pw_gid)

    # pam_env reads /etc/environment for every SSH session, interactive or not.
    env = cfg.get("env") if isinstance(cfg.get("env"), dict) else {}
    pairs = {k: v for k, v in env.items() if k in ENV_ALLOWED and isinstance(v, str) and ENV_VALUE.match(v)}
    if isinstance(cfg.get("microvmId"), str) and re.match(r"^microvm-[0-9a-f-]{1,64}$", cfg["microvmId"]):
        pairs["MVM_ID"] = cfg["microvmId"]
    write_file("/etc/environment", "".join(f"{k}={v}\n" for k, v in pairs.items()), 0o644)

    expires = cfg.get("expiresAt")
    if isinstance(expires, (int, float)):
        write_file("/etc/mvm-expires-at", f"{int(expires // 1000)}\n", 0o644)

    sshd_wanted.set()


class Hooks(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def reply(self, code, body=b""):
        self.send_response(code)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        self.reply(200, b"mvm-agent\n")

    def do_POST(self):
        hook = self.path[len(HOOK_PREFIX):] if self.path.startswith(HOOK_PREFIX) else self.path.strip("/")
        global run_done
        try:
            length = int(self.headers.get("Content-Length") or 0)
            if length < 0:
                return self.reply(400)
            if length > MAX_BODY:
                return self.reply(413)
            body = self.rfile.read(length) if length else b""
            log("hook", hook, f"({len(body)} bytes)" if body else "", "from", self.client_address[0])
            if hook == "run":
                with run_lock:
                    if run_done:
                        log("rejected repeated /run")
                        return self.reply(409)
                    # Closed even if this first call fails: a VM that never got its key stays unusable
                    # rather than open to whoever sends the next /run.
                    run_done = True
                    on_run(unwrap(body))
            elif hook == "resume":
                sshd_wanted.set()
            self.reply(200)
        except Exception as e:  # report the failure to the platform instead of hanging the hook
            log("hook error", hook, repr(e))
            self.reply(500, str(e).encode())


def main():
    threading.Thread(target=supervise, args=("websocat", WEBSOCAT), daemon=True).start()
    threading.Thread(target=supervise, args=("sshd", SSHD, sshd_wanted), daemon=True).start()
    if os.getpid() == 1:
        threading.Thread(target=reap_orphans, daemon=True).start()
    server = ThreadingHTTPServer(("0.0.0.0", 9000), Hooks)
    log("hooks listening :9000, bridge :2222")
    server.serve_forever()


if __name__ == "__main__":
    sys.exit(main())
