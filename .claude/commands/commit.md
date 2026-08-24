---
description: Pre-commit review and concise report - does NOT commit unless explicitly approved
---

Prepare the current changes for a commit. This command inspects and reports;
it does not run `git commit` unless the user's own instruction accompanying
this command explicitly approves committing right now.

1. Run `git status` and `git diff` (and `git diff --staged` if anything is
   already staged) to see exactly what changed.
2. Run the verification appropriate to the change (same logic as `/verify`):
   `git diff --check`, relevant tests from `docs/TEST_MAP.md` via
   `tools/run_tests.ps1` for any behaviour change, confirmation that no
   unrelated files changed.
3. Decide what should be staged. Prefer adding specific files by name over
   `git add -A`/`git add .`. Do not stage anything that looks like a secret,
   credential, or generated/local-only artifact.
4. Draft a concise commit message (why, not just what) following this
   repository's existing commit style (`git log` for recent examples).
5. Produce a pre-commit report: files to be staged, verification results,
   the draft commit message, and anything uncertain.

Stop there. Only run `git add` and `git commit` if the user has explicitly
approved committing in the message that invoked this command - if that
approval isn't there, present the report and ask. Never push. Never use
`git commit --amend`, `--no-verify`, or `-c commit.gpgsign=false` unless the
user explicitly asked for that specific flag.
