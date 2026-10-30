import 'dart:math' as math;

/// Calcula la distancia mínima en metros desde un punto
/// hasta la ruta.
///
/// La ruta tiene el formato OSRM:
/// [longitud, latitud]
///
/// Devuelve null si no hay ruta.
double? distanciaPuntoRutaMetros({
  required double latitud,
  required double longitud,
  required List<List<double>> ruta,
}) {
  if (ruta.isEmpty) return null;

  if (ruta.length == 1) {
    final punto = ruta.first;

    if (punto.length < 2) return null;

    return _distanciaPuntoSegmentoMetros(
      latitud,
      longitud,
      punto[0],
      punto[1],
      punto[0],
      punto[1],
    );
  }

  double distanciaMinima = double.infinity;

  for (int i = 0; i < ruta.length - 1; i++) {
    final a = ruta[i];
    final b = ruta[i + 1];

    if (a.length < 2 || b.length < 2) continue;

    final distancia = _distanciaPuntoSegmentoMetros(
      latitud,
      longitud,
      a[0],
      a[1],
      b[0],
      b[1],
    );

    if (distancia < distanciaMinima) {
      distanciaMinima = distancia;
    }
  }

  if (!distanciaMinima.isFinite) return null;

  return distanciaMinima;
}

double? progresoPuntoRuta({
  required double latitud,
  required double longitud,
  required List<List<double>> ruta,
}) {
  if (!latitud.isFinite ||
      !longitud.isFinite ||
      latitud < -90 ||
      latitud > 90 ||
      longitud < -180 ||
      longitud > 180) {
    return null;
  }

  if (ruta.length < 2) return null;

  const metrosPorGradoLatitud = 110540.0;
  var distanciaAcumulada = 0.0;
  var distanciaTotal = 0.0;
  var distanciaMinimaCuadrada = double.infinity;
  double? distanciaSobreRuta;

  for (var i = 0; i < ruta.length - 1; i++) {
    final inicio = ruta[i];
    final fin = ruta[i + 1];
    if (inicio.length < 2 ||
        fin.length < 2 ||
        !inicio[0].isFinite ||
        !inicio[1].isFinite ||
        !fin[0].isFinite ||
        !fin[1].isFinite) {
      continue;
    }

    final latitudMedia = (latitud + (inicio[1] + fin[1]) / 2) / 2;
    final escalaLongitud =
        111320 * math.cos(latitudMedia * math.pi / 180);
    final dx = (fin[0] - inicio[0]) * escalaLongitud;
    final dy = (fin[1] - inicio[1]) * metrosPorGradoLatitud;
    final puntoX = (longitud - inicio[0]) * escalaLongitud;
    final puntoY = (latitud - inicio[1]) * metrosPorGradoLatitud;
    final longitudCuadrada = dx * dx + dy * dy;
    final t = longitudCuadrada == 0
        ? 0.0
        : ((puntoX * dx + puntoY * dy) / longitudCuadrada)
              .clamp(0.0, 1.0)
              .toDouble();
    final diferenciaX = puntoX - t * dx;
    final diferenciaY = puntoY - t * dy;
    final distanciaCuadrada =
        diferenciaX * diferenciaX + diferenciaY * diferenciaY;
    final longitudSegmento = math.sqrt(longitudCuadrada);

    if (distanciaCuadrada < distanciaMinimaCuadrada) {
      distanciaMinimaCuadrada = distanciaCuadrada;
      distanciaSobreRuta = distanciaAcumulada + longitudSegmento * t;
    }
    distanciaAcumulada += longitudSegmento;
    distanciaTotal += longitudSegmento;
  }

  if (distanciaSobreRuta == null || distanciaTotal <= 0) return null;
  return (distanciaSobreRuta / distanciaTotal).clamp(0.0, 1.0).toDouble();
}

class RouteDistanceIndex {
  RouteDistanceIndex(List<List<double>> ruta, {required this.maxDistanceKm})
    : _cellSizeDegrees = maxDistanceKm / 110 {
    if (!maxDistanceKm.isFinite || maxDistanceKm <= 0) {
      throw ArgumentError.value(maxDistanceKm, 'maxDistanceKm');
    }

    if (ruta.isEmpty) return;

    final segmentos = <_RouteSegment>[];
    if (ruta.length == 1) {
      final punto = ruta.first;
      if (punto.length >= 2 && punto[0].isFinite && punto[1].isFinite) {
        segmentos.add(_RouteSegment(punto[0], punto[1], punto[0], punto[1]));
      }
    } else {
      for (var i = 0; i < ruta.length - 1; i++) {
        final inicio = ruta[i];
        final fin = ruta[i + 1];
        if (inicio.length < 2 ||
            fin.length < 2 ||
            !inicio[0].isFinite ||
            !inicio[1].isFinite ||
            !fin[0].isFinite ||
            !fin[1].isFinite) {
          continue;
        }
        segmentos.add(_RouteSegment(inicio[0], inicio[1], fin[0], fin[1]));
      }
    }

    final latitudMargen = maxDistanceKm / 110;

    for (final segmento in segmentos) {
      final minLat = math.min(segmento.lat1, segmento.lat2);
      final maxLat = math.max(segmento.lat1, segmento.lat2);
      final minLon = math.min(segmento.lon1, segmento.lon2);
      final maxLon = math.max(segmento.lon1, segmento.lon2);
      final maxAbsLat = math.max(
        (minLat - latitudMargen).abs(),
        (maxLat + latitudMargen).abs(),
      );

      if (maxAbsLat >= 85) {
        _segmentosAmplios.add(segmento);
        continue;
      }

      final cosLatitud = math.cos(maxAbsLat * math.pi / 180);
      final longitudMargen = maxDistanceKm / (110 * cosLatitud);
      final minX = _celda(minLon - longitudMargen);
      final maxX = _celda(maxLon + longitudMargen);
      final minY = _celda(minLat - latitudMargen);
      final maxY = _celda(maxLat + latitudMargen);

      for (var x = minX; x <= maxX; x++) {
        for (var y = minY; y <= maxY; y++) {
          _celdas.putIfAbsent((x, y), () => []).add(segmento);
        }
      }
    }
  }

  final double maxDistanceKm;
  final double _cellSizeDegrees;
  final Map<(int, int), List<_RouteSegment>> _celdas = {};
  final List<_RouteSegment> _segmentosAmplios = [];

  int _celda(double coordenada) => (coordenada / _cellSizeDegrees).floor();

  double? distanciaMetros({required double latitud, required double longitud}) {
    if (!latitud.isFinite ||
        !longitud.isFinite ||
        latitud < -90 ||
        latitud > 90 ||
        longitud < -180 ||
        longitud > 180) {
      return null;
    }

    final segmentos = _celdas[(_celda(longitud), _celda(latitud))];
    var distanciaMinima = double.infinity;

    void comprobar(_RouteSegment segmento) {
      final distancia = _distanciaPuntoSegmentoMetros(
        latitud,
        longitud,
        segmento.lon1,
        segmento.lat1,
        segmento.lon2,
        segmento.lat2,
      );
      if (distancia < distanciaMinima) {
        distanciaMinima = distancia;
      }
    }

    if (segmentos != null) {
      for (final segmento in segmentos) {
        comprobar(segmento);
      }
    }
    for (final segmento in _segmentosAmplios) {
      comprobar(segmento);
    }

    if (distanciaMinima > maxDistanceKm * 1000) return null;
    return distanciaMinima;
  }
}

class _RouteSegment {
  const _RouteSegment(this.lon1, this.lat1, this.lon2, this.lat2);

  final double lon1;
  final double lat1;
  final double lon2;
  final double lat2;
}

double _distanciaPuntoSegmentoMetros(
  double latitud,
  double longitud,
  double lon1,
  double lat1,
  double lon2,
  double lat2,
) {
  const radioTierra = 6371000.0;

  final lat0 = latitud * math.pi / 180;
  final lon0 = longitud * math.pi / 180;
  final escalaX = radioTierra * math.cos(lat0);

  final ax = (lon1 * math.pi / 180 - lon0) * escalaX;
  final ay = (lat1 * math.pi / 180 - latitud * math.pi / 180) * radioTierra;
  final bx = (lon2 * math.pi / 180 - lon0) * escalaX;
  final by = (lat2 * math.pi / 180 - latitud * math.pi / 180) * radioTierra;

  final dx = bx - ax;
  final dy = by - ay;
  final longitudCuadrada = dx * dx + dy * dy;

  var t = 0.0;
  if (longitudCuadrada > 0) {
    t = ((-ax * dx) + (-ay * dy)) / longitudCuadrada;
    t = t.clamp(0.0, 1.0);
  }

  final px = ax + t * dx;
  final py = ay + t * dy;
  return math.sqrt(px * px + py * py);
}
