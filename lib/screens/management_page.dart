import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/driver_hours.dart';

const Color arcenBlue = Color(0xFF0755A6);
const Color arcenDarkBlue = Color(0xFF07366D);
const Color arcenBackground = Color(0xFFF2F5F8);
const Color arcenBorder = Color(0xFFD8E0E9);

enum ManagementType { trucks, drivers }

class ManagementPage extends StatefulWidget {
  final ManagementType type;
  final int mantenimientoIntervaloMeses;
  final String? abrirCamionId;

  const ManagementPage({
    super.key,
    required this.type,
    this.mantenimientoIntervaloMeses = 24,
    this.abrirCamionId,
  });

  @override
  State<ManagementPage> createState() => _ManagementPageState();
}

class _ManagementPageState extends State<ManagementPage> {
  final db = FirebaseFirestore.instance;
  final uid = FirebaseAuth.instance.currentUser!.uid;
  bool _camionInicialAbierto = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_camionInicialAbierto || !isTruck || widget.abrirCamionId == null) {
      return;
    }

    _camionInicialAbierto = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _abrirFichaCamion(widget.abrirCamionId!);
    });
  }

  Future<void> _abrirFichaCamion(String id) async {
    try {
      final snapshot = await collection.doc(id).get();
      if (!mounted) return;
      if (!snapshot.exists) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('El camión ya no está disponible.')),
        );
        return;
      }

      await editRecord(
        id: id,
        data: snapshot.data(),
        enfocarMantenimiento: true,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No se pudo abrir la ficha del camión: $error')),
      );
    }
  }

  CollectionReference<Map<String, dynamic>> get collection {
    final name = widget.type == ManagementType.trucks
        ? 'camiones'
        : 'conductores';

    return db.collection('usuarios').doc(uid).collection(name);
  }

  DocumentReference<Map<String, dynamic>> get selectionDoc {
    return db
        .collection('usuarios')
        .doc(uid)
        .collection('configuracion')
        .doc('seleccion');
  }

  bool get isTruck => widget.type == ManagementType.trucks;

  String get title =>
      isTruck ? 'Gestión de camiones' : 'Gestión de conductores';

  String get selectedKey => isTruck ? 'camionId' : 'conductorId';

  String get displayField => isTruck ? 'matricula' : 'nombreCompleto';

  String _formatHours(dynamic value) {
    final seconds = value is num ? value.toInt() : 0;
    final safeSeconds = math.max(0, seconds);
    final hours = safeSeconds ~/ 3600;
    final minutes = (safeSeconds % 3600) ~/ 60;
    return hours == 0 ? '$minutes min' : '$hours h $minutes min';
  }

  // ------------------------------------------------------------
  // CREAR Y EDITAR REGISTROS
  // ------------------------------------------------------------

  Future<void> editRecord({
    String? id,
    Map<String, dynamic>? data,
    bool enfocarMantenimiento = false,
  }) async {
    final formKey = GlobalKey<FormState>();
    final mantenimientoKey = GlobalKey();
    final controllers = <String, TextEditingController>{};

    final fields = isTruck
        ? <String, String>{
            'matricula': 'Matrícula',
            'marca': 'Marca',
            'modelo': 'Modelo',
            'tipo': 'Tipo de vehículo',
            'tonelaje': 'Tonelaje (t)',
            'mmaKg': 'MMA (kg)',
            'taraKg': 'Tara del vehículo vacío (kg)',
            'cargaActualKg': 'Carga actual (kg)',
            'kilometros': 'Cuentakilómetros (km)',
          }
        : <String, String>{'nombre': 'Nombre', 'apellidos': 'Apellidos'};

    for (final field in fields.keys) {
      final value = data?[field];

      controllers[field] = TextEditingController(
        text: value == null ? '' : value.toString(),
      );
    }

    const maintenanceTypes = <({String key, String label})>[
      (key: 'aceiteFiltros', label: 'Aceite y filtros'),
      (key: 'frenos', label: 'Frenos'),
      (key: 'neumaticos', label: 'Neumáticos'),
      (key: 'itv', label: 'ITV'),
    ];
    final storedMaintenance = data?['mantenimientos'];
    final maintenanceMap = storedMaintenance is Map
        ? Map<String, dynamic>.from(storedMaintenance)
        : <String, dynamic>{};
    final storedHours = data?['registroHoras'];
    final driverHours = storedHours is Map
        ? Map<String, dynamic>.from(storedHours)
        : <String, dynamic>{};
    DateTime? readDate(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      if (value is String) return DateTime.tryParse(value);
      return null;
    }

    final lastMaintenanceDates = <String, DateTime?>{};
    final nextMaintenanceDates = <String, DateTime?>{};
    for (final type in maintenanceTypes) {
      final stored = maintenanceMap[type.key];
      final values = stored is Map
          ? Map<String, dynamic>.from(stored)
          : <String, dynamic>{};
      lastMaintenanceDates[type.key] = readDate(values['ultimaFecha']);
      nextMaintenanceDates[type.key] = readDate(values['proximaFecha']);
    }

    String formatDate(DateTime? date) {
      if (date == null) return 'Sin configurar';
      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      return '$day/$month/${date.year}';
    }

    DateTime addMonths(DateTime date, int months) {
      final monthIndex = date.month - 1 + months;
      final year = date.year + monthIndex ~/ 12;
      final month = monthIndex % 12 + 1;
      final lastDay = DateTime(year, month + 1, 0).day;
      return DateTime(year, month, math.min(date.day, lastDay));
    }

    final kmToAddController = TextEditingController();

    double number(String key) {
      final controller = controllers[key];
      if (controller == null) return 0;
      return double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? 0;
    }

    String formatNumber(double value) {
      return value.round().toString();
    }

    var maintenanceFocusScheduled = false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, refreshDialog) {
            if (enfocarMantenimiento && !maintenanceFocusScheduled) {
              maintenanceFocusScheduled = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                final target = mantenimientoKey.currentContext;
                if (target != null) {
                  Scrollable.ensureVisible(
                    target,
                    duration: const Duration(milliseconds: 350),
                    alignment: 0.05,
                  );
                }
              });
            }

            final mma = number('mmaKg');
            final tara = number('taraKg');
            final carga = number('cargaActualKg');
            final km = number('kilometros');

            final cargaMaxima = mma - tara;
            final pesoTotal = tara + carga;
            final margen = mma - pesoTotal;
            final pesoCorrecto = mma > 0 && pesoTotal <= mma;
            final porcentaje = mma > 0
                ? (pesoTotal / mma).clamp(0.0, 1.0)
                : 0.0;

            void cambiarCarga(double cantidad) {
              final nuevaCarga = carga + cantidad;

              if (nuevaCarga < 0) {
                return;
              }

              controllers['cargaActualKg']!.text = formatNumber(nuevaCarga);

              refreshDialog(() {});
            }

            void sumarKilometros() {
              final cantidad = double.tryParse(
                kmToAddController.text.trim().replaceAll(',', '.'),
              );

              if (cantidad == null || cantidad <= 0) {
                ScaffoldMessenger.of(this.context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'Introduce una cantidad de kilómetros válida.',
                    ),
                  ),
                );
                return;
              }

              controllers['kilometros']!.text = formatNumber(km + cantidad);

              kmToAddController.clear();
              refreshDialog(() {});
            }

            Future<void> elegirFechaMantenimiento(
              String key,
              bool ultimaFecha,
            ) async {
              final currentDate = ultimaFecha
                  ? lastMaintenanceDates[key]
                  : nextMaintenanceDates[key];
              final selectedDate = await showDatePicker(
                context: context,
                initialDate: currentDate ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
                helpText: ultimaFecha
                    ? 'Selecciona la última fecha'
                    : 'Selecciona la próxima fecha',
              );
              if (selectedDate == null) return;
              if (ultimaFecha) {
                lastMaintenanceDates[key] = selectedDate;
              } else {
                nextMaintenanceDates[key] = selectedDate;
              }
              refreshDialog(() {});
            }

            return Dialog(
              backgroundColor: arcenBackground,
              insetPadding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: 760,
                  maxHeight: MediaQuery.sizeOf(context).height * 0.90,
                ),
                child: Column(
                  children: [
                    // Cabecera.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 18,
                      ),
                      decoration: const BoxDecoration(
                        color: arcenBlue,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(8),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.local_shipping_outlined,
                            color: Colors.white,
                            size: 28,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  id == null
                                      ? 'Nuevo ${isTruck ? 'camión' : 'conductor'}'
                                      : 'Editar ${isTruck ? 'camión' : 'conductor'}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 21,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (isTruck)
                                  const Text(
                                    'Datos, báscula y cuentakilómetros',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 13,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Formulario desplazable.
                    Expanded(
                      child: Form(
                        key: formKey,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _sectionTitle(
                                isTruck
                                    ? 'Datos del vehículo'
                                    : 'Datos del conductor',
                                Icons.local_shipping_outlined,
                              ),
                              const SizedBox(height: 12),

                              LayoutBuilder(
                                builder: (context, constraints) {
                                  final columns = constraints.maxWidth >= 520
                                      ? 2
                                      : 1;
                                  final fieldWidth =
                                      (constraints.maxWidth -
                                          (columns - 1) * 12) /
                                      columns;

                                  return Wrap(
                                    spacing: 12,
                                    runSpacing: 12,
                                    children: fields.entries.map((entry) {
                                      final key = entry.key;
                                      final numeric = {
                                        'tonelaje',
                                        'mmaKg',
                                        'taraKg',
                                        'cargaActualKg',
                                        'kilometros',
                                      }.contains(key);

                                      return SizedBox(
                                        width: fieldWidth,
                                        child: TextFormField(
                                          controller: controllers[key],
                                          keyboardType: numeric
                                              ? const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                )
                                              : TextInputType.text,
                                          onChanged: (_) {
                                            if (isTruck &&
                                                {
                                                  'mmaKg',
                                                  'taraKg',
                                                  'cargaActualKg',
                                                  'kilometros',
                                                }.contains(key)) {
                                              refreshDialog(() {});
                                            }
                                          },
                                          decoration: InputDecoration(
                                            labelText: entry.value,
                                            filled: true,
                                            fillColor: Colors.white,
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                            ),
                                            enabledBorder: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              borderSide: const BorderSide(
                                                color: arcenBorder,
                                              ),
                                            ),
                                          ),
                                          validator: (value) {
                                            if (value == null ||
                                                value.trim().isEmpty) {
                                              return 'Campo obligatorio';
                                            }

                                            if (numeric) {
                                              final parsed = double.tryParse(
                                                value.trim().replaceAll(
                                                  ',',
                                                  '.',
                                                ),
                                              );

                                              if (parsed == null ||
                                                  !parsed.isFinite ||
                                                  parsed < 0) {
                                                return 'Introduce un número válido';
                                              }
                                            }

                                            return null;
                                          },
                                        ),
                                      );
                                    }).toList(),
                                  );
                                },
                              ),

                              if (!isTruck) ...[
                                const SizedBox(height: 22),
                                _sectionTitle(
                                  'Horas registradas',
                                  Icons.timelapse_outlined,
                                ),
                                const SizedBox(height: 12),
                                _panel(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Actividad actual: ${DriverActivity.fromKey(driverHours['activity']).label}',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                          color: arcenDarkBlue,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Conducción seguida: ${_formatHours(driverHours['continuousDrivingSeconds'])}',
                                      ),
                                      Text(
                                        'Conducción diaria: ${_formatHours(driverHours['dailyDrivingSeconds'])}',
                                      ),
                                      Text(
                                        'Conducción semanal: ${_formatHours(driverHours['weeklyDrivingSeconds'])}',
                                      ),
                                      Text(
                                        'Conducción en dos semanas: '
                                        '${_formatHours(((driverHours['weeklyDrivingSeconds'] as num?)?.toInt() ?? 0) + ((driverHours['previousWeekDrivingSeconds'] as num?)?.toInt() ?? 0))}',
                                      ),
                                      const SizedBox(height: 6),
                                      const Text(
                                        'El registro se actualiza al detectar movimiento GPS y al cambiar manualmente de actividad.',
                                        style: TextStyle(
                                          color: Colors.blueGrey,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],

                              if (isTruck) ...[
                                const SizedBox(height: 22),

                                // BÁSCULA.
                                _sectionTitle('Báscula', Icons.scale_outlined),
                                const SizedBox(height: 4),
                                const Text(
                                  'Controla el peso total y la carga disponible.',
                                  style: TextStyle(
                                    color: Colors.blueGrey,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 12),

                                _panel(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _metricLabel(
                                        'PESO MÁXIMO AUTORIZADO (MMA)',
                                      ),
                                      const SizedBox(height: 5),
                                      _metricValue('${formatNumber(mma)} kg'),
                                      const SizedBox(height: 14),

                                      Row(
                                        children: [
                                          Expanded(
                                            child: _smallMetric(
                                              'TARA',
                                              '${formatNumber(tara)} kg',
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: _smallMetric(
                                              'CARGA ACTUAL',
                                              '${formatNumber(carga)} kg',
                                            ),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 14),

                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          _weightButton(
                                            '-500 KG',
                                            () => cambiarCarga(-500),
                                          ),
                                          _weightButton(
                                            '-100 KG',
                                            () => cambiarCarga(-100),
                                          ),
                                          _weightButton(
                                            '+100 KG',
                                            () => cambiarCarga(100),
                                          ),
                                          _weightButton(
                                            '+500 KG',
                                            () => cambiarCarga(500),
                                          ),
                                        ],
                                      ),

                                      const SizedBox(height: 18),

                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: Colors.white,
                                          border: Border.all(
                                            color: pesoCorrecto
                                                ? arcenBlue
                                                : Colors.red,
                                            width: 1.5,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            14,
                                          ),
                                        ),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            _metricLabel('ESTADO DE LA CARGA'),
                                            const SizedBox(height: 6),
                                            Text(
                                              mma <= 0
                                                  ? 'Introduce la MMA'
                                                  : margen < 0
                                                  ? 'Exceso de ${formatNumber(-margen)} kg'
                                                  : 'Puedes cargar ${formatNumber(margen)} kg más',
                                              style: TextStyle(
                                                color: margen < 0
                                                    ? Colors.red.shade700
                                                    : arcenDarkBlue,
                                                fontSize: 23,
                                                height: 1.15,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            ClipRRect(
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: LinearProgressIndicator(
                                                value: porcentaje,
                                                minHeight: 9,
                                                backgroundColor: const Color(
                                                  0xFFE5EAF0,
                                                ),
                                                color: margen < 0
                                                    ? Colors.red
                                                    : arcenBlue,
                                              ),
                                            ),
                                            const SizedBox(height: 8),
                                            Text(
                                              mma <= 0
                                                  ? 'Configura la masa máxima autorizada.'
                                                  : '${(porcentaje * 100).toStringAsFixed(1)} % del MMA utilizado.',
                                              style: const TextStyle(
                                                color: Colors.blueGrey,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      const SizedBox(height: 12),

                                      Row(
                                        children: [
                                          Expanded(
                                            child: _smallMetric(
                                              'PESO TOTAL',
                                              '${formatNumber(pesoTotal)} kg',
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: _smallMetric(
                                              'CARGA MÁXIMA',
                                              '${formatNumber(cargaMaxima < 0 ? 0 : cargaMaxima)} kg',
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 22),

                                // KILÓMETROS.
                                _sectionTitle(
                                  'Kilómetros',
                                  Icons.speed_outlined,
                                ),
                                const SizedBox(height: 12),

                                _panel(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'CUENTAKILÓMETROS',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          letterSpacing: 0.8,
                                          color: Colors.blueGrey,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '${formatNumber(km)} km',
                                        style: const TextStyle(
                                          color: Color(0xFF17212E),
                                          fontSize: 30,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: kmToAddController,
                                              keyboardType:
                                                  const TextInputType.numberWithOptions(
                                                    decimal: true,
                                                  ),
                                              decoration: InputDecoration(
                                                hintText: 'Km a sumar',
                                                suffixText: 'km',
                                                filled: true,
                                                fillColor: const Color(
                                                  0xFFF2F5F8,
                                                ),
                                                border: OutlineInputBorder(
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                ),
                                              ),
                                              onSubmitted: (_) =>
                                                  sumarKilometros(),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          FilledButton(
                                            onPressed: sumarKilometros,
                                            style: FilledButton.styleFrom(
                                              backgroundColor: arcenBlue,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 18,
                                                    vertical: 18,
                                                  ),
                                            ),
                                            child: const Text('SUMAR'),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      const Text(
                                        'Los kilómetros añadidos se guardarán '
                                        'al pulsar Guardar.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.blueGrey,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 22),
                                KeyedSubtree(
                                  key: mantenimientoKey,
                                  child: _sectionTitle(
                                    'Mantenimiento',
                                    Icons.build_outlined,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                const Text(
                                  'Registra la última revisión y cuándo toca la próxima. '
                                  'Los cambios se aplican al guardar la ficha.',
                                  style: TextStyle(
                                    color: Colors.blueGrey,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                for (final maintenance in maintenanceTypes) ...[
                                  _panel(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          maintenance.label,
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: arcenDarkBlue,
                                          ),
                                        ),
                                        const SizedBox(height: 10),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            OutlinedButton.icon(
                                              onPressed: () =>
                                                  elegirFechaMantenimiento(
                                                    maintenance.key,
                                                    true,
                                                  ),
                                              icon: const Icon(
                                                Icons.event_outlined,
                                                size: 18,
                                              ),
                                              label: Text(
                                                'Última: ${formatDate(lastMaintenanceDates[maintenance.key])}',
                                              ),
                                            ),
                                            OutlinedButton.icon(
                                              onPressed: () =>
                                                  elegirFechaMantenimiento(
                                                    maintenance.key,
                                                    false,
                                                  ),
                                              icon: const Icon(
                                                Icons.event_available_outlined,
                                                size: 18,
                                              ),
                                              label: Text(
                                                'Próxima: ${formatDate(nextMaintenanceDates[maintenance.key])}',
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: TextButton.icon(
                                            onPressed: () {
                                              final realizada = DateTime.now();
                                              lastMaintenanceDates[maintenance
                                                      .key] =
                                                  realizada;
                                              nextMaintenanceDates[maintenance
                                                  .key] = addMonths(
                                                realizada,
                                                widget
                                                    .mantenimientoIntervaloMeses,
                                              );
                                              refreshDialog(() {});
                                            },
                                            icon: const Icon(
                                              Icons.check_circle_outline,
                                            ),
                                            label: const Text(
                                              'Marcar realizado',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                ],
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Acciones.
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        border: Border(top: BorderSide(color: arcenBorder)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () =>
                                Navigator.pop(dialogContext, false),
                            child: const Text('Cancelar'),
                          ),
                          const SizedBox(width: 10),
                          FilledButton.icon(
                            onPressed: () {
                              if (formKey.currentState!.validate()) {
                                if (isTruck &&
                                    number('cargaActualKg') >
                                        number('mmaKg') - number('taraKg')) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text(
                                        'La carga supera la capacidad '
                                        'máxima calculada del vehículo.',
                                      ),
                                    ),
                                  );
                                  return;
                                }

                                Navigator.pop(dialogContext, true);
                              }
                            },
                            icon: const Icon(Icons.save_outlined),
                            label: const Text('Guardar'),
                            style: FilledButton.styleFrom(
                              backgroundColor: arcenBlue,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 14,
                              ),
                            ),
                          ),
                        ],
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

    if (result == true) {
      final record = <String, dynamic>{};

      for (final field in fields.keys) {
        final value = controllers[field]!.text.trim();

        if ({
          'tonelaje',
          'mmaKg',
          'taraKg',
          'cargaActualKg',
          'kilometros',
        }.contains(field)) {
          record[field] = double.parse(value.replaceAll(',', '.'));
        } else {
          record[field] = value;
        }
      }

      if (!isTruck) {
        record['nombreCompleto'] = '${record['nombre']} ${record['apellidos']}'
            .trim();
      }

      if (isTruck) {
        record['mantenimientos'] = {
          for (final maintenance in maintenanceTypes)
            maintenance.key: {
              'ultimaFecha': lastMaintenanceDates[maintenance.key] == null
                  ? null
                  : Timestamp.fromDate(lastMaintenanceDates[maintenance.key]!),
              'proximaFecha': nextMaintenanceDates[maintenance.key] == null
                  ? null
                  : Timestamp.fromDate(nextMaintenanceDates[maintenance.key]!),
            },
        };
      }

      record['actualizadoEn'] = FieldValue.serverTimestamp();

      if (id == null) {
        record['creadoEn'] = FieldValue.serverTimestamp();
        await collection.add(record);
      } else {
        await collection.doc(id).update(record);
      }

      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Registro guardado')));
      }
    }

    for (final controller in controllers.values) {
      controller.dispose();
    }
    kmToAddController.dispose();
  }

  // ------------------------------------------------------------
  // COMPONENTES VISUALES
  // ------------------------------------------------------------

  Widget _sectionTitle(String text, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: arcenBlue, size: 23),
        const SizedBox(width: 9),
        Text(
          text,
          style: const TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: arcenDarkBlue,
          ),
        ),
      ],
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: arcenBorder),
      ),
      child: child,
    );
  }

  Widget _metricLabel(String text) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.bold,
        letterSpacing: 0.7,
        color: Colors.blueGrey,
      ),
    );
  }

  Widget _metricValue(String text) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: arcenBackground,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: arcenBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 19,
                color: Color(0xFF202A36),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _smallMetric(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: arcenBackground,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.blueGrey,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Color(0xFF202A36),
            ),
          ),
        ],
      ),
    );
  }

  Widget _weightButton(String label, VoidCallback onPressed) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: arcenBlue,
        side: const BorderSide(color: arcenBlue),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
      ),
      child: Text(
        label,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
      ),
    );
  }

  // ------------------------------------------------------------
  // SELECCIONAR REGISTRO
  // ------------------------------------------------------------

  Future<void> selectRecord(String id, Map<String, dynamic> data) async {
    await selectionDoc.set({selectedKey: id}, SetOptions(merge: true));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${isTruck ? 'Camión' : 'Conductor'} seleccionado: '
            '${data[displayField]}',
          ),
        ),
      );
    }
  }

  // ------------------------------------------------------------
  // ELIMINAR REGISTRO
  // ------------------------------------------------------------

  Future<void> deleteRecord(String id) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar registro'),
        content: const Text(
          '¿Seguro que quieres eliminar este registro? '
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final selected = await selectionDoc.get();

    if (selected.data()?[selectedKey] == id) {
      await selectionDoc.set({
        selectedKey: FieldValue.delete(),
      }, SetOptions(merge: true));
    }

    await collection.doc(id).delete();
  }

  // ------------------------------------------------------------
  // LISTADO
  // ------------------------------------------------------------

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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: arcenDarkBlue,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  isTruck
                      ? 'Consulta y administra tus camiones.'
                      : 'Consulta y administra tus conductores.',
                  style: const TextStyle(color: Colors.black54, fontSize: 12),
                ),
              ],
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                    stream: collection.snapshots(),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return const Center(
                          child: Text('Error al cargar los registros'),
                        );
                      }

                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }

                      final records = snapshot.data!.docs;

                      if (records.isEmpty) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isTruck
                                      ? Icons.local_shipping_outlined
                                      : Icons.person_outline,
                                  size: 56,
                                  color: Colors.blueGrey,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Todavía no hay '
                                  '${isTruck ? 'camiones' : 'conductores'}',
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Pulsa + para crear el primer registro.',
                                ),
                              ],
                            ),
                          ),
                        );
                      }

                      return ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                        itemCount: records.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final doc = records[index];
                          final data = doc.data();

                          final name = isTruck
                              ? '${data['matricula'] ?? ''}'
                              : '${data['nombreCompleto'] ?? ''}';

                          final savedHours = data['registroHoras'];
                          final subtitle = isTruck
                              ? '${data['marca'] ?? ''} ${data['modelo'] ?? ''} · '
                                    '${data['tonelaje'] ?? 0} t'
                              : savedHours is Map
                              ? 'Conducción seguida: '
                                    '${_formatHours(savedHours['continuousDrivingSeconds'])} · '
                                    'semanal: ${_formatHours(savedHours['weeklyDrivingSeconds'])}'
                              : 'Conductor · Sin actividad registrada';

                          return Card(
                            color: Colors.white,
                            child: ListTile(
                              leading: Icon(
                                isTruck
                                    ? Icons.local_shipping_outlined
                                    : Icons.person_outline,
                                color: arcenBlue,
                                size: 30,
                              ),
                              title: Text(
                                name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(subtitle),
                              onTap: () => selectRecord(doc.id, data),
                              trailing: PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    editRecord(id: doc.id, data: data);
                                  } else if (value == 'select') {
                                    selectRecord(doc.id, data);
                                  } else if (value == 'delete') {
                                    deleteRecord(doc.id);
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Text('Editar'),
                                  ),
                                  if (isTruck)
                                    const PopupMenuItem(
                                      value: 'select',
                                      child: Text('Seleccionar camión'),
                                    ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Eliminar'),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
                ),
                Positioned(
                  right: 16,
                  bottom: 16,
                  child: FloatingActionButton.extended(
                    onPressed: () => editRecord(),
                    backgroundColor: arcenBlue,
                    foregroundColor: Colors.white,
                    icon: const Icon(Icons.add),
                    label: Text(isTruck ? 'Nuevo camión' : 'Nuevo conductor'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
