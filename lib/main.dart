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
      .replaceAll(RegExp(r'[àâäãå]'), 'a')
      .replaceAll(RegExp(r'[éèêë]'), 'e')
      .replaceAll(RegExp(r'[îï]'), 'i')
      .replaceAll(RegExp(r'[ôöõø]'), 'o')
      .replaceAll(RegExp(r'[ùûü]'), 'u')
      .replaceAll(RegExp(r'[ç]'), 'c');
}

int compareElements(
  (int, (List<String>, List<List<String>>)) a,
  (int, (List<String>, List<List<String>>)) b,
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

Widget _buildRowButtonSizeAndJump(
  FileType? _fileType,
  int _currentPage,
  double _fontSize,
  ScrollController _vScrollController,
  PdfViewerController _pdfController,
  void Function(double) _changeFontSize,
) {
  return Row(
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
          onPressed: () => _changeFontSize(_fontSize - 1),
          child: const Text("A-"),
        ),
        ElevatedButton(
          onPressed: () => _changeFontSize(_initialFontSize),
          child: const Text("A"),
        ),
        ElevatedButton(
          onPressed: () => _changeFontSize(_fontSize + 1),
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

Widget _buildColumnButtonsJump(
  FileType? _fileType,
  int _currentPage,
  ScrollController _vScrollController,
  PdfViewerController _pdfController,
) {
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

Future<List<TarEntry>> _parseTarGz(String path) async {
  final tarList = <TarEntry>[];
  Uint8List? bytes;
  int pos = 0;
  final reader = await GzipReader.open(path);
  String? pendingLongName;
  try {
    while (true) {
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

class _FilePickerScreenState extends State<FilePickerScreen> {
  final String _lang = PlatformDispatcher.instance.locale.languageCode;
  // final String _lang = "en"; // ← force l'anglais pour tester
  final ScrollController _vScrollController = ScrollController();
  final ScrollController _hScrollController = ScrollController();
  late PdfViewerController _pdfController;
  int _currentPage = 1;
  int _pdfLoadCount = 0;

  @override
  void initState() {
    super.initState();
    _pdfController = PdfViewerController();
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

  String _t(String fr, String en) => _lang == "fr" ? fr : en;
  String? _initialDir;
  String? _fileName;
  String? _fileContent;
  List<(List<String>, List<List<String>>)> _csvLines = [];
  FileType? _fileType;
  Uint8List? _bytes;
  List<TarEntry> _tarList = [];
  String? _errorMessage;
  bool _loading = false;
  bool _newVersion = true;
  bool _modeFixe = false;
  double _fontSize = _initialFontSize;
  final Map<int, Color> _headersTextColors = {};
  final Map<int, Color> _firstColumnTextColors = {};
  final Map<int, Color> _tarFileNameTextColors = {};

  void _changeFontSize(double newFontSize) {
    final double oldFontSize = _fontSize;
    final double oldOffset = _vScrollController.offset;

    setState(() {
      _fontSize = newFontSize.clamp(8.0, 40.0);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final double ratio = _fontSize / oldFontSize;
      final double newOffset = (oldOffset * ratio).clamp(
        0.0,
        _vScrollController.position.maxScrollExtent,
      );
      _vScrollController.jumpTo(newOffset);
    });
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

  Future<void> _filePicked(String path, String name) async {
    _fontSize = _initialFontSize;
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
      setState(() {
        _fileType = FileType.image;
        _bytes = bytes;
        _fileName = name;
        _fileContent = null;
        _csvLines = [];
        _tarList = [];
        _errorMessage = null;
      });
    } else if (header.startsWith(0, [0x25, 0x50, 0x44, 0x46])) {
      Uint8List? bytes;
      if (isGzip) {
        final zbytes = await File(path).readAsBytes();
        bytes = Uint8List.fromList(GZipDecoder().decodeBytes(zbytes));
      } else {
        bytes = await File(path).readAsBytes();
      }
      setState(() {
        _fileType = FileType.pdf;
        _fileName = name;
        _csvLines = [];
        _fileContent = null;
        _bytes = bytes;
        _tarList = [];
        _errorMessage = null;
      });
    } else if (header.startsWith(257, [0x75, 0x73, 0x74, 0x61, 0x72])) {
      List<TarEntry> tarList = [];
      if (isGzip) {
        setState(() => _loading = true);
        await Future.delayed(Duration(milliseconds: 200));
        tarList = await _parseTarGz(path);
        setState(() => _loading = false);
      } else {
        tarList = await _parseTar(path);
      }
      setState(() {
        _fileType = FileType.tar;
        _fileName = name;
        _fileContent = null;
        _bytes = null;
        _tarList = tarList;
        _errorMessage = null;
      });
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
      final extension = name.split(".").last.toLowerCase();
      _modeFixe = (extension == "csv");
      setState(() {
        _fileType = _modeFixe ? FileType.csv : FileType.txt;
        _csvLines = [];
        _fileName = name;
        _fileContent = content;
        _bytes = null;
        _tarList = [];
        _errorMessage = null;
      });
    }
  }

  // ignore: unused_element
  Future<String?> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result != null && result.files.single.path != null) {
      final path = result.files.single.path!;
      final name = result.files.single.name;
      _filePicked(path, name);
      myprint(path);
      return path;
    }
    return null;
  }

  Widget _buildButtonsChooseModeRow() {
    return Row(
      children: [
        ElevatedButton(
          child: Text(_t("Choisir un fichier", "Choose a file")),
          onPressed: () async {
            final file = Platform.isLinux
                // ? await _pickFile()
                ? await customPickFile(context, _initialDir)
                // : await _pickFile();
                : await customPickFile(context, _initialDir);
            if (file != null) {
              final name = file.split("/").last;
              setState(() {
                _initialDir = file.substring(0, file.lastIndexOf("/"));
                _currentPage = 1;
                _pdfLoadCount++;
              });
              _filePicked(file, name);
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
            onPressed: () => setState(() => _modeFixe = !_modeFixe),
            child: Text(_modeFixe ? "Mode normal" : "Mode fixe"),
          ),
        ],
      ],
    );
  }

  TextStyle fixedTextStyle({Color color = Colors.black}) {
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

  Widget _fixedView(String content) {
    return SingleChildScrollView(
      controller: _vScrollController,
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        controller: _hScrollController,
        scrollDirection: Axis.horizontal,
        child: Text(content, style: fixedTextStyle()),
      ),
    );
  }

  void _actionClickOnCsvHeaderLine(int index, String txt) {
    setState(() {
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
      _csvLines = [firstElement, ...sublist.map((kv) => kv.$2)];
    });
  }

  void _actionClickOnCsvLine(String def, String line) {
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

  Future<void> _actionClickOnTarFileName(TarEntry entry) async {
    final String tarFileName = entry.tarFilePath.split("/").last;
    _vScrollController.jumpTo(0);
    _hScrollController.jumpTo(0);
    if (entry.type == 53) {
      final fileName = entry.fname;
      setState(() {
        _fileType = FileType.txt;
        _fileName = "$fileName ($tarFileName)";
        _fileContent = null;
        _bytes = null;
        _errorMessage = "C'est un répertoire, pas un fichier";
      });
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
      setState(() {
        _fileType = FileType.txt;
        _fileName = "$fileName ($tarFileName)";
        _fileContent = content;
        _modeFixe = true;
        _errorMessage = null;
      });
    }
  }

  Widget _clickOnCsvHeaderLine(int index, String txt) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _headersTextColors[index] = Colors.grey[300] ?? Colors.grey;
        });
        Future.delayed(const Duration(milliseconds: 100), () {
          _headersTextColors[index] = Colors.blue;
          _actionClickOnCsvHeaderLine(index, txt);
        });
      },
      child: Text(
        txt,
        style: fixedTextStyle(color: _headersTextColors[index] ?? Colors.blue),
      ),
    );
  }

  Widget _clickOnCsvLine(int index, String def, String line, String txt) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _firstColumnTextColors[index] = Colors.grey[300] ?? Colors.grey;
        });
        Future.delayed(const Duration(milliseconds: 300), () {
          setState(() => _firstColumnTextColors[index] = Colors.blue);
          _actionClickOnCsvLine(def, line);
        });
      },
      child: Text(
        txt,
        style: fixedTextStyle(
          color: _firstColumnTextColors[index] ?? Colors.blue,
        ),
      ),
    );
  }

  Widget _clickOnTarFileName(int index, TarEntry entry) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _tarFileNameTextColors[index] = Colors.grey[300] ?? Colors.grey;
        });
        Future.delayed(const Duration(milliseconds: 100), () {
          _tarFileNameTextColors[index] = Colors.blue;
          _actionClickOnTarFileName(entry);
        });
      },
      child: Text(
        entry.fname,
        style: fixedTextStyle(
          color: _tarFileNameTextColors[index] ?? Colors.blue,
        ),
      ),
    );
  }

  List<Widget> buildFirstLineColumnChildren() {
    final (leftList, rightLists) = _csvLines.first;
    return rightLists.map((rightList) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: [
          Text("|", style: fixedTextStyle()),
          ...rightList.asMap().entries.map((entry) {
            final int index = entry.key;
            final String txt = entry.value;
            return Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                _clickOnCsvHeaderLine(index, txt),
                Text("|", style: fixedTextStyle()),
              ],
            );
          }),
        ],
      );
    }).toList();
  }

  List<Widget> buildColumnChildren() {
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
            Text("|", style: fixedTextStyle()),
            _clickOnCsvLine(index, firstLine, currentLine, firstField),
            Text("|${allOtherFields.join('|')}|", style: fixedTextStyle()),
          ],
        );
      });
    }).toList();
  }

  Widget _fixedCsvView(String content) {
    // Outer SingleChildScrollView for vertical scrolling of the entire list
    if (_csvLines.isEmpty) _csvLines = treatCsv(content, _newVersion);
    final length =
        _csvLines.first.$2.first.fold(0, (a, s) => a + s.length) +
        _csvLines.first.$2.first.length +
        1;
    final border = "-" * length;
    return SingleChildScrollView(
      controller: _vScrollController,
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        controller: _hScrollController,
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(border, style: fixedTextStyle()),
            ...buildFirstLineColumnChildren(),
            ...buildColumnChildren(),
            Text(border, style: fixedTextStyle()),
            Text(""),
            Text(""),
            Text(""),
          ],
        ),
      ),
    );
  }

  Widget _normalView(String content) {
    return SingleChildScrollView(
      controller: _vScrollController,
      child: SingleChildScrollView(
        controller: _hScrollController,
        scrollDirection: Axis.horizontal,
        child: Text(content, style: TextStyle(fontSize: _fontSize)),
      ),
    );
  }

  List<Widget> _buildContent() {
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
            key: ValueKey("$_fileName-$_pdfLoadCount"),
            sourceName: _fileName!,
            controller: _pdfController,
            initialPageNumber: _currentPage,
            params: PdfViewerParams(
              scrollByMouseWheel: 1.0,
              onPageChanged: (page) {
                setState(() {
                  _currentPage = page!;
                });
              },
            ),
          ),
        )
      else if (_fileType == FileType.tar)
        Expanded(
          child: SingleChildScrollView(
            controller: _vScrollController,
            child: SingleChildScrollView(
              controller: _hScrollController,
              scrollDirection: Axis.horizontal,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: _tarList.asMap().entries.map((entry) {
                  final file = entry.value;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: [
                      Text(file.tperm, style: fixedTextStyle()),
                      Text(" ", style: fixedTextStyle()),
                      Text(file.uname, style: fixedTextStyle()),
                      Text("/", style: fixedTextStyle()),
                      Text(file.gname, style: fixedTextStyle()),
                      Text(" ", style: fixedTextStyle()),
                      Text(
                        file.size.toString().padLeft(8),
                        style: fixedTextStyle(),
                      ),
                      Text(" ", style: fixedTextStyle()),
                      _clickOnTarFileName(entry.key, file),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
        )
      else if (_fileContent != null)
        Expanded(
          child: _modeFixe
              ? (_fileType == FileType.csv
                    ? _fixedCsvView(_fileContent!)
                    : _fixedView(_fileContent!))
              : _normalView(_fileContent!),
        ),
    ];
  }

  Widget _buildNormal() {
    if (Platform.isLinux ||
        MediaQuery.of(context).orientation == Orientation.portrait) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 40),
          _buildButtonsChooseModeRow(),
          if (_fileName != null &&
              _fileType != FileType.image &&
              _errorMessage == null) ...[
            const SizedBox(width: 16),
            _buildRowButtonSizeAndJump(
              _fileType,
              _currentPage,
              _fontSize,
              _vScrollController,
              _pdfController,
              _changeFontSize,
            ),
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
          ..._buildContent(),
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
          ..._buildContent(),
          if (_fileName != null &&
              _fileType != FileType.image &&
              _errorMessage == null) ...[
            const SizedBox(height: 16),
            _buildColumnButtonsJump(
              _fileType,
              _currentPage,
              _vScrollController,
              _pdfController,
            ),
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
  const FilePickerScreen({super.key});

  @override
  State<FilePickerScreen> createState() => _FilePickerScreenState();
}

class CsvTxt extends StatelessWidget {
  const CsvTxt({super.key});
  @override
  // Widget build(BuildContext context) {
  //   return MaterialApp(
  //     themeMode: ThemeMode.dark,
  //     darkTheme: ThemeData.dark(),
  //     home: const FilePickerScreen(),
  //   );
  // }
  @override
  Widget build(BuildContext context) {
    return MaterialApp(home: FilePickerScreen());
  }
}

void main() => runApp(const CsvTxt());
