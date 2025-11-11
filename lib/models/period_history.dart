class PeriodHistory {
  final String id;
  final DateTime startDate;
  final DateTime endDate;
  final List<String> transactionIds;
  final String name;

  PeriodHistory({
    required this.id,
    required this.startDate,
    required this.endDate,
    required this.transactionIds,
    this.name = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'startDate': '${startDate.year.toString().padLeft(4, '0')}-'
          '${startDate.month.toString().padLeft(2, '0')}-'
          '${startDate.day.toString().padLeft(2, '0')}',
      'endDate': '${endDate.year.toString().padLeft(4, '0')}-'
          '${endDate.month.toString().padLeft(2, '0')}-'
          '${endDate.day.toString().padLeft(2, '0')}',
      'transactionIds': transactionIds,
      'name': name,
    };
  }

  factory PeriodHistory.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic dateValue) {
      DateTime dateTime;
      if (dateValue is String) {
        if (dateValue.contains('T') && dateValue.contains('Z')) {
          dateTime = DateTime.parse(dateValue).toLocal();
        } else if (dateValue.contains('T')) {
          dateTime = DateTime.parse(dateValue);
        } else {
          final parts = dateValue.split('-');
          if (parts.length == 3) {
            dateTime = DateTime(
              int.parse(parts[0]),
              int.parse(parts[1]),
              int.parse(parts[2]),
            );
          } else {
            dateTime = DateTime.parse(dateValue);
          }
        }
      } else if (dateValue is Map) {
        final dateStr = dateValue['\$date'] as String? ?? dateValue.toString();
        if (dateStr.contains('T') && dateStr.contains('Z')) {
          dateTime = DateTime.parse(dateStr).toLocal();
        } else {
          dateTime = DateTime.parse(dateStr);
        }
      } else {
        dateTime = dateValue as DateTime;
      }
      return DateTime.utc(dateTime.year, dateTime.month, dateTime.day);
    }

    return PeriodHistory(
      id: json['id'] as String? ?? json['_id']?.toString() ?? '',
      startDate: parseDate(json['startDate']),
      endDate: parseDate(json['endDate']),
      transactionIds: (json['transactionIds'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      name: json['name'] as String? ?? '',
    );
  }
}

