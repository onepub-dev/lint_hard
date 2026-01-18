import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

class ThrowsCache {
  final String rootPath;
  final Map<String, ThrowsCacheFile> _files = {};

  ThrowsCache(this.rootPath);

  String packageCachePath(
    String packageName,
    String version, {
    String? sourceId,
  }) {
    final safeSource = sourceId ?? 'hosted-pub.dev';
    return p.join(
      rootPath,
      'throws',
      'v1',
      'package',
      packageName,
      safeSource,
      '$version.throws',
    );
  }

  ThrowsCacheFile? openPackage(
    String packageName,
    String version, {
    String? sourceId,
  }) {
    return _openFile(
      packageCachePath(
        packageName,
        version,
        sourceId: sourceId,
      ),
    );
  }

  String sdkCachePath(String sdkVersion) {
    return p.join(rootPath, 'throws', 'v1', 'sdk', '$sdkVersion.throws');
  }

  ThrowsCacheFile? openSdk(String sdkVersion) {
    return _openFile(sdkCachePath(sdkVersion));
  }

  ThrowsCacheFile? openFile(String path) => _openFile(path);

  ThrowsCacheFile? _openFile(String path) {
    final existing = _files[path];
    if (existing != null) return existing;
    final file = File(path);
    if (!file.existsSync()) return null;
    final opened = ThrowsCacheFile.openSync(file);
    if (opened == null) return null;
    _files[path] = opened;
    return opened;
  }
}

class ThrowsProvenance {
  final String call;
  final String? origin;

  const ThrowsProvenance({
    required this.call,
    required this.origin,
  });
}

class ThrowsCacheEntry {
  final List<String> thrown;
  final Map<String, List<ThrowsProvenance>> provenance;

  const ThrowsCacheEntry({
    required this.thrown,
    this.provenance = const {},
  });
}

class ThrowsCacheFile {
  static const _magic = 'LHTHROW\u0000';
  static const _headerSize = 64;
  static const _indexRecordSize = 32;
  static const _flagProvenance = 0x1;
  static const _nullOffset = 0xFFFFFFFF;

  final Uint8List _bytes;
  final ByteData _data;
  final int _indexOffset;
  final int _indexCount;
  final int _stringTableOffset;
  final int _stringTableLength;
  final int _flags;

  List<String>? _strings;

  ThrowsCacheFile._(
    this._bytes,
    this._data,
    this._indexOffset,
    this._indexCount,
    this._stringTableOffset,
    this._stringTableLength,
    this._flags,
  );

  static ThrowsCacheFile? openSync(File file) {
    final bytes = file.readAsBytesSync();
    if (bytes.length < _headerSize) return null;
    final data = ByteData.sublistView(bytes);
    final magic = String.fromCharCodes(bytes.sublist(0, 8));
    if (magic != _magic) return null;
    final version = data.getUint32(8, Endian.little);
    if (version != 1) return null;
    final flags = data.getUint32(12, Endian.little);
    final indexOffset = data.getUint64(16, Endian.little);
    final indexCount = data.getUint64(24, Endian.little);
    final stringTableOffset = data.getUint64(32, Endian.little);
    final stringTableLength = data.getUint64(40, Endian.little);
    return ThrowsCacheFile._(
      bytes,
      data,
      indexOffset,
      indexCount,
      stringTableOffset,
      stringTableLength,
      flags,
    );
  }

  List<String> lookup(String key) {
    final strings = _loadStrings();
    final keyHash = hashThrowsCacheKey(key);
    final index = _findIndex(keyHash);
    if (index == null) return const <String>[];

    final record = _readRecord(index, key);
    if (record == null) return const <String>[];
    final offsets = record.thrownOffsets;
    if (offsets.isEmpty) return const <String>[];

    final result = <String>[];
    for (final offset in offsets) {
      if (offset < 0 || offset >= strings.length) continue;
      result.add(strings[offset]);
    }
    return result;
  }

  Map<String, List<ThrowsProvenance>> lookupProvenance(String key) {
    if ((_flags & _flagProvenance) == 0) {
      return const <String, List<ThrowsProvenance>>{};
    }
    final strings = _loadStrings();
    final keyHash = hashThrowsCacheKey(key);
    final index = _findIndex(keyHash);
    if (index == null) return const <String, List<ThrowsProvenance>>{};

    final record = _readRecord(index, key);
    if (record == null) return const <String, List<ThrowsProvenance>>{};
    if (record.provenanceOffsets.isEmpty) {
      return const <String, List<ThrowsProvenance>>{};
    }

    final result = <String, List<ThrowsProvenance>>{};
    for (var i = 0; i < record.thrownOffsets.length; i++) {
      final typeIndex = record.thrownOffsets[i];
      if (typeIndex < 0 || typeIndex >= strings.length) continue;
      final typeName = strings[typeIndex];
      final provOffsets = record.provenanceOffsets[i];
      if (provOffsets.isEmpty) continue;
      final provenance = <ThrowsProvenance>[];
      for (final offsets in provOffsets) {
        if (offsets.callOffset < 0 ||
            offsets.callOffset >= strings.length) {
          continue;
        }
        final call = strings[offsets.callOffset];
        String? origin;
        if (offsets.originOffset != _nullOffset &&
            offsets.originOffset >= 0 &&
            offsets.originOffset < strings.length) {
          origin = strings[offsets.originOffset];
        }
        provenance.add(ThrowsProvenance(call: call, origin: origin));
      }
      if (provenance.isNotEmpty) {
        result[typeName] = provenance;
      }
    }
    return result;
  }

  _IndexRecord? _findIndex(int keyHash) {
    var low = 0;
    var high = _indexCount - 1;
    while (low <= high) {
      final mid = low + ((high - low) >> 1);
      final record = _readIndex(mid);
      if (record.keyHash == keyHash) {
        return _scanForKey(record, mid, keyHash);
      }
      if (record.keyHash < keyHash) {
        low = mid + 1;
      } else {
        high = mid - 1;
      }
    }
    return null;
  }

  _IndexRecord? _scanForKey(
    _IndexRecord record,
    int index,
    int keyHash,
  ) {
    var i = index;
    while (i > 0) {
      final prev = _readIndex(i - 1);
      if (prev.keyHash != keyHash) break;
      i--;
      record = prev;
    }
    return record;
  }

  _ThrownRecord? _readRecord(_IndexRecord index, String key) {
    var current = index;
    for (;;) {
      final record =
          _readThrownRecord(current.recordOffset, current.recordLength);
      if (record != null) {
        if (current.recordKeyLength == 0 || record.key == key) {
          return record;
        }
      }
      final nextIndex = _nextIndex(current);
      if (nextIndex == null) return null;
      if (nextIndex.keyHash != current.keyHash) return null;
      current = nextIndex;
    }
  }

  _IndexRecord? _nextIndex(_IndexRecord current) {
    final index = current.index + 1;
    if (index >= _indexCount) return null;
    return _readIndex(index);
  }

  _IndexRecord _readIndex(int index) {
    final offset = _indexOffset + index * _indexRecordSize;
    final keyHash = _data.getUint64(offset, Endian.little);
    final recordOffset = _data.getUint64(offset + 8, Endian.little);
    final recordLength = _data.getUint32(offset + 16, Endian.little);
    final recordKeyLength = _data.getUint32(offset + 20, Endian.little);
    return _IndexRecord(
      index: index,
      keyHash: keyHash,
      recordOffset: recordOffset,
      recordLength: recordLength,
      recordKeyLength: recordKeyLength,
    );
  }

  _ThrownRecord? _readThrownRecord(int offset, int length) {
    if (offset + length > _bytes.length) return null;
    final keyLength = _data.getUint16(offset, Endian.little);
    final thrownCount = _data.getUint16(offset + 2, Endian.little);
    final recordFlags = _data.getUint32(offset + 4, Endian.little);
    final keyStart = offset + 8;
    final keyEnd = keyStart + keyLength;
    if (keyEnd > _bytes.length) return null;
    final key = String.fromCharCodes(_bytes.sublist(keyStart, keyEnd));
    final thrownOffsets = <int>[];
    var cursor = keyEnd;
    for (var i = 0; i < thrownCount; i++) {
      if (cursor + 4 > _bytes.length) break;
      thrownOffsets.add(_data.getUint32(cursor, Endian.little));
      cursor += 4;
    }
    final provenanceOffsets = <List<_ProvenanceOffset>>[];
    if ((recordFlags & _flagProvenance) != 0) {
      for (var i = 0; i < thrownCount; i++) {
        if (cursor + 4 > _bytes.length) {
          provenanceOffsets.add(const <_ProvenanceOffset>[]);
          continue;
        }
        final provCount = _data.getUint16(cursor, Endian.little);
        cursor += 2;
        cursor += 2; // reserved
        final provList = <_ProvenanceOffset>[];
        for (var j = 0; j < provCount; j++) {
          if (cursor + 8 > _bytes.length) break;
          final callOffset = _data.getUint32(cursor, Endian.little);
          final originOffset = _data.getUint32(cursor + 4, Endian.little);
          cursor += 8;
          provList.add(
            _ProvenanceOffset(
              callOffset: callOffset,
              originOffset: originOffset,
            ),
          );
        }
        provenanceOffsets.add(provList);
      }
    } else {
      for (var i = 0; i < thrownCount; i++) {
        provenanceOffsets.add(const <_ProvenanceOffset>[]);
      }
    }
    return _ThrownRecord(
      key: key,
      thrownOffsets: thrownOffsets,
      provenanceOffsets: provenanceOffsets,
    );
  }

  List<String> _loadStrings() {
    final existing = _strings;
    if (existing != null) return existing;

    final start = _stringTableOffset;
    final end = start + _stringTableLength;
    if (end > _bytes.length) return const <String>[];

    final tableBytes = _bytes.sublist(start, end);
    final tableData = ByteData.sublistView(tableBytes);
    final count = tableData.getUint32(0, Endian.little);
    final offsets = <int>[];
    var cursor = 4;
    for (var i = 0; i < count; i++) {
      offsets.add(tableData.getUint32(cursor, Endian.little));
      cursor += 4;
    }
    final dataStart = cursor;
    final strings = <String>[];
    for (final offset in offsets) {
      final stringOffset = dataStart + offset;
      if (stringOffset >= tableBytes.length) {
        strings.add('');
        continue;
      }
      var endOffset = stringOffset;
      while (endOffset < tableBytes.length &&
          tableBytes[endOffset] != 0x00) {
        endOffset++;
      }
      strings.add(
        String.fromCharCodes(tableBytes.sublist(stringOffset, endOffset)),
      );
    }
    _strings = strings;
    return strings;
  }

}

int hashThrowsCacheKey(String value) {
  const offsetBasis = 0xcbf29ce484222325;
  const prime = 0x100000001b3;
  var hash = offsetBasis;
  for (final unit in value.codeUnits) {
    hash ^= unit;
    hash = (hash * prime) & 0xFFFFFFFFFFFFFFFF;
  }
  return hash;
}

class ThrowsCacheKeyBuilder {
  static String build({
    required String libraryUri,
    required String container,
    required String name,
    required List<String> parameterTypes,
  }) {
    final buffer = StringBuffer();
    buffer.write(libraryUri);
    buffer.write('|');
    buffer.write(container.isEmpty ? '_' : container);
    buffer.write('#');
    buffer.write(name);
    buffer.write('(');
    for (var i = 0; i < parameterTypes.length; i++) {
      if (i > 0) buffer.write(',');
      buffer.write(parameterTypes[i]);
    }
    buffer.write(')');
    return buffer.toString();
  }
}

class _IndexRecord {
  final int index;
  final int keyHash;
  final int recordOffset;
  final int recordLength;
  final int recordKeyLength;

  _IndexRecord({
    required this.index,
    required this.keyHash,
    required this.recordOffset,
    required this.recordLength,
    required this.recordKeyLength,
  });
}

class _ThrownRecord {
  final String key;
  final List<int> thrownOffsets;
  final List<List<_ProvenanceOffset>> provenanceOffsets;

  _ThrownRecord({
    required this.key,
    required this.thrownOffsets,
    required this.provenanceOffsets,
  });
}

class _ProvenanceOffset {
  final int callOffset;
  final int originOffset;

  const _ProvenanceOffset({
    required this.callOffset,
    required this.originOffset,
  });
}
