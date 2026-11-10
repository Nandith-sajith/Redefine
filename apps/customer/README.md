# Redefine Snow — Customer

The homeowner app: add a property to get a price per plough, accept the quote,
then request a plough (optionally with shovelling) whenever it snows and follow
the job until it is done.

    flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8080
    flutter test

`API_BASE_URL` defaults to the hosted API. Payments follow the server: with
Stripe configured a card is saved once on Stripe's hosted page and each request
places a hold; otherwise jobs are billed afterwards.
