# SPDX-License-Identifier: LGPL-2.1-or-later
"""Unix terminal/signal instrumentation for the real Rust supervisor and Nu launcher."""
import errno
import os
from pathlib import Path
import pty
import signal
import subprocess
import sys
import tempfile
import time


def main(runtime, launcher, nu):
    with tempfile.TemporaryDirectory(prefix="anthracite-signals-") as directory:
        root = Path(directory)
        probe = root / "application with spaces"
        probe.write_text(f"#!{sys.executable}\n" + '''
import os, signal, time
def record(text):
    with open(os.environ["SIGNAL_LOG"], "a") as log:
        log.write(text + "\\n")
def interrupted(signum, frame):
    record("INT")
def terminated(signum, frame):
    record("TERM")
    raise SystemExit(0)
signal.signal(signal.SIGINT, interrupted)
signal.signal(signal.SIGTERM, signal.SIG_IGN if os.environ.get("STUBBORN") else terminated)
record("READY " + str(os.getpid()))
while True:
    time.sleep(0.1)
''')
        probe.chmod(0o700)
        for action in ("ctrl-c", "sigterm", "stubborn"):
            log = root / f"{action}.log"
            env = dict(os.environ, SIGNAL_LOG=str(log))
            for kind in ("CONFIG", "DATA", "STATE", "CACHE"):
                env[f"XDG_{kind}_HOME"] = str(root / kind.lower())
            if action == "stubborn":
                env["STUBBORN"] = "1"
            pid, terminal = pty.fork()
            if pid == 0:
                os.execve(nu, [nu, "--no-config-file", launcher, str(probe), "--supervisor", runtime], env)
            child = None
            reaped = False
            os.set_blocking(terminal, False)
            output = bytearray()

            def drain():
                try:
                    while True:
                        chunk = os.read(terminal, 65536)
                        if not chunk:
                            break
                        output.extend(chunk)
                except OSError as error:
                    if error.errno not in (errno.EAGAIN, errno.EIO):
                        raise

            try:
                deadline = time.monotonic() + 15
                while time.monotonic() < deadline:
                    drain()
                    if log.exists() and "READY " in log.read_text():
                        child = int(log.read_text().splitlines()[0].split()[1])
                        break
                    time.sleep(0.02)
                assert child, f"{action}: application did not start: {output.decode(errors='replace')}"
                assert os.getpgid(child) != os.getpgid(pid), "Application shares terminal signal group"
                if action == "sigterm":
                    os.kill(pid, signal.SIGTERM)
                else:
                    os.write(terminal, b"\x03")  # Actual terminal Ctrl-C, not a simulated callback.
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    drain()
                    done, status = os.waitpid(pid, os.WNOHANG)
                    if done:
                        reaped = True
                        assert os.waitstatus_to_exitcode(status) == 0, (action, status)
                        break
                    time.sleep(0.02)
                assert reaped, f"{action}: supervisor did not exit"
                lines = log.read_text().splitlines()
                assert "INT" not in lines, lines
                if action != "stubborn":
                    assert "TERM" in lines, lines
                try:
                    os.kill(child, 0)
                except ProcessLookupError:
                    pass
                else:
                    raise AssertionError(f"{action}: application was not reaped")
            finally:
                if not reaped:
                    if child:
                        try:
                            os.killpg(child, signal.SIGKILL)
                        except ProcessLookupError:
                            pass
                    try:
                        os.kill(pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass
                os.close(terminal)
                if not reaped:
                    deadline = time.monotonic() + 2
                    while time.monotonic() < deadline:
                        if os.waitpid(pid, os.WNOHANG)[0]:
                            break
                        time.sleep(0.02)
        result = subprocess.run([runtime, "--supervise", sys.executable, "-c", "raise SystemExit(7)"], timeout=10)
        assert result.returncode == 7, result
        missing = subprocess.run([runtime, "--supervise", str(root / "missing")], capture_output=True, timeout=10)
        assert missing.returncode != 0
    print("Signal supervision tests passed.", flush=True)


if __name__ == "__main__":
    main(*sys.argv[1:])
