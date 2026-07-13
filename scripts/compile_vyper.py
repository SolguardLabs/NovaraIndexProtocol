from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    files = sorted((ROOT / "src").rglob("*.vy"))
    if not files:
        print("no Vyper files found", file=sys.stderr)
        return 1

    for file in files:
        relative = file.relative_to(ROOT)
        print(f"compiling {relative}")
        subprocess.run(
            [sys.executable, "-m", "vyper", str(file)],
            check=True,
            stdout=subprocess.DEVNULL,
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
