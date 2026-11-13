"""Regression tests for the lightweight generated-environment security gate."""

import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location(
    "security", Path(__file__).resolve().parents[1] / "scripts/check_analysis3_security.py"
)
security = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(security)


class SecurityPolicyTests(unittest.TestCase):
    def test_security_floors(self):
        self.assertEqual(security.check_versions(security.MINIMUMS.copy()), [])
        for name in security.MINIMUMS:
            with self.subTest(package=name):
                versions = security.MINIMUMS.copy()
                versions[name] = "0.0.1"
                self.assertTrue(security.check_versions(versions))

    def test_missing_required_but_optional_tools_may_be_absent(self):
        required = {name: security.MINIMUMS[name] for name in security.REQUIRED}
        self.assertEqual(security.check_versions(required), [])
        for name in required:
            with self.subTest(package=name):
                self.assertTrue(security.check_versions({k: v for k, v in required.items() if k != name}))

    def test_wrong_python_minor_and_prereleases(self):
        for version in ("3.13.1", "3.12.16rc1", "3.12.*"):
            with self.subTest(version=version):
                versions = security.MINIMUMS.copy()
                versions["python"] = version
                self.assertTrue(security.check_versions(versions))

    def test_pixi_export_and_optional_pypi_packages(self):
        versions, errors = security.export_versions(
            "dependencies:\n- python ==3.12.16 h5f976f7_0_cpython\n"
            "- pip ==26.2.2 pyh8b19718_0\n- pip\n- pip:\n  - uv==0.13.6\n"
            "  - py-rattler==0.28.1\n"
        )
        self.assertEqual(errors, [])
        self.assertEqual(versions, {
            "python": "3.12.16", "pip": "26.2.2", "uv": "0.13.6", "py-rattler": "0.28.1",
        })

    def test_unpinned_duplicate_and_prerelease_exports_fail(self):
        for spec in ("- python >=3.12.16", "- python ==3.12.16rc1", "- python ==3.12.16\n- python ==3.12.13"):
            with self.subTest(spec=spec):
                self.assertTrue(security.export_versions(spec)[1])


if __name__ == "__main__":
    unittest.main()
