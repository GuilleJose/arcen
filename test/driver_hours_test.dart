import 'package:arcen/models/driver_hours.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final monday = DateTime(2026, 10, 26, 8);

  test(
    'suma conducción manual a los totales y calcula el siguiente límite',
    () {
      final hours = DriverHours();
      hours.setActivity(DriverActivity.driving, monday);
      hours.advance(monday.add(const Duration(hours: 2)));

      expect(
        hours.continuousDrivingSeconds,
        const Duration(hours: 2).inSeconds,
      );
      expect(hours.dailyDrivingSeconds, const Duration(hours: 2).inSeconds);
      expect(hours.weeklyDrivingSeconds, const Duration(hours: 2).inSeconds);
      expect(
        hours.drivingSecondsUntilBreak,
        const Duration(hours: 2, minutes: 30).inSeconds,
      );
    },
  );

  test('una pausa dividida de 15 + 30 minutos reinicia conducción seguida', () {
    final hours = DriverHours();
    hours.setActivity(DriverActivity.driving, monday);
    hours.advance(monday.add(const Duration(hours: 3)));
    hours.setActivity(
      DriverActivity.rest,
      monday.add(const Duration(hours: 3)),
    );
    hours.advance(monday.add(const Duration(hours: 3, minutes: 15)));
    hours.setActivity(
      DriverActivity.available,
      monday.add(const Duration(hours: 3, minutes: 15)),
    );
    hours.setActivity(
      DriverActivity.rest,
      monday.add(const Duration(hours: 3, minutes: 20)),
    );
    hours.advance(monday.add(const Duration(hours: 3, minutes: 50)));

    expect(hours.continuousDrivingSeconds, 0);
    expect(hours.dailyDrivingSeconds, const Duration(hours: 3).inSeconds);
  });

  test('un descanso diario de nueve horas inicia un nuevo período diario', () {
    final hours = DriverHours();
    hours.setActivity(DriverActivity.driving, monday);
    hours.advance(monday.add(const Duration(hours: 5)));
    hours.setActivity(
      DriverActivity.rest,
      monday.add(const Duration(hours: 5)),
    );
    hours.advance(monday.add(const Duration(hours: 14)));

    expect(hours.dailyDrivingSeconds, 0);
    expect(hours.continuousDrivingSeconds, 0);
  });

  test('cuenta las reducciones diarias entre descansos semanales', () {
    final hours = DriverHours(
      dailyDrivingSeconds: const Duration(hours: 5).inSeconds,
      weekKey: '2026-10-26',
    );
    hours.setActivity(DriverActivity.rest, monday);
    hours.advance(monday.add(const Duration(hours: 9)));

    expect(hours.dailyDrivingSeconds, 0);
    expect(hours.reducedDailyRestsSinceWeeklyRest, 0);

    hours.setActivity(
      DriverActivity.available,
      monday.add(const Duration(hours: 9)),
    );
    expect(hours.reducedDailyRestsSinceWeeklyRest, 1);
  });

  test('requiere once horas tras agotar tres descansos reducidos', () {
    final hours = DriverHours(
      dailyDrivingSeconds: const Duration(hours: 5).inSeconds,
      reducedDailyRestsSinceWeeklyRest: 3,
      weekKey: '2026-10-26',
    );
    hours.setActivity(DriverActivity.rest, monday);
    hours.advance(monday.add(const Duration(hours: 9)));
    expect(hours.dailyDrivingSeconds, const Duration(hours: 5).inSeconds);

    hours.advance(monday.add(const Duration(hours: 11)));
    expect(hours.dailyDrivingSeconds, 0);

    hours.setActivity(
      DriverActivity.available,
      monday.add(const Duration(hours: 11)),
    );
    expect(hours.reducedDailyRestsSinceWeeklyRest, 3);
  });

  test('un descanso semanal de al menos 24 horas reinicia las reducciones', () {
    final hours = DriverHours(
      reducedDailyRestsSinceWeeklyRest: 3,
      weekKey: '2026-10-26',
    );
    hours.setActivity(DriverActivity.rest, monday);
    hours.advance(monday.add(const Duration(hours: 24)));

    expect(hours.reducedDailyRestsSinceWeeklyRest, 0);
  });

  test('el GPS inicia y detiene la conducción tras perder movimiento', () {
    final hours = DriverHours();
    hours.recordMovement(monday);
    hours.advance(monday.add(const Duration(minutes: 1)));
    hours.advance(monday.add(const Duration(minutes: 3)));

    expect(hours.activity, DriverActivity.available);
    expect(
      hours.continuousDrivingSeconds,
      const Duration(minutes: 2).inSeconds,
    );
  });

  test('una ruta nueva reinicia la conducción seguida anterior', () {
    final hours = DriverHours(
      activity: DriverActivity.driving,
      drivingSource: 'gps',
      activityStartedAt: monday,
      lastUpdatedAt: monday,
      lastMovementAt: monday,
      continuousDrivingSeconds: const Duration(hours: 1).inSeconds,
      dailyDrivingSeconds: const Duration(hours: 1).inSeconds,
    );

    hours.startRouteTracking(monday.add(const Duration(hours: 2)));

    expect(hours.activity, DriverActivity.available);
    expect(hours.continuousDrivingSeconds, 0);
    expect(hours.dailyDrivingSeconds, const Duration(hours: 1).inSeconds);
    expect(hours.lastUpdatedAt, monday.add(const Duration(hours: 2)));

    hours.recordMovement(monday.add(const Duration(hours: 2, minutes: 1)));
    hours.advance(monday.add(const Duration(hours: 2, minutes: 2)));
    expect(
      hours.continuousDrivingSeconds,
      const Duration(minutes: 1).inSeconds,
    );
  });

  test('detener el GPS pausa la conducción hasta que haya movimiento', () {
    final hours = DriverHours();
    hours.recordMovement(monday);
    hours.advance(monday.add(const Duration(minutes: 1)));
    hours.stopGpsDriving(monday.add(const Duration(minutes: 1)));
    hours.advance(monday.add(const Duration(minutes: 3)));

    expect(hours.activity, DriverActivity.available);
    expect(
      hours.continuousDrivingSeconds,
      const Duration(minutes: 1).inSeconds,
    );

    hours.recordMovement(monday.add(const Duration(minutes: 3)));
    hours.advance(monday.add(const Duration(minutes: 4)));
    expect(
      hours.continuousDrivingSeconds,
      const Duration(minutes: 2).inSeconds,
    );
  });

  test('permite dos ampliaciones diarias de diez horas por semana', () {
    final hours = DriverHours(
      dailyDrivingSeconds: const Duration(hours: 9).inSeconds,
      weeklyDrivingSeconds: const Duration(hours: 20).inSeconds,
    );
    hours.setActivity(DriverActivity.driving, monday);
    hours.advance(monday.add(const Duration(hours: 1)));

    expect(hours.extendedDaysThisWeek, 1);
    expect(hours.currentDailyExtensionAllowed, isTrue);
    expect(
      hours.dailyLimitForCurrentPeriod,
      DriverHours.extendedDailyLimitSeconds,
    );
  });

  test('el límite diario se amplía solo al usar una ampliación', () {
    final hours = DriverHours();
    expect(hours.dailyLimitForCurrentPeriod, DriverHours.dailyLimitSeconds);

    hours.setActivity(DriverActivity.driving, monday);
    hours.advance(monday.add(const Duration(hours: 9, minutes: 1)));

    expect(hours.currentDailyExtensionAllowed, isTrue);
    expect(
      hours.dailyLimitForCurrentPeriod,
      DriverHours.extendedDailyLimitSeconds,
    );
  });

  test('mantiene los datos al serializar y deserializar', () {
    final hours = DriverHours();
    hours.setActivity(DriverActivity.otherWork, monday);
    hours.advance(monday.add(const Duration(minutes: 25)));

    final restored = DriverHours.fromMap(hours.toMap());

    expect(restored.activity, DriverActivity.otherWork);
    expect(restored.timelineSeconds['otrosTrabajos'], 25 * 60);
    expect(restored.weeklyDrivingSeconds, 0);
  });
}
