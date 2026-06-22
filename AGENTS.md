# AGENTS.md

Guidance for AI agents working in this repository.

## What this is

`cleo_quality_review` is a Ruby gem (>= 3.2; developed on 3.4) exposing the
`check_quality` CLI. It runs local quality checks (e.g. Reek, Flog, Fasterer) over a diff and summarises the output for humans, agents, or GitHub via an LLM.

- Library: `lib/cleo_quality_review/`
- CLI entry point: `exe/check_quality` → `CleoQualityReview::CLI#run`
- Tests mirror the library under `test/lib/`

## Running tests

```sh
bundle exec rake test     # full suite (default rake task)
bundle exec guard         # watch + auto-run on change
```

Coverage is tracked by SimpleCov; aim for the 90% line-coverage target in
`.claude/rules/16-test-coverage.md`.

## Use defaults and conventions where possible

Prefer the established way over a new one. Before adding anything, look for how
the codebase already does it and follow that.

## Work with the Four Rules of Simple Design

Kent Beck's rules, in priority order. A design is "simpler" when it satisfies an earlier rule; later rules never override an earlier one.

1. **Passes the tests.** Behaviour is verified. Write/extend tests with the change,
   keep the suite green, and don't drop coverage.
2. **Reveals intention.** Names and structure make intent obvious. Prefer a clear
   name and a small well-named method over a comment explaining a murky one.
3. **No duplication.** Say each thing once. Extract a method, Struct, or module
   before logic is copied a third time — but not speculatively.
4. **Fewest elements.** Remove anything the first three rules don't require — no
   unused options, dead code, or abstractions added "for later".

When these tensions arise, follow the order: make it work and tested, then clear,
then DRY, then minimal.

## Other repo rules

See `.claude/rules/` for git workflow, test isolation, coverage, and
documentation specifics. Note: where those files describe a test setup (Mocha,
`ActiveSupport::TestCase`, FactoryBot) that differs from the code, **follow the
code.**
