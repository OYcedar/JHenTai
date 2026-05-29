import 'package:jhentai/src/enum/config_enum.dart';

/// Plain DTO for local config rows (no Drift types — safe for web + native).
class LocalConfig {
  ConfigEnum configKey;
  String subConfigKey;
  String value;
  String utime;

  LocalConfig({
    required this.configKey,
    required this.subConfigKey,
    required this.value,
    required this.utime,
  });

  Map<String, dynamic> toJson() {
    return {
      'configKey': configKey.key,
      'subConfigKey': subConfigKey,
      'value': value,
      'utime': utime,
    };
  }

  factory LocalConfig.fromJson(Map<String, dynamic> json) {
    return LocalConfig(
      configKey: ConfigEnum.from(json['configKey']),
      subConfigKey: json['subConfigKey'],
      value: json['value'],
      utime: json['utime'],
    );
  }
}
