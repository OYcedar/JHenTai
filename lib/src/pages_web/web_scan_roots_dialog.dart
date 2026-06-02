import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/network/backend_api_client.dart';

Future<void> showWebScanRootsDialog(
  BuildContext context, {
  Future<void> Function()? onChanged,
}) async {
  final pathController = TextEditingController();
  var saving = false;
  var loading = true;
  var initialized = false;
  var roots = <String>[];
  var extraRoots = <String>{};
  String? error;

  String normalizePath(String path) {
    return path.replaceAll(RegExp(r'/+'), '/').replaceAll(RegExp(r'/+$'), '');
  }

  String displayPath(String path) {
    final normalized = normalizePath(path);
    if (normalized.isEmpty) {
      return '/';
    }
    final parts = normalized.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) {
      return normalized;
    }
    return parts.length >= 2
        ? '${parts[parts.length - 2]}/${parts.last}'
        : parts.last;
  }

  Future<void> loadRoots(void Function(void Function()) setDialogState) async {
    setDialogState(() {
      loading = true;
      error = null;
    });
    try {
      final info = await backendApiClient.getLocalGalleryRootInfo();
      final nextRoots = info.roots
          .map(normalizePath)
          .where((path) => path.isNotEmpty)
          .toList()
        ..sort((a, b) => displayPath(a).compareTo(displayPath(b)));
      final nextExtraRoots = info.extraRoots
          .map(normalizePath)
          .where((path) => path.isNotEmpty)
          .toSet();
      setDialogState(() {
        roots = nextRoots;
        extraRoots = nextExtraRoots;
      });
    } catch (e) {
      setDialogState(() => error = '$e');
    } finally {
      setDialogState(() => loading = false);
    }
  }

  Future<void> copyLocalPath(String path) async {
    if (path.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: path));
    Get.snackbar(
      'hasCopiedToClipboard'.tr,
      path,
      snackPosition: SnackPosition.BOTTOM,
    );
  }

  await showDialog<void>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        Future<void> addRoot() async {
          final path = normalizePath(pathController.text.trim());
          if (path.isEmpty) {
            return;
          }
          setDialogState(() => saving = true);
          try {
            await backendApiClient.addLocalGalleryRoot(path);
            pathController.clear();
            await loadRoots(setDialogState);
            await onChanged?.call();
          } catch (e) {
            Get.snackbar(
              'common.error'.tr,
              'local.addScanRootFailed'.trParams({'error': '$e'}),
              snackPosition: SnackPosition.BOTTOM,
            );
          } finally {
            setDialogState(() => saving = false);
          }
        }

        Future<void> deleteRoot(String path) async {
          setDialogState(() => saving = true);
          try {
            await backendApiClient.deleteLocalGalleryRoot(path);
            await loadRoots(setDialogState);
            await onChanged?.call();
          } catch (e) {
            Get.snackbar(
              'common.error'.tr,
              'local.deleteScanRootFailed'.trParams({'error': '$e'}),
              snackPosition: SnackPosition.BOTTOM,
            );
          } finally {
            setDialogState(() => saving = false);
          }
        }

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!initialized) {
            initialized = true;
            loadRoots(setDialogState);
          }
        });

        return AlertDialog(
          title: Text('local.scanRoots'.tr),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'local.scanRootsHint'.tr,
                  style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                        color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: pathController,
                        enabled: !saving,
                        decoration: InputDecoration(
                          labelText: 'local.addScanRoot'.tr,
                          hintText: '/data/local_gallery_extra',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                        onSubmitted: (_) => addRoot(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: saving ? null : addRoot,
                      icon: saving
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add),
                      label: Text('common.add'.tr),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (error != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.error_outline),
                    title: Text(error!),
                    trailing: const Icon(Icons.refresh),
                    onTap: () => loadRoots(setDialogState),
                  )
                else if (roots.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('local.noScanRoots'.tr),
                  )
                else
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: roots.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final root = roots[index];
                        final isExtra = extraRoots.contains(root);
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.folder_special_outlined),
                          title: Text(
                            displayPath(root),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            root,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Wrap(
                            spacing: 4,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.copy),
                                tooltip: 'local.copyPath'.tr,
                                onPressed: () => copyLocalPath(root),
                              ),
                              if (isExtra)
                                IconButton(
                                  icon: const Icon(Icons.delete_outline),
                                  tooltip: 'common.delete'.tr,
                                  onPressed:
                                      saving ? null : () => deleteRoot(root),
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            if (roots.isNotEmpty)
              TextButton.icon(
                icon: const Icon(Icons.copy_all),
                onPressed: () => copyLocalPath(roots.join('\n')),
                label: Text('local.copyAllPaths'.tr),
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('common.close'.tr),
            ),
          ],
        );
      },
    ),
  );
  pathController.dispose();
}
