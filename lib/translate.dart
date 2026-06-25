import 'dart:convert';
import "dart:io";

String appDirName() {
  if (Platform.isLinux) return "assets";
  return "/storage/emulated/0/Documents/CsvTxt";
}

typedef LangCtx = ({
  String Function() getLang,
  DateTime? Function() getLexDate,
  Map<String, List<(String, String)>> Function() getLexTable,
  void Function(DateTime) setLexDate,
});

void readLexicon(LangCtx _lc, File lexFile) {
  List<String> sl = utf8.decode(lexFile.readAsBytesSync()).split("\n");
  final table = _lc.getLexTable();
  table.clear();
  int i = 0;
  while (i < sl.length) {
    final line = sl[i];
    if (line.length > 5 && line.substring(0, 4) == "    ") {
      final key = line.substring(4);
      i++;
      List<(String, String)> val = [];
      while (i < sl.length) {
        final line = sl[i];
        final j = line.indexOf(":");
        if (j == -1) break;
        final k = line.substring(0, j);
        final v = line.substring(j + 2);
        val.add((k, v));
        i++;
      }
      table[key] = val;
    } else
      i++;
  }
}

String transl(LangCtx _lc, txt) {
  final String _lexFileName = "${appDirName()}/lexicon.txt";
  final lexFile = File(_lexFileName);
  if (!lexFile.existsSync()) {
    print("transl \"$txt\", no lexicon");
    return txt;
  }
  final DateTime lexDate = lexFile.lastModifiedSync();
  final DateTime? prevLexDate = _lc.getLexDate();
  if (prevLexDate == null) {
    print("transl \"$txt\" lexicon not yet loaded");
    readLexicon(_lc, lexFile);
    _lc.setLexDate(lexDate);
  } else if (lexDate.isAfter(prevLexDate)) {
    print("transl \"$txt\" lexicon has changed");
    readLexicon(_lc, lexFile);
    _lc.setLexDate(lexDate);
  }
  final table = _lc.getLexTable();
  final lang = _lc.getLang();
  List<(String, String)>? val = table[txt];
  if (val == null) return "<$txt>";
  try {
    return val.firstWhere((tuple) => tuple.$1 == lang).$2;
  } catch (e) {
    return "[$txt]";
  }
}
