import tempfile
import unittest
from pathlib import Path

from scripts.prepare_monthly_analysis3 import next_version, prepare


class MonthlyAnalysis3Tests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.config = Path(self.directory.name) / "config.sh"
        self.config.write_text(
            "export VERSION_TO_MODIFY=26.10\n"
            "export STABLE_VERSION=26.09\n"
            "export UNSTABLE_VERSION=26.10\n"
            "export FULLENV=\"${ENVIRONMENT}-${VERSION_TO_MODIFY}\"\n"
        )

    def test_advances_release_and_is_idempotent(self):
        self.assertTrue(prepare(self.config, "26.11"))
        self.assertIn("export VERSION_TO_MODIFY=26.11", self.config.read_text())
        self.assertIn("export STABLE_VERSION=26.10", self.config.read_text())
        self.assertIn("export UNSTABLE_VERSION=26.11", self.config.read_text())
        self.assertFalse(prepare(self.config, "26.11"))

    def test_rejects_skipped_month(self):
        with self.assertRaisesRegex(ValueError, "skip or rewind"):
            prepare(self.config, "26.12")

    def test_rolls_year_forward(self):
        self.assertEqual(next_version("26.12"), "27.01")


if __name__ == "__main__":
    unittest.main()
