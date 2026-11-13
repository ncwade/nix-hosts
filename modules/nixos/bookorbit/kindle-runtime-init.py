"""Initialize private Calibre preferences without importing account credentials."""
import json
import os
from pathlib import Path
import stat
import sys
import tempfile


def initialize(directory):
    os.umask(0o077)
    root = Path(directory)
    if not root.is_absolute():
        raise ValueError("Calibre configuration path must be absolute")
    for path in (root, root / "plugins"):
        path.mkdir(mode=0o700, parents=True, exist_ok=True)
        info = path.lstat()
        if (not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid()
                or stat.S_IMODE(info.st_mode) & 0o077):
            raise ValueError("Calibre configuration must be private and owned by this user")
    destination = root / "plugins" / "dedrm.json"
    values = {}
    if destination.exists() or destination.is_symlink():
        info = destination.lstat()
        if (not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid()
                or stat.S_IMODE(info.st_mode) & 0o077):
            raise ValueError("DeDRM configuration must be a private regular file")
        values = json.loads(destination.read_text())
        if not isinstance(values, dict):
            raise ValueError("Invalid DeDRM configuration")
    # Preserve explicit keys on reruns. No account credentials enter this file
    # until the separate authorized acquisition adapter supplies them.
    values.update(configured=True, remove_watermarks=False, deobfuscate_fonts=False)
    for key, default in {"serials": [], "pids": [], "kindlekeys": {},
                         "androidkeys": {}, "kindleextrakeyfile": ""}.items():
        values.setdefault(key, default)
    descriptor, temporary = tempfile.mkstemp(dir=destination.parent, prefix=".dedrm-")
    try:
        with os.fdopen(descriptor, "w") as output:
            json.dump(values, output)
            output.flush()
            os.fsync(output.fileno())
        os.replace(temporary, destination)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    initialize(sys.argv[1])
