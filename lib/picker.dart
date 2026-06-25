// personal file picker, mainly for Linux platform where we don't
// use the usual FilePicker because of problems of font sizes.

import 'package:flutter/material.dart';
import "dart:math";
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
// ignore: unused_import
import 'package:file_picker/file_picker.dart';

import "translate.dart";

double _lsFontSize = 18;

List<List<(String, int)>> buildLsLikeLines(List<String> labels, int maxWidth) {
  int n = labels.length;
  if (n == 0) return [];

  // Find the optimal number of columns
  int bestCols = 1;
  int c = n;
  while (c >= 1) {
    int rows = (n + c - 1) ~/ c;
    int totalWidth = 0;
    for (int col = 0; col < c; col++) {
      int colMax = 0;
      for (int row = 0; row < rows; row++) {
        int idx = col * rows + row;
        if (idx < n) {
          colMax = max(colMax, labels[idx].length);
        }
      }
      totalWidth += colMax + (col < c - 1 ? 2 : 0);
    }
    if (totalWidth <= maxWidth) {
      bestCols = c;
      c = -1;
    } else {
      c--;
    }
  }

  int cols = bestCols;
  int rows = (n + cols - 1) ~/ cols;

  // Calculate the width of each column
  List<int> colWidths = List.filled(cols, 0);
  for (int col = 0; col < cols; col++) {
    for (int row = 0; row < rows; row++) {
      int idx = col * rows + row;
      if (idx < n) {
        colWidths[col] = max(colWidths[col], labels[idx].length);
      }
    }
  }

  // Build the result: List of lines, where each line is a list of (label, pad)
  List<List<(String, int)>> result = [];
  for (int row = 0; row < rows; row++) {
    List<(String, int)> line = [];
    for (int col = 0; col < cols; col++) {
      int idx = col * rows + row;
      if (idx < n) {
        String label = labels[idx];
        // Pad is the difference between column width and label length
        // +2 spaces between columns, except for the last column
        int pad = col < cols - 1 ? (colWidths[col] - label.length + 2) : 0;
        line.add((label, pad));
      }
    }
    result.add(line);
  }

  return result;
}

class CustomFilePicker extends StatefulWidget {
  final LangCtx? langCtx;
  final String? initialDir;
  const CustomFilePicker({super.key, this.initialDir, this.langCtx});

  @override
  CustomFilePickerState createState() => CustomFilePickerState();
}

double _lastVScrollPosition = 0.0;

typedef PickerState = ({
  String? Function() getCurrentDir,
  String? Function() getSelectedFile,
  ScrollController Function() getVScrollController,
  ScrollController Function() getHScrollController,
  void Function(String?) setCurrentDir,
  void Function(String?) setSelectedFile,
  void Function(List<FileSystemEntity>) setFiles,
  void Function() sync,
});

Future<void> _loadFiles(
  PickerState _ps,
  BuildContext context,
  bool mounted,
  String path,
) async {
  final dir = Directory(path);
  try {
    final entities = await dir.list().toList();
    final filteredEntities = entities.where((entity) {
      final basename = entity.path.split('/').last;
      return !basename.startsWith('.');
    }).toList();
    filteredEntities.add(Directory('..'));
    filteredEntities.sort((a, b) => a.path.compareTo(b.path));
    if (_ps.getHScrollController().hasClients) {
      _ps.getHScrollController().jumpTo(0);
    }
    if (_ps.getVScrollController().hasClients) {
      _ps.getVScrollController().jumpTo(_lastVScrollPosition);
    }
    _ps.setCurrentDir(path);
    _ps.setFiles(filteredEntities);
    _ps.sync();
  } catch (e) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Erreur: $e")));
    }
  }
}

TextStyle lsStyle({Color color = Colors.blue}) {
  return TextStyle(
    fontFamily: "monospace", // "Courier",
    fontSize: _lsFontSize,
    fontWeight: FontWeight.bold,
    color: color,
  );
}

// Calculate the width of a character with the given style
double getCharWidth(BuildContext context, TextStyle style) {
  final TextPainter textPainter = TextPainter(
    text: TextSpan(text: 'M', style: style),
    textDirection: TextDirection.ltr,
  )..layout();
  return textPainter.width;
}

int getMaxCharsPerLine(BuildContext context, int width) {
  final padding = 50.0;
  final availableWidth = width - padding;
  final charWidth = getCharWidth(context, lsStyle());
  final r = (availableWidth / charWidth).floor();
  return r;
}

Widget fileSelectorByTiles(
  PickerState _ps,
  bool mounted,
  String currentDir,
  List<FileSystemEntity> files,
) {
  return Expanded(
    child: ListView.builder(
      controller: _ps.getVScrollController(),
      scrollDirection: Axis.vertical,
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        final isDir = file is Directory;
        final displayName = file.path.split('/').last;
        return ListTile(
          title: Text(displayName, style: TextStyle(fontSize: 16)),
          trailing: isDir ? Icon(Icons.folder) : null,
          onTap: () {
            if (isDir) {
              if (displayName == '..') {
                final parentDir = Directory(currentDir).parent.path;
                _loadFiles(_ps, context, mounted, parentDir);
              } else {
                _loadFiles(_ps, context, mounted, file.path);
              }
            } else {
              _ps.setSelectedFile(file.path);
              _ps.sync();
              Navigator.pop(context, _ps.getSelectedFile());
            }
          },
        );
      },
    ),
  );
}

class CustomFilePickerState extends State<CustomFilePicker> {
  List<FileSystemEntity> _files = [];
  LangCtx? _lc;
  String? _currentDir;
  String? _selectedFile;
  final Map<int, Color> _fileTextColors = {};
  final ScrollController _vScrollController = ScrollController();
  final ScrollController _hScrollController = ScrollController();

  String? _getCurrentDir() => _currentDir;
  String? _getSelectedFile() => _selectedFile;
  ScrollController _getVScrollController() => _vScrollController;
  ScrollController _getHScrollController() => _hScrollController;
  void _setCurrentDir(String? d) => _currentDir = d;
  void _setSelectedFile(String? f) => _selectedFile = f;
  void _setFiles(List<FileSystemEntity> fl) => _files = fl;
  void _sync() => setState(() {});

  late PickerState _ps = (
    getCurrentDir: _getCurrentDir,
    getSelectedFile: _getSelectedFile,
    getVScrollController: _getVScrollController,
    getHScrollController: _getHScrollController,
    setCurrentDir: _setCurrentDir,
    setSelectedFile: _setSelectedFile,
    setFiles: _setFiles,
    sync: _sync,
  );

  @override
  void dispose() {
    _vScrollController.dispose();
    _hScrollController.dispose();
    super.dispose();
  }

  Future<void> _initPlatform() async {
    _lc = widget.langCtx;
    if (widget.initialDir != null) {
      _currentDir = widget.initialDir;
    } else if (Platform.isLinux) {
      _currentDir = "/home";
    } else {
      //      final appDir = await getApplicationDocumentsDirectory();
      //      final tempDir = await getTemporaryDirectory();
      final extDir = await getExternalStorageDirectory();
      final status = await Permission.manageExternalStorage.request();
      if (status.isGranted) {
        _currentDir = "/storage/emulated/0";
      } else {
        _currentDir = extDir?.path ?? "/storage/emulated/0";
      }
    }
    _loadFiles(_ps, context, mounted, _currentDir!);
  }

  @override
  void initState() {
    super.initState();
    _vScrollController.addListener(() {
      _lastVScrollPosition = _vScrollController.position.pixels;
    });
    _initPlatform();
  }

  void _actionClickOnFile(String currentDir, String label) {
    final isDir = label.endsWith("/");
    final cds = currentDir.endsWith("/");
    final wds = "$currentDir${cds ? '' : '/'}";
    if (isDir) {
      if (label == '../') {
        final parentDir = Directory(currentDir).parent.path;
        _loadFiles(_ps, context, mounted, parentDir);
      } else {
        _loadFiles(_ps, context, mounted, "$wds$label");
      }
    } else {
      setState(() => _selectedFile = "$wds$label");
      Navigator.pop(context, _selectedFile);
    }
  }

  Widget _clickOnFile(int index, String currentDir, String label, int pad) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _fileTextColors[index] = Colors.grey[300] ?? Colors.grey;
        });
        Future.delayed(const Duration(milliseconds: 300), () {
          _fileTextColors[index] = Colors.blue;
          _actionClickOnFile(currentDir, label);
        });
      },
      child: Text(
        "$label${' ' * pad}",
        style: lsStyle(color: _fileTextColors[index] ?? Colors.blue),
      ),
    );
  }

  Widget buildLsLikeWidget(
    int width,
    String currentDir,
    List<List<(String, int)>> lines,
  ) {
    return Expanded(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        controller: _hScrollController,
        child: ListView.builder(
          controller: _vScrollController,
          itemCount: lines.length,
          itemBuilder: (context, rowIndex) {
            final line = lines[rowIndex];
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: line.asMap().entries.map((entry) {
                final int index = rowIndex * lines.first.length + entry.key;
                final (label, pad) = entry.value;
                return Row(
                  children: [_clickOnFile(index, currentDir, label, pad)],
                );
              }).toList(),
            );
          },
        ),
      ),
    );
  }

  Widget fileSelectorByLs(
    int width,
    String currentDir,
    List<FileSystemEntity> files,
  ) {
    final maxWidth = getMaxCharsPerLine(context, width);
    final filesTagDir = files.map((file) {
      final isDir = file is Directory;
      return "${file.path.split('/').last}${isDir ? '/' : ''}";
    }).toList();
    final spll = buildLsLikeLines(filesTagDir, maxWidth);
    return buildLsLikeWidget(width, currentDir, spll);
  }

  @override
  Widget build(BuildContext context) {
    final containerWidth = min(600, MediaQuery.of(context).size.width).toInt();
    if (_currentDir == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return Dialog(
      child: Container(
        padding: EdgeInsets.all(20),
        width: containerWidth.toDouble(),
        height: 400,
        child: Column(
          children: [
            Text(_currentDir!, style: TextStyle(fontSize: 18)),
            SizedBox(height: 10),
            // fileSelectorByTiles(
            fileSelectorByLs(containerWidth, _currentDir!, _files),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  child: Text(
                    transl(_lc, "Cancel"),
                    style: TextStyle(fontSize: 16),
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

Future<String?> customPickFile(
  BuildContext context,
  LangCtx langCtx,
  String? initialDir,
) async {
  return await showDialog<String>(
    context: context,
    builder: (context) =>
        CustomFilePicker(langCtx: langCtx, initialDir: initialDir),
  );
}
