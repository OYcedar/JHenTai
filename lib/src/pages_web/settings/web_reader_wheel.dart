import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';

/// Persisted key for [WebReaderWheelAction] (horizontal PageView modes in web reader).
const kWebReaderWheelActionKey = 'web_reader_wheel_action';

/// When [WebReaderWheelAction.page], swap wheel direction for next vs previous page.
const kWebReaderWheelInvertPageKey = 'web_reader_wheel_invert_page';

enum WebReaderWheelAction {
  /// Pass wheel to PageView (turn page).
  page,
  /// Scale image with wheel over [InteractiveViewer].
  zoom,
}

extension WebReaderWheelActionStorage on WebReaderWheelAction {
  String get storageValue => name;
}

WebReaderWheelAction webReaderWheelActionFromStorage(String? v) {
  if (v == WebReaderWheelAction.zoom.name) return WebReaderWheelAction.zoom;
  return WebReaderWheelAction.page;
}

bool webReaderWheelInvertPageFromStorage(String? v) =>
    v == '1' || v == 'true' || v == 'yes';

/// Radio group: reader wheel = turn page vs zoom (also used from mouse-wheel settings page).
class WebReaderWheelSettingSection extends StatefulWidget {
  const WebReaderWheelSettingSection({super.key});

  @override
  State<WebReaderWheelSettingSection> createState() => _WebReaderWheelSettingSectionState();
}

class _WebReaderWheelSettingSectionState extends State<WebReaderWheelSettingSection> {
  WebReaderWheelAction _value = WebReaderWheelAction.page;
  bool _invertPageTurn = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await backendApiClient.getSetting(kWebReaderWheelActionKey);
      final invertRaw = await backendApiClient.getSetting(kWebReaderWheelInvertPageKey);
      if (mounted) {
        setState(() {
          _value = webReaderWheelActionFromStorage(raw);
          _invertPageTurn = webReaderWheelInvertPageFromStorage(invertRaw);
          _loaded = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  Future<void> _save(WebReaderWheelAction v) async {
    setState(() => _value = v);
    try {
      await backendApiClient.putSetting(kWebReaderWheelActionKey, v.storageValue);
    } catch (_) {}
  }

  Future<void> _saveInvert(bool v) async {
    setState(() => _invertPageTurn = v);
    try {
      await backendApiClient.putSetting(kWebReaderWheelInvertPageKey, v ? '1' : '0');
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('reader.wheelAction'.tr, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'reader.wheelActionVerticalHint'.tr,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
        ),
        RadioListTile<WebReaderWheelAction>(
          title: Text('reader.wheelActionPage'.tr),
          value: WebReaderWheelAction.page,
          groupValue: _value,
          onChanged: (v) => v != null ? _save(v) : null,
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
        RadioListTile<WebReaderWheelAction>(
          title: Text('reader.wheelActionZoom'.tr),
          value: WebReaderWheelAction.zoom,
          groupValue: _value,
          onChanged: (v) => v != null ? _save(v) : null,
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
        SwitchListTile(
          title: Text('reader.wheelInvertPageTurn'.tr),
          subtitle: Text('reader.wheelInvertPageTurnSubtitle'.tr),
          value: _invertPageTurn,
          onChanged: _saveInvert,
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      ],
    );
  }
}
