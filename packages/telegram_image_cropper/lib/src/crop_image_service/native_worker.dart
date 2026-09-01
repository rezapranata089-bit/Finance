import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

Future<Uint8List> cropImagePlatformSpecific({
  required Uint8List imageBytes,
  required int imageWidth,
  required int imageHeight,
  required int cropLeft,
  required int cropTop,
  required int cropWidth,
  required int cropHeight,
}) async {
  return compute(
    _cropImageInIsolate,
    <String, dynamic>{
      'imageBytes': imageBytes,
      'imageWidth': imageWidth,
      'imageHeight': imageHeight,
      'cropLeft': cropLeft,
      'cropTop': cropTop,
      'cropWidth': cropWidth,
      'cropHeight': cropHeight,
    },
  );
}

Uint8List _cropImageInIsolate(Map<String, dynamic> params) {
  final Uint8List imageBytes = params['imageBytes'] as Uint8List;
  final int imageWidth = params['imageWidth'] as int;
  final int imageHeight = params['imageHeight'] as int;
  final int cropLeft = params['cropLeft'] as int;
  final int cropTop = params['cropTop'] as int;
  final int cropWidth = params['cropWidth'] as int;
  final int cropHeight = params['cropHeight'] as int;

  final img.Image original = img.Image.fromBytes(
    width: imageWidth,
    height: imageHeight,
    bytes: imageBytes.buffer,
    numChannels: 4,
  );

  final img.Image cropped = img.copyCrop(
    original,
    x: cropLeft,
    y: cropTop,
    width: cropWidth,
    height: cropHeight,
  );

  return Uint8List.fromList(img.encodeJpg(cropped, quality: 90));
}