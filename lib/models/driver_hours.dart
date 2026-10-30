import 'package:cloud_firestore/cloud_firestore.dart';

enum DriverActivity {
  driving('conduccion', 'Conducir'),
  otherWork('otrosTrabajos', 'Otros trabajos'),
  available('disponible', 'Disponible'),
  rest('descanso', 'Descanso');

  const DriverActivity(this.key, this.label);

  final String key;
  final String label;

  static DriverActivity fromKey(Object? key) {
    return DriverActivity.values.firstWhere(
      (activity) => activity.key == key,
      orElse: () => DriverActivity.available,
    );
  }
}

class DriverHours {
  DriverHours({
    this.activity = DriverActivity.available,
    this.drivingSource = 'gps',
    this.activityStartedAt,
    this.lastUpdatedAt,
    this.lastMovementAt,
    this.continuousDrivingSeconds = 0,
    this.dailyDrivingSeconds = 0,
    this.weeklyDrivingSeconds = 0,
    this.previousWeekDrivingSeconds = 0,
    this.extendedDaysThisWeek = 0,
    this.reducedDailyRestsSinceWeeklyRest = 0,
    this.currentDailyExtensionUsed = false,
    this.currentDailyExtensionAllowed = false,
    this.currentRestSeconds = 0,
    this.firstSplitBreakSeconds = 0,
    this.weekKey,
    this.timelineDateKey,
    Map<String, int>? timelineSeconds,
  }) : timelineSeconds = timelineSeconds ?? {};

  static const continuousLimitSeconds = 4 * 60 * 60 + 30 * 60;
  static const dailyLimitSeconds = 9 * 60 * 60;
  static const extendedDailyLimitSeconds = 10 * 60 * 60;
  static const weeklyLimitSeconds = 56 * 60 * 60;
  static const fortnightLimitSeconds = 90 * 60 * 60;
  static const gpsStopGraceSeconds = 2 * 60;
  static const dailyRestSeconds = 9 * 60 * 60;
  static const breakSeconds = 45 * 60;

  DriverActivity activity;
  String drivingSource;
  DateTime? activityStartedAt;
  DateTime? lastUpdatedAt;
  DateTime? lastMovementAt;
  int continuousDrivingSeconds;
  int dailyDrivingSeconds;
  int weeklyDrivingSeconds;
  int previousWeekDrivingSeconds;
  int extendedDaysThisWeek;
  int reducedDailyRestsSinceWeeklyRest;
  bool currentDailyExtensionUsed;
  bool currentDailyExtensionAllowed;
  int currentRestSeconds;
  int firstSplitBreakSeconds;
  String? weekKey;
  String? timelineDateKey;
  final Map<String, int> timelineSeconds;

  int get dailyLimitForCurrentPeriod => currentDailyExtensionAllowed
      ? extendedDailyLimitSeconds
      : dailyLimitSeconds;

  int get minimumDailyRestSeconds => reducedDailyRestsSinceWeeklyRest < 3
      ? dailyRestSeconds
      : 11 * 60 * 60;

  int get drivingSecondsUntilLimit {
    return [
      continuousLimitSeconds - continuousDrivingSeconds,
      dailyLimitForCurrentPeriod - dailyDrivingSeconds,
      weeklyLimitSeconds - weeklyDrivingSeconds,
      fortnightLimitSeconds -
          weeklyDrivingSeconds -
          previousWeekDrivingSeconds,
    ].reduce((a, b) => a < b ? a : b)
        .clamp(0, fortnightLimitSeconds)
        .toInt();
  }

  int get drivingSecondsUntilBreak =>
      (continuousLimitSeconds - continuousDrivingSeconds).clamp(
        0,
        continuousLimitSeconds,
      ).toInt();

  factory DriverHours.fromMap(Map<String, dynamic>? map) {
    if (map == null) return DriverHours();
    int number(String key) => (map[key] as num?)?.toInt() ?? 0;
    int numberWithFallback(String key, String fallbackKey) {
      final value = map[key] ?? map[fallbackKey];
      return value is num ? value.toInt() : 0;
    }

    DateTime? date(String key) {
      final value = map[key];
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    final rawTimeline = map['timelineSeconds'];
    final timeline = <String, int>{};
    if (rawTimeline is Map) {
      for (final entry in rawTimeline.entries) {
        if (entry.value is num) {
          timeline[entry.key.toString()] = (entry.value as num).toInt();
        }
      }
    }

    return DriverHours(
      activity: DriverActivity.fromKey(map['activity']),
      drivingSource: map['drivingSource'] as String? ?? 'gps',
      activityStartedAt: date('activityStartedAt'),
      lastUpdatedAt: date('lastUpdatedAt'),
      lastMovementAt: date('lastMovementAt'),
      continuousDrivingSeconds: number('continuousDrivingSeconds'),
      dailyDrivingSeconds: number('dailyDrivingSeconds'),
      weeklyDrivingSeconds: number('weeklyDrivingSeconds'),
      previousWeekDrivingSeconds: number('previousWeekDrivingSeconds'),
      extendedDaysThisWeek: number('extendedDaysThisWeek'),
      reducedDailyRestsSinceWeeklyRest:
          numberWithFallback(
            'reducedDailyRestsSinceWeeklyRest',
            'reducedDailyRestsThisWeek',
          ),
      currentDailyExtensionUsed: map['currentDailyExtensionUsed'] == true,
      currentDailyExtensionAllowed:
          map['currentDailyExtensionAllowed'] == true,
      currentRestSeconds: number('currentRestSeconds'),
      firstSplitBreakSeconds: number('firstSplitBreakSeconds'),
      weekKey: map['weekKey'] as String?,
      timelineDateKey: map['timelineDateKey'] as String?,
      timelineSeconds: timeline,
    );
  }

  Map<String, dynamic> toMap() => {
    'activity': activity.key,
    'drivingSource': drivingSource,
    'activityStartedAt': activityStartedAt == null
        ? null
        : Timestamp.fromDate(activityStartedAt!),
    'lastUpdatedAt': lastUpdatedAt == null
        ? null
        : Timestamp.fromDate(lastUpdatedAt!),
    'lastMovementAt': lastMovementAt == null
        ? null
        : Timestamp.fromDate(lastMovementAt!),
    'continuousDrivingSeconds': continuousDrivingSeconds,
    'dailyDrivingSeconds': dailyDrivingSeconds,
    'weeklyDrivingSeconds': weeklyDrivingSeconds,
    'previousWeekDrivingSeconds': previousWeekDrivingSeconds,
    'extendedDaysThisWeek': extendedDaysThisWeek,
    'reducedDailyRestsSinceWeeklyRest': reducedDailyRestsSinceWeeklyRest,
    'currentDailyExtensionUsed': currentDailyExtensionUsed,
    'currentDailyExtensionAllowed': currentDailyExtensionAllowed,
    'currentRestSeconds': currentRestSeconds,
    'firstSplitBreakSeconds': firstSplitBreakSeconds,
    'weekKey': weekKey,
    'timelineDateKey': timelineDateKey,
    'timelineSeconds': timelineSeconds,
  };

  void setActivity(DriverActivity next, DateTime now) {
    advance(now);
    if (activity == DriverActivity.rest && next != DriverActivity.rest) {
      _finishRestPeriod();
    }
    activity = next;
    drivingSource = next == DriverActivity.driving ? 'manual' : 'gps';
    activityStartedAt = now;
    if (next == DriverActivity.rest) currentRestSeconds = 0;
    lastUpdatedAt = now;
  }

  void recordMovement(DateTime timestamp) {
    final effectiveTime = lastUpdatedAt != null &&
            timestamp.isBefore(lastUpdatedAt!)
        ? lastUpdatedAt!
        : timestamp;
    advance(effectiveTime);
    if (activity == DriverActivity.rest) _finishRestPeriod();
    if (activity != DriverActivity.driving) {
      activityStartedAt = effectiveTime;
    }
    activity = DriverActivity.driving;
    drivingSource = 'gps';
    lastMovementAt = timestamp;
    lastUpdatedAt = effectiveTime;
  }

  void startRouteTracking(DateTime timestamp) {
    final effectiveTime = lastUpdatedAt != null &&
            lastUpdatedAt!.isAfter(timestamp)
        ? lastUpdatedAt!
        : timestamp;
    continuousDrivingSeconds = 0;
    lastMovementAt = null;
    lastUpdatedAt = effectiveTime;
    if (activity == DriverActivity.driving && drivingSource == 'gps') {
      activity = DriverActivity.available;
      drivingSource = 'gps';
      activityStartedAt = effectiveTime;
    }
  }

  void stopGpsDriving(DateTime timestamp, {bool countUntilStop = true}) {
    if (activity != DriverActivity.driving) return;
    final effectiveTime = lastUpdatedAt != null &&
            lastUpdatedAt!.isAfter(timestamp)
        ? lastUpdatedAt!
        : timestamp;

    if (countUntilStop) {
      advance(effectiveTime);
    } else {
      lastUpdatedAt = effectiveTime;
    }
    activity = DriverActivity.available;
    drivingSource = 'gps';
    activityStartedAt = effectiveTime;
    lastMovementAt = null;
  }

  void advance(DateTime now) {
    final oldUpdate = lastUpdatedAt;
    _rollPeriods(now);
    if (oldUpdate != null) {
      final elapsed = now.difference(oldUpdate).inSeconds;
      if (elapsed > 0) {
        final countable = activity == DriverActivity.driving &&
                drivingSource == 'gps'
            ? _gpsDrivingSeconds(oldUpdate, now)
            : elapsed.clamp(0, 24 * 60 * 60);
        _addActivitySeconds(countable);
      }
    }

    if (activity == DriverActivity.driving &&
        drivingSource == 'gps' &&
        lastMovementAt != null &&
        now.difference(lastMovementAt!).inSeconds > gpsStopGraceSeconds) {
      activity = DriverActivity.available;
      drivingSource = 'gps';
      activityStartedAt = now;
    }
    lastUpdatedAt = now;
  }

  int _gpsDrivingSeconds(DateTime start, DateTime end) {
    final movement = lastMovementAt;
    if (movement == null) return 0;
    final graceEnd = movement.add(
      const Duration(seconds: gpsStopGraceSeconds),
    );
    final effectiveEnd = end.isBefore(graceEnd) ? end : graceEnd;
    final seconds = effectiveEnd.difference(start).inSeconds;
    return seconds.clamp(0, gpsStopGraceSeconds).toInt();
  }

  void _addActivitySeconds(int seconds) {
    if (seconds <= 0) return;
    timelineSeconds[activity.key] =
        (timelineSeconds[activity.key] ?? 0) + seconds;

    if (activity == DriverActivity.driving) {
      continuousDrivingSeconds += seconds;
      dailyDrivingSeconds += seconds;
      weeklyDrivingSeconds += seconds;
      if (!currentDailyExtensionUsed &&
          dailyDrivingSeconds > dailyLimitSeconds) {
        currentDailyExtensionUsed = true;
        currentDailyExtensionAllowed = extendedDaysThisWeek < 2;
        if (currentDailyExtensionAllowed) extendedDaysThisWeek++;
      }
    } else if (activity == DriverActivity.rest) {
      currentRestSeconds += seconds;
      _applyRestThresholds();
    }
  }

  void _applyRestThresholds() {
    if (currentRestSeconds >= breakSeconds) {
      continuousDrivingSeconds = 0;
      firstSplitBreakSeconds = 0;
    } else if (firstSplitBreakSeconds >= 15 * 60 &&
        currentRestSeconds >= 30 * 60) {
      continuousDrivingSeconds = 0;
      firstSplitBreakSeconds = 0;
    }

    if (currentRestSeconds >= 11 * 60 * 60 ||
        (reducedDailyRestsSinceWeeklyRest < 3 &&
            currentRestSeconds >= dailyRestSeconds)) {
      _resetDailyDriving();
    }
    if (currentRestSeconds >= 24 * 60 * 60) {
      reducedDailyRestsSinceWeeklyRest = 0;
    }
  }

  void _finishRestPeriod() {
    if (currentRestSeconds >= breakSeconds) {
      continuousDrivingSeconds = 0;
      firstSplitBreakSeconds = 0;
    } else if (firstSplitBreakSeconds >= 15 * 60 &&
        currentRestSeconds >= 30 * 60) {
      continuousDrivingSeconds = 0;
      firstSplitBreakSeconds = 0;
    } else if (currentRestSeconds >= 15 * 60 &&
        firstSplitBreakSeconds == 0) {
      firstSplitBreakSeconds = currentRestSeconds;
    }
    if (currentRestSeconds >= 11 * 60 * 60) {
      _resetDailyDriving();
    } else if (currentRestSeconds >= dailyRestSeconds &&
        reducedDailyRestsSinceWeeklyRest < 3) {
      _resetDailyDriving();
      reducedDailyRestsSinceWeeklyRest++;
    }
    if (currentRestSeconds >= 24 * 60 * 60) {
      reducedDailyRestsSinceWeeklyRest = 0;
    }
    currentRestSeconds = 0;
  }

  void _resetDailyDriving() {
    dailyDrivingSeconds = 0;
    currentDailyExtensionUsed = false;
    currentDailyExtensionAllowed = false;
  }

  void _rollPeriods(DateTime now) {
    final key = _weekKey(now);
    if (weekKey != key) {
      final previousKey = _weekKey(now.subtract(const Duration(days: 7)));
      previousWeekDrivingSeconds = weekKey == previousKey
          ? weeklyDrivingSeconds
          : 0;
      weeklyDrivingSeconds = 0;
      extendedDaysThisWeek = 0;
      currentDailyExtensionUsed = false;
      currentDailyExtensionAllowed = false;
      weekKey = key;
    }

    final dayKey = _dateKey(now);
    if (timelineDateKey != dayKey) {
      timelineSeconds.clear();
      timelineDateKey = dayKey;
    }
  }

  static String _weekKey(DateTime date) {
    final monday = DateTime(date.year, date.month, date.day)
        .subtract(Duration(days: date.weekday - DateTime.monday));
    return _dateKey(monday);
  }

  static String _dateKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
