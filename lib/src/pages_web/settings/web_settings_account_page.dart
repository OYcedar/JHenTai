import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/pages_web/settings/web_settings_controller.dart';
import 'package:jhentai/src/pages_web/web_scroll_to_top.dart';

class WebSettingsAccountPage extends StatefulWidget {
  const WebSettingsAccountPage({super.key});

  @override
  State<WebSettingsAccountPage> createState() => _WebSettingsAccountPageState();
}

class _WebSettingsAccountPageState extends State<WebSettingsAccountPage>
    with WebScrollToTopState<WebSettingsAccountPage> {
  final WebSettingsController controller = Get.find<WebSettingsController>();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.account'.tr)),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        return SingleChildScrollView(
          controller: scrollController,
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
      floatingActionButton: buildScrollToTopFab(),
    );
  }

  Widget _loggedIn(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Obx(() => Text('settings.loggedIn'
                  .trParams({'user': controller.userName.value}))),
            ),
            TextButton.icon(
              onPressed: controller.logout,
              icon: const Icon(Icons.logout, size: 18),
              label: Text('settings.logout'.tr),
            ),
          ],
        ),
        const Divider(height: 32),
        Obx(() => Text(
              controller.cookieStatus.value,
              style: Theme.of(context).textTheme.bodySmall,
            )),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: controller.loadCookieStatus,
              icon: const Icon(Icons.refresh, size: 18),
              label: Text('common.refresh'.tr),
            ),
            OutlinedButton.icon(
              onPressed: () => _copyCookies(controller.cookies),
              icon: const Icon(Icons.copy, size: 18),
              label: Text('settings.copyCookies'.tr),
            ),
            OutlinedButton.icon(
              onPressed: () => _copyCookies(
                controller.cookies
                    .where((c) =>
                        c['name'] == 'ipb_member_id' ||
                        c['name'] == 'ipb_pass_hash' ||
                        c['name'] == 'igneous')
                    .toList(),
              ),
              icon: const Icon(Icons.key, size: 18),
              label: Text('settings.copyKeyCookies'.tr),
            ),
            Obx(() => FilledButton.icon(
                  onPressed: controller.isRefreshingIgneous.value
                      ? null
                      : controller.refreshIgneousCookie,
                  icon: controller.isRefreshingIgneous.value
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.vpn_key_outlined, size: 18),
                  label: Text('settings.refreshIgneous'.tr),
                )),
          ],
        ),
        const SizedBox(height: 8),
        Obx(
          () => ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('settings.showCookies'.tr),
            children: controller.cookies
                .map((cookie) => ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(cookie['name'] ?? ''),
                      subtitle: SelectableText(cookie['value'] ?? ''),
                      onTap: () => _copyCookies([cookie]),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  Future<void> _copyCookies(Iterable<Map<String, String>> cookies) async {
    final text = cookies
        .where((c) => (c['name'] ?? '').isNotEmpty)
        .map((c) => '${c['name']}=${c['value'] ?? ''}')
        .join('; ');
    if (text.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    Get.snackbar('common.success'.tr, 'hasCopiedToClipboard'.tr,
        snackPosition: SnackPosition.BOTTOM);
  }

  Future<void> _pasteCookies() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    final normalized = _normalizeCookieText(text);
    if (normalized.isEmpty) {
      Get.snackbar('common.error'.tr, 'settings.cookieEmpty'.tr,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }
    controller.cookieController.text = normalized;
  }

  String _normalizeCookieText(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final cookies = <String, String>{};
    for (final name in const ['ipb_member_id', 'ipb_pass_hash', 'igneous']) {
      final match =
          RegExp('$name[=:]\\s?([^;\\n\\r\\t ]+)').firstMatch(trimmed);
      final value = match?.group(1);
      if (value != null && value.isNotEmpty) {
        cookies[name] = value;
      }
    }
    if (cookies.isNotEmpty) {
      return cookies.entries.map((e) => '${e.key}=${e.value}').join('; ');
    }

    return trimmed;
  }

  Widget _loginForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('settings.cookieLogin'.tr,
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'settings.cookieHint'.tr,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: Colors.grey),
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
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: controller.loginWithCookies,
              child: Text('settings.setCookies'.tr),
            ),
            OutlinedButton.icon(
              onPressed: _pasteCookies,
              icon: const Icon(Icons.content_paste, size: 18),
              label: Text('settings.pasteCookies'.tr),
            ),
          ],
        ),
        const Divider(height: 32),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('settings.credentialLogin'.tr,
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(color: Colors.grey)),
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
                    onPressed:
                        controller.isLoggingIn.value ? null : controller.login,
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
