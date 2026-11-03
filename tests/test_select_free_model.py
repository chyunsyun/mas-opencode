#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
SELECTOR = ROOT / "scripts" / "select_free_model.py"
ALL_ROLES = (
    "director",
    "chief",
    "auditor",
    "engineer1",
    "engineer2",
    "engineer3",
)


def model_block(
    provider,
    model_id,
    *,
    cost=0,
    context=200_000,
    toolcall=True,
    status="active",
    release="2026-10-01",
):
    payload = {
        "id": model_id,
        "providerID": provider,
        "name": model_id,
        "status": status,
        "cost": {
            "input": cost,
            "output": cost,
            "cache": {"read": cost, "write": cost},
        },
        "limit": {"context": context, "output": 32_000},
        "capabilities": {"toolcall": toolcall, "reasoning": True},
        "release_date": release,
    }
    return f"{provider}/{model_id}\n{json.dumps(payload, indent=2)}\n"


def write_settings(path, models=None):
    models = models or {}
    agents = {}
    for role in ALL_ROLES:
        config = {"type": "opencode", "model": models.get(role, "")}
        if role == "engineer3":
            config["max_bloom"] = 3
        agents[role] = config
    data = {
        "language": "ja",
        "shell": "bash",
        "cli": {"default": "opencode", "agents": agents},
        "capability_tiers": {},
        "bloom_routing": {"enabled": True},
    }
    path.write_text(
        yaml.safe_dump(data, allow_unicode=True, sort_keys=False),
        encoding="utf-8",
    )


def load_settings(path):
    with path.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle) or {}


class SelectFreeModelTest(unittest.TestCase):
    def setUp(self):
        self.tempdir = tempfile.TemporaryDirectory()
        self.root = Path(self.tempdir.name)
        self.settings = self.root / "settings.yaml"
        self.models = self.root / "models.txt"

    def tearDown(self):
        self.tempdir.cleanup()

    def run_selector(
        self,
        *,
        force=False,
        free_model="",
        dry_run=False,
        allow_running=False,
        env=None,
    ):
        command = [
            sys.executable,
            str(SELECTOR),
            "--settings",
            str(self.settings),
            "--models-file",
            str(self.models),
            "--json",
        ]
        if force:
            command.append("--force")
        if free_model:
            command.extend(["--free-model", free_model])
        if dry_run:
            command.append("--dry-run")
        if allow_running:
            command.append("--allow-running")
        return subprocess.run(
            command,
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
            env=env,
        )

    def make_fake_running_bin(self):
        bindir = self.root / "running-bin"
        bindir.mkdir(exist_ok=True)
        pgrep = bindir / "pgrep"
        pgrep.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
        pgrep.chmod(0o755)
        return bindir

    def running_env(self, bindir):
        env = os.environ.copy()
        env["PATH"] = f"{bindir}{os.pathsep}{env.get('PATH', '')}"
        env["MAS_SESSION"] = "mas"
        return env

    def write_catalog(self, blocks):
        self.models.write_text("\n".join(blocks), encoding="utf-8")

    def test_selects_high_and_fast_free_models(self):
        write_settings(self.settings)
        self.write_catalog([
            model_block("opencode", "nemotron-3-ultra-free", context=1_000_000),
            model_block(
                "opencode",
                "deepseek-v4.1-flash-free",
                context=200_000,
                release="2026-10-03",
            ),
            model_block("opencode", "glm-5.3-flash-free", context=200_000),
            model_block("opencode", "paid-model", cost=1),
            model_block("lmstudio", "local-model"),
            model_block("opencode", "inactive-free", status="inactive"),
            model_block("opencode", "no-tools-free", toolcall=False),
            model_block("opencode-go", "beam-free", context=1_000_000),
        ])

        result = self.run_selector()
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)

        self.assertTrue(payload["selected"])
        self.assertEqual(payload["high_model"], "opencode/nemotron-3-ultra-free")
        self.assertEqual(payload["fast_model"], "opencode/deepseek-v4.1-flash-free")

        data = load_settings(self.settings)
        agents = data["cli"]["agents"]
        self.assertEqual(agents["director"]["model"], "opencode/nemotron-3-ultra-free")
        self.assertEqual(agents["chief"]["model"], "opencode/nemotron-3-ultra-free")
        self.assertEqual(agents["engineer2"]["model"], "opencode/nemotron-3-ultra-free")
        self.assertEqual(agents["engineer3"]["model"], "opencode/deepseek-v4.1-flash-free")
        self.assertEqual(agents["engineer3"]["max_bloom"], 3)

        tiers = data["capability_tiers"]
        self.assertEqual(tiers["opencode/nemotron-3-ultra-free"]["max_bloom"], 4)
        self.assertEqual(tiers["opencode/deepseek-v4.1-flash-free"]["max_bloom"], 3)
        self.assertNotIn("opencode/paid-model", tiers)
        self.assertNotIn("lmstudio/local-model", tiers)
        self.assertEqual(payload["candidates"], sorted([
            "opencode/nemotron-3-ultra-free",
            "opencode/deepseek-v4.1-flash-free",
            "opencode/glm-5.3-flash-free",
            "opencode-go/beam-free",
        ]))

    def test_preserves_existing_model_without_force(self):
        write_settings(self.settings, {"director": "custom/model"})
        self.write_catalog([
            model_block("opencode", "nemotron-3-ultra-free"),
        ])

        result = self.run_selector()
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertTrue(payload["skipped"])

        data = load_settings(self.settings)
        self.assertEqual(data["cli"]["agents"]["director"]["model"], "custom/model")
        self.assertNotIn("model_selection", data)

    def test_force_overwrites_existing_models(self):
        write_settings(self.settings, {"director": "custom/model"})
        self.write_catalog([
            model_block("opencode", "nemotron-3-ultra-free"),
            model_block("opencode", "deepseek-v4.1-flash-free"),
        ])

        result = self.run_selector(force=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertTrue(payload["selected"])
        self.assertTrue(payload["backup"])

        data = load_settings(self.settings)
        self.assertEqual(data["cli"]["agents"]["director"]["model"], "opencode/nemotron-3-ultra-free")

    def test_explicit_free_model(self):
        write_settings(self.settings)
        self.write_catalog([
            model_block("opencode", "nemotron-3-ultra-free"),
            model_block("opencode", "glm-5.3-flash-free"),
        ])

        result = self.run_selector(free_model="opencode/glm-5.3-flash-free")
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["high_model"], "opencode/glm-5.3-flash-free")
        self.assertEqual(payload["fast_model"], "opencode/glm-5.3-flash-free")

        data = load_settings(self.settings)
        agents = data["cli"]["agents"]
        self.assertEqual(agents["director"]["model"], "opencode/glm-5.3-flash-free")
        self.assertEqual(agents["engineer3"]["model"], "opencode/glm-5.3-flash-free")
        self.assertEqual(data["capability_tiers"]["opencode/glm-5.3-flash-free"]["max_bloom"], 4)

    def test_no_free_model_leaves_settings_unchanged(self):
        write_settings(self.settings)
        self.write_catalog([
            model_block("opencode", "paid-model", cost=1),
            model_block("lmstudio", "local-model"),
            model_block("opencode", "inactive-free", status="inactive"),
            model_block("opencode", "no-tools-free", toolcall=False),
        ])

        result = self.run_selector()
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertFalse(payload["selected"])
        self.assertTrue(payload["skipped"])

        data = load_settings(self.settings)
        self.assertEqual(data["cli"]["agents"]["director"]["model"], "")

    def test_opencode_go_is_fallback(self):
        write_settings(self.settings)
        self.write_catalog([
            model_block("opencode-go", "beam-free"),
        ])

        result = self.run_selector()
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(payload["high_model"], "opencode-go/beam-free")
        self.assertEqual(payload["fast_model"], "opencode-go/beam-free")

        data = load_settings(self.settings)
        self.assertEqual(
            data["cli"]["agents"]["director"]["model"],
            "opencode-go/beam-free",
        )

    def test_dry_run_does_not_write(self):
        write_settings(self.settings)
        self.write_catalog([
            model_block("opencode", "nemotron-3-ultra-free"),
            model_block("opencode", "deepseek-v4.1-flash-free"),
        ])

        result = self.run_selector(dry_run=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        payload = json.loads(result.stdout)
        self.assertTrue(payload["selected"])
        self.assertTrue(payload["dry_run"])
        self.assertIsNone(payload["backup"])

        data = load_settings(self.settings)
        self.assertEqual(data["cli"]["agents"]["director"]["model"], "")
        self.assertNotIn("model_selection", data)

    def test_running_guard_requires_allow_running(self):
        write_settings(self.settings)
        self.write_catalog([
            model_block("opencode", "nemotron-3-ultra-free"),
            model_block("opencode", "deepseek-v4.1-flash-free"),
        ])
        env = self.running_env(self.make_fake_running_bin())

        result = self.run_selector(force=True, env=env)
        self.assertEqual(result.returncode, 2, result.stderr)
        data = load_settings(self.settings)
        self.assertEqual(data["cli"]["agents"]["director"]["model"], "")
        self.assertNotIn("model_selection", data)

        result = self.run_selector(force=True, dry_run=True, env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = load_settings(self.settings)
        self.assertEqual(data["cli"]["agents"]["director"]["model"], "")

        result = self.run_selector(force=True, allow_running=True, env=env)
        self.assertEqual(result.returncode, 0, result.stderr)
        data = load_settings(self.settings)
        self.assertEqual(
            data["cli"]["agents"]["director"]["model"],
            "opencode/nemotron-3-ultra-free",
        )


if __name__ == "__main__":
    unittest.main()
