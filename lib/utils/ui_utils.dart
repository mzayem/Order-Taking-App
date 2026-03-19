import 'package:flutter/material.dart';

class UiUtils {
  static void showBeautifulSnackBar(BuildContext context, String message, {bool isSuccess = true}) {
    final backgroundColor = isSuccess ? Colors.teal.shade700 : Colors.red.shade700;
    final icon = isSuccess ? Icons.check_circle_outline : Icons.error_outline;

    final snackBar = SnackBar(
      content: Row(
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
      backgroundColor: backgroundColor,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      margin: const EdgeInsets.all(16),
      duration: const Duration(seconds: 4),
      elevation: 6,
    );

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(snackBar);
  }
}
