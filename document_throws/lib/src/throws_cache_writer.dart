import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'throws_cache.dart';

class ThrowsCacheWriter {
  static void writeFileSync(File file, Map<String, ThrowsCacheEntry> entries) {
    file.parent.createSync(recursive: true);
    final tempFile = _tempFileFor(file);
    final sortedKeys = entries.keys.toList()..sort();

    final stringList = _collectStrings(entries);
    final stringIndex = <String, int>{};
    for (var i = 0; i < stringList.length; i++) {
      stringIndex[stringList[i]] = i;
    }

    final dataBuilder = BytesBuilder();
    final recordMeta = <String, _RecordMeta>{};
    final hasProvenance = _hasProvenance(entries);
    for (final key in sortedKeys) {
      final entry = entries[key];
      if (entry == null) continue;
      final throwsList = entry.thrown;
      final provenance = entry.provenance;
      final keyBytes = utf8.encode(key);
      final header = ByteData(8);
      header.setUint16(0, keyBytes.length, Endian.little);
      header.setUint16(2, throwsList.length, Endian.little);
      header.setUint32(4, provenance.isEmpty ? 0 : 1, Endian.little);

      final recordOffset = _headerSize + dataBuilder.length;
      dataBuilder.add(header.buffer.asUint8List());
      dataBuilder.add(keyBytes);
      for (final thrown in throwsList) {
        final index = stringIndex[thrown] ?? 0;
        final entryBytes = ByteData(4);
        entryBytes.setUint32(0, index, Endian.little);
        dataBuilder.add(entryBytes.buffer.asUint8List());
      }

      if (provenance.isNotEmpty) {
        for (final thrown in throwsList) {
          final provList = provenance[thrown] ?? const <ThrowsProvenance>[];
          final headerBytes = ByteData(4);
          headerBytes.setUint16(0, provList.length, Endian.little);
          headerBytes.setUint16(2, 0, Endian.little);
          dataBuilder.add(headerBytes.buffer.asUint8List());
          for (final prov in provList) {
            final callIndex = stringIndex[prov.call] ?? 0;
            final originIndex = prov.origin == null
                ? 0xFFFFFFFF
                : (stringIndex[prov.origin!] ?? 0);
            final provBytes = ByteData(8);
            provBytes.setUint32(0, callIndex, Endian.little);
            provBytes.setUint32(4, originIndex, Endian.little);
            dataBuilder.add(provBytes.buffer.asUint8List());
          }
        }
      }

      var recordLength = 8 + keyBytes.length + throwsList.length * 4;
      if (provenance.isNotEmpty) {
        var provBytes = 0;
        for (final thrown in throwsList) {
          final provList = provenance[thrown] ?? const <ThrowsProvenance>[];
          provBytes += 4;
          provBytes += provList.length * 8;
        }
        recordLength += provBytes;
      }
      recordMeta[key] = _RecordMeta(
        offset: recordOffset,
        length: recordLength,
        keyLength: keyBytes.length,
      );
    }

    final dataBytes = dataBuilder.toBytes();
    final stringTableBytes = _buildStringTable(stringList);
    final stringTableOffset = _headerSize + dataBytes.length;
    final stringTableLength = stringTableBytes.length;

    final indexBuilder = BytesBuilder();
    final indexRecords = <_IndexRecordWrite>[];
    for (final key in sortedKeys) {
      final meta = recordMeta[key]!;
      indexRecords.add(
        _IndexRecordWrite(
          keyHash: hashThrowsCacheKey(key),
          recordOffset: meta.offset,
          recordLength: meta.length,
          recordKeyLength: meta.keyLength,
        ),
      );
    }
    indexRecords.sort((a, b) {
      final cmp = a.keyHash.compareTo(b.keyHash);
      if (cmp != 0) return cmp;
      return a.recordOffset.compareTo(b.recordOffset);
    });

    for (final record in indexRecords) {
      final data = ByteData(_indexRecordSize);
      data.setUint64(0, record.keyHash, Endian.little);
      data.setUint64(8, record.recordOffset, Endian.little);
      data.setUint32(16, record.recordLength, Endian.little);
      data.setUint32(20, record.recordKeyLength, Endian.little);
      data.setUint64(24, 0, Endian.little);
      indexBuilder.add(data.buffer.asUint8List());
    }
    final indexBytes = indexBuilder.toBytes();
    final indexOffset = stringTableOffset + stringTableLength;
    final indexCount = indexRecords.length;

    final header = _buildHeader(
      flags: hasProvenance ? 1 : 0,
      indexOffset: indexOffset,
      indexCount: indexCount,
      stringTableOffset: stringTableOffset,
      stringTableLength: stringTableLength,
      dataOffset: _headerSize,
    );
    final footer = _buildFooter(
      indexOffset: indexOffset,
      indexCount: indexCount,
      stringTableOffset: stringTableOffset,
      stringTableLength: stringTableLength,
    );

    final builder = BytesBuilder();
    builder.add(header);
    builder.add(dataBytes);
    builder.add(stringTableBytes);
    builder.add(indexBytes);
    builder.add(footer);

    tempFile.createSync(recursive: true);
    tempFile.writeAsBytesSync(builder.toBytes());
    tempFile.renameSync(file.path);
  }

  static List<String> _collectStrings(
    Map<String, ThrowsCacheEntry> entries,
  ) {
    final set = <String>{};
    for (final entry in entries.values) {
      set.addAll(entry.thrown);
      for (final provList in entry.provenance.values) {
        for (final prov in provList) {
          set.add(prov.call);
          if (prov.origin != null) {
            set.add(prov.origin!);
          }
        }
      }
    }
    final list = set.toList()..sort();
    return list;
  }

  static bool _hasProvenance(Map<String, ThrowsCacheEntry> entries) {
    for (final entry in entries.values) {
      if (entry.provenance.isNotEmpty) return true;
    }
    return false;
  }

  static Uint8List _buildStringTable(List<String> strings) {
    final offsets = <int>[];
    final dataBuilder = BytesBuilder();
    for (final value in strings) {
      offsets.add(dataBuilder.length);
      dataBuilder.add(utf8.encode(value));
      dataBuilder.addByte(0);
    }
    final header = ByteData(4 + strings.length * 4);
    header.setUint32(0, strings.length, Endian.little);
    var cursor = 4;
    for (final offset in offsets) {
      header.setUint32(cursor, offset, Endian.little);
      cursor += 4;
    }
    final builder = BytesBuilder();
    builder.add(header.buffer.asUint8List());
    builder.add(dataBuilder.toBytes());
    return builder.toBytes();
  }

  static Uint8List _buildHeader({
    required int flags,
    required int indexOffset,
    required int indexCount,
    required int stringTableOffset,
    required int stringTableLength,
    required int dataOffset,
  }) {
    final header = ByteData(_headerSize);
    header.setUint8(0, 0x4C);
    header.setUint8(1, 0x48);
    header.setUint8(2, 0x54);
    header.setUint8(3, 0x48);
    header.setUint8(4, 0x52);
    header.setUint8(5, 0x4F);
    header.setUint8(6, 0x57);
    header.setUint8(7, 0x00);
    header.setUint32(8, 1, Endian.little);
    header.setUint32(12, flags, Endian.little);
    header.setUint64(16, indexOffset, Endian.little);
    header.setUint64(24, indexCount, Endian.little);
    header.setUint64(32, stringTableOffset, Endian.little);
    header.setUint64(40, stringTableLength, Endian.little);
    header.setUint64(48, dataOffset, Endian.little);
    header.setUint64(56, 0, Endian.little);
    return header.buffer.asUint8List();
  }

  static Uint8List _buildFooter({
    required int indexOffset,
    required int indexCount,
    required int stringTableOffset,
    required int stringTableLength,
  }) {
    final footer = ByteData(_footerSize);
    footer.setUint64(0, indexOffset, Endian.little);
    footer.setUint64(8, indexCount, Endian.little);
    footer.setUint64(16, stringTableOffset, Endian.little);
    footer.setUint64(24, stringTableLength, Endian.little);
    return footer.buffer.asUint8List();
  }
}

const _headerSize = 64;
const _footerSize = 32;
const _indexRecordSize = 32;

class _RecordMeta {
  final int offset;
  final int length;
  final int keyLength;

  _RecordMeta({
    required this.offset,
    required this.length,
    required this.keyLength,
  });
}

class _IndexRecordWrite {
  final int keyHash;
  final int recordOffset;
  final int recordLength;
  final int recordKeyLength;

  _IndexRecordWrite({
    required this.keyHash,
    required this.recordOffset,
    required this.recordLength,
    required this.recordKeyLength,
  });
}

File _tempFileFor(File file) {
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final name = '${file.uri.pathSegments.last}.$stamp.tmp';
  return File(p.join(file.parent.path, name));
}
