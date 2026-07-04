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

  const WorkshopItemRemote({
    required this.id,
    required this.title,
    required this.subs,
    this.updated,
  });
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
      );
    }).toList();
  } finally {
    client.close();
  }
}
