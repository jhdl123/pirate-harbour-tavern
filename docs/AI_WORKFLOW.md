# AI / Development Workflow

## Goal

ChatGPT and Claude do different jobs; GitHub is the shared source of truth.

    ChatGPT      design, architecture, second opinion
    Claude Code  implementation, testing, debugging
    GitHub       source of truth, shared memory
    Godot        execution, playtesting

## Roles

**ChatGPT** — design, systems thinking, balancing, architecture review,
challenging assumptions, turning vague ideas into briefs. Not the
implementation source of truth.

**Claude Code** — repository inspection, implementation, refactoring, running
Godot, tests, diagnostics, debugging, commits. Works directly against the
current repository.

**Claude Chat** — optional. Do not make it a mandatory stage when the design is
already agreed. Useful when repository access is unavailable, or for review of
diagnostic output.

**Cowork** — optional, for large delegated analysis across many files or
reports. Not part of the normal build loop.

## Standard feature workflow

1. Discuss the design; define the problem and the desired player experience.
2. Define rules, constraints and edge cases; identify the evidence needed.
3. Record durable decisions in `DECISIONS.md`.
4. Give Claude Code a concise brief.
5. Claude Code inspects, plans, and flags ambiguity **before** editing.
6. Implement, test, diagnose, report, commit.
7. Playtest, then return to design discussion if interpretation is needed.

## ChatGPT → Claude Code handoff format

What Claude Code needs from a design discussion — nothing more. Claude Code
investigates the repository itself; do not pre-explain it.

    Objective            what this should achieve, one or two sentences
    Desired behaviour    what should happen, from the player's or system's
                          perspective
    Constraints          anything ruled out - performance, scope, systems not
                          to touch, existing decisions to respect
    Design decisions     choices already made that should not be re-opened
    Acceptance criteria  how to tell the implementation is actually done

Paste this as the brief to `/feature` (or into plain conversation) — see
"Workflow commands" below.

## Standard bug workflow

1. Reproduce.
2. Collect the smallest useful evidence.
3. Check prerequisites — stock, staffing, run length, sample size.
4. Classify: implementation, configuration, navigation, data, staffing, stock,
   timing, test setup, or design.
5. Fix the actual cause, not the symptom.
6. Targeted tests, then regressions.
7. Representative simulation for anything statistical.
8. Commit.

## Evidence discipline

Do not compare runs of different length, customer count, staffing or stock and
attribute the difference to one change. If a metric is surprising, instrument
before tuning it again.

**Verifying a node exists is not verifying it is wired to its caller.** A
missing reference produces a silent null, not an error.

## Token efficiency

Do not paste the project into conversations. Use `CLAUDE.md`,
`CURRENT_STATE.md`, `DECISIONS.md` and focused system docs as persistent
context. Read only files relevant to the task.

## Git workflow

Clean start → feature branch → focused changes → tests → review the diff →
commit → merge. Avoid ZIP handoffs when direct repository access exists. Never
rely on `git stash` to protect uncommitted work.

## Definition of done

Design agreed · implementation complete · relevant tests pass · behaviour
demonstrated · no obvious regression · affected documentation updated · a
focused commit in Git.

## Source-of-truth hierarchy

1. Current code and resources — what exists.
2. `DECISIONS.md` — durable intent.
3. `GAME_DESIGN.md` — design direction.
4. `CURRENT_STATE.md` — verified summary.
5. Other system documentation.
6. Old chats and `docs/history/` reports — history, not authority.

## Workflow commands

`.claude/commands/` mechanizes the loops above so they don't need restating
per request:

    /status    repo health - branch, tree, last commits, Godot version
    /review    inspect a proposed change before editing (step 5 above)
    /test      run relevant/selected/all tests via tools/run_tests.ps1
    /verify    pre-merge check at the verification level CLAUDE.md defines
    /debug     the standard bug workflow above, systematically
    /feature   take a handoff brief (above) through to a tested change
    /commit    pre-commit report; never commits without explicit approval

Verification levels are defined in `CLAUDE.md`, not here — `/review` picks
the level for a change, `/verify` and `/commit` apply it.

## Claude Code prompt pattern

Before work:

> Inspect the current implementation and relevant documentation first. Do not
> edit yet. Summarise existing behaviour, identify relevant files, and propose
> the smallest implementation that satisfies the agreed design. Flag ambiguity
> before broad changes.

After approval:

> Implement the agreed change. Run targeted tests, relevant regressions and
> diagnostics where required. Do not modify unrelated systems. Report exactly
> what changed, what was tested, the results and remaining uncertainty.
