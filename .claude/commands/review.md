---
description: Inspect a proposed change before editing - affected systems, relevant docs/tests, proposed approach
argument-hint: <description of the proposed change>
---

Review this proposed change, described below, before touching any files:

$ARGUMENTS

Follow CLAUDE.md's working rules 1-2 (inspect before editing; identify
affected systems and propose an approach before broad edits). Do this:

1. Identify which system(s) this touches, using CLAUDE.md's architecture
   anchors table as the starting point. Read the actual code for anything not
   already clear from that table - do not guess from naming alone.
2. Check `docs/CURRENT_STATE.md` for that system's current status (Verified /
   Built, lightly tested / Foundation / Partial / Planned) and any known
   issues already recorded against it. Check `docs/DECISIONS.md` for any
   durable decision this change would need to respect or would contradict.
3. Look up relevant tests in `docs/TEST_MAP.md` by system/area. Note their
   Basis (Verified/Inferred) and any recorded baseline.
4. Determine the verification level this change needs, per CLAUDE.md's
   verification-level model (1-4), based on its actual size and blast
   radius - not automatically the highest level.
5. Propose the smallest coherent change that solves the stated problem.
   Flag any ambiguity in the request itself before proposing a specific
   implementation.

Do not edit any files during this command. Output: affected system(s),
current status per CURRENT_STATE.md, relevant decisions, relevant tests from
TEST_MAP.md, proposed verification level, and the proposed approach. If the
brief is ambiguous in a way that could produce a wrong implementation, say so
instead of guessing.
