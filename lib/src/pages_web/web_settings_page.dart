import 'package:flutter/material.dart';
import 'package:get/get.dart';
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
      Get.snackbar('Error', 'Please enter username and password',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    isLoggingIn.value = true;
    try {
      final result = await backendApiClient.login(user, pass);
      if (result['success'] == true) {
        Get.snackbar('Success', 'Login successful', snackPosition: SnackPosition.BOTTOM);
        loginUserController.clear();
        loginPassController.clear();
        await _loadStatus();
      } else {
        Get.snackbar('Failed', result['message'] ?? 'Login failed',
            snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red.withValues(alpha: 0.7));
      }
    } catch (e) {
      Get.snackbar('Error', 'Login failed: $e',
          snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red.withValues(alpha: 0.7));
    } finally {
      isLoggingIn.value = false;
    }
  }

  Future<void> loginWithCookies() async {
    final cookieStr = cookieController.text.trim();
    if (cookieStr.isEmpty) {
      Get.snackbar('Error', 'Please paste cookies', snackPosition: SnackPosition.BOTTOM);
      return;
    }

    try {
      await backendApiClient.setCookies(cookieStr);
      Get.snackbar('Success', 'Cookies set successfully', snackPosition: SnackPosition.BOTTOM);
      cookieController.clear();
      await _loadStatus();
    } catch (e) {
      Get.snackbar('Error', 'Failed to set cookies: $e',
          snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red.withValues(alpha: 0.7));
    }
  }

  Future<void> logout() async {
    try {
      await backendApiClient.logout();
      await _loadStatus();
      Get.snackbar('Success', 'Logged out', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('Error', 'Logout failed: $e', snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> switchSite(String newSite) async {
    try {
      await backendApiClient.setSite(newSite);
      site.value = newSite;
    } catch (e) {
      Get.snackbar('Error', 'Failed to switch site: $e', snackPosition: SnackPosition.BOTTOM);
    }
  }
}

class WebSettingsPage extends GetView<WebSettingsController> {
  const WebSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
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
            Text('Account', style: Theme.of(context).textTheme.titleLarge),
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
          child: Obx(() => Text('Logged in as: ${controller.userName.value}')),
        ),
        TextButton(
          onPressed: controller.logout,
          child: const Text('Logout'),
        ),
      ],
    );
  }

  Widget _buildLoginForm(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Login with cookies (recommended)', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          'EH forum login is blocked by Cloudflare in server environments. '
          'Please login via browser, then copy cookies here.\n'
          'Steps: Login at e-hentai.org → F12 → Application → Cookies → copy values below.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller.cookieController,
          maxLines: 3,
          decoration: const InputDecoration(
            hintText: 'ipb_member_id=xxx; ipb_pass_hash=xxx; igneous=xxx',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: controller.loginWithCookies,
          child: const Text('Set Cookies'),
        ),
        const Divider(height: 32),
        Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Login with credentials (may fail due to Cloudflare)',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Colors.grey)),
            children: [
              const SizedBox(height: 8),
              TextField(
                controller: controller.loginUserController,
                decoration: const InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller.loginPassController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => controller.login(),
              ),
              const SizedBox(height: 8),
              Obx(() => OutlinedButton(
                onPressed: controller.isLoggingIn.value ? null : controller.login,
                child: controller.isLoggingIn.value
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Login'),
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
            Text('Site', style: Theme.of(context).textTheme.titleLarge),
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

  Widget _buildServerInfoSection(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Server Info', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Obx(() {
              final info = controller.serverInfo;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _infoRow('Data Directory', info['dataDir']?.toString() ?? '-'),
                  _infoRow('Download Directory', info['downloadDir']?.toString() ?? '-'),
                  _infoRow('Local Gallery Dir', info['localGalleryDir']?.toString() ?? '-'),
                  if (info['extraScanPaths'] is List && (info['extraScanPaths'] as List).isNotEmpty)
                    _infoRow('Extra Scan Paths', (info['extraScanPaths'] as List).join(', ')),
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
