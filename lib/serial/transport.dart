import 'dart:typed_data';

/// A serial port the OS currently lists.
class PortInfo {
  const PortInfo({
    required this.name,
    this.description = '',
    this.manufacturer = '',
    this.vendorId,
    this.productId,
  });

  final String name;
  final String description;
  final String manufacturer;
  final int? vendorId;
  final int? productId;

  // USB vendor IDs of the chips found on ESP32 boards.
  static const Set<int> _espVendors = <int>{
    0x303A, // Espressif native USB (S2 / S3 / C3 / C6)
    0x10C4, // Silicon Labs CP210x
    0x1A86, // WCH CH340 / CH9102
    0x0403, // FTDI
  };

  bool get isUsb => vendorId != null;
  bool get isLikelyEsp32 => vendorId != null && _espVendors.contains(vendorId);

  /// Lower sorts first: likely ESP32 boards, then other USB ports, then the rest.
  int get rank => isLikelyEsp32 ? 0 : (isUsb ? 1 : 2);

  String get label {
    final detail = description.isNotEmpty ? description : manufacturer;
    return detail.isEmpty || detail == name ? name : '$name — $detail';
  }
}

class PortSettings {
  const PortSettings({required this.baud, required this.dtr, required this.rts});
  final int baud;
  final bool dtr;
  final bool rts;
}

class SerialOpenException implements Exception {
  const SerialOpenException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// The serial backend. One port open at a time. Kept behind an interface so
/// the session logic can be tested without hardware and the backend swapped.
abstract class SerialTransport {
  /// Ports currently present. Cheap enough to call twice a second.
  List<PortInfo> listPorts();

  /// Opens [name] (8 data bits, no parity, 1 stop bit, no flow control) and
  /// returns the incoming bytes. The stream reports an error or closes when
  /// the device goes away. Throws [SerialOpenException] if it cannot open.
  Stream<Uint8List> open(String name, PortSettings settings);

  void write(Uint8List data);

  /// Drives the DTR / RTS control lines of the open port.
  void setLines({required bool dtr, required bool rts});

  /// Closes the open port, if any. Never throws.
  void close();
}
