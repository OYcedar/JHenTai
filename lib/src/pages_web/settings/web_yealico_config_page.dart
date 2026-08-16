import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_scroll_to_top.dart';
import 'package:web/web.dart' as web;

/// Yealico 阅读器配置页：下载/复制可导入的站点规则（含服务器地址与 reader token）。
///
/// 按 Yealico 官方导入流程：JSON 粘贴到规则编辑器导入；
/// 二维码由 Yealico 内部生成（规则编辑器 → Generate QR Code）供其他设备扫描。
class WebYealicoConfigPage extends StatefulWidget {
  const WebYealicoConfigPage({super.key});

  @override
  State<WebYealicoConfigPage> createState() => _WebYealicoConfigPageState();
}

class _WebYealicoConfigPageState extends State<WebYealicoConfigPage>
    with WebScrollToTopState<WebYealicoConfigPage> {
  Map<String, dynamic>? rule;
  bool loading = true;
  String? error;
  bool rotating = false;

  @override
  void initState() {
    super.initState();
    _loadRule();
  }

  Future<void> _loadRule() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final data = await backendApiClient.fetchReaderSiteRule();
      if (mounted) {
        setState(() {
          rule = data;
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = '$e';
          loading = false;
        });
      }
    }
  }

  Future<void> _rotateRule() async {
    final ok = await Get.dialog<bool>(
      AlertDialog(
        title: Text('yealicoConfigRotate'.tr),
        content: Text('yealicoConfigRotateConfirm'.tr),
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
    if (ok != true || mounted == false) return;

    setState(() => rotating = true);
    try {
      final data = await backendApiClient.rotateReaderToken();
      if (mounted) {
        setState(() {
          rule = data['rule'] is Map
              ? Map<String, dynamic>.from(data['rule'] as Map)
              : rule;
          rotating = false;
        });
        Get.snackbar('common.success'.tr, 'yealicoConfigRotated'.tr,
            duration: const Duration(seconds: 2));
      }
    } catch (e) {
      if (mounted) {
        setState(() => rotating = false);
        Get.snackbar('common.error'.tr, '$e',
            duration: const Duration(seconds: 3));
      }
    }
  }

  Future<void> _copyRule() async {
    if (rule == null) return;
    await Clipboard.setData(ClipboardData(text: jsonEncode(rule)));
    if (mounted) {
      Get.snackbar('common.success'.tr, 'yealicoConfigCopied'.tr,
          duration: const Duration(seconds: 2));
    }
  }

  void _downloadRule() {
    if (rule == null) return;
    final blob = web.Blob([jsonEncode(rule).toJS].toJS,
        web.BlobPropertyBag(type: 'application/json'));
    final objectUrl = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = objectUrl;
    anchor.download = 'jhentai-yealico-rule.json';
    anchor.style.display = 'none';
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(objectUrl);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('yealicoConfigTitle'.tr)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text('yealicoConfigHint'.tr),
            ),
          ),
          const SizedBox(height: 16),
          if (loading)
            const Center(child: CircularProgressIndicator())
          else if (error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text('yealicoConfigLoadFailed'.tr),
                    const SizedBox(height: 8),
                    SelectableText(error!),
                    const SizedBox(height: 8),
                    FilledButton.icon(
                      onPressed: _loadRule,
                      icon: const Icon(Icons.refresh),
                      label: Text('common.retry'.tr),
                    ),
                  ],
                ),
              ),
            )
          else if (rule != null)
            Column(
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'yealicoConfigRuleJson'.tr,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: double.infinity,
                          constraints: const BoxConstraints(maxHeight: 260),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: SelectableText(
                            jsonEncode(rule),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _copyRule,
                                icon: const Icon(Icons.copy, size: 18),
                                label: Text('yealicoConfigCopy'.tr),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _downloadRule,
                                icon: const Icon(Icons.download, size: 18),
                                label: Text('yealicoConfigDownload'.tr),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('yealicoConfigImportSteps'.tr),
                        const SizedBox(height: 4),
                        Text('yealicoConfigQrHint'.tr),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: rotating ? null : _rotateRule,
                  icon: rotating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: Text('yealicoConfigRotate'.tr),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
