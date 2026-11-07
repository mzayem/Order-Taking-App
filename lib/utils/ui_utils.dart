import 'package:flutter/material.dart';

import '../widgets/app_toast.dart';

class UiUtils {
  /// Kept for existing callers; shows the animated [AppToast].
  static void showBeautifulSnackBar(BuildContext context, String message,
      {bool isSuccess = true}) {
    AppToast.show(context, message,
        type: isSuccess ? ToastType.success : ToastType.error);
  }
}
