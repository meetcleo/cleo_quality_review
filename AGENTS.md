# AGENTS.md

Guidance for AI agents working in this repository.

## What this is

`cleo_quality_review` is a Ruby gem (>= 3.2; developed on 3.4) exposing the
`check_quality` CLI. It runs local quality checks (Reek, Flog, Fasterer) over a
diff and summarises the output for humans, agents, or GitHub via an LLM.

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

- **Convention over configuration.** Lean on Ruby and library defaults; don't add
  config, flags, or dependencies for things the defaults already handle.
- **Follow the existing structure.** Each `lib/cleo_quality_review/foo.rb` has a
  matching `test/lib/cleo_quality_review/foo_test.rb`. New code follows suit.
- **Reuse the established patterns** rather than inventing parallel ones:
  - Value objects are `Struct.new(..., keyword_init: true)` (e.g. `command_result.rb`).
  - Module-level interfaces use `class << self`, not `module_function` (e.g. `checks.rb`).
  - Public methods carry YARD/RDoc `##` comments with `@param`/`@return` types.
- **Match the test conventions actually in use** (the code, not the `.claude/rules`
  wording, is the source of truth here):
  - Plain `Minitest::Test` with `def test_…` methods, run via `minitest/autorun`.
  - Specific assertions (`assert_equal`, `assert_includes`, `assert_predicate`) over bare `assert`.
  - Stub dependencies with small `Struct`-based fakes or `define_singleton_method`;
    there is no Mocha/FactoryBot in this gem.
- Add a new dependency, tool, or abstraction only when an existing one genuinely
  doesn't fit — and say why.

## Work with the Four Rules of Simple Design

Kent Beck's rules, in priority order. A design is "simpler" when it satisfies an
earlier rule; later rules never override an earlier one.

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
