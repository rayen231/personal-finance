import 'package:flutter/material.dart';

/// Consistent color/icon per transaction type, used across the app.
class TypeStyle {
  static Color color(String type) => switch (type) {
        'Expense' => Colors.redAccent,
        'Free Money' => Colors.orangeAccent,
        'Investment' => Colors.teal,
        _ => Colors.grey,
      };

  static IconData icon(String type) => switch (type) {
        'Expense' => Icons.shopping_cart,
        'Free Money' => Icons.celebration,
        'Investment' => Icons.trending_up,
        _ => Icons.receipt_long,
      };
}
