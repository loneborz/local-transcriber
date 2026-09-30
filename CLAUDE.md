## LocalTranscriber Operating Contract

**Product boundary:** `media or URL -> local transcript package`. The timestamped local transcript is the core artifact. Do not introduce summarization, RAG, knowledge management, NotebookLM integration, automatic scientific fact correction, or silent transcript rewriting unless a future task explicitly authorizes it. Preserve the existing transcription engine unless the active task requires changing it.

**Scope**
- Work from the active Backlog task and its acceptance criteria.
- Prefer the smallest correct change; do not silently expand task scope.
- Do not automatically turn discovered improvements into new tasks; mention them in your report instead.

**Bounded retries**
- One initial attempt, inspect the failure, then at most one materially different retry.
- After two meaningful attempts at the same blocker, stop and report. Never repeatedly retry the same failing action.

**Stop rather than guess** when there is: ambiguity; an architecture or product decision; missing credentials or permissions; a destructive action; material scope expansion; conflicting repo/task authority; or two failed meaningful attempts.

**When stopping, report:** what was attempted; what happened; relevant evidence/errors; best current explanation; the smallest input or decision needed to continue.

**Native macOS verification:** LocalTranscriber is a native macOS app.
- When a task changes user-visible behavior, drag and drop, file handling, dialogs, queue state, preferences, app lifecycle, or other runtime behavior, use the macOS UI MCP when available to verify the result in the running application. Prefer observing the real app over inferring runtime behavior from source alone.
- Use build/test tooling for compile and test evidence, and macOS UI interaction for runtime acceptance evidence. Do not consider user-facing acceptance criteria verified solely because the project builds.
- The bounded retry rule applies to macOS UI interaction: one initial attempt, inspect what happened, then at most one materially different retry. If the same blocker remains, stop and report instead of repeatedly clicking or retrying.
- Do not use macOS UI interaction when it adds no meaningful verification value.

**Status honesty:** keep these distinct and state which applies: changed locally, verified locally, committed, pushed, human accepted.

**Done:** do not mark a Backlog task Done until its acceptance criteria are verified and the user has accepted the result.


<!-- BACKLOG.MD GUIDELINES START -->
<!-- backlog.md-instructions-version: 1.53.0 -->
<CRITICAL_INSTRUCTION>

## Backlog.md Workflow

This project uses Backlog.md for task and project management.

**At the beginning of each conversation in this project, run `backlog instructions overview` before answering or taking action. Re-read it only if you have not read it yet in the current conversation.**

Use the overview to decide whether to search, read, create, or update Backlog tasks.

Before task lifecycle actions, read the matching detailed guide:
- `backlog instructions task-creation` before creating or splitting tasks
- `backlog instructions task-execution` before planning, changing status or assignee, adding a plan or implementation notes, or implementing task work
- `backlog instructions task-finalization` before checking acceptance criteria, writing final summaries, or moving tasks to terminal statuses

Use `backlog <command> --help` before running unfamiliar commands. Help shows options, fields, and examples.

Do not edit Backlog task, draft, document, decision, or milestone markdown files directly. Use the `backlog` CLI so metadata, relationships, and history stay consistent.

</CRITICAL_INSTRUCTION>
<!-- BACKLOG.MD GUIDELINES END -->
