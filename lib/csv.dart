//
// Searching the separator of a csv file
//

import "dart:math";
import "dart:io";

void traceListString(List<String> sl) {
  bool isFirst2 = true;
  for (final s in sl) {
    if (isFirst2) {
      stdout.write("[");
    } else {
      stdout.write("; ");
    }
    isFirst2 = false;
    stdout.write('"$s"');
  }
  stdout.write("]");
}

void traceFlines(List<List<List<String>>> flines) {
  for (final line in flines) {
    bool isFirst1 = true;
    for (final sl in line) {
      if (isFirst1) {
        stdout.write("[");
      } else {
        stdout.write(";\n ");
      }
      isFirst1 = false;
      traceListString(sl);
      stdout.write("]");
    }
    stdout.write("];\n");
  }
}

void traceFieldsSizes(String s, fieldsSizes) {
  stdout.write("=== $s $fieldsSizes");
  fieldsSizes.forEach((sz) {
    stdout.write(" $sz");
  });
  stdout.write("\n");
}

String escapeString(String s) {
  final buffer = StringBuffer();
  for (final rune in s.runes) {
    final char = String.fromCharCode(rune);
    switch (rune) {
      case 9:
        buffer.write(r'\t');
        break;
      case 10:
        buffer.write(r'\n');
        break;
      case 13:
        buffer.write(r'\r');
        break;
      case 34:
        buffer.write(r'"');
        break;
      case 92:
        buffer.write(r'\\');
        break;
      default:
        buffer.write(char);
    }
  }
  return buffer.toString();
}

int nbLinesOf(String s) {
  int n = 0;
  for (int i = 0; i < s.length; i++) {
    if (s[i] == "\n") n++;
  }
  return n;
}

List<int> numberOfOccurrences(String c, String s, int i) {
  bool inString = false;
  int n = 0;
  while (i < s.length) {
    if (s[i] == '"') {
      if (i + 1 < s.length && s[i + 1] == '"') {
        i += 2;
      } else {
        inString = !inString;
        i++;
      }
    } else if (s[i] == "\n") {
      return [n, i + 1];
    } else {
      if (!inString && s[i] == c) {
        n++;
      }
      i++;
    }
  }
  return [n, i];
}

List<int> numberListOfOccurrences(String c, String content) {
  List<int> nl = [];
  int i = 0;
  while (i < content.length) {
    var result = numberOfOccurrences(c, content, i);
    int n = result[0];
    i = result[1];
    nl.insert(0, n);
  }
  return nl;
}

int charValue(String c) {
  if (c.length != 1) throw Exception("char_value: expected a single character");

  String char = c;
  int code = char.runes.first;

  // Cas 0
  if ((code >= 97 && code <= 122) || // a-z
      (code >= 65 && code <= 90) || // A-Z
      (code >= 48 && code <= 57) || // 0-9
      code == 40 ||
      code == 41 || // ( )
      code == 91 ||
      code == 93 || // [ ]
      code == 123 ||
      code == 125 || // { }
      code == 13 || // \r
      (code >= 128 && code <= 255)) {
    return 0;
  }

  // Cas 2
  if (code == 43 ||
      code == 95 ||
      code == 32 ||
      code == 92 || // + _ \ (espace)
      code == 96 ||
      code == 63 ||
      code == 42 ||
      code == 33 || // ` ? * !
      code == 64 ||
      code == 60 ||
      code == 62) {
    // @ < >
    return 2;
  }

  // Cas 3
  if (code == 45 ||
      code == 39 ||
      code == 61 ||
      code == 126 || // - " = ~
      code == 35 ||
      code == 38 ||
      code == 37) {
    // # & %
    return 3;
  }

  // Cas 4
  if (code == 47 || code == 46 || code == 94) {
    // / . ^
    return 4;
  }

  // Cas 5
  if (code == 44 ||
      code == 59 ||
      code == 124 ||
      code == 9 || // , ; | \t
      code == 58) {
    // :
    return 5;
  }
  throw Exception("char value chais pas ${escapeString(char)}");
}

int criterionValue(String c, int nbCorrectLines, int nbOccOfChar, int nbLines) {
  return (nbCorrectLines * nbOccOfChar) ~/ nbLines + charValue(c);
}

List<List<int>> testSeparator(String c, String content) {
  List<int> r = numberListOfOccurrences(c, content);
  List<List<int>> modalValues = [];

  for (int nbOccOfChar in r) {
    bool found = false;
    for (int i = 0; i < modalValues.length; i++) {
      if (modalValues[i][0] == nbOccOfChar) {
        modalValues[i][1]++;
        found = true;
        break;
      }
    }
    if (!found) {
      modalValues.add([nbOccOfChar, 1]);
    }
  }

  modalValues.sort((a, b) => b[1] - a[1]);
  modalValues.removeWhere((element) => element[0] == 0);

  return modalValues;
}

List<List<dynamic>> testSeparators(String test, String content) {
  List<List<dynamic>> r = [];
  for (int i = 0; i < test.length; i++) {
    String c = test[i];
    List<List<int>> sl = testSeparator(c, content);
    if (sl.isNotEmpty) {
      List<int> first = sl.first;
      int nbOccOfChar = first[0];
      int nbCorrectLines = first[1];
      List<List<int>> defective = sl.sublist(1);
      r.add([c, nbOccOfChar, nbCorrectLines, defective]);
    }
  }
  return r;
}

List<List<dynamic>> sortSeparators(int nbLines, List<List<dynamic>> r) {
  r.sort((a, b) {
    String c1 = a[0];
    int nbOccOfChar1 = a[1];
    int nbCorrectLines1 = a[2];

    String c2 = b[0];
    int nbOccOfChar2 = b[1];
    int nbCorrectLines2 = b[2];

    int criterion1 = criterionValue(c1, nbCorrectLines1, nbOccOfChar1, nbLines);
    int criterion2 = criterionValue(c2, nbCorrectLines2, nbOccOfChar2, nbLines);

    if (criterion2 < criterion1) {
      return -1;
    } else if (criterion2 > criterion1) {
      return 1;
    } else {
      return charValue(c2).compareTo(charValue(c1));
    }
  });
  return r;
}

List<List<dynamic>> findSeparator(String test, String content) {
  final nbLines = nbLinesOf(content);
  final r = testSeparators(test, content);
  return sortSeparators(nbLines, r);
}

String getGoodSeparator(List<List<dynamic>> r) {
  if (r.isNotEmpty) {
    return r.first[0];
  } else {
    return "a";
  }
}

//
// Changing the display of a csv file to make it pretty
//

List<int> listMaxMerge(List<int> nl1, List<int> nl2) {
  if (nl1.isEmpty && nl2.isEmpty) {
    return [];
  } else if (nl1.isEmpty) {
    return nl2;
  } else if (nl2.isEmpty) {
    return nl1;
  } else {
    return [
      [nl1.first, nl2.first].reduce((a, b) => a > b ? a : b),
      ...listMaxMerge(nl1.sublist(1), nl2.sublist(1)),
    ];
  }
}

List<int> computeFieldsSizes(List<List<String>> lines) {
  List<int>? maxLengths;
  for (final line in lines) {
    final lengths = line.map((s) => s.runes.length).toList();
    maxLengths = maxLengths == null
        ? lengths
        : listMaxMerge(maxLengths, lengths);
  }
  return maxLengths ?? [];
}

const int percent = 90;

List<int> computeFieldSizesShortColumns(List<List<String>> lines) {
  List<int> loop(List<int> fsl, int nbCol) {
    List<int> loop1(List<int> szl, List<List<String>> remainingLines) {
      if (remainingLines.isEmpty) {
        return szl;
      }
      final line = remainingLines.first;
      final newSzl = (nbCol < line.length)
          ? [...szl, line[nbCol].length]
          : [...szl];
      return loop1(newSzl, remainingLines.sublist(1));
    }

    final szl = loop1([], lines);
    if (szl.isEmpty) {
      return List.from(fsl.reversed);
    } else {
      final sortedSzl = List.from(szl)..sort();
      final len = sortedSzl.length;
      final u = sortedSzl.last.clamp(0, 10);
      final index = ((len * percent + 50) ~/ 100 - 1).clamp(0, len - 1);
      final fs = max(u, sortedSzl[index]).toInt();
      return loop([fs, ...fsl], nbCol + 1);
    }
  }

  return loop([], 0);
}

(String, String) cutAtSpaceIfPossible(String s, int fs) {
  for (int i = fs; i >= 0; i--) {
    if (i == 0) {
      // Cas 1 : Aucun espace trouvé → coupe à fs
      final s2 = s.substring(0, fs);
      final e = s.substring(fs);
      return (s2, e);
    } else if (s[i - 1] == ' ') {
      // -1 car substring est 0-based
      // Cas 2 : Espace trouvé à i-1 → coupe là
      final s2 = s.substring(0, i - 1);
      final e = s.substring(i);
      return (s2, e);
    }
  }
  // Cas par défaut (ne devrait jamais arriver)
  return (s, "");
}

// Retourne une paire [line, extra] si la ligne dépasse, sinon null
(List<String>, List<String>)? getCutLineAndExtra(
  List<int> fieldSizes,
  List<String> line,
) {
  (List<String>, List<String>)? loop(
    List<int> fsl,
    List<String> sl,
    List<String> revLine,
    List<String> extra,
    bool hasExtra,
  ) {
    if (sl.isEmpty) {
      if (hasExtra) {
        return (revLine.reversed.toList(), extra.reversed.toList());
      } else {
        return null;
      }
    }

    final s = sl.first;
    final remainingSl = sl.sublist(1);

    if (fsl.isNotEmpty) {
      final fs = fsl.first;
      final remainingFsl = fsl.sublist(1);

      String newS = "";
      List<String> newExtra = [];
      bool newHasExtra = hasExtra;
      if (s.length > fs) {
        final (r1, r2) = cutAtSpaceIfPossible(s, fs);
        newS = r1;
        newExtra = [r2, ...extra];
        newHasExtra = true;
      } else {
        newS = s;
        newExtra = ["", ...extra];
      }

      return loop(
        remainingFsl,
        remainingSl,
        [newS, ...revLine],
        newExtra,
        newHasExtra,
      );
    } else {
      return loop(fsl, remainingSl, [s, ...revLine], extra, hasExtra);
    }
  }

  return loop(fieldSizes, line, [], [], false);
}

typedef CsvLine = (List<String>, List<List<String>>);

// Fonction adaptée pour gérer les lignes longues
List<CsvLine> foldLongLines(List<int> fieldSizes, List<List<String>> lines) {
  return lines.map((line) {
    List<List<String>> loop(List<String> currentLine) {
      final result = getCutLineAndExtra(fieldSizes, currentLine);
      if (result != null) {
        // Sépare la ligne coupée des extras
        final (cutLine, extra) = result;
        return [cutLine, ...loop(extra)];
      } else {
        return [currentLine];
      }
    }

    return (line, loop(line));
  }).toList();
}

List<String> splitOnCharButStrings(String sep, String s) {
  bool inString = false;
  int ibeg = 0;
  List<String> result = [];

  for (int i = 0; i < s.length; i++) {
    if (s[i] == '"') {
      if (i + 1 < s.length && s[i + 1] == '"') {
        i++;
      } else {
        inString = !inString;
      }
    } else if (!inString && s[i] == sep) {
      result.add(s.substring(ibeg, i)); // Ajoute à la fin
      ibeg = i + 1;
    }
  }

  // Add the last segment
  if (ibeg < s.length) {
    result.add(s.substring(ibeg));
  }

  return result;
}

List<List<String>> linesOfCsvString(String sep, String content) {
  String trimmedContent = content.isNotEmpty && content.endsWith("\n")
      ? content.substring(0, content.length - 1)
      : content;
  return trimmedContent
      .split("\n")
      .map(
        (line) => splitOnCharButStrings(sep, line)
            .map(
              (s) => s.length > 1 && s.startsWith('"') && s.endsWith('"')
                  ? s.substring(1, s.length - 1)
                  : s,
            )
            .toList(),
      )
      .toList();
}

String trimRightKeepNewlines(String s) {
  final trimmed = s.replaceAll(RegExp(r"[ \t]+$"), "");
  return trimmed;
}

List<CsvLine> completeListBySpaces(
  List<int> fieldsSizes,
  List<CsvLine> flines,
) {
  return flines.map((linesGroup) {
    final (initialLine, linesGroup2) = linesGroup;
    final r = linesGroup2.map((line) {
      return completeBySpaces(fieldsSizes, line);
    }).toList();
    return (initialLine, r);
  }).toList();
}

List<String> completeBySpaces(List<int> fsl, List<String> sl) {
  // Fonction auxiliaire récursive
  List<String> completeBySpaces(List<int> fsl, List<String> sl) {
    if (sl.isEmpty) {
      return fsl.map((fs) => " " * fs).toList();
    }

    final s = sl.first;
    final remainingSl = sl.sublist(1);

    if (fsl.isEmpty) {
      return [s, ...remainingSl];
    }

    final fs = fsl.first;
    final remainingFsl = fsl.sublist(1);

    if (s.length <= fs) {
      final padded = s.padRight(fs);
      return [padded, ...completeBySpaces(remainingFsl, remainingSl)];
    } else {
      final marked = "c$s****************";
      return [marked, ...completeBySpaces(remainingFsl, remainingSl)];
    }
  }

  return completeBySpaces(fsl, sl);
}

List<List<String>> csvStruct(String content) {
  final test = ",;|\t:";
  final rs = findSeparator(test, content);
  final sep = getGoodSeparator(rs);
  final trimmedContent = trimRightKeepNewlines(content);
  return linesOfCsvString(sep, trimmedContent);
}

List<CsvLine> formattedCsv(
  List<List<String>> lines,
  bool csvShortColumns,
) {
  final fieldsSizes = csvShortColumns
      ? computeFieldSizesShortColumns(lines)
      : computeFieldsSizes(lines);
  final flines = foldLongLines(fieldsSizes, lines);
  final flines2 = completeListBySpaces(fieldsSizes, flines);
  return flines2;
}

// Treat a csv file by searching its separator and displaying
// the file correctly aligned

List<CsvLine> treatCsv(String content, bool csvShortColumns) {
  final lines = csvStruct(content);
  return formattedCsv(lines, csvShortColumns);
}
