# Cleo Quality Review - Comment Analysis

Automated tally of inline pull-request review comments posted by the Cleo code quality reviewer.
Comments are identified as Cleo's by author `github-actions[bot]` plus the `_(Ref: <tool> <rule>)_` footer the reviewer appends to every finding.

- **Scope:** PRs authored by the 13 members of the `ai-review` GitHub team, created in the last 3 months (since 2026-04-28).
- **Excluded:** Codex reviews (`chatgpt-codex-connector[bot]`) and all human comments, per request.
- **Active repos** (the only repos where the reviewer currently runs): `meetcleo/cleo_quality_review`, `meetcleo/meetcleo`.
- **Counting:** "incidents" = one per (tool, rule) reference. A single comment can cite several rules and therefore contribute to several rows.
- **Flog note:** Flog has no named rules (it only flags over-threshold method/class complexity), so all Flog findings collapse into one "high-complexity method" bucket.

## Totals

| Metric | Count |
| --- | --- |
| Cleo review comments | 1318 |
| Tool/rule incidents (a comment may cite several) | 1830 |
| Distinct tool/rule pairs | 35 |
| Comments in `meetcleo/cleo_quality_review` (across 12 PRs) | 106 |
| Comments in `meetcleo/meetcleo` (across 183 PRs) | 1212 |

## Count per tool

| Tool | Incidents |
| --- | --- |
| Reek | 1485 |
| Flog | 328 |
| Fasterer | 16 |
| Debride | 1 |

## Count per tool / rule

| Tool / Rule | Incidents |
| --- | --- |
| Reek/TooManyStatements | 494 |
| Reek/DuplicateMethodCall | 360 |
| Flog/high-complexity method | 328 |
| Reek/FeatureEnvy | 176 |
| Reek/LongParameterList | 120 |
| Reek/TooManyInstanceVariables | 54 |
| Reek/NestedIterators | 39 |
| Reek/TooManyMethods | 33 |
| Reek/UncommunicativeVariableName | 25 |
| Reek/BooleanParameter | 24 |
| Reek/RepeatedConditional | 21 |
| Reek/UtilityFunction | 21 |
| Reek/ControlParameter | 17 |
| Reek/InstanceVariableAssumption | 17 |
| Reek/DataClump | 15 |
| Reek/UnusedParameters | 15 |
| Reek/MissingSafeMethod | 14 |
| Reek/Attribute | 13 |
| Reek/TooManyConstants | 10 |
| Reek/NilCheck | 8 |
| Fasterer/HashFetchWithDefaultArgument | 4 |
| Fasterer/HashFetchWithArgument | 3 |
| Reek/ManualDispatch | 3 |
| Fasterer/HashFetchWithSecondArgument | 2 |
| Fasterer/HashKeysEach | 2 |
| Reek/ClassVariable | 2 |
| Reek/UncommunicativeParameterName | 2 |
| Debride/dead_code | 1 |
| Fasterer/EachWithIndex | 1 |
| Fasterer/FetchWithArgument | 1 |
| Fasterer/FetchWithArgumentVsBlock | 1 |
| Fasterer/RescueVsRespondTo | 1 |
| Fasterer/parse error | 1 |
| Reek/IrresponsibleModule | 1 |
| Reek/UncommunicativeMethodName | 1 |

## Unparsed / free-form footers

5 incident(s) across 5 footer variant(s) did not match a recognised `<tool> <RuleName>` shape (usually the model wrote the reference in prose). Listed here so nothing is silently dropped; they are excluded from the counts above.

| Footer text | Count |
| --- | --- |
| `High complexity, TooManyStatements, FeatureEnvy` | 1 |
| `hash fetch default argument` | 1 |
| `high method complexity` | 1 |
| `nested iterators` | 1 |
| `too many statements` | 1 |

