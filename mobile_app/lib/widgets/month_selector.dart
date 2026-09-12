import 'package:flutter/material.dart';

const monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// Left/right arrows to swipe between months, shared by every screen that's
/// scoped to a single year+month (Dashboard, Transactions, Income, Plan).
class MonthSelector extends StatelessWidget {
  final int year;
  final int month;
  final ValueChanged<(int year, int month)> onChanged;

  const MonthSelector({
    super.key,
    required this.year,
    required this.month,
    required this.onChanged,
  });

  (int, int) _shift(int delta) {
    final total = (year * 12 + (month - 1)) + delta;
    return (total ~/ 12, (total % 12) + 1);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          onPressed: () => onChanged(_shift(-1)),
        ),
        Text(
          '${monthNames[month - 1]} $year',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          onPressed: () => onChanged(_shift(1)),
        ),
      ],
    );
  }
}
