# Firebase Migration Testing Plan

This document outlines the testing scenarios for verifying the Firebase/Firestore migration.

---

## Quick Reference Commands

```bash
# Terminal 1: Run server
cd /Users/leew/GitRepo/claude-ops && .build/debug/claude-ops-server

# Terminal 2: Run Flutter app
cd /Users/leew/GitRepo/ops-deck && flutter run

# Terminal 3: Monitor/test
curl http://localhost:5001/jobs | jq
```

---

## Test 1: Server Starts with Firestore

**Objective:** Verify the server initializes Firestore authentication correctly.

**Steps:**
```bash
cd /Users/leew/GitRepo/claude-ops
.build/debug/claude-ops-server
```

**Expected output:**
```
[Firestore] Initialized with project: agent-command-center-bf2b7
Server starting on http://0.0.0.0:5001
```

**Failure case (Firestore auth failed):**
```
[Firestore] Service account not found, using local storage fallback
```

**Pass criteria:**
- [ ] Server starts without errors
- [ ] Firestore initialization message shows correct project ID

---

## Test 2: Server API Endpoints

**Objective:** Verify all API endpoints respond correctly.

**Steps:**
```bash
# Health check
curl http://localhost:5001/
# Expected: "claude-ops server running"

# List jobs
curl http://localhost:5001/jobs
# Expected: JSON array (may be empty)

# List repos
curl http://localhost:5001/repos
# Expected: JSON array of configured repositories
```

**Pass criteria:**
- [ ] Health check returns 200
- [ ] Jobs endpoint returns valid JSON
- [ ] Repos endpoint returns configured repositories

---

## Test 3: Firestore Console Verification

**Objective:** Verify data is being written to Firestore.

**Steps:**
1. Open [Firebase Console → Firestore](https://console.firebase.google.com)
2. Select your project
3. Navigate to Firestore Database
4. Trigger a job (create an issue with `cmd:plan-headless` label)
5. Refresh Firestore console

**Expected:**
- `jobs` collection appears
- Document with job ID exists
- Fields include: `id`, `repo`, `status`, `start_time`, `command`, etc.

**Pass criteria:**
- [ ] Jobs collection exists in Firestore
- [ ] Job documents have correct field structure
- [ ] Status updates reflect in Firestore

---

## Test 4: Flutter App - Firestore Mode

**Objective:** Verify Flutter app uses real-time Firestore updates.

**Steps:**
```bash
cd /Users/leew/GitRepo/ops-deck
flutter run
```

**Expected debug console output:**
```
[JobProvider] Firestore available, using real-time updates
```

**Verification:**
1. App header shows "OPS DECK"
2. Jobs list populates automatically
3. No manual refresh needed when jobs change

**Pass criteria:**
- [ ] Debug console shows Firestore is available
- [ ] Jobs appear without manual refresh
- [ ] Job status changes update in real-time

---

## Test 5: Flutter App - HTTP Fallback Mode

**Objective:** Verify app gracefully falls back to HTTP polling.

**Steps:**
1. Temporarily rename `google-services.json`:
   ```bash
   cd /Users/leew/GitRepo/ops-deck/android/app
   mv google-services.json google-services.json.bak
   ```
2. Run the app:
   ```bash
   flutter run
   ```

**Expected debug console output:**
```
[JobProvider] Firestore not available, falling back to HTTP polling
```

**Verification:**
1. App still functions
2. Jobs update every 2 seconds (polling)
3. All features work (view jobs, approve, reject)

**Cleanup:**
```bash
mv google-services.json.bak google-services.json
```

**Pass criteria:**
- [ ] App detects Firestore unavailable
- [ ] Falls back to HTTP polling
- [ ] All functionality still works

---

## Test 6: End-to-End Job Flow

**Objective:** Verify complete job lifecycle with Firestore.

**Steps:**

1. **Create a test issue:**
   - Use the Flutter app "NEW ISSUE" button, OR
   - Create an issue manually in GitHub with label `cmd:plan-headless`

2. **Monitor job creation:**
   - Watch server logs for job trigger
   - Check Firestore console for new document
   - Verify Flutter app shows new job

3. **Track job progress:**
   - Job should progress: `pending` → `running` → `waiting_approval` or `completed`
   - Each status change should appear in:
     - Server logs
     - Firestore console
     - Flutter app (real-time)

**Pass criteria:**
- [ ] Job appears in server logs
- [ ] Job document created in Firestore
- [ ] Flutter app shows job in real-time
- [ ] Status updates propagate automatically
- [ ] No manual refresh required

---

## Test 7: Approve/Reject Flow

**Objective:** Verify approval actions work through HTTP → Firestore.

**Precondition:** Have a job in `waiting_approval` status.

**Steps:**

1. **Test Approve:**
   - In Flutter app, tap **APPROVE** button
   - Watch server logs for HTTP request
   - Verify Firestore document updates
   - Verify Flutter UI updates

2. **Test Reject:**
   - Trigger another job to `waiting_approval`
   - In Flutter app, tap **REJECT** button
   - Watch server logs
   - Verify status changes to `rejected`

**Pass criteria:**
- [ ] Approve button triggers HTTP POST to server
- [ ] Server updates Firestore
- [ ] Flutter app reflects new status
- [ ] Reject flow works similarly

---

## Test 8: Local Fallback Mode (Server)

**Objective:** Verify server works without Firestore.

**Steps:**
1. Temporarily rename service account:
   ```bash
   cd /Users/leew/GitRepo/claude-ops
   mv service-account.json service-account.json.bak
   ```
2. Start server:
   ```bash
   .build/debug/claude-ops-server
   ```

**Expected output:**
```
[Firestore] Service account not found, using local storage fallback
```

**Verification:**
- Server starts successfully
- Jobs are stored in `jobs.json` locally
- All API endpoints work

**Cleanup:**
```bash
mv service-account.json.bak service-account.json
```

**Pass criteria:**
- [ ] Server starts with fallback message
- [ ] Jobs stored in local `jobs.json`
- [ ] API endpoints functional

---

## Test 9: Cost Tracking Structure

**Objective:** Verify cost field structure is ready (costs won't populate until streaming is implemented).

**Steps:**
1. Open Firestore console
2. Examine a job document
3. Check for `cost` field

**Expected:**
- `cost` field exists (may be null/missing for now)
- When populated, structure should be:
  ```json
  {
    "cost": {
      "total_usd": 0.0,
      "input_tokens": 0,
      "output_tokens": 0,
      "cache_read_tokens": 0,
      "cache_creation_tokens": 0,
      "model": "unknown"
    }
  }
  ```

**Pass criteria:**
- [ ] Job model supports cost field
- [ ] Firestore document structure correct

---

## Test 10: Analytics Collection

**Objective:** Verify analytics aggregation structure.

**Note:** Analytics won't populate until cost tracking is implemented, but verify the path exists.

**Steps:**
1. Open Firestore console
2. Look for `analytics` collection
3. Path should be: `analytics/default/daily/{YYYY-MM-DD}`

**Pass criteria:**
- [ ] Analytics path structure is correct
- [ ] Ready for cost aggregation

---

## Test Summary Checklist

| Test | Description | Status |
|------|-------------|--------|
| 1 | Server starts with Firestore | ☐ |
| 2 | Server API endpoints work | ☐ |
| 3 | Data appears in Firestore console | ☐ |
| 4 | Flutter app uses Firestore real-time | ☐ |
| 5 | Flutter app HTTP fallback works | ☐ |
| 6 | End-to-end job flow | ☐ |
| 7 | Approve/reject actions | ☐ |
| 8 | Server local fallback mode | ☐ |
| 9 | Cost tracking structure | ☐ |
| 10 | Analytics collection structure | ☐ |

---

## Troubleshooting

### Server Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| `[Firestore] Service account not found` | Missing `service-account.json` | Add file to working directory |
| `GoogleAuthError.tokenExchangeFailed` | Invalid credentials | Regenerate service account key |
| `FirestoreError.requestFailed(403, ...)` | Missing IAM permissions | Add Cloud Datastore User role |
| `FirestoreError.requestFailed(404, ...)` | Firestore not enabled | Enable Firestore in Firebase console |

### Flutter App Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| Firestore not available message | Missing `google-services.json` | Add Firebase config file |
| Jobs don't update in real-time | Firestore rules blocking reads | Check security rules |
| "Server not configured" | No base URL set | Configure in Settings screen |
| Approve/reject fails | Server unreachable | Check server is running, URL correct |

### General Issues

| Symptom | Cause | Solution |
|---------|-------|----------|
| No jobs appearing | No jobs triggered | Create issue with `cmd:` label |
| Jobs stuck in pending | Claude CLI issue | Check `claude --version` works |
| Data not syncing | Network issue | Check firewall, connectivity |
