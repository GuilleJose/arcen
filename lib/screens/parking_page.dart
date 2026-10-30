import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import 'route_distance.dart';

const Color _parkingBlue = Color(0xFF0755A6);
const Color _parkingDarkBlue = Color(0xFF07366D);
const Color _parkingBackground = Color(0xFFF2F5F8);

class ParkingPage extends StatefulWidget {
  final List<List<double>> coordenadasRuta;
  final double distanciaMaximaRutaKm;
  final LatLng? ubicacionActual;

  const ParkingPage({
    super.key,
    this.coordenadasRuta = const [],
    this.distanciaMaximaRutaKm = 1,
    this.ubicacionActual,
  });

  @override
  State<ParkingPage> createState() => _ParkingPageState();
}

class _ParkingPageState extends State<ParkingPage> {
  String _filtro = 'todos';

  final Set<String> _guardando = {};
  RouteDistanceIndex? _indiceRuta;

  @override
  void initState() {
    super.initState();
    _actualizarIndiceRuta();
  }

  @override
  void didUpdateWidget(covariant ParkingPage oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.coordenadasRuta != widget.coordenadasRuta ||
        oldWidget.distanciaMaximaRutaKm != widget.distanciaMaximaRutaKm) {
      _actualizarIndiceRuta();
    }
  }

  void _actualizarIndiceRuta() {
    _indiceRuta = widget.coordenadasRuta.isEmpty
        ? null
        : RouteDistanceIndex(
            widget.coordenadasRuta,
            maxDistanceKm: widget.distanciaMaximaRutaKm,
          );
  }

  double? _distanciaRutaKm(Map<String, dynamic> datos) {
    final latitud = _numero(datos['latitud'] ?? datos['latitude']);
    final longitud = _numero(
      datos['longitud'] ?? datos['longitude'] ?? datos['lon'] ?? datos['lng'],
    );

    if (latitud == null || longitud == null) return null;

    // Si existe una ruta calculada, se utiliza para filtrar.
    if (widget.coordenadasRuta.isNotEmpty) {
      final distancia = _indiceRuta?.distanciaMetros(
        latitud: latitud,
        longitud: longitud,
      );

      if (distancia == null) return null;

      return distancia / 1000;
    }

    return null;
  }

  double? _distanciaDesdeUbicacionKm(Map<String, dynamic> datos) {
    final posicionActual = widget.ubicacionActual;
    if (posicionActual == null) return null;

    final latitud = _numero(datos['latitud'] ?? datos['latitude']);
    final longitud = _numero(
      datos['longitud'] ?? datos['longitude'] ?? datos['lon'] ?? datos['lng'],
    );
    if (latitud == null || longitud == null) return null;

    return const Distance().as(
      LengthUnit.Kilometer,
      posicionActual,
      LatLng(latitud, longitud),
    );
  }

  double? _numero(dynamic valor) {
    if (valor is num) return valor.toDouble();
    if (valor is String) return double.tryParse(valor);
    return null;
  }

  bool _coincideFiltro(Map<String, dynamic> datos) {
    final tipo = _nombreTipo(datos).toLowerCase();
    final aptoCamiones = datos['aptoCamiones'] == true;
    final servicios = datos['servicios'];
    final tieneServicios = servicios is Map
        ? servicios.values.any(_servicioActivo)
        : servicios is List
        ? servicios.isNotEmpty
        : servicios is String && servicios.trim().isNotEmpty;

    switch (_filtro) {
      case 'camiones':
        return aptoCamiones;
      case 'parkings':
        return tipo.contains('parking') ||
            tipo.contains('aparcamiento') ||
            tipo.contains('área');
      case 'servicios':
        return tieneServicios ||
            tipo.contains('servicio') ||
            tipo.contains('gasolinera');
      case 'descanso':
        return tipo.contains('descanso') ||
            tipo.contains('área de descanso') ||
            tipo.contains('area de descanso');
      default:
        return true;
    }
  }

  String _nombreTipo(Map<String, dynamic> datos) {
    final tipo = datos['tipo']?.toString().trim();

    if (tipo != null && tipo.isNotEmpty) return tipo;

    if (datos['aptoCamiones'] == true) return 'Parking de camiones';

    return 'Parking';
  }

  bool _servicioActivo(dynamic valor) {
    if (valor is bool) return valor;
    if (valor is num) return valor != 0;
    if (valor is String) {
      return const {
        'true',
        '1',
        'sí',
        'si',
        'yes',
      }.contains(valor.trim().toLowerCase());
    }
    return false;
  }

  List<({String nombre, bool activo})> _leerServicios(dynamic valor) {
    if (valor is Map) {
      return valor.entries
          .map(
            (entry) => (
              nombre: entry.key
                  .toString()
                  .replaceAllMapped(
                    RegExp(r'([a-záéíóú])([A-Z])'),
                    (match) => '${match[1]} ${match[2]}',
                  )
                  .replaceAll('_', ' '),
              activo: _servicioActivo(entry.value),
            ),
          )
          .toList();
    }
    if (valor is List) {
      return valor
          .map((item) => (nombre: item.toString(), activo: true))
          .toList();
    }
    if (valor is String && valor.trim().isNotEmpty) {
      return valor
          .split(RegExp(r'[,·]'))
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .map((item) => (nombre: item, activo: true))
          .toList();
    }
    return const [];
  }

  IconData _iconoTipo(Map<String, dynamic> datos) {
    final tipo = _nombreTipo(datos).toLowerCase();

    if (tipo.contains('descanso')) {
      return Icons.hotel_outlined;
    }

    if (tipo.contains('gasolinera') || tipo.contains('servicio')) {
      return Icons.local_gas_station_outlined;
    }

    if (tipo.contains('parking') ||
        tipo.contains('aparcamiento') ||
        tipo.contains('área')) {
      return Icons.local_parking_outlined;
    }

    return Icons.local_shipping_outlined;
  }

  Color _colorEstado(String? estado) {
    switch (estado) {
      case 'Libre':
        return Colors.green.shade700;
      case 'Pocas':
        return Colors.orange.shade800;
      case 'Lleno':
        return Colors.red.shade700;
      default:
        return Colors.blueGrey;
    }
  }

  String _etiquetaDisponibilidad(Map<String, dynamic> datos) {
    final estado = datos['estadoDisponibilidad']?.toString();

    if (estado == 'Libre') return 'HAY SITIO';
    if (estado == 'Pocas') return 'POCAS PLAZAS';
    if (estado == 'Lleno') return 'LLENO';

    return 'SIN DATOS';
  }

  Widget _etiquetaEstado(Map<String, dynamic> datos) {
    final color = _colorEstado(datos['estadoDisponibilidad']?.toString());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        _etiquetaDisponibilidad(datos),
        style: TextStyle(
          color: color,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  String _nombreEstado(String estado) {
    switch (estado) {
      case 'Libre':
        return 'Libre';
      case 'Pocas':
        return 'Pocas plazas';
      case 'Lleno':
        return 'Lleno';
      default:
        return estado;
    }
  }

  String _tiempoDesdeAviso(dynamic valor) {
    DateTime? fecha;

    if (valor is Timestamp) {
      fecha = valor.toDate();
    } else if (valor is DateTime) {
      fecha = valor;
    } else if (valor is String) {
      fecha = DateTime.tryParse(valor);
    }

    if (fecha == null) return 'Sin avisos recientes';

    final diferencia = DateTime.now().difference(fecha);

    if (diferencia.isNegative) return 'Actualizado hace unos instantes';

    if (diferencia.inMinutes < 1) {
      return 'Actualizado hace unos instantes';
    }

    if (diferencia.inMinutes < 60) {
      return 'Actualizado hace ${diferencia.inMinutes} min';
    }

    if (diferencia.inHours < 24) {
      return 'Actualizado hace ${diferencia.inHours} h';
    }

    if (diferencia.inDays < 30) {
      return 'Actualizado hace ${diferencia.inDays} días';
    }

    return 'Actualizado el ${_formatearFecha(fecha)}';
  }

  String _formatearFecha(DateTime fecha) {
    final dia = fecha.day.toString().padLeft(2, '0');
    final mes = fecha.month.toString().padLeft(2, '0');

    return '$dia/$mes/${fecha.year}';
  }

  Future<void> _guardarEstado({
    required String parkingId,
    required String nuevoEstado,
  }) async {
    final usuario = FirebaseAuth.instance.currentUser;

    if (usuario == null) {
      _mostrarMensaje('Inicia sesión para informar del estado del parking.');
      return;
    }

    if (_guardando.contains(parkingId)) return;

    setState(() {
      _guardando.add(parkingId);
    });

    try {
      await FirebaseFirestore.instance
          .collection('parkings')
          .doc(parkingId)
          .update({
            'estadoDisponibilidad': nuevoEstado,
            'estadoActualizado': FieldValue.serverTimestamp(),
            'ultimoAvisoUsuario': usuario.uid,
          });

      if (!mounted) return;

      _mostrarMensaje(
        'Disponibilidad actualizada: ${_nombreEstado(nuevoEstado)}.',
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;

      if (e.code == 'permission-denied') {
        _mostrarMensaje(
          'Firebase no permite actualizar el parking. '
          'Revisa las reglas de Firestore.',
        );
      } else {
        _mostrarMensaje('No se pudo guardar el aviso: ${e.message ?? e.code}');
      }
    } catch (_) {
      if (!mounted) return;
      _mostrarMensaje('No se ha podido actualizar la disponibilidad.');
    } finally {
      if (mounted) {
        setState(() {
          _guardando.remove(parkingId);
        });
      }
    }
  }

  void _mostrarMensaje(String mensaje) {
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(mensaje), behavior: SnackBarBehavior.floating),
      );
  }

  Widget _botonEstado({
    required String parkingId,
    required String texto,
    required String estado,
    required Color color,
  }) {
    final guardando = _guardando.contains(parkingId);

    return Expanded(
      child: OutlinedButton(
        onPressed: guardando
            ? null
            : () => _guardarEstado(parkingId: parkingId, nuevoEstado: estado),
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.65)),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          minimumSize: const Size(0, 40),
        ),
        child: guardando
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(
                texto,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
    );
  }

  Widget _controlesDisponibilidad(
    String parkingId,
    Map<String, dynamic> datos,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _tiempoDesdeAviso(datos['estadoActualizado']),
          style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _botonEstado(
              parkingId: parkingId,
              texto: 'Libre',
              estado: 'Libre',
              color: Colors.green.shade700,
            ),
            const SizedBox(width: 7),
            _botonEstado(
              parkingId: parkingId,
              texto: 'Pocas plazas',
              estado: 'Pocas',
              color: Colors.orange.shade800,
            ),
            const SizedBox(width: 7),
            _botonEstado(
              parkingId: parkingId,
              texto: 'Lleno',
              estado: 'Lleno',
              color: Colors.red.shade700,
            ),
          ],
        ),
      ],
    );
  }

  Widget _tarjetaParking(
    Map<String, dynamic> datos, {
    required double? distancia,
  }) {
    final parkingId = (datos['_docId'] ?? '').toString();
    final nombre = datos['nombre']?.toString().trim().isNotEmpty == true
        ? datos['nombre'].toString()
        : 'Parking sin nombre';

    final carretera = datos['carretera']?.toString() ?? '';
    final localidad = datos['localidad']?.toString() ?? '';
    final operador = datos['operador']?.toString() ?? '';
    final plazas = datos['plazasCamion'];

    final servicios = _leerServicios(datos['servicios']);
    final latitud = _numero(datos['latitud'] ?? datos['latitude']);
    final longitud = _numero(
      datos['longitud'] ?? datos['longitude'] ?? datos['lon'] ?? datos['lng'],
    );
    final coordenadasValidas =
        latitud != null &&
        longitud != null &&
        latitud >= -90 &&
        latitud <= 90 &&
        longitud >= -180 &&
        longitud <= 180;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 1,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _parkingBlue.withValues(alpha: 0.09),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(_iconoTipo(datos), color: _parkingBlue, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              nombre,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: _parkingDarkBlue,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          _etiquetaEstado(datos),
                        ],
                      ),
                      if (carretera.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          carretera,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                      if (localidad.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          localidad,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (distancia != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _parkingBlue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${distancia.toStringAsFixed(1)} km',
                      style: const TextStyle(
                        fontSize: 11,
                        color: _parkingBlue,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _etiquetaDato(_nombreTipo(datos), Icons.local_parking_outlined),
                if (datos['aptoCamiones'] == true)
                  _etiquetaDato(
                    'Apto para camiones',
                    Icons.local_shipping_outlined,
                  ),
                if (plazas != null)
                  _etiquetaDato(
                    'Plazas camión: $plazas',
                    Icons.directions_car_outlined,
                  ),
              ],
            ),
            if (operador.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                'Operador: $operador',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
              ),
            ],
            if (servicios.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text(
                'Servicios',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: _parkingDarkBlue,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final servicio in servicios)
                    _etiquetaServicio(servicio.nombre, activo: servicio.activo),
                ],
              ),
            ],
            const SizedBox(height: 14),
            if (parkingId.isNotEmpty)
              _controlesDisponibilidad(parkingId, datos)
            else
              Text(
                'No se ha podido identificar este parking en Firebase.',
                style: TextStyle(fontSize: 12, color: Colors.red.shade700),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: coordenadasValidas
                    ? () => _abrirMaps(latitud, longitud)
                    : null,
                icon: const Icon(Icons.directions),
                label: const Text('Cómo llegar'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _abrirMaps(double? latitud, double? longitud) async {
    if (latitud == null || longitud == null) return;
    final url = Uri.https('www.google.com', '/maps/dir/', {
      'api': '1',
      'destination': '$latitud,$longitud',
    });
    final abierto = await launchUrl(url, mode: LaunchMode.platformDefault);
    if (!abierto && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se ha podido abrir Google Maps.')),
      );
    }
  }

  Widget _etiquetaServicio(String nombre, {required bool activo}) {
    final color = activo ? Colors.green.shade700 : Colors.grey.shade600;
    final background = activo
        ? Colors.green.withValues(alpha: 0.1)
        : Colors.grey.withValues(alpha: 0.12);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            activo ? Icons.check_circle_outline : Icons.cancel_outlined,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 5),
          Text(
            nombre,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _etiquetaDato(String texto, IconData icono) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: _parkingBackground,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 14, color: _parkingDarkBlue),
          const SizedBox(width: 5),
          Text(
            texto,
            style: const TextStyle(fontSize: 11, color: _parkingDarkBlue),
          ),
        ],
      ),
    );
  }

  Widget _botonFiltro(String texto, String valor) {
    final seleccionado = _filtro == valor;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(texto),
        selected: seleccionado,
        onSelected: (_) {
          setState(() {
            _filtro = valor;
          });
        },
        selectedColor: _parkingBlue,
        backgroundColor: Colors.white,
        labelStyle: TextStyle(
          color: seleccionado ? Colors.white : _parkingDarkBlue,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
        side: BorderSide(
          color: seleccionado ? _parkingBlue : Colors.grey.shade300,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        showCheckmark: false,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _parkingBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Parking',
                  style: TextStyle(
                    color: _parkingDarkBlue,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  'Encuentra aparcamiento y consulta su disponibilidad.',
                  style: TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 55,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              children: [
                _botonFiltro('Todos', 'todos'),
                _botonFiltro('Camiones', 'camiones'),
                _botonFiltro('Parkings', 'parkings'),
                _botonFiltro('Servicios', 'servicios'),
                _botonFiltro('Descanso', 'descanso'),
              ],
            ),
          ),
          Expanded(
            child: widget.coordenadasRuta.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.route_outlined,
                            size: 48,
                            color: Colors.grey,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'Calcula una ruta para ver parkings cercanos.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _parkingDarkBlue,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Los parkings se mostrarán a menos de 1 km del recorrido.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('parkings')
                        .snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.cloud_off_outlined,
                                  size: 42,
                                  color: Colors.red.shade400,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'No se han podido cargar los parkings.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  snapshot.error.toString(),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !snapshot.hasData) {
                        return const Center(
                          child: CircularProgressIndicator(color: _parkingBlue),
                        );
                      }

                      final documentos = snapshot.data?.docs ?? [];

                      final parkings =
                          <({Map<String, dynamic> datos, double? distancia})>[];
                      for (final doc in documentos) {
                        final datos = <String, dynamic>{
                          ...doc.data(),
                          '_docId': doc.id,
                        };
                        if (!_coincideFiltro(datos)) continue;

                        final distanciaRuta = _distanciaRutaKm(datos);
                        if (widget.coordenadasRuta.isNotEmpty &&
                            (distanciaRuta == null ||
                                distanciaRuta > widget.distanciaMaximaRutaKm)) {
                          continue;
                        }
                        final distancia = _distanciaDesdeUbicacionKm(datos);
                        parkings.add((datos: datos, distancia: distancia));
                      }

                      // Ordenar por distancia a la ruta.
                      parkings.sort((a, b) {
                        final distanciaA = a.distancia;
                        final distanciaB = b.distancia;

                        if (distanciaA == null && distanciaB == null) return 0;
                        if (distanciaA == null) return 1;
                        if (distanciaB == null) return -1;

                        return distanciaA.compareTo(distanciaB);
                      });

                      if (parkings.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.local_parking_outlined,
                                  size: 48,
                                  color: Colors.grey.shade400,
                                ),
                                const SizedBox(height: 12),
                                const Text(
                                  'No hay parkings para mostrar.',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: _parkingDarkBlue,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  widget.coordenadasRuta.isNotEmpty
                                      ? 'No se han encontrado parkings a menos de '
                                            '${widget.distanciaMaximaRutaKm} km de la ruta con este filtro.'
                                      : 'Prueba con otro filtro o vuelve a intentarlo.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                        itemCount: parkings.length,
                        itemBuilder: (context, index) {
                          final parking = parkings[index];
                          return _tarjetaParking(
                            parking.datos,
                            distancia: parking.distancia,
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
