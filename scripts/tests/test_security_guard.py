"""Static guards for macOS privilege, drivers, persistence, and cleanup.

These tests do not replace the real Intel audit. They prevent a future change from
quietly adding a privileged helper, a kernel/system extension, or a system-wide login item.
"""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SAFE_SERVICE_MANAGEMENT = "SMAppService.mainApp"
FORBIDDEN = {
    "SMJobBless": "privileged helper",
    "AuthorizationExecuteWithPrivileges": "privileged execution",
    "AuthorizationCreate": "authorization API",
    "NSTask": "subprocess execution",
    "osascript": "AppleScript execution",
    "kextload": "kernel extension loading",
    "kextutil": "kernel extension loading",
    "/Library/LaunchDaemons": "system daemon",
    "/Library/LaunchAgents": "system login agent",
    "/System/Library": "system modification",
    "OSSystemExtension": "system extension",
    "SystemExtensionRequest": "system extension",
    "com.apple.security.cs.disable-library-validation": "hardened runtime weakening",
    "com.apple.security.cs.allow-jit": "hardened runtime weakening",
    "com.apple.security.get-task-allow": "debug entitlement",
}


def text_files():
    for folder in ("Sources", "Sources/CornettaCore"):
        path = ROOT / folder
        if not path.exists():
            continue
        for file in path.rglob("*"):
            if file.suffix in (".swift", ".plist", ".entitlements"):
                yield file


class MacSecurityGuardTests(unittest.TestCase):
    def read(self, path: str) -> str:
        return (ROOT / path).read_text(encoding="utf-8")

    def check(self, path: str, present: tuple[str, ...] = (), absent: tuple[str, ...] = ()) -> None:
        text = self.read(path)
        for needle in present:
            self.assertIn(needle, text)
        for needle in absent:
            self.assertNotIn(needle, text)

    def test_no_privileged_or_system_level_code(self):
        problems = []
        for file in text_files():
            text = file.read_text(encoding="utf-8", errors="replace")
            for needle, reason in FORBIDDEN.items():
                if needle in text:
                    problems.append(f"{file.relative_to(ROOT)}: {needle} ({reason})")
        self.assertEqual(problems, [], "\n".join(problems))

    def test_login_item_is_only_the_main_app(self):
        text = (ROOT / "Sources/Cornetta/Welcome.swift").read_text(encoding="utf-8")
        if "SMAppService" in text:
            self.assertIn(SAFE_SERVICE_MANAGEMENT, text)
            self.assertNotIn("SMAppService.daemon", text)
            self.assertNotIn("SMAppService.agent", text)
            self.assertIn("unregister()", text)

    def test_audio_aggregate_is_private_and_destroyed(self):
        text = (ROOT / "Sources/CornettaCore/AggregateDevice.swift").read_text(encoding="utf-8")
        self.assertIn("kAudioAggregateDeviceIsPrivateKey: true", text)
        self.assertIn("kAudioAggregateDeviceTapAutoStartKey: false", text)
        self.assertIn("AudioHardwareDestroyAggregateDevice", text)
        recorder = (ROOT / "Sources/CornettaCore/CallRecorder.swift").read_text(encoding="utf-8")
        self.assertIn("aggregate?.destroy()", recorder)
        self.assertIn("tap?.destroy()", recorder)

    def test_no_system_wide_installer_or_receipts(self):
        self.check("Sources/CornettaCore/AppInstaller.swift", present=("replaceItemAt",),
                   absent=("/System", "/Library"))

    def test_entitlements_are_audio_only(self):
        text = self.read("Resources/Cornetta.entitlements")
        keys = set(re.findall(r"<key>([^<]+)</key>", text))
        self.assertEqual({"com.apple.security.device.audio-input"}, keys)

    def test_transcription_network_is_local_by_default(self):
        self.check("Resources/Info.plist", present=("<key>NSAllowsLocalNetworking</key>",),
                   absent=("NSAllowsArbitraryLoads",))
        self.check("Sources/CornettaCore/TranscriptionConfig.swift",
                   present=('defaultBaseURL = "http://127.0.0.1:8080/v1"',))

    def test_transcription_key_is_keychain_only(self):
        self.check("Sources/CornettaCore/TranscriptionCredential.swift",
                   present=("kSecClassGenericPassword", "kSecAttrService", "Bearer"))
        self.check("Sources/CornettaCore/TranscriptionConfig.swift",
                   absent=("apiKeyKey", "transcriptionApiKey"))


if __name__ == "__main__":
    unittest.main()
