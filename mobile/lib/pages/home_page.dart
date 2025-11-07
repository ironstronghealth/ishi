// lib/pages/home_page.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/api.dart';
import '../services/news_api.dart';
import 'app_title_bar.dart';
import 'news_detail_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<NewsItem>? _news;
  String? _newsError;
  bool _loadingNews = false;
  bool _checkedVersion = false;

  @override
  void initState() {
    super.initState();
    _checkVersion();
    _loadNews();
  }

  // ---- version gating ----
  int _cmpVersion(String a, String b) {
    List<int> parse(String v) => v
        .split('.')
        .map((e) => int.tryParse(e.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    final pa = parse(a), pb = parse(b);
    final len = (pa.length > pb.length) ? pa.length : pb.length;
    for (int i = 0; i < len; i++) {
      final ai = (i < pa.length) ? pa[i] : 0;
      final bi = (i < pb.length) ? pb[i] : 0;
      if (ai < bi) return -1;
      if (ai > bi) return 1;
    }
    return 0;
  }

  Future<void> _checkVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final current = info.version;
      final required = ApiConfig.minAppVersion;
      if (_cmpVersion(current, required) < 0 && mounted) {
        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Update required'),
            content: Text(
              'A newer version of ISHI is available.\n\n'
              'Installed: $current\n'
              'Required:  $required\n\n'
              'Please update to continue.',
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final uri = Uri.parse(ApiConfig.storeUrl);
                  await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
                },
                child: const Text('Update'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Later'),
              ),
            ],
          ),
        );
      }
    } catch (_) {
      // ignore
    } finally {
      if (mounted) setState(() => _checkedVersion = true);
    }
  }

  // ---- news loading ----
  Future<void> _loadNews() async {
    setState(() {
      _loadingNews = true;
      _newsError = null;
    });
    try {
      final url = ApiConfig.newsUrl();
      debugPrint('NEWS URL => $url');
      final items = await NewsApi.fetch();
      setState(() => _news = items);
    } catch (e) {
      debugPrint('NEWS ERROR => $e');
      setState(() => _newsError = e.toString());
    } finally {
      if (mounted) setState(() => _loadingNews = false);
    }
  }

  void _openNews(NewsItem item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => NewsDetailPage(title: item.title, url: item.url),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const AppTitleBar(logoSize: 48, titleFontSize: 16),
        actions: [
          IconButton(
            tooltip: 'Refresh news',
            onPressed: _loadingNews ? null : _loadNews,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadNews,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const Text(
                  'Health News',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                if (_loadingNews) ...[
                  const SizedBox(width: 8),
                  const SizedBox(
                    height: 16, width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
            if (_newsError != null)
              Card(
                color: Colors.red[50],
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    'Failed to load news.\n$_newsError',
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              )
            else if (_news == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_news!.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: Text('No news right now.')),
              )
            else
              ..._news!.map((n) => Card(
                    elevation: 0,
                    child: ListTile(
                      title: Text(n.title),
                      subtitle: Text(n.source),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _openNews(n),
                    ),
                  )),
            const SizedBox(height: 24),
            if (!_checkedVersion && kDebugMode)
              const Center(
                child: Text(
                  'Checking app version…',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
