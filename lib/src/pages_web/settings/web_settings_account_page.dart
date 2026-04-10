import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/pages_web/settings/web_settings_controller.dart';

class WebSettingsAccountPage extends GetView<WebSettingsController> {
  const WebSettingsAccountPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.account'.tr)),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Obx(() => controller.isLoggedIn.value
                      ? _loggedIn(context)
                      : _loginForm(context)),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _loggedIn(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.check_circle, color: Colors.green),
        const SizedBox(width: 8),
        Expanded(
          child: Obx(() => Text('settings.loggedIn'.trParams({'user': controller.userName.value}))),
        ),
        TextButton(
          onPressed: controller.logout,
          child: Text('settings.logout'.tr),
        ),
      ],
    );
  }

  Widget _loginForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('settings.cookieLogin'.tr, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'settings.cookieHint'.tr,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller.cookieController,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: 'settings.cookiePlaceholder'.tr,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: controller.loginWithCookies,
          child: Text('settings.setCookies'.tr),
        ),
        const Divider(height: 32),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('settings.credentialLogin'.tr,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey)),
            children: [
              const SizedBox(height: 8),
              TextField(
                controller: controller.loginUserController,
                decoration: InputDecoration(
                  labelText: 'settings.username'.tr,
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller.loginPassController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'settings.password'.tr,
                  border: const OutlineInputBorder(),
                ),
                onSubmitted: (_) => controller.login(),
              ),
              const SizedBox(height: 8),
              Obx(() => OutlinedButton(
                    onPressed: controller.isLoggingIn.value ? null : controller.login,
                    child: controller.isLoggingIn.value
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text('settings.login'.tr),
                  )),
            ],
          ),
        ),
      ],
    );
  }
}
