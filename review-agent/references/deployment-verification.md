# Deployment Verification — Post-Merge Monitoring

After merging a PR, verify the deployment succeeded before marking the issue
as Done. Read during Phase 7d.

## Config-Driven Verification

If `.kanban-config.json` has a `pipeline.cd` section with `enabled: true`, use
it instead of the manual detection below. The config provides:
- `verify_command`: Shell command that outputs the deployment status
- `success_value`: String that means "deployed successfully"
- `pending_values`: Strings that mean "still deploying"
- `timeout_minutes`: Maximum time to poll before treating as failure

Run the `verify_command`, compare output to the values, and poll with 30s
intervals up to the timeout. This is the preferred path — it works across
Cloud Build, GitHub Actions, Vercel, Netlify, and any other provider.

## When to Run (Manual Detection)

If no `pipeline.cd` config exists, fall back to manual detection.

**Run this phase** when the project deploys automatically on merge (CI/CD to
Cloud Run, GKE, App Engine, Firebase, etc.). Check CLAUDE.md for deployment
configuration — look for:

- CI/CD workflows (`.github/workflows/`) with deploy steps
- `deploy.sh` or `Makefile` deploy targets
- Cloud Run service names, GCP project IDs, regions
- Firebase hosting or Firestore rules deployment

**Skip this phase** when:
- The project has no automated deployment (manual deploys only)
- The PR is documentation-only or config-only with no deploy trigger
- CLAUDE.md explicitly says deployments are manual

## Step 1: Identify Deployment Target

From CLAUDE.md and CI/CD workflows, determine:

```
SERVICE_NAME=<cloud-run-service-or-equivalent>
PROJECT_ID=<gcp-project-id>
REGION=<gcp-region>
```

If these aren't documented, check:
```bash
# Cloud Run
gcloud run services list --project "$PROJECT_ID" --format="table(name,region)"

# App Engine
gcloud app describe --project "$PROJECT_ID"

# GKE
gcloud container clusters list --project "$PROJECT_ID"
```

## Step 2: Wait for CI/CD Pipeline

The merge triggers a deployment pipeline. Watch it:

```bash
# Get the latest workflow run triggered by the merge commit
gh run list --branch main --limit 1 --json databaseId,status,conclusion,name

# Watch it
gh run watch <RUN_ID>
```

If the CI pipeline itself fails (build, test, or deploy step), skip to
**Deployment Failure Handling** below.

## Step 3: Verify Deployment with Backoff

Deployments take time — Cloud Run revisions, container builds, rollouts.
Poll with exponential backoff:

```
Attempt 1: wait 30s  → check
Attempt 2: wait 60s  → check
Attempt 3: wait 120s → check
Attempt 4: wait 240s → check (max wait)
Attempt 5+: wait 240s → check
```

**Max total wait: 15 minutes.** If deployment hasn't succeeded by then,
escalate to human review.

### Check methods (use all that apply):

**Cloud Build status (check first):**
```bash
COMMIT_SHA=$(git rev-parse HEAD)  # the merge commit

BUILD_STATUS=$(gcloud builds list \
  --project="$PROJECT_ID" \
  --region=global \
  --filter="substitutions.COMMIT_SHA=$COMMIT_SHA" \
  --sort-by="~createTime" \
  --limit=1 \
  --format='value(status)')
```

Look for: `SUCCESS`. Pending values: `WORKING`, `QUEUED`, `PENDING`.

The `--filter` scopes the query to the build triggered by this specific
merge commit. Without it, `--limit=1` returns the most recent build
globally, which may be from an unrelated trigger — producing false
positives or false negatives. For multi-trigger projects, add
`AND buildTriggerId=$TRIGGER_ID` (store the trigger UUID in
`.kanban-config.json` under `pipeline.cd`).

**Important — do not use `status.conditions[0].status` (service Ready
condition) as a deployment check.** This field reflects whether *any*
healthy revision is currently serving traffic, not whether the *new*
revision deployed successfully. If Cloud Run rolls back to a previous
revision after a failed deploy, the service stays `Ready: True` even
though your code never went live.

`gcloud run services describe` is fine for other purposes — use it
freely to retrieve `status.url`, `status.latestReadyRevisionName`,
traffic splits, or any other service metadata. Only avoid treating the
Ready condition as a deployment-success signal.

**Cloud Run new revision (after build succeeds):**
```bash
# Normalize merge commit timestamp to UTC (required — offset format silently fails)
MERGE_TS_RAW=$(git log -1 --format="%cI" "$COMMIT_SHA")
MERGE_TS_UTC=$(date -u -d "$MERGE_TS_RAW" +"%Y-%m-%dT%H:%M:%SZ")

# Find revisions created after the merge
gcloud run revisions list \
  --service="$SERVICE_NAME" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --filter="metadata.creationTimestamp>$MERGE_TS_UTC" \
  --sort-by="~metadata.creationTimestamp" \
  --format="value(metadata.name,metadata.creationTimestamp)"
```

Look for: at least one revision in the output. A pre-existing revision
showing `True` does not confirm the new deployment.

**Do NOT combine `--limit` with `--filter`** for Cloud Run revision
checks. `--limit` is applied server-side *before* the client-side
`--filter`, so it can silently exclude the revision you're looking for.

**Cloud Run service logs (last 5 minutes):**
```bash
gcloud run services logs read "$SERVICE_NAME" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --limit=100
```

Look for: startup logs, no crash loops, no repeated error patterns.

**Cloud Logging (structured query):**
```bash
gcloud logging read \
  'resource.type="cloud_run_revision"
   resource.labels.service_name="'"$SERVICE_NAME"'"
   severity>=ERROR
   timestamp>="'"$(date -u -d '5 minutes ago' '+%Y-%m-%dT%H:%M:%SZ')"'"' \
  --project="$PROJECT_ID" \
  --limit=20 \
  --format="table(timestamp,severity,textPayload)"
```

Look for: no ERROR/CRITICAL entries in the window after deployment.

**Health check (if endpoint exists):**
```bash
SERVICE_URL=$(gcloud run services describe "$SERVICE_NAME" \
  --project="$PROJECT_ID" \
  --region="$REGION" \
  --format="value(status.url)")

curl -s -o /dev/null -w "%{http_code}" "$SERVICE_URL/health"
```

Look for: 200 response.

## Step 4: Confirm Success

Deployment is confirmed successful when **all** of the following are true:

- [ ] Build/pipeline completed with success status
- [ ] A *new* revision is active and Ready — created after the merge
      (or equivalent for the platform)
- [ ] No ERROR/CRITICAL log entries in the post-deployment window
- [ ] Health check returns 200 (if applicable)

When confirmed, proceed to move the issue to `stage:done` and report
success in the Phase 9 summary.

## Deployment Failure Handling

When deployment fails, diagnose the failure and decide how to proceed.

### Diagnosis

1. **Get the failure details:**
   ```bash
   # CI/CD failure
   gh run view <RUN_ID> --log-failed

   # Cloud Run crash
   gcloud run services logs read "$SERVICE_NAME" \
     --project="$PROJECT_ID" \
     --region="$REGION" \
     --limit=200

   # Cloud Logging for structured errors
   gcloud logging read \
     'resource.type="cloud_run_revision"
      resource.labels.service_name="'"$SERVICE_NAME"'"
      severity>=ERROR' \
     --project="$PROJECT_ID" \
     --limit=50 \
     --format=json
   ```

2. **Categorize the failure:**

| Failure Type | Examples | Action |
|-------------|----------|--------|
| **Build failure** | Syntax error, missing dependency, Docker build error | Agent can likely fix |
| **Test failure in CI** | Flaky test, new test regression | Agent can likely fix |
| **Startup crash** | Import error, missing env var, port binding failure | Agent may fix (config) or escalate (secrets) |
| **Runtime error** | New endpoint 500s, database migration failed | Escalate — needs investigation |
| **Infrastructure** | Quota exceeded, permission denied, network timeout | Escalate — needs human/ops action |
| **Rollback occurred** | Platform auto-rolled back to previous revision | Escalate — previous revision is serving |

### Decision Framework

```
Failure diagnosed?
├─ Build/test failure with clear fix
│  └─ Can agent fix it? (1-2 line, no new tests needed)
│     ├─ Yes → Fix in worktree, push, re-monitor deployment
│     └─ No → REQUEST CHANGES on the issue with failure details
│
├─ Config/env issue
│  ├─ Missing env var or secret → ESCALATE (agent can't set secrets)
│  └─ Wrong config value in code → Fix if trivial, else REQUEST CHANGES
│
├─ Infrastructure/permissions
│  └─ ESCALATE — agent cannot fix quota, IAM, or network issues
│
├─ Runtime regression (new code causes 500s)
│  └─ ESCALATE — needs investigation, possible rollback decision
│
└─ Unknown / unclear failure
   └─ ESCALATE — include all diagnostic output for human
```

### When the agent fixes a deployment failure

1. Create a worktree for the hotfix:
   ```bash
   WORKTREE=$(bash .agents/skills/dev-agent/scripts/enter-worktree.sh "fix+<ISSUE>-deploy-fix")
   cd "$WORKTREE"
   git fetch origin main && git reset --hard origin/main
   ```
2. Make the fix, commit with `fix(<scope>): <description>`
3. Push directly to `main` (this is a hotfix for a broken deploy)
4. Return to Step 2 (wait for CI/CD pipeline) and re-verify
5. Clean up the worktree

**Only fix if you are certain.** If in doubt, escalate immediately.
A failed deploy with the old revision serving is better than a second
broken deploy.

### When escalating a deployment failure

1. **Do NOT move the issue to `stage:done`** — it stays in `stage:in-review`
2. Move to `stage:human-review` (post-review) via `/github-kanban`
3. Comment on the issue with:
   - Failure type and category
   - Full error output (truncated to relevant sections)
   - What you investigated and ruled out
   - Recommended next steps for the human
4. Comment on the merged PR with a summary linking to the issue comment

### When requesting changes for a deployment failure

This is unusual — the PR is already merged. Instead:

1. Create a **new issue** via `/github-kanban` with:
   - Title: `fix(<scope>): deployment failure from #<ORIGINAL_ISSUE>`
   - Body: failure details, root cause, suggested fix
   - Labels: `bug`, `priority:p0`, `stage:ready`
2. Move the original issue to `stage:done` (the code is merged, the fix
   is a new issue)
3. Note the new issue in the Phase 9 report

## Platform-Specific Notes

### Cloud Run
- New revisions take 30-90s to become active
- Watch for "Container failed to start" in logs — usually missing env var
  or wrong entrypoint
- Check Cloud Build status first (filter by `substitutions.COMMIT_SHA`),
  then confirm a new revision exists with `metadata.creationTimestamp`
  after the merge commit

### Firebase Hosting
- Deploys are fast (~10s) but may cache old content
- Check `firebase hosting:channel:list` for preview channels
- Verify with `curl` against the hosting URL

### GKE
- Rollouts can take several minutes depending on pod count
- Check `kubectl rollout status deployment/<name>`
- Watch for `CrashLoopBackOff` in pod status

### App Engine
- Version promotion can take 1-2 minutes
- Check `gcloud app versions list` for traffic split
- Watch for startup errors in `gcloud app logs tail`
