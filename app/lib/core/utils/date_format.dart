class NoteDateFormatter {
  NoteDateFormatter._();

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static String relative(DateTime dt, {DateTime? now}) {
    final n = now ?? DateTime.now();
    final today = DateTime(n.year, n.month, n.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (n.year == dt.year) return '${_months[dt.month - 1]} ${dt.day}';
    return '${_months[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  static String timeOfDay(DateTime dt) {
    var h = dt.hour;
    final m = dt.minute;
    final suffix = h >= 12 ? 'PM' : 'AM';
    h = h % 12;
    if (h == 0) h = 12;
    return '$h:${m.toString().padLeft(2, '0')} $suffix';
  }

  static String dateTime(DateTime dt) =>
      '${relative(dt)}, ${timeOfDay(dt)}';
}
