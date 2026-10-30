import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

import '../services/open_meteo_alerts.dart';

const Color arcenBlue = Color(0xFF0755A6);
const Color arcenDarkBlue = Color(0xFF07366D);
const Color arcenBackground = Color(0xFFF2F5F8);

enum TipoAviso { pesaje, guardiaCivil, radar }

class AvisoItem {
  final String id;
  final String tipo;
  final String titulo;
  final String descripcion;
  final String carretera;
  final double? latitud;
  final double? longitud;
  final DateTime publicado;
  final DateTime? caduca;
  final int sigueAhi;
  final int yaNoEsta;
  final Map<String, dynamic> votos;
  final bool esDgt;
  final bool esMeteorologico;

  const AvisoItem({
    required this.id,
    required this.tipo,
    required this.titulo,
    required this.descripcion,
    required this.carretera,
    required this.latitud,
    required this.longitud,
    required this.publicado,
    required this.caduca,
    required this.sigueAhi,
    required this.yaNoEsta,
    required this.votos,
    required this.esDgt,
    this.esMeteorologico = false,
  });

  factory AvisoItem.fromDocument(
    QueryDocumentSnapshot<Map<String, dynamic>> doc, {
    required bool esDgt,
  }) {
    final data = doc.data();

    DateTime? readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    double? readDouble(dynamic value) {
      if (value is num) return value.toDouble();
      if (value is String) return double.tryParse(value);
      return null;
    }

    final votosRaw = data['votos'];
    final votos = votosRaw is Map
        ? Map<String, dynamic>.from(votosRaw)
        : <String, dynamic>{};

    final fecha =
        readDate(
          data['publicado'] ??
              data['createdAt'] ??
              data['fecha'] ??
              data['publicationTime'],
        ) ??
        DateTime.now();

    return AvisoItem(
      id: doc.id,
      tipo: (data['tipo'] ?? data['type'] ?? 'incidencia').toString(),
      titulo:
          (data['titulo'] ??
                  data['title'] ??
                  (esDgt ? 'Incidencia de tráfico DGT' : 'Aviso de conductor'))
              .toString(),
      descripcion: (data['descripcion'] ?? data['description'] ?? '')
          .toString(),
      carretera:
          (data['carretera'] ??
                  data['road'] ??
                  data['ubicacion'] ??
                  data['location'] ??
                  '')
              .toString(),
      latitud: readDouble(data['lat'] ?? data['latitude']),
      longitud: readDouble(data['lon'] ?? data['lng'] ?? data['longitude']),
      publicado: fecha,
      caduca: readDate(data['caduca'] ?? data['expiresAt']),
      sigueAhi: (data['sigueAhi'] as num?)?.toInt() ?? 0,
      yaNoEsta: (data['yaNoEsta'] as num?)?.toInt() ?? 0,
      votos: votos,
      esDgt: esDgt,
    );
  }

  factory AvisoItem.fromMeteorologico(AvisoMeteorologico aviso) {
    return AvisoItem(
      id: aviso.id,
      tipo: 'meteorologico_${aviso.tipo}',
      titulo: aviso.titulo,
      descripcion: aviso.descripcion,
      carretera: 'Ruta prevista',
      latitud: aviso.latitud,
      longitud: aviso.longitud,
      publicado: aviso.fecha,
      caduca: aviso.caduca,
      sigueAhi: 0,
      yaNoEsta: 0,
      votos: const <String, dynamic>{},
      esDgt: false,
      esMeteorologico: true,
    );
  }

  bool get estaActivo {
    final ahora = DateTime.now();

    if (esMeteorologico) {
      return caduca == null || caduca!.isAfter(ahora);
    }

    if (esDgt) {
      // Los avisos oficiales se muestran mientras no estén caducados.
      return caduca == null || caduca!.isAfter(ahora);
    }

    // Los avisos de conductores caducan una hora después de publicarse.
    final limite = publicado.add(const Duration(hours: 1));
    if (!limite.isAfter(ahora)) return false;
    if (caduca != null && !caduca!.isAfter(ahora)) return false;
    return true;
  }

  String antiguedad() {
    final minutos = DateTime.now().difference(publicado).inMinutes;

    if (esMeteorologico) {
      return 'Previsto ${publicado.hour.toString().padLeft(2, '0')}:'
          '${publicado.minute.toString().padLeft(2, '0')}';
    }

    if (minutos < 1) return 'Ahora mismo';
    if (minutos < 60) return 'Hace $minutos min';

    final horas = minutos ~/ 60;
    if (horas < 24) return 'Hace $horas h';

    return 'Hace ${horas ~/ 24} días';
  }

  String get tipoNormalizado {
    final valor = tipo.toLowerCase();

    if (valor.contains('pesaje') ||
        valor.contains('báscula') ||
        valor.contains('bascula')) {
      return 'pesaje';
    }
    if (valor.contains('guardia') ||
        valor.contains('policía') ||
        valor.contains('policia')) {
      return 'guardia_civil';
    }
    if (valor.contains('radar') || valor.contains('velocidad')) {
      return 'radar';
    }
    return 'incidencia';
  }

  IconData get icono {
    if (esMeteorologico) {
      final valor = tipo.toLowerCase();

      if (valor.contains('viento')) return Icons.air;
      if (valor.contains('nieve')) return Icons.ac_unit;
      if (valor.contains('niebla')) return Icons.cloud;
      if (valor.contains('hielo')) return Icons.thermostat;
      return Icons.cloud_outlined;
    }

    if (esDgt) return Icons.traffic_outlined;

    switch (tipoNormalizado) {
      case 'pesaje':
        return Icons.scale_outlined;
      case 'guardia_civil':
        return Icons.local_police_outlined;
      case 'radar':
        return Icons.speed_outlined;
      default:
        return Icons.warning_amber_outlined;
    }
  }

  Color get color {
    if (esMeteorologico) return Colors.indigo;
    if (esDgt) return Colors.deepOrange;

    switch (tipoNormalizado) {
      case 'pesaje':
        return Colors.deepPurple;
      case 'guardia_civil':
        return arcenBlue;
      case 'radar':
        return Colors.red;
      default:
        return Colors.blueGrey;
    }
  }

  String get etiqueta {
    if (esMeteorologico) return 'AVISO METEOROLÓGICO';
    if (esDgt) return 'DGT · TRÁFICO';

    switch (tipoNormalizado) {
      case 'pesaje':
        return 'CONTROL DE PESAJE';
      case 'guardia_civil':
        return 'GUARDIA CIVIL';
      case 'radar':
        return 'RADAR';
      default:
        return 'AVISO DE CONDUCTOR';
    }
  }
}

class _AvisoLugar {
  const _AvisoLugar({
    required this.nombre,
    required this.latitud,
    required this.longitud,
  });

  final String nombre;
  final double latitud;
  final double longitud;

  factory _AvisoLugar.fromJson(Map<String, dynamic> json) => _AvisoLugar(
    nombre: json['display_name'] as String? ?? '',
    latitud: double.parse(json['lat'].toString()),
    longitud: double.parse(json['lon'].toString()),
  );
}

class AvisosPage extends StatefulWidget {
  final ValueChanged<bool>? onMostrarControlesChanged;
  final List<AvisoMeteorologico> avisosMeteorologicos;
  const AvisosPage({
    super.key,
    this.onMostrarControlesChanged,
    this.avisosMeteorologicos = const [],
  });

  @override
  State<AvisosPage> createState() => _AvisosPageState();
}

class _AvisosPageState extends State<AvisosPage> {
  bool _mostrarControles = true;
  bool _publicando = false;
  int _busquedaUbicacionId = 0;
  DateTime? _ultimaBusquedaUbicacion;

  CollectionReference<Map<String, dynamic>> get _avisosManuales =>
      FirebaseFirestore.instance.collection('avisos_manuales');

  CollectionReference<Map<String, dynamic>> get _avisosDgt =>
      FirebaseFirestore.instance.collection('avisos_dgt');

  String? get _uid => FirebaseAuth.instance.currentUser?.uid;

  void _mensaje(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: arcenBackground,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Avisos de carretera',
                    style: TextStyle(
                      color: arcenDarkBlue,
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Icon(
                  Icons.notifications_active_outlined,
                  color: arcenBlue,
                  size: 25,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _mostrarControles,
              activeColor: arcenBlue,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text(
                'Avisos de controles y radares',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text(
                'Mostrar avisos publicados por otros conductores',
                style: TextStyle(fontSize: 12),
              ),
              onChanged: (value) {
                final mostrar = value ?? false;

                setState(() {
                  _mostrarControles = mostrar;
                });

                widget.onMostrarControlesChanged?.call(mostrar);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _publicando ? null : _mostrarFormulario,
                icon: const Icon(Icons.campaign_outlined),
                label: Text(
                  _publicando
                      ? 'PUBLICANDO AVISO...'
                      : 'AVISAR A OTROS CONDUCTORES',
                  textAlign: TextAlign.center,
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: arcenBlue,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _avisosDgt.snapshots(),
              builder: (context, dgtSnapshot) {
                if (dgtSnapshot.hasError) {
                  return _errorCarga(
                    'No se han podido leer los avisos de la DGT. '
                    'Comprueba las reglas de Firestore.',
                  );
                }

                if (dgtSnapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: arcenBlue),
                  );
                }

                final dgt = (dgtSnapshot.data?.docs ?? [])
                    .map((doc) => AvisoItem.fromDocument(doc, esDgt: true))
                    .where((aviso) => aviso.estaActivo)
                    .toList();

                if (!_mostrarControles) {
                  return _listaAvisos(dgt, []);
                }

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _avisosManuales.snapshots(),
                  builder: (context, manualSnapshot) {
                    if (manualSnapshot.hasError) {
                      return _errorCarga(
                        'No se han podido leer los avisos de conductores. '
                        'Revisa los permisos de Firestore.',
                      );
                    }

                    if (manualSnapshot.connectionState ==
                        ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(color: arcenBlue),
                      );
                    }

                    final manuales = (manualSnapshot.data?.docs ?? [])
                        .map((doc) => AvisoItem.fromDocument(doc, esDgt: false))
                        .where((aviso) => aviso.estaActivo)
                        .toList();

                    return _listaAvisos(dgt, manuales);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorCarga(String texto) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.cloud_off_outlined,
              size: 44,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 12),
            Text(texto, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _listaAvisos(List<AvisoItem> dgt, List<AvisoItem> manuales) {
    final meteorologicos = widget.avisosMeteorologicos
        .map(AvisoItem.fromMeteorologico)
        .where((aviso) => aviso.estaActivo)
        .toList();

    final todos = [...dgt, ...manuales, ...meteorologicos]
      ..sort((a, b) => b.publicado.compareTo(a.publicado));

    if (todos.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 30),
          Icon(
            Icons.check_circle_outline,
            size: 52,
            color: Colors.blueGrey.shade300,
          ),
          const SizedBox(height: 14),
          const Text(
            'No hay avisos activos',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: arcenDarkBlue,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Los avisos de conductores, la DGT y la meteorología '
            'aparecerán aquí cuando haya información disponible.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.blueGrey, height: 1.5),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      itemCount: todos.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _tarjetaAviso(todos[index]),
    );
  }

  Widget _tarjetaAviso(AvisoItem aviso) {
    final uid = _uid;
    final miVoto = uid == null ? null : aviso.votos[uid]?.toString();

    final ubicacion = aviso.carretera.trim().isNotEmpty
        ? aviso.carretera.trim()
        : (aviso.latitud != null && aviso.longitud != null
              ? '${aviso.latitud!.toStringAsFixed(5)}, '
                    '${aviso.longitud!.toStringAsFixed(5)}'
              : 'Ubicación no disponible');

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE3EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
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
                  color: aviso.color.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(aviso.icono, color: aviso.color, size: 25),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      aviso.etiqueta,
                      style: TextStyle(
                        color: aviso.color,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      aviso.titulo,
                      style: const TextStyle(
                        color: arcenDarkBlue,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                aviso.antiguedad(),
                style: const TextStyle(color: Colors.blueGrey, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 19,
                color: Colors.blueGrey,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  ubicacion,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (aviso.descripcion.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              aviso.descripcion,
              style: const TextStyle(color: Colors.blueGrey, height: 1.35),
            ),
          ],
          if (!aviso.esDgt && !aviso.esMeteorologico) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _botonVoto(
                    texto: 'Sigue ahí',
                    icono: Icons.thumb_up_alt_outlined,
                    contador: aviso.sigueAhi,
                    seleccionado: miVoto == 'sigueAhi',
                    color: Colors.green.shade700,
                    onTap: () => _votar(aviso, 'sigueAhi'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _botonVoto(
                    texto: 'Ya no está',
                    icono: Icons.thumb_down_alt_outlined,
                    contador: aviso.yaNoEsta,
                    seleccionado: miVoto == 'yaNoEsta',
                    color: Colors.red.shade700,
                    onTap: () => _votar(aviso, 'yaNoEsta'),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _botonVoto({
    required String texto,
    required IconData icono,
    required int contador,
    required bool seleccionado,
    required Color color,
    required VoidCallback onTap,
  }) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        backgroundColor: seleccionado
            ? color.withValues(alpha: 0.08)
            : Colors.white,
        side: BorderSide(color: seleccionado ? color : const Color(0xFFDCE3EB)),
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icono, size: 17),
            const SizedBox(width: 5),
            Text(texto, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(width: 5),
            Text('$contador'),
          ],
        ),
      ),
    );
  }

  Future<Iterable<_AvisoLugar>> _buscarSugerenciasUbicacion(
    String texto,
  ) async {
    final consulta = texto.trim();
    if (consulta.length < 3) return const [];

    final busquedaId = ++_busquedaUbicacionId;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (!mounted || busquedaId != _busquedaUbicacionId) return const [];

    final ultimaBusqueda = _ultimaBusquedaUbicacion;
    if (ultimaBusqueda != null) {
      final espera =
          const Duration(seconds: 1) -
          DateTime.now().difference(ultimaBusqueda);
      if (espera > Duration.zero) await Future<void>.delayed(espera);
    }
    if (!mounted || busquedaId != _busquedaUbicacionId) return const [];

    _ultimaBusquedaUbicacion = DateTime.now();
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
        throw Exception('HTTP ${response.statusCode}');
      }

      final resultados = jsonDecode(utf8.decode(response.bodyBytes)) as List;
      return resultados
          .map(
            (resultado) =>
                _AvisoLugar.fromJson(resultado as Map<String, dynamic>),
          )
          .where((lugar) => lugar.nombre.isNotEmpty)
          .toList();
    } catch (error) {
      if (mounted && busquedaId == _busquedaUbicacionId) {
        _mensaje('No se pudieron cargar las sugerencias de ubicación: $error');
      }
      return const [];
    }
  }

  Future<_AvisoLugar?> _buscarUbicacionExacta(String texto) async {
    final sugerencias = await _buscarSugerenciasUbicacion(texto);
    return sugerencias.isEmpty ? null : sugerencias.first;
  }

  Future<void> _mostrarFormulario() async {
    if (_uid == null) {
      _mensaje('Inicia sesión para publicar un aviso.');
      return;
    }

    TipoAviso tipo = TipoAviso.pesaje;
    final descripcionController = TextEditingController();
    String referencia = '';
    _AvisoLugar? ubicacionSeleccionada;
    var resolviendoUbicacion = false;
    _AvisoLugar? ubicacionManual;

    final confirmado = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                20,
                20,
                20,
                20 + MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Avisar a otros conductores',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.bold,
                        color: arcenDarkBlue,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Indica una carretera o lugar para situar el aviso. '
                      'Si lo dejas vacío, se usará tu ubicación GPS. '
                      'Caducará al cabo de una hora.',
                      style: TextStyle(color: Colors.blueGrey, height: 1.4),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Tipo de aviso',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    _opcionTipo(
                      tipoActual: tipo,
                      tipo: TipoAviso.pesaje,
                      titulo: 'Control de pesaje',
                      icono: Icons.scale_outlined,
                      color: Colors.deepPurple,
                      onTap: () => setModalState(() => tipo = TipoAviso.pesaje),
                    ),
                    _opcionTipo(
                      tipoActual: tipo,
                      tipo: TipoAviso.guardiaCivil,
                      titulo: 'Guardia Civil',
                      icono: Icons.local_police_outlined,
                      color: arcenBlue,
                      onTap: () =>
                          setModalState(() => tipo = TipoAviso.guardiaCivil),
                    ),
                    _opcionTipo(
                      tipoActual: tipo,
                      tipo: TipoAviso.radar,
                      titulo: 'Radar',
                      icono: Icons.speed_outlined,
                      color: Colors.red,
                      onTap: () => setModalState(() => tipo = TipoAviso.radar),
                    ),
                    const SizedBox(height: 12),
                    Autocomplete<_AvisoLugar>(
                      displayStringForOption: (lugar) => lugar.nombre,
                      optionsBuilder: (value) =>
                          _buscarSugerenciasUbicacion(value.text),
                      onSelected: (lugar) {
                        ubicacionSeleccionada = lugar;
                        referencia = lugar.nombre;
                        setModalState(() {});
                      },
                      fieldViewBuilder:
                          (context, controller, focusNode, onSubmitted) {
                            return TextField(
                              controller: controller,
                              focusNode: focusNode,
                              textCapitalization: TextCapitalization.words,
                              onChanged: (value) {
                                referencia = value;
                                if (ubicacionSeleccionada?.nombre != value) {
                                  ubicacionSeleccionada = null;
                                }
                                setModalState(() {});
                              },
                              onSubmitted: (_) => onSubmitted(),
                              decoration: const InputDecoration(
                                labelText: 'Carretera o referencia (opcional)',
                                hintText: 'Ej. A-2, Zaragoza',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.route_outlined),
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
                                      color: arcenBlue,
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
                    const SizedBox(height: 12),
                    TextField(
                      controller: descripcionController,
                      maxLines: 2,
                      maxLength: 160,
                      decoration: const InputDecoration(
                        labelText: 'Detalle adicional (opcional)',
                        hintText: 'Sentido, salida, descripción...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: resolviendoUbicacion
                            ? null
                            : () async {
                                if (referencia.trim().isNotEmpty) {
                                  setModalState(
                                    () => resolviendoUbicacion = true,
                                  );
                                  ubicacionManual =
                                      ubicacionSeleccionada ??
                                      await _buscarUbicacionExacta(
                                        referencia.trim(),
                                      );
                                  if (!sheetContext.mounted) return;
                                  setModalState(
                                    () => resolviendoUbicacion = false,
                                  );
                                  if (ubicacionManual == null) {
                                    _mensaje(
                                      'Selecciona una sugerencia de ubicación '
                                      'o deja el campo vacío para usar el GPS.',
                                    );
                                    return;
                                  }
                                }
                                Navigator.of(sheetContext).pop(true);
                              },
                        icon: Icon(
                          referencia.trim().isEmpty
                              ? Icons.my_location
                              : Icons.publish,
                        ),
                        label: Text(
                          resolviendoUbicacion
                              ? 'BUSCANDO UBICACIÓN...'
                              : referencia.trim().isEmpty
                              ? 'PUBLICAR CON MI UBICACIÓN'
                              : 'PUBLICAR',
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: arcenBlue,
                          foregroundColor: Colors.white,
                          minimumSize: const Size.fromHeight(48),
                        ),
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

    if (confirmado == true && mounted) {
      await _crearAviso(
        tipo: tipo,
        carretera: referencia.trim(),
        descripcion: descripcionController.text.trim(),
        ubicacionManual: ubicacionManual,
      );
    }

    descripcionController.dispose();
  }

  Widget _opcionTipo({
    required TipoAviso tipoActual,
    required TipoAviso tipo,
    required String titulo,
    required IconData icono,
    required Color color,
    required VoidCallback onTap,
  }) {
    final seleccionado = tipoActual == tipo;

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: seleccionado ? color.withValues(alpha: 0.08) : Colors.white,
            border: Border.all(
              color: seleccionado ? color : const Color(0xFFDCE3EB),
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(icono, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  titulo,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Icon(
                seleccionado
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: seleccionado ? color : Colors.blueGrey,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<Position> _obtenerUbicacion() async {
    final servicioActivo = await Geolocator.isLocationServiceEnabled();

    if (!servicioActivo) {
      throw Exception('Activa el GPS del dispositivo y vuelve a intentarlo.');
    }

    LocationPermission permiso = await Geolocator.checkPermission();

    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
    }

    if (permiso == LocationPermission.denied) {
      throw Exception('No se ha concedido permiso para acceder al GPS.');
    }

    if (permiso == LocationPermission.deniedForever) {
      throw Exception(
        'El permiso de ubicación está bloqueado. Actívalo en los '
        'ajustes del navegador o dispositivo.',
      );
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 20),
      ),
    );
  }

  Future<void> _crearAviso({
    required TipoAviso tipo,
    required String carretera,
    required String descripcion,
    _AvisoLugar? ubicacionManual,
  }) async {
    final uid = _uid;

    if (uid == null) {
      _mensaje('Tu sesión ha caducado. Vuelve a iniciar sesión.');
      return;
    }

    setState(() => _publicando = true);

    try {
      final position = ubicacionManual == null
          ? await _obtenerUbicacion()
          : null;
      final latitud = ubicacionManual?.latitud ?? position!.latitude;
      final longitud = ubicacionManual?.longitud ?? position!.longitude;
      final ahora = DateTime.now();
      final caduca = ahora.add(const Duration(hours: 1));

      final tipoTexto = switch (tipo) {
        TipoAviso.pesaje => 'pesaje',
        TipoAviso.guardiaCivil => 'guardia_civil',
        TipoAviso.radar => 'radar',
      };

      final titulo = switch (tipo) {
        TipoAviso.pesaje => 'Control de pesaje',
        TipoAviso.guardiaCivil => 'Guardia Civil',
        TipoAviso.radar => 'Radar',
      };

      await _avisosManuales.add({
        'tipo': tipoTexto,
        'titulo': titulo,
        'descripcion': descripcion,
        'carretera': carretera,
        'lat': latitud,
        'lon': longitud,
        'publicado': FieldValue.serverTimestamp(),
        'createdAt': FieldValue.serverTimestamp(),
        'caduca': Timestamp.fromDate(caduca),
        'expiresAt': Timestamp.fromDate(caduca),
        'autorUid': uid,
        'sigueAhi': 0,
        'yaNoEsta': 0,
        'votos': <String, dynamic>{},
      });

      _mensaje('Aviso publicado correctamente.');
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        _mensaje(
          'Firebase ha denegado la publicación. Revisa las reglas de '
          'Firestore para la colección avisos_manuales.',
        );
      } else {
        _mensaje('Error de Firebase (${e.code}): ${e.message ?? e.code}');
      }
    } catch (e) {
      _mensaje('No se ha podido publicar el aviso: $e');
    } finally {
      if (mounted) setState(() => _publicando = false);
    }
  }

  Future<void> _votar(AvisoItem aviso, String votoNuevo) async {
    final uid = _uid;

    if (uid == null) {
      _mensaje('Inicia sesión para confirmar un aviso.');
      return;
    }

    final ref = _avisosManuales.doc(aviso.id);

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final snapshot = await transaction.get(ref);

        if (!snapshot.exists) {
          throw Exception('Este aviso ya no existe.');
        }

        final data = snapshot.data() ?? <String, dynamic>{};
        final votosRaw = data['votos'];
        final votos = votosRaw is Map
            ? Map<String, dynamic>.from(votosRaw)
            : <String, dynamic>{};

        final votoAnterior = votos[uid]?.toString();

        if (votoAnterior == votoNuevo) {
          // Pulsar de nuevo el mismo botón retira el voto.
          votos.remove(uid);
        } else {
          votos[uid] = votoNuevo;
        }

        int contar(String valor) =>
            votos.values.where((v) => v.toString() == valor).length;

        transaction.update(ref, {
          'votos': votos,
          'sigueAhi': contar('sigueAhi'),
          'yaNoEsta': contar('yaNoEsta'),
        });
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        _mensaje(
          'Firebase ha denegado el voto. Revisa las reglas de '
          'actualización de avisos_manuales.',
        );
      } else {
        _mensaje('No se ha podido registrar el voto: ${e.message ?? e.code}');
      }
    } catch (e) {
      _mensaje('No se ha podido registrar el voto: $e');
    }
  }
}
