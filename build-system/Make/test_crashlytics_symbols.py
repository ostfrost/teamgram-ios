import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import UploadCrashlyticsSymbols as symbols


class CrashlyticsSymbolsTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.plist = self.root / "GoogleService-Info.plist"
        with self.plist.open("wb") as stream:
            plistlib.dump({"BUNDLE_ID": "com.avatarmessenger.app", "GOOGLE_APP_ID": "test-app"}, stream)
        self.dsym = self.root / "App with spaces.app.dSYM"
        self.add_dwarf_file(self.dsym)
        self.args = symbols.parser().parse_args([
            "--dsym-path", str(self.dsym), "--google-service-plist", str(self.plist),
            "--cache-dir", str(self.root / "cache"),
        ])
        self.env = patch.dict(os.environ, {"ACTION": "build", "AVATAR_CRASHLYTICS_UPLOAD": "1"})
        self.env.start()
        self.addCleanup(self.env.stop)

    def add_dwarf_file(self, dsym):
        dwarf = dsym / "Contents/Resources/DWARF" / dsym.name.removesuffix(".dSYM")
        dwarf.parent.mkdir(parents=True)
        dwarf.write_bytes(b"symbols")

    def test_discovers_only_top_level_telegram_dsyms_and_resolves_symlinks(self):
        bazel_out = self.root / "bazel-out"
        app = bazel_out / "ios_sim_arm64-dbg/bin/Telegram/Telegram.app.dSYM"
        self.add_dwarf_file(app)
        unrelated = bazel_out / "ios_sim_arm64-dbg/bin/Other/Other.dSYM"
        self.add_dwarf_file(unrelated)
        alias = self.root / "alias.dSYM"
        alias.symlink_to(app)
        self.assertEqual(symbols.find_symbols([alias], bazel_out), [app.resolve()])

    def test_discovers_nested_rules_apple_app_symbols(self):
        bazel_out = self.root / "bazel-out"
        directory = bazel_out / "ios_sim_arm64-dbg/bin/Telegram"
        app = directory / "Telegram_dsyms/Avatar Messenger App.app.dSYM"
        self.add_dwarf_file(app)
        framework = directory / "TelegramUIFramework.framework.dSYM"
        self.add_dwarf_file(framework)
        expected = sorted([app.resolve(), framework.resolve()])
        self.assertEqual(symbols.find_symbols([], bazel_out), expected)
        self.assertEqual(symbols.find_symbols([directory]), expected)

    def test_ignores_dsym_bundles_without_dwarf_files(self):
        directory = self.root / "bazel-out/ios_sim_arm64-dbg/bin/Telegram"
        valid = directory / "Telegram_dsyms/Avatar Messenger App.app.dSYM"
        self.add_dwarf_file(valid)
        empty = directory / "TelegramCoreFramework.framework.dSYM"
        (empty / "Contents").mkdir(parents=True)
        (empty / "Contents/Info.plist").write_bytes(b"plist")

        self.assertEqual(symbols.find_symbols([directory]), [valid.resolve()])

    @patch.object(symbols, "symbol_key", return_value="uuid-test")
    @patch.object(symbols.subprocess, "run")
    def test_success_cached_and_not_uploaded_twice(self, run, key):
        symbols.upload(self.args)
        symbols.upload(self.args)
        run.assert_called_once()
        command = run.call_args.args[0]
        self.assertIn(str(self.dsym.resolve()), command)
        self.assertIn(str(self.plist.resolve()), command)
        self.assertEqual(run.call_args.kwargs["cwd"], symbols.REPOSITORY)
        self.assertTrue(run.call_args.kwargs["check"])
        self.assertEqual(len(list((self.root / "cache").glob("*/uuid-test"))), 1)

    @patch.object(symbols, "symbol_key", return_value="uuid-test")
    @patch.object(symbols.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "upload-symbols"))
    def test_failed_upload_is_not_cached(self, run, key):
        with self.assertRaises(subprocess.CalledProcessError):
            symbols.upload(self.args)
        self.assertFalse((self.root / "cache").exists())

    @patch.object(symbols, "symbol_key", return_value="uuid-test")
    @patch.object(symbols.subprocess, "run")
    def test_force_reuploads_and_cache_is_per_firebase_app(self, run, key):
        symbols.upload(self.args)
        self.args.force = True
        symbols.upload(self.args)
        self.args.force = False
        with self.plist.open("wb") as stream:
            plistlib.dump({"BUNDLE_ID": "com.avatarmessenger.app", "GOOGLE_APP_ID": "another-app"}, stream)
        symbols.upload(self.args)
        self.assertEqual(run.call_count, 3)

    def test_empty_symbols_fail_unless_explicitly_allowed(self):
        self.args.dsym_path = []
        with self.assertRaisesRegex(ValueError, "No app dSYMs"):
            symbols.upload(self.args)
        self.args.allow_empty = True
        symbols.upload(self.args)

    @patch.object(symbols.subprocess, "run")
    def test_index_and_offline_modes_never_upload(self, run):
        with patch.dict(os.environ, {"ACTION": "indexbuild"}):
            symbols.upload(self.args)
        with patch.dict(os.environ, {"AVATAR_CRASHLYTICS_UPLOAD": "0"}):
            symbols.upload(self.args)
        run.assert_not_called()

    def test_wrong_bundle_rejected(self):
        with self.plist.open("wb") as stream:
            plistlib.dump({"BUNDLE_ID": "com.avatarmessanger.app", "GOOGLE_APP_ID": "old-app"}, stream)
        with self.assertRaisesRegex(ValueError, "com.avatarmessenger.app"):
            symbols.upload(self.args)

    def test_zip_must_contain_dwarf(self):
        archive_path = self.root / "symbols.zip"
        with zipfile.ZipFile(archive_path, "w") as archive:
            archive.writestr("DSYMs/", "")
        with self.assertRaisesRegex(ValueError, "no dSYM"):
            symbols.symbol_key(archive_path)
        with zipfile.ZipFile(archive_path, "w") as archive:
            archive.writestr("DSYMs/App.dSYM/Contents/Resources/DWARF/App", "symbols")
        self.assertTrue(symbols.symbol_key(archive_path).startswith("zip-"))

    @patch.object(symbols.subprocess, "run")
    def test_uuid_validation(self, run):
        run.return_value.stdout = "UUID: A82CCF5A-B80A-316D-9908-5D1A946F0277 (arm64) App\n"
        self.assertEqual(symbols.symbol_key(self.dsym), "a82ccf5a-b80a-316d-9908-5d1a946f0277")
        run.return_value.stdout = ""
        with self.assertRaisesRegex(ValueError, "No UUIDs"):
            symbols.symbol_key(self.dsym)


if __name__ == "__main__":
    unittest.main()
