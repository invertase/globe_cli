import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:shelf_cors_headers/shelf_cors_headers.dart';

import 'package:server/env.dart';
import 'package:server/router.dart';
import 'package:server/src/firebase.dart';

void main(List<String> args) async {
  Firebase.init(
    projectId: Env.firebaseProjectId,
    clientId: Env.firebaseClientId,
    privateKey: Env.firebasePrivateKey.replaceAll(r'\n', '\n'),
    clientEmail: Env.firebasePrivateEmail,
  );

  // Use any available host or container IP (usually `0.0.0.0`).
  final ip = InternetAddress.anyIPv4;

  // Configure a pipeline that logs requests.
  final handler = Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(corsHeaders())
      .addHandler(router);

  // For running in containers, we respect the PORT environment variable.
  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await serve(handler, ip, port);
  print('Server listening on port ${server.port}');

  ProcessSignal.sigint.watch().listen((_) async {
    await Firebase.close();
    await server.close();
    exit(0); // Exit the program
  });
}