import 'dart:convert';

/// A command the device accepts, from a `[!cmd]` line or a protocol file.
class CommandSpec {
  const CommandSpec({required this.name, this.args = '', this.desc = '', this.example = ''});

  final String name;
  final String args;
  final String desc;
  final String example;

  /// Text placed in the input box when the command is picked.
  String get insertText {
    if (example.isNotEmpty) return example;
    return args.isEmpty ? name : '$name ';
  }

  /// `move <steps> [speed]`
  String get usage => args.isEmpty ? name : '$name $args';

  /// From the key/value pairs of a `[!cmd]` line. Null when `name` is missing.
  static CommandSpec? fromFields(Map<String, String> f) {
    final name = f['name'];
    if (name == null || name.isEmpty) return null;
    return CommandSpec(
      name: name,
      args: f['args'] ?? '',
      desc: f['desc'] ?? '',
      example: f['example'] ?? '',
    );
  }
}

/// A protocol description file (docs/PROTOCOL.md §5).
class ProtocolDoc {
  const ProtocolDoc({required this.name, required this.commands});

  final String name;
  final List<CommandSpec> commands;

  /// Throws [FormatException] when the text is not a usable description.
  factory ProtocolDoc.fromJson(String text) {
    final Object? root = jsonDecode(text);
    if (root is! Map) throw const FormatException('Expected a JSON object');
    final commands = <CommandSpec>[];
    final Object? list = root['commands'];
    if (list is List) {
      for (final Object? item in list) {
        if (item is! Map) continue;
        final Object? name = item['name'];
        if (name is! String || name.isEmpty) continue;
        commands.add(CommandSpec(
          name: name,
          args: '${item['args'] ?? ''}',
          desc: '${item['desc'] ?? ''}',
          example: '${item['example'] ?? ''}',
        ));
      }
    }
    return ProtocolDoc(name: '${root['name'] ?? ''}', commands: commands);
  }
}
