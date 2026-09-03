# Working in this repository

This is a **throwaway feasibility prototype**. It exists to answer one question by running
it — can the pipeline the design calls for actually be built end to end — and it is meant
to be discarded once it has answered. Judge a change by whether it answered something, not
by how finished it looks.

Read this before making a change. [`CONTRIBUTING.md`](CONTRIBUTING.md) says how the thing
is put together; this file says what to build and what not to.

## What to build

**Only enough for a conforming Ruby program to compile.** No generalization, no future
extension, no abstraction nothing uses yet. Whatever was left out is written down
afterwards rather than filled in.

**No tests for what a program does.** A sample program that fails to compile before the
change and compiles after it is what stands in for one; the full check is in
[`CONTRIBUTING.md`](CONTRIBUTING.md#checking-a-change). The suites under `gems/*/spec/`
are a separate thing and stay small: they check that each gem resolves and loads on its
own, and that the seam between gems still holds. Do not write specs there for language
behaviour.

**No error guards.** No diagnostics, no defensive checks, no command-line options beyond
the few a build cannot do without, no branches for cases that cannot arise on the happy
path. The exception is a refusal that is itself the thing being proved — a program the
language is meant to reject has to actually be rejected.

**Write the sample first.** Put it in `samples/`, and confirm it fails on the current code
before implementing anything. A sample that already compiles is verifying nothing, and the
failure is what says where the question actually lies.

## When to stop and ask

Push back rather than through. Four things end the work instead of continuing it:

- **A gap in the specification.** Something is unspecified. Do not decide it here; report
  it and let it be decided where specifications are decided.
- **A contradiction.** Two rules disagree. Do not pick one. Lay out the conflict and ask.
- **A verification failure whose cause is the design.** Do not make the implementation
  agree with a broken specification.
- **Something that cannot be built as specified.** **This is a result, not a failure.**
  Record precisely what did not work and hand it back — that answer is the whole point of
  the prototype. Never hide it behind a workaround.

## Language

This repository is public and its artifacts are English-only: **code, comments,
`README.md` and the other prose files, and commit messages.**

**Pull request bodies and issues are written in Japanese.** They are addressed to the
people implementing this prototype, who are to be assumed to read Japanese only, and a
document that fails to reach its reader is worth nothing in the language it failed in.
This applies to pull requests and issues and to nothing else.

Nothing here points at a repository that is not public — no names, no paths, no document
titles, no section numbers. When a decision needs a reason, give the reason in its own
terms, so this repository reads on its own.

## Branches, commits and pull requests

Branch from `main` as `feat/<topic>` for something new or `fix/<topic>` for something
wrong, kebab-case: `feat/gpio-interrupt`, `fix/array-element-type-unification`.

Commits are **English, subject line only** — no body, no trailers — in the imperative:
`Implement the GPIO interrupt feasibility path`. **One commit, one reason**: never mix an
implementation with a refactoring. The usual sequence is

| | commit | example |
| --- | --- | --- |
| 1 | the sample, failing | `Add a GPIO interrupt feasibility sample` |
| 2 | the implementation | `Implement the GPIO interrupt feasibility path` |
| 3 | refactoring, if any | `Encapsulate realtime LIR analysis state` |
| 4 | the record | `Record what GPIO interrupts prove` |

The sample may join the implementation commit when they are one reason, but **the record
is always its own commit.**

Open the pull request with `gh pr create`. **Its structure is not prescribed** — write
what that particular change calls for, in whatever order reads best. Three things are
required:

- **A signature on the first line**, naming the agent and the model that wrote it —
  `*Created by Claude Opus 5*`. It goes above the summary. Whether a person or an agent
  wrote something cannot be reconstructed later, so it is recorded now.
- **An overall summary**, directly below the signature, complete enough on its own.
- **Evidence that nothing broke** — what was checked and what came back, with real
  figures.

Never write "verified" for something that was only built. Say "built but not
hardware-flashed".

## Recording it

The value of this repository is the record of what ran and what it cost, so a change is
not finished until it is written down: [`HISTORY.md`](HISTORY.md) for what was proved,
what was deliberately not implemented, and the measured cost;
[`samples/README.md`](samples/README.md) for the new sample;
[`README.md`](README.md) only if what a person types or sees has changed.
