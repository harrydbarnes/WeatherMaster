import 'package:flutter_test/flutter_test.dart';
import 'package:weather_master_app/services/forecast_grid_service.dart';

void main() {
  test('ForecastGridService can be instantiated', () {
    final service = ForecastGridService();
    expect(service, isNotNull);
  });
}
