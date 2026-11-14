import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// A tiny loopback-only TCP endpoint that lets build tools ask the monitor to
/// let go of the serial port (see tool/pio_smp_hook.py).
///
/// One text line in, one text line out, then the connection closes:
///   release [seconds]   close the port; take it back after `seconds` or on resume
///   resume              take the port back now
///   status              report the connection state
class ControlServer {
  static const int defaultPort = 47800;

  ServerSocket? _server;

  /// Starts listening. Returns an error message, or null on success.
  Future<String?> start(String Function(String command) handle, {int port = defaultPort}) async {
    try {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      _server = server;
      server.listen((Socket socket) => _serve(socket, handle), onError: (Object _) {});
      return null;
    } catch (e) {
      return '$e';
    }
  }

  void _serve(Socket socket, String Function(String command) handle) {
    var answered = false;
    final timeout = Timer(const Duration(seconds: 5), socket.destroy);
    utf8.decoder.bind(socket).transform(const LineSplitter()).listen(
      (String line) {
        if (answered) return;
        answered = true;
        timeout.cancel();
        String reply;
        try {
          reply = handle(line.trim());
        } catch (e) {
          reply = 'error $e';
        }
        socket.writeln(reply);
        socket.flush().then((_) => socket.destroy(), onError: (Object _) => socket.destroy());
      },
      onError: (Object _) {
        timeout.cancel();
        socket.destroy();
      },
      onDone: () {
        timeout.cancel();
        if (!answered) socket.destroy();
      },
      cancelOnError: true,
    );
  }

  Future<void> stop() async {
    final server = _server;
    _server = null;
    await server?.close();
  }
}
