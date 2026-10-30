import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/app_settings.dart';

/// Aviso meteorológico calculado por Arcén a partir de la previsión.
class AvisoMeteorologico {
  final String id;
  final String tipo;
  final String titulo;
  final String descripcion;
  final double latitud;
  final double longitud;
  final DateTime fecha;
  final DateTime caduca;
  final double? valor;

  const AvisoMeteorologico({
    required this.id,
    required this.tipo,
    required this.titulo,
    required this.descripcion,
    required this.latitud,
    required this.longitud,
    required this.fecha,
    required this.caduca,
    this.valor,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'tipo': tipo,
      'titulo': titulo,
      'descripcion': descripcion,
      'latitud': latitud,
      'longitud': longitud,
      'publicado': fecha.toIso8601String(),
      'caduca': caduca.toIso8601String(),
      'origen': 'open_meteo',
      'esMeteorologico': true,
    };
  }
}

class OpenMeteoAlerts {
  OpenMeteoAlerts._();

  static const Duration timeout = Duration(seconds: 15);

  /// Recibe coordenadas [longitud, latitud], como las de ViajePage.
  ///
  /// Consulta hasta 6 puntos repartidos por la ruta y analiza las
  /// próximas 24 horas. Devuelve avisos sin duplicados aproximados.
  static Future<List<AvisoMeteorologico>> consultarRuta(
    List<List<double>> coordenadasRuta, {
    AppSettings settings = const AppSettings(),
  }) async {
    if (coordenadasRuta.isEmpty) return [];

    final puntos = _seleccionarPuntos(coordenadasRuta);
    final resultadosPorPunto = await Future.wait(
      puntos.map((punto) async {
        try {
          return await _consultarPunto(
            longitud: punto[0],
            latitud: punto[1],
            settings: settings,
          );
        } catch (e) {
          // Un punto fallido no impide consultar el resto de la ruta.
          // ignore: avoid_print
          print('Error consultando Open-Meteo: $e');
          return const <AvisoMeteorologico>[];
        }
      }),
    );

    return _eliminarDuplicados(
      resultadosPorPunto.expand((avisos) => avisos).toList(),
    );
  }

  static List<List<double>> _seleccionarPuntos(List<List<double>> ruta) {
    final validos = ruta.where((p) => p.length >= 2).toList();
    if (validos.length <= 6) return validos;

    // Reparte seis consultas desde el inicio hasta el final de la ruta.
    final puntos = <List<double>>[];
    for (var i = 0; i < 6; i++) {
      final indice = (i * (validos.length - 1) / 5).round();
      puntos.add(validos[indice]);
    }
    return puntos;
  }

  static Future<List<AvisoMeteorologico>> _consultarPunto({
    required double longitud,
    required double latitud,
    required AppSettings settings,
  }) async {
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': latitud.toString(),
      'longitude': longitud.toString(),
      'hourly': [
        'temperature_2m',
        'precipitation',
        'snowfall',
        'visibility',
        'wind_gusts_10m',
        'weather_code',
        'freezing_rain_probability',
      ].join(','),
      'forecast_days': '2',
      'timezone': 'auto',
      'wind_speed_unit': 'kmh',
    });

    final response = await http.get(uri).timeout(timeout);

    if (response.statusCode != 200) {
      throw Exception('Open-Meteo HTTP ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final hourly = data['hourly'] as Map<String, dynamic>?;

    if (hourly == null) return [];

    final times = _list(hourly, 'time');
    final temperatures = _list(hourly, 'temperature_2m');
    final precipitation = _list(hourly, 'precipitation');
    final snowfall = _list(hourly, 'snowfall');
    final visibility = _list(hourly, 'visibility');
    final gusts = _list(hourly, 'wind_gusts_10m');
    final codes = _list(hourly, 'weather_code');
    final freezingRain = _list(hourly, 'freezing_rain_probability');

    final ahora = DateTime.now();
    final avisos = <AvisoMeteorologico>[];

    for (var i = 0; i < times.length; i++) {
      final fecha = DateTime.tryParse(times[i].toString());
      if (fecha == null) continue;

      // La API devuelve la hora local del punto consultado.
      // Se limita el análisis a las próximas 24 horas.
      final diferencia = fecha.difference(ahora);
      if (diferencia.inMinutes < -60 ||
          diferencia > const Duration(hours: 24)) {
        continue;
      }

      final temperatura = _numero(temperatures, i);
      final lluvia = _numero(precipitation, i);
      final nieve = _numero(snowfall, i);
      final visibilidad = _numero(visibility, i);
      final racha = _numero(gusts, i);
      final codigo = _numero(codes, i)?.round();
      final probHielo = _numero(freezingRain, i);

      final caduca = fecha.add(const Duration(hours: 1));

      if (racha != null && racha >= settings.rachasVientoKmh) {
        avisos.add(
          _crear(
            tipo: 'viento',
            titulo: 'Viento fuerte',
            descripcion:
                'Rachas previstas de ${racha.round()} km/h en este tramo.',
            latitud: latitud,
            longitud: longitud,
            fecha: fecha,
            caduca: caduca,
            valor: racha,
          ),
        );
      }

      final codigoNieve =
          codigo == 71 ||
          codigo == 73 ||
          codigo == 75 ||
          codigo == 77 ||
          codigo == 85 ||
          codigo == 86;

      if (nieve != null ? nieve >= settings.nieveCmHora : codigoNieve) {
        avisos.add(
          _crear(
            tipo: 'nieve',
            titulo: 'Posible nieve',
            descripcion: 'La previsión indica nieve en este tramo de la ruta.',
            latitud: latitud,
            longitud: longitud,
            fecha: fecha,
            caduca: caduca,
            valor: nieve,
          ),
        );
      }

      final codigoNiebla = codigo == 45 || codigo == 48;
      if (visibilidad != null
          ? visibilidad < settings.visibilidadMetros
          : codigoNiebla) {
        avisos.add(
          _crear(
            tipo: 'niebla',
            titulo: 'Visibilidad reducida',
            descripcion: visibilidad == null
                ? 'La previsión indica posibles bancos de niebla.'
                : 'Visibilidad prevista: '
                      '${visibilidad.round()} metros.',
            latitud: latitud,
            longitud: longitud,
            fecha: fecha,
            caduca: caduca,
            valor: visibilidad,
          ),
        );
      }

      final riesgoHielo =
          temperatura != null &&
          temperatura <= settings.temperaturaHieloCelsius &&
          ((lluvia != null && lluvia > settings.precipitacionHieloMm) ||
              (nieve != null && nieve > 0) ||
              (probHielo != null &&
                  probHielo >= settings.probabilidadLluviaEngelante));

      if (riesgoHielo) {
        avisos.add(
          _crear(
            tipo: 'hielo',
            titulo: 'Posible hielo en carretera',
            descripcion:
                'Temperatura prevista de ${temperatura.toStringAsFixed(1)} °C '
                'con precipitación o posibilidad de lluvia engelante.',
            latitud: latitud,
            longitud: longitud,
            fecha: fecha,
            caduca: caduca,
            valor: temperatura,
          ),
        );
      }
    }

    return avisos;
  }

  static AvisoMeteorologico _crear({
    required String tipo,
    required String titulo,
    required String descripcion,
    required double latitud,
    required double longitud,
    required DateTime fecha,
    required DateTime caduca,
    double? valor,
  }) {
    final id =
        '${tipo}_${latitud.toStringAsFixed(3)}_'
        '${longitud.toStringAsFixed(3)}_${fecha.toIso8601String()}';

    return AvisoMeteorologico(
      id: id,
      tipo: tipo,
      titulo: titulo,
      descripcion: descripcion,
      latitud: latitud,
      longitud: longitud,
      fecha: fecha,
      caduca: caduca,
      valor: valor,
    );
  }

  static List<dynamic> _list(Map<String, dynamic> data, String key) {
    final value = data[key];
    return value is List ? value : const [];
  }

  static double? _numero(List<dynamic> valores, int indice) {
    if (indice >= valores.length) return null;
    final value = valores[indice];
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static List<AvisoMeteorologico> _eliminarDuplicados(
    List<AvisoMeteorologico> avisos,
  ) {
    final unicos = <String, AvisoMeteorologico>{};

    for (final aviso in avisos) {
      final clave =
          '${aviso.tipo}_'
          '${aviso.latitud.toStringAsFixed(2)}_'
          '${aviso.longitud.toStringAsFixed(2)}_'
          '${aviso.fecha.year}_${aviso.fecha.month}_'
          '${aviso.fecha.day}_${aviso.fecha.hour}';

      unicos.putIfAbsent(clave, () => aviso);
    }

    return unicos.values.toList()..sort((a, b) => a.fecha.compareTo(b.fecha));
  }
}
