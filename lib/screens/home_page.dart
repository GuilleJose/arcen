import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/app_settings.dart';
import '../models/driver_hours.dart';
import 'map_page.dart';
import 'management_page.dart';
import 'viaje_page.dart';
import 'gasoleo_page.dart';
import 'avisos_page.dart';
import 'parking_page.dart';
import 'configuration_page.dart';
import 'hours_page.dart';
//import '../route_distance.dart';
import '../services/open_meteo_alerts.dart';
import '../services/pause_parking_recommendation.dart';

import 'dart:async';

const arcenBlue = Color(0xFF0755A6);
const arcenDarkBlue = Color(0xFF07366D);
const arcenBackground = Color(0xFFF2F5F8);

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  _HomeSection selectedSection = _HomeSection.map;
  Widget? _utilityPage;

  String _poblacion = 'Localizando...';
  String _provincia = '';
  LatLng? _posicionActual;
  Position? _ultimaPosicionGps;

  // Coordenadas de la ruta calculada en Viaje.
  // Formato: [longitud, latitud].
  List<List<double>> _coordenadasRuta = [];
  int? _duracionRutaSegundos;
  DateTime? _rutaCalculadaEn;

  // Gasolineras recibidas desde GasoleoPage.
  List<Map<String, dynamic>> _gasolineras = [];
  // Avisos activos recibidos desde Firestore.
  List<AvisoItem> _avisos = [];

  // Parkings recibidos desde Firestore.
  List<Map<String, dynamic>> _parkings = [];

  // Suscripción a la colección de parkings.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _suscripcionParkings;

  // Estado de la casilla de controles y radares.
  bool _mostrarControles = true;

  // Suscripciones a las colecciones de avisos.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _suscripcionAvisosManuales;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _suscripcionAvisosDgt;

  List<AvisoMeteorologico> _avisosMeteorologicos = [];
  AppSettings _settings = const AppSettings();
  String? _settingsLoadError;
  int _consultaMeteorologicaId = 0;

  Future<void> _actualizarAvisosMeteorologicos(List<List<double>> ruta) async {
    final consultaId = ++_consultaMeteorologicaId;
    final settings = _settings;
    try {
      final nuevosAvisos = await OpenMeteoAlerts.consultarRuta(
        ruta,
        settings: settings,
      );

      if (!mounted || consultaId != _consultaMeteorologicaId) return;

      setState(() {
        _avisosMeteorologicos = nuevosAvisos;
      });
    } catch (e) {
      debugPrint('Error actualizando avisos meteorológicos: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _escucharAvisos();
    _escucharParkings();
    unawaited(_cargarConfiguracion());
  }

  void _escucharAvisos() {
    final firestore = FirebaseFirestore.instance;

    _suscripcionAvisosManuales = firestore
        .collection('avisos_manuales')
        .snapshots()
        .listen((snapshot) {
          if (!mounted) return;

          final manuales = snapshot.docs
              .map((doc) => AvisoItem.fromDocument(doc, esDgt: false))
              .where((aviso) => aviso.estaActivo)
              .toList();

          setState(() {
            _avisos = [..._avisos.where((aviso) => aviso.esDgt), ...manuales];
          });
        });

    _suscripcionAvisosDgt = firestore
        .collection('avisos_dgt')
        .snapshots()
        .listen((snapshot) {
          if (!mounted) return;

          final dgt = snapshot.docs
              .map((doc) => AvisoItem.fromDocument(doc, esDgt: true))
              .where((aviso) => aviso.estaActivo)
              .toList();

          setState(() {
            _avisos = [..._avisos.where((aviso) => !aviso.esDgt), ...dgt];
          });
        });
  }

  void _escucharParkings() {
    _suscripcionParkings = FirebaseFirestore.instance
        .collection('parkings')
        .snapshots()
        .listen(
          (snapshot) {
            if (!mounted) return;

            setState(() {
              _parkings = snapshot.docs.map((doc) {
                return {...doc.data(), 'id': doc.id};
              }).toList();
            });
          },
          onError: (Object error) {
            debugPrint('Error cargando parkings: $error');
          },
        );
  }

  @override
  void dispose() {
    _suscripcionAvisosManuales?.cancel();
    _suscripcionAvisosDgt?.cancel();
    _suscripcionParkings?.cancel();
    super.dispose();
  }

  // Capas visibles en el mapa.
  // Gasóleo aparece activado por defecto.
  bool _mostrarGasoleo = true;
  bool _mostrarParking = true;
  bool _mostrarAvisos = true;

  String get uid => FirebaseAuth.instance.currentUser!.uid;

  late final Stream<DocumentSnapshot<Map<String, dynamic>>>
  _selectionSnapshots = selectionDocument.snapshots();
  final Map<String, Stream<DocumentSnapshot<Map<String, dynamic>>>>
  _truckSnapshots = {};
  final Map<String, Stream<DocumentSnapshot<Map<String, dynamic>>>>
  _driverSnapshots = {};

  Stream<DocumentSnapshot<Map<String, dynamic>>> _truckSnapshotsFor(String id) {
    return _truckSnapshots.putIfAbsent(
      id,
      () => trucksCollection.doc(id).snapshots(),
    );
  }

  Stream<DocumentSnapshot<Map<String, dynamic>>> _driverSnapshotsFor(
    String id,
  ) {
    return _driverSnapshots.putIfAbsent(
      id,
      () => driversCollection.doc(id).snapshots(),
    );
  }

  CollectionReference<Map<String, dynamic>> get trucksCollection {
    return FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .collection('camiones');
  }

  CollectionReference<Map<String, dynamic>> get driversCollection {
    return FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .collection('conductores');
  }

  DocumentReference<Map<String, dynamic>> get selectionDocument {
    return FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .collection('configuracion')
        .doc('seleccion');
  }

  DocumentReference<Map<String, dynamic>> get settingsDocument {
    return FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .collection('configuracion')
        .doc('preferencias');
  }

  Future<void> _cargarConfiguracion() async {
    try {
      final snapshot = await settingsDocument.get();
      if (!mounted) return;
      final settings = snapshot.exists
          ? AppSettings.fromMap(snapshot.data()!)
          : const AppSettings();
      setState(() {
        _settings = settings;
        _settingsLoadError = null;
      });
      if (_coordenadasRuta.isNotEmpty) {
        unawaited(_actualizarAvisosMeteorologicos(_coordenadasRuta));
      }
    } catch (error) {
      debugPrint('Error cargando la configuración: $error');
      if (!mounted) return;
      setState(() {
        _settingsLoadError = 'No se pudo cargar la configuración: $error';
      });
    }
  }

  Future<void> _abrirConfiguracion() async {
    if (!mounted) return;
    setState(() {
      _utilityPage = ConfigurationPage(
        initialSettings: _settings,
        loadError: _settingsLoadError,
        onSaved: _onSettingsSaved,
      );
    });
  }

  void _onSettingsSaved(AppSettings settings) {
    setState(() {
      _settings = settings;
      _settingsLoadError = null;
      _avisosMeteorologicos = [];
    });
    if (_coordenadasRuta.isNotEmpty) {
      unawaited(_actualizarAvisosMeteorologicos(_coordenadasRuta));
    }
  }

  void _mostrarAcercaDe() {
    showAboutDialog(
      context: context,
      applicationName: 'Arcén',
      applicationVersion: '0.1.0',
      applicationIcon: Image.asset('lib/imag/logo.PNG', width: 48, height: 48),
      children: [
        const Text('Herramientas para quienes viven en la carretera.'),
        const SizedBox(height: 16),
        const Text(
          'Origen de los datos',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 6),
        _aboutSource(
          'Gasolineras y precios',
          'Ministerio para la Transición Ecológica · Geoportal de '
              'Precios de Carburantes',
          Uri.https('sedeaplicaciones.minetur.gob.es', '/'),
        ),
        _aboutSource(
          'Avisos meteorológicos',
          'Open-Meteo · previsión meteorológica; Arcén calcula los avisos '
              'a partir de esos datos',
          Uri.https('open-meteo.com', '/'),
        ),
        _aboutSource(
          'Parkings',
          'Datos de parkings guardados en Arcén (Firestore), procedentes de '
              'OpenStreetMap y consultados con Overpass Turbo',
          Uri.https('overpass-turbo.eu', '/'),
        ),
        _aboutSource(
          'Mapas y datos de lugares',
          'OpenStreetMap · mapas, búsqueda de localidades (Nominatim) y '
              'datos de carreteras',
          Uri.https('www.openstreetmap.org', '/copyright'),
        ),
        _aboutSource(
          'Cálculo de rutas',
          'OSRM · servicio de rutas',
          Uri.https('project-osrm.org', '/'),
        ),
        _aboutSource(
          'Avisos de carretera',
          'Avisos de la DGT y avisos comunicados por usuarios, almacenados '
              'en Arcén (Firestore)',
          Uri.https('www.dgt.es', '/'),
        ),
        const Text(
          'La ubicación se obtiene del GPS del dispositivo. Los datos de '
          'camiones, conductores y configuración se guardan en Firebase.',
          style: TextStyle(fontSize: 12),
        ),
      ],
    );
  }

  Widget _aboutSource(String title, String detail, Uri uri) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          Text(detail, style: const TextStyle(fontSize: 12)),
          InkWell(
            onTap: () async {
              if (!await launchUrl(uri, mode: LaunchMode.externalApplication) &&
                  mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No se pudo abrir el enlace.')),
                );
              }
            },
            child: Text(
              uri.host,
              style: const TextStyle(
                fontSize: 12,
                color: arcenBlue,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> logout() async {
    await FirebaseAuth.instance.signOut();
  }

  void _abrirVentajas() {
    setState(() {
      _utilityPage = const _AdvantagesPage();
    });
  }

  void openTruckManagement({String? truckId}) {
    setState(() {
      _utilityPage = ManagementPage(
        type: ManagementType.trucks,
        mantenimientoIntervaloMeses: _settings.mantenimientoIntervaloMeses,
        abrirCamionId: truckId,
      );
    });
  }

  void openDriverManagement() {
    setState(() {
      _utilityPage = const ManagementPage(type: ManagementType.drivers);
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < 500;
    final sections = <_Section>[
      _Section(
        id: _HomeSection.map,
        title: 'Mapa',
        icon: Icons.map_outlined,
        page: _buildHomeMap(compact),
      ),
      _Section(
        id: _HomeSection.journey,
        title: 'Viaje',
        icon: Icons.route_outlined,
        page: ViajePage(
          posicionActual: _posicionActual,
          onDuracionRutaCalculada: (seconds) {
            if (!mounted) return;
            setState(() {
              _duracionRutaSegundos = seconds;
            });
          },
          onRutaCalculada: (ruta) {
            if (!mounted) return;

            setState(() {
              _coordenadasRuta = ruta;
              _rutaCalculadaEn = DateTime.now();
              _gasolineras = [];
              _avisosMeteorologicos = [];
            });

            unawaited(_actualizarAvisosMeteorologicos(ruta));
          },
        ),
      ),
      _Section(
        id: _HomeSection.hours,
        title: 'Horas',
        icon: Icons.timer_outlined,
        page: _buildHoursPage(),
      ),
      _Section(
        id: _HomeSection.diesel,
        title: 'Gasóleo',
        icon: Icons.local_gas_station_outlined,
        page: GasoleoPage(
          coordenadasRuta: _coordenadasRuta,
          radioRutaKm: _settings.gasolinerasRutaKm,
          ubicacionActual: _posicionActual,
          onGasolinerasChanged: (gasolineras) {
            if (!mounted) return;

            setState(() {
              _gasolineras = gasolineras;
            });
          },
        ),
      ),
      _Section(
        id: _HomeSection.parking,
        title: 'Parking',
        icon: Icons.local_parking_outlined,
        page: ParkingPage(
          coordenadasRuta: _coordenadasRuta,
          distanciaMaximaRutaKm: _settings.parkingsListaRutaKm,
          ubicacionActual: _posicionActual,
        ),
      ),
      _Section(
        id: _HomeSection.notices,
        title: 'Avisos',
        icon: Icons.warning_amber_outlined,
        page: AvisosPage(
          avisosMeteorologicos: _avisosMeteorologicos,
          onMostrarControlesChanged: (mostrar) {
            setState(() {
              _mostrarControles = mostrar;
            });
          },
        ),
      ),
    ];

    return PopScope(
      canPop: _utilityPage == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _utilityPage != null) {
          setState(() {
            _utilityPage = null;
          });
        }
      },
      child: Scaffold(
        backgroundColor: arcenBackground,
        body: SafeArea(
          child: Column(
            children: [
              // Cabecera de marca y ubicación.
              _buildBrandHeader(compact),

              // Camión y conductor seleccionados.
              _buildDriverHeader(compact),

              // Contenido de las secciones.
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: IndexedStack(
                        index: sections.indexWhere(
                          (section) => section.id == selectedSection,
                        ),
                        children: [
                          for (final section in sections)
                            KeyedSubtree(
                              key: ValueKey(section.title),
                              child: section.page,
                            ),
                        ],
                      ),
                    ),
                    if (_utilityPage != null)
                      Positioned.fill(child: _utilityPage!),
                  ],
                ),
              ),

              // Navegación inferior.
              _buildBottomNavigation(compact, sections),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // MAPA PRINCIPAL Y FILTROS
  // ------------------------------------------------------------

  Widget _buildHoursPage() {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _selectionSnapshots,
      builder: (context, snapshot) {
        final driverId = snapshot.data?.data()?['conductorId'] as String?;
        return HoursPage(
          key: ValueKey('hours-$driverId'),
          driverId: driverId,
          position: _ultimaPosicionGps,
          route: _coordenadasRuta,
          routeStartedAt: _rutaCalculadaEn,
          routeDurationSeconds: _duracionRutaSegundos,
          parkings: _parkings,
          maxParkingDistanceKm: _settings.parkingsListaRutaKm,
        );
      },
    );
  }

  Widget _buildDrivingSummary(bool compact) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _selectionSnapshots,
      builder: (context, selectionSnapshot) {
        if (selectionSnapshot.hasError) {
          return _drivingSummaryCard(
            compact,
            activity: 'No disponible',
            continuous: '--',
            untilBreak: '--',
            parking: 'No se pudo leer el conductor seleccionado.',
          );
        }

        final driverId =
            selectionSnapshot.data?.data()?['conductorId'] as String?;
        if (driverId == null || driverId.isEmpty) {
          return _drivingSummaryCard(
            compact,
            activity: 'Sin conductor',
            continuous: '0 min',
            untilBreak: '4 h 30 min',
            parking: 'Selecciona un conductor para registrar sus horas.',
          );
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _driverSnapshotsFor(driverId),
          builder: (context, driverSnapshot) {
            if (driverSnapshot.hasError) {
              return _drivingSummaryCard(
                compact,
                activity: 'No disponible',
                continuous: '--',
                untilBreak: '--',
                parking: 'No se pudieron cargar las horas del conductor.',
              );
            }

            final rawHours = driverSnapshot.data?.data()?['registroHoras'];
            final hours = DriverHours.fromMap(
              rawHours is Map ? Map<String, dynamic>.from(rawHours) : null,
            );
            final trackingRoute =
                _coordenadasRuta.isNotEmpty && _rutaCalculadaEn != null;
            final recommendation = recommendPauseParking(
              hours: hours,
              currentPosition: _posicionActual,
              route: _coordenadasRuta,
              routeDurationSeconds: _duracionRutaSegundos,
              parkings: _parkings,
              maxDistanceFromRouteKm: _settings.parkingsListaRutaKm,
            );

            final parkingText = recommendation == null
                ? 'Calcula una ruta para recomendar el parking de pausa.'
                : '${recommendation.name} · '
                      'aprox. ${_textoDuracion(recommendation.secondsFromCurrentPosition)}'
                      '${recommendation.beforeDrivingLimit ? '' : ' (después del límite)'}';

            return _drivingSummaryCard(
              compact,
              activity: trackingRoute
                  ? hours.activity.label
                  : 'Sin ruta activa',
              continuous: _textoDuracion(
                trackingRoute ? hours.continuousDrivingSeconds : 0,
              ),
              untilBreak: _textoDuracion(
                trackingRoute
                    ? hours.drivingSecondsUntilBreak
                    : DriverHours.continuousLimitSeconds,
              ),
              parking: trackingRoute
                  ? parkingText
                  : 'Calcula una ruta para iniciar el registro de conducción.',
              continuousProgress: trackingRoute
                  ? hours.continuousDrivingSeconds /
                        DriverHours.continuousLimitSeconds
                  : 0,
              parkingLate:
                  trackingRoute &&
                  recommendation != null &&
                  !recommendation.beforeDrivingLimit,
            );
          },
        );
      },
    );
  }

  Widget _drivingSummaryCard(
    bool compact, {
    required String activity,
    required String continuous,
    required String untilBreak,
    required String parking,
    double continuousProgress = 0,
    bool parkingLate = false,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFD8E0E9)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.timelapse_outlined, color: arcenBlue, size: 18),
              const SizedBox(width: 7),
              const Expanded(
                child: Text(
                  'TIEMPOS DE CONDUCCIÓN',
                  style: TextStyle(
                    color: arcenDarkBlue,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
              Text(
                activity.toUpperCase(),
                style: const TextStyle(
                  color: Colors.blueGrey,
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              SizedBox(
                width: 42,
                height: 42,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        value: continuousProgress.clamp(0.0, 1.0).toDouble(),
                        strokeWidth: 4,
                        backgroundColor: const Color(0xFFD8E0E9),
                        valueColor: const AlwaysStoppedAnimation(arcenBlue),
                      ),
                    ),
                    const Icon(
                      Icons.local_shipping_outlined,
                      size: 17,
                      color: arcenDarkBlue,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Conducción seguida',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: arcenDarkBlue,
                            ),
                          ),
                        ),
                        Text(
                          continuous,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: arcenDarkBlue,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Hasta la pausa: $untilBreak',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.blueGrey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                Icons.local_parking_outlined,
                color: parkingLate ? Colors.red.shade700 : arcenBlue,
                size: 16,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  parking,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: parkingLate ? Colors.red.shade700 : Colors.blueGrey,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _textoDuracion(int segundos) {
    final horas = segundos ~/ 3600;
    final minutos = (segundos % 3600) ~/ 60;
    if (horas == 0) return '$minutos min';
    return '$horas h ${minutos.toString().padLeft(2, '0')} min';
  }

  Widget _buildHomeMap(bool compact) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 12 : 20,
        12,
        compact ? 12 : 20,
        12,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildMaintenanceAlerts(compact),
          const SizedBox(height: 10),
          _buildDrivingSummary(compact),
          const SizedBox(height: 10),
          if (_posicionActual == null)
            const Padding(
              padding: EdgeInsets.only(bottom: 6),
              child: Text(
                'Esperando ubicación GPS para mostrar distancias.',
                style: TextStyle(fontSize: 11, color: Colors.blueGrey),
              ),
            ),
          const SizedBox(height: 12),

          // Botones de las capas.
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _mapFilterButton(
                label: 'Gasóleo',
                icon: Icons.local_gas_station_outlined,
                selected: _mostrarGasoleo,
                onSelected: (value) {
                  setState(() {
                    _mostrarGasoleo = value;
                  });
                },
              ),
              _mapFilterButton(
                label: 'Parking',
                icon: Icons.local_parking_outlined,
                selected: _mostrarParking,
                onSelected: (value) {
                  setState(() {
                    _mostrarParking = value;
                  });
                },
              ),
              _mapFilterButton(
                label: 'Avisos',
                icon: Icons.warning_amber_outlined,
                selected: _mostrarAvisos,
                onSelected: (value) {
                  setState(() {
                    _mostrarAvisos = value;
                  });
                },
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Mapa en una tarjeta en la parte inferior.
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFD8E0E9)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.06),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: MapPage(
                onLocationChanged: (poblacion, provincia) {
                  if (!mounted) return;

                  setState(() {
                    _poblacion = poblacion.toUpperCase();
                    _provincia = provincia.toUpperCase();
                  });
                },
                onGpsPositionChanged: (position) {
                  if (!mounted) return;
                  setState(() {
                    _ultimaPosicionGps = position;
                    _posicionActual = LatLng(
                      position.latitude,
                      position.longitude,
                    );
                  });
                },
                coordenadasRuta: _coordenadasRuta,

                // Las gasolineras solo se muestran
                // cuando el filtro Gasóleo está activado.
                gasolineras: _mostrarGasoleo ? _gasolineras : [],
                parkings: _mostrarParking ? _parkings : [],
                avisos: _avisos,
                avisosMeteorologicos: _avisosMeteorologicos,
                mostrarAvisos: _mostrarAvisos && _mostrarControles,
                distanciaParkingsRutaKm: _settings.parkingsMapaRutaKm,
                distanciaAvisosGpsKm: _settings.avisosGpsKm,
                distanciaAvisosMeteorologicosRutaKm:
                    _settings.avisosMeteorologicosRutaKm,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMaintenanceAlerts(bool compact) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _selectionSnapshots,
      builder: (context, selectionSnapshot) {
        if (selectionSnapshot.hasError) {
          return _maintenanceMessage(
            'No se pudo consultar el camión seleccionado.',
            isError: true,
          );
        }

        final truckId = selectionSnapshot.data?.data()?['camionId'] as String?;
        if (truckId == null || truckId.isEmpty) {
          return const SizedBox.shrink();
        }

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: _truckSnapshotsFor(truckId),
          builder: (context, truckSnapshot) {
            if (truckSnapshot.hasError) {
              return _maintenanceMessage(
                'No se pudieron cargar los mantenimientos del camión.',
                isError: true,
              );
            }

            final truck = truckSnapshot.data?.data();
            if (truck == null) return const SizedBox.shrink();

            final maintenanceData = truck['mantenimientos'];
            if (maintenanceData is! Map) return const SizedBox.shrink();

            const labels = <String, String>{
              'aceiteFiltros': 'Aceite y filtros',
              'frenos': 'Frenos',
              'neumaticos': 'Neumáticos',
              'itv': 'ITV',
            };
            DateTime? readDate(dynamic value) {
              if (value is Timestamp) return value.toDate();
              if (value is DateTime) return value;
              if (value is String) return DateTime.tryParse(value);
              return null;
            }

            final now = DateTime.now();
            final today = DateTime(now.year, now.month, now.day);
            final deadline = today.add(const Duration(days: 30));
            final dueItems = <({String label, DateTime date})>[];

            for (final entry in labels.entries) {
              final item = maintenanceData[entry.key];
              if (item is! Map) continue;
              final date = readDate(item['proximaFecha']);
              if (date == null) continue;
              if (date.isBefore(deadline) || date.isAtSameMomentAs(deadline)) {
                dueItems.add((label: entry.value, date: date));
              }
            }

            if (dueItems.isEmpty) return const SizedBox.shrink();
            dueItems.sort((a, b) => a.date.compareTo(b.date));

            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 10),
              padding: EdgeInsets.all(compact ? 11 : 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                border: Border.all(color: const Color(0xFFFFD166)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.build_circle_outlined,
                        color: Color(0xFF9A6700),
                        size: 19,
                      ),
                      const SizedBox(width: 7),
                      const Expanded(
                        child: Text(
                          'MANTENIMIENTOS PRÓXIMOS',
                          style: TextStyle(
                            color: Color(0xFF795300),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                      Text(
                        (truck['matricula'] ?? '').toString(),
                        style: const TextStyle(
                          color: Color(0xFF795300),
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  for (final item in dueItems)
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Row(
                        children: [
                          Icon(
                            item.date.isBefore(today)
                                ? Icons.warning_amber_rounded
                                : Icons.event_available_outlined,
                            size: 16,
                            color: item.date.isBefore(today)
                                ? Colors.red.shade700
                                : const Color(0xFF9A6700),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              item.label,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                          Text(
                            _textoFechaMantenimiento(item.date, today),
                            style: TextStyle(
                              color: item.date.isBefore(today)
                                  ? Colors.red.shade700
                                  : const Color(0xFF795300),
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: () => openTruckManagement(truckId: truckId),
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: const Text('Ver ficha'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFF795300),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _maintenanceMessage(String message, {required bool isError}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        message,
        style: TextStyle(
          color: isError ? Colors.red.shade700 : Colors.blueGrey,
          fontSize: 12,
        ),
      ),
    );
  }

  String _textoFechaMantenimiento(DateTime fecha, DateTime hoy) {
    final dias = DateTime(
      fecha.year,
      fecha.month,
      fecha.day,
    ).difference(hoy).inDays;
    if (dias < 0) return 'Vencido hace ${-dias} días';
    if (dias == 0) return 'Vence hoy';
    if (dias == 1) return 'Vence mañana';
    return 'En $dias días';
  }

  Widget _mapFilterButton({
    required String label,
    required IconData icon,
    required bool selected,
    required ValueChanged<bool> onSelected,
  }) {
    return FilterChip(
      selected: selected,
      showCheckmark: false,
      onSelected: onSelected,
      avatar: Icon(icon, size: 19, color: selected ? Colors.white : arcenBlue),
      label: Text(label),
      labelStyle: TextStyle(
        color: selected ? Colors.white : arcenDarkBlue,
        fontWeight: FontWeight.w700,
        fontSize: 13,
      ),
      backgroundColor: Colors.white,
      selectedColor: arcenBlue,
      side: BorderSide(color: selected ? arcenBlue : const Color(0xFFD8E0E9)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 5),
    );
  }

  // ------------------------------------------------------------
  // CABECERA DE MARCA Y UBICACIÓN
  // ------------------------------------------------------------

  Widget _buildBrandHeader(bool compact) {
    return Container(
      width: double.infinity,
      color: arcenBlue,
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 24,
        vertical: compact ? 12 : 18,
      ),
      child: Row(
        children: [
          PopupMenuButton<_BrandMenuChoice>(
            tooltip: 'Menú de Arcén',
            position: PopupMenuPosition.under,
            onSelected: (choice) {
              switch (choice) {
                case _BrandMenuChoice.configuration:
                  unawaited(_abrirConfiguracion());
                  break;
                case _BrandMenuChoice.about:
                  _mostrarAcercaDe();
                  break;
                case _BrandMenuChoice.logout:
                  unawaited(logout());
                  break;
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: _BrandMenuChoice.configuration,
                child: Row(
                  children: [
                    Icon(Icons.settings_outlined),
                    SizedBox(width: 10),
                    Text('Configuración'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: _BrandMenuChoice.about,
                child: Row(
                  children: [
                    Icon(Icons.info_outline),
                    SizedBox(width: 10),
                    Text('Acerca de'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: _BrandMenuChoice.logout,
                child: Row(
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 10),
                    Text('Salir'),
                  ],
                ),
              ),
            ],
            child: Image.asset(
              'lib/imag/logo.PNG',
              width: compact ? 42 : 54,
              height: compact ? 42 : 54,
              fit: BoxFit.contain,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'ARCÉN',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 23 : 30,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.3,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  'PARA QUIEN VIVE EN LA CARRETERA',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: compact ? 8 : 11,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            flex: 0,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.location_on,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 3),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: compact ? 105 : 180,
                      ),
                      child: Text(
                        _poblacion,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: compact ? 11 : 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _provincia.isEmpty
                      ? 'OBTENIENDO UBICACIÓN...'
                      : '$_provincia · GPS ACTIVO',
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: compact ? 7 : 10,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          Material(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(9),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _abrirVentajas,
              borderRadius: BorderRadius.circular(9),
              child: SizedBox(
                width: compact ? 40 : 46,
                height: compact ? 40 : 46,
                child: Icon(
                  Icons.confirmation_number_outlined,
                  color: Colors.white,
                  size: compact ? 22 : 25,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // CABECERA DEL CAMIÓN Y CONDUCTOR
  // ------------------------------------------------------------

  Widget _buildDriverHeader(bool compact) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _selectionSnapshots,
      builder: (context, selectionSnapshot) {
        final selection = selectionSnapshot.data?.data() ?? {};

        final truckId = selection['camionId'] as String?;
        final driverId = selection['conductorId'] as String?;

        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: truckId == null ? null : _truckSnapshotsFor(truckId),
          builder: (context, truckSnapshot) {
            final truck = truckSnapshot.data?.data();

            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: driverId == null ? null : _driverSnapshotsFor(driverId),
              builder: (context, driverSnapshot) {
                final driver = driverSnapshot.data?.data();

                final plate =
                    truck?['matricula'] as String? ?? 'Seleccionar camión';

                final driverName =
                    driver?['nombreCompleto'] as String? ??
                    'Seleccionar conductor';

                final type = truck?['tipo'] as String? ?? 'Tipo de vehículo';

                final tonnage = truck?['tonelaje']?.toString() ?? '—';
                final currentLoad = _formatHeaderWeight(
                  truck?['cargaActualKg'],
                );

                return Container(
                  width: double.infinity,
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 12 : 24,
                    vertical: compact ? 10 : 18,
                  ),
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    border: Border(
                      bottom: BorderSide(color: Color(0xFFDCE3EB)),
                    ),
                  ),
                  child: compact
                      ? _buildCompactDriverHeader(
                          driverName: driverName,
                          plate: plate,
                          type: type,
                          tonnage: tonnage,
                          currentLoad: currentLoad,
                        )
                      : _buildWideDriverHeader(
                          driverName: driverName,
                          plate: plate,
                          type: type,
                          tonnage: tonnage,
                          currentLoad: currentLoad,
                        ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildCompactDriverHeader({
    required String driverName,
    required String plate,
    required String type,
    required String tonnage,
    required String currentLoad,
  }) {
    return Column(
      children: [
        InkWell(
          onTap: openDriverManagement,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const Icon(Icons.person_outline, color: arcenBlue, size: 23),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        driverName,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          color: arcenDarkBlue,
                        ),
                      ),
                      Text(
                        type,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 10,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 18),
        InkWell(
          onTap: openTruckManagement,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                _licensePlate(plate, compact: true),
                const Spacer(),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$currentLoad kg',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'de $tonnage t',
                      style: const TextStyle(fontSize: 10, color: Colors.grey),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWideDriverHeader({
    required String driverName,
    required String plate,
    required String type,
    required String tonnage,
    required String currentLoad,
  }) {
    return Row(
      children: [
        InkWell(
          onTap: openTruckManagement,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Row(children: [_licensePlate(plate)]),
          ),
        ),
        const SizedBox(width: 18),
        const SizedBox(
          height: 42,
          child: VerticalDivider(width: 1, thickness: 1),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: InkWell(
            onTap: openDriverManagement,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          driverName,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 17,
                            color: arcenDarkBlue,
                          ),
                        ),
                        Text(
                          type,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.blueGrey,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$currentLoad kg',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
            ),
            Text(
              'de $tonnage t',
              style: const TextStyle(color: Colors.blueGrey, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }

  String _formatHeaderWeight(dynamic value) {
    final weight = value is num ? value : num.tryParse(value?.toString() ?? '');
    return weight == null ? '—' : weight.round().toString();
  }

  Widget _licensePlate(String plate, {bool compact = false}) {
    return Container(
      padding: const EdgeInsets.all(1.5),
      decoration: BoxDecoration(
        color: const Color(0xFF20252B),
        borderRadius: BorderRadius.circular(4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x26000000),
            blurRadius: 2,
            offset: Offset(0, 1),
          ),
        ],
      ),
      child: Container(
        padding: EdgeInsets.only(
          left: compact ? 1 : 2,
          right: compact ? 5 : 6,
          top: compact ? 2 : 3,
          bottom: compact ? 2 : 3,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAF7),
          border: Border.all(color: const Color(0xFFB8BEC4), width: 0.7),
          borderRadius: BorderRadius.circular(3),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: compact ? 15 : 17,
              height: compact ? 24 : 26,
              decoration: BoxDecoration(
                color: const Color(0xFF064B9B),
                borderRadius: BorderRadius.circular(2),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.star, color: Colors.white, size: compact ? 5 : 6),
                  Text(
                    'E',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: compact ? 9 : 10,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Icon(Icons.star, color: Colors.white, size: compact ? 5 : 6),
                ],
              ),
            ),
            SizedBox(width: compact ? 4 : 5),
            Text(
              plate.toUpperCase(),
              maxLines: 1,
              style: TextStyle(
                color: const Color(0xFF15191D),
                fontSize: compact ? 12 : 13,
                fontWeight: FontWeight.w900,
                letterSpacing: compact ? 0.8 : 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // NAVEGACIÓN INFERIOR
  // ------------------------------------------------------------

  Widget _buildBottomNavigation(bool compact, List<_Section> sections) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFDCE3EB))),
      ),
      padding: EdgeInsets.only(top: 5, bottom: compact ? 2 : 8),
      child: Row(
        children: sections.map((section) {
          final selected = selectedSection == section.id;
          final color = selected ? arcenBlue : const Color(0xFF718096);

          return Expanded(
            child: InkWell(
              onTap: () {
                setState(() {
                  selectedSection = section.id;
                  _utilityPage = null;
                });
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(section.icon, size: compact ? 23 : 28, color: color),
                    const SizedBox(height: 3),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        section.title,
                        style: TextStyle(
                          fontSize: compact ? 10 : 12,
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: 3,
                      width: selected ? 25 : 0,
                      decoration: BoxDecoration(
                        color: arcenBlue,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// --------------------------------------------------------------
// MODELO DE SECCIÓN
// --------------------------------------------------------------

enum _HomeSection { map, journey, hours, diesel, parking, notices }

enum _BrandMenuChoice { configuration, about, logout }

class _Section {
  final _HomeSection id;
  final String title;
  final IconData icon;
  final Widget page;

  const _Section({
    required this.id,
    required this.title,
    required this.icon,
    required this.page,
  });
}

// --------------------------------------------------------------
// PANTALLAS TEMPORALES
// --------------------------------------------------------------

class _AdvantagesPage extends StatelessWidget {
  const _AdvantagesPage();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: arcenBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
            child: const Text(
              'VENTAJAS',
              style: TextStyle(
                color: arcenDarkBlue,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const Expanded(
            child: Center(
              child: Text(
                'Próximamente...',
                style: TextStyle(
                  color: arcenDarkBlue,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
