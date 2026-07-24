import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/mod.dart';
import '../services/stager.dart';
import '../services/steamcmd.dart';
import '../services/updater.dart';
import '../version.dart';
import '../services/steamworks_engine.dart';
import '../services/workshop_api.dart';

enum LogLevel { info, warn, error }

class LogEntry {
  final LogLevel level;
  final String message;
  final DateTime time;
  LogEntry(this.level, this.message) : time = DateTime.now();
}

class PublishProgress {
  final String stage;
  final double progress;
  const PublishProgress(this.stage, this.progress);
}

class AppState extends ChangeNotifier {
  String engine = 'steamworks';
  String modsDir = '';
  String steamcmdPath = '';
  String steamUser = '';
  String webApiKey = '';
  String steamId64 = '';
  String seed = 'purple';
  ThemeMode themeMode = ThemeMode.dark;

  List<Mod> mods = [];
  Mod? current;
  String? publishTargetId;
  final List<LogEntry> logs = [];
  List<WorkshopItemRemote> remoteItems = [];

  bool busy = false;
  PublishProgress? progress;
  String? failNote;

  int navIndex = 0;

  Future<void> init() async {
    final sp = await SharedPreferences.getInstance();
    engine = sp.getString('engine') ?? 'steamworks';
    modsDir = sp.getString('modsDir') ?? '';
    steamcmdPath = sp.getString('steamcmdPath') ?? '';
    steamUser = sp.getString('steamUser') ?? '';
    webApiKey = sp.getString('webApiKey') ?? '';
    steamId64 = sp.getString('steamId64') ?? '';
    seed = sp.getString('seed') ?? 'purple';

    themeMode =
        ThemeMode.values[sp.getInt('themeMode') ?? ThemeMode.dark.index];
    notifyListeners();
    unawaited(_warmup());
  }

  Future<void> _warmup() async {
    if (modsDir.isNotEmpty) await scanMods();
    if (engine == 'steamworks' && steamReady) {
      unawaited(refreshRemote());
    }
    unawaited(checkUpdates());
    unawaited(fetchNews());
    _updateTimer = Timer.periodic(const Duration(minutes: 20), (_) {
      if (update == null && !busy) unawaited(checkUpdates());
    });
  }

  List<NewsItem> news = [];

  Future<void> fetchNews() async {
    final n = await fetchDstNews();
    if (n.isNotEmpty) {
      news = n;
      notifyListeners();
    }
  }

  UpdateInfo? update;
  Timer? _updateTimer;

  @override
  void dispose() {
    _updateTimer?.cancel();
    super.dispose();
  }

  Future<void> checkUpdates({bool manual = false}) async {
    final u = await checkWorkshopUpdate(modsDir) ?? await checkGithubUpdate();
    update = u;
    if (u != null) {
      log(LogLevel.info, '发现新版本 v${u.version}(${u.source}),当前 v$kAppVersion');
    } else if (manual) {
      log(LogLevel.info, '已是最新版本 v$kAppVersion');
    }
    notifyListeners();
  }

  void dismissUpdate() {
    update = null;
    notifyListeners();
  }

  String? updateStage;
  double? updateProgress;

  Future<void> startUpdate() async {
    final u = update;
    if (u == null || busy) return;
    busy = true;
    updateStage = '准备更新…';
    updateProgress = null;
    notifyListeners();
    var lastNotified = 0.0;
    try {
      var zip = u.zipPath;
      if (zip == null && u.downloadUrl != null) {
        log(LogLevel.info, '正在从 ${u.source} 下载 v${u.version}…');
        zip = await downloadZip(
          u.downloadUrl!,
          onProgress: (done, total) {
            if (total > 0) {
              final frac = done / total;
              if (frac - lastNotified < 0.01 && frac < 1) return;
              lastNotified = frac;
              updateProgress = frac;
              updateStage =
                  '下载 v${u.version} · ${(done / 1048576).toStringAsFixed(1)}/${(total / 1048576).toStringAsFixed(1)} MB';
            } else {
              updateStage =
                  '下载 v${u.version} · ${(done / 1048576).toStringAsFixed(1)} MB';
            }
            notifyListeners();
          },
        );
      }
      if (zip == null) {
        log(LogLevel.error, '更新包获取失败,稍后重试');
        return;
      }
      updateStage = '解压并替换文件,应用即将自动重启…';
      updateProgress = null;
      notifyListeners();
      log(LogLevel.info, '应用更新中,即将自动重启…');
      final err = await applyUpdate(zip);
      if (err != null) log(LogLevel.error, '更新失败:$err');
    } finally {
      busy = false;
      updateStage = null;
      updateProgress = null;
      notifyListeners();
    }
  }

  Future<void> _persist(String key, String value) async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(key, value);
  }

  void log(LogLevel lv, String msg) {
    logs.insert(0, LogEntry(lv, msg));
    if (logs.length > 500) logs.removeLast();
    notifyListeners();
  }

  void goto(int index) {
    navIndex = index;
    notifyListeners();
  }

  void clearLogs() {
    logs.clear();
    notifyListeners();
  }

  Future<void> setEngine(String e) async {
    engine = e;
    await _persist('engine', e);
    notifyListeners();
  }

  Future<void> setModsDir(String dir) async {
    modsDir = dir;
    notifyListeners();
    await _persist('modsDir', dir);
    await scanMods();
  }

  Future<void> setSteamcmdPath(String path) async {
    steamcmdPath = path;
    await _persist('steamcmdPath', path);
    notifyListeners();
  }

  Future<void> setSteamUser(String u) async {
    steamUser = u;
    await _persist('steamUser', u);
    notifyListeners();
  }

  Future<void> setWebApi(String key, String sid) async {
    webApiKey = key;
    steamId64 = sid;
    await _persist('webApiKey', key);
    await _persist('steamId64', sid);
    notifyListeners();
  }

  Future<void> setSeed(String s) async {
    seed = s;
    await _persist('seed', s);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode m) async {
    themeMode = m;
    final sp = await SharedPreferences.getInstance();
    await sp.setInt('themeMode', m.index);
    notifyListeners();
  }

  String get helperPath => p.join(
    File(Platform.resolvedExecutable).parent.path,
    'helper',
    Platform.isWindows ? 'CpSteamHelper.exe' : 'CpSteamHelper',
  );

  bool get steamReady => engine == 'steamworks'
      ? File(helperPath).existsSync()
      : (steamcmdPath.isNotEmpty &&
            File(steamcmdPath).existsSync() &&
            steamUser.isNotEmpty);

  Future<void> scanMods() async {
    mods = [];
    final root = Directory(modsDir);
    if (await root.exists()) {
      await for (final ent in root.list(followLinks: false)) {
        if (ent is! Directory) continue;
        try {
          final mod = await Mod.load(ent);
          if (mod != null) mods.add(mod);
        } catch (e) {
          log(LogLevel.warn, '跳过无法读取的模组 ${ent.path}:$e');
        }
      }
      mods.sort((a, b) => a.info.name.compareTo(b.info.name));
      log(LogLevel.info, '扫描 $modsDir → ${mods.length} 个模组');
    }
    if (current != null && !mods.any((m) => m.path == current!.path)) {
      current = null;
    }
    current ??= mods.isNotEmpty ? mods.first : null;
    notifyListeners();
  }

  void select(Mod mod) {
    current = mod;
    notifyListeners();
  }

  Future<Mod?> addExternalFolder(String dir) async {
    final existing = mods.where((m) => m.path == dir).firstOrNull;
    if (existing != null) return existing;
    final mod = await Mod.load(Directory(dir));
    if (mod == null) {
      log(LogLevel.error, '$dir 里没有有效的 modinfo.lua,无法作为模组文件夹');
      return null;
    }
    mods.add(mod);
    mods.sort((a, b) => a.info.name.compareTo(b.info.name));
    log(LogLevel.info, '已加入外部文件夹 ${mod.folderName}/(${mod.info.name})');
    notifyListeners();
    return mod;
  }

  static const int publishPageIndex = 2;

  void startPublish({Mod? content, String? targetId, bool goto = true}) {
    if (content != null) current = content;
    publishTargetId = targetId;
    if (goto) navIndex = publishPageIndex;
    notifyListeners();
  }

  void setPublishTarget(String? id) {
    publishTargetId = id;
    notifyListeners();
  }

  Future<StagePlan> dryRun(Mod mod) async {
    final plan = await planStage(mod);
    log(
      LogLevel.info,
      'Dry-run(${mod.info.name}):${plan.kept.length} 项 · '
      '${(plan.totalSize / 1048576).toStringAsFixed(2)} MB · '
      '${plan.dropped.length} 项被忽略 · 未上传',
    );
    return plan;
  }

  Future<bool> publish({
    required Mod mod,
    required String? targetId,
    required String version,
    required List<LangEntry> languages,
    required String changeNote,
    required int visibility,
    required List<String> tags,
    Set<String> parts = const {
      'content',
      'text',
      'preview',
      'tags',
      'visibility',
    },
  }) async {
    final isNew = targetId == null;
    final upContent = isNew || parts.contains('content');
    final upText = isNew || parts.contains('text');
    final upPreview = isNew || parts.contains('preview');
    final upTags = isNew || parts.contains('tags');
    final upVisibility = isNew || parts.contains('visibility');
    if (busy) return false;
    if (!steamReady) {
      log(
        LogLevel.error,
        engine == 'steamworks'
            ? '发布环境未就绪:未找到 Steamworks 助手(helper\\CpSteamHelper.exe),请使用完整发行包'
            : '发布环境未就绪:检查 steamcmd 路径与账号(设置页)',
      );
      return false;
    }
    busy = true;
    failNote = null;
    progress = const PublishProgress('校验 modinfo.lua', .02);
    notifyListeners();

    try {
      if (!mod.info.valid) {
        throw Exception('modinfo.lua 无效:缺少 name 或 version');
      }
      var contentFolder = mod.path;
      if (upContent) {
        final wsVersion = targetId == null
            ? ''
            : (remoteItems
                      .where((x) => x.id == targetId)
                      .firstOrNull
                      ?.version ??
                  '');
        if (wsVersion.isNotEmpty && cmpVer(version, wsVersion) <= 0) {
          throw Exception('版本 $version 需大于工坊当前 $wsVersion');
        }

        if (version != mod.info.version) {
          await mod.writeVersion(version);
          log(LogLevel.info, 'modinfo.lua version → $version');
        }

        progress = const PublishProgress('暂存清洗副本', .1);
        notifyListeners();
        final plan = await planStage(mod);
        if (plan.overLimit) {
          log(
            LogLevel.warn,
            '内容 ${(plan.totalSize / 1048576).toStringAsFixed(1)} MB 较大,上传耗时会变长;若被 Steam 拒绝请检查是否含无关大文件',
          );
        }
        final staged = await materialize(mod, plan);
        log(
          LogLevel.info,
          '已暂存 ${plan.kept.length} 项(忽略 ${plan.dropped.length} 项)→ ${staged.path}',
        );
        if (mod.pub.appId == 322330) {
          log(LogLevel.info, '已生成 mod.manifest(游戏资源索引,与官方上传器一致)');
        }
        contentFolder = staged.path;
      } else {
        log(LogLevel.info, '本次不更新内容文件,跳过版本校验与暂存');
      }

      String? preview;
      if (upPreview) {
        final pv = mod.preview;
        if (pv != null) {
          final len = await pv.length();
          if (len >= 1024 * 1024) {
            throw Exception(
              '预览图 ${(len / 1024).round()} KB ≥ 1MB 上限,Steam 会拒收',
            );
          }
          preview = pv.path;
        }
      }

      final tagSet = <String>{mod.info.typeTag, ...tags};
      tagSet.removeWhere((t) => t.startsWith('version:'));

      final primary = languages.isNotEmpty
          ? languages.first
          : LangEntry('english', mod.info.name, '');
      final req = PublishRequest(
        appId: mod.pub.appId,
        publishedFileId: targetId,
        contentFolder: contentFolder,
        previewFile: preview,
        title: primary.title,
        description: primary.desc,
        changeNote: changeNote,
        visibility: visibility,
        tags: tagSet.toList(),
        version: version,
        languages: languages,
        updateContent: upContent,
        updateText: upText,
        updatePreview: upPreview,
        updateTags: upTags,
        updateVisibility: upVisibility,
      );
      final Stream<PublishEvent> events = engine == 'steamworks'
          ? SteamworksEngine(helperPath: helperPath).publish(req)
          : SteamcmdEngine(
              steamcmdPath: steamcmdPath,
              username: steamUser,
            ).publish(req);

      String? newId;
      String? error;
      await for (final ev in events) {
        if (ev.logLine != null) log(LogLevel.info, '[steamcmd] ${ev.logLine}');
        if (ev.stage != null) {
          progress = PublishProgress(ev.stage!, ev.progress ?? 0);
          notifyListeners();
        }
        if (ev.done) {
          error = ev.error;
          newId = ev.publishedFileId;
        }
      }
      if (error != null) throw Exception(error);

      final resultId = (newId != null && newId.isNotEmpty) ? newId : targetId;

      mod.pub.visibility = visibility;
      mod.pub.tags = List.of(tags);
      await mod.savePub();
      publishTargetId = resultId;
      if (resultId != null) _itemLangsCache.remove(resultId);
      log(
        LogLevel.info,
        '✔ 已发布 ${mod.info.name} v$version(条目 ${resultId ?? '?'})· 更新记录已写入',
      );

      if (resultId != null) _upsertLocal(resultId, mod, version, visibility);
      Timer(const Duration(seconds: 4), () => unawaited(refreshRemote()));
      return true;
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      failNote = msg;
      log(LogLevel.error, '发布失败:$msg —— 表单内容与草稿完好,修复后直接重试');
      return false;
    } finally {
      busy = false;
      progress = null;
      notifyListeners();
    }
  }

  void _upsertLocal(String id, Mod mod, String version, int visibility) {
    final idx = remoteItems.indexWhere((x) => x.id == id);
    if (idx >= 0) {
      final old = remoteItems[idx];
      remoteItems[idx] = WorkshopItemRemote(
        id: id,
        title: mod.info.name,
        subs: old.subs,
        favorites: old.favorites,
        comments: old.comments,
        views: old.views,
        votesUp: old.votesUp,
        votesDown: old.votesDown,
        score: old.score,
        updated: DateTime.now(),
        tags: old.tags,
        version: version,
        previewUrl: old.previewUrl,
        description: old.description,
        visibility: visibility,
      );
    } else {
      remoteItems = [
        WorkshopItemRemote(
          id: id,
          title: mod.info.name,
          subs: 0,
          updated: DateTime.now(),
          version: version,
          visibility: visibility,
        ),
        ...remoteItems,
      ];
    }
    notifyListeners();
  }

  bool _refreshing = false;

  final Map<String, List<LangEntry>> _itemLangsCache = {};

  Future<List<LangEntry>> fetchItemLangs(String id) async {
    final cached = _itemLangsCache[id];
    if (cached != null) return cached;
    if (engine != 'steamworks' || !File(helperPath).existsSync()) return [];
    final out = <LangEntry>[];
    try {
      final proc = await Process.start(helperPath, ['desc', id]);
      await proc.stdin.close();
      final killer = Timer(const Duration(seconds: 60), () => proc.kill());
      await for (final line
          in proc.stdout
              .transform(utf8.decoder)
              .transform(const LineSplitter())) {
        try {
          final j = jsonDecode(line) as Map<String, dynamic>;
          if (j['event'] == 'lang') {
            out.add(
              LangEntry(
                j['lang'] as String? ?? '',
                j['title'] as String? ?? '',
                j['desc'] as String? ?? '',
              ),
            );
          }
        } catch (_) {}
      }
      await proc.exitCode;
      killer.cancel();
    } catch (_) {}
    if (out.isNotEmpty) _itemLangsCache[id] = out;
    return out;
  }

  Future<void> refreshRemote() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      await _refreshRemoteInner();
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _refreshRemoteInner() async {
    if (engine == 'steamworks' && File(helperPath).existsSync()) {
      Process? proc;
      try {
        proc = await Process.start(helperPath, ['list', '322330']);
        await proc.stdin.close();
        final p = proc;

        final killTimer = Timer(const Duration(seconds: 40), () => p.kill());
        final errFuture = proc.stderr
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .toList();
        final items = <WorkshopItemRemote>[];
        String? error;
        var ok = false;
        await for (final line
            in proc.stdout
                .transform(utf8.decoder)
                .transform(const LineSplitter())) {
          try {
            final j = jsonDecode(line) as Map<String, dynamic>;
            if (j['event'] == 'item') {
              final tags = (j['tags'] as String? ?? '')
                  .split(',')
                  .map((t) => t.trim())
                  .where((t) => t.isNotEmpty)
                  .toList();

              var ver = versionFromMeta(j['meta'] as String?);
              if (ver.isEmpty) {
                final vt = tags.firstWhere(
                  (t) => t.startsWith('version:'),
                  orElse: () => '',
                );
                if (vt.isNotEmpty) ver = vt.substring('version:'.length);
              }
              items.add(
                WorkshopItemRemote(
                  id: j['id'].toString(),
                  title: j['title'] as String? ?? '(无标题)',
                  subs: (j['subs'] as num?)?.toInt() ?? 0,
                  favorites: (j['favorites'] as num?)?.toInt() ?? 0,
                  comments: (j['comments'] as num?)?.toInt() ?? 0,
                  views: (j['views'] as num?)?.toInt() ?? 0,
                  votesUp: (j['votesUp'] as num?)?.toInt() ?? 0,
                  votesDown: (j['votesDown'] as num?)?.toInt() ?? 0,
                  score: (j['score'] as num?)?.toDouble() ?? 0,
                  updated: j['updated'] != null && (j['updated'] as num) > 0
                      ? DateTime.fromMillisecondsSinceEpoch(
                          (j['updated'] as num).toInt() * 1000,
                        )
                      : null,
                  tags: tags,
                  version: ver,
                  previewUrl: j['preview'] as String? ?? '',
                  description: j['desc'] as String? ?? '',
                  visibility: (j['visibility'] as num?)?.toInt() ?? -1,
                ),
              );
            } else if (j['event'] == 'result') {
              ok = j['ok'] == true;
              if (!ok) error = j['error']?.toString();
            }
          } catch (_) {}
        }
        final errLines = await errFuture;
        final code = await proc.exitCode;
        killTimer.cancel();
        if (ok) {
          remoteItems = items;
          log(
            LogLevel.info,
            items.isEmpty
                ? 'QueryUserUGC → 0 个条目:该账号尚未发布过工坊模组(功能正常)'
                : 'QueryUserUGC → ${items.length} 个条目(零配置,来自 Steam 会话)',
          );
        } else {
          final noise = RegExp(r'minidump|breakpad|API loaded|SetMinidump');
          for (final line in errLines) {
            if (!noise.hasMatch(line)) log(LogLevel.warn, '[helper] $line');
          }
          log(
            LogLevel.warn,
            '拉取名下条目失败:${error ?? '助手退出($code)'} —— 不影响发布,稍后自动重试',
          );
        }
      } catch (e) {
        proc?.kill();
        log(LogLevel.warn, '拉取名下条目出错:$e —— 不影响发布');
      }
      notifyListeners();
      return;
    }

    if (webApiKey.isEmpty || steamId64.isEmpty) {
      log(
        LogLevel.warn,
        'steamcmd 引擎下拉取名下条目需配置 Web API Key / SteamID64(设置页);切回 Steamworks 引擎则零配置',
      );
      return;
    }
    try {
      remoteItems = await fetchUserItems(
        apiKey: webApiKey,
        steamId64: steamId64,
      );
      log(LogLevel.info, 'GetUserFiles → ${remoteItems.length} 个条目');
    } catch (e) {
      log(LogLevel.error, '拉取工坊条目失败:$e');
    }
    notifyListeners();
  }
}
