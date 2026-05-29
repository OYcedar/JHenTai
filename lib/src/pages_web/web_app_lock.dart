import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:pinput/pinput.dart';
import 'package:web/web.dart' as web;

class WebAppLockController extends GetxController with WidgetsBindingObserver {
  static const _enabledKey = 'jh_web_password_auth_enabled';
  static const _passwordHashKey = 'jh_web_password_hash';
  static const _lockOnResumeKey = 'jh_web_lock_on_resume';
  static const _resumeDelay = Duration(seconds: 3);

  final enabled = false.obs;
  final lockOnResume = false.obs;
  final locked = false.obs;

  DateTime? _pausedAt;

  bool get hasPasswordHash =>
      (web.window.localStorage.getItem(_passwordHashKey) ?? '').isNotEmpty;

  bool get shouldLock =>
      backendApiClient.hasToken && enabled.value && locked.value;

  @override
  void onInit() {
    super.onInit();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!enabled.value || !lockOnResume.value) {
      return;
    }
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _pausedAt = DateTime.now();
      return;
    }
    if (state != AppLifecycleState.resumed) {
      return;
    }
    final pausedAt = _pausedAt;
    _pausedAt = null;
    if (pausedAt == null) {
      return;
    }
    if (DateTime.now().difference(pausedAt) >= _resumeDelay) {
      lock();
    }
  }

  void _load() {
    enabled.value = web.window.localStorage.getItem(_enabledKey) == 'true' &&
        hasPasswordHash;
    lockOnResume.value =
        web.window.localStorage.getItem(_lockOnResumeKey) == 'true';
    locked.value = enabled.value && backendApiClient.hasToken;
  }

  void enableWithPassword(String password) {
    web.window.localStorage.setItem(_passwordHashKey, _hash(password));
    web.window.localStorage.setItem(_enabledKey, 'true');
    enabled.value = true;
    locked.value = false;
  }

  void disablePasswordAuth() {
    web.window.localStorage.removeItem(_enabledKey);
    web.window.localStorage.removeItem(_passwordHashKey);
    enabled.value = false;
    locked.value = false;
  }

  void saveLockOnResume(bool value) {
    web.window.localStorage.setItem(_lockOnResumeKey, value ? 'true' : 'false');
    lockOnResume.value = value;
  }

  void lock() {
    if (enabled.value && backendApiClient.hasToken) {
      locked.value = true;
    }
  }

  bool unlock(String password) {
    final expected = web.window.localStorage.getItem(_passwordHashKey);
    if (expected == null || expected != _hash(password)) {
      return false;
    }
    locked.value = false;
    return true;
  }

  static String _hash(String raw) => md5.convert(utf8.encode(raw)).toString();
}

class WebAppLockGate extends StatelessWidget {
  const WebAppLockGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<WebAppLockController>();
    return Obx(() {
      if (!controller.shouldLock) {
        return child;
      }
      return _WebLockPage(controller: controller);
    });
  }
}

class _WebLockPage extends StatefulWidget {
  const _WebLockPage({required this.controller});

  final WebAppLockController controller;

  @override
  State<_WebLockPage> createState() => _WebLockPageState();
}

class _WebLockPageState extends State<_WebLockPage> {
  final pinController = TextEditingController();
  String hintText = 'localizedReason'.tr;

  @override
  void dispose() {
    pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      child: ColoredBox(
        color: Theme.of(context).colorScheme.surface,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 48,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),
                Pinput(
                  length: 4,
                  controller: pinController,
                  autofocus: true,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  onCompleted: (value) {
                    if (widget.controller.unlock(value)) {
                      return;
                    }
                    setState(() {
                      hintText = 'passwordErrorHint'.tr;
                      pinController.clear();
                    });
                  },
                ),
                const SizedBox(height: 20),
                Text(
                  hintText,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
