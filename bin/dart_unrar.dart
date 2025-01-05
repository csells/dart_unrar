import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A class to represent the RAR file entry with metadata.
class RarFileEntry {
  final String fileName;
  final int uncompressedSize;
  final int compressedSize;
  final bool isDirectory;

  RarFileEntry({
    required this.fileName,
    required this.uncompressedSize,
    required this.compressedSize,
    required this.isDirectory,
  });

  @override
  String toString() {
    return 'RarFileEntry('
        'fileName: $fileName, '
        'uncompressedSize: $uncompressedSize, '
        'compressedSize: $compressedSize, '
        'isDirectory: $isDirectory'
        ')';
  }
}

List<RarFileEntry> parseRar4(Uint8List data) {
  final reader = _ByteReader(data);
  final fileEntries = <RarFileEntry>[];

  // RAR 4 Signature
  const rarSignature = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00];
  if (!_checkSignature(reader, rarSignature)) {
    throw FormatException('Not a valid RAR 4.x file.');
  }

  while (!reader.isEOF) {
    final blockStart = reader.position;

    if (!reader.canRead(7)) {
      // Not enough data for a new block header
      break;
    }

    final headCrc = reader.readUint16(); // HEAD_CRC (2 bytes)
    final headType = reader.readByte(); // HEAD_TYPE (1 byte)
    final headFlags = reader.readUint16(); // HEAD_FLAGS (2 bytes)
    final headSize = reader.readUint16(); // HEAD_SIZE (2 bytes)

    // Validate header size
    if (headSize < 7 || !reader.canRead(headSize - 7)) {
      // Invalid or incomplete header; resynchronize
      reader.skip(1);
      continue;
    }

    // Check if the header type is valid
    if (headType == 0x73) {
      // Main archive header
      reader.skip(headSize - 7); // Skip the block
    } else if (headType == 0x74) {
      // File header
      final packSize = reader.readUint32(); // PACK_SIZE (4 bytes)
      final unpSize = reader.readUint32(); // UNP_SIZE (4 bytes)
      final hostOS = reader.readByte(); // HOST_OS (1 byte)
      final fileCRC = reader.readUint32(); // FILE_CRC (4 bytes)
      final ftime = reader.readUint32(); // FTIME (4 bytes)
      final unpVer = reader.readByte(); // UNP_VER (1 byte)
      final method = reader.readByte(); // METHOD (1 byte)
      final nameSize = reader.readUint16(); // NAME_SIZE (2 bytes)
      final fileAttr = reader.readUint32(); // FILE_ATTR (4 bytes)

      if (!reader.canRead(nameSize)) {
        throw FormatException(
            'Incomplete file name data at offset $blockStart.');
      }

      // Read the file name
      final fileNameBytes = reader.readBytes(nameSize);
      final fileName = latin1.decode(fileNameBytes);

      // Check if this is a directory
      final isDirectory = (fileAttr & 0x10) != 0 || fileName.endsWith('/');

      // Add to the list of file entries
      fileEntries.add(RarFileEntry(
        fileName: fileName,
        uncompressedSize: unpSize,
        compressedSize: packSize,
        isDirectory: isDirectory,
      ));

      // Skip any remaining block data
      final bytesConsumed = reader.position - blockStart;
      final extraToSkip = headSize - bytesConsumed;
      if (extraToSkip > 0) {
        if (!reader.canRead(extraToSkip)) break;
        reader.skip(extraToSkip);
      }

      // Skip the compressed file data for this file
      if (!reader.canRead(packSize)) break;
      reader.skip(packSize);
    } else {
      // Invalid or unrecognized header type
      if (!reader.canRead(1)) break;
      reader.skip(1); // Resynchronize
    }
  }

  return fileEntries;
}

/// Utility function to check the file signature.
bool _checkSignature(_ByteReader reader, List<int> signatureBytes) {
  if (!reader.canRead(signatureBytes.length)) return false;
  final fileSig = reader.readBytes(signatureBytes.length);
  for (int i = 0; i < signatureBytes.length; i++) {
    if (fileSig[i] != signatureBytes[i]) return false;
  }
  return true;
}

/// A helper class for sequentially reading bytes from a Uint8List.
class _ByteReader {
  final Uint8List _data;
  int _offset = 0;

  _ByteReader(this._data);

  int get position => _offset;
  bool get isEOF => _offset >= _data.lengthInBytes;

  bool canRead(int count) => (_offset + count) <= _data.lengthInBytes;

  int readByte() {
    if (!canRead(1)) {
      throw RangeError('Attempted to read past end of data');
    }
    return _data[_offset++];
  }

  Uint8List readBytes(int count) {
    if (!canRead(count)) {
      throw RangeError(
          'Attempted to read $count bytes but only ${_data.lengthInBytes - _offset} remain.');
    }
    final bytes = _data.sublist(_offset, _offset + count);
    _offset += count;
    return bytes;
  }

  int readUint16() {
    final b0 = readByte();
    final b1 = readByte();
    return (b1 << 8) | b0;
  }

  int readUint32() {
    final b0 = readByte();
    final b1 = readByte();
    final b2 = readByte();
    final b3 = readByte();
    return (b3 << 24) | (b2 << 16) | (b1 << 8) | b0;
  }

  void skip(int count) {
    if (!canRead(count)) {
      throw RangeError(
          'Attempted to skip $count bytes but only ${_data.lengthInBytes - _offset} remain.');
    }
    _offset += count;
  }
}

void main() {
  // Example usage:
  // final bytes = File('example.rar').readAsBytesSync();
  // final entries = parseRarFile(bytes);
  // for (final e in entries) {
  //   print(e);
  // }

  var file = File('/Users/csells/Downloads/Batman 001.cbr');
  final bytes = file.readAsBytesSync();

  try {
    final entries = parseRar4(bytes);
    for (final e in entries) {
      print(e);
    }
  } catch (e) {
    print('Error parsing RAR file: $e');
  }
}
