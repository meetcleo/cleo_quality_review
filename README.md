# Cleo Quality Review

[![Tests](https://github.com/meetcleo/cleo-quality-review/actions/workflows/tests.yml/badge.svg?branch=main)](https://github.com/meetcleo/cleo-quality-review/actions/workflows/tests.yml)
[![Gem Version](https://badge.fury.io/rb/cleo_quality_review.svg?icon=si%3Arubygems)](https://badge.fury.io/rb/cleo_quality_review)


Runs a suite of code quality tools against your code changes, and feeds them to an LLM to help make the feedback easier to apply.

> [!IMPORTANT]
> This tool uses an LLM (OpenAI) behind the scenes — every review sends your code and the quality
> tool output to the OpenAI API. You provide your own API key
> (`CLEO_QUALITY_REVIEW_OPEN_AI_KEY`), so **you incur your own token costs** for each run. It is your responsibility to understand how OpenAI billing works when using this tool.

## Use cases

### Review my own code locally before pushing

This will run all of the tools locally, and report back a human-readable report on what needs changed and why.

```
bundle exec check_quality foo.rb
```

### 🤖 Agents review their own code before pushing

This will run all of the tools locally, and report back an agent-readable report on what needs changed and why.

```
bundle exec check_quality foo.rb --format=agent
```

### 🤖 Github actions reviews changes on PR

This will run all of the tools on a PR branch, and report back a github-readable report on what needs changed and why. This will add [annotation comments](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands#setting-a-debug-message) to your code where issues are reported.

```
bundle exec check_quality foo.rb --format=github
```


## Installation

```
bundle add cleo_quality_review --group=development
```

In your local environment, configure the ENV variable named `CLEO_QUALITY_REVIEW_OPEN_AI_KEY` with your own [OpenAI API key](https://platform.openai.com/api-keys).

### Setting your API key

Exporting the key from your shell config is the common way to persist an OpenAI API key for local use. Add it to `~/.zshrc` (zsh — the default shell on macOS) or `~/.bashrc` / `~/.bash_profile` (bash):

```bash
echo 'export CLEO_QUALITY_REVIEW_OPEN_AI_KEY="sk-..."' >> ~/.zshrc
source ~/.zshrc   # reload now, or just open a new terminal
```



## Usage 

```bash
bundle exec check_quality --format agent --checks reek --files vendor/cleo_quality_review/lib
bundle exec check_quality --format github --checks fasterer --files app/services/my_area
CLEO_QUALITY_REVIEW_OPEN_AI_KEY=sk-... bundle exec check_quality --format human --files app/models/example.rb
```

`--files` accepts files or directories. Directories are expanded recursively, then filtered by the active config. When `--files` is omitted, `check_quality` targets changed files from `origin/main...HEAD` that match the active config. Use `--base REF` to compare against another fetched ref, such as `--base origin/feature-branch`.

CI can split analysis from output rendering so the Ruby quality tools run once and multiple outputs reuse the same artifacts:

```bash
# On a pull request, analyze reads the previously-reviewed commit from the PR to scope the diff,
# so pass GITHUB_TOKEN here as well as to publish-pr-review.
review_id="$(GITHUB_TOKEN=... bundle exec check_quality analyze --checks all --changed)"
bundle exec check_quality render --format github --review-id "${review_id}"
bundle exec check_quality render --format pr_review --review-id "${review_id}" > "tmp/quality_checks/${review_id}/pr_review.json"
GITHUB_TOKEN=... bundle exec check_quality publish-pr-review --review-id "${review_id}"
```

`analyze` prints the deterministic review ID for the captured diff. The artifact directory is `tmp/quality_checks/<review_id>/`, and later commands reuse it when `complete.json` is present.

## Incremental re-review on pull requests

On a pull request that has already been reviewed, `analyze` diffs against the most recent commit it previously reviewed rather than against `origin/main`.
Only code changed since that review is re-analysed, so findings on unchanged code are not repeated on every push.
The first review of a pull request still covers the whole diff.

The previously-reviewed commit is read from the pull request's existing reviews via the GitHub API.
The `analyze` step therefore needs `GITHUB_TOKEN` in its environment, alongside the `GITHUB_EVENT_PATH` and `GITHUB_REPOSITORY` variables that GitHub Actions provides automatically.
Without a token, or outside a pull request, `analyze` falls back to the full `origin/main` diff.

If a force-push rewrites the branch, the newest previously-reviewed commit that is still an ancestor of `HEAD` is used, and the review falls back to the full diff when none survive.

Set `CLEO_QUALITY_REVIEW_INCREMENTAL=0` (or `false`, `no`, `off`) to disable incremental re-review and always analyse the full diff.

## Checks

The gem embeds Ruby check adapters for Reek, Flog, and Fasterer. Each run writes raw tool artifacts to `tmp/quality_checks/<review_id>/<tool_type>/<check>/raw_output.*` and also normalizes findings for machine-readable output.

Checks run in parallel, one worker per CPU core by default. Override with `--jobs N` (`-j`) or `CLEO_QUALITY_REVIEW_MAX_CONCURRENCY`.

`agent` output uses the agent prompt to condense run metadata, the git diff, raw tool outputs, and normalized findings into JSON for coding agents.

`github` output uses the GitHub prompt to condense the full report into GitHub workflow annotations for the most relevant findings.

`pr_review` output uses the PR review prompt to condense the full report into JSON for GitHub pull request reviews.

`publish-pr-review` posts that rendered PR review JSON. Comments that map to commentable right-side diff lines become inline review comments; comments that do not map cleanly are omitted.

## Prompts

Every run combines two prompts: a shared `configuration` prompt and a format-specific prompt.

`configuration` defines the standard review rules that apply to every run regardless of output format: the inputs, tool thresholds, prioritisation, and noise-reduction rules. The format-specific prompts define only the output shape:

- `human`
- `agent`
- `github`
- `pr_review`

Local overrides are loaded first from `.cleo_quality_review/prompts/<format>.md`, then `.cleo_quality_review/<format>.md`. For backwards compatibility, `human` also supports `.cleo_quality_review/prompt.md`. If no local prompt exists, the gem uses `vendor/cleo_quality_review/prompts/<format>.md`. The `configuration` prompt follows the same lookup, so it can be overridden per repository.

## File Configuration

Target files are configured with YAML. The gem always loads its default config, then optionally loads `.cleo_quality_review.yaml` from the repository root.

```yaml
inherit_from:
  - ~/.config/cleo_quality_review.yml

AllTools:
  Include:
    - "**/*.rb"
    - "**/*.rake"
  Exclude:
    - "vendor/**/*"
    - "db/schema.rb"
```

`inherit_from` accepts a string or list of config files. Relative paths are resolved from the config file that declares them, and `~` can be used for user-level preferences. The special values `default` and `gem:default` point at the gem's bundled default config.


## LLM Configuration

All output formats use OpenAI's Responses API.

| Variable | Required | Description |
|----------|----------|-------------|
| `CLEO_QUALITY_REVIEW_OPEN_AI_KEY` | Yes | OpenAI API key |
| `CLEO_QUALITY_REVIEW_TIMEOUT_SECONDS` | No | OpenAI request timeout in seconds (default: 180) |

The model is currently fixed to `gpt-5.5`.
