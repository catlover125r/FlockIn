# Flock In

An iOS app for high school ASB volunteer events. Students sign in with their school
Google account, browse upcoming events, sign up for one, and check in on location to
earn volunteer hours.

Built with SwiftUI, Firebase Auth, Firestore and Cloud Messaging.

## For App Review

Tap **Staff sign-in** on the login screen. The fields are already filled in:

| Username | Password |
| --- | --- |
| `admin` | `password` |

This test account is self-contained. It signs in without a network connection and shows
a fixed set of sample events — it never reads or writes real student data. A banner stays
on screen for the whole session so the sample data is never mistaken for the real thing.

Reviewers can sign up for a sample event, view it under **My Events**, and check in. The
"Homecoming Game" event has no location attached, so its check-in works from anywhere;
the located events require standing within 200m, which is the behaviour real students get.

Students themselves sign in with **Continue with Google**, which is restricted to the
school's Google Workspace domain and to a roster the ASB advisor maintains.

## Support

Please open an [issue](../../issues) for bug reports or questions.

## Building

The app needs a Firebase project. `GoogleService-Info.plist` is deliberately not in this
repository — it is specific to a Firebase project and is generated per install.

1. Create a Firebase project with Auth (Google + Email/Password), Firestore and Messaging.
2. Add an iOS app and download `GoogleService-Info.plist` into `FlockIn/`.
3. Set `AuthService.schoolDomain` to your Google Workspace domain.
4. Deploy `firestore.rules`.
5. Open `FlockIn.xcodeproj` and run.

`SETUP.md` walks through this in detail. `PROJECT_SUMMARY.md` describes the data model,
the security rules and how the pieces fit together.

## Layout

```
FlockIn/
  FlockInApp.swift        App entry, Firebase init, push registration
  EventStore.swift        Event state, Firestore listeners, sample data
  LocationManager.swift   Check-in proximity
  Models/Event.swift
  Services/               AuthService, FirestoreService
  Views/                  Login, events list, detail, map, calendar
firestore.rules           Security rules
```

Sign-ups go through an admin dashboard API rather than straight to Firestore, so an
event's spot limit can be enforced somewhere allowed to count existing sign-ups.
