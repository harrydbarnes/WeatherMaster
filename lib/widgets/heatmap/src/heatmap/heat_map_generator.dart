import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:weather_master_app/widgets/heatmap/flutter_map_heatmap.dart';
import 'transparent.dart';

class HeatMap {
  HeatMap(this.options, this.width, this.height, this.data) {
    _initColorPalette();
  }

  final HeatMapOptions options;
  final double width;
  final double height;
  final List<DataPoint> data;

  late ByteData _palette;
  final Completer<void> ready = Completer<void>();

  /// Base Shapes used to represent each point
  final Map<double, ui.Image> _baseShapes = {};

  Future<void> get onReady => ready.future;

  /// generates a 256 color palette used to colorize the heatmap
  _initColorPalette() async {
    List<double> stops = [];
    List<Color> colors = [];

    for (final entry in options.gradient.entries) {
      colors.add(entry.value);
      stops.add(entry.key);
    }

    Gradient colorGradient = LinearGradient(colors: colors, stops: stops);
    var paletteRect = const Rect.fromLTRB(0, 0, 256, 1);

    var shader = colorGradient.createShader(paletteRect,
        textDirection: TextDirection.ltr);

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, paletteRect);

    Paint palettePaint = Paint()..shader = shader;
    canvas.drawRect(paletteRect, palettePaint);
    final picture = recorder.endRecording();
    var image = await picture.toImage(256, 1);
    _palette = (await image.toByteData())!;
    ready.complete();
  }

  Future<ui.Image> _getBaseShape() async {
    final radius = options.radius;
    if (_baseShapes.containsKey(radius)) {
      return _baseShapes[radius]!;
    }

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final baseCirclePainter =
        AltBaseCirclePainter(radius: radius, blurFactor: options.blurFactor);
    Size size = Size.fromRadius(radius);
    baseCirclePainter.paint(canvas, size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(radius.round() * 2, radius.round() * 2);

    _baseShapes[radius] = image;
    return image;
  }

  _grayscaleHeatmap(ui.Image baseCircle) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    // Pass minOpacity and max (maxIntensity) to the painter
    final painter = GrayScaleHeatMapPainter(
        baseCircle: baseCircle,
        data: data,
        minOpacity: options.minOpacity,
        max: options.maxIntensity);

    painter.paint(
        canvas, Size(width + options.radius, height + options.radius));

    final picture = recorder.endRecording();
    final image = await picture.toImage(width.toInt(), height.toInt());
    return image;
  }

  Future<Uint8List> _colorize(ui.Image image) async {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final byteCount = byteData?.lengthInBytes;
    var transparentByteCount = 0;

    // Safety check for palette availability
    if (byteData == null) {
      return Uint8List(0);
    }

    for (var i = 0, len = byteData.lengthInBytes, j = 0; i < len; i += 4) {
      // GrayScaleHeatMapPainter writes the intensity to the Alpha channel.
      int sourceAlpha = byteData.getUint8(i + 3);

      // Use sourceAlpha as index into the palette (0-255)
      j = sourceAlpha * 4;

      if (j > 0 && sourceAlpha > 0) {
        // Read RGB from palette
        byteData.setUint8(i, _palette.getUint8(j));
        byteData.setUint8(i + 1, _palette.getUint8(j + 1));
        byteData.setUint8(i + 2, _palette.getUint8(j + 2));

        // Combine source alpha (intensity shape) with palette alpha (color opacity)
        // This ensures both the Gaussian falloff and the gradient opacity are respected.
        int paletteAlpha = _palette.getUint8(j + 3);
        int finalAlpha = (sourceAlpha * paletteAlpha) ~/ 255;

        byteData.setUint8(i + 3, finalAlpha);
      } else {
        transparentByteCount = transparentByteCount + 4;
      }
    }

    Uint8List bitmap;
    // for some reason transparency is not honored when rendering on web. by checking
    // all bytes are transparent we can render a single pixel transparent png instead
    if (transparentByteCount == byteCount) {
      bitmap = kTransparentImage;
    } else {
      bitmap = Bitmap.fromHeadless(
              image.width, image.height, byteData.buffer.asUint8List())
          .buildHeaded();
    }

    return bitmap;
  }

  Future<Uint8List> generate() async {
    await ready.future;

    // if there is no data then return a transparent image
    if (data.isEmpty) {
      return kTransparentImage;
    }
    // generate shape to be used for all points on the heatmap
    final baseShape = await _getBaseShape();

    final grayscale = await _grayscaleHeatmap(baseShape);

    final heatmapBytes = await _colorize(grayscale);

    return heatmapBytes;
  }
}
