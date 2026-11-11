"""Keep the release QA plan complete and enforce its sign-off rule."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PLAN = ROOT / "docs" / "QA-TEST-PLAN.md"
SCRIPT = ROOT / "scripts" / "qa-release.sh"


class ReleaseQAPlanTests(unittest.TestCase):
    def plan(self) -> str:
        return PLAN.read_text(encoding="utf-8")

    def test_plan_has_every_test_case_and_scenario(self):
        text = self.plan()
        self.assertEqual({f"TC-{n:02d}" for n in range(1, 25)},
                         set(re.findall(r"\bTC-\d{2}\b", text)))
        self.assertEqual({f"TS-{n:02d}" for n in range(1, 25)},
                         set(re.findall(r"\bTS-\d{2}\b", text)))

    def test_plan_covers_every_reported_bug_and_requirement(self):
        text = self.plan().lower()
        for phrase in ("menu", "english", "italian", "speech.framework", "ats",
                       "transcription", "privacy", "feed", "kext", "history", "credential",
                       "tag", "panel", "diarization", "summary", "prompt", "base url",
                       "model selector", "meeting editor", "default model", "markdown",
                       "copy summary", "footer", "resize", "ui_probe"):
            self.assertIn(phrase, text)

    def test_automated_checks_reference_existing_files(self):
        references = set(re.findall(r"(?<!`)`([^`\n]+)`(?!`)", self.plan()))
        paths = [reference for reference in references
                 if reference.startswith(("scripts/", "Tests/")) and " " not in reference]
        self.assertTrue(paths)
        for path in paths:
            self.assertTrue((ROOT / path).exists(), f"missing QA target: {path}")

    def test_release_rule_is_documented_everywhere(self):
        for path in ("CLAUDE.md", "docs/DEVELOPMENT.md", "docs/UPDATES.md",
                     ".jcode/skills/cornetta/SKILL.md"):
            text = (ROOT / path).read_text(encoding="utf-8")
            self.assertIn("QA_MANUAL_SIGNOFF", text, path)
            self.assertIn("docs/QA-TEST-PLAN.md", text, path)

    def test_qa_script_is_executable_and_requires_manual_signoff(self):
        self.assertTrue(SCRIPT.is_file())
        self.assertTrue(SCRIPT.stat().st_mode & 0o111, "qa-release.sh is not executable")
        text = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("QA_MANUAL_SIGNOFF", text)
        self.assertIn("scripts/test.sh", text)
        self.assertIn("unittest", text)
        self.assertIn("localization.py --check", text)


if __name__ == "__main__":
    unittest.main()
