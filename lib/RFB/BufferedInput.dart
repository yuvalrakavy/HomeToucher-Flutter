
import 'dart:io';
import 'dart:typed_data';
import 'package:async/async.dart';

class BufferedInputCancledError extends Error {}

class BufferedInput {
  final Stream<Uint8List> input;

  final StreamQueue<Uint8List> _queue;
  Uint8List _buffer;
  int _bufferIndex;
  CancelableOperation<Uint8List> _operation;
  bool _pendingCancelation = false;

  BufferedInput(this.input): _queue = StreamQueue(input);

  Future<Uint8List> get(int bytesCount) async {
    BytesBuilder accumulatedBytesBuffer;
    int receivedBytes = 0;
    Uint8List result;

    while(receivedBytes < bytesCount) {
      if(_buffer == null) {
        _operation = CancelableOperation<Uint8List>.fromFuture(_queue.next);
        _buffer = await _operation.valueOrCancellation(null);

        if(_operation.isCanceled || _pendingCancelation) {
          _pendingCancelation = false;
          throw BufferedInputCancledError();
        }

        _operation = null;
        _bufferIndex = 0;
      }

      if(accumulatedBytesBuffer == null) {     // No buffer is being built
        if(_bufferIndex + bytesCount <= _buffer.length) {
          // All data can be extracted from the buffer
          result = _buffer.sublist(_bufferIndex, _bufferIndex + bytesCount);
          receivedBytes += bytesCount;
          _bufferIndex += bytesCount;

          if(_bufferIndex == _buffer.length)
            _buffer = null;
        }
        else {
          // Not all requested data is in the buffer, need to get it from multiple buffers
          accumulatedBytesBuffer = BytesBuilder();

          accumulatedBytesBuffer.add(_buffer.sublist(_bufferIndex));
          receivedBytes += _buffer.length - _bufferIndex;
          _buffer = null;
        }
      }
      else {    // Received bytes are acuumulated from multiple chunks
        final neededBytesCount = bytesCount - receivedBytes;
        final bytesCountToAdd = neededBytesCount > _buffer.length - _bufferIndex ? _buffer.length - _bufferIndex : neededBytesCount;

        accumulatedBytesBuffer.add(_buffer.sublist(_bufferIndex, _bufferIndex + bytesCountToAdd));
        receivedBytes += bytesCountToAdd;

        if(receivedBytes == bytesCount) {
          result = accumulatedBytesBuffer.toBytes();
          accumulatedBytesBuffer = null;
        }

        _bufferIndex += bytesCountToAdd;
        if(_bufferIndex >= _buffer.length)
          _buffer = null;
      }
    }

    assert(result != null);
    return result;
  }

  Future<void> cancel() async {
    _pendingCancelation = true;
    await _operation?.cancel();
  }
}
