import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/pages_web/web_scroll_to_top.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher_string.dart';

class WebSettingsAboutPage extends StatefulWidget {
  const WebSettingsAboutPage({super.key});

  @override
  State<WebSettingsAboutPage> createState() => _WebSettingsAboutPageState();
}

class _WebSettingsAboutPageState extends State<WebSettingsAboutPage>
    with WebScrollToTopState<WebSettingsAboutPage> {
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
            controller: scrollController,
            padding: const EdgeInsets.only(top: 16),
            children: [
              ListTile(
                title: Text('settings.aboutVersionLabel'.tr),
                subtitle: Text(verLine),
              ),
              ListTile(
                title: Text('settings.aboutAuthorLabel'.tr),
                subtitle: const SelectableText(_author),
              ),
              ListTile(
                title: const Text('GitHub'),
                subtitle: const SelectableText(_gitUpstream),
                onTap: () => launchUrlString(
                  _gitUpstream,
                  mode: LaunchMode.externalApplication,
                ),
              ),
              ListTile(
                title: Text('settings.aboutTelegramTitle'.tr),
                subtitle:
                    Text('${'settings.aboutTelegramHint'.tr}\n$_telegram'),
                onTap: () => launchUrlString(
                  _telegram,
                  mode: LaunchMode.externalApplication,
                ),
              ),
              ListTile(
                title: Text('settings.aboutQA'.tr),
                subtitle: const SelectableText(_helpPage),
                onTap: () => launchUrlString(
                  _helpPage,
                  mode: LaunchMode.externalApplication,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'settings.aboutWebForkNote'.tr,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: Colors.grey),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: buildScrollToTopFab(),
    );
  }
}
