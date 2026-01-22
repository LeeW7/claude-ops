# Firebase Migration Setup Guide

This guide covers setting up the Firebase/Firestore integration for claude-ops and ops-deck.

---

## Prerequisites

- Firebase project created (e.g., `agent-command-center-bf2b7`)
- Service account JSON file with Firestore access
- Swift toolchain installed (5.9+)
- Flutter SDK installed (3.x)

---

## Step 1: Firebase Project Configuration

### Enable Firestore Database

1. Go to [Firebase Console](https://console.firebase.google.com)
2. Select your project
3. Navigate to **Build → Firestore Database**
4. Click **Create database** if not already created
5. Choose **Start in test mode** (for development)
6. Select a region close to you

### Verify Service Account

Your `service-account.json` in `/Users/leew/GitRepo/claude-ops/` should contain:

```json
{
  "type": "service_account",
  "project_id": "agent-command-center-bf2b7",
  "private_key_id": "...",
  "private_key": "-----BEGIN PRIVATE KEY-----\n...",
  "client_email": "firebase-adminsdk-xxxxx@agent-command-center-bf2b7.iam.gserviceaccount.com",
  "client_id": "...",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token"
}
```

The service account needs these IAM roles:
- **Cloud Datastore User** (for Firestore access)
- **Firebase Admin SDK Administrator Service Agent** (if using other Firebase features)

---

## Step 2: Build the Swift Server

```bash
cd /Users/leew/GitRepo/claude-ops
git checkout feature/firebase-migration
swift build
```

Expected output:
```
Building for debugging...
Build complete!
```

---

## Step 3: Prepare the Flutter App

```bash
cd /Users/leew/GitRepo/ops-deck
git checkout feature/firebase-migration
flutter pub get
```

### Flutter Firebase Configuration

Ensure these files exist:
- `android/app/google-services.json` - Android Firebase config
- `ios/Runner/GoogleService-Info.plist` - iOS Firebase config (if testing on iOS)

---

## Step 4: Firestore Security Rules

For development/testing, use permissive rules:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    match /{document=**} {
      allow read, write: if true;
    }
  }
}
```

For production, use more restrictive rules:

```javascript
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    // Jobs collection - server can read/write, clients can read
    match /jobs/{jobId} {
      allow read: if true;
      allow write: if false; // Only server writes via service account
    }

    // Analytics collection
    match /analytics/{userId}/daily/{date} {
      allow read: if true;
      allow write: if false;
    }

    match /analytics/{userId}/monthly/{month} {
      allow read: if true;
      allow write: if false;
    }
  }
}
```

---

## Step 5: Environment Configuration

### Server Configuration

The server automatically looks for `service-account.json` in the current working directory. If not found, it falls back to local JSON file storage.

### Flutter App Configuration

The app needs the server URL configured in Settings. Default: `http://localhost:5001`

For Firestore to work in the Flutter app:
1. Firebase must be initialized (happens automatically via `firebase_core`)
2. `google-services.json` must be present and valid
3. The app checks Firestore availability on startup

---

## Firestore Data Structure

```
firestore/
├── jobs/
│   └── {jobId}/
│       ├── id: string
│       ├── repo: string
│       ├── repo_slug: string
│       ├── issue_num: number
│       ├── issue_title: string
│       ├── command: string
│       ├── status: string
│       ├── start_time: number
│       ├── completed_time: number (optional)
│       ├── log_path: string
│       ├── local_path: string
│       ├── full_command: string
│       ├── error: string (optional)
│       ├── cost: map (optional)
│       │   ├── total_usd: number
│       │   ├── input_tokens: number
│       │   ├── output_tokens: number
│       │   ├── cache_read_tokens: number
│       │   ├── cache_creation_tokens: number
│       │   └── model: string
│       ├── created_at: timestamp
│       └── updated_at: timestamp
│
└── analytics/
    └── default/
        └── daily/
            └── {YYYY-MM-DD}/
                ├── date: string
                ├── total_cost: number
                ├── job_count: number
                ├── input_tokens: number
                ├── output_tokens: number
                ├── cache_read_tokens: number
                └── cache_creation_tokens: number
```

---

## Troubleshooting

### Server Issues

| Issue | Solution |
|-------|----------|
| `[Firestore] Service account not found` | Verify `service-account.json` exists in the working directory |
| `GoogleAuthError.tokenExchangeFailed` | Check service account has Firestore IAM permissions |
| `FirestoreError.requestFailed(403, ...)` | Service account lacks Cloud Datastore User role |

### Flutter App Issues

| Issue | Solution |
|-------|----------|
| `[JobProvider] Firestore not available` | Check `google-services.json` exists and is valid |
| Firebase initialization failed | Verify Firebase project ID matches in all config files |
| Jobs don't sync in real-time | Check Firestore rules allow reads |

---

## Architecture Overview

```
┌─────────────────┐              ┌─────────────────┐
│   ops-deck      │              │   claude-ops    │
│   (Flutter)     │              │   (Swift)       │
└────────┬────────┘              └────────┬────────┘
         │                                │
         │ Real-time        REST API      │ Writes jobs,
         │ Firestore        (JWT auth)    │ analytics
         │ listeners                      │
         │                                │
         └───────────┬────────────────────┘
                     │
             ┌───────▼───────┐
             │   Firestore   │
             │               │
             │ • jobs        │
             │ • analytics   │
             └───────────────┘
```

The Flutter app reads from Firestore directly (real-time listeners), while the Swift server writes to Firestore via REST API with service account authentication.

HTTP API is still used for:
- Approve/reject actions (client → server → Firestore)
- Creating issues
- Fetching logs (stored locally on server)
