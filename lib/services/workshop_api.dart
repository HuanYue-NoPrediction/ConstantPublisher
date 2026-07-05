import 'dart:convert';
import 'dart:io';

/// 可选:通过 Steam Web API 拉取账号名下的工坊条目(工坊页巡检用)。
/// 需要在设置页填 Web API Key(steamcommunity.com/dev/apikey)和 SteamID64。
/// 拉不到也不影响发布 —— 发布真相源永远是本地 dstpub.json。
class WorkshopItemRemote {
  final String id;
  final String title;
  final int subs;
  final DateTime? updated;
  final List<String> tags;

  /// 工坊版本号:来自条目 metadata(本工具发布时写入;老条目为空)。
  final String version;

  /// 工坊封面图 CDN 直链(可能为空)。
  final String previewUrl;

  const WorkshopItemRemote({
    required this.id,
    required this.title,
    required this.subs,
    this.updated,
    this.tags = const [],
    this.version = '',
    this.previewUrl = '',
  });
}

/// metadata 里长得像版本号才认(防止其他工具写的任意内容混进来)。
String versionFromMeta(String? meta) {
  final m = (meta ?? '').trim();
  return RegExp(r'^\d[\w.\-]{0,30}$').hasMatch(m) ? m : '';
}

Future<List<WorkshopItemRemote>> fetchUserItems({
  required String apiKey,
  required String steamId64,
  int appId = 322330,
}) async {
  final uri = Uri.https('api.steampowered.com',
      '/IPublishedFileService/GetUserFiles/v1/', {
    'key': apiKey,
    'steamid': steamId64,
    'appid': '$appId',
    'numperpage': '100',
    'return_details': 'true',
    'return_tags': 'true',
  });

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
                (m['time_updated'] as num).toInt() * 1000)
            : null,
        tags: (m['tags'] as List?)
                ?.map((t) => '${(t as Map)['tag']}')
                .where((t) => t.isNotEmpty)
                .toList() ??
            const [],
        previewUrl: m['preview_url'] as String? ?? '',
      );
    }).toList();
  } finally {
    client.close();
  }
}
