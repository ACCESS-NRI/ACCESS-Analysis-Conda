import tempfile
import unittest
from datetime import date
from pathlib import Path

from scripts.prepare_monthly_analysis3 import next_version, prepare, target_for


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

    def test_missed_month_is_prepared_before_next_month(self):
        self.assertEqual(target_for(date(2026, 11, 2), "26.10"), "26.11")
        self.assertEqual(target_for(date(2026, 11, 28), "26.10"), "26.11")

    def test_already_prepared_next_month_is_not_advanced_early(self):
        self.assertEqual(target_for(date(2026, 10, 29), "26.11"), "26.11")
        self.assertEqual(target_for(date(2026, 12, 31), "26.12"), "27.01")


if __name__ == "__main__":
    unittest.main()
