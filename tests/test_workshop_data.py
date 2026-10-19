"""Checks for server/workshop_data.py (port of tests/loader.tests.ps1).

Uses the real workspace for count checks and a temporary fixture for exclusions, hostile links and warnings.
Run from the app folder: python -m unittest discover -s tests -v
"""

from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
import unittest

APP_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(APP_DIR, "server"))

import workshop_data as wd  # noqa: E402

INFRA_ROOT = os.environ.get("WORKSHOP_INFRA") or os.path.normpath(os.path.join(APP_DIR, "..", "..", "infra"))


def write(path: str, text: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(text + "\n")


def by_text(text: str) -> wd.Resource:
    return wd.Resource(section="Agentes", type_label="Agente", name="x", title="x", description="", status="",
                       area="", path="", relative_path="", usage="", usage_hint="", modified=None, search_text=text)


class ParsingTests(unittest.TestCase):
    def test_agent_catalogue_row_parses(self) -> None:
        table = ("| Area | Agent | Use it to | Access |\n|---|---|---|---|\n"
                 "| UI | [ui-designer](../../agents/ui/ui-designer.md) | Visual `design` | Edit |")
        rows = wd.parse_catalogue_table(table, "Agentes")
        self.assertEqual(len(rows), 1)
        self.assertEqual((rows[0].name, rows[0].area, rows[0].use), ("ui-designer", "UI", "Visual design"))

    def test_empty_catalogue_returns_empty_list(self) -> None:
        self.assertEqual(wd.parse_catalogue_table("no table here", "Agentes"), [])

    def test_task_catalogue_row_parses(self) -> None:
        table = "| Task | Status | Purpose |\n|---|---|---|\n| [a-task](../../tasks/a-task.md) | active (rev. 2) | Do [it](x.md) |"
        rows = wd.parse_catalogue_table(table, "Tareas")
        self.assertEqual(len(rows), 1)
        self.assertEqual((rows[0].status, rows[0].use), ("active (rev. 2)", "Do it"))

    def test_front_matter_description_parses(self) -> None:
        self.assertEqual(wd.get_field('---\nname: x\ndescription: "Hello there"\n---', "description"), "Hello there")

    def test_fields_outside_front_matter_ignored(self) -> None:
        self.assertEqual(wd.get_field("# Doc\n\ndescription: not front matter", "description"), "")

    def test_folded_yaml_marker_not_shown(self) -> None:
        self.assertEqual(wd.get_field("---\ndescription: >\n  folded\n---", "description"), "")

    def test_title_ignores_code_fences(self) -> None:
        self.assertEqual(wd.get_title("```text\n# not a title\n```\n# Real title", "x"), "Real title")

    def test_document_summary_skips_lists_and_metadata(self) -> None:
        text = "# Title\n\nStatus: x\n\n- list\n\nFirst real\nparagraph.\n"
        self.assertEqual(wd.get_document_summary(text), "First real paragraph.")

    def test_diacritics_removed(self) -> None:
        self.assertEqual(wd.remove_diacritics("Diseño ÁGIL"), "diseno agil")

    def test_web_links_rejected(self) -> None:
        self.assertEqual(wd.resolve_link(r"C:\w\infra\docs\catalogues", "http://example.com/a.md"), "")

    def test_absolute_links_rejected(self) -> None:
        self.assertEqual(wd.resolve_link(r"C:\w\infra\docs\catalogues", r"C:\Windows\win.ini"), "")

    def test_encoded_relative_link_resolves(self) -> None:
        self.assertEqual(wd.resolve_link(r"C:\w\infra\docs\catalogues", "../../agents/a%20b.md#x"),
                         r"C:\w\infra\agents\a b.md")

    def test_non_markdown_links_rejected(self) -> None:
        self.assertEqual(wd.resolve_link(r"C:\w\infra\docs\catalogues", "../../scripts/run.ps1"), "")
        self.assertEqual(wd.resolve_link(r"C:\w\infra\docs\catalogues", "../../agents"), "")

    def test_waiting_status_label(self) -> None:
        self.assertEqual(wd.get_status_label("active (rev. 2, 2026-10-18); starts only after X"),
                         "Activa, en espera (rev. 2, 2026-10-18)")

    def test_completed_status_label(self) -> None:
        self.assertEqual(wd.get_status_label("completed (2026-10-17)"), "Completada (2026-10-17)")


class ExclusionTests(unittest.TestCase):
    EXCLUDED = [
        r"C:\w\infra\vendor\x.md", r"C:\w\infra\clients\.codex\agents\a.md",
        r"C:\w\infra\clients\.agents\skills\s\README.md", r"C:\w\app\node_modules\p\README.md",
        r"C:\w\app\.venv\l.md", r"C:\w\app\.env", r"C:\w\app\.env.local", r"C:\w\x\auth.json",
        r"C:\w\x\settings.local.json", r"C:\w\x\.credentials.json", r"C:\w\x\id.key", r"C:\w\x\api-token.txt",
        r"C:\w\x\client_secret.json",
    ]

    def test_excluded_paths(self) -> None:
        for path in self.EXCLUDED:
            with self.subTest(path=path):
                self.assertTrue(wd.is_excluded_path(path))

    def test_normal_doc_not_excluded(self) -> None:
        self.assertFalse(wd.is_excluded_path(r"C:\w\infra\docs\onboarding.md"))

    def test_markdown_doc_with_token_in_name_not_excluded(self) -> None:
        self.assertFalse(wd.is_excluded_path(r"C:\w\infra\docs\token-optimization-candidate-review.md"))


class SearchTests(unittest.TestCase):
    def test_short_word_matches_whole_word(self) -> None:
        self.assertTrue(wd.resource_matches(by_text("build a windows-friendly ui-designer"), "ui"))

    def test_short_word_does_not_match_inside_word(self) -> None:
        self.assertFalse(wd.resource_matches(by_text("build things"), "ui"))

    def test_match_accepts_payload_dicts_and_accents(self) -> None:
        self.assertTrue(wd.resource_matches({"searchText": "ui-designer visual design"}, "Diseño"))

    def test_empty_query_matches(self) -> None:
        self.assertTrue(wd.resource_matches(by_text("anything"), "   "))


class RealWorkspaceTests(unittest.TestCase):
    data: wd.WorkshopData
    elapsed: float

    @classmethod
    def setUpClass(cls) -> None:
        if not os.path.isdir(INFRA_ROOT):
            raise unittest.SkipTest(f"infra folder not found: {INFRA_ROOT}")
        started = time.perf_counter()
        cls.data = wd.get_workshop_data(INFRA_ROOT)
        cls.elapsed = time.perf_counter() - started

    def items(self, section: str) -> list[wd.Resource]:
        return [i for i in self.data.items if i.section == section]

    def test_loads_in_under_two_seconds(self) -> None:
        self.assertLess(self.elapsed, 2.0, f"took {self.elapsed:.3f} s")

    def test_counts_match_catalogues(self) -> None:
        def row_count(file: str, pattern: str) -> int:
            text = wd.read_text_file(os.path.join(INFRA_ROOT, "docs", "catalogues", file))
            return sum(1 for line in re.split(r"\r?\n", text) if re.search(pattern, line))

        expected = {
            "Agentes": row_count("agents.md", r"^\|\s*[^|\[]+\|\s*\[[^\]]+\]\("),
            "Skills": row_count("skills.md", r"^\|\s*[^|\[]+\|\s*\[[^\]]+\]\("),
            "Tareas": row_count("tasks.md", r"^\|\s*\[[^\]]+\]\("),
        }
        for section, count in expected.items():
            with self.subTest(section=section):
                actual = sum(1 for i in self.items(section) if i.area != wd.NOT_CATALOGUED_AREA)
                self.assertEqual(actual, count)

    def test_every_section_has_items(self) -> None:
        for section in wd.SECTIONS:
            with self.subTest(section=section):
                self.assertGreater(len(self.items(section)), 0)

    def test_no_excluded_path_listed(self) -> None:
        self.assertEqual([i.path for i in self.data.items if wd.is_excluded_path(i.path)], [])

    def test_generated_adapter_files_not_listed(self) -> None:
        self.assertEqual([i.path for i in self.data.items if re.search(r"\\clients\\\.", i.path)], [])

    def test_every_path_inside_workspace(self) -> None:
        root = self.data.workshop_root
        self.assertEqual([i.path for i in self.data.items if not wd.is_inside_root(i.path, root)], [])

    def test_every_path_exists(self) -> None:
        self.assertEqual([i.path for i in self.data.items if i.path and not os.path.exists(i.path)], [])

    def test_skill_usage(self) -> None:
        for skill in self.items("Skills"):
            with self.subTest(skill=skill.name):
                self.assertEqual(skill.usage, "/workshop:" + skill.name)
                self.assertIn("$" + skill.name + ".", skill.usage_hint)
                self.assertNotIn("$workshop:", skill.usage_hint)

    def test_task_usage_title_and_related(self) -> None:
        for task in self.items("Tareas"):
            with self.subTest(task=task.name):
                if wd.is_active_task(task):
                    self.assertRegex(task.usage, r"^Ejecuta la tarea en infra\\tasks\\.*\.md$")
                else:
                    self.assertEqual(task.usage, "")
                    self.assertTrue(task.usage_hint.startswith("No ejecutar:"))
                self.assertNotRegex(task.title, r"(?i)^TASK PROMPT")
                related = wd.get_related_resources(task, self.data.items)
                self.assertIsInstance(related, list)
                self.assertNotIn(None, related)

    def test_agent_usage(self) -> None:
        for agent in self.items("Agentes"):
            with self.subTest(agent=agent.name):
                self.assertEqual(agent.usage, f"Usa el agente workshop:{agent.name} para ")

    def test_assistant_usage(self) -> None:
        for assistant in self.items("Asistentes"):
            with self.subTest(assistant=assistant.name):
                self.assertEqual(assistant.usage, f"claude --agent workshop:{assistant.name}")

    def test_spanish_search_finds_security_reviewer(self) -> None:
        reviewer = next((i for i in self.data.items if i.name == "security-reviewer"), None)
        self.assertIsNotNone(reviewer)
        self.assertTrue(wd.resource_matches(reviewer, "seguridad"))

    def test_all_search_words_must_match(self) -> None:
        reviewer = next((i for i in self.data.items if i.name == "security-reviewer"), None)
        self.assertIsNotNone(reviewer)
        self.assertFalse(wd.resource_matches(reviewer, "seguridad música"))

    def test_application_usage_shows_launch_command_as_text(self) -> None:
        app = next((i for i in self.items("Aplicaciones") if i.name == "workshop-infrastructure-ui"), None)
        self.assertIsNotNone(app)
        self.assertRegex(app.usage, r"INICIAR\.cmd")
        self.assertRegex(app.usage_hint, "no inicia")

    def test_snapshot_shape(self) -> None:
        snapshot = wd.build_snapshot(INFRA_ROOT)
        payload = snapshot.payload
        ids = [i["id"] for i in payload["items"]]
        self.assertEqual(len(ids), len(set(ids)), "ids are unique")
        self.assertEqual(ids, [i["id"] for i in wd.build_snapshot(INFRA_ROOT).payload["items"]], "ids are stable")
        self.assertEqual(payload["sections"], wd.SECTIONS)
        reviewer = snapshot.payload["items"][ids.index("agentes:security-reviewer")]
        self.assertEqual(reviewer["typeLabel"], "Agente")
        self.assertTrue(reviewer["canOpenDocument"] and reviewer["canOpenFolder"])
        self.assertRegex(reviewer["modified"], r"^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$")
        for item in payload["items"]:
            with self.subTest(item=item["id"]):
                if item["section"] == "Tareas":
                    self.assertIn(item["taskState"], ("active", "waiting", "completed", "retired", "superseded", "other"))
                    self.assertIn(item["statusShort"], ("Activa", "En espera", "Completada", "Retirada", "Sustituida", ""))
                    self.assertTrue(all(isinstance(n, str) for n in item["related"]))
                else:
                    self.assertEqual((item["taskState"], item["related"]), ("", []))


class FixtureTests(unittest.TestCase):
    """Catalogue/disk mismatch, hostile links, secrets and junctions in a temporary workspace."""

    def setUp(self) -> None:
        self.fixture = tempfile.mkdtemp(prefix="workshop-ui-test-")
        self.addCleanup(self._cleanup)
        self.infra = os.path.join(self.fixture, "infra")
        for folder in ("tasks", r"agents\ui", r"skills\demo-skill", r"docs\catalogues", r"clients\demo-client",
                       r"clients\.codex", r"agents\personal-assistants"):
            os.makedirs(os.path.join(self.infra, folder), exist_ok=True)
        write(os.path.join(self.fixture, "outside.md"), "# Outside the infra folder")
        write(os.path.join(self.infra, r"docs\catalogues\agents.md"), "\n".join([
            "| Area | Agent | Use | Access |", "|---|---|---|---|",
            "| UI | [listed](../../agents/ui/listed.md) | Listed agent | RO |",
            "| UI | [missing](../../agents/ui/missing.md) | Missing agent | RO |",
            "| UI | [web](http://example.com/a.md) | Web link | RO |",
            r"| UI | [drive](C:\Windows\win.ini) | Absolute link | RO |",
            "| UI | [outside](../../../../outside.md) | Outside link | RO |",
            "| UI | [script](../../agents/ui/run.ps1) | Script link | RO |",
        ]))
        write(os.path.join(self.infra, r"agents\ui\listed.md"), "---\nname: listed\n---")
        write(os.path.join(self.infra, r"agents\ui\extra.md"), "---\nname: extra\ndescription: Extra\n---")
        write(os.path.join(self.infra, r"skills\demo-skill\SKILL.md"), "---\nname: demo-skill\ndescription: Demo\n---")
        write(os.path.join(self.infra, r"clients\demo-client\README.md"), "# Demo client\n\nGuide text.")
        write(os.path.join(self.infra, r"clients\.codex\README.md"), "# Generated")
        write(os.path.join(self.infra, r"clients\demo-client\.env"), "SECRET=not-read")

    def _cleanup(self) -> None:
        # Remove junctions first so rmtree never walks into their targets.
        junction = os.path.join(self.infra, "docs", "linked")
        if os.path.lexists(junction):
            os.rmdir(junction)
        shutil.rmtree(self.fixture, ignore_errors=True)

    def test_catalogue_mismatch_and_hostile_links(self) -> None:
        data = wd.get_workshop_data(self.infra)
        warnings = "\n".join(data.warnings)
        self.assertIn("cita 'missing', pero su archivo no existe", warnings)
        self.assertIn("'extra' existe en disco", warnings)
        for name in ("web", "drive", "outside", "script"):
            with self.subTest(link=name):
                self.assertIn(f"cita '{name}' con un enlace no válido", warnings)
        self.assertEqual(sum(1 for i in data.items if i.section == "Agentes"), 2)
        self.assertIn("skills.md", warnings)
        self.assertEqual(sum(1 for i in data.items if i.name == "demo-skill"), 1)
        self.assertEqual(sum(1 for i in data.items if i.section == "Clientes IA"), 1)
        self.assertEqual([i.path for i in data.items if re.search(r"\.env$|\\\.codex\\", i.path)], [])

    def test_files_behind_a_junction_not_listed(self) -> None:
        target = os.path.join(self.fixture, "linked-target")
        write(os.path.join(target, "leak.md"), "# Leak")
        junction = os.path.join(self.infra, "docs", "linked")
        result = subprocess.run(["cmd", "/c", "mklink", "/J", junction, target], capture_output=True)
        if result.returncode != 0 or not os.path.isdir(junction):
            self.skipTest("NOT CHECKED: junction test (could not create a junction here)")
        self.assertTrue(wd.is_linked_path(os.path.join(junction, "leak.md"), self.fixture))
        data = wd.get_workshop_data(self.infra)
        self.assertEqual([i.path for i in data.items if i.path.lower().endswith("leak.md")], [])


if __name__ == "__main__":
    unittest.main()
