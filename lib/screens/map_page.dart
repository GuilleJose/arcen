import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'avisos_page.dart';
import '../services/open_meteo_alerts.dart';
import 'route_distance.dart';

class MapPage extends StatefulWidget {
  final void Function(String poblacion, String provincia)? onLocationChanged;

  // Coordenadas OSRM: [longitud, latitud].
  final List<List<double>> coordenadasRuta;

  // Datos compartidos desde HomePage.
  final List<Map<String, dynamic>> gasolineras;
  final List<AvisoItem> avisos;
  final bool mostrarAvisos;
  final List<Map<String, dynamic>> parkings;
  final List<AvisoMeteorologico> avisosMeteorologicos;
  final ValueChanged<LatLng>? onPositionChanged;
  final ValueChanged<Position>? onGpsPositionChanged;
  final double distanciaParkingsRutaKm;
  final double distanciaAvisosGpsKm;
  final double distanciaAvisosMeteorologicosRutaKm;

  const MapPage({
    super.key,
    this.onLocationChanged,
    this.coordenadasRuta = const [],
    this.gasolineras = const [],
    this.avisos = const [],
    this.mostrarAvisos = false,
    this.parkings = const [],
    this.avisosMeteorologicos = const [],
    this.onPositionChanged,
    this.onGpsPositionChanged,
    this.distanciaParkingsRutaKm = 0.1,
    this.distanciaAvisosGpsKm = 5,
    this.distanciaAvisosMeteorologicosRutaKm = 10,
  });

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();

  StreamSubscription<Position>? _positionSubscription;

  LatLng? _currentPosition;
  LatLng? _lastGeocodedPosition;

  bool _mapReady = false;
  bool _loading = true;
  bool _following = true;
  bool _geocoding = false;

  String? _error;
  RouteDistanceIndex? _indiceRutaParkings;

  static const LatLng _initialPosition = LatLng(40.4168, -3.7038);

  List<LatLng> get _puntosRuta {
    return widget.coordenadasRuta
        .where((p) => p.length >= 2)
        .map((p) => LatLng(p[1], p[0]))
        .toList();
  }

  @override
  void initState() {
    super.initState();
    _actualizarIndiceRutaParkings();
    _startLocation();
  }

  @override
  void didUpdateWidget(covariant MapPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    final rutaCambiada = oldWidget.coordenadasRuta != widget.coordenadasRuta;

    if (rutaCambiada ||
        oldWidget.distanciaParkingsRutaKm != widget.distanciaParkingsRutaKm) {
      _actualizarIndiceRutaParkings();
    }

    if (rutaCambiada && widget.coordenadasRuta.isNotEmpty) {
      _following = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _encuadrarRuta();
      });
    }
  }

  void _actualizarIndiceRutaParkings() {
    _indiceRutaParkings = widget.coordenadasRuta.isEmpty
        ? null
        : RouteDistanceIndex(
            widget.coordenadasRuta,
            maxDistanceKm: widget.distanciaParkingsRutaKm,
          );
  }

  void _encuadrarRuta() {
    if (!_mapReady) return;

    final puntos = _puntosRuta;
    if (puntos.isEmpty) return;

    if (puntos.length == 1) {
      _mapController.move(puntos.first, 13);
      return;
    }

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(puntos),
        padding: const EdgeInsets.all(48),
        maxZoom: 14,
      ),
    );
  }

  Future<void> _startLocation() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Activa los servicios de ubicación del dispositivo.');
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('Necesitas permitir el acceso a tu ubicación.');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;

      _updatePosition(position, centerMap: true);
      setState(() {
        _loading = false;
        _error = null;
      });

      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 100,
            ),
          ).listen(
            (position) {
              if (!mounted) return;
              _updatePosition(position, centerMap: _following);
            },
            onError: (Object error) {
              if (!mounted) return;
              setState(() {
                _error = 'No se puede actualizar la ubicación.';
              });
            },
          );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  void _updatePosition(Position position, {required bool centerMap}) {
    final point = LatLng(position.latitude, position.longitude);
    setState(() {
      _currentPosition = point;
    });
    widget.onPositionChanged?.call(point);
    widget.onGpsPositionChanged?.call(position);

    if (centerMap && _mapReady) {
      _mapController.move(point, 16);
    }
    _updateAddress(point);
  }

  Future<void> _updateAddress(LatLng point) async {
    if (_lastGeocodedPosition != null) {
      final distance = const Distance().as(
        LengthUnit.Meter,
        _lastGeocodedPosition!,
        point,
      );
      if (distance < 1000) return;
    }

    if (_geocoding) return;
    _geocoding = true;
    _lastGeocodedPosition = point;

    try {
      final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
        'format': 'jsonv2',
        'lat': point.latitude.toString(),
        'lon': point.longitude.toString(),
        'zoom': '10',
        'addressdetails': '1',
      });

      final response = await http.get(
        uri,
        headers: {'User-Agent': 'ArcenApp/1.0 (ubicacion)'},
      );

      if (response.statusCode != 200) {
        throw Exception('No se pudo consultar la dirección.');
      }

      final data =
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      final address = data['address'] as Map<String, dynamic>?;

      if (address == null) {
        throw Exception('No se encontró la dirección.');
      }

      final poblacion =
          address['city'] ??
          address['town'] ??
          address['village'] ??
          address['municipality'] ??
          address['hamlet'] ??
          address['county'] ??
          'Ubicación actual';

      final provincia =
          address['province'] ??
          address['state_district'] ??
          address['county'] ??
          address['state'] ??
          '';

      if (!mounted) return;
      widget.onLocationChanged?.call(
        poblacion.toString(),
        provincia.toString(),
      );
    } catch (_) {
      // Si falla la consulta, el mapa y el GPS siguen funcionando.
    } finally {
      _geocoding = false;
    }
  }

  void _centerOnLocation() {
    final position = _currentPosition;
    if (position == null) {
      _startLocation();
      return;
    }

    setState(() {
      _following = true;
    });
    _mapController.move(position, 16);
  }

  List<Marker> _crearMarcadoresGasolineras() {
    return widget.gasolineras
        .map((gasolinera) {
          final lat = (gasolinera['latitud'] as num?)?.toDouble();
          final lon = (gasolinera['longitud'] as num?)?.toDouble();
          if (lat == null || lon == null) return null;

          final nombre = gasolinera['nombre']?.toString() ?? 'Gasolinera';
          final precio = (gasolinera['precio'] as num?)?.toDouble();
          final municipio = gasolinera['municipio']?.toString() ?? '';

          return Marker(
            point: LatLng(lat, lon),
            width: 46,
            height: 54,
            child: GestureDetector(
              onTap: () {
                showModalBottomSheet<void>(
                  context: context,
                  builder: (context) => SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nombre,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          if (municipio.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(municipio),
                            ),
                          if (precio != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 10),
                              child: Text(
                                '${precio.toStringAsFixed(3).replaceAll('.', ',')} €/L',
                                style: const TextStyle(
                                  color: Colors.green,
                                  fontSize: 22,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
              child: const Icon(
                Icons.local_gas_station,
                color: Colors.deepOrange,
                size: 20,
                shadows: [Shadow(color: Colors.white, blurRadius: 3)],
              ),
            ),
          );
        })
        .whereType<Marker>()
        .toList();
  }

  List<Marker> _crearMarcadoresParkings() {
    if (widget.coordenadasRuta.isEmpty) return [];

    return widget.parkings
        .map((parking) {
          final lat =
              (parking['latitud'] ?? parking['latitude'] ?? parking['lat'])
                  as num?;
          final lon =
              (parking['longitud'] ??
                      parking['longitude'] ??
                      parking['lon'] ??
                      parking['lng'])
                  as num?;

          if (lat == null || lon == null) return null;

          final latitud = lat.toDouble();
          final longitud = lon.toDouble();

          if (!latitud.isFinite ||
              !longitud.isFinite ||
              latitud < -90 ||
              latitud > 90 ||
              longitud < -180 ||
              longitud > 180) {
            return null;
          }

          final distanciaRuta = _indiceRutaParkings?.distanciaMetros(
            latitud: latitud,
            longitud: longitud,
          );

          if (distanciaRuta == null) return null;

          final nombre =
              (parking['nombre'] ??
                      parking['name'] ??
                      parking['titulo'] ??
                      'Parking de camiones')
                  .toString();
          final municipio =
              (parking['municipio'] ??
                      parking['localidad'] ??
                      parking['poblacion'] ??
                      parking['localidadNombre'] ??
                      '')
                  .toString();
          final direccion = (parking['direccion'] ?? parking['address'] ?? '')
              .toString();
          final plazas =
              parking['plazas'] ??
              parking['capacidad'] ??
              parking['numeroPlazas'] ??
              parking['plazasCamion'];
          final tipo = (parking['tipo'] ?? parking['tipoParking'] ?? '')
              .toString();

          final parkingId =
              (parking['id'] ?? parking['docId'] ?? parking['documentId'])
                  ?.toString();

          String normalizarEstado(dynamic valor) {
            final estado = valor?.toString().toLowerCase().trim() ?? '';
            if (estado == 'libre') return 'Libre';
            if (estado == 'pocas' || estado == 'pocas plazas') return 'Pocas';
            if (estado == 'lleno' || estado == 'completo') return 'Lleno';
            return '';
          }

          DateTime? leerFecha(dynamic valor) {
            if (valor is Timestamp) return valor.toDate();
            if (valor is DateTime) return valor;
            if (valor is String) return DateTime.tryParse(valor);
            return null;
          }

          String tiempoDesde(DateTime? fecha) {
            if (fecha == null) return 'Sin avisos todavía';
            final minutos = DateTime.now()
                .difference(fecha)
                .inMinutes
                .clamp(0, 999999);
            if (minutos < 1) return 'Último aviso hace menos de 1 min';
            if (minutos == 1) return 'Último aviso hace 1 min';
            if (minutos < 60) return 'Último aviso hace $minutos min';

            final horas = minutos ~/ 60;
            final minutosRestantes = minutos % 60;
            if (horas < 24) {
              return minutosRestantes == 0
                  ? 'Último aviso hace $horas h'
                  : 'Último aviso hace $horas h $minutosRestantes min';
            }
            return 'Último aviso hace ${horas ~/ 24} d';
          }

          Color colorEstado(String estado) {
            switch (estado) {
              case 'Libre':
                return const Color(0xFF187641);
              case 'Pocas':
                return const Color(0xFF946200);
              case 'Lleno':
                return const Color(0xFFB42318);
              default:
                return Colors.blueGrey;
            }
          }

          final estadoInicial = normalizarEstado(
            parking['estadoDisponibilidad'] ?? parking['estado'],
          );
          final fechaInicial = leerFecha(
            parking['estadoActualizado'] ??
                parking['ultimoAviso'] ??
                parking['fechaAviso'],
          );

          return Marker(
            point: LatLng(latitud, longitud),
            width: 32,
            height: 38,
            child: GestureDetector(
              onTap: () {
                var estadoActual = estadoInicial;
                var fechaActual = fechaInicial;
                var guardando = false;

                showModalBottomSheet<void>(
                  context: context,
                  isScrollControlled: true,
                  showDragHandle: true,
                  builder: (modalContext) {
                    return StatefulBuilder(
                      builder: (context, actualizarModal) {
                        final color = colorEstado(estadoActual);
                        final etiqueta = estadoActual == 'Lleno'
                            ? 'LLENO'
                            : estadoActual == 'Libre' || estadoActual == 'Pocas'
                            ? 'HAY SITIO'
                            : 'SIN DATOS';

                        Future<void> marcarEstado(String nuevoEstado) async {
                          if (guardando) return;

                          final usuario = FirebaseAuth.instance.currentUser;
                          if (usuario == null) {
                            ScaffoldMessenger.of(modalContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Inicia sesión para informar del parking.',
                                ),
                              ),
                            );
                            return;
                          }

                          if (parkingId == null || parkingId.isEmpty) {
                            ScaffoldMessenger.of(modalContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'No se encuentra el ID del parking en Firebase.',
                                ),
                              ),
                            );
                            return;
                          }

                          actualizarModal(() {
                            guardando = true;
                          });

                          final ahora = DateTime.now();
                          try {
                            await FirebaseFirestore.instance
                                .collection('parkings')
                                .doc(parkingId)
                                .set({
                                  'estadoDisponibilidad': nuevoEstado,
                                  'estadoActualizado':
                                      FieldValue.serverTimestamp(),
                                  'ultimoAvisoUsuario': usuario.uid,
                                }, SetOptions(merge: true));

                            if (!modalContext.mounted) return;

                            parking['estadoDisponibilidad'] = nuevoEstado;
                            parking['estadoActualizado'] = Timestamp.fromDate(
                              ahora,
                            );

                            actualizarModal(() {
                              estadoActual = nuevoEstado;
                              fechaActual = ahora;
                              guardando = false;
                            });
                          } catch (_) {
                            if (!modalContext.mounted) return;
                            actualizarModal(() {
                              guardando = false;
                            });
                            ScaffoldMessenger.of(modalContext).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'No se pudo guardar el aviso. Comprueba tu conexión y los permisos de Firebase.',
                                ),
                              ),
                            );
                          }
                        }

                        return SafeArea(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 44,
                                      height: 44,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFE7EEF8),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: const Icon(
                                        Icons.local_parking,
                                        color: Color(0xFF0755A6),
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            nombre,
                                            style: const TextStyle(
                                              fontSize: 19,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          if (municipio.isNotEmpty)
                                            Padding(
                                              padding: const EdgeInsets.only(
                                                top: 4,
                                              ),
                                              child: Text(
                                                municipio,
                                                style: const TextStyle(
                                                  color: Colors.blueGrey,
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 7,
                                      ),
                                      decoration: BoxDecoration(
                                        color: estadoActual == 'Lleno'
                                            ? const Color(0xFFFCE4E4)
                                            : estadoActual == 'Libre' ||
                                                  estadoActual == 'Pocas'
                                            ? const Color(0xFFDDF5E5)
                                            : const Color(0xFFECEFF1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        etiqueta,
                                        style: TextStyle(
                                          color: estadoActual == 'Lleno'
                                              ? const Color(0xFFB42318)
                                              : estadoActual == 'Libre' ||
                                                    estadoActual == 'Pocas'
                                              ? const Color(0xFF176B36)
                                              : Colors.blueGrey,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 18),
                                if (direccion.isNotEmpty)
                                  _detalleParking('Dirección', direccion),
                                if (tipo.isNotEmpty)
                                  _detalleParking('Tipo', tipo),
                                if (plazas != null)
                                  _detalleParking('Plazas', '$plazas'),
                                const Divider(height: 28),
                                const Text(
                                  '¿Cómo está el parking ahora?',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _botonEstadoParking(
                                        texto: 'Libre',
                                        icono: Icons.check_circle,
                                        color: const Color(0xFF187641),
                                        fondo: const Color(0xFFE1F5E8),
                                        seleccionado: estadoActual == 'Libre',
                                        cargando: guardando,
                                        alPulsar: () => marcarEstado('Libre'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _botonEstadoParking(
                                        texto: 'Pocas',
                                        icono: Icons.warning_amber_rounded,
                                        color: const Color(0xFF946200),
                                        fondo: const Color(0xFFFFF0CC),
                                        seleccionado: estadoActual == 'Pocas',
                                        cargando: guardando,
                                        alPulsar: () => marcarEstado('Pocas'),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _botonEstadoParking(
                                        texto: 'Lleno',
                                        icono: Icons.cancel,
                                        color: const Color(0xFFB42318),
                                        fondo: const Color(0xFFFCE4E4),
                                        seleccionado: estadoActual == 'Lleno',
                                        cargando: guardando,
                                        alPulsar: () => marcarEstado('Lleno'),
                                      ),
                                    ),
                                  ],
                                ),
                                if (guardando) ...[
                                  const SizedBox(height: 12),
                                  const LinearProgressIndicator(),
                                ],
                                const SizedBox(height: 18),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF2F5F8),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.access_time,
                                        size: 19,
                                        color: color,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          tiempoDesde(fechaActual),
                                          style: const TextStyle(fontSize: 13),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  estadoActual.isEmpty
                                      ? 'Todavía no hay información de disponibilidad.'
                                      : 'Último estado comunicado: $estadoActual',
                                  style: const TextStyle(
                                    color: Colors.blueGrey,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
              child: const Icon(
                Icons.local_parking,
                color: Color(0xFF0755A6),
                size: 18,
                shadows: [Shadow(color: Colors.white, blurRadius: 3)],
              ),
            ),
          );
        })
        .whereType<Marker>()
        .toList();
  }

  Widget _detalleParking(String titulo, String valor) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text('$titulo: $valor'),
    );
  }

  Widget _botonEstadoParking({
    required String texto,
    required IconData icono,
    required Color color,
    required Color fondo,
    required bool seleccionado,
    required bool cargando,
    required VoidCallback alPulsar,
  }) {
    return Material(
      color: seleccionado ? fondo : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: cargando ? null : alPulsar,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: seleccionado ? color : Colors.black12,
              width: seleccionado ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icono, color: color, size: 23),
              const SizedBox(height: 5),
              Text(
                texto,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Avisos manuales: cerca del GPS o de la ruta; DGT: cerca del GPS.
  // Avisos meteorológicos: máximo 10 km de la ruta prevista.
  List<Marker> _crearMarcadoresAvisos() {
    if (!widget.mostrarAvisos) return [];

    const distanciaGps = Distance();

    // Unificamos los avisos de conductores/DGT y los meteorológicos.
    final todosLosAvisos = <AvisoItem>[
      ...widget.avisos,
      ...widget.avisosMeteorologicos.map(AvisoItem.fromMeteorologico),
    ];

    final marcadores = <Marker>[];

    for (final aviso in todosLosAvisos) {
      if (!aviso.estaActivo) continue;

      final lat = aviso.latitud;
      final lon = aviso.longitud;

      if (lat == null || lon == null) continue;
      if (!lat.isFinite || !lon.isFinite) continue;
      if (lat < -90 || lat > 90 || lon < -180 || lon > 180) {
        continue;
      }

      final punto = LatLng(lat, lon);
      final esMeteorologico = aviso.esMeteorologico;
      final esAvisoManual = !aviso.esDgt && !esMeteorologico;

      double metros;
      var cercaDeRuta = false;

      if (esMeteorologico) {
        // Los avisos meteorológicos se relacionan con la ruta,
        // no con la posición GPS actual del camión.
        if (widget.coordenadasRuta.isEmpty) continue;

        final distanciaRuta = distanciaPuntoRutaMetros(
          latitud: lat,
          longitud: lon,
          ruta: widget.coordenadasRuta,
        );

        if (distanciaRuta == null ||
            distanciaRuta > widget.distanciaAvisosMeteorologicosRutaKm * 1000) {
          continue;
        }

        metros = distanciaRuta;
      } else {
        final posicion = _currentPosition;
        final metrosGps = posicion == null
            ? null
            : distanciaGps.as(LengthUnit.Meter, posicion, punto);
        final metrosRuta = esAvisoManual && widget.coordenadasRuta.isNotEmpty
            ? distanciaPuntoRutaMetros(
                latitud: lat,
                longitud: lon,
                ruta: widget.coordenadasRuta,
              )
            : null;
        final radioMetros = widget.distanciaAvisosGpsKm * 1000;

        if (metrosGps != null && metrosGps <= radioMetros) {
          metros = metrosGps;
        } else if (metrosRuta != null && metrosRuta <= radioMetros) {
          metros = metrosRuta;
          cercaDeRuta = true;
        } else {
          continue;
        }
      }

      final distanciaTexto = metros < 1000
          ? '${metros.round()} m'
          : '${(metros / 1000).toStringAsFixed(1)} km';

      marcadores.add(
        Marker(
          point: punto,
          width: 48,
          height: 54,
          child: GestureDetector(
            onTap: () {
              showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (context) => SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(aviso.icono, color: aviso.color, size: 30),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                aviso.titulo,
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          aviso.etiqueta,
                          style: TextStyle(
                            color: aviso.color,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          esMeteorologico
                              ? 'A $distanciaTexto de la ruta prevista'
                              : cercaDeRuta
                              ? 'A $distanciaTexto de la ruta prevista'
                              : 'A $distanciaTexto de tu posición',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (aviso.carretera.trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text('Carretera: ${aviso.carretera}'),
                        ],
                        if (aviso.descripcion.trim().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(aviso.descripcion),
                        ],
                        const SizedBox(height: 8),
                        Text(
                          aviso.antiguedad(),
                          style: const TextStyle(color: Colors.blueGrey),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
            child: Icon(
              aviso.icono,
              size: esMeteorologico ? 30 : 29,
              color: aviso.color,
              shadows: const [Shadow(color: Colors.white, blurRadius: 5)],
            ),
          ),
        ),
      );
    }

    return marcadores;
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mapCenter = _currentPosition ?? _initialPosition;
    final puntosRuta = _puntosRuta;

    final marcadores = <Marker>[
      ..._crearMarcadoresGasolineras(),
      ..._crearMarcadoresParkings(),
      ..._crearMarcadoresAvisos(),
      if (puntosRuta.isNotEmpty)
        Marker(
          point: puntosRuta.first,
          width: 42,
          height: 48,
          child: const Icon(Icons.trip_origin, color: Colors.green, size: 34),
        ),
      if (puntosRuta.length > 1)
        Marker(
          point: puntosRuta.last,
          width: 42,
          height: 48,
          child: const Icon(Icons.flag, color: Colors.red, size: 34),
        ),
      if (_currentPosition != null)
        Marker(
          point: _currentPosition!,
          width: 44,
          height: 44,
          child: const Icon(
            Icons.local_shipping,
            color: Color.fromARGB(255, 6, 47, 80),
            size: 36,
          ),
        ),
    ];

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: mapCenter,
              initialZoom: 6,
              onMapReady: () {
                _mapReady = true;
                if (widget.coordenadasRuta.isNotEmpty) {
                  _encuadrarRuta();
                } else if (_currentPosition != null && _following) {
                  _mapController.move(_currentPosition!, 16);
                }
              },
              onPositionChanged: (camera, hasGesture) {
                if (hasGesture && _following && mounted) {
                  setState(() {
                    _following = false;
                  });
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.arcen.app',
              ),
              if (puntosRuta.length > 1)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: puntosRuta,
                      strokeWidth: 5,
                      color: const Color(0xFF0755A6),
                    ),
                  ],
                ),
              if (marcadores.isNotEmpty) MarkerLayer(markers: marcadores),
              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    'OpenStreetMap contributors',
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),
          if (_loading || _error != null)
            Positioned(
              top: 76,
              left: 16,
              right: 72,
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      if (_loading)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        const Icon(Icons.location_off, color: Colors.red),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _loading ? 'Obteniendo ubicación GPS...' : _error!,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          Positioned(
            right: 16,
            bottom: 24,
            child: FloatingActionButton(
              onPressed: _centerOnLocation,
              tooltip: 'Mi ubicación',
              child: Icon(
                _following ? Icons.my_location : Icons.location_searching,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
