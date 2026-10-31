import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'route_distance.dart';

const Color _blue = Color(0xFF1053A4);
const Color _background = Color(0xFFF3F6F9);
const Color _border = Color(0xFFD8E0E9);

enum _Combustible { gasoleoA, gasoleoB, adblue }

List<Map<String, dynamic>> _procesarGasolineras(Map<String, dynamic> consulta) {
  final data = jsonDecode(
    utf8.decode(consulta['body'] as List<int>),
  ) as Map<String, dynamic>;
  final lista = data['ListaEESSPrecio'] as List<dynamic>? ?? [];
  final ruta = consulta['ruta'] as List<List<double>>;
  final radioKm = consulta['radioKm'] as double;
  final campoPrecio = consulta['campoPrecio'] as String;
  final indiceRuta = RouteDistanceIndex(ruta, maxDistanceKm: radioKm);
  final estaciones = <Map<String, dynamic>>[];

  for (final item in lista) {
    if (item is! Map<String, dynamic>) continue;

    final latitud = _parseNumero(item['Latitud']);
    final longitud = _parseNumero(item['Longitud (WGS84)']);
    if (latitud == null || longitud == null) continue;

    final distanciaMetros = indiceRuta.distanciaMetros(
      latitud: latitud,
      longitud: longitud,
    );
    if (distanciaMetros == null) continue;

    final precio = _parsePrecio(item[campoPrecio]);
    if (precio == null || precio <= 0) continue;

    estaciones.add({
      'nombre': (item['Rótulo'] ?? 'Gasolinera').toString(),
      'direccion': (item['Dirección'] ?? '').toString(),
      'municipio': (item['Municipio'] ?? '').toString(),
      'provincia': (item['Provincia'] ?? '').toString(),
      'horario': (item['Horario'] ?? '').toString(),
      'latitud': latitud,
      'longitud': longitud,
      'precio': precio,
    });
  }

  estaciones.sort(
    (a, b) => (a['precio'] as double).compareTo(b['precio'] as double),
  );
  return estaciones;
}

double? _parsePrecio(dynamic valor) {
  if (valor == null) return null;

  final texto = valor.toString().trim();
  if (texto.isEmpty) return null;

  return double.tryParse(texto.replaceAll(',', '.'));
}

double? _parseNumero(dynamic valor) {
  if (valor == null) return null;

  return double.tryParse(valor.toString().trim().replaceAll(',', '.'));
}

class GasoleoPage extends StatefulWidget {
  final List<List<double>> coordenadasRuta;
  final double radioRutaKm;
  final LatLng? ubicacionActual;

  // Permite comunicar las gasolineras encontradas a HomePage.
  final ValueChanged<List<Map<String, dynamic>>>? onGasolinerasChanged;

  const GasoleoPage({
    super.key,
    required this.coordenadasRuta,
    this.radioRutaKm = 0.09,
    this.ubicacionActual,
    this.onGasolinerasChanged,
  });

  @override
  State<GasoleoPage> createState() => _GasoleoPageState();
}

class _GasoleoPageState extends State<GasoleoPage> {
  _Combustible _combustible = _Combustible.gasoleoA;

  List<_Gasolinera> _gasolineras = [];

  bool _loading = false;
  String? _error;

  bool _datosDescargados = false;

  // Identifica la consulta más reciente para evitar que una
  // respuesta antigua sobrescriba los datos de otra ruta.
  int _consultaId = 0;

  @override
  void initState() {
    super.initState();

    if (widget.coordenadasRuta.isNotEmpty) {
      _consultarGasolineras();
    }
  }

  @override
  void didUpdateWidget(covariant GasoleoPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.coordenadasRuta != widget.coordenadasRuta ||
        oldWidget.radioRutaKm != widget.radioRutaKm) {
      _consultaId++;
      _datosDescargados = false;
      _gasolineras = [];
      _error = null;

      if (widget.coordenadasRuta.isNotEmpty) {
        _consultarGasolineras();
      } else {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String get _nombreCombustible {
    switch (_combustible) {
      case _Combustible.gasoleoA:
        return 'Gasóleo A';
      case _Combustible.gasoleoB:
        return 'Gasóleo B';
      case _Combustible.adblue:
        return 'AdBlue';
    }
  }

  String get _campoPrecio {
    switch (_combustible) {
      case _Combustible.gasoleoA:
        return 'Precio Gasoleo A';
      case _Combustible.gasoleoB:
        return 'Precio Gasoleo B';
      case _Combustible.adblue:
        return 'Precio Adblue';
    }
  }

  Future<void> _consultarGasolineras() async {
    final consultaActual = ++_consultaId;

    if (widget.coordenadasRuta.isEmpty) {
      if (!mounted) return;

      setState(() {
        _loading = false;
        _datosDescargados = false;
        _error = 'Primero calcula una ruta en la sección Viaje.';
        _gasolineras = [];
      });

      widget.onGasolinerasChanged?.call([]);
      return;
    }

    final rutaConsulta = widget.coordenadasRuta
        .map((punto) => List<double>.from(punto))
        .toList();

    final radioConsulta = widget.radioRutaKm;
    final campoPrecioConsulta = _campoPrecio;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final uri = Uri.https(
        'sedeaplicaciones.minetur.gob.es',
        '/ServiciosRESTCarburantes/PreciosCarburantes/'
            'EstacionesTerrestres/',
      );

      final response = await http.get(uri);

      if (consultaActual != _consultaId || !mounted) return;

      if (response.statusCode != 200) {
        throw Exception(
          'Error al consultar el Ministerio '
          '(HTTP ${response.statusCode}).',
        );
      }

      final estacionesProcesadas =
          await compute<Map<String, dynamic>, List<Map<String, dynamic>>>(
            _procesarGasolineras,
            {
              'body': response.bodyBytes,
              'ruta': rutaConsulta,
              'radioKm': radioConsulta,
              'campoPrecio': campoPrecioConsulta,
            },
          );

      if (consultaActual != _consultaId || !mounted) return;

      final estaciones = estacionesProcesadas.map((datos) {
        return _Gasolinera(
          nombre: datos['nombre'] as String,
          direccion: datos['direccion'] as String,
          municipio: datos['municipio'] as String,
          provincia: datos['provincia'] as String,
          horario: datos['horario'] as String,
          latitud: datos['latitud'] as double,
          longitud: datos['longitud'] as double,
          precio: datos['precio'] as double,
        );
      }).toList();

      setState(() {
        _gasolineras = estaciones;
        _datosDescargados = true;
        _error = null;
      });

      // Envía las gasolineras a HomePage para mostrarlas
      // como marcadores en MapPage.
      widget.onGasolinerasChanged?.call(
        estaciones
            .map(
              (g) => <String, dynamic>{
                'nombre': g.nombre,
                'direccion': g.direccion,
                'municipio': g.municipio,
                'provincia': g.provincia,
                'horario': g.horario,
                'latitud': g.latitud,
                'longitud': g.longitud,
                'precio': g.precio,
              },
            )
            .toList(),
      );
    } catch (e) {
      if (!mounted || consultaActual != _consultaId) return;

      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _datosDescargados = false;
      });

      widget.onGasolinerasChanged?.call([]);
    } finally {
      if (mounted && consultaActual == _consultaId) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _formatearPrecio(double precio) {
    return '${precio.toStringAsFixed(3).replaceAll('.', ',')} €/L';
  }

  void _cambiarCombustible(_Combustible combustible) {
    if (_combustible == combustible) return;

    setState(() {
      _combustible = combustible;
      _datosDescargados = false;
      _gasolineras = [];
    });

    widget.onGasolinerasChanged?.call([]);
    _consultarGasolineras();
  }

  @override
  void dispose() {
    // Invalida cualquier petición que todavía esté en curso.
    _consultaId++;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rutaDisponible = widget.coordenadasRuta.isNotEmpty;

    return Container(
      color: _background,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 24),
        children: [
          Text(
            _nombreCombustible.toUpperCase(),
            style: const TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w800,
              color: Color(0xFF202A36),
            ),
          ),
          const SizedBox(height: 7),
          const Text(
            'Encuentra las estaciones de servicio más '
            'económicas cerca de tu ruta.',
            style: TextStyle(color: Color(0xFF64748B), height: 1.5),
          ),
          const SizedBox(height: 18),

          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tipo de combustible',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _filtro('Gasóleo A', _Combustible.gasoleoA),
                    _filtro('Gasóleo B', _Combustible.gasoleoB),
                    _filtro('AdBlue', _Combustible.adblue),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          if (!rutaDisponible)
            _card(
              child: const Column(
                children: [
                  Icon(Icons.route_outlined, size: 48, color: _blue),
                  SizedBox(height: 12),
                  Text(
                    'Calcula primero tu ruta',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Ve a la sección Viaje, indica el origen '
                    'y el destino y pulsa Planificar viaje. '
                    'Después podrás consultar las gasolineras.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFF64748B), height: 1.5),
                  ),
                ],
              ),
            ),

          if (_loading)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Center(child: CircularProgressIndicator(color: _blue)),
            ),

          if (_error != null && !_loading)
            _card(
              child: Column(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 38),
                  const SizedBox(height: 10),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _consultarGasolineras,
                    child: const Text('Reintentar'),
                  ),
                ],
              ),
            ),

          if (!_loading &&
              _error == null &&
              rutaDisponible &&
              _datosDescargados) ...[
            const SizedBox(height: 14),

            if (_gasolineras.isEmpty)
              _card(
                child: const Column(
                  children: [
                    Icon(
                      Icons.local_gas_station_outlined,
                      size: 45,
                      color: Colors.blueGrey,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'No se han encontrado gasolineras',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Prueba a aumentar la distancia máxima '
                      'respecto a la ruta.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),

            for (var i = 0; i < _gasolineras.length; i++)
              _tarjetaGasolinera(_gasolineras[i], esLaMasBarata: i == 0),

            if (_gasolineras.length >= 2) ...[
              const SizedBox(height: 10),
              _buildAhorro(),
            ],
          ],

          const SizedBox(height: 16),
          const Text(
            'Precios obtenidos del Geoportal de Hidrocarburos '
            'del MITECO. Pueden variar según la actualización '
            'de los datos y los descuentos de cada estación.',
            style: TextStyle(
              fontSize: 11,
              color: Color(0xFF64748B),
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _filtro(String texto, _Combustible combustible) {
    final seleccionado = _combustible == combustible;

    return ChoiceChip(
      label: Text(texto),
      selected: seleccionado,
      selectedColor: _blue,
      labelStyle: TextStyle(
        color: seleccionado ? Colors.white : Colors.black87,
        fontWeight: FontWeight.w600,
      ),
      onSelected: (_) {
        _cambiarCombustible(combustible);
      },
    );
  }

  Widget _buildAhorro() {
    if (_gasolineras.length < 2) {
      return const SizedBox.shrink();
    }

    // Precio medio de todas las gasolineras encontradas.
    final precioMedio =
        _gasolineras.map((g) => g.precio).reduce((a, b) => a + b) /
        _gasolineras.length;

    // La lista ya está ordenada de menor a mayor precio.
    final precioMasBarato = _gasolineras.first.precio;

    // Diferencia de precio por litro.
    final ahorroPorLitro = precioMedio - precioMasBarato;

    // Estimación para un repostaje de 80 litros.
    final ahorro50Litros = ahorroPorLitro * 80;

    String euros(double valor) {
      return '${valor.toStringAsFixed(2).replaceAll('.', ',')} €';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F7EC),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFF9AD5AA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.savings_outlined,
                color: Color(0xFF188044),
                size: 26,
              ),
              const SizedBox(width: 9),
              const Expanded(
                child: Text(
                  'Ahorro con la más barata',
                  style: TextStyle(
                    color: Color(0xFF176B38),
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'AHORRO POR LITRO',
            style: TextStyle(
              color: Color(0xFF487456),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${euros(ahorroPorLitro)} / L',
            style: const TextStyle(
              color: Color(0xFF188044),
              fontSize: 28,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFFB9DFC3)),
          const SizedBox(height: 8),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Ahorro estimado en 80 litros',
                  style: TextStyle(
                    color: Color(0xFF315D3D),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                euros(ahorro50Litros),
                style: const TextStyle(
                  color: Color(0xFF188044),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Precio medio: ${_formatearPrecio(precioMedio)}'
            '\nPrecio más barato: ${_formatearPrecio(precioMasBarato)}',
            style: const TextStyle(
              color: Color(0xFF487456),
              fontSize: 12,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tarjetaGasolinera(
    _Gasolinera gasolinera, {
    required bool esLaMasBarata,
  }) {
    final posicionActual = widget.ubicacionActual;
    final distanciaKm = posicionActual == null
        ? null
        : const Distance().as(
            LengthUnit.Kilometer,
            posicionActual,
            LatLng(gasolinera.latitud, gasolinera.longitud),
          );

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: esLaMasBarata ? Colors.green.shade300 : _border,
          width: esLaMasBarata ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_gas_station, color: _blue, size: 26),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  gasolinera.nombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _formatearPrecio(gasolinera.precio),
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: esLaMasBarata ? Colors.green : _blue,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 5),
              if (esLaMasBarata)
                const Icon(
                  Icons.emoji_events,
                  color: Color(0xFFD18400),
                  size: 19,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            gasolinera.direccion,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
          Text(
            '${gasolinera.municipio} (${gasolinera.provincia})',
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                distanciaKm == null
                    ? 'Ubicación no disponible'
                    : '${distanciaKm.toStringAsFixed(1)} km',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          if (gasolinera.horario.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.access_time, size: 15, color: Colors.blueGrey),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    gasolinera.horario,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: () async {
                final url = Uri.https('www.google.com', '/maps/dir/', {
                  'api': '1',
                  'destination': '${gasolinera.latitud},${gasolinera.longitud}',
                });

                final abierto = await launchUrl(
                  url,
                  mode: LaunchMode.platformDefault,
                );

                if (!abierto && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('No se ha podido abrir Google Maps.'),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.directions),
              label: const Text('Cómo llegar'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(15),
      ),
      child: child,
    );
  }
}

class _Gasolinera {
  final String nombre;
  final String direccion;
  final String municipio;
  final String provincia;
  final String horario;

  final double latitud;
  final double longitud;
  final double precio;

  const _Gasolinera({
    required this.nombre,
    required this.direccion,
    required this.municipio,
    required this.provincia,
    required this.horario,
    required this.latitud,
    required this.longitud,
    required this.precio,
  });
}
