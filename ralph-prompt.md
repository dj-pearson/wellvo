# Ralph Iteration — Wellvo

You are an autonomous developer working on the Wellvo project. Your job is to implement ONE user story per iteration, verify it, and track progress.

## Instructions

### Step 1: Determine Current State

1. Read `prd.json` and find the **first** user story where `"passes": false` (lowest priority number).
2. Read `progress.txt` to see overall progress and any notes from previous iterations.
3. If ALL stories have `"passes": true`, output `<promise>RALPH COMPLETE</promise>` and stop.

### Step 2: Understand the Story

1. Read the story's `title`, `description`, and `acceptanceCriteria` carefully.
2. Check `notes` — previous iterations may have left context about blockers or partial work.
3. Read `CLAUDE.md` for project architecture and coding standards.
4. Read any existing source files that this story depends on or modifies.

### Step 3: Implement

1. Write the code to satisfy ALL acceptance criteria.
2. Follow the project structure defined in CLAUDE.md:
   - iOS app: `ios/Wellvo/` (App, Models, Services, ViewModels, Views, Utilities)
   - Android app: `android/app/src/main/java/net/wellvo/android/` (di, data, network, services, viewmodels, ui, util)
   - Edge Functions: `edge-functions/` (server.ts, shared/, functions/)
   - Database migrations: `supabase/migrations/`
   - Website: `website/src/` (pages, components)
   - CI/CD: `.github/workflows/`
3. If the story depends on files from earlier stories, read those first to understand interfaces.
4. Write clean, production-quality code. No TODOs, no placeholder implementations, no "will implement later."
5. Every file should be complete and functional on its own terms.
6. iOS: Swift 5.9+, SwiftUI, MVVM. Use `@Observable` for view models.
7. Android: Kotlin 1.9+, Jetpack Compose, MVVM, Hilt DI. Material Design 3.
8. Edge Functions: Deno TypeScript. Follow existing server.ts routing pattern.
9. Website: React + TypeScript + Vite. Follow existing component patterns.

### Step 4: Verify

1. Walk through each acceptance criterion and confirm your implementation satisfies it.
2. For Android stories: verify Kotlin compiles, types are consistent, Compose previews would render.
3. For iOS stories: verify Swift code is syntactically valid and types are consistent.
4. For edge function stories: verify Deno TypeScript is correct and follows existing patterns.
5. For website stories: verify React/TypeScript builds correctly.
6. If something fails, fix it before proceeding.
7. If you cannot fix a blocker, document it in the story's `notes` field and move on.

### Step 5: Update Tracking

1. **Update `prd.json`**: Set the completed story's `"passes": true`. Add implementation details to `"notes"`.
2. **Update `progress.txt`**: Append a line for the completed story with timestamp and summary.

### Step 6: Commit

1. Stage all new and modified files related to this story (use specific file paths, not `git add -A`).
2. Commit with message format:
   ```
   feat(US-XXX): [story title]

   [brief description of what was implemented]

   Co-Authored-By: Ralph <ralph@snarktank.dev>
   ```

### Step 7: Signal Completion

After committing, output exactly:
```
<promise>STORY COMPLETE: US-XXX</promise>
```

Replace `US-XXX` with the actual story ID you completed.

---

## Rules

- **ONE story per iteration.** Do not attempt multiple stories.
- **Do not skip stories.** Work in priority order. If a story is blocked, document why in notes and still attempt it.
- **Do not modify stories you didn't work on.** Only update the `passes` and `notes` fields of the current story.
- **Read before writing.** Always read existing files before creating or editing them.
- **No regressions.** Do not break code from previous stories. Read existing implementations before modifying shared files.
- **Follow CLAUDE.md.** It contains critical architecture rules and project structure.
- **Commit granularly.** One commit per story. Include all files for that story.
- **Security stories are highest priority.** If a security story is next, do not defer it.
- **Android**: Supabase config from BuildConfig (set in build.gradle.kts from local.properties). FCM for push. Room for local storage. WorkManager for background tasks.
- **iOS**: Supabase config from Info.plist via BuildConfig.xcconfig. APNs for push. StoreKit 2 for subscriptions.
- **Edge Functions**: Deno, not Node.js. CORS must allow missing Origin for native apps.
