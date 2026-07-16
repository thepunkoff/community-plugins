from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path


VALIDATOR_PATH = Path(__file__).with_name("validate-plugins.py")
SPEC = importlib.util.spec_from_file_location("validate_plugins", VALIDATOR_PATH)
assert SPEC is not None and SPEC.loader is not None
validate_plugins = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(validate_plugins)


class LauncherPrefixTests(unittest.TestCase):
    def validate_prefix(self, prefix: str) -> list[str]:
        validator = validate_plugins.Validator(Path("/repo"))
        validator.validate_launcher_fields(
            Path("/repo/example/plugin.toml"),
            "launcher_provider[0]",
            {"prefix": prefix},
        )
        return validator.errors

    def test_accepts_lowercase_ascii_letters(self) -> None:
        self.assertEqual(self.validate_prefix("bla"), [])

    def test_rejects_leading_symbol(self) -> None:
        self.assertNotEqual(self.validate_prefix("/bla"), [])

    def test_rejects_uppercase_letters(self) -> None:
        self.assertNotEqual(self.validate_prefix("Bla"), [])

    def test_rejects_digits(self) -> None:
        self.assertNotEqual(self.validate_prefix("bla2"), [])

    def test_rejects_other_symbols(self) -> None:
        self.assertNotEqual(self.validate_prefix("bla-bla"), [])


class AllowedTagsTests(unittest.TestCase):
    def validate_tags(self, tags: object) -> list[str]:
        validator = validate_plugins.Validator(Path("/repo"))
        validator.validate_tags(Path("/repo/example/plugin.toml"), tags)
        return validator.errors

    def test_accepts_every_allowed_tag(self) -> None:
        self.assertEqual(self.validate_tags(sorted(validate_plugins.ALLOWED_TAGS)), [])

    def test_rejects_unknown_tag(self) -> None:
        self.assertEqual(
            self.validate_tags(["utility", "unknown"]),
            [
                "example/plugin.toml: root: "
                "tags[1] 'unknown' is not an allowed tag"
            ],
        )

    def test_rejects_wrong_case(self) -> None:
        self.assertNotEqual(self.validate_tags(["Utility"]), [])

    def test_retains_string_list_validation(self) -> None:
        errors = self.validate_tags(["utility", "utility", ""])
        self.assertTrue(any("duplicate 'utility'" in error for error in errors))
        self.assertTrue(any("tags[2] must be a non-empty string" in error for error in errors))


class PluginConfigAccessorTests(unittest.TestCase):
    def test_accepts_universal_accessor(self) -> None:
        self.assertEqual(
            validate_plugins.obsolete_config_accessors('local value = noctalia.getConfig("key")'),
            [],
        )

    def test_rejects_every_entry_specific_alias(self) -> None:
        source = "\n".join(
            [
                'barWidget.getConfig("one")',
                'desktopWidget.getConfig("two")',
                'panel . getConfig("three")',
                'launcher.getConfig("four")',
            ]
        )
        self.assertEqual(
            validate_plugins.obsolete_config_accessors(source),
            [
                ("barWidget.getConfig", 1),
                ("desktopWidget.getConfig", 2),
                ("panel.getConfig", 3),
                ("launcher.getConfig", 4),
            ],
        )

    def test_ignores_comments_and_strings(self) -> None:
        source = "\n".join(
            [
                '-- barWidget.getConfig("comment")',
                '--[[ panel.getConfig("block comment") ]]',
                'local text = "launcher.getConfig(\\\"string\\\")"',
                'local block = [[desktopWidget.getConfig("long string")]]',
            ]
        )
        self.assertEqual(validate_plugins.obsolete_config_accessors(source), [])


class ReadmeTests(unittest.TestCase):
    MANIFEST = {
        "id": "me/example",
        "dependencies": ["example-cli"],
        "setting": [{"key": "interval"}],
        "widget": [{"id": "widget", "entry": "widget.luau"}],
        "panel": [{"id": "panel", "entry": "panel.luau"}],
        "launcher_provider": [
            {"id": "search", "entry": "launcher.luau", "prefix": "ex"}
        ],
    }

    VALID_README = """# Example

Example provides a useful widget, panel, and launcher for demonstration purposes.

## Plugin

| Field | Value |
| --- | --- |
| ID | `me/example` |
| Entries | Widget: `widget`; panel: `panel`; launcher: `search` |
| Launcher Prefix | `/ex` |

## Requirements

Install `example-cli` on `PATH`.

## Usage

Add the widget, type `/ex`, or open the panel:

```sh
noctalia msg panel-toggle me/example:panel
```

## Settings

Configure the update interval in plugin settings.
"""

    def validate_readme(self, contents: str) -> list[str]:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            plugin_dir = root / "example"
            plugin_dir.mkdir()
            (plugin_dir / "README.md").write_text(contents, encoding="utf-8")
            validator = validate_plugins.Validator(root)
            validator.validate_readme(plugin_dir, self.MANIFEST)
            return validator.errors

    def test_accepts_official_plugin_readme_structure(self) -> None:
        self.assertEqual(self.validate_readme(self.VALID_README), [])

    def test_requires_core_sections_and_intro(self) -> None:
        errors = self.validate_readme("# Example\n\nToo short.\n")
        self.assertTrue(any("short introduction" in error for error in errors))
        self.assertTrue(any("## Plugin" in error for error in errors))
        self.assertTrue(any("## Usage" in error for error in errors))

    def test_headings_inside_code_fences_do_not_satisfy_sections(self) -> None:
        errors = self.validate_readme(
            "# Example\n\nA sufficiently descriptive introduction for this example plugin.\n\n"
            "```md\n## Plugin\n## Usage\n```\n"
        )
        self.assertTrue(any("## Plugin" in error for error in errors))
        self.assertTrue(any("## Usage" in error for error in errors))

    def test_derives_documented_values_from_manifest(self) -> None:
        readme = self.VALID_README
        replacements = {
            "`me/example`": "`me/wrong`",
            "`widget`": "`other-widget`",
            "noctalia msg panel-toggle me/example:panel": "noctalia msg panel-toggle me/example:wrong",
            "`/ex`": "`/wrong`",
            "`example-cli`": "`other-cli`",
        }
        for old, new in replacements.items():
            with self.subTest(missing=old):
                errors = self.validate_readme(readme.replace(old, new))
                self.assertTrue(errors)

    def test_requires_conditional_sections(self) -> None:
        without_requirements = self.VALID_README.replace(
            "## Requirements\n\nInstall `example-cli` on `PATH`.\n\n", ""
        )
        without_settings = self.VALID_README.replace(
            "## Settings\n\nConfigure the update interval in plugin settings.\n", ""
        )
        self.assertTrue(
            any("## Requirements" in error for error in self.validate_readme(without_requirements))
        )
        self.assertTrue(any("## Settings" in error for error in self.validate_readme(without_settings)))


if __name__ == "__main__":
    unittest.main()
