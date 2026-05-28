import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

// ---------------------------------------------------------------------------
// Shared constants
// ---------------------------------------------------------------------------

const _backendBaseUrl = 'http://<backend-url>';
const _accentColor = Color(0xFFE0B84C);
const _surfaceColor = Color(0xFF171717);
const _bgColor = Color(0xFF0D0D0D);

// ---------------------------------------------------------------------------
// Data models
// ---------------------------------------------------------------------------

class _InvoiceData {
  const _InvoiceData({
    required this.invoiceId,
    required this.amountCentral,
    required this.amountDomme,
    required this.amountTotal,
  });

  final String invoiceId;
  final double amountCentral;
  final double amountDomme;
  final double amountTotal;

  factory _InvoiceData.fromJson(Map<String, dynamic> json) {
    return _InvoiceData(
      invoiceId: (json['invoice_id'] as String?) ?? '',
      amountCentral: _parseDouble(json['amount_central']),
      amountDomme: _parseDouble(json['amount_domme']),
      amountTotal: _parseDouble(json['amount_total']),
    );
  }

  static double _parseDouble(Object? value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }
}

// ---------------------------------------------------------------------------
// PaymentDashboard – sub-facing invoice + QR + tribute
// ---------------------------------------------------------------------------

class PaymentDashboard extends StatefulWidget {
  const PaymentDashboard({
    super.key,
    required this.dommeId,
    required this.deviceId,
  });

  final String dommeId;
  final String deviceId;

  @override
  State<PaymentDashboard> createState() => _PaymentDashboardState();
}

class _PaymentDashboardState extends State<PaymentDashboard> {
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _backendBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  bool _loading = true;
  String? _error;
  _InvoiceData? _invoice;

  final _tributeAmountController = TextEditingController();
  final _tributeMessageController = TextEditingController();
  bool _sendingTribute = false;

  @override
  void initState() {
    super.initState();
    _fetchInvoice();
  }

  Future<void> _fetchInvoice() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/api/ledger/invoice',
        data: {
          'domme_id': widget.dommeId,
          'device_id': widget.deviceId,
        },
      );
      if (!mounted) return;
      setState(() {
        _invoice = _InvoiceData.fromJson(response.data ?? {});
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _extractDetail(e) ?? 'Unable to load invoice.';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Unable to load invoice.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendTribute() async {
    final amountText = _tributeAmountController.text.trim();
    final amount = double.tryParse(amountText);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid tribute amount.')),
      );
      return;
    }
    setState(() => _sendingTribute = true);
    try {
      await _dio.post<void>(
        '/api/ledger/tribute',
        data: {
          'recipient_id': widget.dommeId,
          'amount': amount,
          'message': _tributeMessageController.text.trim(),
        },
      );
      if (!mounted) return;
      _tributeAmountController.clear();
      _tributeMessageController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tribute sent.')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_extractDetail(e) ?? 'Tribute failed.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tribute failed.')),
      );
    } finally {
      if (mounted) setState(() => _sendingTribute = false);
    }
  }

  String? _extractDetail(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic> && data['detail'] is String) {
      return data['detail'] as String;
    }
    return null;
  }

  String _buildQrPayload(_InvoiceData invoice) {
    return jsonEncode({
      'invoice_id': invoice.invoiceId,
      'amount_total': invoice.amountTotal,
      'currency': 'USDC',
    });
  }

  @override
  void dispose() {
    _dio.close();
    _tributeAmountController.dispose();
    _tributeMessageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Payment Dashboard'),
        actions: [
          IconButton(
            onPressed: _fetchInvoice,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null)
                    _ErrorBanner(message: _error!),
                  if (_invoice != null) ...[
                    _InvoiceSummaryCard(invoice: _invoice!),
                    const SizedBox(height: 16),
                    _QrInvoiceCard(qrData: _buildQrPayload(_invoice!)),
                    const SizedBox(height: 24),
                  ],
                  _TributeCard(
                    amountController: _tributeAmountController,
                    messageController: _tributeMessageController,
                    sending: _sendingTribute,
                    onSend: _sendTribute,
                  ),
                ],
              ),
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Sub-widgets for PaymentDashboard
// ---------------------------------------------------------------------------

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.redAccent.withOpacity(0.5)),
      ),
      child: Text(message, style: const TextStyle(color: Colors.redAccent)),
    );
  }
}

class _InvoiceSummaryCard extends StatelessWidget {
  const _InvoiceSummaryCard({required this.invoice});
  final _InvoiceData invoice;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accentColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Amount Owed',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Text(
            '\$${invoice.amountTotal.toStringAsFixed(2)} USDC',
            style: const TextStyle(
              color: _accentColor,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          const Divider(color: Colors.white12),
          const SizedBox(height: 8),
          _SplitRow(label: 'Platform Fee', amount: invoice.amountCentral),
          const SizedBox(height: 4),
          _SplitRow(label: 'Service Fee', amount: invoice.amountDomme),
        ],
      ),
    );
  }
}

class _SplitRow extends StatelessWidget {
  const _SplitRow({required this.label, required this.amount});
  final String label;
  final double amount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: Colors.white54, fontSize: 13)),
        Text(
          '\$${amount.toStringAsFixed(2)}',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
      ],
    );
  }
}

class _QrInvoiceCard extends StatelessWidget {
  const _QrInvoiceCard({required this.qrData});
  final String qrData;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          const Text(
            'Scan to Pay',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 16),
          Center(
            child: QrImageView(
              data: qrData,
              version: QrVersions.auto,
              size: 200,
              backgroundColor: Colors.white,
              errorCorrectionLevel: QrErrorCorrectLevel.M,
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Pay with USDC on Solana or Ethereum',
            style: TextStyle(color: Colors.white38, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _TributeCard extends StatelessWidget {
  const _TributeCard({
    required this.amountController,
    required this.messageController,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController amountController;
  final TextEditingController messageController;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: _surfaceColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Send a Tribute',
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: amountController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Amount (USDC)',
              labelStyle: TextStyle(color: Colors.white54),
              prefixText: '\$ ',
              prefixStyle: TextStyle(color: Colors.white70),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: _accentColor),
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: messageController,
            maxLines: 2,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Message (optional)',
              labelStyle: TextStyle(color: Colors.white54),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white24),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: _accentColor),
              ),
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: sending ? null : onSend,
              style: FilledButton.styleFrom(
                backgroundColor: _accentColor,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              icon: sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : const Icon(Icons.favorite_border),
              label: const Text('Send Tribute', style: TextStyle(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// DommeBillingSettings – domme sets markup and fee-pass-through toggle
// ---------------------------------------------------------------------------

class DommeBillingSettings extends StatefulWidget {
  const DommeBillingSettings({
    super.key,
    required this.dommeId,
  });

  final String dommeId;

  @override
  State<DommeBillingSettings> createState() => _DommeBillingSettingsState();
}

class _DommeBillingSettingsState extends State<DommeBillingSettings> {
  final Dio _dio = Dio(
    BaseOptions(
      baseUrl: _backendBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ),
  );

  bool _loading = true;
  bool _saving = false;
  String? _error;

  final _markupController = TextEditingController();
  bool _passCentralFeeToSub = true;

  @override
  void initState() {
    super.initState();
    _fetchCurrentSettings();
  }

  Future<void> _fetchCurrentSettings() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await _dio.get<Map<String, dynamic>>(
        '/api/ledger/lease-tier/${widget.dommeId}',
      );
      final data = response.data ?? {};
      if (!mounted) return;
      setState(() {
        _markupController.text =
            (data['domme_markup'] as num?)?.toStringAsFixed(2) ?? '0.00';
        _passCentralFeeToSub = (data['pass_central_to_sub'] as bool?) ?? true;
      });
    } on DioException {
      // No existing tier is fine; use defaults
    } catch (_) {
      // Ignore; use defaults
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _saveSettings() async {
    final markupText = _markupController.text.trim();
    final markup = double.tryParse(markupText);
    if (markup == null || markup < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid markup amount.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await _dio.post<void>(
        '/api/ledger/lease-tier',
        data: {
          'domme_id': widget.dommeId,
          'domme_markup': markup,
          'pass_central_to_sub': _passCentralFeeToSub,
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Billing settings saved.')),
      );
    } on DioException catch (e) {
      if (!mounted) return;
      final data = e.response?.data;
      final detail =
          data is Map<String, dynamic> && data['detail'] is String
              ? data['detail'] as String
              : 'Failed to save settings.';
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(detail)));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save settings.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _dio.close();
    _markupController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF111111),
        title: const Text('Billing Settings'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_error != null) _ErrorBanner(message: _error!),
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: _surfaceColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Service Markup',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'The additional fee you charge your sub on top of the platform fee.',
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _markupController,
                          keyboardType:
                              const TextInputType.numberWithOptions(decimal: true),
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            labelText: 'Markup Amount (USDC)',
                            labelStyle: TextStyle(color: Colors.white54),
                            prefixText: '\$ ',
                            prefixStyle: TextStyle(color: Colors.white70),
                            enabledBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: Colors.white24),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderSide: BorderSide(color: _accentColor),
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Divider(color: Colors.white12),
                        const SizedBox(height: 12),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Pass Central Fee to Sub',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'When enabled, the sub pays the platform infrastructure cost.',
                                    style: TextStyle(color: Colors.white54, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                            Switch(
                              value: _passCentralFeeToSub,
                              activeColor: _accentColor,
                              onChanged: (value) =>
                                  setState(() => _passCentralFeeToSub = value),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SizedBox(
                          width: double.infinity,
                          child: FilledButton(
                            onPressed: _saving ? null : _saveSettings,
                            style: FilledButton.styleFrom(
                              backgroundColor: _accentColor,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: _saving
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.black),
                                  )
                                : const Text(
                                    'Save Settings',
                                    style: TextStyle(fontWeight: FontWeight.w700),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
