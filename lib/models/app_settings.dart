class AppSettings {
  final double gasolinerasRutaKm;
  final double parkingsListaRutaKm;
  final double parkingsMapaRutaKm;
  final double avisosGpsKm;
  final double avisosMeteorologicosRutaKm;
  final double rachasVientoKmh;
  final double nieveCmHora;
  final double visibilidadMetros;
  final double temperaturaHieloCelsius;
  final double probabilidadLluviaEngelante;
  final double precipitacionHieloMm;
  final int mantenimientoIntervaloMeses;

  const AppSettings({
    this.gasolinerasRutaKm = 0.09,
    this.parkingsListaRutaKm = 1,
    this.parkingsMapaRutaKm = 0.1,
    this.avisosGpsKm = 5,
    this.avisosMeteorologicosRutaKm = 10,
    this.rachasVientoKmh = 70,
    this.nieveCmHora = 0.1,
    this.visibilidadMetros = 1000,
    this.temperaturaHieloCelsius = 1,
    this.probabilidadLluviaEngelante = 30,
    this.precipitacionHieloMm = 0,
    this.mantenimientoIntervaloMeses = 24,
  });

  factory AppSettings.fromMap(Map<String, dynamic> map) {
    final defaults = const AppSettings();

    double read(
      String key,
      double defaultValue, {
      bool allowNegative = false,
      double? maximum,
    }) {
      final value = map[key];
      if (value == null) return defaultValue;
      if (value is num && value.toDouble().isFinite) {
        final number = value.toDouble();
        if ((allowNegative || number >= 0) &&
            (maximum == null || number <= maximum)) {
          return number;
        }
      }
      throw FormatException('El valor "$key" de la configuración no es válido.');
    }

    final intervalValue = map['mantenimientoIntervaloMeses'];
    final maintenanceIntervalMonths = intervalValue == null
        ? defaults.mantenimientoIntervaloMeses
        : intervalValue is int && intervalValue > 0
        ? intervalValue
        : throw const FormatException(
            'El intervalo de mantenimiento no es válido.',
          );

    return AppSettings(
      gasolinerasRutaKm: read('gasolinerasRutaKm', defaults.gasolinerasRutaKm),
      parkingsListaRutaKm: read(
        'parkingsListaRutaKm',
        defaults.parkingsListaRutaKm,
      ),
      parkingsMapaRutaKm: read(
        'parkingsMapaRutaKm',
        defaults.parkingsMapaRutaKm,
      ),
      avisosGpsKm: read('avisosGpsKm', defaults.avisosGpsKm),
      avisosMeteorologicosRutaKm: read(
        'avisosMeteorologicosRutaKm',
        defaults.avisosMeteorologicosRutaKm,
      ),
      rachasVientoKmh: read('rachasVientoKmh', defaults.rachasVientoKmh),
      nieveCmHora: read('nieveCmHora', defaults.nieveCmHora),
      visibilidadMetros: read('visibilidadMetros', defaults.visibilidadMetros),
      temperaturaHieloCelsius: read(
        'temperaturaHieloCelsius',
        defaults.temperaturaHieloCelsius,
        allowNegative: true,
      ),
      probabilidadLluviaEngelante: read(
        'probabilidadLluviaEngelante',
        defaults.probabilidadLluviaEngelante,
        maximum: 100,
      ),
      precipitacionHieloMm: read(
        'precipitacionHieloMm',
        defaults.precipitacionHieloMm,
      ),
      mantenimientoIntervaloMeses: maintenanceIntervalMonths,
    );
  }

  Map<String, dynamic> toMap() => {
    'gasolinerasRutaKm': gasolinerasRutaKm,
    'parkingsListaRutaKm': parkingsListaRutaKm,
    'parkingsMapaRutaKm': parkingsMapaRutaKm,
    'avisosGpsKm': avisosGpsKm,
    'avisosMeteorologicosRutaKm': avisosMeteorologicosRutaKm,
    'rachasVientoKmh': rachasVientoKmh,
    'nieveCmHora': nieveCmHora,
    'visibilidadMetros': visibilidadMetros,
    'temperaturaHieloCelsius': temperaturaHieloCelsius,
    'probabilidadLluviaEngelante': probabilidadLluviaEngelante,
    'precipitacionHieloMm': precipitacionHieloMm,
    'mantenimientoIntervaloMeses': mantenimientoIntervaloMeses,
  };
}
