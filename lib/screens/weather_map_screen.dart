import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart'; // For HapticFeedback
import '../services/forecast_grid_service.dart';

class WeatherMapScreen extends StatefulWidget {
  final double lat;
  final double lon;

  const WeatherMapScreen({super.key, required this.lat, required this.lon});

  @override
  State<WeatherMapScreen> createState() => _WeatherMapScreenState();
}

class _WeatherMapScreenState extends State<WeatherMapScreen> {
  final ForecastGridService _service = ForecastGridService();
  Map<DateTime, List<WeightedLatLng>>? _data;
  List<DateTime> _timestamps = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  Timer? _timer;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    final data = await _service.fetchPrecipitationGrid(widget.lat, widget.lon);
    if (mounted) {
      setState(() {
        _data = data;
        _timestamps = data.keys.toList()..sort();
        _isLoading = false;
      });
    }
  }

  void _togglePlay() {
    setState(() {
      _isPlaying = !_isPlaying;
    });

    if (_isPlaying) {
      _timer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
        if (_timestamps.isEmpty) return;
        setState(() {
          _currentIndex = (_currentIndex + 1) % _timestamps.length;
        });
      });
    } else {
      _timer?.cancel();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Color _getColorForIntensity(double intensity) {
    // Intensity in mm
    if (intensity < 0.1) return Colors.transparent;
    if (intensity < 0.5) return Colors.lightBlue.withValues(alpha: 0.3);
    if (intensity < 2.0) return Colors.blue.withValues(alpha: 0.4);
    if (intensity < 5.0) return Colors.indigo.withValues(alpha: 0.5);
    if (intensity < 10.0) return Colors.purple.withValues(alpha: 0.6);
    return Colors.red.withValues(alpha: 0.7);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final currentTime =
        _timestamps.isNotEmpty ? _timestamps[_currentIndex] : DateTime.now();
    final currentData = _data?[currentTime] ?? [];

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Container(
             padding: const EdgeInsets.all(8),
             decoration: BoxDecoration(
               color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
               shape: BoxShape.circle,
             ),
             child: const Icon(Icons.arrow_back),
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: LatLng(widget.lat, widget.lon),
              initialZoom: 9.0,
            ),
            children: [
              TileLayer(
                urlTemplate: isDark
                    ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                    : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c', 'd'],
                userAgentPackageName: 'com.pranshulgg.weather_master_app',
              ),
              CircleLayer(
                circles: currentData.map((p) {
                  return CircleMarker(
                    point: p.point,
                    color: _getColorForIntensity(p.intensity),
                    radius: 6000, // ~6km radius for ~8km spacing overlap
                    useRadiusInMeter: true,
                    borderStrokeWidth: 0,
                  );
                }).toList(),
              ),
              MarkerLayer(
                markers: [
                  Marker(
                    point: LatLng(widget.lat, widget.lon),
                    width: 20,
                    height: 20,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.red,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (_isLoading)
            const Center(child: CircularProgressIndicator())
          else if (_timestamps.isNotEmpty)
            Positioned(
              left: 16,
              right: 16,
              bottom: 32,
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                     BoxShadow(
                       color: Colors.black.withValues(alpha: 0.1),
                       blurRadius: 10,
                       offset: const Offset(0, 4),
                     ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          DateFormat('HH:mm').format(currentTime),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        Text(
                           currentTime.day == DateTime.now().day ? "today".tr() : DateFormat('MMM d').format(currentTime),
                           style: TextStyle(
                             color: Theme.of(context).colorScheme.onSurfaceVariant,
                           ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        IconButton(
                          icon: Icon(_isPlaying ? Icons.pause : Icons.play_arrow),
                          onPressed: _togglePlay,
                          color: Theme.of(context).colorScheme.primary,
                          iconSize: 32,
                        ),
                        Expanded(
                          child: Slider(
                            value: _currentIndex.toDouble(),
                            min: 0,
                            max: (_timestamps.length - 1).toDouble(),
                            divisions: _timestamps.length > 1 ? _timestamps.length - 1 : 1,
                            onChanged: (value) {
                              setState(() {
                                _currentIndex = value.toInt();
                                _isPlaying = false; // Stop auto-play on scrub
                                _timer?.cancel();
                              });
                              HapticFeedback.selectionClick();
                            },
                          ),
                        ),
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
