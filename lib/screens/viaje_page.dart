import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'route_distance.dart';

const Color _blue = Color(0xFF1053A4);
const Color _background = Color(0xFFF3F6F9);
const Color _border = Color(0xFFD8E0E9);

class ViajePage extends StatefulWidget {
  // Callback para compartir la geometría de la ruta
  // calculada con HomePage.
  final ValueChanged<List<List<double>>>? onRutaCalculada;
  final ValueChanged<int>? onDuracionRutaCalculada;
  final LatLng? posicionActual;

  const ViajePage({
    super.key,
    this.onRutaCalculada,
    this.onDuracionRutaCalculada,
    this.posicionActual,
  });

  @override
  State<ViajePage> createState() => _ViajePageState();
}

class _ViajePageState extends State<ViajePage> {
  static const _ubicacionActualLabel = 'Mi ubicación actual';

  String _origenTexto = _ubicacionActualLabel;
  String _destinoTexto = '';
  _Lugar? _origenSeleccionado;
  _Lugar? _destinoSeleccionado;
  Position? _posicionActual;
  Future<void>? _ubicacionActualFuture;
  bool _ubicacionCargando = true;
  int _busquedaOrigenId = 0;
  int _busquedaDestinoId = 0;
  DateTime? _ultimaSolicitudSugerencias;

  bool _loading = false;
  String? _error;

  double? _distanciaKm;
  double? _tiempoConduccion;

  DateTime? _horaSalida;
  DateTime? _horaLlegada;

  List<_Parada> _paradas = [];

  // Coordenadas completas de la ruta calculada.
  //
  // Cada punto contiene:
  // [longitud, latitud]
  //
  // Esta información se comparte con HomePage
  // para localizar gasolineras próximas al itinerario.
  List<List<double>> _coordenadasRuta = [];

  double? get _progresoRuta {
    final posicion =
        widget.posicionActual ??
        (_posicionActual == null
            ? null
            : LatLng(
                _posicionActual!.latitude,
                _posicionActual!.longitude,
              ));
    if (posicion == null) return null;

    return progresoPuntoRuta(
      latitud: posicion.latitude,
      longitud: posicion.longitude,
      ruta: _coordenadasRuta,
    );
  }

  @override
  void initState() {
    super.initState();
    _ubicacionActualFuture = _obtenerUbicacionActual();
  }

  Future<void> _obtenerUbicacionActual() async {
    try {
      final servicioActivo = await Geolocator.isLocationServiceEnabled();
      if (!servicioActivo) {
        throw Exception('Activa los servicios de ubicación del dispositivo.');
      }

      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }

      if (permiso == LocationPermission.denied ||
          permiso == LocationPermission.deniedForever) {
        throw Exception('Necesitas permitir el acceso a tu ubicación.');
      }

      final posicion = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;
      setState(() {
        _posicionActual = posicion;
        _ubicacionCargando = false;
        if (_error != null &&
            (_error!.contains('ubicación') || _error!.contains('ubicacion'))) {
          _error = null;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _ubicacionCargando = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<_Lugar> _buscarLocalidad(String localidad) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': localidad,
      'format': 'jsonv2',
      'limit': '1',
      'countrycodes': 'es',
    });

    final response = await http.get(
      uri,
      headers: {
        'Accept': 'application/json',
        'User-Agent': 'ArcenFlutterApp/1.0',
      },
    );

    if (response.statusCode != 200) {
      throw Exception('No se ha podido localizar "$localidad".');
    }

    final resultados = jsonDecode(utf8.decode(response.bodyBytes)) as List;

    if (resultados.isEmpty) {
      throw Exception('No se encuentra la localidad "$localidad".');
    }

    return _Lugar.fromJson(resultados.first as Map<String, dynamic>);
  }

  Future<Iterable<_Lugar>> _buscarSugerencias(
    String texto, {
    required bool esOrigen,
  }) async {
    final idBusqueda = esOrigen ? ++_busquedaOrigenId : ++_busquedaDestinoId;
    final consulta = texto.trim();

    if (consulta.length < 3 ||
        (esOrigen && consulta == _ubicacionActualLabel)) {
      return const [];
    }

    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted ||
        idBusqueda != (esOrigen ? _busquedaOrigenId : _busquedaDestinoId)) {
      return const [];
    }

    final ultimaSolicitud = _ultimaSolicitudSugerencias;
    if (ultimaSolicitud != null) {
      final espera =
          const Duration(seconds: 1) -
          DateTime.now().difference(ultimaSolicitud);
      if (espera > Duration.zero) {
        await Future<void>.delayed(espera);
      }
    }

    if (!mounted ||
        idBusqueda != (esOrigen ? _busquedaOrigenId : _busquedaDestinoId)) {
      return const [];
    }

    _ultimaSolicitudSugerencias = DateTime.now();

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
        'q': consulta,
        'format': 'jsonv2',
        'limit': '5',
        'countrycodes': 'es',
      });
      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'ArcenFlutterApp/1.0',
        },
      );

      if (response.statusCode != 200) {
        throw Exception('No se pudieron cargar las sugerencias de lugares.');
      }

      if (!mounted ||
          idBusqueda != (esOrigen ? _busquedaOrigenId : _busquedaDestinoId)) {
        return const [];
      }

      final resultados = jsonDecode(utf8.decode(response.bodyBytes)) as List;
      return resultados
          .map(
            (resultado) => _Lugar.fromJson(resultado as Map<String, dynamic>),
          )
          .toList();
    } catch (error) {
      if (mounted &&
          idBusqueda == (esOrigen ? _busquedaOrigenId : _busquedaDestinoId)) {
        setState(() {
          _error = error.toString().replaceFirst('Exception: ', '');
        });
      }
      return const [];
    }
  }

  Future<_Lugar> _resolverLocalidad({
    required String texto,
    required bool esOrigen,
  }) async {
    final seleccionada = esOrigen ? _origenSeleccionado : _destinoSeleccionado;

    if (seleccionada != null && seleccionada.nombre == texto) {
      return seleccionada;
    }

    if (esOrigen && texto == _ubicacionActualLabel) {
      if (_posicionActual == null && _ubicacionCargando) {
        await _ubicacionActualFuture;
      }
      final posicion = _posicionActual;
      if (posicion == null) {
        throw Exception(
          'No se pudo obtener tu ubicación actual. '
          'Escribe un origen para continuar.',
        );
      }
      return _Lugar(
        nombre: _ubicacionActualLabel,
        latitud: posicion.latitude,
        longitud: posicion.longitude,
      );
    }

    return _buscarLocalidad(texto);
  }

  Future<void> _planificarViaje() async {
    FocusScope.of(context).unfocus();

    final origen = _origenTexto.trim();
    final destino = _destinoTexto.trim();

    if (origen.isEmpty || destino.isEmpty) {
      setState(() {
        _error = 'Introduce un origen y un destino.';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      // 1. Buscar coordenadas del origen y destino.
      final resultados = await Future.wait([
        _resolverLocalidad(texto: origen, esOrigen: true),
        _resolverLocalidad(texto: destino, esOrigen: false),
      ]);

      final inicio = resultados[0];
      final fin = resultados[1];

      final latInicio = inicio.latitud;
      final lonInicio = inicio.longitud;
      final latFin = fin.latitud;
      final lonFin = fin.longitud;

      // 2. Calcular ruta mediante OSRM.
      //
      // overview=full devuelve la geometría completa.
      // geometries=geojson devuelve coordenadas
      // en formato [longitud, latitud].
      final uri = Uri.https(
        'router.project-osrm.org',
        '/route/v1/driving/'
            '$lonInicio,$latInicio;$lonFin,$latFin',
        {'overview': 'full', 'geometries': 'geojson', 'steps': 'false'},
      );

      final response = await http.get(uri);

      if (response.statusCode != 200) {
        throw Exception('No se ha podido calcular la ruta.');
      }

      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

      if (data['code'] != 'Ok' || (data['routes'] as List).isEmpty) {
        throw Exception('No se ha encontrado una ruta.');
      }

      final route = (data['routes'] as List).first as Map<String, dynamic>;

      // 3. Obtener distancia y duración.
      final km = (route['distance'] as num).toDouble() / 1000;

      final segundos = (route['duration'] as num).toDouble();

      // 4. Obtener la geometría completa de la ruta.
      final geometry = route['geometry'] as Map<String, dynamic>;

      final coordinates = (geometry['coordinates'] as List)
          .map<List<double>>(
            (point) => [
              (point[0] as num).toDouble(),
              (point[1] as num).toDouble(),
            ],
          )
          .toList();

      // 5. Calcular paradas orientativas.
      //
      // Pausa de 45 minutos por cada bloque
      // de 4 horas y 30 minutos de conducción.
      //
      // Es una estimación, no un cálculo legal completo.
      const bloqueConduccion = 4.5 * 3600;
      const duracionPausa = 45 * 60;

      final paradas = <_Parada>[];

      var segundosConduccionAcumulados = bloqueConduccion;

      while (segundos > segundosConduccionAcumulados) {
        final numero = paradas.length + 1;

        final tiempoParada =
            segundosConduccionAcumulados + paradas.length * duracionPausa;

        final kmParada = km * segundosConduccionAcumulados / segundos;

        paradas.add(
          _Parada(
            titulo: 'Pausa de 45 min',
            detalle:
                'Parada orientativa · '
                'km ${kmParada.round()}',
            segundosDesdeSalida: tiempoParada,
            km: kmParada,
            color: const Color(0xFFD18400),
          ),
        );

        segundosConduccionAcumulados = bloqueConduccion * (numero + 1);
      }

      final salida = DateTime.now();

      final segundosPausas = paradas.length * duracionPausa;

      // 6. Guardar todos los datos de la ruta.
      setState(() {
        _distanciaKm = km;
        _tiempoConduccion = segundos;

        _horaSalida = salida;

        _horaLlegada = salida.add(
          Duration(seconds: segundos.round() + segundosPausas),
        );

        _paradas = paradas;

        // Guardar geometría completa.
        _coordenadasRuta = coordinates;
      });

      // 7. Compartir ruta con HomePage.
      //
      // HomePage guardará las coordenadas y se las
      // pasará a GasoleoPage.
      widget.onRutaCalculada?.call(_coordenadasRuta);
      widget.onDuracionRutaCalculada?.call(segundos.round());
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _hora(DateTime? fecha) {
    if (fecha == null) return '--:--';

    final h = fecha.hour.toString().padLeft(2, '0');
    final m = fecha.minute.toString().padLeft(2, '0');

    return '$h:$m';
  }

  String _duracion(double? segundos) {
    if (segundos == null) return '--';

    final minutos = (segundos / 60).round();

    final horas = minutos ~/ 60;
    final resto = minutos % 60;

    return '$horas h '
        '${resto.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _background,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 18, 14, 24),
        children: [
          const Text(
            'NUEVO VIAJE',
            style: TextStyle(
              fontSize: 23,
              fontWeight: FontWeight.w800,
              color: Color(0xFF202A36),
            ),
          ),

          const SizedBox(height: 7),

          const Text(
            'Indica el origen y el destino para calcular '
            'tu ruta y organizar las paradas.',
            style: TextStyle(color: Color(0xFF64748B), height: 1.5),
          ),

          const SizedBox(height: 18),

          // ------------------------------------------------
          // 1. RUTA
          // ------------------------------------------------
          _card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '1 · Ruta',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),

                const SizedBox(height: 16),

                _campoLocalidad(
                  titulo: 'ORIGEN',
                  icono: Icons.trip_origin,
                  esOrigen: true,
                ),

                const SizedBox(height: 14),

                _campoLocalidad(
                  titulo: 'DESTINO',
                  icono: Icons.location_on,
                  esOrigen: false,
                ),

                const SizedBox(height: 18),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _loading ? null : _planificarViaje,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                    ),
                    child: _loading
                        ? const SizedBox(
                            width: 21,
                            height: 21,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Text(
                            'PLANIFICAR VIAJE',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                  ),
                ),

                if (_error != null) ...[
                  const SizedBox(height: 12),

                  Text(_error!, style: const TextStyle(color: Colors.red)),
                ],
              ],
            ),
          ),

          // ------------------------------------------------
          // 2. VIAJE Y PARADAS
          // ------------------------------------------------
          if (_distanciaKm != null) ...[
            const SizedBox(height: 14),

            _card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '2 · Tu viaje y tus paradas',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),

                  const SizedBox(height: 14),

                  Row(
                    children: [
                      Expanded(
                        child: _dato(
                          '${_distanciaKm!.round()} km',
                          'Distancia aprox.',
                        ),
                      ),

                      const SizedBox(width: 6),

                      Expanded(
                        child: _dato(
                          _duracion(_tiempoConduccion),
                          'Conducción',
                        ),
                      ),

                      const SizedBox(width: 6),

                      Expanded(
                        child: _dato(_hora(_horaLlegada), 'Llegada aprox.'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 22),

                  _barraProgresoRuta(),

                  const SizedBox(height: 18),

                  _evento(
                    hora: _hora(_horaSalida),
                    titulo:
                        'Salida · '
                        '$_origenTexto',
                    detalle: 'Inicio del viaje',
                    color: _blue,
                    primero: true,
                  ),

                  for (final parada in _paradas)
                    _evento(
                      hora: _hora(
                        _horaSalida?.add(
                          Duration(seconds: parada.segundosDesdeSalida.round()),
                        ),
                      ),
                      titulo: parada.titulo,
                      detalle: parada.detalle,
                      color: parada.color,
                    ),

                  _evento(
                    hora: _hora(_horaLlegada),
                    titulo:
                        'Llegada · '
                        '$_destinoTexto',
                    detalle:
                        'Fin del recorrido · '
                        '${_distanciaKm!.round()} km',
                    color: const Color(0xFF202A36),
                    ultimo: true,
                  ),

                  const SizedBox(height: 12),

                  const Text(
                    'Estimación orientativa. Las paradas '
                    'no corresponden todavía a áreas de '
                    'servicio reales y la ruta no está '
                    'optimizada para camiones.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _barraProgresoRuta() {
    final progress = _progresoRuta;

    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'SALIDA',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  Text(
                    _hora(_horaSalida),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text(
                  'LLEGADA',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF64748B),
                  ),
                ),
                Text(
                  _hora(_horaLlegada),
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 5),
        LayoutBuilder(
          builder: (context, constraints) {
            final progressWidth = (constraints.maxWidth - 26) *
                (progress ?? 0);
            return SizedBox(
              height: 32,
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  Positioned(
                    left: 2,
                    right: 2,
                    top: 13,
                    child: Container(
                      height: 6,
                      decoration: BoxDecoration(
                        color: _border,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 2,
                    top: 13,
                    child: Container(
                      width: progressWidth,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _blue,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Positioned(
                    left: (constraints.maxWidth - 26) * (progress ?? 0),
                    top: 2,
                    child: Icon(
                      Icons.local_shipping,
                      size: 26,
                      color: progress == null ? Colors.blueGrey : _blue,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
        if (progress == null)
          const Align(
            alignment: Alignment.centerLeft,
            child: Text(
              'Esperando ubicación GPS para mostrar el avance.',
              style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
            ),
          ),
      ],
    );
  }

  // ------------------------------------------------------
  // CAMPO DE LOCALIDAD
  // ------------------------------------------------------

  Widget _campoLocalidad({
    required String titulo,
    required IconData icono,
    required bool esOrigen,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          titulo,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 11,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.7,
          ),
        ),

        const SizedBox(height: 6),

        Autocomplete<_Lugar>(
          displayStringForOption: (lugar) => lugar.nombre,
          initialValue: TextEditingValue(
            text: esOrigen ? _origenTexto : _destinoTexto,
          ),
          optionsBuilder: (valor) =>
              _buscarSugerencias(valor.text, esOrigen: esOrigen),
          onSelected: (lugar) {
            setState(() {
              if (esOrigen) {
                _origenTexto = lugar.nombre;
                _origenSeleccionado = lugar;
              } else {
                _destinoTexto = lugar.nombre;
                _destinoSeleccionado = lugar;
              }
            });
          },
          fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              textCapitalization: TextCapitalization.words,
              onChanged: (texto) {
                if (esOrigen) {
                  _origenTexto = texto;
                  if (_origenSeleccionado?.nombre != texto) {
                    _origenSeleccionado = null;
                  }
                } else {
                  _destinoTexto = texto;
                  if (_destinoSeleccionado?.nombre != texto) {
                    _destinoSeleccionado = null;
                  }
                }
              },
              onSubmitted: (_) => onFieldSubmitted(),
              decoration: InputDecoration(
                prefixIcon: Icon(icono, color: _blue, size: 20),
                suffixIcon: esOrigen && _ubicacionCargando
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : null,
                hintText: 'Escribe una localidad o dirección',
                filled: true,
                fillColor: const Color(0xFFF3F6F9),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 14,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: const BorderSide(color: _border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(9),
                  borderSide: const BorderSide(color: _border),
                ),
              ),
            );
          },
          optionsViewBuilder: (context, onSelected, opciones) {
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 4,
                borderRadius: BorderRadius.circular(9),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 220),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    shrinkWrap: true,
                    itemCount: opciones.length,
                    itemBuilder: (context, index) {
                      final lugar = opciones.elementAt(index);
                      return ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.location_on_outlined,
                          color: _blue,
                        ),
                        title: Text(
                          lugar.nombre,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => onSelected(lugar),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  // ------------------------------------------------------
  // TARJETA
  // ------------------------------------------------------

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: _border),
        borderRadius: BorderRadius.circular(15),
      ),
      child: child,
    );
  }

  // ------------------------------------------------------
  // DATO
  // ------------------------------------------------------

  Widget _dato(String valor, String etiqueta) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
      decoration: BoxDecoration(
        color: _background,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              valor,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),

          const SizedBox(height: 5),

          Text(
            etiqueta,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------
  // EVENTO DEL VIAJE
  // ------------------------------------------------------

  Widget _evento({
    required String hora,
    required String titulo,
    required String detalle,
    required Color color,
    bool primero = false,
    bool ultimo = false,
  }) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 52,
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(
                hora,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),

          SizedBox(
            width: 22,
            child: Column(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),

                if (!ultimo)
                  Expanded(child: Container(width: 2, color: _border)),
              ],
            ),
          ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 6, bottom: 22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    titulo,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                  ),

                  const SizedBox(height: 4),

                  Text(
                    detalle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------------
// MODELO DE PARADA
// --------------------------------------------------------

class _Parada {
  final String titulo;
  final String detalle;
  final double segundosDesdeSalida;
  final double km;
  final Color color;

  const _Parada({
    required this.titulo,
    required this.detalle,
    required this.segundosDesdeSalida,
    required this.km,
    required this.color,
  });
}

class _Lugar {
  final String nombre;
  final double latitud;
  final double longitud;

  const _Lugar({
    required this.nombre,
    required this.latitud,
    required this.longitud,
  });

  factory _Lugar.fromJson(Map<String, dynamic> json) {
    final nombre = json['display_name']?.toString();
    final latitud = double.tryParse(json['lat']?.toString() ?? '');
    final longitud = double.tryParse(json['lon']?.toString() ?? '');

    if (nombre == null ||
        nombre.isEmpty ||
        latitud == null ||
        longitud == null) {
      throw const FormatException('La ubicación recibida no es válida.');
    }

    return _Lugar(nombre: nombre, latitud: latitud, longitud: longitud);
  }
}
