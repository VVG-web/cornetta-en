"""Guard the public history and tracked credentials.

The fork removed the maintainer's private address from its own commits. Upstream authors keep their
original attribution. This test also rejects tracked private-key and environment files.
"""
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
FORBIDDEN_EMAIL_DOMAINS = ("@gnivc.ru",)
FORBIDDEN_FILE_NAMES = (".env", "id_rsa", "id_ed25519", "credentials.json", "secrets.json")
FORBIDDEN_SUFFIXES = (".pem", ".p12", ".pfx", ".key")
FORBIDDEN_CONTENT = (
    "BEGIN PRIVATE KEY",
    "BEGIN OPENSSH PRIVATE KEY",
    "BEGIN RSA PRIVATE KEY",
    "TELEGRAM_TOKEN",
)


def git(*args: str) -> str:
    result = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, check=True)
    return result.stdout


class PublicHistoryGuardTests(unittest.TestCase):
    def test_no_private_maintainer_email_in_any_commit(self):
        emails = sorted(set(git("log", "--all", "--format=%ae").splitlines()))
        offenders = [email for email in emails
                     if any(email.lower().endswith(domain) for domain in FORBIDDEN_EMAIL_DOMAINS)]
        self.assertEqual(offenders, [], f"private email remains in history: {offenders}")

    def test_no_tracked_credentials_or_environment_files(self):
        offenders = []
        for name in git("ls-files").splitlines():
            path = Path(name)
            if path.name in FORBIDDEN_FILE_NAMES or path.suffix.lower() in FORBIDDEN_SUFFIXES:
                offenders.append(name)
        self.assertEqual(offenders, [], f"credential-like files are tracked: {offenders}")

    def test_no_private_key_or_access_token_in_tracked_text(self):
        offenders = []
        for name in git("ls-files").splitlines():
            if name.startswith("scripts/tests/"):
                continue
            path = ROOT / name
            if not path.is_file() or path.stat().st_size > 1_000_000:
                continue
            text = path.read_text(encoding="utf-8", errors="ignore")
            for needle in FORBIDDEN_CONTENT:
                if needle in text:
                    offenders.append(f"{name}: {needle}")
        self.assertEqual(offenders, [], "\n".join(offenders))


if __name__ == "__main__":
    unittest.main()
