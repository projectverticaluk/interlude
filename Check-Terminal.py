"""Run with python3 on macOS to check both launch paths in a simulated terminal."""
import fcntl
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import struct
import termios
import time

folder = Path(__file__).resolve().parent
for command in ([str(folder / 'Start.command'), '-NoMovie'],
                [shutil.which('pwsh'), '-NoLogo', '-NoProfile', '-File',
                 str(folder / 'run.ps1'), '-NoMovie']):
    pid, fd = pty.fork()
    if pid == 0:
        os.environ['TERM'] = 'xterm-256color'
        os.execv(command[0], command)
    fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', 24, 80, 0, 0))
    output = b''
    resized = False
    sent_quit = False
    try:
        deadline = time.monotonic() + 20
        while time.monotonic() < deadline:
            if not select.select([fd], [], [], .05)[0]:
                continue
            try:
                data = os.read(fd, 65536)
            except OSError:
                break
            if not data:
                break
            output += data
            if b'\x1b[6n' in data:
                os.write(fd, b'\x1b[1;1R')
            if not resized and b'\x1b[8;45;129t' in output:
                fcntl.ioctl(fd, termios.TIOCSWINSZ, struct.pack('HHHH', 45, 129, 0, 0))
                os.kill(pid, signal.SIGWINCH)
                resized = True
            if not sent_quit and b'Maz is fixing your shit :)' in output:
                os.write(fd, b'q')
                sent_quit = True
        else:
            raise AssertionError('Terminal test timed out')
        _, status = os.waitpid(pid, 0)
        assert resized and sent_quit, repr(output[-1000:])
        assert os.waitstatus_to_exitcode(status) == 0, repr(output[-1000:])
        assert b'Enlarge terminal' not in output, 'Resize request was not applied before drawing'
        assert b'\x1b[?25h' in output, 'Cursor not restored'
        print('PASS: resize, title and exit via', Path(command[0]).name)
    finally:
        os.close(fd)
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
