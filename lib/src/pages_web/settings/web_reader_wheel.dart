import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';

/// Persisted key for [WebReaderWheelAction] (horizontal PageView modes in web reader).
const kWebReaderWheelActionKey = 'web_reader_wheel_action';

/// When [WebReaderWheelAction.page], swap wheel direction for next vs previous page.
const kWebReaderWheelInvertPageKey = 'web_reader_wheel_invert_page';

/// Mouse wheel multiplier for vertical / fit-width continuous reader modes.
const kWebReaderWheelScrollSpeedKey = 'web_reader_wheel_scroll_speed';

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
  if (v == WebReaderWheelAction.zoom.name) {
    return WebReaderWheelAction.zoom;
  }
  return WebReaderWheelAction.page;
}

bool webReaderWheelInvertPageFromStorage(String? v) =>
    v == '1' || v == 'true' || v == 'yes';

double webReaderWheelScrollSpeedFromStorage(String? v) {
  final parsed = double.tryParse(v ?? '');
  if (parsed == null || parsed <= 0) {
    return 5.0;
  }
  return parsed.clamp(0.5, 12.0);
}

/// Radio group: reader wheel = turn page vs zoom (also used from mouse-wheel settings page).
class WebReaderWheelSettingSection extends StatefulWidget {
  const WebReaderWheelSettingSection({super.key});

  @override
  State<WebReaderWheelSettingSection> createState() =>
      _WebReaderWheelSettingSectionState();
}

class _WebReaderWheelSettingSectionState
    extends State<WebReaderWheelSettingSection> {
  WebReaderWheelAction _value = WebReaderWheelAction.page;
  bool _invertPageTurn = false;
  double _scrollSpeed = 5.0;
  bool _loaded = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loaded = false;
      _errorMessage = '';
    });
    try {
      final raw = await backendApiClient.getSetting(kWebReaderWheelActionKey);
      final invertRaw =
          await backendApiClient.getSetting(kWebReaderWheelInvertPageKey);
      final speedRaw =
          await backendApiClient.getSetting(kWebReaderWheelScrollSpeedKey);
      if (mounted) {
        setState(() {
          _value = webReaderWheelActionFromStorage(raw);
          _invertPageTurn = webReaderWheelInvertPageFromStorage(invertRaw);
          _scrollSpeed = webReaderWheelScrollSpeedFromStorage(speedRaw);
          _loaded = true;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage =
              'settings.loadWheelSettingsFailed'.trParams({'error': '$e'});
          _loaded = true;
        });
      }
    }
  }

  Future<void> _save(WebReaderWheelAction v) async {
    final previous = _value;
    setState(() => _value = v);
    try {
      await backendApiClient.putSetting(
          kWebReaderWheelActionKey, v.storageValue);
    } catch (e) {
      if (mounted) {
        setState(() => _value = previous);
      }
      _showSaveFailed(e);
    }
  }

  Future<void> _saveInvert(bool v) async {
    final previous = _invertPageTurn;
    setState(() => _invertPageTurn = v);
    try {
      await backendApiClient.putSetting(
          kWebReaderWheelInvertPageKey, v ? '1' : '0');
    } catch (e) {
      if (mounted) {
        setState(() => _invertPageTurn = previous);
      }
      _showSaveFailed(e);
    }
  }

  Future<void> _saveScrollSpeed(double v) async {
    final next = v.clamp(0.5, 12.0);
    final previous = _scrollSpeed;
    setState(() => _scrollSpeed = next);
    try {
      await backendApiClient.putSetting(
        kWebReaderWheelScrollSpeedKey,
        next.toStringAsFixed(1),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _scrollSpeed = previous);
      }
      _showSaveFailed(e);
    }
  }

  void _showSaveFailed(Object error) {
    Get.snackbar(
      'common.error'.tr,
      'settings.saveWheelSettingsFailed'.trParams({'error': '$error'}),
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (_errorMessage.isNotEmpty) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.error_outline,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _load,
              icon: const Icon(Icons.refresh),
              label: Text('common.retry'.tr),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('reader.wheelAction'.tr,
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'reader.wheelActionVerticalHint'.tr,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Colors.grey),
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
        const Divider(height: 24),
        Text('reader.wheelScrollSpeed'.tr,
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'reader.wheelScrollSpeedSubtitle'.tr,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Colors.grey),
        ),
        Row(
          children: [
            Expanded(
              child: Slider(
                value: _scrollSpeed,
                min: 0.5,
                max: 12,
                divisions: 23,
                label: _scrollSpeed.toStringAsFixed(1),
                onChanged: (value) => setState(() => _scrollSpeed = value),
                onChangeEnd: _saveScrollSpeed,
              ),
            ),
            SizedBox(
              width: 48,
              child: Text(
                _scrollSpeed.toStringAsFixed(1),
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
