import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart';
import 'package:path/path.dart' as path;

const kReleaseMode = bool.fromEnvironment('dart.vm.product');

String get libPath {
  final p = kReleaseMode
      ? 'static/libnative_hello.so'
      : 'native_hello/target/debug/libnative_hello.dylib';
  return path.join(Directory.current.path, p);
}

final dylib = DynamicLibrary.open(libPath);
typedef _GreetHumanFnNative
    = NativeFunction<Pointer<Utf8> Function(Pointer<Utf8>)>;
typedef _GreetHumanFnDart = Pointer<Utf8> Function(Pointer<Utf8>);

final _greetHumanFfi = dylib
    .lookup<_GreetHumanFnNative>('greet_human_ffi')
    .asFunction<_GreetHumanFnDart>();

String greetHuman(String name) {
  final namePtr = name.toNativeUtf8();
  final result = _greetHumanFfi(namePtr).toDartString();
  malloc.free(namePtr);
  return result;
}

void main(List<String> args) async {
  final handler = Pipeline().addMiddleware(logRequests()).addHandler((request) {
    final name = request.url.queryParameters['name'] ?? 'FFI Works 🚀';
    return Response.ok(greetHuman(name));
  });

  final port = int.parse(Platform.environment['PORT'] ?? '8080');
  final server = await serve(handler, InternetAddress.anyIPv4, port);

  print('Server listening on port ${server.port} PID: $pid');
}
