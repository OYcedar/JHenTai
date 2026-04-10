import 'package:flutter/material.dart';
import 'package:get/get.dart';

class WebSettingsPerformancePage extends StatelessWidget {
  const WebSettingsPerformancePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.menuPerformance'.tr)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'settings.performanceWebStub'.tr,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
