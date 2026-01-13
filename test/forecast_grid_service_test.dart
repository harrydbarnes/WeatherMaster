import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:weather_master_app/services/forecast_grid_service.dart';

void main() {
  group('ForecastGridService', () {
    final service = ForecastGridService();

    test('generateGrid returns correct number of points for 15x15 grid', () {
      final bounds = LatLngBounds(
        const LatLng(0, 0),
        const LatLng(10, 10),
      );

      final grid = service.generateGrid(bounds);

      // 15 * 15 = 225 points
      expect(grid.length, 225);

      // Verify corners
      expect(grid.first.latitude, 0.0); // South
      expect(grid.first.longitude, 0.0); // West

      // Note: loop order in service is i (lat) then j (lon) or vice versa?
      // Service code:
      // for (int i = 0; i < steps; i++) { // lat
      //   for (int j = 0; j < steps; j++) { // lon
      //     points.add(LatLng(minLat + i * latStep, minLon + j * lonStep));
      //   }
      // }
      // Last point should be roughly (10, 10)
      expect(grid.last.latitude, closeTo(10.0, 0.0001));
      expect(grid.last.longitude, closeTo(10.0, 0.0001));
    });
  });
}
