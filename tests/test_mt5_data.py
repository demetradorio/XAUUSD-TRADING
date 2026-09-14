"""Compile and run the deterministic fixture against production Data.mqh."""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MT5DataFixtureTests(unittest.TestCase):
    def test_data_header_fixture(self) -> None:
        compiler = shutil.which(os.environ.get("CXX", "g++"))
        self.assertIsNotNone(compiler, "Install g++ (C++17) or set CXX to a compatible compiler.")
        with tempfile.TemporaryDirectory(prefix="super-scalper-data-") as directory:
            output = str(Path(directory) / "test")
            flags = ["-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", "-pedantic"]
            if os.environ.get("SC_SANITIZE") == "1":
                flags += ["-O1", "-g", "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
            compiled = subprocess.run(
                [compiler, *flags, str(ROOT / "tests" / "mt5_data.cpp"), "-o", output],
                capture_output=True,
                text=True,
                timeout=120,
                check=False,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            executed = subprocess.run(
                [output], capture_output=True, text=True, timeout=120, check=False
            )
            self.assertEqual(executed.returncode, 0, executed.stdout + executed.stderr)


if __name__ == "__main__":
    unittest.main()
