import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'src/circle_cutout_painter.dart';
import 'src/crop_image_service/crop_image_service.dart';

/// A widget that provides an interactive image cropping experience.
///
/// It allows users to zoom and pan an image behind a fixed circular mask,
/// similar to the photo cropping experience in apps like Telegram.
class TelegramImageCropper extends StatefulWidget {
  /// The path to the image asset that needs to be cropped.
  ///
  /// Provide either [imagePath] (for a bundled Flutter asset) or
  /// [imageBytes] (for an in-memory image, e.g. a photo picked from the
  /// gallery/camera). At least one of the two must be provided.
  final String? imagePath;

  /// Raw bytes of the image that needs to be cropped.
  ///
  /// Use this instead of [imagePath] when the source image is not a
  /// bundled asset (for example a file picked from the gallery/camera).
  /// Works uniformly on native and web, since it doesn't rely on
  /// filesystem access.
  final Uint8List? imageBytes;

  /// The diameter of the circular crop area in logical pixels.
  ///
  /// Defaults to 200. If the image is smaller than this size, the crop size
  /// will be adjusted to fit the image dimensions.
  final int cropSize;

  /// The style to be applied to the 'Crop Image' button.
  final ButtonStyle? cropButtonStyle;

  /// The text widget to be displayed inside the 'Crop Image' button.
  ///
  /// Defaults to `Text('Crop Image')` if null.
  final Text? cropButtonText;

  /// An optional widget to display as the result of the cropping process.
  ///
  /// Only used when [showResultDialog] is true. If provided, this widget
  /// will be shown in a dialog after the user presses the crop button. If
  /// null, a default `AlertDialog` with the cropped image will be shown.
  final Widget? croppedImageResultWidget;

  /// Called with the raw cropped JPEG bytes right after cropping finishes,
  /// before the result dialog (if any) is shown. Use this to save the
  /// result or pop the cropper screen with the bytes as a result.
  final void Function(Uint8List croppedBytes)? onCropped;

  /// Whether to automatically show a result dialog after cropping.
  ///
  /// Defaults to true to preserve the original demo behavior. Set this to
  /// false when the cropper is pushed as its own screen and should just
  /// return the result via [onCropped] without an extra confirmation popup.
  final bool showResultDialog;

  const TelegramImageCropper({
    this.imagePath,
    this.imageBytes,
    this.cropSize = 200,
    this.cropButtonStyle,
    this.cropButtonText,
    this.croppedImageResultWidget,
    this.onCropped,
    this.showResultDialog = true,
    super.key,
  }) : assert(
          imagePath != null || imageBytes != null,
          'Provide either imagePath or imageBytes',
        );

  @override
  _TelegramImageCropperState createState() => _TelegramImageCropperState();
}

class _TelegramImageCropperState extends State<TelegramImageCropper> {
  late ui.Image _image;
  bool _imageLoaded = false;
  final GlobalKey _key = GlobalKey();
  final TransformationController _controller = TransformationController();
  EdgeInsets _boundaryMargin = EdgeInsets.zero;

  // Default crop area dimensions
  int _cropSize = 200;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  void _getBoundaryMargin() {
    final RenderBox? renderBox =
        _key.currentContext?.findRenderObject() as RenderBox?;

    if (renderBox != null) {
      final ui.Size size = renderBox.size;

      final double vertical =
          ((size.height - _cropSize) / 2) / _controller.value.row0[0];
      final double horizontal =
          ((size.width - _cropSize) / 2) / _controller.value.row0[0];

      setState(() {
        _boundaryMargin =
            EdgeInsets.symmetric(vertical: vertical, horizontal: horizontal);
      });
    }
  }

  Future<void> _loadImage() async {
    final Uint8List list;
    if (widget.imageBytes != null) {
      // In-memory source (e.g. picked from gallery/camera).
      list = widget.imageBytes!;
    } else {
      // Load an image from assets
      final ByteData data = await rootBundle.load(widget.imagePath!);
      list = Uint8List.view(data.buffer);
    }
    final ui.Image image = await _loadImageFromBytes(list);

    setState(() {
      _image = image;
      _imageLoaded = true;
      _cropSize = _image.width < widget.cropSize
          ? _image.width
          : _image.height < widget.cropSize
              ? _image.height
              : widget.cropSize;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getBoundaryMargin();
    });
  }

  Future<ui.Image> _loadImageFromBytes(Uint8List list) async {
    final Completer<ui.Image> completer = Completer<ui.Image>();
    ui.decodeImageFromList(list, (ui.Image img) {
      return completer.complete(img);
    });
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Expanded(
          child: Center(
            child: _imageLoaded
                ? Stack(
                    children: <Widget>[
                      Center(
                        child: InteractiveViewer(
                          minScale: 0.5,
                          maxScale: 3.0,
                          transformationController: _controller,
                          clipBehavior: Clip.none,
                          boundaryMargin: _boundaryMargin,
                          onInteractionEnd: (ScaleEndDetails details) {
                            _getBoundaryMargin();
                          },
                          child: RawImage(
                            key: _key,
                            image: _image,
                          ),
                        ),
                      ),
                      // Static crop area in the center
                      IgnorePointer(
                        child: Center(
                          child: SizedBox(
                            width: MediaQuery.of(context).size.width,
                            height: MediaQuery.of(context).size.height,
                            child: CustomPaint(
                              painter: CircleCutoutPainter(
                                cropSize: _cropSize,
                                overlayColor:
                                    Colors.black.withValues(alpha: 0.6),
                              ),
                            ),
                          ),
                        ),
                      ),

                      Padding(
                        padding: const EdgeInsets.only(bottom: 36),
                        child: Align(
                          alignment: Alignment.bottomCenter,
                          child: ElevatedButton(
                            style: widget.cropButtonStyle,
                            onPressed:
                                _imageLoaded ? () => _cropImage(context) : null,
                            child: widget.cropButtonText ??
                                const Text('Crop Image'),
                          ),
                        ),
                      ),
                    ],
                  )
                : const CircularProgressIndicator(),
          ),
        ),
      ],
    );
  }

  Future<void> _cropImage(BuildContext context) async {
    final Uint8List? croppedBytes = await CropImageService.cropImage(
      transformation: _controller.value,
      renderBox: _key.currentContext!.findRenderObject()! as RenderBox,
      cropSize: _cropSize,
      imageWidth: _image.width,
      imageHeight: _image.height,
      imageByteData: await _image.toByteData(),
    );

    if (croppedBytes == null) return;

    widget.onCropped?.call(croppedBytes);

    if (!widget.showResultDialog || !context.mounted) return;

    showDialog(
      context: context,
      builder: (_) =>
          widget.croppedImageResultWidget ??
          AlertDialog(
            content: Image.memory(croppedBytes),
            contentPadding: EdgeInsets.zero,
          ),
    );
  }
}