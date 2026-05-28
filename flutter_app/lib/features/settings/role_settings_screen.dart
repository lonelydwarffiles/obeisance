import 'package:flutter/material.dart';

typedef TermUpdate = void Function(
  String value, {
  bool isCustom,
  bool requestGlobalApproval,
});

abstract class LibraryService {
  Future<List<String>> getApprovedTerms(String category);
}

class DynamicTermField extends StatefulWidget {
  const DynamicTermField({
    required this.category,
    required this.onUpdate,
    required this.libraryService,
    super.key,
    this.labelText,
    this.initialValue,
  });

  final String category;
  final TermUpdate onUpdate;
  final LibraryService libraryService;
  final String? labelText;
  final String? initialValue;

  @override
  State<DynamicTermField> createState() => _DynamicTermFieldState();
}

class _DynamicTermFieldState extends State<DynamicTermField> {
  static const _customOption = '__custom__';

  final _customController = TextEditingController();
  List<String> _terms = const [];
  bool _loading = true;
  String? _selected;
  bool _isCustom = false;
  bool _requestApproval = false;

  @override
  void initState() {
    super.initState();
    _loadTerms();
  }

  Future<void> _loadTerms() async {
    setState(() => _loading = true);
    try {
      final terms = await widget.libraryService.getApprovedTerms(widget.category);
      final initial = widget.initialValue;
      final isInitialCustom = initial != null && initial.isNotEmpty && !terms.contains(initial);
      setState(() {
        _terms = terms;
        _isCustom = isInitialCustom;
        _selected = isInitialCustom ? _customOption : initial;
        if (isInitialCustom) _customController.text = initial!;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _emitStandard(String value) =>
      widget.onUpdate(value, isCustom: false, requestGlobalApproval: false);

  void _emitCustom() {
    final value = _customController.text.trim();
    if (value.isEmpty) return;
    widget.onUpdate(value, isCustom: true, requestGlobalApproval: _requestApproval);
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }

    return InputDecorator(
      decoration: InputDecoration(
        labelText: widget.labelText ?? widget.category,
        border: const OutlineInputBorder(),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            value: _selected,
            isExpanded: true,
            hint: const Text('Select a term'),
            items: [
              ..._terms.map(
                (term) => DropdownMenuItem<String>(value: term, child: Text(term)),
              ),
              const DropdownMenuItem<String>(value: _customOption, child: Text('Custom...')),
            ],
            onChanged: (value) {
              if (value == null) return;
              setState(() {
                _selected = value;
                _isCustom = value == _customOption;
                if (!_isCustom) _requestApproval = false;
              });
              if (!_isCustom) {
                _emitStandard(value);
              } else {
                _emitCustom();
              }
            },
          ),
          if (_isCustom) ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: _customController,
              decoration: const InputDecoration(
                labelText: 'Custom value',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => _emitCustom(),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Request global approval'),
              value: _requestApproval,
              onChanged: (value) {
                setState(() => _requestApproval = value);
                _emitCustom();
              },
            ),
          ],
        ],
      ),
    );
  }
}
