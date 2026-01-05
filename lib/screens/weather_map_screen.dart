import 'dart:async';
import 'dart:convert';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:http/http.dart' as http;
import 'package:material_symbols_icons/material_symbols_icons.dart';
import 'package:flutter/services.dart';

class WeatherMapScreen extends StatefulWidget {
  final double lat;
  final double lon;

  const WeatherMapScreen({super.key, required this.lat, required this.lon});

  @override
  State<WeatherMapScreen> createState() => _WeatherMapScreenState();
}

class _WeatherMapScreenState extends State<WeatherMapScreen> {
  List<MapFrame> _frames = [];
  int _currentIndex = 0;
  bool _isPlaying = false;
  Timer? _timer;
  bool _isLoading = true;
  String _host = '';

  @override
  void initState() {
    super.initState();
    _fetchRainViewerData();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchRainViewerData() async {
    try {
      final response = await http.get(Uri.parse('https://api.rainviewer.com/public/weather-maps.json'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _host = data['host'];
        final radar = data['radar'];
        var past = radar['past'] as List;
        var nowcast = radar['nowcast'] as List;

        // Filter: max 1 hour past
        // Past array is sorted by time. Last element is most recent past.
        // We want frames within [now - 1h, now].
        // But simply taking the last 60 minutes is easier if intervals are known.
        // RainViewer usually has 10 min intervals. So last 6 frames.
        // But we also want 15 min intervals.
        // Let's grab all data first, then resample.

        List<MapFrame> allFrames = [
           ...past.map((e) => MapFrame.fromJson(e, isPast: true)),
           ...nowcast.map((e) => MapFrame.fromJson(e, isPast: false)),
        ];

        // Current time estimation (last past frame)
        int currentTime = past.last['time'];

        // Filter: Keep frames from (currentTime - 1 hour) to (currentTime + 12 hours) to match "up to 12 hours"
        int startTime = currentTime - 3600;
        int endTime = currentTime + (12 * 3600);

        // Filter by time range
        List<MapFrame> filtered = allFrames.where((f) => f.time >= startTime && f.time <= endTime).toList();

        // Resample to ~15 min intervals
        // RainViewer standard is 10 mins (past) and 10 mins (nowcast).
        // 0, 10, 20, 30, 40, 50, 60
        // We want 0, 15, 30, 45...
        // We can pick frames closest to 15 min marks relative to start.

        List<MapFrame> resampled = [];
        if (filtered.isNotEmpty) {
           resampled.add(filtered.first);
           for (int i = 1; i < filtered.length; i++) {
             // If difference from last added frame is >= 15 mins (900 sec), add it.
             // Or better, align to 15 min clock boundaries if possible, but data is fixed.
             if (filtered[i].time - resampled.last.time >= 900) {
               resampled.add(filtered[i]);
             }
           }
        }

        // Limit total duration if needed, but the loop above roughly handles it.
        // Ensure we don't exceed 8 hours roughly (32 frames).

        setState(() {
          _frames = resampled;

          // Find the frame closest to "now" to start there
          // The last 'isPast' frame or the one closest to currentTime
           int initialIndex = 0;
           for(int i=0; i<_frames.length; i++){
             if(_frames[i].time <= currentTime) {
               initialIndex = i;
             }
           }
          _currentIndex = initialIndex;
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load weather maps');
      }
    } catch (e) {
      debugPrint('Error fetching RainViewer data: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
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
          if (_currentIndex < _frames.length - 1) {
            _currentIndex++;
          } else {
            _currentIndex = 0;
          }
        });
      });
    } else {
      _timer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

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
      ),
      body: Stack(
        children: [
          FlutterMap(
            options: MapOptions(
              initialCenter: LatLng(widget.lat, widget.lon),
              initialZoom: 8.0,
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: isDarkMode
                    ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: isDarkMode ? ['a', 'b', 'c'] : ['a', 'b', 'c'], // OSM doesn't strictly need it but fine
                userAgentPackageName: 'com.pranshulgg.weather_master_app',
              ),
              if (!_isLoading && _frames.isNotEmpty)
                TileLayer(
                  // Removing key to prevent full rebuild flicker, allowing internal tile updates
                  urlTemplate: '$_host${_frames[_currentIndex].path}/256/{z}/{x}/{y}/2/1_1.png',
                  userAgentPackageName: 'com.pranshulgg.weather_master_app',
                  tileProvider: NetworkTileProvider(), // Ensure standard provider
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
          if (!_isLoading && _frames.isNotEmpty)
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
                          DateFormat.jm().format(DateTime.fromMillisecondsSinceEpoch(_frames[_currentIndex].time * 1000)),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          _frames[_currentIndex].isPast ? "past".tr() : "forecast".tr(),
                          style: TextStyle(
                            color: _frames[_currentIndex].isPast ? Colors.grey : Colors.blue,
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
                            max: _frames.isEmpty ? 0 : (_frames.length - 1).toDouble(),
                            divisions: _frames.isEmpty ? 1 : _frames.length - 1,
                            onChanged: _frames.isEmpty ? null : (value) {
                              if (value.toInt() != _currentIndex) {
                                HapticFeedback.selectionClick();
                              }
                              setState(() {
                                _currentIndex = value.toInt();
                                if (_isPlaying) {
                                  _togglePlay(); // Pause if user drags
                                }
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
                                 Color(0x00000000), // Transparent
                                 Color(0xFF83F2AA), // Light Rain
                                 Color(0xFF3569A6), // Heavy Rain
                                 Color(0xFFB13158), // Storm
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

class MapFrame {
  final int time;
  final String path;
  final bool isPast;

  MapFrame({required this.time, required this.path, required this.isPast});

  factory MapFrame.fromJson(Map<String, dynamic> json, {required bool isPast}) {
    return MapFrame(
      time: json['time'],
      path: json['path'],
      isPast: isPast,
    );
  }
}
