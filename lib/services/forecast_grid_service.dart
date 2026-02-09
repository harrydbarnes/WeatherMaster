import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';

class WeightedLatLng {
  final LatLng point;
  final double intensity;

  WeightedLatLng(this.point, this.intensity);
}

class ForecastGridService {
  // Grid configuration
  static const int gridSize = 5; // 5x5 grid
  static const double gridSpacing = 0.08; // Roughly 8-9km spacing

  Future<Map<DateTime, List<WeightedLatLng>>> fetchPrecipitationGrid(
      double centerLat, double centerLon) async {
    final List<double> lats = [];
    final List<double> lons = [];

    // Generate grid coordinates
    final offset = (gridSize - 1) / 2;
    for (int i = 0; i < gridSize; i++) {
      for (int j = 0; j < gridSize; j++) {
        final lat = centerLat + (i - offset) * gridSpacing;
        final lon = centerLon + (j - offset) * gridSpacing;
        lats.add(lat);
        lons.add(lon);
      }
    }

    final latString = lats.join(',');
    final lonString = lons.join(',');

    final uri = Uri.parse('https://api.open-meteo.com/v1/forecast')
        .replace(queryParameters: {
      'latitude': latString,
      'longitude': lonString,
      'hourly': 'precipitation',
      'forecast_hours': '12', // Fetch next 12 hours
      'timezone': 'auto',
    });

    try {
      final response = await http.get(uri);
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final dynamic decoded = json.decode(response.body);
        final List<dynamic> data;

        if (decoded is List) {
          data = decoded;
        } else {
          data = [decoded];
        }

        final Map<DateTime, List<WeightedLatLng>> result = {};

        if (data.isNotEmpty) {
           // Initialize the map keys based on the first location's time
           final firstLoc = data[0];
           final times = (firstLoc['hourly']['time'] as List).cast<String>();

           for (var t in times) {
             result[DateTime.parse(t)] = [];
           }

           // Fill data
           for (int i = 0; i < data.length; i++) {
             final locationData = data[i];
             final lat = locationData['latitude'];
             final lon = locationData['longitude'];
             final hourly = locationData['hourly'];
             final precipList = hourly['precipitation'] as List;
             final precip = precipList.map((e) => (e as num).toDouble()).toList();
             final timeStrings = (hourly['time'] as List).cast<String>();

             for (int t = 0; t < timeStrings.length; t++) {
               final time = DateTime.parse(timeStrings[t]);
               final value = precip[t]; // mm

               if (result.containsKey(time)) {
                  result[time]!.add(WeightedLatLng(LatLng(lat, lon), value));
               }
             }
           }
        }
        return result;
      } else {
        throw Exception('Failed to fetch grid data: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching grid data: $e');
      return {};
    }
  }
}
