import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_app_lock.dart';
import 'package:pinput/pinput.dart';
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
  final WebAppLockController _lockController = Get.find<WebAppLockController>();

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
          Obx(
            () => Card(
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: const Icon(Icons.password_outlined),
                    title: Text('enablePasswordAuth'.tr),
                    subtitle: Text('settings.webPasswordAuthHint'.tr),
                    value: _lockController.enabled.value,
                    onChanged: _handlePasswordAuthChanged,
                  ),
                  if (_lockController.enabled.value) ...[
                    const Divider(height: 1),
                    SwitchListTile(
                      secondary: const Icon(Icons.lock_clock_outlined),
                      title: Text('enableAuthOnResume'.tr),
                      subtitle: Text('enableAuthOnResumeHints'.tr),
                      value: _lockController.lockOnResume.value,
                      onChanged: _lockController.saveLockOnResume,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.pin_outlined),
                      title: Text('settings.changeWebPin'.tr),
                      onTap: _changePassword,
                    ),
                    const Divider(height: 1),
                    ListTile(
                      leading: const Icon(Icons.lock_reset_outlined),
                      title: Text('settings.lockNow'.tr),
                      onTap: _lockController.lock,
                    ),
                  ],
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
    if (token.length <= 16) {
      return '********';
    }
    return '${token.substring(0, 8)}...${token.substring(token.length - 4)}';
  }

  Future<void> _verifyCurrentToken() async {
    final token = backendApiClient.currentToken ?? '';
    if (token.isEmpty) {
      return;
    }
    setState(() => _checking = true);
    final valid = await backendApiClient.verifyToken(token);
    if (!mounted) {
      return;
    }
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
    if (confirmed != true) {
      return;
    }
    backendApiClient.clearToken();
    web.window.location.href = '/web/setup';
  }

  Future<void> _handlePasswordAuthChanged(bool value) async {
    if (!value) {
      final confirmed = await Get.dialog<bool>(
        AlertDialog(
          title: Text('settings.disablePasswordAuthTitle'.tr),
          content: Text('settings.disablePasswordAuthConfirm'.tr),
          actions: [
            TextButton(
              onPressed: () => Get.back(result: false),
              child: Text('common.cancel'.tr),
            ),
            FilledButton(
              onPressed: () => Get.back(result: true),
              child: Text('common.confirm'.tr),
            ),
          ],
        ),
      );
      if (confirmed == true) {
        _lockController.disablePasswordAuth();
      }
      return;
    }

    final password =
        await Get.dialog<String>(const _WebPasswordSettingDialog());
    if (password == null) {
      return;
    }
    _lockController.enableWithPassword(password);
    Get.snackbar(
      'common.success'.tr,
      'settings.passwordAuthEnabled'.tr,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  Future<void> _changePassword() async {
    final password = await Get.dialog<String>(
      _WebPasswordChangeDialog(lockController: _lockController),
    );
    if (password == null) {
      return;
    }
    _lockController.changePassword(password);
    Get.snackbar(
      'common.success'.tr,
      'settings.webPinChanged'.tr,
      snackPosition: SnackPosition.BOTTOM,
    );
  }
}

class _WebPasswordSettingDialog extends StatefulWidget {
  const _WebPasswordSettingDialog();

  @override
  State<_WebPasswordSettingDialog> createState() =>
      _WebPasswordSettingDialogState();
}

class _WebPasswordSettingDialogState extends State<_WebPasswordSettingDialog> {
  final controller = TextEditingController();
  String? firstPassword;
  late String hintText;

  @override
  void initState() {
    super.initState();
    hintText = 'setPasswordHint'.tr;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('enablePasswordAuth'.tr),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Pinput(
            length: 4,
            controller: controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            onCompleted: (value) {
              if (firstPassword == null) {
                setState(() {
                  firstPassword = value;
                  hintText = 'confirmPasswordHint'.tr;
                  controller.clear();
                });
                return;
              }
              if (firstPassword == value) {
                Get.back(result: value);
                return;
              }
              setState(() {
                firstPassword = null;
                hintText = 'passwordNotMatchHint'.tr;
                controller.clear();
              });
            },
          ),
          const SizedBox(height: 16),
          Text(hintText, textAlign: TextAlign.center),
        ],
      ),
      actions: [
        TextButton(
          onPressed: Get.back,
          child: Text('common.cancel'.tr),
        ),
      ],
    );
  }
}

class _WebPasswordChangeDialog extends StatefulWidget {
  const _WebPasswordChangeDialog({required this.lockController});

  final WebAppLockController lockController;

  @override
  State<_WebPasswordChangeDialog> createState() =>
      _WebPasswordChangeDialogState();
}

class _WebPasswordChangeDialogState extends State<_WebPasswordChangeDialog> {
  final controller = TextEditingController();
  String? firstPassword;
  var step = _WebPasswordChangeStep.current;
  late String hintText;

  @override
  void initState() {
    super.initState();
    hintText = 'settings.currentWebPinHint'.tr;
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('settings.changeWebPin'.tr),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Pinput(
            length: 4,
            controller: controller,
            autofocus: true,
            obscureText: true,
            keyboardType: TextInputType.number,
            onCompleted: _handleCompleted,
          ),
          const SizedBox(height: 16),
          Text(hintText, textAlign: TextAlign.center),
        ],
      ),
      actions: [
        TextButton(
          onPressed: Get.back,
          child: Text('common.cancel'.tr),
        ),
      ],
    );
  }

  void _handleCompleted(String value) {
    switch (step) {
      case _WebPasswordChangeStep.current:
        if (!widget.lockController.verifyPassword(value)) {
          setState(() {
            hintText = 'passwordErrorHint'.tr;
            controller.clear();
          });
          return;
        }
        setState(() {
          step = _WebPasswordChangeStep.newPassword;
          hintText = 'settings.newWebPinHint'.tr;
          controller.clear();
        });
        return;
      case _WebPasswordChangeStep.newPassword:
        setState(() {
          firstPassword = value;
          step = _WebPasswordChangeStep.confirm;
          hintText = 'confirmPasswordHint'.tr;
          controller.clear();
        });
        return;
      case _WebPasswordChangeStep.confirm:
        if (firstPassword == value) {
          Get.back(result: value);
          return;
        }
        setState(() {
          firstPassword = null;
          step = _WebPasswordChangeStep.newPassword;
          hintText = 'passwordNotMatchHint'.tr;
          controller.clear();
        });
        return;
    }
  }
}

enum _WebPasswordChangeStep {
  current,
  newPassword,
  confirm,
}
