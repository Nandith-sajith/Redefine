# Redefine Snow — Crew

The crew app of Redefine, an on-demand snow ploughing service (Flutter, web and Windows).

A crew member signs up, waits for the office to approve the application, and then:

- **Open** — sees every plough request nobody has accepted yet; the first to accept takes it.
- **Jobs** — starts, releases or completes the jobs they accepted.
- **Pay** — follows the unpaid balance, earnings and the payouts recorded by the office.

The app never shows what the customer pays, only what the job pays the crew member.

## Run

```
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080
```

Without `API_BASE_URL` the app talks to the hosted API. In debug builds the login form is
prefilled with the demo crew account.

## Check

```
flutter analyze
flutter test
flutter build web --dart-define=API_BASE_URL=http://localhost:8080
```

The widget tests boot the real app against an in-memory fake of the API (`test/fake_api.dart`);
no network is involved.
