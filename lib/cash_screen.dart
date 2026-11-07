// lib/screens/cash_screen.dart

import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../db/database.dart';
import 'services/api_service.dart';
import 'home_screen.dart';

class CashScreen extends StatefulWidget {
  final int? transactionId;
  const CashScreen({super.key, this.transactionId});

  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _remarksController = TextEditingController();

  final FocusNode _amountFocusNode = FocusNode();

  String? _selectedCustomer;
  bool _isSaving = false;
  bool _isLoading = false;
  bool _isLoadingData = true;

  List<String> _customers = [];
  List<Map<String, dynamic>> _customersMap = [];
  double customerBalance = 0.0;
  bool isBalanceLoading = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoadingData = true);
    await _fetchCustomers();
    if (widget.transactionId != null) {
      await _loadExisting(widget.transactionId!);
    }
    setState(() => _isLoadingData = false);
  }

  Future<void> _fetchCustomers() async {
    final db = await AppDatabase.init();
    final custRows = await db.query('Customer');

    final customers = custRows.map((r) {
      return {
        "id": r['CustomerID'],
        "name": r['Name'],
        "address": r['Address'] ?? '',
      };
    }).toList();

    if (mounted) {
      setState(() {
        _customersMap = customers;
      });
    }
  }

  Future<void> _fetchCustomerBalance(int customerId) async {
    if (customerId == 0) return;
    final prefs = await SharedPreferences.getInstance();

    final baseUrl = prefs.getString('baseUrl') ?? '';
    final userId = prefs.getString('userId') ?? '';

    if (baseUrl.isEmpty || userId.isEmpty) return;

    setState(() {
      isBalanceLoading = true;
    });

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/Customer/balanceFetch'),
        headers: {
          "accept": "*/*",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "userId": userId,
          "customerId": customerId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'success') {
          setState(() {
            customerBalance = (data['balance'] ?? 0).toDouble();
          });
        }
      }
    } catch (e) {
      debugPrint("Balance fetch error: $e");
    } finally {
      if (mounted) {
        setState(() {
          isBalanceLoading = false;
        });
      }
    }
  }

  Future<void> _loadCustomersFromDB() async {
    await _fetchCustomers();
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
          _fetchCustomerBalance(custId);
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
        Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (_) => const HomeScreen()),
            (route) => false);
        return;
      } else {
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
    if (_isLoadingData) {
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
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.all(18.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                const Text(
                  "Select Customer",
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                Autocomplete<Map<String, dynamic>>(
                  displayStringForOption: (option) =>
                      option['name']?.toString() ?? '',
                  optionsBuilder: (TextEditingValue textEditingValue) {
                    if (textEditingValue.text.isEmpty) {
                      return const Iterable<Map<String, dynamic>>.empty();
                    }

                    return _customersMap.where((customer) {
                      return (customer['name'] ?? '')
                          .toString()
                          .toLowerCase()
                          .contains(
                            textEditingValue.text.toLowerCase(),
                          );
                    });
                  },
                  optionsViewBuilder: (
                    context,
                    onSelected,
                    options,
                  ) {
                    return Align(
                      alignment: Alignment.topLeft,
                      child: Material(
                        elevation: 4,
                        child: Container(
                          width: MediaQuery.of(context).size.width - 36,
                          constraints: const BoxConstraints(maxHeight: 300),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: options.length,
                            itemBuilder: (context, index) {
                              final customer = options.elementAt(index);

                              return InkWell(
                                onTap: () => onSelected(customer),
                                child: Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 4,
                                    vertical: 4,
                                  ),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    border: Border.all(
                                      color: Colors.black12,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade300,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              "#${customer['id']}",
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              customer['name'] ?? '',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 16,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        customer['address'] ?? '',
                                        style: TextStyle(
                                          color: Colors.grey.shade700,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    );
                  },
                  onSelected: (selection) {
                    setState(() {
                      _selectedCustomer = selection['name']?.toString() ?? '';
                    });

                    _fetchCustomerBalance(selection['id']);

                    _amountFocusNode.requestFocus();
                  },
                  fieldViewBuilder: (
                    context,
                    controller,
                    focusNode,
                    onEditingComplete,
                  ) {
                    controller.text = _selectedCustomer ?? '';

                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      onEditingComplete: onEditingComplete,
                      decoration: inputDecoration("Select Customer"),
                    );
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _amountController,
                  focusNode: _amountFocusNode,
                  textInputAction: TextInputAction.done,
                  keyboardType: TextInputType.number,
                  decoration: inputDecoration("Enter Amount (Rs)"),
                  validator: (v) {
                    if (v == null || v.isEmpty) {
                      return 'Enter amount';
                    }

                    final value = double.tryParse(v);

                    if (value == null || value <= 0) {
                      return 'Enter valid positive number';
                    }

                    return null;
                  },
                ),
                const SizedBox(height: 30),
                if (_selectedCustomer != null && _selectedCustomer!.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: isBalanceLoading
                        ? const Text(
                            "Loading balance...",
                            style: TextStyle(
                              color: Colors.grey,
                            ),
                          )
                        : Text(
                            "Remaining Balance: Rs.${customerBalance.toStringAsFixed(2)}",
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: Colors.red,
                            ),
                          ),
                  ),
                const SizedBox(height: 50),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveCashPayment,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 14,
                      ),
                    ),
                    child: _isSaving
                        ? const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          )
                        : Text(
                            widget.transactionId == null
                                ? "Save Cash Payment"
                                : "Update Cash",
                            style: const TextStyle(fontSize: 16),
                          ),
                  ),
                ),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
