# GitHub Branch Rulesets

Version-controlled definitions of the branch protection rulesets applied to `dj-pearson/wellvo`. Use these JSON files as the source of truth — apply them with `scripts/apply-rulesets.sh` rather than editing in the GitHub UI.

## Why rulesets (not classic branch protection)

GitHub rulesets are the modern replacement for "classic" branch protection rules. They support:

- Pattern-based targets (`refs/heads/release/*`)
- Multiple bypass actors with explicit modes
- Versioning (each ruleset has an `id` and update history)
- A clean REST API: `POST /repos/{owner}/{repo}/rulesets`

We commit the JSON so the protection state is reproducible and reviewable.

## Branch → protections

| Ruleset                       | Targets                  | Deletion | Force-push | PR required          | Bypass             |
| ----------------------------- | ------------------------ | -------- | ---------- | -------------------- | ------------------ |
| `main-protection`             | `refs/heads/main`        | blocked  | blocked    | yes (0 approvals)    | Repo admin (always) |
| `develop-protection`          | `refs/heads/develop`     | blocked  | blocked    | yes (0 approvals)    | Repo admin (always) |
| `release-branches-protection` | `refs/heads/release/*`   | blocked  | blocked    | yes (0 approvals)    | Repo admin (always) |
| `hotfix-branches-protection`  | `refs/heads/hotfix/*`    | blocked  | blocked    | **no** (direct commits allowed on the hotfix branch itself; the gate is the PR `hotfix/* → main`, enforced by `main-protection`) | Repo admin (always) |

`required_approving_review_count: 0` is intentional for the current solo-developer setup — GitHub does not let the PR author approve their own PR, so requiring an approval would deadlock all merges. A PR is still required for `main`, `develop`, and `release/*`; the author just self-merges.

**When a second reviewer joins**, bump `required_approving_review_count` from `0` to `1` in `main.json` and `release.json` and re-apply. Leave `develop.json` at 0 if you want low-friction integration merges.

## Bypass actor

```json
{ "actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always" }
```

`actor_id: 5` is the well-known ID for the **Admin** repository role. `bypass_mode: "always"` means an admin (you) can override the ruleset without flipping it to "evaluate" mode first. This is the emergency-override escape hatch.

## Apply / re-apply

```bash
# requires gh CLI authenticated against the repo, or a GITHUB_TOKEN with `repo` and `administration` scopes
bash scripts/apply-rulesets.sh
```

The script does an idempotent **find by name → PUT if exists, POST if not** loop:

1. `GET /repos/{owner}/{repo}/rulesets` — list all rulesets
2. For each `.github/rulesets/*.json` (excluding `README.md`):
   - Match by `name` field in the JSON
   - If found: `PUT /repos/{owner}/{repo}/rulesets/{id}` with the JSON body
   - If not found: `POST /repos/{owner}/{repo}/rulesets` with the JSON body

This means you can re-run the script after any local edit and it will converge the remote state to match the JSON.

## Adding required status checks (later)

Required status check names that don't exist on a PR **block all merges**. Don't add them speculatively. The correct sequence:

1. Open a real PR that triggers the workflows. Note the exact "check run" names that appear in the merge box (e.g. `build-and-test`, `api-integration-tests`).
2. Add a `required_status_checks` rule to `main.json` (and optionally `release.json`):

   ```json
   {
     "type": "required_status_checks",
     "parameters": {
       "strict_required_status_checks_policy": false,
       "required_status_checks": [
         {
           "context": "build-and-test",
           "integration_id": 15368
         },
         {
           "context": "api-integration-tests",
           "integration_id": 15368
         }
       ]
     }
   }
   ```

   `integration_id: 15368` is the GitHub Actions app — without it, GitHub treats the check name as ambiguous (any app could post it).

3. Re-run `scripts/apply-rulesets.sh`.

If you ever rename a workflow's `job` key or its `name:`, the check context name changes and any required check pinned to the old name will block all merges until you update the ruleset.

## Editing tips

- Don't hand-edit in the GitHub UI — your change will be silently overwritten the next time someone runs the apply script. Edit the JSON, commit, re-apply.
- The `enforcement` field can be `"active"` (enforced) or `"evaluate"` (logged but not enforced — useful for testing a new rule).
- The `conditions.ref_name.include` field supports `refs/heads/foo`, `refs/heads/foo/*`, and the special `~DEFAULT_BRANCH` / `~ALL` tokens.
