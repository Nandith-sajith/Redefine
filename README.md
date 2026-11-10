# Redefine — snow ploughing

Three Flutter apps (customer / admin / crew) on one Dart API.

A customer adds a property and asks for a quote. The admin visits, then enters a price per
plough. From then on the customer can request a plough whenever it snows, optionally with
shovelling for an extra charge. Each request is open to every approved crew member; the first
to accept does the job. The customer's card is held at request time and charged only when the
job is completed.

```
app_red/
├── backend/                  Dart (shelf) REST API  →  Cloud Run + Firestore
│   ├── bin/server.dart
│   ├── lib/                  api.dart, src/{features,data,auth,payments}
│   ├── test/                 in-process API tests
│   ├── setup.ps1  deploy.ps1  scripts/
│   └── Dockerfile
├── e2e/                      real server driven through the real client
├── packages/
│   ├── redefine_core/        models + ApiClient (pure Dart)
│   └── redefine_ui/          theme, widgets, session, live-data helpers (Flutter)
└── apps/
    ├── customer/             properties, quotes, request a plough, live tracking, billing
    ├── admin/                inbox, quotes and pricing, jobs, customers, crew and payouts, settings
    └── crew/                 open requests, my jobs, pay
```

The `redefine-*-app.html` mockups and `pencil-new.pen` describe the earlier lawn-care design
and are kept for reference only.

## How it works

| Step | Who | What happens |
|------|-----|--------------|
| 1 | Customer | Signs up, adds a property. A quote request is created. |
| 2 | Admin | Enters the price per plough and the crew pay per plough, sends the quote. |
| 3 | Customer | Accepts, and (with Stripe on) saves a card once on a Stripe-hosted page. |
| 4 | Customer | Requests a plough, optionally adding shovelling. A hold is placed on the card. |
| 5 | Crew | Any approved crew member accepts, starts and completes the job. |
| 6 | System | The hold is captured on completion; cancelling releases it. Crew pay accrues. |
| 7 | Admin | Sees everything live, records crew payouts, handles any payment problems. |

The shovelling price (default $20), the crew shovelling bonus (default $10) and how long an
unclaimed request stays open (default 48 h) are admin settings.

**Payments.** With a Stripe key configured the API uses real card holds and captures. Without
one it runs in *manual* mode: no card is needed, a finished job shows as due, and the admin
marks it paid.

## Run it locally

Start the API (in-memory data, demo accounts, manual payments):

```powershell
cd backend
dart pub get
dart run bin/server.dart        # http://localhost:8080
```

Run an app against it, from `apps/customer`, `apps/admin` or `apps/crew`:

```powershell
flutter run -d chrome --web-port 5101 --dart-define=API_BASE_URL=http://localhost:8080
```

Use a different fixed port per app (for example 5101, 5102, 5103) so each keeps its own
sign-in between runs. Without `--dart-define` an app talks to the deployed API.

### Demo accounts

Three sign-in accounts and nothing else; the data is whatever you create.

| App | Email | Who |
|-----|-------|-----|
| Admin | `lia@redefine.co` | Lia Robinson |
| Crew | `marcus@redefine.co` | Marcus Reid (approved) |
| Customer | `sarah.m@gmail.com` | Sarah Mitchell |

Locally the password is `redefine`. On the deployed system it is the password you entered
with `backend/scripts/set-demo-password.ps1`.

For local development only, `SEED_SAMPLE_DATA=true` also loads the sample properties, quotes,
jobs and extra accounts that the automated tests use (it is refused on a Firestore server).

### Stripe test mode locally

Set your own **test** key in the terminal before starting the API:

```powershell
$env:STRIPE_SECRET_KEY = "<your sk_test_ key>"
dart run bin/server.dart
```

## Tests

```powershell
cd backend;                 dart test      # API, persistence, Stripe client, auth
cd e2e;                     dart test      # server + client end to end
cd packages/redefine_core;  dart test
cd packages/redefine_ui;    flutter test
cd apps/customer;           flutter test   # likewise admin, crew
```

## Deploy the API

Everything uses the Google account `redefine073@gmail.com` and project `redefine-8a0b828f`,
passed explicitly, so it does not matter which gcloud account is active.

```powershell
cd backend
./setup.ps1                        # once: APIs, Firestore database in Toronto, service account
./scripts/set-stripe-key.ps1       # optional: turns on card payments
./scripts/set-demo-password.ps1    # optional: loads the demo accounts with a password you choose
./deploy.ps1
```

`deploy.ps1` ends by checking `/health` and prints the storage and payment mode in use. The API
runs as a single instance and keeps a working copy of the data in memory, writing every change
through to Firestore.

For real use, skip the demo password and create the first admin with an invite code:

```powershell
./scripts/set-admin-invite-code.ps1
./deploy.ps1
```

Then sign up in the admin app with that code. Crew sign up in the crew app and wait for an
admin to approve them. Customers sign up in the customer app.

## API configuration

Environment variables read by `backend/bin/server.dart`:

| Variable | Default | Meaning |
|----------|---------|---------|
| `PORT` | `8080` | Port to listen on |
| `PERSISTENCE` | `memory` | `memory` or `firestore` |
| `GCP_PROJECT` | — | Required for Firestore |
| `FIRESTORE_DATABASE` | `(default)` | Firestore database id |
| `STRIPE_SECRET_KEY` | — | Absent means manual payments |
| `PUBLIC_BASE_URL` | `http://localhost:$PORT` | Used for the Stripe return page |
| `ADMIN_INVITE_CODE` | — | Enables admin signup; at least 16 characters |
| `SEED_DEMO` | `true` in memory, `false` in Firestore | Create the three demo accounts in an empty database |
| `SEED_SAMPLE_DATA` | `false` | Memory mode only: also load the sample data used by the tests |
| `DEMO_PASSWORD` | `redefine` | Must be private when seeding Firestore |

## Not included yet

Photos, push or SMS notifications, password reset, taxes, refunds from inside the app, and
Windows desktop builds (the apps are verified on web).
