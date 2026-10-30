import 'package:latlong2/latlong.dart';

import '../models/driver_hours.dart';
import '../screens/route_distance.dart';

class PauseParkingRecommendation {
  const PauseParkingRecommendation({
    required this.name,
    required this.secondsFromCurrentPosition,
    required this.beforeDrivingLimit,
  });

  final String name;
  final int secondsFromCurrentPosition;
  final bool beforeDrivingLimit;
}

PauseParkingRecommendation? recommendPauseParking({
  required DriverHours hours,
  required LatLng? currentPosition,
  required List<List<double>> route,
  required int? routeDurationSeconds,
  required List<Map<String, dynamic>> parkings,
  required double maxDistanceFromRouteKm,
}) {
  if (currentPosition == null ||
      route.length < 2 ||
      routeDurationSeconds == null ||
      routeDurationSeconds <= 0 ||
      parkings.isEmpty) {
    return null;
  }

  final currentProgress = progresoPuntoRuta(
    latitud: currentPosition.latitude,
    longitud: currentPosition.longitude,
    ruta: route,
  );
  if (currentProgress == null) return null;

  final candidates = <({String name, int seconds})>[];
  for (final parking in parkings) {
    if (!_isTruckSuitable(parking)) continue;
    final latitude = _number(parking['latitud'] ?? parking['latitude']);
    final longitude = _number(
      parking['longitud'] ??
          parking['longitude'] ??
          parking['lon'] ??
          parking['lng'],
    );
    if (latitude == null ||
        longitude == null ||
        latitude < -90 ||
        latitude > 90 ||
        longitude < -180 ||
        longitude > 180) {
      continue;
    }

    final distanceFromRoute = distanciaPuntoRutaMetros(
      latitud: latitude,
      longitud: longitude,
      ruta: route,
    );
    if (distanceFromRoute == null ||
        distanceFromRoute > maxDistanceFromRouteKm * 1000) {
      continue;
    }

    final progress = progresoPuntoRuta(
      latitud: latitude,
      longitud: longitude,
      ruta: route,
    );
    if (progress == null || progress <= currentProgress) continue;

    final seconds =
        ((progress - currentProgress) * routeDurationSeconds).round();
    candidates.add((
      name: (parking['nombre'] ?? parking['name'] ?? 'Parking').toString(),
      seconds: seconds,
    ));
  }
  if (candidates.isEmpty) return null;

  candidates.sort((a, b) => a.seconds.compareTo(b.seconds));
  final secondsUntilBreak = hours.drivingSecondsUntilBreak;
  final beforeLimit = candidates
      .where((candidate) => candidate.seconds <= secondsUntilBreak)
      .toList();
  final selected = beforeLimit.isNotEmpty
      ? beforeLimit.last
      : candidates.first;

  return PauseParkingRecommendation(
    name: selected.name,
    secondsFromCurrentPosition: selected.seconds,
    beforeDrivingLimit: beforeLimit.isNotEmpty,
  );
}

bool _isTruckSuitable(Map<String, dynamic> parking) {
  final aptoCamiones = parking['aptoCamiones'];
  if (aptoCamiones is bool) return aptoCamiones;
  final searchable =
      '${parking['tipo'] ?? ''} ${parking['nombre'] ?? ''}'.toLowerCase();
  return searchable.contains('camion') ||
      searchable.contains('camión') ||
      searchable.contains('truck');
}

double? _number(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value);
  return null;
}
