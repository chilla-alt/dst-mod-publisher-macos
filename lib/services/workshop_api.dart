import 'dart:convert';
import 'dart:io';

class WorkshopItemRemote {
  final String id;
  final String title;
  final int subs;
  final int favorites;
  final int comments;
  final int views;
  final int votesUp;
  final int votesDown;
  final double score;
  final DateTime? updated;
  final List<String> tags;

  final String version;

  final String previewUrl;

  final String description;

  final int visibility;

  const WorkshopItemRemote({
    required this.id,
    required this.title,
    required this.subs,
    this.favorites = 0,
    this.comments = 0,
    this.views = 0,
    this.votesUp = 0,
    this.votesDown = 0,
    this.score = 0,
    this.updated,
    this.tags = const [],
    this.version = '',
    this.previewUrl = '',
    this.description = '',
    this.visibility = -1,
  });

  double get rating {
    final total = votesUp + votesDown;
    return total > 0 ? votesUp / total : score;
  }
}

class NewsItem {
  final String title;
  final String url;
  final DateTime date;
  final String feed;
  const NewsItem({
    required this.title,
    required this.url,
    required this.date,
    required this.feed,
  });
}

Future<List<NewsItem>> fetchDstNews({int count = 6}) async {
  final uri = Uri.https(
    'api.steampowered.com',
    '/ISteamNews/GetNewsForApp/v0002/',
    {'appid': '322330', 'count': '$count', 'maxlength': '1', 'format': 'json'},
  );
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
  try {
    final req = await client.getUrl(uri);
    final res = await req.close().timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return [];
    final j =
        jsonDecode(await res.transform(utf8.decoder).join())
            as Map<String, dynamic>;
    final items = (j['appnews']?['newsitems'] as List?) ?? const [];
    return [
      for (final it in items.cast<Map<String, dynamic>>())
        NewsItem(
          title: it['title'] as String? ?? '',
          url: it['url'] as String? ?? '',
          date: DateTime.fromMillisecondsSinceEpoch(
            ((it['date'] as num?)?.toInt() ?? 0) * 1000,
          ),
          feed: it['feedlabel'] as String? ?? '',
        ),
    ];
  } catch (_) {
    return [];
  } finally {
    client.close();
  }
}

String versionFromMeta(String? meta) {
  final m = (meta ?? '').trim();
  return RegExp(r'^\d[\w.\-]{0,30}$').hasMatch(m) ? m : '';
}

Future<List<WorkshopItemRemote>> fetchUserItems({
  required String apiKey,
  required String steamId64,
  int appId = 322330,
}) async {
  final uri = Uri.https(
    'api.steampowered.com',
    '/IPublishedFileService/GetUserFiles/v1/',
    {
      'key': apiKey,
      'steamid': steamId64,
      'appid': '$appId',
      'numperpage': '100',
      'return_details': 'true',
      'return_tags': 'true',
      'return_long_description': 'true',
    },
  );

  final client = HttpClient();
  try {
    final req = await client.getUrl(uri);
    final res = await req.close();
    if (res.statusCode != 200) {
      throw Exception('Steam Web API HTTP ${res.statusCode}');
    }
    final body = await res.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final files =
        (json['response']?['publishedfiledetails'] as List?) ?? const [];
    return files.map((f) {
      final m = f as Map<String, dynamic>;
      return WorkshopItemRemote(
        id: '${m['publishedfileid']}',
        title: m['title'] as String? ?? '(无标题)',
        subs: (m['subscriptions'] as num?)?.toInt() ?? 0,
        updated: m['time_updated'] != null
            ? DateTime.fromMillisecondsSinceEpoch(
                (m['time_updated'] as num).toInt() * 1000,
              )
            : null,
        tags:
            (m['tags'] as List?)
                ?.map((t) => '${(t as Map)['tag']}')
                .where((t) => t.isNotEmpty)
                .toList() ??
            const [],
        previewUrl: m['preview_url'] as String? ?? '',
        description: m['file_description'] as String? ?? '',
        visibility: (m['visibility'] as num?)?.toInt() ?? -1,
      );
    }).toList();
  } finally {
    client.close();
  }
}
