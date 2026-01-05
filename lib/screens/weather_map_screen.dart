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
        final past = radar['past'] as List;
        final nowcast = radar['nowcast'] as List;

        // Filter past frames to strictly last 1 hour
        final int now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        final oneHourAgo = now - 3600;

        var filteredPast = past
            .map((e) => MapFrame.fromJson(e, isPast: true))
            .where((frame) => frame.time >= oneHourAgo)
            .toList();

        var filteredNowcast = nowcast
            .map((e) => MapFrame.fromJson(e, isPast: false))
            .toList();

        // Combine and filter to approximate 15 minute intervals
        // RainViewer usually provides 10 min intervals for past, 5 for nowcast.
        // We will try to pick frames closest to 15 min steps.
        List<MapFrame> allFrames = [...filteredPast, ...filteredNowcast];
        List<MapFrame> sampledFrames = [];

        if (allFrames.isNotEmpty) {
          sampledFrames.add(allFrames.first);
          int lastTime = allFrames.first.time;

          for (int i = 1; i < allFrames.length; i++) {
            if (allFrames[i].time - lastTime >= 900) { // 900 seconds = 15 mins
              sampledFrames.add(allFrames[i]);
              lastTime = allFrames[i].time;
            }
          }
        } else {
           sampledFrames = allFrames;
        }

        setState(() {
          _frames = sampledFrames;
          // Start at the last "past" frame (current time roughly)
          _currentIndex = filteredPast.isNotEmpty ?
              sampledFrames.lastIndexWhere((f) => f.isPast) : 0;

          if (_currentIndex < 0) _currentIndex = 0;
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
          HapticFeedback.selectionClick();
        });
      });
    } else {
      _timer?.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final mapUrl = isDarkMode
        ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png'
        : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';

    return Scaffold(
      backgroundColor: Colors.black, // Fix white line on right side
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
                urlTemplate: mapUrl,
                subdomains: isDarkMode ? const ['a', 'b', 'c', 'd'] : const ['a', 'b', 'c'],
                userAgentPackageName: 'com.pranshulgg.weather_master_app',
              ),
              if (!_isLoading && _frames.isNotEmpty)
                TileLayer(
                  // Remove key to prevent hard rebuilds, enabling smoother transitions (if supported by cache)
                  // key: ValueKey(_frames[_currentIndex].path),
                  urlTemplate: '$_host${_frames[_currentIndex].path}/256/{z}/{x}/{y}/2/1_1.png',
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
                            max: (_frames.length - 1).toDouble(),
                            onChanged: (value) {
                              setState(() {
                                _currentIndex = value.toInt();
                                HapticFeedback.selectionClick();
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
