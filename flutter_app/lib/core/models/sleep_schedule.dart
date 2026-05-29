class SleepSchedule {
  const SleepSchedule({
    required this.startTime,
    required this.endTime,
  });

  // 24h local wall-clock time, format HH:mm
  final String startTime;
  final String endTime;

  Map<String, dynamic> toMap() {
    return {
      'start_time': startTime,
      'end_time': endTime,
    };
  }
}
