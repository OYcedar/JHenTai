import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';
import 'package:jhentai/src/pages_web/web_scroll_to_top.dart';

class WebBlockRulesController extends GetxController
    with WebScrollToTopControllerMixin {
  final rules = <Map<String, dynamic>>[].obs;
  final isLoading = true.obs;
  final errorMessage = ''.obs;

  @override
  void onInit() {
    super.onInit();
    bindScrollToTop();
    loadRules();
  }

  @override
  void onClose() {
    unbindScrollToTop();
    super.onClose();
  }

  Future<bool> loadRules() async {
    resetScrollToTopState();
    isLoading.value = true;
    errorMessage.value = '';
    try {
      final list = await backendApiClient.listBlockRules();
      rules.value = list.cast<Map<String, dynamic>>();
      return true;
    } catch (e) {
      errorMessage.value = 'blockRule.loadFailed'.trParams({'error': '$e'});
      return false;
    } finally {
      isLoading.value = false;
    }
  }

  Future<bool> deleteRule(int id) async {
    try {
      await backendApiClient.deleteBlockRule(id);
      rules.removeWhere((r) => r['id'] == id);
      Get.snackbar('common.success'.tr, 'blockRule.deleteSuccess'.tr);
      return true;
    } catch (e) {
      Get.snackbar(
        'common.error'.tr,
        'blockRule.deleteFailed'.trParams({'error': '$e'}),
      );
      return false;
    }
  }

  Future<bool> deleteGroup(String groupId) async {
    try {
      await backendApiClient.deleteBlockRuleGroup(groupId);
      final loaded = await loadRules();
      if (!loaded) {
        return false;
      }
      Get.snackbar('common.success'.tr, 'blockRule.deleteSuccess'.tr);
      return true;
    } catch (e) {
      Get.snackbar(
        'common.error'.tr,
        'blockRule.deleteFailed'.trParams({'error': '$e'}),
      );
      return false;
    }
  }

  Future<bool> saveRule({
    int? id,
    String groupId = '',
    required String target,
    required String attribute,
    required String pattern,
    required String expression,
  }) async {
    try {
      await backendApiClient.saveBlockRule(
        id: id,
        groupId: groupId,
        target: target,
        attribute: attribute,
        pattern: pattern,
        expression: expression,
      );
      final loaded = await loadRules();
      if (!loaded) {
        return false;
      }
      Get.snackbar('common.success'.tr, 'blockRule.saveSuccess'.tr);
      return true;
    } catch (e) {
      Get.snackbar(
        'common.error'.tr,
        'blockRule.saveFailed'.trParams({'error': '$e'}),
      );
      return false;
    }
  }

  Map<String, List<Map<String, dynamic>>> get groupedRules {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final rule in rules) {
      final gid = (rule['group_id'] as String?) ?? '';
      groups.putIfAbsent(gid, () => []).add(rule);
    }
    return groups;
  }
}

class WebBlockRulesPage extends GetView<WebBlockRulesController> {
  const WebBlockRulesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('blockRule.title'.tr),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'blockRule.add'.tr,
            onPressed: () => _showEditDialog(context),
          ),
        ],
      ),
      floatingActionButton: Obx(
        () => buildWebScrollToTopFab(
          visible: controller.showScrollToTop.value,
          onPressed: controller.scrollToTop,
        ),
      ),
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.errorMessage.isNotEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 48,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    controller.errorMessage.value,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: controller.loadRules,
                    icon: const Icon(Icons.refresh),
                    label: Text('common.retry'.tr),
                  ),
                ],
              ),
            ),
          );
        }
        if (controller.rules.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.block, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                Text(
                  'blockRule.empty'.tr,
                  style: const TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }
        final grouped = controller.groupedRules;
        final groupKeys = grouped.keys.toList();
        return ListView.builder(
          controller: controller.scrollController,
          padding: const EdgeInsets.all(16),
          itemCount: groupKeys.length,
          itemBuilder: (context, i) {
            final groupId = groupKeys[i];
            final groupRules = grouped[groupId]!;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ExpansionTile(
                title:
                    Text(groupId.isEmpty ? 'blockRule.ungrouped'.tr : groupId),
                subtitle: Text(
                  'blockRule.ruleCount'
                      .trParams({'count': '${groupRules.length}'}),
                ),
                trailing: groupId.isNotEmpty
                    ? Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            icon:
                                const Icon(Icons.add_circle_outline, size: 20),
                            tooltip: 'blockRule.addCondition'.tr,
                            onPressed: () => _showEditDialog(
                              context,
                              groupId: groupId,
                              target: groupRules.first['target']?.toString(),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete_sweep, size: 20),
                            tooltip: 'blockRule.deleteGroup'.tr,
                            onPressed: () => _confirmDeleteGroup(
                              context,
                              groupId,
                              groupRules.length,
                            ),
                          ),
                        ],
                      )
                    : null,
                initiallyExpanded: true,
                children: groupRules
                    .map((rule) => _buildRuleTile(context, rule))
                    .toList(),
              ),
            );
          },
        );
      }),
    );
  }

  Widget _buildRuleTile(BuildContext context, Map<String, dynamic> rule) {
    final target = rule['target'] ?? 'gallery';
    final attribute = rule['attribute'] ?? '';
    final pattern = rule['pattern'] ?? '';
    final expression = rule['expression'] ?? '';
    return ListTile(
      dense: true,
      title: Text('$target.$attribute $pattern "$expression"',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.edit, size: 18),
            onPressed: () => _showEditDialog(context, rule: rule),
          ),
          IconButton(
            icon: const Icon(Icons.delete, size: 18, color: Colors.red),
            onPressed: () => _confirmDeleteRule(context, rule),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDeleteGroup(
    BuildContext context,
    String groupId,
    int count,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('blockRule.deleteGroupTitle'.tr),
        content: Text(
          'blockRule.deleteGroupConfirm'.trParams({
            'group': groupId,
            'count': '$count',
          }),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('common.delete'.tr),
          ),
        ],
      ),
    );
    if (ok == true) {
      await controller.deleteGroup(groupId);
    }
  }

  Future<void> _confirmDeleteRule(
    BuildContext context,
    Map<String, dynamic> rule,
  ) async {
    final id = (rule['id'] as num?)?.toInt();
    if (id == null) {
      return;
    }
    final label = _ruleLabel(rule);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('blockRule.deleteRuleTitle'.tr),
        content: Text(
          'blockRule.deleteRuleConfirm'.trParams({'rule': label}),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('common.delete'.tr),
          ),
        ],
      ),
    );
    if (ok == true) {
      await controller.deleteRule(id);
    }
  }

  String _ruleLabel(Map<String, dynamic> rule) {
    final target = rule['target']?.toString() ?? 'gallery';
    final attribute = rule['attribute']?.toString() ?? '';
    final pattern = rule['pattern']?.toString() ?? '';
    final expression = rule['expression']?.toString() ?? '';
    return '$target.$attribute $pattern "$expression"';
  }

  void _showEditDialog(
    BuildContext context, {
    Map<String, dynamic>? rule,
    String? groupId,
    String? target,
  }) {
    final isEdit = rule != null;
    final targets = ['gallery', 'comment'];
    final galleryAttrs = ['title', 'tag', 'uploader', 'category', 'gid'];
    final commentAttrs = ['userName', 'userId', 'score', 'content'];
    final patterns = [
      'equal',
      'like',
      'notContain',
      'regex',
      'gt',
      'gte',
      'st',
      'ste',
    ];

    final selectedTarget =
        (rule?['target'] as String? ?? target ?? 'gallery').obs;
    final selectedAttribute = (rule?['attribute'] as String? ?? 'title').obs;
    final selectedPattern = (rule?['pattern'] as String? ?? 'like').obs;
    final expressionCtrl =
        TextEditingController(text: rule?['expression'] as String? ?? '');
    final groupIdCtrl = TextEditingController(
        text: rule?['group_id'] as String? ?? groupId ?? '');

    Get.dialog(
      AlertDialog(
        title: Text(isEdit ? 'blockRule.edit'.tr : 'blockRule.add'.tr),
        content: SizedBox(
          width: 400,
          child: Obx(() {
            final attrs =
                selectedTarget.value == 'comment' ? commentAttrs : galleryAttrs;
            if (!attrs.contains(selectedAttribute.value)) {
              selectedAttribute.value = attrs.first;
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedTarget.value,
                  decoration: InputDecoration(labelText: 'blockRule.target'.tr),
                  items: targets
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (v) => selectedTarget.value = v!,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedAttribute.value,
                  decoration:
                      InputDecoration(labelText: 'blockRule.attribute'.tr),
                  items: attrs
                      .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                      .toList(),
                  onChanged: (v) => selectedAttribute.value = v!,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  initialValue: selectedPattern.value,
                  decoration:
                      InputDecoration(labelText: 'blockRule.pattern'.tr),
                  items: patterns
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) => selectedPattern.value = v!,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: expressionCtrl,
                  decoration: InputDecoration(
                    labelText: 'blockRule.expression'.tr,
                    hintText: 'blockRule.expressionHint'.tr,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: groupIdCtrl,
                  decoration: InputDecoration(
                    labelText: 'blockRule.groupId'.tr,
                    hintText: 'blockRule.groupIdHint'.tr,
                  ),
                ),
              ],
            );
          }),
        ),
        actions: [
          TextButton(
            onPressed: Get.back,
            child: Text('common.cancel'.tr),
          ),
          FilledButton(
            onPressed: () async {
              final success = await controller.saveRule(
                id: (rule?['id'] as num?)?.toInt(),
                groupId: groupIdCtrl.text.trim(),
                target: selectedTarget.value,
                attribute: selectedAttribute.value,
                pattern: selectedPattern.value,
                expression: expressionCtrl.text.trim(),
              );
              if (success) {
                Get.back();
              }
            },
            child: Text('common.save'.tr),
          ),
        ],
      ),
    );
  }
}
