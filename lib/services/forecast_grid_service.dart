import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ForecastGridService {

  /// Generates a grid of points within the given bounds.
  /// returns a list of approximately 400 points (20x20).
  List<LatLng> generateGrid(LatLngBounds bounds) {
    // Get corners
    double minLat = bounds.south;
    double maxLat = bounds.north;
    double minLon = bounds.west;
    double maxLon = bounds.east;

    // Handle antimeridian crossing if necessary (not fully robust for global wrap, but sufficient for local views)
    if (minLon > maxLon) {
      // Very rough handling: if it wraps, we might just look at one side or split logic.
      // For now, assume non-wrapping or local region.
    }

    // Determine step size to get roughly 20x20 grid (400 points)
    // Reduced from 25x25 to ensure URL length stays within safe limits while maintaining coverage
    int steps = 20;
    double latStep = (maxLat - minLat) / (steps - 1);
    double lonStep = (maxLon - minLon) / (steps - 1);

    List<LatLng> points = [];
    for (int i = 0; i < steps; i++) {
      for (int j = 0; j < steps; j++) {
        points.add(LatLng(minLat + i * latStep, minLon + j * lonStep));
      }
    }
    return points;
  }

  /// Fetches precipitation forecast for the given points.
  /// Returns a map of timestamps (seconds since epoch) to a list of WeightedLatLng.
  /// The list of WeightedLatLng represents the grid with precipitation values for that time.
  Future<Map<int, Map<LatLng, double>>> fetchForecast(List<LatLng> gridPoints) async {
    if (gridPoints.isEmpty) return {};

    // Prepare URL parameters
    // Open-Meteo takes comma-separated lists for lat and lon
    String lats = gridPoints.map((p) => p.latitude.toStringAsFixed(4)).join(',');
    String lons = gridPoints.map((p) => p.longitude.toStringAsFixed(4)).join(',');

    final uri = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$lats&longitude=$lons&hourly=precipitation&forecast_days=2');

    final response = await http.get(uri);

    if (response.statusCode != 200) {
      throw Exception('Failed to fetch forecast data: ${response.statusCode}');
    }

    final data = json.decode(response.body);

    // Open-Meteo returns a list of results if multiple coordinates are provided?
    // Wait, per docs: "If multiple coordinates are requested, the response is an array of objects."
    // Let's verify this structure.
    // If I pass multiple lat/lon, do I get a list or a single object with arrays?
    // Docs say: "You can specify multiple locations by providing a list of latitudes and longitudes."
    // "The response will be a list of JSON objects."

    // However, if I use the format above, the output is indeed a list of JSON objects if multiple points.

    List<dynamic> locationsData;
    if (data is List) {
      locationsData = data;
    } else {
      // If single point, it returns just the object.
      locationsData = [data];
    }

    if (locationsData.length != gridPoints.length) {
       // Mismatch in response length vs requested points
       // This might happen if API handles it differently.
       // For now assume 1-to-1 mapping.
    }

    // Process data to organize by Time -> (Location -> Value)
    // We want to interpolate to 15-min intervals.

    // 1. Extract hourly data for each point
    // structure: locationsData[i]['hourly']['time'] (list of strings)
    // structure: locationsData[i]['hourly']['precipitation'] (list of doubles)

    Map<int, Map<LatLng, double>> hourlyFrames = {};

    // Assume all locations return same time steps
    List<dynamic> timeStrings = locationsData[0]['hourly']['time'];
    // Open-Meteo returns time in ISO8601 format without 'Z' (e.g. "2024-01-01T00:00") but it is UTC by default
    List<int> timestamps = timeStrings.map((t) => DateTime.parse("${t}Z").millisecondsSinceEpoch ~/ 1000).toList();

    for (int tIndex = 0; tIndex < timestamps.length; tIndex++) {
      int time = timestamps[tIndex];
      Map<LatLng, double> frameData = {};

      for (int i = 0; i < locationsData.length; i++) {
        // Safe access
        var precipList = locationsData[i]['hourly']['precipitation'];
        double precip = 0.0;
        if (precipList != null && tIndex < precipList.length) {
          var val = precipList[tIndex];
          if (val != null) {
            precip = (val as num).toDouble();
          }
        }
        frameData[gridPoints[i]] = precip;
      }
      hourlyFrames[time] = frameData;
    }

    // 2. Interpolate to 15-min intervals
    // We want 0, 15, 30, 45 mins.
    // hourlyFrames has data at :00.

    Map<int, Map<LatLng, double>> interpolatedFrames = {};

    for (int tIndex = 0; tIndex < timestamps.length - 1; tIndex++) {
      int t0 = timestamps[tIndex];
      int t1 = timestamps[tIndex + 1];

      // We assume t1 - t0 is 3600 seconds (1 hour)

      var frame0 = hourlyFrames[t0]!;
      var frame1 = hourlyFrames[t1]!;

      // 0 min (Original)
      interpolatedFrames[t0] = frame0;

      // 15 min (0.25)
      interpolatedFrames[t0 + 900] = _interpolateFrame(frame0, frame1, 0.25, gridPoints);

      // 30 min (0.50)
      interpolatedFrames[t0 + 1800] = _interpolateFrame(frame0, frame1, 0.50, gridPoints);

      // 45 min (0.75)
      interpolatedFrames[t0 + 2700] = _interpolateFrame(frame0, frame1, 0.75, gridPoints);
    }

    // Add the very last hour if needed, or just stop at tIndex < length - 1
    // We probably have enough.

    return interpolatedFrames;
  }

  Map<LatLng, double> _interpolateFrame(
      Map<LatLng, double> start,
      Map<LatLng, double> end,
      double factor,
      List<LatLng> points) {

    Map<LatLng, double> result = {};
    for (var point in points) {
      double v0 = start[point] ?? 0.0;
      double v1 = end[point] ?? 0.0;
      double vInterp = v0 + (v1 - v0) * factor;
      result[point] = vInterp;
    }
    return result;
  }
}
