import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:web/web.dart' as web;

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

  /// `null` = always show folder picker; `0`–`9` = long-press heart on gallery detail adds to this slot.
  final defaultFavoriteSlot = Rxn<int>();

  static const _defaultFavCatKey = 'jh_web_default_favcat';

  @override
  void onInit() {
    super.onInit();
    _loadDefaultFavoriteSlot();
    _loadStatus();
  }

  void _loadDefaultFavoriteSlot() {
    final raw = web.window.localStorage.getItem(_defaultFavCatKey);
    if (raw == null || raw.isEmpty) {
      defaultFavoriteSlot.value = null;
      return;
    }
    final n = int.tryParse(raw);
    defaultFavoriteSlot.value = (n != null && n >= 0 && n <= 9) ? n : null;
  }

  void setDefaultFavoriteSlot(int? slot) {
    defaultFavoriteSlot.value = slot;
    if (slot == null) {
      web.window.localStorage.removeItem(_defaultFavCatKey);
    } else {
      web.window.localStorage.setItem(_defaultFavCatKey, '$slot');
    }
  }

  Future<void> refreshStatus() => _loadStatus();

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
      loadCookieStatus();
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

  final cookieStatus = ''.obs;

  Future<void> loadCookieStatus() async {
    try {
      final cookies = await backendApiClient.getCookies();
      final list = cookies['cookies'] as List? ?? [];
      final names = list.map((c) => (c as Map)['name']?.toString() ?? '').where((n) => n.isNotEmpty).toList();
      final hasIgneous = names.contains('igneous');
      final hasMemberId = names.contains('ipb_member_id');
      final hasPassHash = names.contains('ipb_pass_hash');
      if (hasMemberId && hasPassHash) {
        cookieStatus.value = hasIgneous ? 'settings.cookieStatusFull'.tr : 'settings.cookieStatusNoIgneous'.tr;
      } else {
        cookieStatus.value = 'settings.cookieStatusNone'.tr;
      }
    } catch (_) {
      cookieStatus.value = '';
    }
  }

  Future<void> switchSite(String newSite) async {
    try {
      final result = await backendApiClient.setSite(newSite);
      if (result['success'] == true) {
        site.value = newSite;
        Get.snackbar('common.success'.tr, 'settings.siteSwitched'.trParams({'site': newSite}), snackPosition: SnackPosition.BOTTOM);
      } else {
        final error = result['error']?.toString() ?? 'settings.switchSiteFailed'.tr;
        Get.snackbar('common.error'.tr, error,
            snackPosition: SnackPosition.BOTTOM, backgroundColor: Colors.red.withValues(alpha: 0.7));
      }
    } catch (e) {
      Get.snackbar('common.error'.tr, 'settings.switchSiteFailed'.trParams({'error': '$e'}), snackPosition: SnackPosition.BOTTOM);
    }
  }
}

void ensureWebSettingsController() {
  if (!Get.isRegistered<WebSettingsController>()) {
    Get.put(WebSettingsController());
  }
}
