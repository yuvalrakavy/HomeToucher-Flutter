import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hometoucher/RFB/frameBuffer.dart';
import 'package:hometoucher/RFB/BufferedInput.dart';

class RemoteScreenController extends ValueNotifier<ui.Image> {
  final Socket socket;
  Size deviceSizeInPixels;
  
  final BufferedInput _inputSocket;
  _PixelFormat _pixelFormat;
  Size _frameBufferSizeInPixels;
  FrameBufferBitmap _bitmap;

  RemoteScreenController({
    @required this.socket,
    @required this.deviceSizeInPixels,
  }) : _inputSocket = BufferedInput(socket), super(null);

  Future<void> generateFrames() async {
    try {
      await _initializeSession();
      await _sendFrameUpdateRequest(incremental: false);

      do {
        final serverMessageType = await _inputSocket.get(1);

        switch(serverMessageType[0]) {
          case 0:     // Frame update
            await _handleFrameUpdates();
            await _sendFrameUpdateRequest(incremental: true);

            value = await _bitmap.getImage();
            break;

          default:
            throw RFBsessionInvalidServerMessage();
        }
      } while(true);
    } on BufferedInputCancledError {
      print("RFB session cancled");
    }
    catch (e) {
      print("RFB session expection $e"); 
    } finally {
      socket.destroy();
      print("RFB session terminated");
    }
  }

  Future<void> terminate() async {
    _inputSocket.cancel();
  }

  void onTapDown(Offset location) {
    _sendPointerEvent(location: location, down: true);
  }

  void onTapUp(Offset location) {
    _sendPointerEvent(location: location, down: false);
  }

  Future<void> _sendPointerEvent({Offset location, bool down}) async {
    try {
      final pointerMessage = ByteData.view(Uint8List(6).buffer);

      pointerMessage.setUint8(0, 5);    // 5 = pointer message
      pointerMessage.setUint8(1, down ? 1 : 0);
      pointerMessage.setUint16(2, location.dx.toInt(), Endian.big);
      pointerMessage.setUint16(4, location.dy.toInt(), Endian.big);

      socket.add(pointerMessage.buffer.asUint8List());
      // await socket.flush();
    } catch (e) {
      print("Send pointer event failed with exception $e");
    }
  }

  Future<void> _sendFrameUpdateRequest({bool incremental}) async {
    final frameUpdateMessage = ByteData.view(Uint8List(10).buffer);

    frameUpdateMessage.setUint8(0, 3);    // Message type
    frameUpdateMessage.setUint8(1, incremental ? 1 : 0);  // incremental
    frameUpdateMessage.setUint16(2, 0, Endian.big);       // x position
    frameUpdateMessage.setUint16(4, 0, Endian.big);       // y position
    frameUpdateMessage.setUint16(6, _frameBufferSizeInPixels.width.toInt(), Endian.big);
    frameUpdateMessage.setUint16(8, _frameBufferSizeInPixels.height.toInt(), Endian.big);

    socket.add(frameUpdateMessage.buffer.asUint8List());
    await socket.flush();
  }

  Future<void> _handleFrameUpdates() async {
    final updater = FrameUpdaterFromBufferedInput(
      inputSocket: _inputSocket,
      bitmap: _bitmap,
      pixelFormat: _pixelFormat
    );

    await updater.updateFrame();
  }

  Future<void> _initializeSession() async {
    final protocolBytes = await _inputSocket.get(12);

    print('Got from server ${utf8.decode(protocolBytes)}');

    socket.add(protocolBytes);      // Send back protocol message to the server
    final securityTypesCount = (await _inputSocket.get(1))[0];

    if(securityTypesCount == 0)
      throw RFBsessionSetupError();

    final _ = await _inputSocket.get(securityTypesCount);

    socket.add([1]);      // Send security none

    final securityResultBytes = await _inputSocket.get(4);
    final securityResult = ByteData.view(securityResultBytes.buffer).getUint32(0, Endian.big);

    if(securityResult != 0)
      throw RFBsessionSecurityFailed();

    // Send ClientInit message with shared flag set to true
    socket.add([1]);

    // Get ServerInit message
    final serverInitBytes = ByteData.view((await _inputSocket.get(24)).buffer);
    _frameBufferSizeInPixels = Size(serverInitBytes.getUint16(0, Endian.big).toDouble(), serverInitBytes.getUint16(2, Endian.big).toDouble());
    _pixelFormat = _PixelFormat(
      bitsPerPixel: serverInitBytes.getUint8(4+0),
      depth: serverInitBytes.getUint8(4+1),
      bigEndians: serverInitBytes.getUint8(4+2) != 0,
      trueColors: serverInitBytes.getUint8(4+3) != 0,
      redMax: serverInitBytes.getUint16(4+4, Endian.big),
      greenMax: serverInitBytes.getUint16(4+6, Endian.big),
      blueMax: serverInitBytes.getUint16(4+8, Endian.big),
      redShift: serverInitBytes.getUint8(4+10),
      greenShift: serverInitBytes.getUint8(4+11),
      blueShift: serverInitBytes.getUint8(4+12),
    );

    final sessionNameLength = serverInitBytes.getUint32(20, Endian.big);
    final sessionName = utf8.decode(await _inputSocket.get(sessionNameLength));

    print("Initialized RFB session: $sessionName");

    _bitmap = FrameBufferBitmap(size: _frameBufferSizeInPixels, targetSize: deviceSizeInPixels);

    // Set supported encoding
    final supportedEncodingFormats = [5, 0];      // Hextile and raw encoding
    final setEncodingMessage = ByteData.view(Uint8List(4 + 4 * supportedEncodingFormats.length).buffer);

    setEncodingMessage.setUint8(0, 2);  // Set encoding message (2)
    setEncodingMessage.setUint8(1, 0);  // Padding
    setEncodingMessage.setUint16(2, supportedEncodingFormats.length, Endian.big);
 
    for(int iEncoding = 0; iEncoding < supportedEncodingFormats.length; iEncoding++)
      setEncodingMessage.setInt32(4 + iEncoding*4, supportedEncodingFormats[iEncoding], Endian.big);

    socket.add(setEncodingMessage.buffer.asUint8List());
    await socket.flush();
  }
}

class _PixelFormat {
  final int bitsPerPixel;
  final int depth;
  final bool bigEndians;
  final bool trueColors;
  final int redMax;
  final int greenMax;
  final int blueMax;
  final int redShift;
  final int greenShift;
  final int blueShift;

  _PixelFormat({
    this.bitsPerPixel,
    this.depth,
    this.bigEndians,
    this.trueColors,
    this.redMax,
    this.greenMax,
    this.blueMax,
    this.redShift,
    this.greenShift,
    this.blueShift,
  });
}

class RFBsessionError extends Error {}
class RFBsessionSetupError extends RFBsessionError {}
class RFBsessionSecurityFailed extends RFBsessionSetupError {}
class RFBsessionInvalidServerMessage extends RFBsessionError {}
class RFBsessionInvalidEncoding extends RFBsessionError {}

class IntPoint {
  final int x;
  final int y;
  
  IntPoint(this.x, this.y);
}

class IntSize {
  final int width;
  final int height;

  IntSize(this.width, this.height);
}

class IntRect {
  final IntPoint origin;
  final IntSize size;

  IntRect(this.origin, this.size);
}

class FrameUpdater {
  final _PixelFormat pixelFormat;
  final FrameBufferBitmap bitmap;

  final bool _devicePixelSameAsServer;

  FrameUpdater({@required this.bitmap, @required this.pixelFormat}) :
    _devicePixelSameAsServer = 
      pixelFormat.blueShift == 0 && pixelFormat.blueMax == 255 &&
      pixelFormat.greenShift == 8 && pixelFormat.greenMax == 256 &&
      pixelFormat.redShift == 16 && pixelFormat.redMax == 255;

  int toDevicePixel(int serverPixel) {
    if(_devicePixelSameAsServer)
      return serverPixel | 0xff000000;
    else {  
      final r = (serverPixel >> pixelFormat.redShift) & pixelFormat.redMax;
      final g = (serverPixel >> pixelFormat.greenShift) & pixelFormat.greenMax;
      final b = (serverPixel >> pixelFormat.blueShift) & pixelFormat.blueMax;

      return b | (g << 8) | (r << 16) | (255 << 24);
    }
  }

  void fillSubrect({IntRect tile, IntRect subrect, int devicePixel}) {
    int subrectOffset = (tile.origin.y + subrect.origin.y) * bitmap.pixelsPerRow + tile.origin.x + subrect.origin.x;

    for(int y = 0; y < subrect.size.height; y++) {
      bitmap.pixels.fillRange(subrectOffset, subrectOffset + subrect.size.width, devicePixel);
      subrectOffset += bitmap.pixelsPerRow;
    }
  }
}

class FrameUpdaterFromBufferedInput extends FrameUpdater {
  final BufferedInput inputSocket;

  FrameUpdaterFromBufferedInput({@required this.inputSocket, @required bitmap, @required pixelFormat}) :
     super(bitmap: bitmap, pixelFormat: pixelFormat);

  Future<void> updateFrame() async {
    final headerBytes = ByteData.view((await inputSocket.get(3)).buffer);
    final rectCount = headerBytes.getUint16(1, Endian.big);

    for(int i = 0; i < rectCount; i++) {
      final rectHeaderBytes = ByteData.view((await inputSocket.get(12)).buffer);
      final updatedRect = IntRect(
        IntPoint(rectHeaderBytes.getUint16(0, Endian.big), rectHeaderBytes.getUint16(2, Endian.big)),
        IntSize(rectHeaderBytes.getUint16(4, Endian.big), rectHeaderBytes.getUint16(6, Endian.big))
      );
      final encodingType = rectHeaderBytes.getInt32(8, Endian.big);

      switch(encodingType) {
        case 0: await _handleRawEncoding(updatedRect);  break;
        case 5: await _handleHextileEncoding(updatedRect); break;
        default:
          throw RFBsessionInvalidEncoding();
      }
    }
  }

  Future<void> _handleRawEncoding(IntRect updatedRect) async {
    int pixelOffset = updatedRect.origin.y * bitmap.pixelsPerRow + updatedRect.origin.x;

    for(int row = 0; row < updatedRect.size.height; row++) {
      final rowPixles = (await inputSocket.get(updatedRect.size.width * sizeOf<Uint32>())).buffer.asUint32List().map((p) => toDevicePixel(p));

      bitmap.pixels.setRange(pixelOffset, pixelOffset + updatedRect.size.width, rowPixles);
      pixelOffset += bitmap.pixelsPerRow;
    }
  }

  Future<void> _handleHextileEncoding(IntRect updatedRect) async {
    final hTileCount = (updatedRect.size.width + 15) ~/ 16;
    final vTileCount = (updatedRect.size.height + 15) ~/ 16;
    int foregroundColor = 0;
    int backgroundColor = 0;

    Future<void> processTile(IntRect tileRect) async {
      final tileEncoding = (await inputSocket.get(1))[0];

      if((tileEncoding & 1) != 0) {   // Tile raw encoding
        var pixelsOffset = tileRect.origin.y * bitmap.pixelsPerRow + tileRect.origin.x;

        for(int row = 0; row < tileRect.size.height; row++) {
          final rowPixels = (await inputSocket.get(tileRect.size.width * sizeOf<Uint32>())).buffer.asUint32List().map((p) => toDevicePixel(p));

          bitmap.pixels.setRange(pixelsOffset, pixelsOffset+tileRect.size.width, rowPixels);
          pixelsOffset += bitmap.pixelsPerRow;
        }
      }
      else {
        var subrectCount = 0;

        if((tileEncoding & 2) != 0)
          backgroundColor = toDevicePixel(ByteData.view((await inputSocket.get(sizeOf<Uint32>())).buffer).getUint32(0, Endian.little));

        if((tileEncoding & 4) != 0)
          foregroundColor = toDevicePixel(ByteData.view((await inputSocket.get(sizeOf<Uint32>())).buffer).getUint32(0, Endian.little));

        if((tileEncoding & 8) != 0)
          subrectCount = (await inputSocket.get(1))[0];

        final subrectsAreColors = (tileEncoding & 16) != 0;

        fillSubrect(
          tile: tileRect,
          subrect: IntRect(IntPoint(0, 0), tileRect.size),
          devicePixel: backgroundColor
        );

        if(subrectCount > 0) {

          if(subrectsAreColors) {
            for(int iSubrect = 0; iSubrect < subrectCount; iSubrect++) {
              final subRectBytes = ByteData.view((await inputSocket.get(6)).buffer);
              final color = toDevicePixel(subRectBytes.getUint32(0, Endian.little));
              final xy = subRectBytes.getUint8(4);
              final wh = subRectBytes.getUint8(5);
              final subrect = IntRect(IntPoint((xy >> 4) & 0x0f, (xy & 0x0f)), IntSize(((wh >> 4) & 0x0f) + 1, (wh & 0x0f) + 1));

              fillSubrect(
                tile: tileRect,
                subrect: subrect,
                devicePixel: color
              );
            }
          }
          else {
            for(int iSubrect = 0; iSubrect < subrectCount; iSubrect++) {
              final subRectBytes = ByteData.view((await inputSocket.get(2)).buffer);
              final xy = subRectBytes.getUint8(0);
              final wh = subRectBytes.getUint8(1);
              final subrect = IntRect(IntPoint((xy >> 4) & 0x0f, (xy & 0x0f)), IntSize(((wh >> 4) & 0x0f) + 1, (wh & 0x0f) + 1));

              fillSubrect(
                tile: tileRect,
                subrect: subrect,
                devicePixel: foregroundColor
              );
            }
          }
        }
      }
    }   // processTile (function)

    for(var vTile = 0; vTile < vTileCount; vTile++) {
      for(var hTile = 0; hTile < hTileCount; hTile++) {
        final xOffset = hTile * 16, yOffset = vTile * 16;
        final x = updatedRect.origin.x +  xOffset, y = updatedRect.origin.y + yOffset;
        final tileRect = IntRect(
          IntPoint(x, y),
          IntSize(
            xOffset + 16 > updatedRect.size.width ? updatedRect.size.width - xOffset : 16,
            yOffset + 16 > updatedRect.size.height ? updatedRect.size.height - yOffset : 16
          )
        );

        assert(tileRect.size.width >= 0 && tileRect.size.width <= 16 && tileRect.size.height >= 0 && tileRect.size.height <= 16);

        await processTile(tileRect);
      }
    }
  }

}