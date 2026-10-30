import 'package:flutter_test/flutter_test.dart';

import 'package:arcen/screens/route_distance.dart';

void main() {
  const ruta = <List<double>>[
    [-3.7, 40.4],
    [-3.69, 40.4],
    [-3.69, 40.41],
  ];

  test('el índice conserva la distancia al segmento más cercano', () {
    final indice = RouteDistanceIndex(ruta, maxDistanceKm: 1);
    const latitud = 40.402;
    const longitud = -3.695;

    final distanciaCompleta = distanciaPuntoRutaMetros(
      latitud: latitud,
      longitud: longitud,
      ruta: ruta,
    );
    final distanciaIndexada = indice.distanciaMetros(
      latitud: latitud,
      longitud: longitud,
    );

    expect(distanciaIndexada, closeTo(distanciaCompleta!, 0.01));
  });

  test('el índice omite puntos fuera del radio configurado', () {
    final indice = RouteDistanceIndex(ruta, maxDistanceKm: 0.1);

    expect(indice.distanciaMetros(latitud: 40.42, longitud: -3.7), isNull);
  });

  test('el índice admite rutas de un único punto', () {
    const ruta = <List<double>>[
      [-3.7, 40.4],
    ];
    final indice = RouteDistanceIndex(ruta, maxDistanceKm: 1);

    expect(indice.distanciaMetros(latitud: 40.4, longitud: -3.7), 0);
  });

  test('calcula el progreso GPS proyectado sobre la ruta', () {
    const rutaRecta = <List<double>>[
      [-3.7, 40.4],
      [-3.68, 40.4],
    ];
    expect(
      progresoPuntoRuta(latitud: 40.4, longitud: -3.7, ruta: rutaRecta),
      closeTo(0, 0.001),
    );
    expect(
      progresoPuntoRuta(latitud: 40.4, longitud: -3.69, ruta: rutaRecta),
      closeTo(0.5, 0.01),
    );
    expect(
      progresoPuntoRuta(latitud: 40.4, longitud: -3.68, ruta: rutaRecta),
      closeTo(1, 0.001),
    );
  });

  test('devuelve null si no hay una ruta válida para seguir', () {
    expect(
      progresoPuntoRuta(latitud: 40.4, longitud: -3.7, ruta: const []),
      isNull,
    );
    expect(
      progresoPuntoRuta(latitud: 91, longitud: -3.7, ruta: ruta),
      isNull,
    );
  });
}
