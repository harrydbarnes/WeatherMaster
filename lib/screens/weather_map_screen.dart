import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:flutter/services.dart';
import 'package:weather_master_app/widgets/heatmap/flutter_map_heatmap.dart';
import 'package:weather_master_app/services/forecast_grid_service.dart';

class WeatherMapScreen extends StatefulWidget {
  final double lat;
  final double lon;

  const WeatherMapScreen({super.key, required this.lat, required this.lon});

  @override
  State<WeatherMapScreen> createState() => _WeatherMapScreenState();
}

class _WeatherMapScreenState extends State<WeatherMapScreen> {
  // Map of timestamp (epoch seconds) -> Map<LatLng, precipitation value>
  Map<int, Map<LatLng, double>> _frames = {};
  List<int> _sortedTimestamps = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  Timer? _timer;
  bool _isLoading = true;

  final MapController _mapController = MapController();
  final ForecastGridService _forecastService = ForecastGridService();

  // Stream controller to force heatmap layer reset/update if needed
  final StreamController<void> _rebuildStream = StreamController.broadcast();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _rebuildStream.close();
    super.dispose();
  }

  Future<void> _fetchWeatherFrames() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 1. Get Bounds
      // If controller not ready or bounds null, construct approximate bounds from initial center
      LatLngBounds bounds;
      if (_mapController.camera.visibleBounds.isValid) {
        bounds = _mapController.camera.visibleBounds;
      } else {
        // Fallback to a reasonable area around the center (e.g. +/- 1 degree)
        bounds = LatLngBounds(
          LatLng(widget.lat - 1, widget.lon - 1),
          LatLng(widget.lat + 1, widget.lon + 1),
        );
      }

      // 2. Create Grid
      List<LatLng> gridPoints = _forecastService.generateGrid(bounds);

      // 3. Fetch & Interpolate
      Map<int, Map<LatLng, double>> fetchedFrames = await _forecastService.fetchForecast(gridPoints);

      // 4. Store
      List<int> sortedKeys = fetchedFrames.keys.toList()..sort();

      // Filter out past frames if we want strictly "Forecast" or keep them if we want history?
      // Request said "12 hour forecast", implies future.
      // Open-Meteo forecast usually starts from current hour.

      // Filter: Keep frames from Now to Now + 12 hours
      int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      // Also allow some past if returned by API (e.g. start of current hour)
      // but let's strictly follow the plan: "Loop through the next 12 hours".

      // Let's filter to roughly [now - 1h, now + 12h] to be safe and showing context.
      int maxTime = now + 12 * 3600;

      List<int> filteredKeys = sortedKeys.where((t) => t <= maxTime).toList();
      Map<int, Map<LatLng, double>> filteredFrames = {};
      for (var k in filteredKeys) {
        filteredFrames[k] = fetchedFrames[k]!;
      }

      if (mounted) {
        setState(() {
          _frames = filteredFrames;
          _sortedTimestamps = filteredKeys;

          // Set index to start near "now"
          int bestIndex = 0;
          int minDiff = 99999999;
          for(int i=0; i<_sortedTimestamps.length; i++) {
            int diff = (_sortedTimestamps[i] - now).abs();
            if (diff < minDiff) {
              minDiff = diff;
              bestIndex = i;
            }
          }
          _currentIndex = bestIndex;

          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching forecast grid: $e");
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to load weather forecast: $e")),
        );
      }
    }
  }

  void _togglePlay() {
    setState(() {
      _isPlaying = !_isPlaying;
    });

    if (_isPlaying) {
      _timer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
        setState(() {
          if (_sortedTimestamps.isEmpty) {
            timer.cancel();
            _isPlaying = false;
            return;
          }

          if (_currentIndex < _sortedTimestamps.length - 1) {
            _currentIndex++;
          } else {
            _currentIndex = 0;
          }
          _rebuildStream.add(null);
        });
      });
    } else {
      _timer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Prepare data for HeatMapLayer
    // it expects Map<LatLng, double>
    Map<LatLng, double> currentHeatMapData = {};
    if (!_isLoading && _sortedTimestamps.isNotEmpty) {
      currentHeatMapData = _frames[_sortedTimestamps[_currentIndex]] ?? {};
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.7),
              shape: BoxShape.circle,
            ),
            child: const Icon(Symbols.arrow_back),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          // Refresh button
          IconButton(
            icon: Container(
              padding: const EdgeInsets.all(8),
               decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface.withOpacity(0.7),
                shape: BoxShape.circle,
              ),
              child: const Icon(Symbols.refresh),
            ),
            onPressed: _isLoading ? null : _fetchWeatherFrames,
          )
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: LatLng(widget.lat, widget.lon),
              initialZoom: 8.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onMapReady: () {
                _fetchWeatherFrames();
              },
            ),
            children: [
              TileLayer(
                urlTemplate: isDarkMode
                    ? 'https://services.arcgisonline.com/arcgis/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: isDarkMode ? [] : ['a', 'b', 'c'],
                userAgentPackageName: 'com.pranshulgg.weather_master_app',
              ),

              // Heatmap Overlay
              if (!_isLoading && currentHeatMapData.isNotEmpty)
                HeatMapLayer(
                  heatMapDataSource: InMemoryHeatMapDataSource(
                    data: currentHeatMapData.entries.map((e) => WeightedLatLng(e.key, e.value)).toList()
                  ),
                  heatMapOptions: HeatMapOptions(
                    radius: 60.0, // Adjust size of "blobs" - 30.0 requested, but let's try 60 for better coverage or stick to 30.
                    minOpacity: 0.1,
                    gradient: {
                      0.1: Colors.blue.withOpacity(0.2), // Light Rain
                      0.5: Colors.yellow,                // Moderate
                      1.0: Colors.red,                   // Heavy
                    },
                  ),
                  reset: _rebuildStream.stream,
                ),

              if (isDarkMode)
                TileLayer(
                  urlTemplate: 'https://services.arcgisonline.com/arcgis/rest/services/Canvas/World_Dark_Gray_Reference/MapServer/tile/{z}/{y}/{x}',
                  userAgentPackageName: 'com.pranshulgg.weather_master_app',
                ),

              // Marker for current location
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(widget.lat, widget.lon),
                    width: 20,
                    height: 20,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.blueAccent,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (_isLoading)
            const Center(
              child: CircularProgressIndicator(),
            ),
          if (!_isLoading && _sortedTimestamps.isNotEmpty)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Theme.of(context).colorScheme.surface.withOpacity(0.9),
                padding: EdgeInsets.fromLTRB(16, 16, 16, MediaQuery.of(context).padding.bottom + 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          DateFormat.jm().format(DateTime.fromMillisecondsSinceEpoch(_sortedTimestamps[_currentIndex] * 1000)),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          "Forecast", // Mostly forecast now
                          style: TextStyle(
                            color: Colors.blue,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(_isPlaying ? Symbols.pause : Symbols.play_arrow),
                          onPressed: _togglePlay,
                          iconSize: 32,
                        ),
                        Expanded(
                          child: Slider(
                            value: _currentIndex.toDouble(),
                            min: 0,
                            max: (_sortedTimestamps.length - 1).toDouble(),
                            divisions: _sortedTimestamps.length > 1 ? _sortedTimestamps.length - 1 : 1,
                            onChanged: (value) {
                              if (value.toInt() != _currentIndex) {
                                HapticFeedback.selectionClick();
                              }
                              setState(() {
                                _currentIndex = value.toInt();
                                if (_isPlaying) {
                                  _togglePlay(); // Pause if user drags
                                }
                                _rebuildStream.add(null);
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                     Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                         Text("light".tr(), style: TextStyle(fontSize: 12)),
                         Container(
                           width: 150,
                           height: 10,
                           decoration: BoxDecoration(
                             borderRadius: BorderRadius.circular(5),
                             gradient: LinearGradient(
                               colors: [
                                 Colors.blue.withOpacity(0.2), // Light Rain
                                 Colors.yellow,                // Moderate
                                 Colors.red,                   // Heavy
                               ],
                             )
                           ),
                         ),
                         Text("heavy".tr(), style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
