import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:easy_localization/easy_localization.dart';
import '../screens/weather_map_screen.dart';

class MapTile extends StatelessWidget {
  final double lat;
  final double lon;
  final int selectedContainerBgIndex;

  const MapTile({
    super.key,
    required this.lat,
    required this.lon,
    required this.selectedContainerBgIndex,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.7),
      child: Material(
        elevation: 1,
        borderRadius: BorderRadius.circular(20),
        color: Color(selectedContainerBgIndex),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => WeatherMapScreen(lat: lat, lon: lon),
              ),
            );
          },
          child: SizedBox(
            height: 200,
            child: Stack(
              children: [
                FlutterMap(
                  options: MapOptions(
                    initialCenter: LatLng(lat, lon),
                    initialZoom: 9.0,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.none,
                    ),
                    backgroundColor: Color(selectedContainerBgIndex), // Match background to hide loading
                  ),
                  children: [
                    TileLayer(
                      urlTemplate: isDark
                          ? 'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png'
                          : 'https://{s}.basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                      subdomains: const ['a', 'b', 'c', 'd'],
                      userAgentPackageName: 'com.pranshulgg.weather_master_app',
                    ),
                    // Optional: Add a subtle gradient overlay to match the "vibe"
                    TileLayer(
                        urlTemplate: '', // Placeholder if we wanted weather overlay here too
                    ),
                    MarkerLayer(
                      markers: [
                        Marker(
                          point: LatLng(lat, lon),
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
                Positioned(
                  top: 16,
                  left: 16,
                  child: Container(
                     padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                     decoration: BoxDecoration(
                       color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
                       borderRadius: BorderRadius.circular(20),
                     ),
                     child: Row(
                       mainAxisSize: MainAxisSize.min,
                       children: [
                         Icon(Icons.map, size: 16, color: Theme.of(context).colorScheme.onSurface),
                         const SizedBox(width: 8),
                         Text(
                           "weather_map".tr(),
                           style: TextStyle(
                             fontWeight: FontWeight.w600,
                             color: Theme.of(context).colorScheme.onSurface,
                           ),
                         ),
                       ],
                     ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
