import 'package:material_ui/material_ui.dart';

import '../app_controller.dart';
import '../protocol/protocol_doc.dart';
import '../serial/session.dart';
import 'style.dart';

/// A suggestion in the command box: a declared command or a past entry.
class _Suggestion {
  const _Suggestion(this.text, this.label, this.detail);

  /// What goes into the input box.
  final String text;

  /// What the list shows on the left.
  final String label;
  final String detail;
}

/// Text box for sending commands, with suggestions from the device's
/// declared commands, a loaded protocol file and what was sent before.
class CommandBar extends StatefulWidget {
  const CommandBar({super.key, required this.app});

  final AppController app;

  @override
  State<CommandBar> createState() => _CommandBarState();
}

class _CommandBarState extends State<CommandBar> {
  static const Map<String, String> _lineEndings = <String, String>{
    '\n': 'LF',
    '\r\n': 'CRLF',
    '\r': 'CR',
    '': 'None',
  };

  TextEditingController? _controller;
  FocusNode? _focusNode;

  AppController get _app => widget.app;

  Iterable<_Suggestion> _suggestions(TextEditingValue value) {
    final typed = value.text.trimLeft().toLowerCase();
    // Nothing typed: stay out of the way. The picker button lists everything.
    if (typed.isEmpty) return const <_Suggestion>[];
    final out = <_Suggestion>[];
    final seen = <String>{};
    for (final CommandSpec c in _app.commands) {
      if (c.name.toLowerCase().startsWith(typed) || typed.startsWith('${c.name.toLowerCase()} ')) {
        if (seen.add(c.insertText)) out.add(_Suggestion(c.insertText, c.usage, c.desc));
      }
    }
    for (final String h in _app.history) {
      if (h.toLowerCase() == typed) continue;
      if (h.toLowerCase().startsWith(typed)) {
        if (seen.add(h)) out.add(_Suggestion(h, h, 'sent earlier'));
      }
    }
    return out.take(12);
  }

  void _submit() {
    final controller = _controller;
    if (controller == null) return;
    final text = controller.text;
    if (text.trim().isEmpty) return;
    if (_app.send(text)) {
      controller.clear();
    } else {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Not connected: nothing was sent')));
    }
    _focusNode?.requestFocus();
  }

  void _insert(String text) {
    final controller = _controller;
    if (controller == null) return;
    controller.value = TextEditingValue(text: text, selection: TextSelection.collapsed(offset: text.length));
    _focusNode?.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final session = _app.session;
    final connected = session.state == LinkState.connected;
    final commands = _app.commands;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: <Widget>[
          PopupMenuButton<CommandSpec>(
            tooltip: commands.isEmpty
                ? 'No commands known yet. Send ? or load a protocol file'
                : 'Pick a command',
            enabled: commands.isNotEmpty,
            icon: const Icon(Icons.list_alt),
            onSelected: (c) => _insert(c.insertText),
            itemBuilder: (context) => <PopupMenuEntry<CommandSpec>>[
              for (final c in commands)
                PopupMenuItem<CommandSpec>(
                  value: c,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Text(c.usage, style: kMono),
                      if (c.desc.isNotEmpty) ...<Widget>[
                        const SizedBox(width: 16),
                        Flexible(
                          child: Text(
                            c.desc,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: kMuted, fontSize: 12),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Autocomplete<_Suggestion>(
              optionsBuilder: _suggestions,
              displayStringForOption: (s) => s.text,
              optionsViewOpenDirection: OptionsViewOpenDirection.up,
              fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                _controller = controller;
                _focusNode = focusNode;
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  style: kMono,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    isDense: true,
                    border: const OutlineInputBorder(),
                    hintText: connected ? 'Type a command, Enter to send' : 'Connect to send commands',
                  ),
                  // Enter sends exactly what is typed; keep the focus for the next one.
                  onEditingComplete: () {},
                  onSubmitted: (_) => _submit(),
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                final list = options.toList(growable: false);
                return Align(
                  alignment: Alignment.bottomLeft,
                  child: Material(
                    elevation: 6,
                    color: kSurface,
                    borderRadius: BorderRadius.circular(6),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 260),
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        shrinkWrap: true,
                        itemCount: list.length,
                        itemBuilder: (context, index) {
                          final s = list[index];
                          final highlighted = AutocompleteHighlightedOption.of(context) == index;
                          return InkWell(
                            onTap: () => onSelected(s),
                            child: Container(
                              color: highlighted ? kAccent.withAlpha(40) : null,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              child: Row(
                                children: <Widget>[
                                  Flexible(child: Text(s.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: kMono)),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Text(
                                      s.detail,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(color: kMuted, fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Line ending added to each command',
            child: DropdownButton<String>(
              isDense: true,
              value: session.lineEnding,
              items: <DropdownMenuItem<String>>[
                for (final e in _lineEndings.entries) DropdownMenuItem<String>(value: e.key, child: Text(e.value)),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => session.lineEnding = value);
              },
            ),
          ),
          const SizedBox(width: 8),
          FilledButton(onPressed: connected ? _submit : null, child: const Text('Send')),
          const SizedBox(width: 4),
          IconButton(
            tooltip: 'Ask the device for its commands (sends ?)',
            icon: const Icon(Icons.help_outline),
            onPressed: connected ? () => _app.send('?') : null,
          ),
        ],
      ),
    );
  }
}
