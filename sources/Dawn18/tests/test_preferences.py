#!/usr/bin/env python3
"""Source-contract checks only; does not execute UIKit or CFPreferences."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PreferenceContractTests(unittest.TestCase):
    def test_existing_keys_and_appended_hud_key(self):
        source = (ROOT / "Preferences.m").read_text()
        array = re.search(r"D18Keys = @\[(.*?)\];", source, re.S).group(1)
        self.assertEqual(re.findall(r'@"([^"]+)"', array), [
            "Applications", "Folders", "Notifications", "NotificationButtons",
            "Widgets", "Dock", "Banners", "AppLibrary", "QuickActions",
            "RingerVolume",
        ])

    def test_one_settings_control_per_preference(self):
        source = (ROOT / "Settings.m").read_text()
        array = re.search(r"_options = @\[(.*?)\n    \];", source, re.S).group(1)
        elements = re.findall(r'@"element": @\((D18\w+)\)', array)
        self.assertCountEqual(elements, [
            "D18Applications", "D18Folders", "D18Notifications", "D18Buttons",
            "D18Widgets", "D18Dock", "D18Banners", "D18AppLibrary",
            "D18QuickActions", "D18RingerVolume",
        ])
        self.assertIn('@"title": @"Ringer"', array)
        self.assertNotIn('Ringer & Volume', source)

    def test_read_write_and_reset_include_new_choice(self):
        preferences = (ROOT / "Preferences.m").read_text()
        settings = (ROOT / "Settings.m").read_text()
        self.assertEqual(preferences.count(
            "for (NSUInteger i = 0; i < D18ElementCount; i++)"), 2)
        self.assertIn("D18Configuration result = {{0}};", preferences)
        self.assertIn("D18Configuration defaults = {{0}};", settings)
        self.assertIn("[self saveConfiguration:defaults];", settings)


if __name__ == "__main__":
    unittest.main()
