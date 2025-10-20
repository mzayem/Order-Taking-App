// lib/screens/cash_screen.dart
import 'package:flutter/material.dart';
import '../db/database.dart';

class CashScreen extends StatefulWidget {
  // When this is provided, screen will load that transaction for editing
  final int? transactionId;
  const CashScreen({super.key, this.transactionId});

  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();

  String? _selectedCustomer;
  bool _isSaving = false;
  bool _isLoading = false;

  // Dummy list until API available
  final List<String> _dummyCustomers = [
    "Ali",
    "Ahmed",
    "Sara",
    "Hassan",
    "Ahsan",
  ];

  @override
  void initState() {
    super.initState();
    if (widget.transactionId != null) {
      _loadExisting(widget.transactionId!);
    }
  }

  Future<void> _loadExisting(int transactionId) async {
    setState(() => _isLoading = true);
    try {
      final rows = await AppDatabase.getTransactionWithDetails(transactionId);
      if (rows.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      final header = rows.first;
      final db = await AppDatabase.init();
      final custId = header['CustomerID'] as int?;
      if (custId != null) {
        final custRows = await db.query('Customer',
            where: 'CustomerID = ?', whereArgs: [custId], limit: 1);
        if (custRows.isNotEmpty) {
          _selectedCustomer = custRows.first['Name'] as String?;
        }
      }

      final cash = (header['CashAmount'] ?? 0.0) as num;
      _amountController.text = cash.toString();
      _remarksController.text = (header['Remarks'] ?? '') as String;
    } catch (e) {
      debugPrint('Error loading cash transaction: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveCashPayment() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomer == null || _selectedCustomer!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a customer")),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final customerId =
          await AppDatabase.insertCustomerIfNotExists(_selectedCustomer!);
      final cashAmount = double.tryParse(_amountController.text.trim()) ?? 0.0;

      // If screen was opened for editing a specific transactionId -> update that
      if (widget.transactionId != null) {
        await AppDatabase.updateTransactionAndReplaceDetails(
          transactionId: widget.transactionId!,
          customerId: customerId,
          type: 'Cash',
          details: const [],
          cashAmount: cashAmount,
          remarks: _remarksController.text.trim(),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cash updated (local)')));
      } else {
        // Otherwise fallback: check same-customer same-day to update or create
        final existingId = await AppDatabase.findTransactionForCustomerOnDate(
            customerId, 'Cash', DateTime.now());

        if (existingId != null) {
          await AppDatabase.updateTransactionAndReplaceDetails(
            transactionId: existingId,
            customerId: customerId,
            type: 'Cash',
            details: const [],
            cashAmount: cashAmount,
            remarks: _remarksController.text.trim(),
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Cash updated (local)')));
        } else {
          final txnId = await AppDatabase.createTransactionWithDetails(
            customerId: customerId,
            type: 'Cash',
            details: const [],
            cashAmount: cashAmount,
            remarks: _remarksController.text.trim(),
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Cash saved (local) id: $txnId')));
        }
      }

      if (!mounted) return;
      setState(() {
        _selectedCustomer = null;
        _amountController.clear();
        _remarksController.clear();
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error saving cash: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  InputDecoration inputDecoration(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF6F6F6),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 16, horizontal: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEBEBEB)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFEBEBEB)),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final customers = _dummyCustomers; // replace with API list later

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title:
              Text(widget.transactionId == null ? 'Cash Payment' : 'Edit Cash'),
          backgroundColor: Colors.black,
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.transactionId == null ? 'Cash Payment' : 'Edit Cash'),
        centerTitle: true,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(18.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              const SizedBox(height: 20),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text("Select Customer",
                    style:
                        TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              const SizedBox(height: 10),
              Autocomplete<String>(
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text.isEmpty) {
                    return const Iterable<String>.empty();
                  }
                  return customers.where((String option) {
                    return option
                        .toLowerCase()
                        .contains(textEditingValue.text.toLowerCase());
                  });
                },
                onSelected: (String selection) {
                  setState(() => _selectedCustomer = selection);
                },
                fieldViewBuilder:
                    (context, controller, focusNode, onEditingComplete) {
                  controller.text = _selectedCustomer ?? '';
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onEditingComplete: onEditingComplete,
                    decoration: inputDecoration("Select Customer"),
                  );
                },
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: inputDecoration("Enter Amount (Rs)"),
                validator: (v) {
                  if (v == null || v.isEmpty) return 'Enter amount';
                  final value = double.tryParse(v);
                  if (value == null || value <= 0) {
                    return 'Enter valid positive number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveCashPayment,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: _isSaving
                      ? const CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2)
                      : Text(
                          widget.transactionId == null
                              ? "Save Cash Payment"
                              : "Update Cash",
                          style: const TextStyle(fontSize: 16),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
