import 'package:get/get.dart';
import 'package:jhentai/src/l18n/web_en_US.dart';
import 'package:jhentai/src/l18n/web_zh_CN.dart';
import 'package:jhentai/src/l18n/web_ko_KR.dart';

class WebLocaleText extends Translations {
  @override
  Map<String, Map<String, String>> get keys => {
        'en_US': WebEnUS.keys(),
        'zh_CN': WebZhCN.keys(),
        'zh_TW': WebZhCN.keys(),
        'ko_KR': WebKoKR.keys(),
      };
}
