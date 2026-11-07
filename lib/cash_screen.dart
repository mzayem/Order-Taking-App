// lib/screens/cash_screen.dart

import 'package:flutter/material.dart';
import 'package:dmc/widgets/app_toast.dart';
import 'package:dmc/theme/app_theme.dart';
import 'package:dmc/widgets/page_hero.dart';
import 'package:dmc/widgets/skeleton.dart';
import 'dart:convert';
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
  final FocusNode _remarksFocusNode = FocusNode();
  FocusNode? _customerFocusNode; // fast entry: back here after each save

  String? _selectedCustomer;
  int? _selectedCustomerId;
  int? _selectedVendorGroupId; // optional; null = ungrouped payment
  List<Map<String, dynamic>> _vendorGroups = [];
  bool _isSaving = false;
  bool _isLoading = false;
  bool _isLoadingData = true;

  final List<String> _customers = [];
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
    _vendorGroups = await AppDatabase.getVendorGroups();
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
      final response = await ApiService.post(
        Uri.parse('$baseUrl/api/Customer/balanceFetch'),
        headers: await ApiService.headers(),
        body: jsonEncode({
          "userId": userId,
          "customerId": customerId,
        }),
      );
      await ApiService.handleUnauthorized(response);

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
          _selectedCustomerId = custId;
          _fetchCustomerBalance(custId);
        }
      }

      final cash = (header['CashAmount'] ?? 0.0) as num;
      _amountController.text = cash.toString();
      _remarksController.text = (header['Remarks'] ?? '') as String;
      _selectedVendorGroupId = header['VendorGroupID'] as int?;
    } catch (e) {
      debugPrint('Error loading cash transaction: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveCashPayment() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomerId == null) {
      AppToast.show(context, "Please select a customer",
          type: ToastType.warning);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final customerId = _selectedCustomerId!;
      final cashAmount = double.tryParse(_amountController.text.trim()) ?? 0.0;

      if (widget.transactionId != null) {
        await AppDatabase.updateTransactionAndReplaceDetails(
          transactionId: widget.transactionId!,
          customerId: customerId,
          type: 'Cash',
          details: const [],
          cashAmount: cashAmount,
          remarks: _remarksController.text.trim(),
          vendorGroupId: _selectedVendorGroupId,
        );
        if (!mounted) return;
        AppToast.show(context, 'Cash updated (local)', type: ToastType.success);
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
            vendorGroupId: _selectedVendorGroupId,
          );
          if (!mounted) return;
          AppToast.show(context, 'Cash updated (local)',
              type: ToastType.success);
        } else {
          final txnId = await AppDatabase.createTransactionWithDetails(
            customerId: customerId,
            type: 'Cash',
            details: const [],
            cashAmount: cashAmount,
            remarks: _remarksController.text.trim(),
            vendorGroupId: _selectedVendorGroupId,
          );
          if (!mounted) return;
          AppToast.show(context, 'Cash saved (local) id: $txnId',
              type: ToastType.success);
        }
      }

      if (!mounted) return;
      setState(() {
        _selectedCustomer = null;
        _selectedCustomerId = null;
        _amountController.clear();
        _remarksController.clear();
        _selectedVendorGroupId = null;
      });
      // Ready for the next customer straight away.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _customerFocusNode?.requestFocus();
      });
    } catch (e) {
      AppToast.show(context, 'Error saving cash: $e', type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Themed field (readable in light and dark), with an icon from the label.
  InputDecoration inputDecoration(String label) => AppInput.decoration(label);

  @override
  void dispose() {
    _amountFocusNode.dispose();
    _remarksFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return Scaffold(
        appBar: AppBar(
          title:
              Text(widget.transactionId == null ? 'Cash Payment' : 'Edit Cash'),
        ),
        body: const FormSkeleton(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.transactionId == null ? 'Cash Payment' : 'Edit Cash'),
        centerTitle: true,
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
                PageHero(
                  icon: Icons.payments_outlined,
                  title: widget.transactionId == null
                      ? "Cash payment"
                      : "Edit cash payment",
                  subtitle: "Record money received from a customer",
                ),
                const Text(
                  "Select Customer",
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
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
                        elevation: 6,
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        clipBehavior: Clip.antiAlias,
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
                                      color: AppColors.hairline,
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
                                              color: AppColors.surfaceMuted,
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                            ),
                                            child: Text(
                                              "#${customer['id']}",
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              customer['name'] ?? '',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
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
                                          color: AppColors.textSecondary,
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
                      _selectedCustomerId = selection['id'] as int?;
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
                    _customerFocusNode = focusNode;
                    controller.text = _selectedCustomer ?? '';

                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      textInputAction: TextInputAction.next,
                      onEditingComplete: onEditingComplete,
                      decoration: inputDecoration("Select Customer"),
                    );
                  },
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _amountController,
                  focusNode: _amountFocusNode,
                  // Enter moves on to Remarks.
                  textInputAction: TextInputAction.next,
                  onFieldSubmitted: (_) => _remarksFocusNode.requestFocus(),
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
                const SizedBox(height: 10),
                DropdownButtonFormField<int?>(
                  initialValue: _vendorGroups.any(
                          (g) => g['VendorGroupID'] == _selectedVendorGroupId)
                      ? _selectedVendorGroupId
                      : null,
                  isExpanded: true,
                  decoration: inputDecoration("Vendor Group (optional)"),
                  items: [
                    const DropdownMenuItem<int?>(
                        value: null, child: Text("No vendor group")),
                    for (final g in _vendorGroups)
                      DropdownMenuItem<int?>(
                        value: g['VendorGroupID'] as int,
                        child: Text(g['Name']?.toString() ?? ''),
                      ),
                  ],
                  onChanged: (v) => setState(() => _selectedVendorGroupId = v),
                ),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _remarksController,
                  focusNode: _remarksFocusNode,
                  maxLength: 200, // matches the server's Remarks limit
                  maxLines: 2,
                  textInputAction: TextInputAction.done,
                  decoration: inputDecoration("Remarks (optional)"),
                ),
                const SizedBox(height: 20),
                if (_selectedCustomer != null && _selectedCustomer!.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: isBalanceLoading
                        ? Text(
                            "Loading balance...",
                            style: TextStyle(
                              color: AppColors.textSecondary,
                            ),
                          )
                        : Text(
                            "Remaining Balance: Rs.${customerBalance.toStringAsFixed(2)}",
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.red,
                            ),
                          ),
                  ),
                const SizedBox(height: 50),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isSaving ? null : _saveCashPayment,
                    style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                      vertical: 14,
                    )).merge(AppButtons.primary),
                    child: _isSaving
                        ? CircularProgressIndicator(
                            color: AppColors.onBrand,
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
