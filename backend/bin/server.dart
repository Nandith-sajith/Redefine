import 'dart:io';

import 'package:shelf/shelf_io.dart' as io;

import 'package:redefine_api/api.dart';

/// Entry point. Cloud Run provides the port via the PORT env var (default 8080).
Future<void> main() async {
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await io.serve(createApp(), InternetAddress.anyIPv4, port);
  // ignore: avoid_print
  print('Redefine API listening on http://${server.address.host}:${server.port}');
}
