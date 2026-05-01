"""Phase 8 / Q2.CO7 — A10 NL workflow lifecycle persona test.

Drives the full Sprint 19 close path from a single test:

  1. Login as panel admin.
  2. POST /v1/workflows/synthesize with NL intent → JSON workflow.
  3. Validate the workflow against the n8n-compatible schema (ABS subset).
  4. POST /v1/workflows/execute (dry_run) → step plan.
  5. POST /v1/workflows/execute (live) → job_id.
  6. Poll /v1/workflows/jobs/{id} until state=done.

Synchronous httpx so the script runs from the host without async harness.
"""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

import httpx


BASE = os.environ.get("ABS_BACKEND_URL", "http://localhost:8000")
LOGIN_PAYLOAD = {
    "email": os.environ.get("A10_LOGIN_EMAIL", "newuser4@demo.co"),
    "password": os.environ.get("A10_LOGIN_PASSWORD", "NewUser2026!"),
}
INTENT = (
    "Slack #support kanalına yeni mesaj geldiğinde Linear'da issue oluştur "
    "ve özetini Coqui TTS ile seslendir."
)


# Minimal ABS-flavoured n8n schema check — workflow has nodes, each node has
# id+kind, edges (if present) reference declared node ids.
def _validate_n8n_schema(workflow: dict) -> list[str]:
    issues: list[str] = []
    nodes = workflow.get("nodes")
    if not isinstance(nodes, list) or len(nodes) < 1:
        issues.append("nodes_missing_or_empty")
        return issues
    seen_ids: set[str] = set()
    for n in nodes:
        nid = n.get("id")
        if not nid or nid in seen_ids:
            issues.append(f"node_id_duplicate_or_missing:{nid}")
        seen_ids.add(nid)
        if not n.get("kind"):
            issues.append(f"node_kind_missing:{nid}")
    edges = workflow.get("edges") or []
    for e in edges:
        for key in ("source", "target"):
            ref = e.get(key) or e.get(key.replace("source", "from").replace("target", "to"))
            if ref and ref not in seen_ids:
                issues.append(f"edge_ref_unknown:{key}={ref}")
    return issues


def _expect(label: str, expected: object, actual: object) -> bool:
    ok = expected == actual
    print(f"  {'PASS' if ok else 'FAIL'}  {label} expected={expected} actual={actual}")
    return ok


def main() -> int:
    pass_ct = 0
    fail_ct = 0

    with httpx.Client(base_url=BASE, timeout=30.0) as client:
        # 1. Login
        login = client.post("/auth/login", json=LOGIN_PAYLOAD)
        if _expect("login", 200, login.status_code):
            pass_ct += 1
        else:
            fail_ct += 1
            return fail_ct
        cookies = login.cookies

        # 2. Synthesize
        synth = client.post(
            "/v1/workflows/synthesize",
            json={"intent": INTENT, "locale": "tr"},
            cookies=cookies,
        )
        if _expect("synthesize", 200, synth.status_code):
            pass_ct += 1
        else:
            fail_ct += 1
            return fail_ct
        body = synth.json()
        workflow = body["workflow"]
        if _expect("nodes >= 3", True, len(workflow["nodes"]) >= 3):
            pass_ct += 1
        else:
            fail_ct += 1

        # 3. Schema check
        issues = _validate_n8n_schema(workflow)
        if _expect("n8n schema clean", [], issues):
            pass_ct += 1
        else:
            fail_ct += 1

        # 4. Dry run
        dry = client.post(
            "/v1/workflows/execute",
            json={"workflow": workflow, "dry_run": True},
            cookies=cookies,
        )
        if _expect("dry_run status", 200, dry.status_code):
            pass_ct += 1
        else:
            fail_ct += 1
        dry_body = dry.json()
        if _expect("dry_run_ok", "dry_run_ok", dry_body.get("status")):
            pass_ct += 1
        else:
            fail_ct += 1

        # 5. Live execute
        live = client.post(
            "/v1/workflows/execute",
            json={"workflow": workflow, "dry_run": False},
            cookies=cookies,
        )
        if _expect("live status", 200, live.status_code):
            pass_ct += 1
        else:
            fail_ct += 1
        live_body = live.json()
        job_id = live_body.get("job_id")
        if _expect("job_id present", True, bool(job_id)):
            pass_ct += 1
        else:
            fail_ct += 1
            return fail_ct

        # 6. Poll
        final_state = None
        for _ in range(15):
            time.sleep(1)
            poll = client.get(f"/v1/workflows/jobs/{job_id}", cookies=cookies)
            if poll.status_code != 200:
                continue
            state = poll.json().get("state")
            if state == "done":
                final_state = state
                break
        if _expect("job state=done", "done", final_state):
            pass_ct += 1
        else:
            fail_ct += 1

    print(f"\nA10 PASS={pass_ct} FAIL={fail_ct}")
    Path("/tmp/a10_lifecycle.json").write_text(
        json.dumps(
            {
                "pass": pass_ct,
                "fail": fail_ct,
                "intent": INTENT,
                "nodes_seen": len(workflow["nodes"]),
                "schema_issues": issues,
                "job_state": final_state,
            },
            indent=2,
        )
    )
    return fail_ct


if __name__ == "__main__":
    sys.exit(main())
