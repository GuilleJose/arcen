import 'package:arcen/models/app_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('usa por defecto las distancias y umbrales actuales', () {
    const settings = AppSettings();

    expect(settings.gasolinerasRutaKm, 0.09);
    expect(settings.parkingsListaRutaKm, 1);
    expect(settings.parkingsMapaRutaKm, 0.1);
    expect(settings.avisosGpsKm, 5);
    expect(settings.avisosMeteorologicosRutaKm, 10);
    expect(settings.rachasVientoKmh, 70);
    expect(settings.nieveCmHora, 0.1);
    expect(settings.visibilidadMetros, 1000);
    expect(settings.temperaturaHieloCelsius, 1);
    expect(settings.probabilidadLluviaEngelante, 30);
    expect(settings.precipitacionHieloMm, 0);
    expect(settings.mantenimientoIntervaloMeses, 24);
  });

  test('serializa y restaura la configuración personalizada', () {
    const settings = AppSettings(
      gasolinerasRutaKm: 2,
      parkingsListaRutaKm: 3,
      parkingsMapaRutaKm: 0.4,
      avisosGpsKm: 7,
      avisosMeteorologicosRutaKm: 12,
      rachasVientoKmh: 80,
      nieveCmHora: 0.5,
      visibilidadMetros: 700,
      temperaturaHieloCelsius: -2,
      probabilidadLluviaEngelante: 45,
      precipitacionHieloMm: 0.2,
      mantenimientoIntervaloMeses: 36,
    );

    expect(AppSettings.fromMap(settings.toMap()).toMap(), settings.toMap());
  });

  test('rechaza valores persistidos fuera de rango', () {
    expect(
      () => AppSettings.fromMap({'gasolinerasRutaKm': -1}),
      throwsFormatException,
    );
    expect(
      () => AppSettings.fromMap({'probabilidadLluviaEngelante': 101}),
      throwsFormatException,
    );
    expect(
      () => AppSettings.fromMap({'mantenimientoIntervaloMeses': 0}),
      throwsFormatException,
    );
  });
}
