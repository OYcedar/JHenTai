import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/main_web.dart';
import 'package:jhentai/src/network/backend_api_client.dart';

class WebSettingsController extends GetxController {
  final isLoggedIn = false.obs;
  final site = 'EH'.obs;
  final userName = ''.obs;
  final serverInfo = <String, dynamic>{}.obs;
  final isLoading = true.obs;

  final loginUserController = TextEditingController();
  final loginPassController = TextEditingController();
  final cookieController = TextEditingController();
  final isLoggingIn = false.obs;

  @override
  void onInit() {
    super.onInit();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    isLoading.value = true;
    try {
      final status = await backendApiClient.getAuthStatus();
      isLoggedIn.value = status['loggedIn'] as bool? ?? false;
      site.value = status['site'] as String? ?? 'EH';

      final settings = await backendApiClient.getSettings();
      serverInfo.value = settings['server'] as Map<String, dynamic>? ?? {};

      if (settings.containsKey('userSetting')) {
        final user = settings['userSetting'];
        if (user is Map) {
          userName.value = user['userName'] as String? ?? '';
        }
      }
    } catch (e) {
      debugPrint('Failed to load settings: $e');
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> login() async {
    final user = loginUserController.text.trim();
    final pass = loginPassController.text.trim();
    if (user.isEmpty || pass.isEmpty) {
      Get.snackbar('common.error'.tr, 'settings.emptyCredentials'.tr,
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    isLoggingIn.value = true;
    try {
      final result = await backendApiClient.login(user, pass);
      if (result['success'] == true) {
        Get.snackbar('common.success'.tr, 'settings.loginSuccess'.tr, snackPosition: SnackPosition.BOTTOM);
        loginUserController.clear();
        loginPassController.clear();
        await _loadStatus();
      } else {
        Get.snackbar('common.failed'.tr, result['message'] ?? 'settings.loginFailed'.tr,
            snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red.withValues(alpha: 0.7));
      }
    } catch (e) {
      Get.snackbar('common.error'.tr, 'settings.loginError'.trParams({'error': '$e'}),
          snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red.withValues(alpha: 0.7));
    } finally {
      isLoggingIn.value = false;
    }
  }

  Future<void> loginWithCookies() async {
    final cookieStr = cookieController.text.trim();
    if (cookieStr.isEmpty) {
      Get.snackbar('common.error'.tr, 'settings.cookieEmpty'.tr, snackPosition: SnackPosition.BOTTOM);
      return;
    }

    try {
      await backendApiClient.setCookies(cookieStr);
      Get.snackbar('common.success'.tr, 'settings.cookieSuccess'.tr, snackPosition: SnackPosition.BOTTOM);
      cookieController.clear();
      await _loadStatus();
    } catch (e) {
      Get.snackbar('common.error'.tr, 'settings.cookieFailed'.trParams({'error': '$e'}),
          snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red.withValues(alpha: 0.7));
    }
  }

  Future<void> logout() async {
    try {
      await backendApiClient.logout();
      await _loadStatus();
      Get.snackbar('common.success'.tr, 'settings.logoutSuccess'.tr, snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('common.error'.tr, 'settings.logoutFailed'.trParams({'error': '$e'}), snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> switchSite(String newSite) async {
    try {
      await backendApiClient.setSite(newSite);
      site.value = newSite;
    } catch (e) {
      Get.snackbar('common.error'.tr, 'settings.switchSiteFailed'.trParams({'error': '$e'}), snackPosition: SnackPosition.BOTTOM);
    }
  }
}

class WebSettingsPage extends GetView<WebSettingsController> {
  const WebSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('settings.title'.tr)),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildAccountSection(context),
                  const SizedBox(height: 24),
                  _buildSiteSection(context),
                  const SizedBox(height: 24),
                  _buildAppearanceSection(context),
                  const SizedBox(height: 24),
                  _buildServerInfoSection(context),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildAccountSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('settings.account'.tr, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Obx(() => controller.isLoggedIn.value
                ? _buildLoggedInView(context)
                : _buildLoginForm(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildLoggedInView(BuildContext context) {
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

  Widget _buildLoginForm(BuildContext context) {
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
            border: OutlineInputBorder(),
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
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => controller.login(),
              ),
              const SizedBox(height: 8),
              Obx(() => OutlinedButton(
                onPressed: controller.isLoggingIn.value ? null : controller.login,
                child: controller.isLoggingIn.value
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text('settings.login'.tr),
              )),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSiteSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('settings.site'.tr, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Obx(() => SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'EH', label: Text('E-Hentai')),
                ButtonSegment(value: 'EX', label: Text('ExHentai')),
              ],
              selected: {controller.site.value},
              onSelectionChanged: (selected) => controller.switchSite(selected.first),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildAppearanceSection(BuildContext context) {
    final tc = Get.find<ThemeController>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('settings.appearance'.tr, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text('settings.themeMode'.tr, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Obx(() => SegmentedButton<ThemeMode>(
              segments: [
                ButtonSegment(value: ThemeMode.system, label: Text('settings.system'.tr), icon: const Icon(Icons.settings_brightness)),
                ButtonSegment(value: ThemeMode.light, label: Text('settings.light'.tr), icon: const Icon(Icons.light_mode)),
                ButtonSegment(value: ThemeMode.dark, label: Text('settings.dark'.tr), icon: const Icon(Icons.dark_mode)),
              ],
              selected: {tc.themeMode.value},
              onSelectionChanged: (selected) => tc.setThemeMode(selected.first),
            )),
            const SizedBox(height: 16),
            Text('settings.accentColor'.tr, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            Obx(() => Wrap(
              spacing: 8,
              runSpacing: 8,
              children: ThemeController.seedColors.map((color) {
                final isSelected = tc.seedColor.value.toARGB32() == color.toARGB32();
                return GestureDetector(
                  onTap: () => tc.setSeedColor(color),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: isSelected ? Border.all(color: Theme.of(context).colorScheme.onSurface, width: 3) : null,
                    ),
                    child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                  ),
                );
              }).toList(),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildServerInfoSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('settings.serverInfo'.tr, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Obx(() {
              final info = controller.serverInfo;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow('settings.dataDir'.tr, info['dataDir']?.toString() ?? '-'),
                  _infoRow('settings.downloadDir'.tr, info['downloadDir']?.toString() ?? '-'),
                  _infoRow('settings.localGalleryDir'.tr, info['localGalleryDir']?.toString() ?? '-'),
                  if (info['extraScanPaths'] is List && (info['extraScanPaths'] as List).isNotEmpty)
                    _infoRow('settings.extraScanPaths'.tr, (info['extraScanPaths'] as List).join(', ')),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(child: Text(value, style: const TextStyle(color: Colors.grey))),
        ],
      ),
    );
  }
}
