import 'dart:async';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:hometoucher/RFB/BufferedInput.dart';


Uint8List generateBytes(int start, int length) {
  final buffer = Uint8List(length);

  for(int i = 0; i < length; i++)
    buffer[i] = start + i;

  return buffer;
}

void verify(Uint8List buffer, int start, int length) {
  expect(buffer.length, equals(length), reason: "buffer length");
  
  for(int i = 0; i < buffer.length; i++)
    expect(buffer[i], equals((start+i) & 0xff), reason: "buffer byte content at index $i");
}

Stream<Uint8List>  generateStream(List<Uint8List> chunkcs) {
  final controller = StreamController<Uint8List>();

  for(var chunk in chunkcs)
    controller.add(chunk);
  controller.close();
  return controller.stream;
}

void main() {
  group('Test BufferedInput class', () {
    test('Test basic functions (generate and verify', () {
      final buffer = generateBytes(100, 200);
      verify(buffer, 100, 200);
    });

    test('Test generate stream', () {
      final s = generateStream([generateBytes(0, 100)]);

      s.listen((chunk) { verify(chunk, 0, 100); });
    });

    test('Test BufferdInput with single chunk', () async {
      final s = generateStream([generateBytes(0, 100), generateBytes(200, 100)]);
      final b = BufferedInput(s);
      final p1 = await b.get(100);
      final p2 = await b.get(100);

      verify(p1, 0, 100);
      verify(p2, 200, 100);
    });

    test('Test BufferedInput 2 get from same chunk', () async {
      final s = generateStream([generateBytes(0, 100)]);
      final b = BufferedInput(s);
      final p1 = await b.get(50);
      final p2 = await b.get(50);

      verify(p1, 0, 50);
      verify(p2, 50, 50);
    });

    test('Test BufferedInput get from 2 chunks', () async {
      final s = generateStream([generateBytes(0, 30), generateBytes(30, 30)]);
      final b = BufferedInput(s);
      final result = await b.get(60);

      verify(result, 0, 60);
    });

    test('Test BufferedInput get from part of chunk, get from 2 chunks, get rest of 2nd chunk', () async {
      final s = generateStream([generateBytes(0, 30), generateBytes(30, 30)]);
      final b = BufferedInput(s);
      final p1 = await b.get(15);
      final p2 = await b.get(30);
      final p3 = await b.get(15);

      verify(p1, 0, 15);
      verify(p2, 15, 30);
      verify(p3, 45, 15);
    });
  });
}
