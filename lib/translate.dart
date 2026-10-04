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

void readLexicon(LangCtx _lc, String text) {
  List<String> sl = text.split("\n");
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

String? lexiconAssetText;

String transl(LangCtx? _lc, txt) {
  if (_lc == null) return txt;
  if (Platform.isLinux) {
    final lexFile = File("${appDirName()}/lexicon.txt");
    if (!lexFile.existsSync()) {
      print("transl \"$txt\", no lexicon");
      return txt;
    }
    final DateTime lexDate = lexFile.lastModifiedSync();
    final DateTime? prevLexDate = _lc.getLexDate();
    if (prevLexDate == null || lexDate.isAfter(prevLexDate)) {
      readLexicon(_lc, utf8.decode(lexFile.readAsBytesSync()));
      _lc.setLexDate(lexDate);
    }
  } else if (_lc.getLexDate() == null) {
    readLexicon(_lc, lexiconAssetText!);
    _lc.setLexDate(DateTime.now());
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
