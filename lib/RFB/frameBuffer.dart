import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

class FrameBufferBitmap {
  final Size size;
  final Size targetSize;
  Uint32List pixels;
  int pixelsPerRow;

  int _pixelDataSize;
  final _shouldScale;

  FrameBufferBitmap({
    this.size,
    this.targetSize,
  }) : _shouldScale = size != targetSize {
    pixelsPerRow = size.width.toInt();
    _pixelDataSize = pixelsPerRow * size.height.toInt();
    pixels = Uint32List(_pixelDataSize);
  }

  Future<Image> getImage() async {
    final imageDecoding = Completer<Image>();

    if(!_shouldScale)
      decodeImageFromPixels(pixels.buffer.asUint8List(), size.width.toInt(), size.height.toInt(), PixelFormat.bgra8888, (image) => imageDecoding.complete(image));
    else
      decodeImageFromPixels(
        pixels.buffer.asUint8List(), size.width.toInt(), size.height.toInt(), PixelFormat.bgra8888, (image) => imageDecoding.complete(image),
        targetHeight: targetSize.height.toInt(),
        targetWidth: targetSize.width.toInt(),
      );
      
    return imageDecoding.future;
  }
}
