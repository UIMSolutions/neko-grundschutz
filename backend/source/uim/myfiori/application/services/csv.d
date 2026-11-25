/**
 * RFC 4180 CSV reading/writing (UTF-8). Exported cells that start with a formula
 * character (= + - @ TAB CR) are prefixed with an apostrophe to prevent formula injection
 * in spreadsheet programs; the prefix is removed again on import.
 */
module uim.myfiori.application.services.csv;

@safe:

import std.array : appender;
import std.string : indexOf, startsWith;
import uim.myfiori.domain.exceptions : ValidationException;

private bool isFormulaStart(char c) pure nothrow @nogc {
  return c == '=' || c == '+' || c == '-' || c == '@' || c == '\t' || c == '\r';
}

/// Formats one cell (quoting + formula neutralisation).
string csvCell(string value, char delimiter = ',') {
  auto v = value.length && isFormulaStart(value[0]) ? "'" ~ value : value;
  bool quote = v.indexOf(delimiter) >= 0 || v.indexOf('"') >= 0 || v.indexOf('\n') >= 0 || v.indexOf('\r') >= 0
    || (v.length && (v[0] == ' ' || v[$ - 1] == ' '));
  if (!quote) return v;
  auto r = appender!string;
  r ~= '"';
  foreach (c; v) { if (c == '"') r ~= '"'; r ~= c; }
  r ~= '"';
  return r.data;
}

/// Writes a header line and the rows (CRLF line endings as required by RFC 4180).
string writeCsv(string[] header, string[][] rows, char delimiter = ',') {
  auto w = appender!string;
  void line(string[] cells) {
    foreach (i, c; cells) {
      if (i) w ~= delimiter;
      w ~= csvCell(c, delimiter);
    }
    w ~= "\r\n";
  }
  line(header);
  foreach (r; rows) line(r);
  return w.data;
}

/// Detects ',', ';' or TAB from the header line (outside quotes).
char detectDelimiter(string text) {
  size_t comma, semi, tab;
  bool quoted;
  foreach (c; text) {
    if (c == '"') quoted = !quoted;
    else if (!quoted) {
      if (c == '\n') break;
      if (c == ',') comma++;
      else if (c == ';') semi++;
      else if (c == '\t') tab++;
    }
  }
  if (semi > comma && semi >= tab) return ';';
  if (tab > comma && tab > semi) return '\t';
  return ',';
}

/// Parses CSV text into rows of cells. Handles BOM, CRLF/LF and quoted fields with line breaks.
string[][] parseCsv(string text, char delimiter = ',') {
  if (text.startsWith("\xEF\xBB\xBF")) text = text[3 .. $];
  string[][] rows;
  string[] row;
  auto cell = appender!string;
  bool quoted, wasQuoted;
  size_t i;

  void endCell() {
    auto v = cell.data.idup;
    if (!wasQuoted || true) {
      if (v.length >= 2 && v[0] == '\'' && isFormulaStart(v[1])) v = v[1 .. $];
    }
    row ~= v;
    cell = appender!string;
    wasQuoted = false;
  }
  void endRow() {
    endCell();
    if (!(row.length == 1 && row[0].length == 0)) rows ~= row;   // skip empty lines
    row = null;
  }

  while (i < text.length) {
    auto c = text[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') { cell ~= '"'; i += 2; continue; }
        quoted = false;
      } else cell ~= c;
      i++;
      continue;
    }
    if (c == '"' && cell.data.length == 0) { quoted = true; wasQuoted = true; }
    else if (c == delimiter) endCell();
    else if (c == '\r') { /* handled with \n */ }
    else if (c == '\n') endRow();
    else cell ~= c;
    i++;
  }
  if (quoted) throw new ValidationException("CSV: unterminated quoted field");
  if (cell.data.length || row.length) endRow();
  return rows;
}

unittest {
  auto text = writeCsv(["a", "b"], [["x,y", "say \"hi\""], ["=1+1", "line\nbreak"]], ',');
  assert(text == "a,b\r\n\"x,y\",\"say \"\"hi\"\"\"\r\n'=1+1,\"line\nbreak\"\r\n", text);
  auto rows = parseCsv("\xEF\xBB\xBF" ~ text);
  assert(rows == [["a", "b"], ["x,y", "say \"hi\""], ["=1+1", "line\nbreak"]]);
  assert(detectDelimiter("a;b;c\n1,2;3") == ';');
  assert(parseCsv("a;b\n1;2\n\n", ';') == [["a", "b"], ["1", "2"]]);
}
