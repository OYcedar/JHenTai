import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// Web-safe group picker (chips + text field). Does not use [EHGroupNameSelector],
/// which pulls imports incompatible with `flutter build web` (dart:ffi via extensions).
class WebGroupNameSelector extends StatefulWidget {
  final String? currentGroup;
  final List<String> candidates;
  final ValueChanged<String>? listener;

  const WebGroupNameSelector({
    super.key,
    this.currentGroup,
    required this.candidates,
    this.listener,
  });

  @override
  State<WebGroupNameSelector> createState() => _WebGroupNameSelectorState();
}

class _WebGroupNameSelectorState extends State<WebGroupNameSelector> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentGroup ?? 'default');
    _controller.addListener(() {
      widget.listener?.call(_controller.text);
      setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.candidates.isNotEmpty) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'existingGroup'.tr,
              style: TextStyle(fontSize: 11, color: Theme.of(context).hintColor),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final c in widget.candidates)
                ChoiceChip(
                  label: Text(c),
                  selected: _controller.text == c,
                  onSelected: (_) {
                    _controller.text = c;
                  },
                ),
            ],
          ),
          const SizedBox(height: 10),
        ],
        TextField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: 'groupName'.tr,
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
      ],
    );
  }
}
