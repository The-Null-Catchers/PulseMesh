import 'package:flutter/widgets.dart';

import 'mobile_data_controller.dart';

class MobileDataScope extends InheritedNotifier<MobileDataController> {
  const MobileDataScope({
    required MobileDataController controller,
    required super.child,
    super.key,
  }) : super(notifier: controller);

  static MobileDataController of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<MobileDataScope>();
    assert(scope != null, 'MobileDataScope is missing above this context');
    return scope!.notifier!;
  }
}
