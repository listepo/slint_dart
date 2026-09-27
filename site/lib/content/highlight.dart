/// Tiny, dependency-free syntax highlighter for the docs' code blocks.
///
/// Deliberately restrained (brand: one accent at a time): keywords, strings,
/// comments, numbers and YAML keys only. Output is escaped HTML.
library;

const _cLike = r'//[^\n]*|/\*[\s\S]*?\*/';
const _hash = r'(?:^|(?<=\s))#[^\n]*';
const _str = r'''"(?:\\.|[^"\\\n])*"|'(?:\\.|[^'\\\n])*'|`[^`\n]*`''';
const _num = r'\b\d+(?:\.\d+)?(?:px|ms|%)?\b';

const _keywords = <String, Set<String>>{
  'dart': {
    'import', 'export', 'library', 'part', 'class', 'extends', 'implements', 'with', 'mixin', 'enum',
    'void', 'final', 'const', 'var', 'late', 'required', 'return', 'if', 'else', 'for', 'while', 'in',
    'new', 'null', 'true', 'false', 'this', 'super', 'static', 'async', 'await', 'sync', 'yield',
    'override', 'get', 'set', 'is', 'as', 'show', 'hide', 'typedef', 'external', 'try', 'catch',
    'throw', 'switch', 'case', 'default', 'break', 'continue', 'abstract', 'factory', 'operator',
  },
  'slint': {
    'export', 'import', 'from', 'component', 'inherits', 'struct', 'enum', 'property', 'in', 'out',
    'in-out', 'callback', 'private', 'public', 'function', 'pure', 'if', 'else', 'for', 'return',
    'root', 'self', 'parent', 'true', 'false', 'animate', 'states', 'transitions', 'global',
  },
  'rust': {
    'fn', 'let', 'mut', 'pub', 'use', 'mod', 'crate', 'struct', 'enum', 'impl', 'trait', 'for', 'in',
    'if', 'else', 'match', 'return', 'extern', 'unsafe', 'const', 'static', 'self', 'Self', 'true',
    'false', 'as', 'where', 'loop', 'while', 'move', 'ref', 'dyn', 'type',
  },
  'bash': {
    'cd', 'export', 'if', 'then', 'fi', 'for', 'do', 'done', 'in', 'echo', 'dart', 'flutter', 'cargo',
    'mise', 'just', 'melos', 'jaspr', 'git', 'rustup', 'patrol', 'cbindgen', 'exec', 'run',
  },
};

String escapeHtml(String s) =>
    s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

String unescapeHtml(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&amp;', '&');

String _lang(String? l) {
  switch (l) {
    case 'dart':
      return 'dart';
    case 'slint':
      return 'slint';
    case 'rust':
    case 'rs':
      return 'rust';
    case 'yaml':
    case 'yml':
    case 'toml':
      return 'yaml';
    case 'bash':
    case 'sh':
    case 'shell':
    case 'console':
    case 'zsh':
      return 'bash';
    default:
      return '';
  }
}

/// Highlights raw (unescaped) [code]; returns escaped HTML.
String highlight(String code, String? language) {
  final lang = _lang(language);
  if (lang.isEmpty) return escapeHtml(code);
  final comment = (lang == 'yaml' || lang == 'bash') ? _hash : _cLike;
  final keyPattern = lang == 'yaml' ? r'|(?<key>^[ \t]*-?[ \t]*[\w.$/-]+(?=:(?:\s|$)))' : '';
  final word = (lang == 'slint' || lang == 'bash' || lang == 'yaml') ? r'[A-Za-z_][\w-]*' : r'[A-Za-z_$][\w$]*';
  final re = RegExp(
    '(?<c>$comment)|(?<s>$_str)|(?<n>$_num)$keyPattern|(?<w>$word)',
    multiLine: true,
  );
  final kw = _keywords[lang] ?? const <String>{};
  final out = StringBuffer();
  var last = 0;
  for (final m in re.allMatches(code)) {
    out.write(escapeHtml(code.substring(last, m.start)));
    last = m.end;
    final text = m.group(0)!;
    String? cls;
    if (m.namedGroup('c') != null) {
      cls = 'tok-c';
    } else if (m.namedGroup('s') != null) {
      cls = 'tok-s';
    } else if (m.namedGroup('n') != null) {
      cls = 'tok-n';
    } else if (lang == 'yaml' && m.namedGroup('key') != null) {
      cls = 'tok-k';
    } else if (m.namedGroup('w') != null) {
      if (kw.contains(text)) {
        cls = 'tok-k';
      } else if (lang != 'bash' && RegExp(r'^[A-Z][a-z0-9]\w*$').hasMatch(text)) {
        cls = 'tok-t';
      }
    }
    out.write(cls == null ? escapeHtml(text) : '<span class="$cls">${escapeHtml(text)}</span>');
  }
  out.write(escapeHtml(code.substring(last)));
  return out.toString();
}

/// Jaspr's static renderer re-indents every line of raw HTML, which would add
/// leading spaces inside `<pre>`. Encoding those newlines as `&#10;` keeps each
/// code block on one source line, so the rendered text stays byte-exact.
String preserveNewlines(String html) => html.replaceAllMapped(
      RegExp(r'<pre\b[\s\S]*?</pre>'),
      (m) => m.group(0)!.replaceAll('\n', '&#10;'),
    );
