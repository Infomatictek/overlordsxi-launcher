"""Run the Ashita addon unit tests with LuaJIT 2.1 via Lupa."""

from pathlib import Path
import os

from lupa.luajit21 import LuaRuntime


def main() -> int:
    addon = Path(__file__).resolve().parents[1] / "addons/ashita4/soulspire_soul_actions"
    os.chdir(addon)
    failures = []
    for path in sorted(Path("tests").glob("*_test.lua")):
        try:
            LuaRuntime().execute(f"dofile({str(path)!r})")
            print(f"PASS {path.name}")
        except Exception as error:
            failures.append(path.name)
            print(f"FAIL {path.name}: {error}")
    return bool(failures)


if __name__ == "__main__":
    raise SystemExit(main())
