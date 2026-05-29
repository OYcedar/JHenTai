import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/pages_web/settings/web_reader_wheel.dart';

class WebSettingsMouseWheelPage extends StatelessWidget {
  const WebSettingsMouseWheelPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.menuMouseWheel'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('settings.mouseWheelIntro'.tr, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: WebReaderWheelSettingSection(),
            ),
          ),
        ],
      ),
    );
  }
}
