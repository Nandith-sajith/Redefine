# Redefine — lawn-care platform

Three Flutter apps (admin / crew / customer) sharing a design system and a Dart API,
built from the Pencil designs.

```
app_red/
├── backend/                  Dart (shelf) REST API  →  deployed to Cloud Run
│   ├── bin/server.dart
│   ├── lib/ (api.dart, store.dart)
│   ├── Dockerfile
│   └── deploy.ps1
├── packages/
│   ├── redefine_core/        models + ApiClient (pure Dart, shared)
│   └── redefine_ui/          design tokens, theme, widget kit (Flutter, shared)
└── apps/
    ├── admin/                Home · Quote detail · Schedule (Timeline/Week/Month) · Crew · Customers · Post card · Customer detail
    ├── crew/                 Jobs · Job detail · In progress · Pending · Accept · Pay
    └── customer/             Empty · Picker · Quote form · Waiting · Quote received · Timeline · Photo · Skip/pause
```

The three apps talk to **one** API, so actions flow between them: a customer's quote
request lands in the admin inbox; an admin-posted job card shows up in the crew's
Pending tab; claiming it updates everywhere.

## Live API

Deployed on Google Cloud Run (project `redefine-8a0b828f`):

> **https://redefine-api-867740771011.us-central1.run.app**

Health check: `/health` · try `/dashboard/admin`, `/quotes`, `/crew`, `/pending-jobs`,
`/crew/crew-marcus/pay`. The apps point at this URL by default — no local server needed.

**Auth:** `POST /auth/login`, `POST /auth/signup`, `GET /auth/me`. Login/signup return
`{ token, user }`; the token is sent as a `Bearer` header on later requests. Passwords are
SHA-256 hashed. (Store is in-memory, so new signups reset on a Cloud Run cold start.)

## Run an app

From `apps/<admin|crew|customer>`:

```powershell
flutter run -d chrome      # in a browser (recommended on Windows)
flutter run -d windows     # as a desktop window
```

On a wide window the UI is framed to a phone width so it previews like a handset.

### Point at a different API

```powershell
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080
```

## Run the API locally (optional)

```powershell
cd backend
dart pub get
dart run bin/server.dart        # http://localhost:8080
```

## Redeploy the API

```powershell
cd backend
./deploy.ps1                     # uses the current gcloud project
```

## Auth flow

Each app now opens on a **login screen** (persona-branded) and routes to its shell after
sign-in. You can also create a new account from the **Sign up** link. The shared screens
live in `packages/redefine_ui/lib/src/auth.dart` and are configured per app via `AuthPersona`
in each `main.dart`.

## Demo logins (seeded)

Password for all three is **`redefine`** (pre-filled on each app's login screen):

| App | Email | Who |
|-----|-------|-----|
| Admin | `lia@redefine.co` | Lia (operator) |
| Crew | `marcus@redefine.co` | Marcus Reid |
| Customer | `sarah.m@gmail.com` | Sarah Mitchell (Maple Street home, mid-subscription) |
