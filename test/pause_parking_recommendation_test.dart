import 'package:arcen/models/driver_hours.dart';
import 'package:arcen/services/pause_parking_recommendation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  const route = <List<double>>[
    [-3.7, 40.4],
    [-3.68, 40.4],
  ];
  final hours = DriverHours(continuousDrivingSeconds: 3 * 60 * 60 + 30 * 60);
  final parkings = <Map<String, dynamic>>[
    {
      'nombre': 'Área camiones cercana',
      'latitud': 40.4,
      'longitud': -3.69,
      'aptoCamiones': true,
    },
    {
      'nombre': 'Parking sin aptitud camiones',
      'latitud': 40.4,
      'longitud': -3.685,
      'aptoCamiones': false,
    },
  ];

  test('recomienda el parking apto antes del límite de conducción', () {
    final recommendation = recommendPauseParking(
      hours: hours,
      currentPosition: const LatLng(40.4, -3.695),
      route: route,
      routeDurationSeconds: 7200,
      parkings: parkings,
      maxDistanceFromRouteKm: 1,
    );

    expect(recommendation?.name, 'Área camiones cercana');
    expect(recommendation?.beforeDrivingLimit, isTrue);
  });

  test('no recomienda si faltan ruta o posición GPS', () {
    expect(
      recommendPauseParking(
        hours: hours,
        currentPosition: null,
        route: route,
        routeDurationSeconds: 7200,
        parkings: parkings,
        maxDistanceFromRouteKm: 1,
      ),
      isNull,
    );
  });
}
