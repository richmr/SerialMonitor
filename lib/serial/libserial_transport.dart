import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

import 'transport.dart';

/// [SerialTransport] backed by libserialport (macOS, Windows, Linux).
class LibSerialTransport implements SerialTransport {
  SerialPort? _port;
  SerialPortReader? _reader;
  final Map<String, PortInfo> _infoCache = <String, PortInfo>{};

  @override
  List<PortInfo> listPorts() {
    final names = SerialPort.availablePorts;
    _infoCache.removeWhere((name, _) => !names.contains(name));
    // Details are looked up once per port, not on every poll.
    return <PortInfo>[for (final name in names) _infoCache.putIfAbsent(name, () => _describe(name))];
  }

  PortInfo _describe(String name) {
    final port = SerialPort(name);
    try {
      return PortInfo(
        name: name,
        description: port.description ?? '',
        manufacturer: port.manufacturer ?? '',
        vendorId: port.vendorId,
        productId: port.productId,
      );
    } catch (_) {
      return PortInfo(name: name);
    } finally {
      port.dispose();
    }
  }

  @override
  Stream<Uint8List> open(String name, PortSettings settings) {
    close();
    final port = SerialPort(name);
    try {
      if (!port.openReadWrite()) {
        throw SerialOpenException(SerialPort.lastError?.message ?? 'could not open $name');
      }
      final config = port.config;
      config.baudRate = settings.baud;
      config.bits = 8;
      config.parity = SerialPortParity.none;
      config.stopBits = 1;
      config.setFlowControl(SerialPortFlowControl.none);
      config.dtr = settings.dtr ? SerialPortDtr.on : SerialPortDtr.off;
      config.rts = settings.rts ? SerialPortRts.on : SerialPortRts.off;
      port.config = config;
      final reader = SerialPortReader(port);
      _port = port;
      _reader = reader;
      return reader.stream;
    } catch (e) {
      try {
        if (port.isOpen) port.close();
      } catch (_) {}
      try {
        port.dispose();
      } catch (_) {}
      if (e is SerialOpenException) rethrow;
      throw SerialOpenException(e is SerialPortError ? e.message : '$e');
    }
  }

  @override
  void write(Uint8List data) {
    final port = _port;
    if (port == null) throw const SerialOpenException('port is not open');
    port.write(data);
  }

  @override
  void setLines({required bool dtr, required bool rts}) {
    final port = _port;
    if (port == null) return;
    final config = port.config;
    config.dtr = dtr ? SerialPortDtr.on : SerialPortDtr.off;
    config.rts = rts ? SerialPortRts.on : SerialPortRts.off;
    port.config = config;
  }

  @override
  void close() {
    final reader = _reader;
    final port = _port;
    _reader = null;
    _port = null;
    try {
      reader?.close();
    } catch (_) {}
    if (port != null) {
      try {
        if (port.isOpen) port.close();
      } catch (_) {}
      try {
        port.dispose();
      } catch (_) {}
    }
  }
}
