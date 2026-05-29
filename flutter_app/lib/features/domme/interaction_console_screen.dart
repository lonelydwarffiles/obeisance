import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/services/dom_sub_interaction_service.dart';

class InteractionConsoleScreen extends ConsumerStatefulWidget {
  const InteractionConsoleScreen({
    super.key,
    required this.subId,
    this.subName = 'Sub',
    this.contractId = '',
  });

  final String subId;
  final String subName;
  final String contractId;

  @override
  ConsumerState<InteractionConsoleScreen> createState() =>
      _InteractionConsoleScreenState();
}

class _InteractionConsoleScreenState
    extends ConsumerState<InteractionConsoleScreen> {
  static const List<String> _knownCapabilities = <String>[
    'lock_device',
    'message_sub',
    'restrict_packages',
    'revoke_authority',
  ];

  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _contractId;
  InteractionContractSummary? _contract;
  List<InteractionCommandResult> _commands = const [];
  List<InteractionReceipt> _receipts = const [];
  List<ActiveConstraint> _constraints = const [];
  Set<String> _editedCapabilities = <String>{};

  @override
  void initState() {
    super.initState();
    _contractId = widget.contractId;
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final service = ref.read(domSubInteractionServiceProvider);
      final contractId = await _ensureContractId(service);
      if (contractId == null) {
        throw const _ConsoleException(
            'Unable to resolve interaction contract.');
      }

      final results = await Future.wait([
        service.fetchContract(contractId),
        service.fetchCommands(contractId),
        service.fetchReceipts(contractId),
        service.fetchActiveConstraints(contractId),
      ]);

      if (!mounted) {
        return;
      }

      final contract = results[0] as InteractionContractSummary;
      setState(() {
        _contractId = contractId;
        _contract = contract;
        _commands = results[1] as List<InteractionCommandResult>;
        _receipts = results[2] as List<InteractionReceipt>;
        _constraints = results[3] as List<ActiveConstraint>;
        _editedCapabilities = contract.capabilities.toSet();
      });
    } on _ConsoleException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
      });
    } on DioException {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = 'Unable to load interaction console.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<String?> _ensureContractId(DomSubInteractionService service) async {
    if (_contractId != null && _contractId!.isNotEmpty) {
      return _contractId;
    }

    try {
      final created = await service.createContract(
        subId: widget.subId,
        capabilities: _knownCapabilities.take(3).toList(growable: false),
      );
      _contractId = created.contractId;
      return _contractId;
    } on DioException catch (error) {
      final detail = error.response?.data;
      if (detail is Map) {
        final detailMap = detail['detail'];
        if (detailMap is Map) {
          final contractId = detailMap['contract_id'];
          if (contractId is String && contractId.isNotEmpty) {
            _contractId = contractId;
            return _contractId;
          }
        }
      }
      rethrow;
    }
  }

  Future<void> _activateContract() async {
    final contractId = _contractId;
    if (contractId == null || contractId.isEmpty) {
      return;
    }

    await _withBusy(() async {
      final service = ref.read(domSubInteractionServiceProvider);
      await service.activateContract(contractId);
      await _refresh();
    });
  }

  Future<void> _pauseContract() async {
    final contractId = _contractId;
    if (contractId == null || contractId.isEmpty) {
      return;
    }

    final reason = await _promptForReason('Pause Contract');
    if (reason == null) {
      return;
    }

    await _withBusy(() async {
      final service = ref.read(domSubInteractionServiceProvider);
      await service.pauseContract(contractId, reason: reason);
      await _refresh();
    });
  }

  Future<void> _revokeContract() async {
    final contractId = _contractId;
    if (contractId == null || contractId.isEmpty) {
      return;
    }

    final reason = await _promptForReason('Revoke Contract');
    if (reason == null) {
      return;
    }

    await _withBusy(() async {
      final service = ref.read(domSubInteractionServiceProvider);
      await service.revokeContract(contractId, reason: reason);
      await _refresh();
    });
  }

  Future<void> _saveCapabilities() async {
    final contractId = _contractId;
    if (contractId == null || contractId.isEmpty) {
      return;
    }

    await _withBusy(() async {
      final service = ref.read(domSubInteractionServiceProvider);
      await service.updateCapabilities(
        contractId,
        _editedCapabilities.toList(growable: false)..sort(),
      );
      await _refresh();
    });
  }

  Future<void> _issueCommand(String commandType) async {
    final contractId = _contractId;
    if (contractId == null || contractId.isEmpty) {
      return;
    }

    await _withBusy(() async {
      final service = ref.read(domSubInteractionServiceProvider);
      final command = await service.issueCommand(
        contractId,
        commandType: commandType,
        requiresSubAck: true,
        payload: {'source': 'interaction_console'},
        expiresAfterSeconds: 1800,
      );
      if (command.status == 'pending_confirmation') {
        await service.confirmCommand(command.commandId);
      }
      await _refresh();
    });
  }

  Future<void> _confirmPendingCommand(String commandId) async {
    await _withBusy(() async {
      final service = ref.read(domSubInteractionServiceProvider);
      await service.confirmCommand(commandId);
      await _refresh();
    });
  }

  Future<void> _withBusy(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await action();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Updated successfully.')),
      );
    } on DioException catch (error) {
      if (!mounted) {
        return;
      }
      final message = error.response?.data is Map
          ? ((error.response!.data as Map)['detail']?.toString() ??
              'Request failed.')
          : 'Request failed.';
      setState(() {
        _error = message;
      });
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<String?> _promptForReason(String title) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Enter reason',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Submit'),
            ),
          ],
        );
      },
    );
    controller.dispose();

    if (reason == null || reason.isEmpty) {
      return null;
    }
    return reason;
  }

  @override
  Widget build(BuildContext context) {
    final contract = _contract;
    final pendingConfirmations = _commands
        .where((item) => item.status == 'pending_confirmation')
        .toList(growable: false);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        title: Text('Interaction Console • ${widget.subName}'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _refresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                  ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Contract State',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text('Contract: ${contract?.contractId ?? '--'}'),
                        Text('Status: ${contract?.status ?? '--'}'),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonal(
                              onPressed: _busy ? null : _activateContract,
                              child: const Text('Activate'),
                            ),
                            FilledButton.tonal(
                              onPressed: _busy ? null : _pauseContract,
                              child: const Text('Pause'),
                            ),
                            FilledButton(
                              onPressed: _busy ? null : _revokeContract,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFC62828),
                              ),
                              child: const Text('Revoke'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Capabilities',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: _knownCapabilities
                              .map(
                                (capability) => FilterChip(
                                  label: Text(capability),
                                  selected:
                                      _editedCapabilities.contains(capability),
                                  onSelected: _busy
                                      ? null
                                      : (selected) {
                                          setState(() {
                                            if (selected) {
                                              _editedCapabilities
                                                  .add(capability);
                                            } else {
                                              _editedCapabilities
                                                  .remove(capability);
                                            }
                                          });
                                        },
                                ),
                              )
                              .toList(growable: false),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.tonal(
                            onPressed: _busy ? null : _saveCapabilities,
                            child: const Text('Save Capabilities'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Issue Command',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            FilledButton.tonal(
                              onPressed: _busy
                                  ? null
                                  : () => _issueCommand('lock_device'),
                              child: const Text('Lock Device'),
                            ),
                            FilledButton.tonal(
                              onPressed: _busy
                                  ? null
                                  : () => _issueCommand('message_sub'),
                              child: const Text('Message Sub'),
                            ),
                            FilledButton.tonal(
                              onPressed: _busy
                                  ? null
                                  : () => _issueCommand('restrict_packages'),
                              child: const Text('Restrict Packages'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Pending Confirmations',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        if (pendingConfirmations.isEmpty)
                          const Text(
                            'No pending confirmation commands.',
                            style: TextStyle(color: Colors.black54),
                          ),
                        for (final command in pendingConfirmations)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(command.commandType),
                            subtitle: Text('status=${command.status}'),
                            trailing: TextButton(
                              onPressed: _busy
                                  ? null
                                  : () =>
                                      _confirmPendingCommand(command.commandId),
                              child: const Text('Confirm'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Active Constraints',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        if (_constraints.isEmpty)
                          const Text(
                            'No active constraints.',
                            style: TextStyle(color: Colors.black54),
                          ),
                        for (final constraint in _constraints)
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title:
                                Text('${constraint.key}: ${constraint.value}'),
                            subtitle: Text(constraint.reason ?? '--'),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Recent Receipts',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        if (_receipts.isEmpty)
                          const Text(
                            'No receipts available.',
                            style: TextStyle(color: Colors.black54),
                          ),
                        for (final receipt in _receipts.take(12))
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(receipt.title),
                            subtitle: Text(receipt.detail),
                            trailing: Text(
                              _formatTimestamp(receipt.createdAt),
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.black54),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  String _formatTimestamp(DateTime? value) {
    if (value == null) {
      return '--';
    }
    final local = value.toLocal();
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$month/$day $hour:$minute';
  }
}

class _ConsoleException implements Exception {
  const _ConsoleException(this.message);

  final String message;
}
