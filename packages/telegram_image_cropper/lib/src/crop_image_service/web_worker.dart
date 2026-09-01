import 'dart:async';
import 'dart:typed_data';
import 'dart:js_interop';
import 'package:web/web.dart' as web;

Future<Uint8List> cropImagePlatformSpecific({
  required Uint8List imageBytes,
  required int imageWidth,
  required int imageHeight,
  required int cropLeft,
  required int cropTop,
  required int cropWidth,
  required int cropHeight,
}) async {
  // 1. Create ImageData from raw bytes (RGBA)
  final Uint8ClampedList clampedBytes = imageBytes.buffer.asUint8ClampedList();
  final web.ImageData imageData =
      web.ImageData(clampedBytes.toJS, imageWidth, imageHeight as JSAny);

  // 2. Create temporary Canvas to draw the source image
  final web.HTMLCanvasElement sourceCanvas = web.HTMLCanvasElement()
    ..width = imageWidth
    ..height = imageHeight;
  sourceCanvas.context2D.putImageData(imageData, 0, 0);

  // 3. Create destination Canvas for the cropped image
  final web.HTMLCanvasElement destCanvas = web.HTMLCanvasElement()
    ..width = cropWidth
    ..height = cropHeight;

  // 4. Draw the required area
  destCanvas.context2D.drawImage(
    sourceCanvas,
    cropLeft.toDouble(),
    cropTop.toDouble(),
    cropWidth.toDouble(),
    cropHeight.toDouble(),
    0,
    0,
    cropWidth.toDouble(),
    cropHeight.toDouble(),
  );

  // 5. Convert Canvas to Blob (JPEG)
  final Completer<web.Blob?> completer = Completer<web.Blob?>();
  destCanvas.toBlob(
    (web.Blob? b) {
      completer.complete(b);
    }.toJS,
    'image/jpeg',
    0.9.toJS,
  );

  final web.Blob? croppedBlob = await completer.future;
  if (croppedBlob == null) {
    throw Exception('Failed to create Blob');
  }

  // 6. Read Blob as ArrayBuffer
  final JSArrayBuffer jsArrayBuffer = await croppedBlob.arrayBuffer().toDart;

  // 7. Convert JSArrayBuffer -> Uint8List
  return jsArrayBuffer.toDart.asUint8List();
}