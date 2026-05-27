import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:web/web.dart' as web;

class WebSettingsSecurityPage extends StatefulWidget {
  const WebSettingsSecurityPage({super.key});

  @override
  State<WebSettingsSecurityPage> createState() =>
      _WebSettingsSecurityPageState();
}

class _WebSettingsSecurityPageState extends State<WebSettingsSecurityPage> {
  bool _checking = false;
  bool? _tokenValid;

  @override
  Widget build(BuildContext context) {
    final token = backendApiClient.currentToken ?? '';
    final hasToken = token.isNotEmpty;
    return Scaffold(
      appBar: AppBar(title: Text('settings.menuSecurity'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'settings.webTokenSecurity'.tr,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _statusRow(
                    context,
                    'settings.webTokenSaved'.tr,
                    hasToken
                        ? 'settings.webTokenSavedYes'.tr
                        : 'settings.webTokenSavedNo'.tr,
                    active: hasToken,
                  ),
                  if (hasToken)
                    _statusRow(
                      context,
                      'settings.webTokenFingerprint'.tr,
                      _maskToken(token),
                      active: true,
                    ),
                  if (_tokenValid != null)
                    _statusRow(
                      context,
                      'settings.webTokenVerifyStatus'.tr,
                      _tokenValid!
                          ? 'settings.webTokenValid'.tr
                          : 'settings.webTokenInvalid'.tr,
                      active: _tokenValid!,
                    ),
                  const SizedBox(height: 12),
                  Text(
                    'settings.securityWebBody'.tr,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: hasToken && !_checking ? _verifyCurrentToken : null,
            icon: _checking
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.fact_check_outlined),
            label: Text('settings.verifyCurrentToken'.tr),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: hasToken ? _confirmDisconnect : null,
            icon: const Icon(Icons.logout),
            label: Text('settings.disconnectWebToken'.tr),
          ),
          const SizedBox(height: 16),
          Text(
            'settings.webTokenRotateHint'.tr,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _statusRow(
    BuildContext context,
    String label,
    String value, {
    required bool active,
  }) {
    final color = active ? Theme.of(context).colorScheme.primary : Colors.grey;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Icon(
            active ? Icons.check_circle_outline : Icons.warning_amber_outlined,
            size: 17,
            color: color,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _maskToken(String token) {
    if (token.length <= 16) return '********';
    return '${token.substring(0, 8)}...${token.substring(token.length - 4)}';
  }

  Future<void> _verifyCurrentToken() async {
    final token = backendApiClient.currentToken ?? '';
    if (token.isEmpty) return;
    setState(() => _checking = true);
    final valid = await backendApiClient.verifyToken(token);
    if (!mounted) return;
    setState(() {
      _checking = false;
      _tokenValid = valid;
    });
    Get.snackbar(
      valid ? 'common.success'.tr : 'common.failed'.tr,
      valid ? 'settings.webTokenValid'.tr : 'settings.webTokenInvalid'.tr,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  Future<void> _confirmDisconnect() async {
    final confirmed = await Get.dialog<bool>(
      AlertDialog(
        title: Text('settings.disconnectWebTokenTitle'.tr),
        content: Text('settings.disconnectWebTokenConfirm'.tr),
        actions: [
          TextButton(
            onPressed: () => Get.back(result: false),
            child: Text('common.cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Get.back(result: true),
            child: Text('settings.disconnectWebToken'.tr),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    backendApiClient.clearToken();
    web.window.location.href = '/web/setup';
  }
}
