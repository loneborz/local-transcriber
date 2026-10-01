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

**Engineering reference:** architecture, data flow, the YouTube helper's sandbox/signing model and the persistent state are in the Backlog document `doc-1` (`backlog doc view doc-1`). Read it before changing queue, output or helper code. Do not duplicate it here.

**Build and run**
- Build: `xcodebuild -project LocalTranscriber.xcodeproj -scheme LocalTranscriber -destination 'platform=macOS' build`. For a Release check add `-configuration Release -derivedDataPath <scratch dir>`. There are no automated tests; behavior is verified by running the real app.
- Find the product with `xcodebuild … -showBuildSettings | awk -F' = ' '/ BUILT_PRODUCTS_DIR/{print $2}'`. DerivedData is per checkout path, so a git worktree builds its own separate copy.
- Launch exactly the build you made: `pkill -x LocalTranscriber`, then `open "<BUILT_PRODUCTS_DIR>/LocalTranscriber.app"` by full path, then confirm with `ps -o command= -p "$(pgrep -x LocalTranscriber)"` that the running path is the one you built. Do not open the app by name: other copies (other DerivedData folders, scratch builds) may be registered with Launch Services and open instead. Every build shares one bundle id, so preferences, the output-folder bookmark and the sandbox container are shared too.
- Before `git checkout main`, run `git worktree list`: `main` may be checked out in another worktree.

**Runtime verification (reusable lessons)**
- Get the app's pid with `pgrep -x LocalTranscriber`. Prefer element-based clicks (text and role) over coordinates; a row scrolled outside the window cannot be clicked by coordinates.
- Queue input with the clipboard and Cmd-V: `printf '<url>' | pbcopy` (several lines queue several links) or `osascript -e 'set the clipboard to (POSIX file "<path>")'` for a file.
- Synthetic mouse drags only work if the pointer presses and holds (about 0.7 s) before moving, and the source and target are on the same display. A browser address-bar URL must be selected first, then dragged.
- Do not script other apps (AppleScript to Chrome raises a macOS Automation prompt). Never click such a prompt on the user's behalf.
- Test runs write real files into the user's configured output folder. Snapshot the folder with `ls` first, afterwards delete only what the test created, and restore anything you changed (output folder, language, the source-package checkbox). Preference changes show up in `~/Library/Containers/nl.wavesweb.LocalTranscriber/Data/Library/Preferences/` a moment later, so re-read before concluding a toggle failed.
- YouTube runs need the network. Check helper cleanup in `~/Library/Containers/nl.wavesweb.LocalTranscriber/Data/tmp/LocalTranscriber-acquisition` and with `ps -axo pid,ppid,command | grep python3.13`.

**Repository conventions that are easy to break**
- Do not put YouTube logic in `TranscriptionService.swift`; do not combine `.withoutOverwriting` with `.atomic` in `Data.write`.
- Files under `LocalTranscriber/` join the app automatically. Vendored helper files live in `Vendor/YouTubeHelper/` and are installed only by the "Embed YouTube helper" build phase in `project.pbxproj`. Xcode may reformat that hand-written entry when building; revert such noise instead of committing it.
- Helper rules: the only Mach-O is `Contents/Helpers/python3.13`, signed with `app-sandbox` + `inherit` only. Never add `network.client` or other entitlements to it, and keep Python data in `Resources`.
- Run the vendored Python with `PYTHONDONTWRITEBYTECODE=1`, or it litters `Vendor/` with `__pycache__`.

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
