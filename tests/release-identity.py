"""Assert native packaged identity, including missing/wrong provenance controls."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

binary, expected, revision = sys.argv[1:]
probe = """
import json
from hermes_cli import __version__
from hermes_cli.version_info import get_version_info, get_code_identity
from pm.paths import repo_root, install_stamp_path
info = get_version_info()
print(json.dumps(dict(version=info.derived_version, base=info.base_version,
    commit=info.commit, source=info.source, distribution=info.distribution,
    distance=info.distance, compatibility=__version__, code=get_code_identity(),
    root=str(repo_root()), stamp=str(install_stamp_path(repo_root())))))
"""
with tempfile.TemporaryDirectory() as temporary:
    root = Path(temporary)
    env = dict(PATH=os.path.dirname(sys.executable), HOME=str(root),
               HERMES_HOME=str(root / "home"), PYTHONNOUSERSITE="1")

    def identity(environment):
        return json.loads(subprocess.check_output(
            [sys.executable, "-c", probe], env=environment, text=True))

    def matches(info):
        return (info["version"] == expected and info["base"] == expected
                and info["commit"] == revision)

    missing = root / "missing"
    missing.mkdir()
    assert not matches(identity(dict(env, HERMES_INSTALL_ROOT=str(missing)))), "missing identity accepted"
    wrong = root / "wrong"
    wrong.mkdir()
    (wrong / "install-stamp.json").write_text(json.dumps(dict(
        schemaVersion=2, commit=revision, baseVersion="0.0.0",
        displayVersion="0.0.0", distance=0, source="nix", distribution="nix",
        updateMechanism="external", payload="bootstrap")))
    assert not matches(identity(dict(env, HERMES_INSTALL_ROOT=str(wrong)))), "wrong version accepted"
    stamp = json.loads((wrong / "install-stamp.json").read_text())
    stamp.update(baseVersion=expected, displayVersion=expected, commit="f" * 40)
    (wrong / "install-stamp.json").write_text(json.dumps(stamp))
    assert not matches(identity(dict(env, HERMES_INSTALL_ROOT=str(wrong)))), "wrong revision accepted"
    info = identity(env)
    assert matches(info), f"installed identity mismatch: {info}"
    assert info["source"] == info["distribution"] == "nix"
    assert info["distance"] == 0 and info["compatibility"] == expected
    assert info["code"]["sha"] == revision and info["code"]["version"] == expected
    assert info["root"].startswith("/nix/store/") and Path(info["stamp"]).is_file()
    output = subprocess.check_output([binary, "--version"], env=env, text=True)
    assert output.splitlines()[0].startswith(f"Hermes Agent v{expected} (")
    print(output, end="")
    print(f"PASS immutable-native-identity {expected} {revision}")
