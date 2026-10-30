import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_settings.dart';

class ConfigurationPage extends StatefulWidget {
  final AppSettings initialSettings;
  final String? loadError;
  final ValueChanged<AppSettings>? onSaved;

  const ConfigurationPage({
    super.key,
    required this.initialSettings,
    this.loadError,
    this.onSaved,
  });

  @override
  State<ConfigurationPage> createState() => _ConfigurationPageState();
}

class _ConfigurationPageState extends State<ConfigurationPage> {
  final _formKey = GlobalKey<FormState>();
  late final Map<String, TextEditingController> _controllers;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final settings = widget.initialSettings;
    _controllers = {
      'gasolinerasRutaKm': _controller(settings.gasolinerasRutaKm),
      'parkingsListaRutaKm': _controller(settings.parkingsListaRutaKm),
      'parkingsMapaRutaKm': _controller(settings.parkingsMapaRutaKm),
      'avisosGpsKm': _controller(settings.avisosGpsKm),
      'avisosMeteorologicosRutaKm': _controller(
        settings.avisosMeteorologicosRutaKm,
      ),
      'rachasVientoKmh': _controller(settings.rachasVientoKmh),
      'nieveCmHora': _controller(settings.nieveCmHora),
      'visibilidadMetros': _controller(settings.visibilidadMetros),
      'temperaturaHieloCelsius': _controller(settings.temperaturaHieloCelsius),
      'probabilidadLluviaEngelante': _controller(
        settings.probabilidadLluviaEngelante,
      ),
      'precipitacionHieloMm': _controller(settings.precipitacionHieloMm),
      'mantenimientoIntervaloMeses': TextEditingController(
        text: settings.mantenimientoIntervaloMeses.toString(),
      ),
    };
  }

  TextEditingController _controller(double value) {
    return TextEditingController(text: value.toString());
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  double _value(String key) {
    return double.parse(_controllers[key]!.text.trim().replaceAll(',', '.'));
  }

  int _integerValue(String key) => _value(key).toInt();

  String? _validateValue(
    String? value, {
    bool signed = false,
    bool integer = false,
    double? minimum,
    double? maximum,
  }) {
    final number = double.tryParse((value ?? '').trim().replaceAll(',', '.'));
    if (number == null || !number.isFinite) {
      return 'Introduce un número válido.';
    }
    if (!signed && number < 0) {
      return 'El valor no puede ser negativo.';
    }
    if (minimum != null && number < minimum) {
      return 'El valor mínimo es ${minimum.toStringAsFixed(0)}.';
    }
    if (maximum != null && number > maximum) {
      return 'El máximo es ${maximum.toStringAsFixed(0)}.';
    }
    if (integer && number.truncateToDouble() != number) {
      return 'Introduce un número entero de meses.';
    }
    return null;
  }

  Future<void> _guardar() async {
    if (!_formKey.currentState!.validate()) return;

    final usuario = FirebaseAuth.instance.currentUser;
    if (usuario == null) {
      setState(() {
        _error = 'Inicia sesión para guardar la configuración.';
      });
      return;
    }

    final settings = AppSettings(
      gasolinerasRutaKm: _value('gasolinerasRutaKm'),
      parkingsListaRutaKm: _value('parkingsListaRutaKm'),
      parkingsMapaRutaKm: _value('parkingsMapaRutaKm'),
      avisosGpsKm: _value('avisosGpsKm'),
      avisosMeteorologicosRutaKm: _value('avisosMeteorologicosRutaKm'),
      rachasVientoKmh: _value('rachasVientoKmh'),
      nieveCmHora: _value('nieveCmHora'),
      visibilidadMetros: _value('visibilidadMetros'),
      temperaturaHieloCelsius: _value('temperaturaHieloCelsius'),
      probabilidadLluviaEngelante: _value('probabilidadLluviaEngelante'),
      precipitacionHieloMm: _value('precipitacionHieloMm'),
      mantenimientoIntervaloMeses: _integerValue('mantenimientoIntervaloMeses'),
    );

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(usuario.uid)
          .collection('configuracion')
          .doc('preferencias')
          .set(settings.toMap());

      if (!mounted) return;
      final onSaved = widget.onSaved;
      if (onSaved == null) {
        Navigator.of(context).pop(settings);
      } else {
        onSaved(settings);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo guardar la configuración: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Widget _campo({
    required String keyName,
    required String label,
    required String unit,
    required String help,
    bool signed = false,
    bool integer = false,
    double? minimum,
    double? maximum,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: _controllers[keyName],
        keyboardType: TextInputType.numberWithOptions(
          decimal: true,
          signed: signed,
        ),
        validator: (value) => _validateValue(
          value,
          signed: signed,
          integer: integer,
          minimum: minimum,
          maximum: maximum,
        ),
        decoration: InputDecoration(
          labelText: label,
          suffixText: unit,
          helperText: help,
          filled: true,
          fillColor: const Color(0xFFF3F6F9),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(9)),
        ),
      ),
    );
  }

  Widget _seccion(String titulo, List<Widget> campos) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      color: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              titulo,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: Color(0xFF07366D),
              ),
            ),
            const SizedBox(height: 14),
            ...campos,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFF2F5F8),
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Configuración',
              style: TextStyle(
                color: Color(0xFF07366D),
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Ajusta las distancias de búsqueda y los umbrales de los avisos. '
              'Los valores indicados son los predeterminados.',
              style: TextStyle(color: Colors.black54, height: 1.4),
            ),
            if (widget.loadError != null) ...[
              const SizedBox(height: 12),
              _mensaje(widget.loadError!, Colors.orange.shade900),
            ],
            const SizedBox(height: 16),
            _seccion('Distancias', [
              _campo(
                keyName: 'gasolinerasRutaKm',
                label: 'Gasolineras desde la ruta',
                unit: 'km',
                help: 'Predeterminado: 0,09 km (90 m).',
              ),
              _campo(
                keyName: 'parkingsListaRutaKm',
                label: 'Parkings en la lista',
                unit: 'km',
                help: 'Predeterminado: 1 km.',
              ),
              _campo(
                keyName: 'parkingsMapaRutaKm',
                label: 'Parkings en el mapa',
                unit: 'km',
                help: 'Predeterminado: 0,1 km (100 m).',
              ),
              _campo(
                keyName: 'avisosGpsKm',
                label: 'Avisos de conductores/DGT desde tu GPS',
                unit: 'km',
                help: 'Predeterminado: 5 km.',
              ),
              _campo(
                keyName: 'avisosMeteorologicosRutaKm',
                label: 'Avisos meteorológicos desde la ruta',
                unit: 'km',
                help: 'Predeterminado: 10 km.',
              ),
            ]),
            _seccion('Avisos meteorológicos', [
              _campo(
                keyName: 'rachasVientoKmh',
                label: 'Rachas para aviso de viento',
                unit: 'km/h',
                help: 'Se avisa a partir de este valor. Predeterminado: 70.',
              ),
              _campo(
                keyName: 'nieveCmHora',
                label: 'Nieve prevista',
                unit: 'cm/h',
                help: 'Se avisa a partir de este valor. Predeterminado: 0,1.',
              ),
              _campo(
                keyName: 'visibilidadMetros',
                label: 'Visibilidad reducida',
                unit: 'm',
                help:
                    'Se avisa por debajo de este valor. Predeterminado: 1000.',
              ),
              _campo(
                keyName: 'temperaturaHieloCelsius',
                label: 'Temperatura para riesgo de hielo',
                unit: '°C',
                help: 'Se avisa a esta temperatura o menos. Predeterminado: 1.',
                signed: true,
              ),
              _campo(
                keyName: 'probabilidadLluviaEngelante',
                label: 'Probabilidad de lluvia engelante',
                unit: '%',
                help: 'Predeterminado: 30%.',
                maximum: 100,
              ),
              _campo(
                keyName: 'precipitacionHieloMm',
                label: 'Precipitación para riesgo de hielo',
                unit: 'mm',
                help: 'Predeterminado: cualquier precipitación (> 0 mm).',
              ),
            ]),
            _seccion('Mantenimiento de camiones', [
              _campo(
                keyName: 'mantenimientoIntervaloMeses',
                label: 'Intervalo para próxima revisión',
                unit: 'meses',
                help: 'Predeterminado: 24 meses (2 años).',
                integer: true,
                minimum: 1,
              ),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 4),
              _mensaje(_error!, Colors.red.shade800),
            ],
            const SizedBox(height: 4),
            SizedBox(
              height: 50,
              child: ElevatedButton.icon(
                onPressed: _saving ? null : _guardar,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_outlined),
                label: Text(_saving ? 'Guardando...' : 'Guardar configuración'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0755A6),
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mensaje(String texto, Color color) {
    return Text(texto, style: TextStyle(color: color));
  }
}
