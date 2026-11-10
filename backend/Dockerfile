# --- build stage ---
FROM dart:3.10 AS build
WORKDIR /app
COPY pubspec.* ./
RUN dart pub get
COPY . .
RUN dart pub get --offline
RUN dart compile exe bin/server.dart -o bin/server

# --- runtime stage (minimal) ---
FROM scratch
# /runtime/ holds the AOT runtime's shared libraries and the CA certificates
# needed for HTTPS to Google and Stripe.
COPY --from=build /runtime/ /
COPY --from=build /app/bin/server /app/bin/server
EXPOSE 8080
CMD ["/app/bin/server"]
