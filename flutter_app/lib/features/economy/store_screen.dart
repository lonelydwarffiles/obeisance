import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class StoreScreen extends StatefulWidget {
  const StoreScreen({
    super.key,
    required this.deviceId,
    this.currencyName = 'Compliance Credits',
  });

  final String deviceId;
  final String currencyName;

  @override
  State<StoreScreen> createState() => _StoreScreenState();
}

class _StoreScreenState extends State<StoreScreen> {
  static const _backendBaseUrl = 'http://<backend-url>';

  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _backendBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  bool _loading = true;
  String? _error;
  int _balance = 0;
  String? _purchasingItemId;
  List<StoreItemView> _items = const [];

  @override
  void initState() {
    super.initState();
    _refreshStore();
  }

  Future<void> _refreshStore() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _dio.get<List<dynamic>>('/api/store/${widget.deviceId}');
      final entries = (response.data ?? [])
          .whereType<Map>()
          .map((entry) => StoreItemView.fromJson(Map<String, dynamic>.from(entry)))
          .toList();
      final balanceHeader = response.headers.value('x-grace-balance');
      final parsedBalance = int.tryParse(balanceHeader ?? '');

      if (!mounted) {
        return;
      }
      setState(() {
        _items = entries;
        _balance = parsedBalance ?? _balance;
      });
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error =
            error.response?.data is Map<String, dynamic> && error.response?.data['detail'] is String
                ? error.response?.data['detail'] as String
                : 'Unable to load store items.';
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Unable to load store items.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _purchase(StoreItemView item) async {
    if (_purchasingItemId != null) {
      return;
    }

    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Purchase'),
        content: Text('Spend ${item.cost} ${widget.currencyName} to purchase ${item.title}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (approved != true || !mounted) {
      return;
    }

    setState(() {
      _purchasingItemId = item.id;
    });

    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/store/purchase/${item.id}',
        data: {'device_id': widget.deviceId},
      );
      final remainingBalance = response.data?['remaining_balance'];
      if (!mounted) {
        return;
      }
      setState(() {
        if (remainingBalance is int) {
          _balance = remainingBalance;
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Purchased ${item.title}.')),
      );
      await _refreshStore();
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }
      final message =
          error.response?.data is Map<String, dynamic> && error.response?.data['detail'] is String
              ? error.response?.data['detail'] as String
              : 'Purchase failed.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Purchase failed.')));
    } finally {
      if (mounted) {
        setState(() {
          _purchasingItemId = null;
        });
      }
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
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Grace Store'),
        actions: [
          IconButton(
            onPressed: _refreshStore,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshStore,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF171717),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFE0B84C)),
                    ),
                    child: Text(
                      'Balance: $_balance ${widget.currencyName}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(
                        _error!,
                        style: const TextStyle(color: Colors.redAccent),
                      ),
                    ),
                  const SizedBox(height: 12),
                  for (final item in _items)
                    Card(
                      color: const Color(0xFF171717),
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: item.isCentral ? const Color(0xFFE0B84C) : Colors.white12,
                          width: item.isCentral ? 1.4 : 1.0,
                        ),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                item.title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            if (item.isCentral)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE0B84C).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFFE0B84C)),
                                ),
                                child: const Text(
                                  'SYSTEM',
                                  style: TextStyle(
                                    color: Color(0xFFE0B84C),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            item.description,
                            style: const TextStyle(color: Colors.white70),
                          ),
                        ),
                        trailing: _purchasingItemId == item.id
                            ? const SizedBox(
                                width: 26,
                                height: 26,
                                child: CircularProgressIndicator(strokeWidth: 2.4),
                              )
                            : FilledButton(
                                onPressed: _balance < item.cost ? null : () => _purchase(item),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFE0B84C),
                                  foregroundColor: Colors.black,
                                ),
                                child: Text('${item.cost}'),
                              ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class StoreItemView {
  const StoreItemView({
    required this.id,
    required this.title,
    required this.description,
    required this.cost,
    required this.isCentral,
  });

  final String id;
  final String title;
  final String description;
  final int cost;
  final bool isCentral;

  factory StoreItemView.fromJson(Map<String, dynamic> json) {
    return StoreItemView(
      id: (json['id'] as String?) ?? '',
      title: (json['title'] as String?) ?? 'Untitled',
      description: (json['description'] as String?) ?? '',
      cost: (json['cost'] as int?) ?? 0,
      isCentral: (json['is_central'] as bool?) ?? false,
    );
  }
}
