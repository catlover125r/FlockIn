# Flock In — Project Summary

## Overview

Flock In is a school ASB (Associated Student Body) event management and volunteer hour tracking system. It digitizes the process of signing students up for school events and verifying their attendance using GPS proximity check-in — eliminating paper sign-in sheets and manual hour tracking.

The project consists of two parts: a native iOS app for students and a web-based admin dashboard for ASB staff.

---

## What It Does

**For Students (iOS App):**
- Browse and sign up for upcoming ASB events via a weekly calendar view
- Check in to events using GPS geofencing — the check-in button only activates when the event is live and the student is within 200 meters of the event location
- View personal volunteer hours earned across all attended events
- Receive push notifications when events go active

**For Admins (Web Dashboard):**
- Create, edit, and manage events (title, description, date/time, location, GPS coordinates, hours value, spot limit)
- Toggle events active/inactive, with automatic activation at the scheduled time
- Send push notifications to all registered students
- Manage a student whitelist with bulk CSV import for start-of-year setup
- View attendance records, check-in history, and each student's total accumulated hours
- Dashboard overview with key stats (whitelisted students, events, active events, today's check-ins)

---

## Tech Stack

| Layer | Technology |
|---|---|
| iOS App | Swift, SwiftUI, Firebase SDK, Google Sign-In, Core Location, MapKit |
| Admin Dashboard | Next.js 14, TypeScript, Tailwind CSS, Firebase JS SDK |
| Database | Firebase Firestore (NoSQL) |
| Auth | Firebase Authentication (Google Sign-In) |
| Push Notifications | Firebase Cloud Messaging (FCM) |
| Hosting | Vercel (admin dashboard) |

---

## Architecture Highlights

**GPS Check-In**
The check-in button unlocks only when the admin has activated the event and the student is within 200 meters of its coordinates — no QR codes, no manual check-in from an admin.

Note what each half actually guarantees. Event activation is enforced in Firestore rules, as is the number of hours a check-in is worth and the rule that one sign-up yields at most one check-in. The 200m radius is **not** enforceable: location is only ever asserted by the device, so any server-side check would amount to trusting a number the client chose. Treat the geofence as a convenience that keeps honest students from checking in early, not as an anti-fraud control.

**Data Denormalization**
Event data (title, date, location, hours) is copied into each signup and check-in document at the time of creation. This avoids expensive join queries and preserves an accurate audit trail — retroactive changes to event details don't alter past records.

**Dual Activation Strategy**
Events can be toggled active manually by an admin, or they activate automatically when the scheduled date/time arrives (the dashboard polls every minute). This ensures events go live on time without requiring admin action.

**Student Authentication — Triple Validation**
On login, three checks run in sequence:
1. Google email domain must match the school domain (e.g. `@seq.org`)
2. The email must exist in Firestore with `isWhitelisted: true`
3. Firebase Auth credential must be valid

Because the app only runs these at interactive sign-in and a restored session skips them, the whitelist is re-checked independently on every sign-up and every check-in — otherwise removing a student would not take effect until they happened to sign out.

**Role-Based Firestore Security Rules**
Students can read only their own record, their own sign-ups, and their own check-ins; the roster is admin-only. They can update a narrow set of safe fields on their own profile (FCM token, last sign-in). Full event/student/check-in management is locked to users present in a separate `/admins` collection.

The rules are the security boundary, so they have tests: `npm run test:rules` in `admin-dashboard/` runs them against the Firestore emulator. Run it before publishing any rules change.

**Server-Authoritative Sign-Ups**
Sign-ups are created only by `POST /api/signup`, never by the app writing to Firestore directly (the rules deny client creates). Two things require it: enforcing an event's spot limit means counting its sign-ups, which rules cannot do and students have no permission to do; and the event snapshot stored on the sign-up — including the hours it will later be worth — must come from the event document rather than from the caller.

**API Routes Are Credentialed**
Everything under `app/api/` runs with Admin SDK credentials, which bypass Firestore rules completely. Each route therefore verifies the caller's Firebase ID token itself: `requireAdmin` for `/api/notify` and `/api/events`, `requireUser` for `/api/signup`.

---

## Database Structure (Firestore)

- `/events` — Event definitions (title, date/time, location, GPS, hours, isActive flag)
- `/students` — Whitelist with student metadata and FCM push token
- `/signups` — Student registrations, including a snapshot of event data at signup time
- `/checkins` — Attendance records created on successful GPS check-in
- `/admins` — Admin access control (managed via Firebase console only)

---

## Key Files

```
FlockIn/                     iOS SwiftUI app source
  AppDelegate.swift          Firebase init, FCM token registration
  AuthViewModel.swift        Google Sign-In, domain + whitelist validation
  EventsViewModel.swift      Firestore listeners, signup/check-in logic
  EventsView.swift           Week calendar + event list (Tab 1)
  MyEventsView.swift         Student's signed-up events (Tab 2)
  EventDetailView.swift      Event info, map, GPS check-in button
  LocationManager.swift      Core Location wrapper

admin-dashboard/             Next.js admin web app
  app/dashboard/             Overview stats + recent check-ins
  app/events/                Event CRUD, activation toggle, signups view
  app/students/              Whitelist management, CSV import, hours view
  app/hours/                 Full check-in log + per-student hour totals
  app/api/notify/            FCM push notification endpoint (server-side)

firestore.rules              Firestore security rules
```
