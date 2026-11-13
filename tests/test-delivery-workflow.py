import os
from pathlib import Path
import subprocess

import yaml


ROOT = Path(__file__).resolve().parents[1]


def test_title_edits_are_checked_as_data(tmp_path):
    workflow = yaml.load(
        (ROOT / ".github/workflows/ci.yml").read_text(), Loader=yaml.BaseLoader
    )
    assert "edited" in workflow["on"]["pull_request"]["types"]
    step = next(
        s for s in workflow["jobs"]["governance"]["steps"]
        if s.get("name") == "Validate PR title"
    )
    assert step["env"]["PR_TITLE"] == "${{ github.event.pull_request.title }}"
    marker = tmp_path / "executed"
    for title, valid in [("fix(api)!: change response", True), ("update", False),
                         (f"fix: $(touch {marker})", True)]:
        result = subprocess.run(
            ["sh", "-c", step["run"]], cwd=ROOT,
            env={**os.environ, "PR_TITLE": title}, capture_output=True,
        )
        assert (result.returncode == 0) == valid
        assert not marker.exists()
