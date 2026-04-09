import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';

class WebBlockRulesController extends GetxController {
  final rules = <Map<String, dynamic>>[].obs;
  final isLoading = true.obs;

  @override
  void onInit() {
    super.onInit();
    loadRules();
  }

  Future<void> loadRules() async {
    isLoading.value = true;
    try {
      final list = await backendApiClient.listBlockRules();
      rules.value = list.cast<Map<String, dynamic>>();
    } catch (_) {}
    isLoading.value = false;
  }

  Future<void> deleteRule(int id) async {
    try {
      await backendApiClient.deleteBlockRule(id);
      rules.removeWhere((r) => r['id'] == id);
    } catch (_) {}
  }

  Future<void> saveRule({
    int? id,
    String groupId = '',
    required String target,
    required String attribute,
    required String pattern,
    required String expression,
  }) async {
    try {
      await backendApiClient.saveBlockRule(
        id: id, groupId: groupId, target: target,
        attribute: attribute, pattern: pattern, expression: expression,
      );
      await loadRules();
    } catch (_) {}
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
      body: Obx(() {
        if (controller.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (controller.rules.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.block, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                Text('blockRule.empty'.tr, style: const TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }
        final grouped = controller.groupedRules;
        final groupKeys = grouped.keys.toList();
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: groupKeys.length,
          itemBuilder: (context, i) {
            final groupId = groupKeys[i];
            final groupRules = grouped[groupId]!;
            return Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ExpansionTile(
                title: Text(groupId.isEmpty ? 'blockRule.ungrouped'.tr : groupId),
                subtitle: Text('blockRule.ruleCount'.trParams({'count': '${groupRules.length}'})),
                trailing: groupId.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.delete_sweep, size: 20),
                        tooltip: 'blockRule.deleteGroup'.tr,
                        onPressed: () async {
                          await backendApiClient.deleteBlockRuleGroup(groupId);
                          controller.loadRules();
                        },
                      )
                    : null,
                initiallyExpanded: true,
                children: groupRules.map((rule) => _buildRuleTile(context, rule)).toList(),
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
            onPressed: () => controller.deleteRule(rule['id'] as int),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, {Map<String, dynamic>? rule}) {
    final isEdit = rule != null;
    final targets = ['gallery', 'comment'];
    final galleryAttrs = ['title', 'tag', 'uploader', 'category', 'gid'];
    final commentAttrs = ['userName', 'userId', 'score', 'content'];
    final patterns = ['equal', 'like', 'notContain', 'regex', 'gt', 'gte', 'st', 'ste'];

    final selectedTarget = (rule?['target'] as String? ?? 'gallery').obs;
    final selectedAttribute = (rule?['attribute'] as String? ?? 'title').obs;
    final selectedPattern = (rule?['pattern'] as String? ?? 'like').obs;
    final expressionCtrl = TextEditingController(text: rule?['expression'] as String? ?? '');
    final groupIdCtrl = TextEditingController(text: rule?['group_id'] as String? ?? '');

    Get.dialog(
      AlertDialog(
        title: Text(isEdit ? 'blockRule.edit'.tr : 'blockRule.add'.tr),
        content: SizedBox(
          width: 400,
          child: Obx(() {
            final attrs = selectedTarget.value == 'comment' ? commentAttrs : galleryAttrs;
            if (!attrs.contains(selectedAttribute.value)) {
              selectedAttribute.value = attrs.first;
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedTarget.value,
                  decoration: InputDecoration(labelText: 'blockRule.target'.tr),
                  items: targets.map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                  onChanged: (v) => selectedTarget.value = v!,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedAttribute.value,
                  decoration: InputDecoration(labelText: 'blockRule.attribute'.tr),
                  items: attrs.map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
                  onChanged: (v) => selectedAttribute.value = v!,
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: selectedPattern.value,
                  decoration: InputDecoration(labelText: 'blockRule.pattern'.tr),
                  items: patterns.map((p) => DropdownMenuItem(value: p, child: Text(p))).toList(),
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
          TextButton(onPressed: () => Get.back(), child: Text('common.cancel'.tr)),
          FilledButton(
            onPressed: () {
              controller.saveRule(
                id: rule?['id'] as int?,
                groupId: groupIdCtrl.text.trim(),
                target: selectedTarget.value,
                attribute: selectedAttribute.value,
                pattern: selectedPattern.value,
                expression: expressionCtrl.text.trim(),
              );
              Get.back();
            },
            child: Text('common.save'.tr),
          ),
        ],
      ),
    );
  }
}
