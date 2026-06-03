import 'package:flutter/material.dart';
import 'package:get/get.dart';

const webDownloadPriorityLow = 0;
const webDownloadPriorityMedium = 5;
const webDownloadPriorityHigh = 10;

int normalizeWebDownloadPriority(int value) {
  if (value <= webDownloadPriorityLow) {
    return webDownloadPriorityLow;
  }
  if (value >= webDownloadPriorityHigh) {
    return webDownloadPriorityHigh;
  }
  return webDownloadPriorityMedium;
}

String webDownloadPriorityLabel(int value) {
  return switch (normalizeWebDownloadPriority(value)) {
    webDownloadPriorityHigh => 'downloads.priorityHigh'.tr,
    webDownloadPriorityMedium => 'downloads.priorityMedium'.tr,
    _ => 'downloads.priorityLow'.tr,
  };
}

class WebDownloadPrioritySelector extends StatelessWidget {
  const WebDownloadPrioritySelector({
    super.key,
    required this.selectedPriority,
    required this.onSelected,
    this.labelText,
  });

  final int selectedPriority;
  final ValueChanged<int> onSelected;
  final String? labelText;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<int>(
      initialValue: normalizeWebDownloadPriority(selectedPriority),
      decoration: InputDecoration(
        labelText: labelText ?? 'downloads.setPriority'.tr,
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final priority in const [
          webDownloadPriorityLow,
          webDownloadPriorityMedium,
          webDownloadPriorityHigh,
        ])
          DropdownMenuItem(
            value: priority,
            child: Text(webDownloadPriorityLabel(priority)),
          ),
      ],
      onChanged: (value) {
        if (value != null) {
          onSelected(value);
        }
      },
    );
  }
}
