import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models/mod.dart';

const List<String> kDefaultIgnore = [
  '.git',
  '.svn',
  '.vscode',
  '.idea',
  'exported',
  '*.psd',
  '*.aseprite',
  '*.xcf',
  '*.rar',
  '*.7z',
  '*.bak',
  '*.tmp',
  '*.exe',
  '*.dll',
  '*.pdb',

  'Thumbs.db',
  'desktop.ini',
  'dstpub.json',
  '.modignore',
  'mod.manifest',
];

class StagedEntry {
  final String rel;
  final int size;
  final bool skipped;
  final String? reason;

  const StagedEntry(this.rel, this.size, this.skipped, this.reason);
}

class StagePlan {
  final List<StagedEntry> entries;
  StagePlan(this.entries);

  List<StagedEntry> get kept => entries.where((e) => !e.skipped).toList();
  List<StagedEntry> get dropped => entries.where((e) => e.skipped).toList();
  int get totalSize => kept.fold(0, (a, e) => a + e.size);

  static const int sizeReference = 100 * 1024 * 1024;
  bool get overLimit => totalSize > sizeReference;
}

bool _match(String rel, String pattern) {
  final re = RegExp(
    '^${RegExp.escape(pattern).replaceAll(r'\*', '[^/]*')}\$',
    caseSensitive: false,
  );
  if (re.hasMatch(rel)) return true;
  final segments = rel.split('/');
  for (var i = 0; i < segments.length; i++) {
    if (re.hasMatch(segments[i])) return true;
    if (re.hasMatch(segments.sublist(0, i + 1).join('/'))) return true;
  }
  return false;
}

Future<List<String>> loadModIgnore(Mod mod) async {
  final f = File(p.join(mod.path, '.modignore'));
  if (!await f.exists()) return [];
  return (await f.readAsLines())
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty && !l.startsWith('#'))
      .toList();
}

Future<StagePlan> planStage(Mod mod) async {
  final fromFile = await loadModIgnore(mod);
  final entries = <StagedEntry>[];

  await for (final ent in mod.dir.list(recursive: true, followLinks: false)) {
    if (ent is! File) continue;
    final rel = p.relative(ent.path, from: mod.path).replaceAll('\\', '/');

    final hiddenDir = rel
        .split('/')
        .any((s) => s.startsWith('.') && s != '.modignore');
    String? reason;
    if (mod.pub.keep.any((pat) => _match(rel, pat))) {
      reason = null;
    } else if (mod.pub.ignore.any((pat) => _match(rel, pat))) {
      reason = '自定义';
    } else if (hiddenDir || kDefaultIgnore.any((pat) => _match(rel, pat))) {
      reason = '默认忽略';
    } else if (fromFile.any((pat) => _match(rel, pat))) {
      reason = '.modignore';
    }
    final size = await ent.length();
    entries.add(StagedEntry(rel, size, reason != null, reason));
  }
  entries.sort((a, b) => a.rel.compareTo(b.rel));
  return StagePlan(entries);
}

Future<Directory> materialize(Mod mod, StagePlan plan) async {
  final staging = Directory(
    p.join(Directory.systemTemp.path, 'dst_mod_publisher', mod.folderName),
  );
  if (await staging.exists()) await staging.delete(recursive: true);
  await staging.create(recursive: true);

  for (final e in plan.kept) {
    final src = File(p.join(mod.path, e.rel));
    final dst = File(p.join(staging.path, e.rel));
    await dst.parent.create(recursive: true);
    await src.copy(dst.path);
  }
  if (mod.pub.appId == 322330) {
    await _writeModManifest(staging, plan.kept.map((e) => e.rel));
  }
  return staging;
}

int _sdbm(String s) {
  var h = 0;
  for (final b in utf8.encode(s)) {
    h = (h * 65599 + b) & 0xFFFFFFFF;
  }
  return h;
}

Uint8List _u32le(int v) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, v, Endian.little);

Future<void> _writeModManifest(Directory staging, Iterable<String> rels) async {
  final hashes = [
    for (final r in rels)
      if (r.toLowerCase() != 'mod.manifest') _sdbm(r.toLowerCase()),
  ];
  final b = BytesBuilder()
    ..add(ascii.encode('MNFS'))
    ..add(_u32le(1))
    ..add(_u32le(hashes.length));
  for (final h in hashes) {
    b.add(_u32le(h));
  }
  await File(p.join(staging.path, 'mod.manifest')).writeAsBytes(b.toBytes());
}
