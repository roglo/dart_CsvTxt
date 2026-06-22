//
// Display any text, images and pdf file.
// For csv files, display it in aligned columns.
//

import 'dart:async';
import 'dart:convert';
import "dart:io";
import "dart:math";
import "dart:ui";
import 'package:archive/archive.dart';
import "package:file_picker/file_picker.dart";
import 'package:flutter/foundation.dart';
import "package:flutter/material.dart";
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';

import "picker.dart";
import "find_sep.dart";

const double _initialFontSize = 14;

extension BytesUtils on Uint8List {
  bool startsWith(int shift, List<int> prefix) {
    if (length < shift + prefix.length) return false;
    for (int i = 0; i < prefix.length; i++) {
      if (this[shift + i] != prefix[i]) return false;
    }
    return true;
  }
}

String normalizeString(String input) {
  // Replace common accented characters with their base equivalents
  return input
      .toLowerCase()
      .replaceAll(RegExp(r'[áàâäãå]'), 'a')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[îï]'), 'i')
      .replaceAll(RegExp(r'[ôöõø]'), 'o')
      .replaceAll(RegExp(r'[œ]'), 'oe')
      .replaceAll(RegExp(r'[ùûü]'), 'u')
      .replaceAll(RegExp(r'[ç]'), 'c');
}

int compareElements(
  (int, CsvLine) a,
  (int, CsvLine) b,
  bool isNumber,
  int index,
) {
  final valueA = a.$2.$1[index];
  final valueB = b.$2.$1[index];

  if (isNumber) {
    final numA = double.tryParse(valueA) ?? 0;
    final numB = double.tryParse(valueB) ?? 0;
    final comparison = numA.compareTo(numB);
    return comparison == 0 ? a.$1.compareTo(b.$1) : comparison;
  } else {
    // Normalize strings for accent and case-insensitive comparison
    final normalizedA = normalizeString(valueA);
    final normalizedB = normalizeString(valueB);
    final comparison = normalizedA.compareTo(normalizedB);
    return comparison == 0 ? a.$1.compareTo(b.$1) : comparison;
  }
}

String readString(Uint8List b, int offset, int len) {
  final end = b.indexOf(0, offset).clamp(offset, offset + len);
  return String.fromCharCodes(b.sublist(offset, end));
}

void myprint(String txt) {
  //  print(txt);
  stdout.write("$txt\n");
}

enum FileType { txt, csv, image, pdf, tar, tooBig }

class GzipReader {
  final StreamIterator<List<int>> _iterator;
  int _pos = 0;
  final _buffer = <int>[];

  GzipReader._(this._iterator);

  static Future<GzipReader> open(String path) async {
    final stream = File(path).openRead().transform(GZipCodec().decoder);
    final iterator = StreamIterator(stream);
    return GzipReader._(iterator);
  }

  Future<Uint8List> readAt(int offset, int size) async {
    while (_pos < offset) {
      if (_buffer.isEmpty) {
        if (!await _iterator.moveNext()) break;
        _buffer.addAll(_iterator.current);
      }
      final skip = min(offset - _pos, _buffer.length);
      _buffer.removeRange(0, skip);
      _pos += skip;
    }

    final result = <int>[];
    while (result.length < size) {
      if (_buffer.isEmpty) {
        if (!await _iterator.moveNext()) break;
        _buffer.addAll(_iterator.current);
      }
      final take = min(size - result.length, _buffer.length);
      result.addAll(_buffer.sublist(0, take));
      _buffer.removeRange(0, take);
      _pos += take;
    }

    return Uint8List.fromList(result);
  }

  Future<void> close() async {
    await _iterator.cancel();
  }
}

String parseTarString(Uint8List bytes, int offset, int length) {
  final sub = bytes.sublist(offset, offset + length);
  final end = sub.indexOf(0);
  return utf8.decode(end == -1 ? sub : sub.sublist(0, end));
}

typedef TarEntry = ({
  String tperm,
  String uname,
  String gname,
  int size,
  String fname,
  int type,
  int contentStartPos,
  String tarFilePath,
  bool tarFileIsGz,
});

Future<Uint8List> readFilePart(String filePath, int pos, int size) async {
  final file = File(filePath);
  final raf = await file.open(mode: FileMode.read);
  try {
    await raf.setPosition(pos);
    final buffer = Uint8List(size);
    final bytesRead = await raf.readInto(buffer);
    if (bytesRead != size) {
      throw Exception("Impossible de lire $size octets à partir de $pos");
    }
    return buffer;
  } finally {
    await raf.close();
  }
}

typedef States = ({
  BuildContext Function() getContext,
  String Function() getLang,
  String? Function() getInitialDir,
  String? Function() getFileName,
  String? Function() getFileContent,
  Uint8List? Function() getBytes,
  List<TarEntry> Function() getTarList,
  List<CsvLine> Function() getCsvLines,
  int Function() getCurrentPage,
  FileType? Function() getFileType,
  double Function() getFontSize,
  bool Function() getModeFixe,
  bool Function() getNewVersion,
  bool Function() getLoading,
  int Function() getPdfLoadCount,
  ScrollController Function() getVScrollController,
  ScrollController Function() getHScrollController,
  PdfViewerController Function() getPdfController,
  Color? Function(int) getTextColorList1,
  Color? Function(int) getTextColorList2,
  void Function(int) setCurrentPage,
  void Function(List<CsvLine>) setCsvLines,
  void Function(double) setFontSize,
  void Function(bool) setLoading,
  void Function(int, Color) setTextColorList1,
  void Function(int, Color) setTextColorList2,
  void Function() sync,
});

Widget _buildRowButtonSizeAndJump(States _st) {
  final FileType? _fileType = _st.getFileType();
  final double _fontSize = _st.getFontSize();
  final ScrollController _vScrollController = _st.getVScrollController();
  final PdfViewerController _pdfController = _st.getPdfController();
  final _setFontSize = _st.setFontSize;
  return Row(
    children: [
      if (_fileType == FileType.pdf) ...[
        ElevatedButton(
          onPressed: () => _pdfController.goToPage(pageNumber: 1),
          child: const Text("«"),
        ),
        const SizedBox(width: 16),
        Text("${_st.getCurrentPage()}"),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: () {
            final last = _pdfController.pageCount;
            _pdfController.goToPage(pageNumber: last);
          },
          child: const Text("»"),
        ),
      ] else ...[
        ElevatedButton(
          onPressed: () {
            _setFontSize(_fontSize - 1);
            _st.sync();
          },
          child: const Text("A-"),
        ),
        ElevatedButton(
          onPressed: () {
            _setFontSize(_initialFontSize);
            _st.sync();
          },
          child: const Text("A"),
        ),
        ElevatedButton(
          onPressed: () {
            _setFontSize(_fontSize + 1);
            _st.sync();
          },
          child: const Text("A+"),
        ),
        ElevatedButton(
          onPressed: () => _vScrollController.jumpTo(0),
          child: const Text("«"),
        ),
        ElevatedButton(
          onPressed: () => _vScrollController.jumpTo(
            _vScrollController.position.maxScrollExtent,
          ),
          child: const Text("»"),
        ),
      ],
    ],
  );
}

Widget _buildColumnButtonsJump(States _st) {
  final FileType? _fileType = _st.getFileType();
  final int _currentPage = _st.getCurrentPage();
  final ScrollController _vScrollController = _st.getVScrollController();
  final PdfViewerController _pdfController = _st.getPdfController();
  return Column(
    children: [
      if (_fileType == FileType.pdf) ...[
        ElevatedButton(
          onPressed: () => _pdfController.goToPage(pageNumber: 1),
          child: const Text("«"),
        ),
        const SizedBox(width: 16),
        Text("$_currentPage"),
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: () {
            final last = _pdfController.pageCount;
            _pdfController.goToPage(pageNumber: last);
          },
          child: const Text("»"),
        ),
      ] else ...[
        ElevatedButton(
          onPressed: () => _vScrollController.jumpTo(0),
          child: const Text("«"),
        ),
        ElevatedButton(
          onPressed: () => _vScrollController.jumpTo(
            _vScrollController.position.maxScrollExtent,
          ),
          child: const Text("»"),
        ),
      ],
    ],
  );
}

String tPerm(Uint8List bytes) {
  final modeStr = parseTarString(bytes, 100, 8);
  final mode = int.parse(modeStr.trim(), radix: 8);
  final typeChar = switch (bytes[156]) {
    53 => 'd', // '5'
    50 => 'l', // '2' symlink
    _ => '-',
  };
  final perms = [
    mode & 0x100 != 0 ? 'r' : '-',
    mode & 0x080 != 0 ? 'w' : '-',
    mode & 0x040 != 0 ? 'x' : '-',
    mode & 0x020 != 0 ? 'r' : '-',
    mode & 0x010 != 0 ? 'w' : '-',
    mode & 0x008 != 0 ? 'x' : '-',
    mode & 0x004 != 0 ? 'r' : '-',
    mode & 0x002 != 0 ? 'w' : '-',
    mode & 0x001 != 0 ? 'x' : '-',
  ].join();
  return "$typeChar$perms";
}

Future<List<TarEntry>> _parseTarGz(States _st, String path) async {
  final tarList = <TarEntry>[];
  final _getLoading = _st.getLoading;
  Uint8List? bytes;
  int pos = 0;
  final reader = await GzipReader.open(path);
  String? pendingLongName;
  try {
    while (_getLoading()) {
      bytes = await reader.readAt(pos, 512);
      final ended = bytes[0];
      if (ended == 0) break;
      final elemName = parseTarString(bytes, 0, 100);
      final sizeStr = readString(bytes, 124, 12);
      final size = int.parse(sizeStr.trim(), radix: 8);
      final type = bytes[156];
      final tperm = tPerm(bytes);
      final uname = parseTarString(bytes, 265, 32);
      final gname = parseTarString(bytes, 297, 32);
      final dataBlocks = (size + 511) ~/ 512;
      if (elemName == '././@LongLink') {
        final nameBytes = <int>[];
        for (int i = 0; i < dataBlocks; i++) {
          final block = await reader.readAt(pos + (i + 1) * 512, 512);
          nameBytes.addAll(block);
        }
        pendingLongName = utf8.decode(
          nameBytes.sublist(0, nameBytes.indexOf(0)),
          allowMalformed: true,
        );
      }
      final realName = pendingLongName ?? elemName;
      pendingLongName = null;
      tarList.add((
        tperm: tperm,
        uname: uname,
        gname: gname,
        size: size,
        fname: realName,
        type: type,
        contentStartPos: pos + 512,
        tarFilePath: path,
        tarFileIsGz: true,
      ));
      pos += 512 + dataBlocks * 512;
    }
  } finally {
    await reader.close();
  }
  return tarList;
}

Future<List<TarEntry>> _parseTar(String path) async {
  final tarList = <TarEntry>[];
  final bytes = await File(path).readAsBytes();
  int pos = 0;
  while (pos + 512 <= bytes.length) {
    if (bytes[pos] == 0) break;
    final name = readString(bytes, pos, 100);
    final sizeStr = readString(bytes, pos + 124, 12);
    final size = int.parse(sizeStr.trim(), radix: 8);
    final type = bytes[pos + 156];
    final tperm = tPerm(bytes);
    final uname = parseTarString(bytes, 265, 32);
    final gname = parseTarString(bytes, 297, 32);
    tarList.add((
      tperm: tperm,
      uname: uname,
      gname: gname,
      size: size,
      fname: name,
      type: type,
      contentStartPos: pos + 512,
      tarFilePath: path,
      tarFileIsGz: false,
    ));
    pos += 512 + ((size + 511) ~/ 512) * 512;
  }
  return tarList;
}

Future<void> _filePicked(
  States _st,
  String path,
  String? name,
  void Function(FileType, String?, Uint8List?, String?, List<TarEntry>)
  _setState,
) async {
  final ScrollController _vScrollController = _st.getVScrollController();
  final ScrollController _hScrollController = _st.getHScrollController();
  final _setLoading = _st.setLoading;
  if (_vScrollController.hasClients) {
    _vScrollController.jumpTo(0);
  }
  if (_hScrollController.hasClients) {
    _hScrollController.jumpTo(0);
  }
  //
  final chunks = <int>[];
  await for (final chunk in File(path).openRead()) {
    chunks.addAll(chunk);
    if (chunks.length >= 1024) break;
  }
  final beginning = Uint8List.fromList(
    chunks.sublist(0, min(1024, chunks.length)),
  );
  Uint8List? header;
  bool isGzip = false;
  if (beginning.startsWith(0, [0x1F, 0x8B])) {
    isGzip = true;
    final reader = await GzipReader.open(path);
    try {
      header = await reader.readAt(0, 512);
    } finally {
      await reader.close();
    }
  } else {
    final bytes = await File(path).openRead(0, 512).first;
    header = Uint8List.fromList(bytes);
  }
  bool isGif = header.startsWith(0, [0x47, 0x49, 0x46]);
  bool isPng = header.startsWith(0, [0x89, 0x50, 0x4E]);
  bool isJpeg = header.startsWith(0, [0xFF, 0xD8]);
  final isImage = isGif || isPng || isJpeg;
  if (isImage) {
    Uint8List? bytes;
    if (isGzip) {
      final zbytes = await File(path).readAsBytes();
      bytes = Uint8List.fromList(GZipDecoder().decodeBytes(zbytes));
    } else {
      bytes = await File(path).readAsBytes();
    }
    _setState(FileType.image, name, bytes, null, []);
  } else if (header.startsWith(0, [0x25, 0x50, 0x44, 0x46])) {
    Uint8List? bytes;
    if (isGzip) {
      final zbytes = await File(path).readAsBytes();
      bytes = Uint8List.fromList(GZipDecoder().decodeBytes(zbytes));
    } else {
      bytes = await File(path).readAsBytes();
    }
    _setState(FileType.pdf, name, bytes, null, []);
  } else if (header.startsWith(257, [0x75, 0x73, 0x74, 0x61, 0x72])) {
    List<TarEntry> tarList = [];
    if (isGzip) {
      _setLoading(true);
      await Future.delayed(Duration(milliseconds: 200));
      tarList = await _parseTarGz(_st, path);
      _setLoading(false);
    } else {
      tarList = await _parseTar(path);
    }
    _setState(FileType.tar, name, null, null, tarList);
  } else {
    Uint8List? bytes;
    if (isGzip) {
      final zbytes = await File(path).readAsBytes();
      bytes = Uint8List.fromList(GZipDecoder().decodeBytes(zbytes));
    } else {
      bytes = await File(path).readAsBytes();
    }
    final s = utf8.decode(bytes);
    final content = s.isNotEmpty && !s.endsWith("\n") ? "$s\n" : s;
    final extension = name == null ? "" : name.split(".").last.toLowerCase();
    final ft = (extension == "csv") ? FileType.csv : FileType.txt;
    _setState(ft, name, null, content, []);
  }
}

// ignore: unused_element
Future<String?> _pickFile(
  States _st,
  void Function(FileType, String?, Uint8List?, String?, List<TarEntry>)
  _setState,
) async {
  final result = await FilePicker.platform.pickFiles();
  if (result != null && result.files.single.path != null) {
    final path = result.files.single.path!;
    final name = result.files.single.name;
    _filePicked(_st, path, name, _setState);
    myprint(path);
    return path;
  }
  return null;
}

String _t(String _lang, String fr, String en) => _lang == "fr" ? fr : en;

Widget _buildButtonsChooseFile(
  States _st,
  String? _errorMessage,
  void Function(String) _setPickedFileState,
  void Function(FileType, String?, Uint8List?, String?, List<TarEntry>)
  _setState,
  void Function() _switchModeFixe,
) {
  final BuildContext context = _st.getContext();
  final String _lang = _st.getLang();
  final String? _initialDir = _st.getInitialDir();
  final String? _fileName = _st.getFileName();
  final FileType? _fileType = _st.getFileType();
  return Row(
    children: [
      ElevatedButton(
        child: Text(_t(_lang, "Choisir un fichier", "Choose a file")),
        onPressed: () async {
          final String? path = Platform.isLinux
              // ? await _pickFile()
              ? await customPickFile(context, _initialDir)
              : await _pickFile(_st, _setState);
          // : await customPickFile(context, _initialDir);
          if (path != null) {
            final name = path.split("/").last;
            _setPickedFileState(path);
            _filePicked(_st, path, name, _setState);
          }
        },
      ),
      if (_fileName != null &&
          _fileType != FileType.image &&
          _fileType != FileType.pdf &&
          _fileType != FileType.tar &&
          _errorMessage == null) ...[
        const SizedBox(width: 16),
        ElevatedButton(
          onPressed: () => _switchModeFixe(),
          child: Text(_st.getModeFixe() ? "Mode normal" : "Mode fixe"),
        ),
      ],
    ],
  );
}

TextStyle _fixedTextStyle(double _fontSize, {Color color = Colors.black}) {
  return TextStyle(
    fontFamily: "Courier",
    fontSize: _fontSize,
    fontWeight: FontWeight.bold,
    color: color,
  );
}

List<(String, String)> _csvFormatLine(String def, String line) {
  final List<String> defs = def
      .substring(1, def.length - 1)
      .replaceAll(RegExp(r"\s+"), " ")
      .split("|");
  final List<String> lines = line
      .substring(1, line.length - 1)
      .replaceAll(RegExp(r"\s+"), " ")
      .split("|");
  final List<(String, String)> s = defs.asMap().entries.map((entry) {
    return (
      entry.value.trimRight(),
      entry.key < lines.length ? lines[entry.key].trimRight() : "",
    );
  }).toList();
  return s;
}

Widget _fixedView(States _st) {
  final String _content = _st.getFileContent()!;
  final double _fontSize = _st.getFontSize();
  final ScrollController _vScrollController = _st.getVScrollController();
  final ScrollController _hScrollController = _st.getHScrollController();
  return SingleChildScrollView(
    controller: _vScrollController,
    scrollDirection: Axis.vertical,
    child: SingleChildScrollView(
      controller: _hScrollController,
      scrollDirection: Axis.horizontal,
      child: Text(_content, style: _fixedTextStyle(_fontSize)),
    ),
  );
}

List<CsvLine> _actionClickOnCsvHeaderLine(
  List<CsvLine> _csvLines,
  int index,
  String txt,
) {
  bool isNumber = true;
  for (int i = 1; i < _csvLines.length - 1; i++) {
    if (double.tryParse(_csvLines[i].$1[index]) == null) {
      isNumber = false;
      break;
    }
  }
  // add the index to make the sort stable
  final csvLinesIndexed = _csvLines.asMap().entries.map((entry) {
    return (entry.key, entry.value);
  }).toList();

  bool isAlreadySorted = true;
  for (int i = 1; i < _csvLines.length - 1; i++) {
    if (compareElements(
          csvLinesIndexed[i],
          csvLinesIndexed[i + 1],
          isNumber,
          index,
        ) >
        0) {
      isAlreadySorted = false;
      break;
    }
  }
  final firstElement = _csvLines.first;
  final sublist = csvLinesIndexed.sublist(1);
  sublist.sort((a, b) {
    final comparison = compareElements(a, b, isNumber, index);
    return isAlreadySorted ? -comparison : comparison;
  });
  final r = [firstElement, ...sublist.map((kv) => kv.$2)];
  return r;
}

void _actionClickOnCsvLine(States _st, String def, String line) {
  final BuildContext context = _st.getContext();
  final double _fontSize = _st.getFontSize();
  final List<(String, String)> s = _csvFormatLine(def, line);
  showDialog(
    context: context,
    builder: (context) => AlertDialog(
      title: Text("Ligne sélectionnée"),
      content: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Text.rich(
            TextSpan(
              children: s
                  .map(
                    (line) => TextSpan(
                      text: line.$1,
                      style: TextStyle(
                        fontSize: _fontSize,
                        fontWeight: FontWeight.bold,
                      ),
                      children: [
                        TextSpan(
                          text: ": ${line.$2}\n",
                          style: TextStyle(
                            fontSize: _fontSize,
                            fontWeight: FontWeight.normal,
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("Fermer"),
        ),
      ],
    ),
  );
}

void _openFile(
  States _st,
  String file,
  void Function(String) _setPickedFileState,
  void Function(FileType, String?, Uint8List?, String?, List<TarEntry>)
  _setState,
) {
  final name = file.split("/").last;
  _setPickedFileState(file);
  _filePicked(_st, file, name, _setState);
}

Future<void> _actionClickOnTarFileName(
  States _st,
  TarEntry entry,
  void Function(FileType, String?, Uint8List?, String?, List<TarEntry>)
  _setState,
  void Function(String?, String) _setStateError,
) async {
  final ScrollController _vScrollController = _st.getVScrollController();
  final ScrollController _hScrollController = _st.getHScrollController();
  final String tarFileName = entry.tarFilePath.split("/").last;
  _vScrollController.jumpTo(0);
  _hScrollController.jumpTo(0);
  if (entry.type == 53) {
    final fileName = entry.fname;
    _setStateError(
      "$fileName ($tarFileName)",
      "C\'est un répertoire, pas un fichier",
    );
  } else {
    final String fileName = entry.fname.split("/").last;
    Uint8List? bytes;
    if (entry.tarFileIsGz) {
      final reader = await GzipReader.open(entry.tarFilePath);
      try {
        bytes = await reader.readAt(entry.contentStartPos, entry.size);
      } finally {
        await reader.close();
      }
    } else {
      bytes = await readFilePart(
        entry.tarFilePath,
        entry.contentStartPos,
        entry.size,
      );
    }
    final content = utf8.decode(bytes);
    _setState(FileType.txt, "$fileName ($tarFileName)", null, content, []);
  }
}

Widget _clickOnCsvHeaderLine(States _st, int index, String txt) {
  final List<CsvLine> _csvLines = _st.getCsvLines();
  final _setCsvLines = _st.setCsvLines;
  final _setTextColorList1 = _st.setTextColorList1;
  return GestureDetector(
    onTap: () {
      _setTextColorList1(index, Colors.grey[300] ?? Colors.grey);
      _st.sync();
      Future.delayed(const Duration(milliseconds: 100), () {
        _setCsvLines(_actionClickOnCsvHeaderLine(_csvLines, index, txt));
        _setTextColorList1(index, Colors.blue);
        _st.sync();
      });
    },
    child: Text(
      txt,
      style: _fixedTextStyle(
        _st.getFontSize(),
        color: _st.getTextColorList1(index) ?? Colors.blue,
      ),
    ),
  );
}

List<Widget> _buildFirstLineColumnChildren(States _st) {
  final List<CsvLine> _csvLines = _st.getCsvLines();
  final (leftList, rightLists) = _csvLines.first;
  return rightLists.map((rightList) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      children: [
        Text("|", style: _fixedTextStyle(_st.getFontSize())),
        ...rightList.asMap().entries.map((entry) {
          final int index = entry.key;
          final String txt = entry.value;
          return Row(
            mainAxisAlignment: MainAxisAlignment.start,
            children: [
              _clickOnCsvHeaderLine(_st, index, txt),
              Text("|", style: _fixedTextStyle(_st.getFontSize())),
            ],
          );
        }),
      ],
    );
  }).toList();
}

Widget _clickOnCsvLine(
  States _st,
  int index,
  String def,
  String line,
  String txt,
) {
  final double _fontSize = _st.getFontSize();
  final _setTextColorList2 = _st.setTextColorList2;
  return GestureDetector(
    onTap: () {
      _setTextColorList2(index, Colors.grey[300] ?? Colors.grey);
      _st.sync();
      Future.delayed(const Duration(milliseconds: 300), () {
        _setTextColorList2(index, Colors.blue);
        _st.sync();
        _actionClickOnCsvLine(_st, def, line);
      });
    },
    child: Text(
      txt,
      style: _fixedTextStyle(
        _fontSize,
        color: _st.getTextColorList2(index) ?? Colors.blue,
      ),
    ),
  );
}

List<Widget> _buildColumnChildren(States _st) {
  final double _fontSize = _st.getFontSize();
  final List<CsvLine> _csvLines = _st.getCsvLines();
  final String firstLine = "|${_csvLines.first.$1.join('|')}|";
  return _csvLines.sublist(1).asMap().entries.expand((entry) {
    final index = entry.key;
    final (leftList, rightLists) = entry.value;
    return rightLists.map((rightList) {
      final firstField = rightList.first;
      final allOtherFields = rightList.sublist(1);
      final currentLine = "|${leftList.join('|')}|";
      return Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text("|", style: _fixedTextStyle(_fontSize)),
          _clickOnCsvLine(_st, index, firstLine, currentLine, firstField),
          Text(
            "|${allOtherFields.join('|')}|",
            style: _fixedTextStyle(_fontSize),
          ),
        ],
      );
    });
  }).toList();
}

Widget _clickOnTarFileName(
  States _st,
  int index,
  TarEntry entry,
  void Function(FileType, String?, Uint8List?, String?, List<TarEntry>)
  _setState,
  void Function(String?, String) _setStateError,
) {
  final double _fontSize = _st.getFontSize();
  return GestureDetector(
    onTap: () {
      _st.setTextColorList1(index, Colors.grey[300] ?? Colors.grey);
      _st.sync();
      Future.delayed(const Duration(milliseconds: 100), () {
        _st.setTextColorList1(index, Colors.blue);
        _st.sync();
        _actionClickOnTarFileName(_st, entry, _setState, _setStateError);
      });
    },
    child: Text(
      entry.fname,
      style: _fixedTextStyle(
        _fontSize,
        color: _st.getTextColorList1(index) ?? Colors.blue,
      ),
    ),
  );
}

Widget _fixedCsvView(States _st) {
  List<CsvLine> _csvLines = _st.getCsvLines();
  final double _fontSize = _st.getFontSize();
  final ScrollController _vScrollController = _st.getVScrollController();
  final ScrollController _hScrollController = _st.getHScrollController();
  if (_csvLines.isEmpty) {
    _st.setCsvLines(treatCsv(_st.getFileContent()!, _st.getNewVersion()));
    _st.sync();
  }
  _csvLines = _st.getCsvLines();
  final length =
      _csvLines.first.$2.first.fold(0, (a, s) => a + s.length) +
      _csvLines.first.$2.first.length +
      1;
  final border = "-" * length;
  return SingleChildScrollView(
    controller: _hScrollController,
    scrollDirection: Axis.horizontal,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(border, style: _fixedTextStyle(_fontSize)),
        ..._buildFirstLineColumnChildren(_st),
        Text(border, style: _fixedTextStyle(_fontSize)),
        Expanded(
          child: SingleChildScrollView(
            controller: _vScrollController,
            scrollDirection: Axis.vertical,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ..._buildColumnChildren(_st),
                Text(border, style: _fixedTextStyle(_fontSize)),
                Text(""),
                Text(""),
                Text(""),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

Widget _parseWithItalics(States _st) {
  final String content = _st.getFileContent()!;
  return Text.rich(
    TextSpan(
      children: content.split("*").asMap().entries.expand((v) {
        final int i = v.key;
        final String txt = v.value;
        return txt.split("_").asMap().entries.map((w) {
          final int j = w.key;
          final String txt2 = w.value;
          return TextSpan(
            text: txt2,
            style: TextStyle(
              fontSize: _st.getFontSize(),
              fontWeight: (i % 2 == 1) ? FontWeight.bold : FontWeight.normal,
              fontStyle: (j % 2 == 1) ? FontStyle.italic : FontStyle.normal,
            ),
          );
        });
      }).toList(),
    ),
  );
}

Widget _normalView(States _st, String? fileName) {
  final String content = _st.getFileContent()!;
  return SingleChildScrollView(
    controller: _st.getVScrollController(),
    child: SingleChildScrollView(
      controller: _st.getHScrollController(),
      scrollDirection: Axis.horizontal,
      child: fileName != null && fileName.endsWith(".txt")
          ? _parseWithItalics(_st)
          : Text(content, style: TextStyle(fontSize: _st.getFontSize())),
    ),
  );
}

List<Widget> _buildContent(
  States _st,
  void Function(FileType, String?, Uint8List?, String?, List<TarEntry>)
  _setState,
  void Function(String?, String) _setStateError,
) {
  final BuildContext context = _st.getContext();
  final String? _fileContent = _st.getFileContent();
  final Uint8List? _bytes = _st.getBytes();
  final FileType? _fileType = _st.getFileType();
  final String? _fileName = _st.getFileName();
  final double _fontSize = _st.getFontSize();
  final int _currentPage = _st.getCurrentPage();
  final int _pdfLoadCount = _st.getPdfLoadCount();
  final PdfViewerController _pdfController = _st.getPdfController();
  final _setTextColorList1 = _st.setTextColorList1;
  final _setTextColorList2 = _st.setTextColorList2;
  return [
    if (_fileType == FileType.image)
      ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width,
          maxHeight: MediaQuery.of(context).size.height,
        ),
        child: InteractiveViewer(
          minScale: 0.1,
          maxScale: 4.0,
          constrained: true,
          child: Image.memory(_bytes!, fit: BoxFit.contain),
        ),
      )
    else if (_fileType == FileType.pdf)
      Expanded(
        child: PdfViewer.data(
          _bytes!,
          key: ValueKey(_fileName == null ? "1" : "$_fileName-$_pdfLoadCount"),
          sourceName: _fileName == null ? "" : _fileName,
          controller: _pdfController,
          initialPageNumber: _currentPage,
          params: PdfViewerParams(
            scrollByMouseWheel: 1.0,
            onPageChanged: (page) {
              _st.setCurrentPage(page!);
              _st.sync();
            },
          ),
        ),
      )
    else if (_fileType == FileType.tar)
      Expanded(
        child: SingleChildScrollView(
          controller: _st.getVScrollController(),
          child: SingleChildScrollView(
            controller: _st.getHScrollController(),
            scrollDirection: Axis.horizontal,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _st.getTarList().asMap().entries.map((entry) {
                final file = entry.value;
                return Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    Text(file.tperm, style: _fixedTextStyle(_fontSize)),
                    Text(" ", style: _fixedTextStyle(_fontSize)),
                    Text(file.uname, style: _fixedTextStyle(_fontSize)),
                    Text("/", style: _fixedTextStyle(_fontSize)),
                    Text(file.gname, style: _fixedTextStyle(_fontSize)),
                    Text(" ", style: _fixedTextStyle(_fontSize)),
                    Text(
                      file.size.toString().padLeft(8),
                      style: _fixedTextStyle(_fontSize),
                    ),
                    Text(" ", style: _fixedTextStyle(_fontSize)),
                    _clickOnTarFileName(
                      _st,
                      entry.key,
                      file,
                      _setState,
                      _setStateError,
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      )
    else if (_fileContent != null)
      Expanded(
        child: _st.getModeFixe()
            ? (_fileType == FileType.csv ? _fixedCsvView(_st) : _fixedView(_st))
            : _normalView(_st, _fileName),
      ),
  ];
}

class _FilePickerScreenState extends State<FilePickerScreen> {
  final String _lang = PlatformDispatcher.instance.locale.languageCode;
  // final String _lang = "en"; // ← force l'anglais pour tester
  final ScrollController _vScrollController = ScrollController();
  final ScrollController _hScrollController = ScrollController();
  late PdfViewerController _pdfController;
  int _currentPage = 1;
  int _pdfLoadCount = 0;
  bool _dirFromButton = true;
  String? _initialDir;
  String? _fileName;
  String? _fileContent;
  List<CsvLine> _csvLines = [];
  FileType? _fileType;
  Uint8List? _bytes;
  List<TarEntry> _tarList = [];
  String? _errorMessage;
  bool _loading = false;
  bool _newVersion = true;
  bool _modeFixe = false;
  double _fontSize = _initialFontSize;
  final Map<int, Color> _textColorsList1 = {};
  final Map<int, Color> _textColorsList2 = {};

  void _setPickedFileState(String file) {
    setState(() {
      _initialDir = file.substring(0, file.lastIndexOf("/"));
      _currentPage = 1;
      _pdfLoadCount++;
      _fontSize = _initialFontSize;
    });
  }

  @override
  void initState() {
    super.initState();
    _pdfController = PdfViewerController();
    if (widget.initialFile != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        setState(() {
          _dirFromButton = false;
        });
        _openFile(_st, widget.initialFile!, _setPickedFileState, _setState);
      });
    }
  }

  @override
  void dispose() {
    _vScrollController.dispose();
    _hScrollController.dispose();
    //    _pdfController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pdfController = PdfViewerController();
  }

  void _setStateError(String? filename, String msg) {
    _fileType = FileType.txt;
    _fileName = filename;
    _fileContent = null;
    _bytes = null;
    _errorMessage = msg;
    setState(() {});
  }

  void _setState(
    FileType ft,
    String? name,
    Uint8List? bytes,
    String? fileContent,
    List<TarEntry> tarList,
  ) {
    _fileType = ft;
    _modeFixe = (ft == FileType.csv ? true : false);
    _fileName = name;
    _bytes = bytes;
    _fileContent = fileContent;
    _csvLines = [];
    _tarList = tarList;
    _errorMessage = null;
    setState(() {});
  }

  void _switchModeFixe() {
    setState(() => _modeFixe = !_modeFixe);
  }

  BuildContext _getContext() => context;
  String _getLang() => _lang;
  String? _getInitialDir() => _initialDir;
  String? _getFileName() => _fileName;
  String? _getFileContent() => _fileContent;
  Uint8List? _getBytes() => _bytes;
  List<TarEntry> _getTarList() => _tarList;
  List<CsvLine> _getCsvLines() => _csvLines;
  int _getCurrentPage() => _currentPage;
  FileType? _getFileType() => _fileType;
  double _getFontSize() => _fontSize;
  bool _getModeFixe() => _modeFixe;
  bool _getNewVersion() => _newVersion;
  bool _getLoading() => _loading;
  int _getPdfLoadCount() => _pdfLoadCount;
  ScrollController _getVScrollController() => _vScrollController;
  ScrollController _getHScrollController() => _hScrollController;
  PdfViewerController _getPdfController() => _pdfController;
  Color? _getTextColorList1(int i) => _textColorsList1[i];
  Color? _getTextColorList2(int i) => _textColorsList2[i];

  void _setCsvLines(List<CsvLine> _newCsvLines) => _csvLines = _newCsvLines;
  void _setCurrentPage(int page) => _currentPage = page;

  void _setFontSize(double newFontSize) {
    final double oldFontSize = _fontSize;
    final double oldOffset = _vScrollController.offset;
    _fontSize = newFontSize.clamp(8.0, 40.0);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final double ratio = _fontSize / oldFontSize;
      final double newOffset = (oldOffset * ratio).clamp(
        0.0,
        _vScrollController.position.maxScrollExtent,
      );
      _vScrollController.jumpTo(newOffset);
    });
  }

  void _setLoading(bool loading) => _loading = loading;
  void _setTextColorList1(int index, Color color) =>
      _textColorsList1[index] = color;
  void _setTextColorList2(int index, Color color) =>
      _textColorsList2[index] = color;
  void _sync() => setState(() {});

  late States _st = (
    getContext: _getContext,
    getLang: _getLang,
    getInitialDir: _getInitialDir,
    getFileName: _getFileName,
    getFileContent: _getFileContent,
    getBytes: _getBytes,
    getTarList: _getTarList,
    getCsvLines: _getCsvLines,
    getCurrentPage: _getCurrentPage,
    getFileType: _getFileType,
    getFontSize: _getFontSize,
    getModeFixe: _getModeFixe,
    getNewVersion: _getNewVersion,
    getLoading: _getLoading,
    getPdfLoadCount: _getPdfLoadCount,
    getVScrollController: _getVScrollController,
    getHScrollController: _getHScrollController,
    getPdfController: _getPdfController,
    getTextColorList1: _getTextColorList1,
    getTextColorList2: _getTextColorList2,
    setCsvLines: _setCsvLines,
    setCurrentPage: _setCurrentPage,
    setFontSize: _setFontSize,
    setLoading: _setLoading,
    setTextColorList1: _setTextColorList1,
    setTextColorList2: _setTextColorList2,
    sync: _sync,
  );

  Widget _buildNormal() {
    if (Platform.isLinux ||
        MediaQuery.of(context).orientation == Orientation.portrait) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          if (_dirFromButton)
            _buildButtonsChooseFile(
              _st,
              _errorMessage,
              _setPickedFileState,
              _setState,
              _switchModeFixe,
            ),
          if ((!_dirFromButton || _fileName != null) &&
              _fileType != FileType.image &&
              _errorMessage == null) ...[
            const SizedBox(width: 16),
            _buildRowButtonSizeAndJump(_st),
          ],
          const SizedBox(height: 16),
          if (_fileName != null)
            Text(
              "Fichier : $_fileName",
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          const SizedBox(height: 8),
          if (_errorMessage != null)
            Text(_errorMessage!, style: const TextStyle(color: Colors.red)),

          const SizedBox(height: 8),
          ..._buildContent(_st, _setState, _setStateError),
          if (_fileContent != null && _fileType == FileType.csv && _modeFixe)
            ElevatedButton(
              onPressed: () => setState(() {
                _newVersion = !_newVersion;
                _csvLines = [];
              }),
              child: Text(
                _newVersion ? "Une ligne par entrée" : "Colonnes courtes",
              ),
            ),
        ],
      );
    } else {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._buildContent(_st, _setState, _setStateError),
          if ((!_dirFromButton || _fileName != null) &&
              _fileType != FileType.image &&
              _errorMessage == null) ...[
            const SizedBox(height: 16),
            _buildColumnButtonsJump(_st),
          ],
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Center(child: LinearProgressIndicator()),
                Text("merci de patienter..."),
                ElevatedButton(
                  onPressed: () {
                    _setLoading(false);
                  },
                  child: const Text("Interrompre"),
                ),
              ],
            ),
          ),
        ),
      );
    } else {
      return Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _buildNormal(),
          ),
        ),
      );
    }
  }
}

class FilePickerScreen extends StatefulWidget {
  final String? initialFile;
  const FilePickerScreen({super.key, this.initialFile});

  @override
  State<FilePickerScreen> createState() => _FilePickerScreenState();
}

class CsvTxt extends StatelessWidget {
  final String? initialFile;
  const CsvTxt({super.key, this.initialFile});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: FilePickerScreen(initialFile: initialFile));
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('app/intent');
  String? initialUri;
  try {
    initialUri = await channel.invokeMethod<String>('getInitialUri');
  } catch (_) {}

  runApp(CsvTxt(initialFile: initialUri));
}
