"""Run unchanged production headers with C++ shims and terminal API test doubles.

g++ is required. This is not MetaEditor compilation or a real-broker backtest.
"""

from pathlib import Path
import os
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class MT5ProductionCoreTests(unittest.TestCase):
    def compile_and_run(self, source: str) -> None:
        compiler = shutil.which(os.environ.get("CXX", "g++"))
        self.assertIsNotNone(compiler, "Install g++ (C++17) or set CXX to a compatible compiler.")
        with tempfile.TemporaryDirectory(prefix="super-scalper-tests-") as directory:
            output = str(Path(directory) / "test")
            flags = ["-std=c++17", "-O2", "-Wall", "-Wextra", "-Werror", "-pedantic"]
            if os.environ.get("SC_SANITIZE") == "1":
                flags += ["-O1", "-g", "-fsanitize=address,undefined", "-fno-omit-frame-pointer"]
            compiled = subprocess.run(
                [compiler, *flags, str(ROOT / "tests" / source), "-o", output],
                capture_output=True, text=True, timeout=120, check=False,
            )
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            executed = subprocess.run(
                [output], capture_output=True, text=True, timeout=120, check=False,
            )
            self.assertEqual(executed.returncode, 0, executed.stdout + executed.stderr)

    def test_indicators(self) -> None:
        self.compile_and_run("mt5_indicators.cpp")

    def test_fixed_lot_risk_math(self) -> None:
        self.compile_and_run("mt5_risk.cpp")

    def test_clock_routing_and_signal_engine(self) -> None:
        self.compile_and_run("mt5_engine.cpp")

    def test_order_execution_and_durable_guard(self) -> None:
        self.compile_and_run("mt5_execution.cpp")


if __name__ == "__main__":
    unittest.main()
