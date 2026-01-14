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
      try {
        bounds = _mapController.camera.visibleBounds;
        // Basic check if bounds are extremely small or invalid (0 area)
        if (bounds.west == bounds.east && bounds.north == bounds.south) {
          throw Exception("Invalid bounds");
        }
      } catch (e) {
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
      final filteredFrames = { for (var k in filteredKeys) k: fetchedFrames[k]! };

      if (mounted) {
        setState(() {
          _frames = filteredFrames;
          _sortedTimestamps = filteredKeys;

          // Set index to start near "now"
          int bestIndex = 0;
          if (_sortedTimestamps.isNotEmpty) {
            final closestTimestamp = _sortedTimestamps.reduce((a, b) => (a - now).abs() < (b - now).abs() ? a : b);
            bestIndex = _sortedTimestamps.indexOf(closestTimestamp);
          }
          _currentIndex = bestIndex;

          // Debug logging
          double maxPrecip = 0.0;
          if (_sortedTimestamps.isNotEmpty && _frames.isNotEmpty && _frames.containsKey(_sortedTimestamps[bestIndex])) {
             var frame = _frames[_sortedTimestamps[bestIndex]]!;
             if (frame.isNotEmpty) {
               maxPrecip = frame.values.reduce((curr, next) => curr > next ? curr : next);
             }
             debugPrint("Forecast loaded: ${_sortedTimestamps.length} frames. Max precip at index $bestIndex: $maxPrecip");
          } else {
             debugPrint("Forecast loaded: ${_sortedTimestamps.length} frames. (Empty or invalid state)");
          }

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
                    radius: 150.0, // Increased radius for better coverage
                    blurFactor: 1.0, // Use full radius for the gradient (removes "dot" effect)
                    minOpacity: 0.1, // Keep base opacity low to allow smooth blending
                    maxIntensity: 10.0, // Cap at 10mm for full range
                    scaleIntensityByZoom: false, // Disable density scaling, use raw values
                    gradient: {
                      0.1: Colors.lightGreen,
                      0.4: Colors.green,
                      0.6: Colors.yellow,
                      0.8: Colors.orange,
                      1.0: Colors.purple,
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
          if (!_isLoading && _sortedTimestamps.isNotEmpty) ...[
            // Legend Pill
            Positioned(
              bottom: 180, // Position above the card
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E), // Dark background
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text("Light", style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                    const SizedBox(width: 8),
                    Container(
                      width: 100,
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: const LinearGradient(
                          colors: [
                            Colors.lightGreen,
                            Colors.green,
                            Colors.yellow,
                            Colors.orange,
                            Colors.purple,
                            Colors.indigo
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text("Heavy", style: TextStyle(color: Colors.grey[400], fontSize: 12)),
                    const SizedBox(width: 8),
                    const Icon(Symbols.keyboard_arrow_up, color: Colors.grey, size: 16),
                  ],
                ),
              ),
            ),

            // Floating Control Card
            Positioned(
              bottom: 30,
              left: 16,
              right: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                decoration: BoxDecoration(
                  color: const Color(0xFF251A15), // Dark brown/black shade
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.5),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Top Row: Time and Play Button
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        // Time Display
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text(
                              DateFormat('h:mm').format(DateTime.fromMillisecondsSinceEpoch(_sortedTimestamps[_currentIndex] * 1000)),
                              style: const TextStyle(
                                fontSize: 36,
                                fontWeight: FontWeight.w400,
                                color: Colors.white, // Color(0xFFE0E0E0),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              DateFormat('a').format(DateTime.fromMillisecondsSinceEpoch(_sortedTimestamps[_currentIndex] * 1000)).toLowerCase(),
                              style: const TextStyle(
                                fontSize: 18,
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                        // Play Button
                        GestureDetector(
                          onTap: _togglePlay,
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF8A80), // Light coral/red accent
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.2),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Icon(
                              _isPlaying ? Symbols.pause : Symbols.play_arrow,
                              color: Colors.black, // Dark icon on light button
                              size: 28,
                              fill: 1.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    // Timeline Ruler
                    LayoutBuilder(
                      builder: (context, constraints) {
                        return Stack(
                          alignment: Alignment.bottomCenter,
                          clipBehavior: Clip.none,
                          children: [
                            // Ticks
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: List.generate(_sortedTimestamps.length, (index) {
                                final date = DateTime.fromMillisecondsSinceEpoch(_sortedTimestamps[index] * 1000);
                                final isHour = date.minute == 0;
                                final isQuarter = date.minute % 15 == 0; // Assuming 15 min intervals

                                // Show label for hours only?
                                // If too many points, we might need to skip ticks.
                                // 12 hours * 4 = 48 points.
                                // Screen width ~350px. 350/48 = 7px per tick. Tight but okay.

                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                     Container(
                                      width: 1, // Thin ticks
                                      height: isHour ? 16 : 8,
                                      color: Colors.grey[600],
                                    ),
                                    if (isHour) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        DateFormat('h a').format(date).toLowerCase(),
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Colors.grey[600]
                                        ),
                                      ),
                                    ] else if (isHour) // Spacer for alignment if needed
                                       const SizedBox(height: 14),
                                  ],
                                );
                              }),
                            ),
                            // The actual Slider (invisible track)
                            SliderTheme(
                              data: SliderThemeData(
                                trackHeight: 0,
                                overlayShape: SliderComponentShape.noOverlay,
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6, elevation: 0),
                                thumbColor: const Color(0xFFFF8A80), // Match play button
                                activeTrackColor: Colors.transparent,
                                inactiveTrackColor: Colors.transparent,
                              ),
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
                            // Current Position Indicator (Red Line) - Optional if thumb is enough
                            // The thumb acts as the indicator.
                          ],
                        );
                      }
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
