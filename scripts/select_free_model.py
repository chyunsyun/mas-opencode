#!/usr/bin/env python3
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from datetime import datetime
from pathlib import Path

import yaml

HIGH_ROLES = ("director", "chief", "auditor", "engineer1", "engineer2")
FAST_ROLES = ("engineer3",)
ALL_ROLES = HIGH_ROLES + FAST_ROLES

PROVIDER_PRIORITY = ("opencode", "opencode-go")
MIN_CONTEXT = 128_000
HIGH_MAX_BLOOM = 4
FAST_MAX_BLOOM = 3

HIGH_PRIORITY = (
    "opencode/nemotron-3-ultra-free",
    "opencode/beam-free",
    "opencode/nemotron-3.5-super-vl-free",
    "opencode/big-pickle",
    "opencode/glm-5.3-flash-free",
    "opencode/deepseek-v4.1-flash-free",
    "opencode/mimo-v2.6-flash-free",
    "opencode/flint-40b-free",
    "opencode/nemotron-3.5-lightning-free",
    "opencode-go/beam-free",
    "opencode-go/iceman-contributor-free",
)

FAST_PRIORITY = (
    "opencode/deepseek-v4.1-flash-free",
    "opencode/glm-5.3-flash-free",
    "opencode/mimo-v2.6-flash-free",
    "opencode/nemotron-3.5-lightning-free",
    "opencode/flint-40b-free",
    "opencode/beam-free",
    "opencode/nemotron-3-ultra-free",
    "opencode/nemotron-3.5-super-vl-free",
    "opencode/big-pickle",
    "opencode-go/beam-free",
    "opencode-go/iceman-contributor-free",
)


def log(message: str) -> None:
    print(f"[free-model] {message}", file=sys.stderr)


def warn(message: str) -> None:
    print(f"[free-model] WARN: {message}", file=sys.stderr)


def default_settings_path() -> Path:
    env_path = os.environ.get("MAS_SETTINGS_FILE", "").strip()
    if env_path:
        return Path(env_path)
    root = os.environ.get("MAS_ROOT", "").strip()
    if root:
        return Path(root) / "config" / "settings.yaml"
    return Path(__file__).resolve().parent.parent / "config" / "settings.yaml"


def mas_root_is_running(root: Path) -> bool:
    root = root.resolve()
    pattern = str(root / "scripts" / "inbox_watcher.sh")

    pgrep = shutil.which("pgrep")
    if pgrep:
        result = subprocess.run(
            [pgrep, "-f", "--", pattern],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
        if result.returncode == 0:
            return True

    tmux = shutil.which("tmux")
    if not tmux:
        return False
    session = os.environ.get("MAS_SESSION", "").strip() or "mas"
    result = subprocess.run(
        [tmux, "list-panes", "-t", session, "-F", "#{pane_current_path}"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return False
    for line in result.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            if Path(line).resolve() == root:
                return True
        except OSError:
            continue
    return False


def parse_models(text: str) -> list[dict]:
    lines = text.splitlines()
    models: list[dict] = []
    index = 0
    while index < len(lines):
        line = lines[index].strip()
        if not line or line.startswith("{") or "/" not in line:
            index += 1
            continue

        key = line
        start = index + 1
        while start < len(lines) and not lines[start].lstrip().startswith("{"):
            start += 1
        if start >= len(lines):
            break

        depth = 0
        end = start
        while end < len(lines):
            depth += lines[end].count("{") - lines[end].count("}")
            end += 1
            if depth == 0:
                break
        if depth != 0:
            index = end
            continue

        try:
            obj = json.loads("\n".join(lines[start:end]))
        except json.JSONDecodeError:
            index = end
            continue
        obj["_key"] = key
        models.append(obj)
        index = end
    return models


def model_id(obj: dict) -> str:
    provider = str(obj.get("providerID") or "").strip()
    identifier = str(obj.get("id") or "").strip()
    if provider and identifier:
        return f"{provider}/{identifier}"
    return str(obj.get("_key") or "").strip()


def cost_is_zero(obj: dict) -> bool:
    cost = obj.get("cost")
    if not isinstance(cost, dict):
        return False
    cache = cost.get("cache") or {}
    if not isinstance(cache, dict):
        cache = {}
    for key in ("input", "output"):
        try:
            if float(cost.get(key, 0) or 0) != 0:
                return False
        except (TypeError, ValueError):
            return False
    for key in ("read", "write"):
        try:
            if float(cache.get(key, 0) or 0) != 0:
                return False
        except (TypeError, ValueError):
            return False
    return True


def context_limit(obj: dict) -> int:
    limit = obj.get("limit") or {}
    try:
        return int(limit.get("context") or 0)
    except (TypeError, ValueError):
        return 0


def is_usable_free(obj: dict) -> bool:
    if obj.get("status") != "active":
        return False
    if obj.get("providerID") not in PROVIDER_PRIORITY:
        return False
    if not cost_is_zero(obj):
        return False
    capabilities = obj.get("capabilities") or {}
    if not capabilities.get("toolcall"):
        return False
    return context_limit(obj) >= MIN_CONTEXT


def choose_model(preferred: tuple[str, ...], free_by_id: dict[str, dict]) -> str | None:
    for candidate in preferred:
        if candidate in free_by_id:
            return candidate
    for provider in PROVIDER_PRIORITY:
        candidates = [
            model
            for model in free_by_id.values()
            if model.get("providerID") == provider
        ]
        if not candidates:
            continue
        candidates.sort(
            key=lambda model: (
                context_limit(model),
                str(model.get("release_date") or ""),
            ),
            reverse=True,
        )
        return model_id(candidates[0])
    return None


def load_settings(path: Path) -> dict:
    with path.open(encoding="utf-8") as handle:
        data = yaml.safe_load(handle) or {}
    if not isinstance(data, dict):
        raise ValueError(f"settings must be a mapping: {path}")
    return data


def agent_config(data: dict, role: str) -> dict:
    cli = data.setdefault("cli", {})
    if not isinstance(cli, dict):
        cli = {}
        data["cli"] = cli
    cli["default"] = "opencode"
    agents = cli.setdefault("agents", {})
    if not isinstance(agents, dict):
        agents = {}
        cli["agents"] = agents
    config = agents.get(role)
    if isinstance(config, str):
        config = {"type": config}
    if not isinstance(config, dict):
        config = {}
    config["type"] = "opencode"
    agents[role] = config
    return config


def has_configured_model(data: dict) -> bool:
    cli = data.get("cli") or {}
    agents = cli.get("agents") or {}
    if not isinstance(agents, dict):
        return False
    for role in ALL_ROLES:
        config = agents.get(role)
        if isinstance(config, str):
            return bool(config.strip())
        if isinstance(config, dict) and str(config.get("model") or "").strip():
            return True
    return False


def write_settings(path: Path, data: dict) -> str:
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup = path.with_name(f"{path.name}.bak.{stamp}")
    suffix = 0
    while backup.exists():
        suffix += 1
        backup = path.with_name(f"{path.name}.bak.{stamp}.{suffix}")

    shutil.copy2(path, backup)
    mode = path.stat().st_mode

    fd, temp_name = tempfile.mkstemp(
        dir=str(path.parent),
        prefix=f".{path.name}.",
        suffix=".tmp",
    )
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            yaml.safe_dump(data, handle, allow_unicode=True, sort_keys=False)
        os.chmod(temp_name, mode)
        os.replace(temp_name, path)
    except Exception:
        try:
            os.unlink(temp_name)
        except FileNotFoundError:
            pass
        raise
    return str(backup)


def run_models(opencode_bin: str, verbose: bool, timeout: int) -> str:
    args = [opencode_bin, "models"]
    if verbose:
        args.append("--verbose")
    result = subprocess.run(
        args,
        capture_output=True,
        text=True,
        timeout=timeout,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(
            f"{' '.join(args)} failed ({result.returncode}): "
            f"{(result.stderr or '').strip()}"
        )
    return result.stdout


def refresh_models(opencode_bin: str, timeout: int) -> None:
    try:
        result = subprocess.run(
            [opencode_bin, "models", "--refresh"],
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        if result.returncode != 0:
            warn(
                "opencode models --refresh failed; using cached model list: "
                f"{(result.stderr or '').strip()}"
            )
    except Exception as exc:
        warn(f"opencode models --refresh failed; using cached model list: {exc}")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Select free OpenCode models and write them to settings.yaml",
    )
    parser.add_argument(
        "--settings",
        type=Path,
        default=default_settings_path(),
        help="settings.yaml path",
    )
    parser.add_argument(
        "--models-file",
        type=Path,
        help="read opencode models --verbose output from a file (for tests)",
    )
    parser.add_argument(
        "--refresh",
        action="store_true",
        help="run opencode models --refresh before reading the model list",
    )
    parser.add_argument(
        "--free-model",
        default="",
        help="explicit free model id (provider/model) for every role",
    )
    parser.add_argument(
        "--force",
        action="store_true",
        help="overwrite existing model settings",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="report the selection without writing settings",
    )
    parser.add_argument(
        "--allow-running",
        action="store_true",
        help="write settings even if the MAS instance is running",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="print a machine-readable result",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=60,
        help="opencode command timeout in seconds",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    settings_path: Path = args.settings

    if not settings_path.is_file():
        log(f"settings not found: {settings_path}")
        return 1

    if not args.dry_run and not args.allow_running:
        root = settings_path.resolve().parent.parent
        if mas_root_is_running(root):
            log(
                "mas_oc is running; refusing to write settings "
                "(stop it or use --allow-running)"
            )
            return 2

    try:
        data = load_settings(settings_path)
    except Exception as exc:
        log(f"failed to read {settings_path}: {exc}")
        return 1

    if not args.force and not args.free_model and has_configured_model(data):
        message = "existing model settings found; left unchanged"
        log(message)
        if args.json:
            print(json.dumps({
                "selected": False,
                "skipped": True,
                "reason": message,
                "settings": str(settings_path),
            }, ensure_ascii=False))
        return 0

    text = ""
    if args.models_file:
        try:
            text = args.models_file.read_text(encoding="utf-8")
        except OSError as exc:
            log(f"failed to read {args.models_file}: {exc}")
            return 1
    else:
        opencode_bin = (
            os.environ.get("OPENCODE_BIN", "").strip()
            or shutil.which("opencode")
            or ""
        )
        if not opencode_bin:
            warn("opencode not found; free model selection skipped")
            if args.json:
                print(json.dumps({
                    "selected": False,
                    "skipped": True,
                    "reason": "opencode not found",
                    "settings": str(settings_path),
                }, ensure_ascii=False))
            return 0
        if args.refresh:
            refresh_models(opencode_bin, args.timeout)
        try:
            text = run_models(opencode_bin, verbose=True, timeout=args.timeout)
        except Exception as exc:
            warn(f"failed to list OpenCode models: {exc}")
            if args.json:
                print(json.dumps({
                    "selected": False,
                    "skipped": True,
                    "reason": "failed to list models",
                    "settings": str(settings_path),
                }, ensure_ascii=False))
            return 0

    models = parse_models(text)
    free_models = {
        model_id(model): model for model in models if is_usable_free(model)
    }
    if not free_models:
        warn("no usable free model found; settings left unchanged")
        if args.json:
            print(json.dumps({
                "selected": False,
                "skipped": True,
                "reason": "no usable free model",
                "settings": str(settings_path),
            }, ensure_ascii=False))
        return 0

    if args.free_model:
        requested = args.free_model.strip()
        if requested not in free_models:
            log(f"requested free model is not available: {requested}")
            return 1
        high_model = requested
        fast_model = requested
    else:
        high_model = choose_model(HIGH_PRIORITY, free_models)
        fast_model = choose_model(FAST_PRIORITY, free_models)
        if not high_model:
            high_model = fast_model
        if not fast_model:
            fast_model = high_model
        if not high_model or not fast_model:
            warn("no usable free model found; settings left unchanged")
            return 0

    for role in ALL_ROLES:
        config = agent_config(data, role)
        config["model"] = high_model if role in HIGH_ROLES else fast_model
        if role == "engineer3":
            config["max_bloom"] = 3

    tiers = data.setdefault("capability_tiers", {})
    if not isinstance(tiers, dict):
        tiers = {}
        data["capability_tiers"] = tiers
    tiers.setdefault(high_model, {})["max_bloom"] = HIGH_MAX_BLOOM
    if fast_model != high_model:
        tiers.setdefault(fast_model, {})["max_bloom"] = FAST_MAX_BLOOM

    data["model_selection"] = {
        "source": "opencode-free",
        "selected_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "high_model": high_model,
        "fast_model": fast_model,
        "provider_priority": list(PROVIDER_PRIORITY),
        "candidates": sorted(free_models),
    }

    backup = None
    if not args.dry_run:
        try:
            backup = write_settings(settings_path, data)
        except Exception as exc:
            log(f"failed to write {settings_path}: {exc}")
            return 1

    result = {
        "selected": True,
        "skipped": False,
        "high_model": high_model,
        "fast_model": fast_model,
        "settings": str(settings_path),
        "backup": backup,
        "dry_run": bool(args.dry_run),
        "candidates": sorted(free_models),
    }
    log(
        f"high={high_model} fast={fast_model} "
        f"bloom={HIGH_MAX_BLOOM}/{FAST_MAX_BLOOM} "
        f"{'dry-run' if args.dry_run else 'written'}"
    )
    if args.json:
        print(json.dumps(result, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
