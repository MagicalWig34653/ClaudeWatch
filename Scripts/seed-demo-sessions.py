#!/usr/bin/env python3
"""Posts a set of realistic Claude Code hook payloads to a running ClaudeWatch.

Used to produce the README screenshots; also handy for trying the UI locally:

    python3 Scripts/seed-demo-sessions.py [--port 17831]

Payload shapes match the real Claude Code hook fixtures in
ClaudeWatchCore/Tests/ClaudeWatchCoreTests/Fixtures/hooks. Transcript paths point at
cswap session directories so accounts resolve when cswap is set up with slots 1 and 2.
"""
import argparse
import json
import os
import time
import urllib.request

HOME = os.path.expanduser("~")
PROJECTS = f"{HOME}/Projects"


def transcript(slot: int, email_slug: str, session_id: str) -> str:
    return f"{HOME}/.claude-swap-backup/sessions/{slot}-{email_slug}/projects/demo/{session_id}.jsonl"


WORK = (1, "work_example.com")
PERSONAL = (2, "me_example.org")

SESSIONS = [
    # (session id, project, account, events)
    ("5f1d7c2e-0b1a-4c55-9d3e-7a2b1c9e0f11", "docs", WORK, [
        {"hook_event_name": "SessionStart", "source": "startup"},
        {"hook_event_name": "Stop", "last_assistant_message": "Updated the API reference and fixed three broken links."},
    ]),
    ("c2a4e6f8-1b3d-4f5a-8c7e-9d0b2a4c6e81", "cli-tools", PERSONAL, [
        {"hook_event_name": "SessionStart", "source": "startup"},
        {"hook_event_name": "Stop", "last_assistant_message": "Added shell completions for zsh and fish. All 128 tests pass."},
    ]),
    ("9b8a7c6d-5e4f-4a3b-2c1d-0e9f8a7b6c52", "data-pipeline", PERSONAL, [
        {"hook_event_name": "SessionStart", "source": "startup"},
        {"hook_event_name": "StopFailure", "error": "rate_limit", "error_details": "5-hour limit reached"},
    ]),
    ("3e5c7a9b-2d4f-4b6a-8e0c-1f3a5c7e9b27", "ios-app", PERSONAL, [
        {"hook_event_name": "SessionStart", "source": "startup"},
        {"hook_event_name": "UserPromptSubmit", "prompt": "Add pull-to-refresh to the feed"},
        {"hook_event_name": "PostToolUse", "tool_name": "Edit", "tool_input": {"file_path": f"{PROJECTS}/ios-app/FeedView.swift"}},
    ]),
    ("7d9f1b3c-5e7a-4c9e-b1d3-f5a7c9e1b3d4", "infra", WORK, [
        {"hook_event_name": "SessionStart", "source": "startup"},
        {"hook_event_name": "PreToolUse", "tool_name": "ExitPlanMode", "tool_use_id": "toolu_demo_plan",
         "tool_input": {"plan": "## Move CI to macOS 15 runners\n\n1. Update the workflow matrix\n2. Pin Xcode"}},
    ]),
    ("a1c3e5b7-d9f2-4e6a-8c0b-2d4f6a8c0e19", "website", WORK, [
        {"hook_event_name": "SessionStart", "source": "startup"},
        {"hook_event_name": "PermissionRequest", "tool_name": "Bash",
         "tool_input": {"command": "npm run deploy -- --prod", "description": "Deploy the site"}},
    ]),
    ("6f1c2b8e-4d3a-4e5f-9a7b-1c2d3e4f5a6b", "backend-api", WORK, [
        {"hook_event_name": "SessionStart", "source": "startup"},
        {"hook_event_name": "UserPromptSubmit", "prompt": "Add a migration for the orders table"},
        {"hook_event_name": "PreToolUse", "tool_name": "AskUserQuestion", "tool_use_id": "toolu_demo_question",
         "tool_input": {"questions": [{
             "question": "Which migration strategy should be used?", "header": "Migration", "multiSelect": False,
             "options": [{"label": "Online", "description": "Backfill in batches"},
                         {"label": "Offline", "description": "Maintenance window"}]}]}},
    ]),
]


def post(port: int, payload: dict) -> None:
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}/v1/events",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    # Never route loopback traffic through a proxy.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    with opener.open(request, timeout=5) as response:
        response.read()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--port", type=int, default=17831)
    args = parser.parse_args()
    for index, (session_id, project, (slot, slug), events) in enumerate(SESSIONS):
        base = {
            "session_id": session_id,
            "cwd": f"{PROJECTS}/{project}",
            "transcript_path": transcript(slot, slug, session_id),
            "prompt_id": f"demo-turn-{index}",
            "permission_mode": "default",
        }
        for event in events:
            post(args.port, {**base, **event})
            time.sleep(0.3)
        print(f"{session_id}  {project}")
        time.sleep(1)


if __name__ == "__main__":
    main()
