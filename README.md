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

Checks run in parallel across a bounded pool of worker threads, sized to the machine's CPU count by default, so the gem scales with the host. When there are more checks than workers, the surplus queues and runs as workers free up. Set the worker count with `--jobs N` (alias `-j`) or the `CLEO_QUALITY_REVIEW_MAX_CONCURRENCY` environment variable; the flag takes precedence over the variable, which takes precedence over the CPU count. Findings stay in check order regardless of how the work is scheduled.

```bash
bundle exec check_quality analyze --checks all --jobs 2
CLEO_QUALITY_REVIEW_MAX_CONCURRENCY=2 bundle exec check_quality analyze --checks all
```

`agent` output uses the agent prompt to condense run metadata, the git diff, raw tool outputs, and normalized findings into JSON for coding agents.

`github` output uses the GitHub prompt to condense the full report into GitHub workflow annotations for the most relevant findings.

`pr_review` output uses the PR review prompt to condense the full report into JSON for GitHub pull request reviews.

`publish-pr-review` posts that rendered PR review JSON. Comments that map to commentable right-side diff lines become inline review comments; comments that do not map cleanly are omitted.

## Prompts

Prompts are format-specific:

- `human`
- `agent`
- `github`
- `pr_review`

Local overrides are loaded first from `.cleo_quality_review/prompts/<format>.md`, then `.cleo_quality_review/<format>.md`. For backwards compatibility, `human` also supports `.cleo_quality_review/prompt.md`. If no local prompt exists, the gem uses `vendor/cleo_quality_review/prompts/<format>.md`.

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

## Architecture

`check_quality` is a thin executable over the `CleoQualityReview` library. A run resolves the target files, executes the selected Ruby quality tools, stores raw artifacts, normalizes findings, and then renders one of the supported output formats.

```mermaid
%%{init: {"themeVariables": {"fontSize": "32px"}}}%%
flowchart LR
    Executable["exe/check_quality"]:::accent --> CLI["CLI"]:::accent
    CLI --> RootRegistrations["CleoQualityReview root registrations"]:::accent
    RootRegistrations --> ChecksModule["Checks"]:::rounded
    RootRegistrations --> LlmProvidersModule["LlmProviders"]:::rounded
    CLI --> Options["Options"]:::rounded
    CLI --> Runner["Runner"]:::accent
    CLI --> Formatter["Formatter"]:::accent
    CLI --> GitHubReviewPublisher["GitHubReviewPublisher"]:::positive
    Options --> Runner

    Runner --> TargetResolver["TargetResolver"]:::rounded
    TargetResolver --> Configuration["Configuration"]:::neutral
    TargetResolver --> Git["Git"]:::info
    Runner --> RunArtifacts["RunArtifacts"]:::neutral
    RunArtifacts --> Git

    Runner --> ChecksModule
    ChecksModule --> ChecksRegistry["Checks::Registry"]:::rounded
    ChecksModule --> QualityCheck["QualityCheck"]:::rounded
    ChecksRegistry --> QualityCheck
    Runner --> QualityCheck
    QualityCheck --> CommandRunner["CommandRunner"]:::rounded
    CommandRunner --> Tools["Reek / Flog / Fasterer"]:::info

    RunArtifacts --> Run["Run"]:::rounded
    Runner --> Run

    Formatter --> Run
    Formatter --> PromptLoader["PromptLoader"]:::neutral
    Formatter --> PromptBuilder["PromptBuilder"]:::rounded
    PromptBuilder --> Run
    PromptBuilder --> RunArtifacts
    Formatter --> LlmClient["LlmClient"]:::info
    LlmClient --> LlmConfig["LlmConfig"]:::neutral
    LlmClient --> LlmProvidersModule
    LlmProvidersModule --> LlmProvidersRegistry["LlmProviders::Registry"]:::rounded
    LlmProvidersModule --> OpenAiProvider["OpenAi::Provider"]:::info
    LlmProvidersModule --> StubProvider["Stub::Provider"]:::neutral
    LlmConfig --> OpenAiConfig["OpenAi::Config"]:::neutral
    LlmConfig --> StubConfig["Stub::Config"]:::neutral
    OpenAiProvider --> OpenAiClient["OpenAi::Client"]:::info
    OpenAiProvider --> OpenAiConfig
    OpenAiClient --> OpenAI["OpenAI API"]:::info
    StubProvider --> StubClient["Stub::Client"]:::neutral
    StubProvider --> StubConfig

    Runner --> IncrementalBaseResolver["IncrementalBaseResolver"]:::rounded
    IncrementalBaseResolver --> Git
    IncrementalBaseResolver --> GitHubClient["GitHubClient"]:::info

    GitHubReviewPublisher --> GitHubReviewBuilder["GitHubReviewBuilder"]:::rounded
    GitHubReviewPublisher --> GitHubClient
    GitHubClient --> GitHubAPI["GitHub API"]:::info

    classDef rounded fill:#F8F6F2,stroke:#AC9B98,stroke-width:2px,color:#47201C,rx:10,ry:10
    classDef positive fill:#E6F2C9,stroke:#51623A,stroke-width:2px,color:#28371A,rx:10,ry:10
    classDef info fill:#E8FAFF,stroke:#42657C,stroke-width:2px,color:#1A3348,rx:10,ry:10
    classDef accent fill:#FFE3D1,stroke:#905013,stroke-width:2px,color:#4F2600,rx:10,ry:10
    classDef neutral fill:#DAF0E5,stroke:#46635E,stroke-width:2px,color:#1D3733,rx:10,ry:10
```

All formats build a prompt from the run data and artifacts, then send it through the configured LLM provider. The selected format determines which prompt is loaded and therefore the output shape. The `publish-pr-review` subcommand uses `GitHubReviewPublisher` to post rendered reviews directly to GitHub pull requests.

On a pull request, `Runner` uses `IncrementalBaseResolver` to scope the diff to changes made since the last review. Both it and `GitHubReviewPublisher` talk to the GitHub API through the shared `GitHubClient`.
