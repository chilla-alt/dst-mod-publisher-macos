import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

class ModInfo {
  final String name;
  final String author;
  final String version;
  final String description;
  final String apiVersion;
  final bool clientOnly;
  final bool serverOnly;

  const ModInfo({
    this.name = '',
    this.author = '',
    this.version = '',
    this.description = '',
    this.apiVersion = '',
    this.clientOnly = false,
    this.serverOnly = false,
  });

  bool get valid => name.isNotEmpty && version.isNotEmpty;

  String get typeTag => clientOnly
      ? 'client_only_mod'
      : serverOnly
      ? 'server_only_mod'
      : 'all_clients_require_mod';

  static ModInfo parse(String lua) {
    String field(String key) {
      final at = RegExp('(?<![\\w])$key\\s*=').firstMatch(lua);
      if (at == null) return '';
      final rest = lua.substring(at.end);
      final line = rest.split('\n').first;

      final q = RegExp(
        '"((?:[^"\\\\]|\\\\.)*)"|\'((?:[^\'\\\\]|\\\\.)*)\'',
      ).firstMatch(line);
      if (q != null) return q.group(1) ?? q.group(2) ?? '';

      final long = RegExp('\\[\\[([\\s\\S]*?)\\]\\]').firstMatch(rest);
      if (long != null) return (long.group(1) ?? '').trim();
      final num = RegExp('([0-9][0-9.]*)').firstMatch(line);
      return num?.group(1) ?? '';
    }

    bool flag(String key) =>
        RegExp('$key\\s*=\\s*true', caseSensitive: false).hasMatch(lua);

    return ModInfo(
      name: field('name'),
      author: field('author'),
      version: field('version'),
      description: field('description'),
      apiVersion: field('api_version'),
      clientOnly: flag('client_only_mod'),
      serverOnly: flag('server_only_mod'),
    );
  }
}

class DstPub {
  int appId;
  int visibility;
  List<String> tags;
  List<String> ignore;

  List<String> keep;

  DstPub({
    this.appId = 322330,
    this.visibility = 0,
    List<String>? tags,
    List<String>? ignore,
    List<String>? keep,
  }) : tags = tags ?? [],
       ignore = ignore ?? [],
       keep = keep ?? [];

  factory DstPub.fromJson(Map<String, dynamic> j) => DstPub(
    appId: (j['appid'] as num?)?.toInt() ?? 322330,
    visibility: (j['visibility'] as num?)?.toInt() ?? 0,
    tags: (j['tags'] as List?)?.cast<String>() ?? [],
    ignore: (j['ignore'] as List?)?.cast<String>() ?? [],
    keep: (j['keep'] as List?)?.cast<String>() ?? [],
  );

  Map<String, dynamic> toJson() => {
    'appid': appId,
    'visibility': visibility,
    'tags': tags,
    'ignore': ignore,
    'keep': keep,
  };
}

class Mod {
  final Directory dir;
  ModInfo info;
  DstPub pub;

  Mod({required this.dir, required this.info, required this.pub});

  String get path => dir.path;
  String get folderName => p.basename(dir.path);

  File get modinfoFile => File(p.join(dir.path, 'modinfo.lua'));
  File get pubFile => File(p.join(dir.path, 'dstpub.json'));

  File? get preview {
    final cands = [
      for (final n in ['preview.jpg', 'preview.png', 'preview.gif'])
        File(p.join(dir.path, n)),
    ].where((f) => f.existsSync()).toList();
    if (cands.isEmpty) return null;
    cands.sort(
      (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
    );
    return cands.first;
  }

  static Future<Mod?> load(Directory d) async {
    final mi = File(p.join(d.path, 'modinfo.lua'));
    if (!await mi.exists()) return null;

    final text = utf8.decode(await mi.readAsBytes(), allowMalformed: true);
    final info = ModInfo.parse(text);
    var pub = DstPub();
    final pf = File(p.join(d.path, 'dstpub.json'));
    if (await pf.exists()) {
      try {
        pub = DstPub.fromJson(
          jsonDecode(await pf.readAsString()) as Map<String, dynamic>,
        );
      } catch (_) {}
    }
    return Mod(dir: d, info: info, pub: pub);
  }

  Future<void> savePub() async {
    const enc = JsonEncoder.withIndent('  ');
    await pubFile.writeAsString(enc.convert(pub.toJson()));
  }

  Future<void> writeVersion(String v) async {
    var text = await modinfoFile.readAsString();
    text = text.replaceFirst(
      RegExp('version\\s*=\\s*("[^"]*"|\'[^\']*\')'),
      'version = "$v"',
    );
    await modinfoFile.writeAsString(text);
    info = ModInfo.parse(text);
  }
}

int cmpVer(String a, String b) {
  final as = a.split(RegExp(r'[.\-]'));
  final bs = b.split(RegExp(r'[.\-]'));
  final n = as.length > bs.length ? as.length : bs.length;
  for (var i = 0; i < n; i++) {
    final x = i < as.length ? int.tryParse(as[i]) ?? 0 : 0;
    final y = i < bs.length ? int.tryParse(bs[i]) ?? 0 : 0;
    if (x != y) return x - y;
  }
  return 0;
}

String bumpVer(String v) {
  final parts = v.split('.');
  final last = parts.last;
  final m = RegExp(r'^(\d+)').firstMatch(last);
  if (m != null) {
    final n = int.parse(m.group(1)!);
    parts[parts.length - 1] = '${n + 1}${last.substring(m.group(1)!.length)}';
    return parts.join('.');
  }
  return '$v.1';
}

String suggestBump(String local, String? workshop) {
  var base = local.isEmpty ? '0' : local;
  if (workshop != null && workshop.isNotEmpty && cmpVer(workshop, base) >= 0) {
    base = workshop;
  }
  return bumpVer(base);
}

String detectChannel(String v) {
  final s = v.toLowerCase();
  if (s.contains('alpha')) return 'alpha';
  if (s.contains('beta') || s.contains('rc') || s.contains('pre')) {
    return 'beta';
  }
  return 'release';
}
