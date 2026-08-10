# Flock In — Setup Guide

Complete setup takes about 20–30 minutes.

---

## 1. Create a Firebase Project

1. Go to [console.firebase.google.com](https://console.firebase.google.com)
2. Click **Add project** → name it (e.g. `flock-in-asb`) → Continue
3. Disable Google Analytics (not needed) → **Create project**

---

## 2. Enable Firebase Services

### Firestore Database
1. Left sidebar → **Firestore Database** → **Create database**
2. Choose **Production mode** → select a region close to you → **Enable**
3. Go to the **Rules** tab → paste the contents of `firestore.rules` → **Publish**

### Authentication
1. Left sidebar → **Authentication** → **Get started**
2. **Sign-in method** tab → Enable **Google**
3. Set your **Project support email** → Save

### Cloud Messaging (FCM)
- FCM is enabled automatically — no action needed for the free tier.

---

## 3. Add the iOS App to Firebase

1. In Firebase Console → Project Overview → click **iOS+** icon
2. **iOS bundle ID**: `com.lukepopler.FlockIn`
3. **App nickname**: Flock In
4. Click **Register app**
5. **Download** `GoogleService-Info.plist`
6. In Xcode, **delete** `FlockIn/GoogleService-Info.plist` (the placeholder)
7. **Drag** the downloaded file into `FlockIn/` in Xcode → check *Copy items if needed*

---

## 4. Update the iOS App Config

### Set your school domain
Open `FlockIn/Services/AuthService.swift` and change line 8:
```swift
static let schoolDomain = "yourschool.org"  // ← change this
```

### Add the Google Sign-In URL scheme
1. Open `FlockIn/Info.plist` in Xcode
2. Find `CFBundleURLTypes` → the `REPLACE_WITH_REVERSED_CLIENT_ID` entry
3. Replace it with your `REVERSED_CLIENT_ID` from `GoogleService-Info.plist`
   (looks like: `com.googleusercontent.apps.123456789-abcde...`)

### Add Swift Packages in Xcode
1. Xcode menu → **File** → **Add Package Dependencies…**
2. Add **Firebase iOS SDK**:
   - URL: `https://github.com/firebase/firebase-ios-sdk`
   - Version: Up to Next Major from `10.0.0`
   - Add products: **FirebaseAuth**, **FirebaseFirestore**, **FirebaseMessaging**
3. Add **Google Sign-In**:
   - URL: `https://github.com/google/GoogleSignIn-iOS`
   - Version: Up to Next Major from `7.0.0`
   - Add product: **GoogleSignIn**

### Enable Push Notifications in Xcode
1. Select the **FlockIn** target → **Signing & Capabilities** tab
2. Click **+ Capability** → add **Push Notifications**
3. Click **+ Capability** → add **Background Modes** → check **Remote notifications**

### Upload your APNs key to Firebase
1. Apple Developer Portal → **Certificates, Identifiers & Profiles** → **Keys** → **+**
2. Name it, check **Apple Push Notifications service (APNs)** → Continue → Register
3. Download the `.p8` key file — **save it, you can only download once**
4. Firebase Console → Project Settings → **Cloud Messaging** tab
5. Under **Apple app configuration** → upload the `.p8` file + enter your Key ID and Team ID

---

## 5. Set Up the Admin Dashboard

### Install dependencies
```bash
cd "admin-dashboard"
npm install
```

### Configure environment variables
```bash
cp .env.local.example .env.local
```
Edit `.env.local`:

```
NEXT_PUBLIC_FIREBASE_API_KEY=         # Firebase Console → Project Settings → General → Your apps
NEXT_PUBLIC_FIREBASE_AUTH_DOMAIN=
NEXT_PUBLIC_FIREBASE_PROJECT_ID=
NEXT_PUBLIC_FIREBASE_STORAGE_BUCKET=
NEXT_PUBLIC_FIREBASE_MESSAGING_SENDER_ID=
NEXT_PUBLIC_FIREBASE_APP_ID=

FIREBASE_ADMIN_SERVICE_ACCOUNT=       # See below
```

### Get the Admin Service Account (for push notifications)
1. Firebase Console → Project Settings → **Service accounts** tab
2. Click **Generate new private key** → Download JSON
3. Open the JSON file, copy the entire contents
4. Minify it (paste into [jsonminifier.org](https://www.jsonminifier.org)) and paste as the value for `FIREBASE_ADMIN_SERVICE_ACCOUNT`

### Run the dashboard locally
```bash
npm run dev
# Open http://localhost:3000
```

### Deploy to Vercel (free)
```bash
npm install -g vercel
vercel
```
Add the same environment variables in Vercel's dashboard under **Settings → Environment Variables**.

### Point the iOS app at the deployed API

The app does not write sign-ups to Firestore directly — it calls `POST /api/signup`, which is the only place an event's spot limit can be enforced. After deploying, open `FlockIn/Services/FirestoreService.swift` and set your URL:

```swift
enum AppConfig {
    static let apiBaseURL = URL(string: "https://your-project.vercel.app")!
}
```

Sign-ups fail until this points at the deployed dashboard.

### Test the security rules

The Firestore rules are what stop a student from awarding themselves volunteer hours, so they have a test suite. Run it before publishing any change to `firestore.rules`:

```bash
cd admin-dashboard
npm run test:rules      # needs Java for the Firestore emulator
```

---

## 6. Add the First Admin

After deploying the dashboard, you need to manually add yourself as the first admin:

1. Firebase Console → **Firestore Database**
2. **Start collection** → Collection ID: `admins`
3. **Document ID**: your Firebase Auth UID (find it in **Authentication** → your email)
4. Add fields: `email` (string), `name` (string)
5. Now sign in to the dashboard at your deployed URL

---

## 7. Add Students (Whitelist)

**Option A — Dashboard (easiest)**
1. Sign in to the admin dashboard
2. Go to **Students** → **Add Student**
3. Enter the student's school Google email and name
4. They can now sign in to the iOS app

**Option B — Bulk import via Firestore**
For each student, create a document in `/students/` with:
- **Document ID**: sanitized email (replace `.` with `_`, replace `@` with `_at_`)
  - Example: `jsmith_at_sequoiahs_org`
- Fields: `email`, `displayName`, `isWhitelisted: true`

---

## 8. Coordinates for Events

When creating events in the dashboard, use real GPS coordinates for your school locations.

Find coordinates:
1. Open Google Maps → right-click on the location → copy the lat/long
2. Example: New Gym → `37.4848, -122.2351`

Update the placeholder events in `EventStore.swift` OR delete them and create real ones through the dashboard.

---

## Architecture Summary

```
Firebase (Backend)
  ├── Firestore:    events, students, signups, checkins, admins
  ├── Auth:         Google Sign-In for both students and admins
  └── FCM:          Push notifications to iOS devices

iOS App (Swift/SwiftUI)
  ├── Google Sign-In → domain check → whitelist check → Firebase Auth
  ├── Live Firestore listeners for events and signups
  └── GPS check (200m) + isActive flag before check-in

Admin Dashboard (Next.js → Vercel)
  ├── Google Sign-In → admins collection check
  ├── Create/edit/delete events + toggle active
  ├── Manage student whitelist
  ├── View hours and check-ins
  └── Send FCM push to all registered devices
```
