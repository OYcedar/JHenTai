import 'package:flutter/material.dart';
import 'package:get/get.dart';

class WebSettingsSecurityPage extends StatelessWidget {
  const WebSettingsSecurityPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.menuSecurity'.tr)),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'settings.securityWebStub'.tr,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}
