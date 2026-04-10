import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';

class WebSettingsAboutPage extends StatelessWidget {
  const WebSettingsAboutPage({super.key});

  static const _author = '酱天小禽兽(JTMonster)';
  static const _telegram = 'https://t.me/+PindoE9yvIpmOWI9';
  static const _gitUpstream = 'https://github.com/jiangtian616/JHenTai';
  static const _helpPage = 'https://github.com/jiangtian616/JHenTai/wiki';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('JHenTai')),
      body: FutureBuilder<PackageInfo>(
        future: PackageInfo.fromPlatform(),
        builder: (context, snap) {
          final version = snap.data?.version ?? '—';
          final build = snap.data?.buildNumber ?? '—';
          final verLine = version == '—'
              ? '1.0.0'
              : (build == '—' ? version : '$version+$build');
          return ListView(
            padding: const EdgeInsets.only(top: 16),
            children: [
              ListTile(
                title: Text('settings.aboutVersionLabel'.tr),
                subtitle: Text(verLine),
              ),
              ListTile(
                title: Text('settings.aboutAuthorLabel'.tr),
                subtitle: SelectableText(_author),
              ),
              ListTile(
                title: const Text('GitHub'),
                subtitle: SelectableText(_gitUpstream),
                onTap: () => launchUrlString(_gitUpstream, mode: LaunchMode.externalApplication),
              ),
              ListTile(
                title: Text('settings.aboutTelegramTitle'.tr),
                subtitle: Text('${'settings.aboutTelegramHint'.tr}\n$_telegram'),
                onTap: () => launchUrlString(_telegram, mode: LaunchMode.externalApplication),
              ),
              ListTile(
                title: Text('settings.aboutQA'.tr),
                subtitle: SelectableText(_helpPage),
                onTap: () => launchUrlString(_helpPage, mode: LaunchMode.externalApplication),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'settings.aboutWebForkNote'.tr,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
