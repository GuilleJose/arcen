import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../models/driver_hours.dart';
import '../services/pause_parking_recommendation.dart';

class HoursPage extends StatefulWidget {
  const HoursPage({
    super.key,
    required this.driverId,
    required this.position,
    required this.route,
    required this.routeStartedAt,
    required this.routeDurationSeconds,
    required this.parkings,
    required this.maxParkingDistanceKm,
  });

  final String? driverId;
  final Position? position;
  final List<List<double>> route;
  final DateTime? routeStartedAt;
  final int? routeDurationSeconds;
  final List<Map<String, dynamic>> parkings;
  final double maxParkingDistanceKm;

  @override
  State<HoursPage> createState() => _HoursPageState();
}

class _HoursPageState extends State<HoursPage> {
  static const _blue = Color(0xFF0755A6);
  static const _dark = Color(0xFF07366D);
  static const _muted = Color(0xFF637184);
  static const _border = Color(0xFFDCE3EB);

  DriverHours _hours = DriverHours();
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  Timer? _timer;
  DocumentReference<Map<String, dynamic>>? _driverDocument;
  DateTime? _lastPersistAt;
  Position? _lastPosition;
  Position? _pendingPosition;
  DateTime? _activeRouteStartedAt;
  bool _loading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _listenToDriver();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
    _handlePosition(widget.position);
  }

  @override
  void didUpdateWidget(covariant HoursPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.driverId != widget.driverId) {
      _subscription?.cancel();
      _driverDocument = null;
      _hours = DriverHours();
      _lastPersistAt = null;
      _lastPosition = null;
      _activeRouteStartedAt = null;
      _listenToDriver();
    }
    if (oldWidget.routeStartedAt != widget.routeStartedAt ||
        oldWidget.route.isEmpty != widget.route.isEmpty) {
      _lastPosition = null;
      if (!_isRouteTrackingActive) {
        _hours.stopGpsDriving(
          DateTime.now(),
          countUntilStop: false,
        );
        _activeRouteStartedAt = null;
        if (!_loading) unawaited(_persist(force: true));
      } else if (!_loading) {
        _ensureRouteSession();
        _handlePosition(widget.position);
      }
    }
    if (_isNewPosition(oldWidget.position, widget.position)) {
      _handlePosition(widget.position);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  bool _isNewPosition(Position? oldPosition, Position? position) {
    if (position == null) return false;
    return oldPosition?.timestamp != position.timestamp;
  }

  bool get _isRouteTrackingActive =>
      widget.route.isNotEmpty && widget.routeStartedAt != null;

  void _ensureRouteSession() {
    final startedAt = widget.routeStartedAt;
    if (!_isRouteTrackingActive ||
        startedAt == null ||
        _activeRouteStartedAt == startedAt) {
      return;
    }
    _hours.startRouteTracking(startedAt);
    _activeRouteStartedAt = startedAt;
    unawaited(_persist(force: true));
  }

  void _listenToDriver() {
    final id = widget.driverId;
    final user = FirebaseAuth.instance.currentUser;
    if (id == null || id.isEmpty || user == null) return;

    _loading = true;
    _driverDocument = FirebaseFirestore.instance
        .collection('usuarios')
        .doc(user.uid)
        .collection('conductores')
        .doc(id);
    _subscription = _driverDocument!.snapshots().listen(
      (snapshot) {
        final stored = snapshot.data()?['registroHoras'];
        final map = stored is Map ? Map<String, dynamic>.from(stored) : null;
        if (!mounted) return;
        setState(() {
          _hours = DriverHours.fromMap(map);
          _loading = false;
          _error = null;
        });
        _ensureRouteSession();
        final pendingPosition = _pendingPosition ?? widget.position;
        _pendingPosition = null;
        if (pendingPosition != null) _handlePosition(pendingPosition);
        if (map == null) {
          unawaited(_persist(force: true));
        } else {
          _tick();
        }
      },
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'No se pudieron cargar las horas del conductor: $error';
        });
      },
    );
  }

  void _handlePosition(Position? position) {
    if (position == null || widget.driverId == null) return;
    if (_loading) {
      _pendingPosition = position;
      return;
    }
    if (!_isRouteTrackingActive) return;
    _ensureRouteSession();

    final previous = _lastPosition;
    _lastPosition = position;

    var moving = position.speed.isFinite && position.speed >= 1.5;
    if (!moving && previous != null) {
      final elapsed = position.timestamp
          .difference(previous.timestamp)
          .inMilliseconds;
      if (elapsed > 0 && elapsed <= 180000) {
        final distance = Geolocator.distanceBetween(
          previous.latitude,
          previous.longitude,
          position.latitude,
          position.longitude,
        );
        moving = distance / (elapsed / 1000) >= 1.5;
      }
    }
    final routeStartedAt = widget.routeStartedAt!;
    final timestamp = position.timestamp.isBefore(routeStartedAt)
        ? routeStartedAt
        : position.timestamp;
    if (!moving) {
      final wasDriving = _hours.activity == DriverActivity.driving &&
          _hours.drivingSource == 'gps';
      if (wasDriving) {
        _hours.stopGpsDriving(timestamp);
        if (mounted) setState(() {});
        unawaited(_persist(force: true));
      }
      return;
    }

    final wasDriving = _hours.activity == DriverActivity.driving;
    _hours.recordMovement(timestamp);
    if (!mounted) return;
    setState(() {});
    unawaited(_persist(force: !wasDriving));
  }

  void _tick() {
    if (widget.driverId == null || _loading) return;
    if (!_isRouteTrackingActive) {
      _hours.stopGpsDriving(DateTime.now(), countUntilStop: false);
    } else {
      _ensureRouteSession();
    }
    _hours.advance(DateTime.now());
    if (mounted) setState(() {});
    unawaited(_persist());
  }

  Future<void> _selectActivity(DriverActivity activity) async {
    _hours.setActivity(activity, DateTime.now());
    if (mounted) setState(() {});
    await _persist(force: true);
  }

  Future<void> _persist({bool force = false}) async {
    final document = _driverDocument;
    if (document == null || _saving) return;
    final now = DateTime.now();
    if (!force &&
        _lastPersistAt != null &&
        now.difference(_lastPersistAt!).inSeconds < 60) {
      return;
    }

    _saving = true;
    try {
      await document.set({
        'registroHoras': _hours.toMap(),
      }, SetOptions(merge: true));
      _lastPersistAt = now;
      if (mounted && _error != null) {
        setState(() {
          _error = null;
        });
      }
    } catch (error) {
      debugPrint('Error guardando registro horario del conductor: $error');
      if (mounted) {
        setState(() {
          _error = 'No se pudieron guardar las horas: $error';
        });
      }
    } finally {
      _saving = false;
    }
  }

  LatLng? get _currentPosition {
    final position = widget.position;
    if (position == null) return null;
    return LatLng(position.latitude, position.longitude);
  }

  PauseParkingRecommendation? get _recommendedParking => recommendPauseParking(
    hours: _hours,
    currentPosition: _currentPosition,
    route: widget.route,
    routeDurationSeconds: widget.routeDurationSeconds,
    parkings: widget.parkings,
    maxDistanceFromRouteKm: widget.maxParkingDistanceKm,
  );

  String _duration(int seconds) {
    final safeSeconds = math.max(0, seconds);
    final hours = safeSeconds ~/ 3600;
    final minutes = (safeSeconds % 3600) ~/ 60;
    if (hours == 0) return '$minutes min';
    return '$hours h ${minutes.toString().padLeft(2, '0')} min';
  }

  double _progress(int used, int limit) {
    if (limit <= 0) return 1;
    return (used / limit).clamp(0.0, 1.0).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    if (widget.driverId == null) {
      return _message('Selecciona un conductor para registrar sus horas.');
    }

    final recommendation = _recommendedParking;
    final drivingLimit = _hours.dailyLimitForCurrentPeriod;
    final secondsToDriveLimit = _hours.drivingSecondsUntilLimit;

    return Container(
      color: const Color(0xFFF2F5F8),
      child: ListView(
        padding: EdgeInsets.fromLTRB(
          compact ? 12 : 20,
          14,
          compact ? 12 : 20,
          20,
        ),
        children: [
          const Text(
            'HORAS DE CONDUCCIÓN',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _dark,
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            'Registro GPS mientras Arcén está en primer plano y actividad '
            'indicada por el conductor. No sustituye al tacógrafo.',
            style: TextStyle(fontSize: 12, color: _muted, height: 1.35),
          ),
          if (_loading) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ],
          const SizedBox(height: 14),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel(
                  'ACTIVIDAD AHORA · ${_hours.activity.label.toUpperCase()}',
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 7,
                  runSpacing: 7,
                  children: [
                    for (final activity in DriverActivity.values)
                      ChoiceChip(
                        selected: _hours.activity == activity,
                        showCheckmark: false,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        side: BorderSide(
                          color: _hours.activity == activity
                              ? _blue
                              : _border,
                        ),
                        label: Text(activity.label),
                        avatar: Icon(
                          _activityIcon(activity),
                          size: 17,
                          color: _hours.activity == activity
                              ? Colors.white
                              : _dark,
                        ),
                        selectedColor: _blue,
                        labelStyle: TextStyle(
                          color: _hours.activity == activity
                              ? Colors.white
                              : _dark,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        onSelected: activity == DriverActivity.driving
                            ? null
                            : (_) => _selectActivity(activity),
                      ),
                  ],
                ),
                const SizedBox(height: 7),
                const Text(
                  'Calcula una ruta para activar el registro. La conducción '
                  'se inicia al detectar movimiento y se pausa al detenerte. '
                  'Marca manualmente trabajo, disponibilidad o descanso.',
                  style: TextStyle(fontSize: 10, color: _muted, height: 1.3),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          _card(
            borderColor: _blue,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _sectionLabel('TIEMPO HASTA EL PRÓXIMO LÍMITE'),
                Text(
                  _duration(secondsToDriveLimit),
                  style: const TextStyle(
                    fontSize: 25,
                    fontWeight: FontWeight.w800,
                    height: 1.1,
                    color: _dark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Pausa de conducción antes de ${_duration(_hours.drivingSecondsUntilBreak)}. '
                  'Límite diario actual: ${_duration(drivingLimit)}.',
                  style: const TextStyle(
                    fontSize: 10,
                    color: _muted,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          _card(
            child: Column(
              children: [
                _metric(
                  'Conducción seguida',
                  '${_duration(_hours.continuousDrivingSeconds)} / 4 h 30 min',
                  _progress(
                    _hours.continuousDrivingSeconds,
                    DriverHours.continuousLimitSeconds,
                  ),
                ),
                const SizedBox(height: 12),
                _metric(
                  'Conducción diaria',
                  '${_duration(_hours.dailyDrivingSeconds)} / ${_duration(drivingLimit)}',
                  _progress(_hours.dailyDrivingSeconds, drivingLimit),
                ),
                const SizedBox(height: 12),
                _metric(
                  'Conducción semanal',
                  '${_duration(_hours.weeklyDrivingSeconds)} / 56 h',
                  _progress(
                    _hours.weeklyDrivingSeconds,
                    DriverHours.weeklyLimitSeconds,
                  ),
                ),
                const SizedBox(height: 12),
                _metric(
                  'Dos semanas',
                  '${_duration(_hours.weeklyDrivingSeconds + _hours.previousWeekDrivingSeconds)} / 90 h',
                  _progress(
                    _hours.weeklyDrivingSeconds +
                        _hours.previousWeekDrivingSeconds,
                    DriverHours.fortnightLimitSeconds,
                  ),
                  color: const Color(0xFFE29A00),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ampliaciones diarias de 10 h usadas esta semana: '
                  '${_hours.extendedDaysThisWeek} / 2.',
                  style: const TextStyle(fontSize: 10, color: _muted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 9),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Actividad de hoy',
                  style: TextStyle(fontWeight: FontWeight.w800, color: _dark),
                ),
                const SizedBox(height: 12),
                _activityTimeline(),
              ],
            ),
          ),
          const SizedBox(height: 9),
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Próxima pausa',
                  style: TextStyle(fontWeight: FontWeight.w800, color: _dark),
                ),
                const SizedBox(height: 8),
                Text(
                  _hours.currentRestSeconds >= _hours.minimumDailyRestSeconds
                      ? 'Descanso diario completado.'
                      : 'Pausa de 45 min (15 + 30). Descanso diario: '
                            '11 h, reducible a 9 h hasta 3 veces entre '
                            'descansos semanales.',
                  style: const TextStyle(
                    fontSize: 11,
                    color: _muted,
                    height: 1.3,
                  ),
                ),
                Text(
                  'Descansos reducidos desde el último descanso semanal: '
                  '${_hours.reducedDailyRestsSinceWeeklyRest} / 3.',
                  style: const TextStyle(fontSize: 10, color: _muted),
                ),
                if (_hours.activity == DriverActivity.rest)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 5),
                        child: Text(
                          'Descanso registrado: '
                          '${_duration(_hours.currentRestSeconds)}',
                          style: const TextStyle(
                            color: _dark,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 12),
                if (recommendation == null)
                  const Text(
                    'Calcula una ruta y activa el GPS para recomendar un parking.',
                    style: TextStyle(fontSize: 11, color: _muted),
                  )
                else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.local_parking_outlined,
                        color: _blue,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              recommendation.name,
                              style: const TextStyle(
                                color: _dark,
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                            Text(
                              'Aprox. en ${_duration(recommendation.secondsFromCurrentPosition)}'
                              '${recommendation.beforeDrivingLimit ? '' : ' · después del límite de conducción'}',
                              style: TextStyle(
                                color: recommendation.beforeDrivingLimit
                                    ? _muted
                                    : Colors.red.shade700,
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _activityTimeline() {
    final colors = <DriverActivity, Color>{
      DriverActivity.driving: _blue,
      DriverActivity.otherWork: const Color(0xFFE39A22),
      DriverActivity.available: const Color(0xFF64748B),
      DriverActivity.rest: const Color(0xFF16864B),
    };
    final seconds = DriverActivity.values
        .map((activity) => _hours.timelineSeconds[activity.key] ?? 0)
        .toList();
    final total = seconds.fold<int>(0, (sum, value) => sum + value);
    if (total == 0) {
      return const Text(
        'Aún no hay actividad registrada hoy.',
        style: TextStyle(fontSize: 11, color: _muted),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: SizedBox(
            height: 16,
            child: Row(
              children: [
                for (
                  var index = 0;
                  index < DriverActivity.values.length;
                  index++
                )
                  if (seconds[index] > 0)
                    Expanded(
                      flex: seconds[index],
                      child: ColoredBox(
                        color: colors[DriverActivity.values[index]]!,
                      ),
                    ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 9),
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            for (final activity in DriverActivity.values)
              _legend(
                colors[activity]!,
                '${activity.label} · ${_duration(_hours.timelineSeconds[activity.key] ?? 0)}',
              ),
          ],
        ),
      ],
    );
  }

  IconData _activityIcon(DriverActivity activity) => switch (activity) {
    DriverActivity.driving => Icons.local_shipping_outlined,
    DriverActivity.otherWork => Icons.construction_outlined,
    DriverActivity.available => Icons.crop_square,
    DriverActivity.rest => Icons.hotel_outlined,
  };

  Widget _metric(
    String label,
    String value,
    double progress, {
    Color color = _blue,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: _dark,
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 7,
            backgroundColor: const Color(0xFFD8E0E9),
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }

  Widget _legend(Color color, String text) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 4),
      Text(text, style: const TextStyle(fontSize: 9, color: _muted)),
    ],
  );

  Widget _sectionLabel(String text) => Text(
    text,
    style: const TextStyle(
      fontSize: 9,
      letterSpacing: 0.6,
      fontWeight: FontWeight.w800,
      color: Color(0xFF718096),
    ),
  );

  Widget _card({required Widget child, Color borderColor = _border}) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: child,
      );

  Widget _message(String message) => Container(
    color: const Color(0xFFF2F5F8),
    alignment: Alignment.center,
    padding: const EdgeInsets.all(24),
    child: Text(
      message,
      textAlign: TextAlign.center,
      style: const TextStyle(color: _muted),
    ),
  );
}
