import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class PraiseItem {
  const PraiseItem({
    required this.id,
    required this.title,
    required this.description,
    required this.iconName,
  });

  final String id;
  final String title;
  final String description;
  final String iconName;
}

class PraiseGallery extends StatefulWidget {
  const PraiseGallery({required this.deviceId, super.key});

  final String deviceId;

  @override
  State<PraiseGallery> createState() => _PraiseGalleryState();
}

class _PraiseGalleryState extends State<PraiseGallery> {
  static const _backendBaseUrl = 'http://<backend-url>';

  late final Dio _dio;
  bool _loading = true;
  String? _error;
  List<PraiseItem> _items = const [];

  @override
  void initState() {
    super.initState();
    _dio = Dio(BaseOptions(baseUrl: _backendBaseUrl));
    _fetchPraise();
  }

  Future<void> _fetchPraise() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await _dio.get<List<dynamic>>(
        '/api/praise/${widget.deviceId}',
      );
      final items = (res.data ?? [])
          .whereType<Map>()
          .map((e) => PraiseItem(
                id: (e['id'] as String?) ?? '',
                title: (e['title'] as String?) ?? '',
                description: (e['description'] as String?) ?? '',
                iconName: (e['icon'] as String?) ?? 'star',
              ))
          .toList();
      if (mounted) setState(() => _items = items);
    } catch (_) {
      if (mounted) setState(() => _error = 'Unable to load praise gallery.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _dio.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Praise Gallery')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.redAccent)))
              : _items.isEmpty
                  ? const Center(child: Text('No medals yet. Keep going!'))
                  : RefreshIndicator(
                      onRefresh: _fetchPraise,
                      child: GridView.builder(
                        padding: const EdgeInsets.all(16),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          return _PraiseTile(item: item);
                        },
                      ),
                    ),
    );
  }
}

class _PraiseTile extends StatelessWidget {
  const _PraiseTile({required this.item});
  final PraiseItem item;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.star, size: 36, color: Color(0xFFE0B84C)),
            const SizedBox(height: 8),
            Text(
              item.title,
              style: const TextStyle(fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              item.description,
              style: Theme.of(context).textTheme.bodySmall,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
