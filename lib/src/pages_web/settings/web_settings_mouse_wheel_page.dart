import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/settings/web_reader_wheel.dart';
import 'package:jhentai/src/pages_web/web_home_page.dart';
import 'package:jhentai/src/pages_web/web_wheel_speed_controller.dart';

class WebSettingsMouseWheelPage extends StatefulWidget {
  const WebSettingsMouseWheelPage({super.key});

  @override
  State<WebSettingsMouseWheelPage> createState() =>
      _WebSettingsMouseWheelPageState();
}

class _WebSettingsMouseWheelPageState extends State<WebSettingsMouseWheelPage> {
  double _wheelScrollSpeed = 5.0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final value = await loadWebWheelScrollSpeed();
    if (!mounted) {
      return;
    }
    setState(() {
      _wheelScrollSpeed = value;
      _loaded = true;
    });
  }

  Future<void> _saveWheelScrollSpeed(double value) async {
    final next = value.clamp(0.5, 12.0);
    setState(() => _wheelScrollSpeed = next);
    try {
      await backendApiClient.putSetting(
        kWebWheelScrollSpeedKey,
        next.toStringAsFixed(1),
      );
      if (Get.isRegistered<WebHomeController>()) {
        Get.find<WebHomeController>().wheelScrollSpeed.value = next;
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.menuMouseWheel'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('settings.mouseWheelIntro'.tr,
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: _loaded
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('wheelScrollSpeed'.tr,
                            style: Theme.of(context).textTheme.titleSmall),
                        const SizedBox(height: 4),
                        Text(
                          'settings.webWheelScrollSpeedHint'.tr,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey),
                        ),
                        Row(
                          children: [
                            Expanded(
                              child: Slider(
                                value: _wheelScrollSpeed,
                                min: 0.5,
                                max: 12,
                                divisions: 23,
                                label: _wheelScrollSpeed.toStringAsFixed(1),
                                onChanged: (value) =>
                                    setState(() => _wheelScrollSpeed = value),
                                onChangeEnd: _saveWheelScrollSpeed,
                              ),
                            ),
                            SizedBox(
                              width: 48,
                              child: Text(
                                _wheelScrollSpeed.toStringAsFixed(1),
                                textAlign: TextAlign.end,
                              ),
                            ),
                          ],
                        ),
                      ],
                    )
                  : const Center(child: CircularProgressIndicator()),
            ),
          ),
          const SizedBox(height: 16),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: WebReaderWheelSettingSection(),
            ),
          ),
        ],
      ),
    );
  }
}
