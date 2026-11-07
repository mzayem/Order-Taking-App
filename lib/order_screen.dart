// lib/screens/order_screen.dart
import 'package:flutter/material.dart';
import 'package:dmc/widgets/app_toast.dart';
import 'package:dmc/theme/app_theme.dart';
import 'package:dmc/widgets/page_hero.dart';
import 'package:dmc/widgets/skeleton.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../db/database.dart';
import 'services/api_service.dart';
import 'home_screen.dart';

class OrderScreen extends StatefulWidget {
  final int? transactionId;
  final List<Map<String, dynamic>> customers;
  final List<Map<String, dynamic>> products;

  const OrderScreen({
    super.key,
    this.transactionId,
    this.customers = const [],
    this.products = const [],
  });

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> with WidgetsBindingObserver {
  late List<Map<String, dynamic>> customers;
  late List<Map<String, dynamic>> products;

  String? selectedCustomer;
  Map<String, dynamic>? selectedCustomerObj;
  Map<String, dynamic>? selectedProduct;

  final TextEditingController qtyController = TextEditingController();
  final FocusNode _qtyFocusNode = FocusNode();
  List<Map<String, dynamic>> selectedProducts = [];
  static const String _draftKey = "order_draft";
  bool _isLoading = false;
  final bool _isSaving = false;
  bool _isLoadingData = true;

  double customerBalance = 0.0;
  bool isBalanceLoading = false;

  FocusNode? _productFocusNode;
  FocusNode? _customerFocusNode; // fast entry: back here after each save

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    customers = widget.customers;
    products = widget.products;

    _loadInitialData();
    _restoreDraft(); // NEW
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _saveDraft();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _saveDraft() async {
    if (selectedCustomer == null || selectedProducts.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();

    final draft = {
      "customer": selectedCustomer,
      "customerObj": selectedCustomerObj,
      "products": selectedProducts,
      "balance": customerBalance,
    };

    await prefs.setString(
      _draftKey,
      jsonEncode(draft),
    );

    print("DRAFT SAVED");
  }

  Future<void> _restoreDraft() async {
    final prefs = await SharedPreferences.getInstance();

    final draftString = prefs.getString(_draftKey);

    if (draftString == null) return;

    final draft = jsonDecode(draftString);

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            "Resume Last Order",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          content: const Text(
            "You have an unfinished order.\nDo you want to continue?",
          ),
          actions: [
            ElevatedButton(
              style: AppButtons.dangerSoft,
              onPressed: () async {
                await prefs.remove(_draftKey);

                Navigator.pop(context);
              },
              child: const Text(
                "Start New",
              ),
            ),
            ElevatedButton(
              style: AppButtons.primary,
              onPressed: () {
                setState(() {
                  selectedCustomer = draft["customer"];
                  selectedCustomerObj =
                      Map<String, dynamic>.from(draft["customerObj"]);

                  selectedProducts =
                      List<Map<String, dynamic>>.from(draft["products"]);

                  customerBalance = (draft["balance"] ?? 0).toDouble();
                });

                Navigator.pop(context);

                print("DRAFT RESTORED");
              },
              child: const Text(
                "Resume",
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoadingData = true);

    await _loadCustomersFromDB();
    await _loadProductsFromDB();

    if (widget.transactionId != null) {
      await _loadExistingTransaction(widget.transactionId!);
    }

    if (mounted) setState(() => _isLoadingData = false);
  }

  Future<void> _loadCustomersFromDB() async {
    try {
      final db = await AppDatabase.init();
      final rows = await db.query('Customer');

      print("========= CUSTOMER DATA =========");

      for (final row in rows.take(5)) {
        print(row);
      }

      final maps = rows
          .map((r) => {
                "id": r['CustomerID'],
                "name": r['Name'],
                "address": r['Address'] ?? '',
                "isNarcoticsAllowed": r['IsNarcotics'] == 1,
              })
          .toList();

      if (mounted) setState(() => customers = maps);
    } catch (e) {
      debugPrint("DB err: $e");
    }
  }

  Future<void> _loadProductsFromDB() async {
    try {
      final db = await AppDatabase.init();
      final rows = await db.query('Product');
      final Map<String, Map<String, dynamic>> uniqueProd = {};
      for (var r in rows) {
        final name = r['Name'] as String;
        final id = r['ProductID'] as int;
        if (!uniqueProd.containsKey(name) ||
            (uniqueProd[name]!['id'] ?? 0) < id) {
          uniqueProd[name] = {
            'id': id,
            'name': name,
            'price': (r['UnitPrice'] as num).toDouble(),
            'availableQty': r['AvailableQty'] as int,
            'type': r['ProductType'],
          };
        }
      }
      if (mounted) setState(() => products = uniqueProd.values.toList());
    } catch (e) {
      debugPrint("DB err: $e");
    }
  }

  /// FETCH DATA FROM API
  Future<void> _fetchCustomerBalance(int customerId) async {
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

      print("BALANCE API STATUS: ${response.statusCode}");
      print("BALANCE API BODY: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'success') {
          if (mounted) {
            setState(() {
              customerBalance = (data['balance'] ?? 0).toDouble();
            });
          }
        }
      }
    } catch (e) {
      print("Balance fetch error: $e");
    } finally {
      if (mounted) {
        setState(() {
          isBalanceLoading = false;
        });
      }
    }
  }

  /// LOAD EXISTING ORDER

  Future<void> addProduct() async {
    if (selectedCustomerObj == null) {
      AppToast.show(context, "Select customer first", type: ToastType.warning);
      return;
    }

    if (selectedProduct != null && qtyController.text.isNotEmpty) {
      final qty = int.tryParse(qtyController.text) ?? 0;
      final available = selectedProduct!['availableQty'] as int? ?? 0;

      if (qty <= 0) {
        AppToast.show(context, "Enter valid quantity", type: ToastType.warning);
        _qtyFocusNode.requestFocus(); // cursor goes to what needs fixing
        return;
      }

      if (qty > available) {
        bool? proceed = await showDialog<bool>(
          context: context,
          builder: (context) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              title: const Text("Quantity Exceeds",
                  style: TextStyle(fontWeight: FontWeight.w600)),
              content: const Text(
                  "The entered quantity exceeds the available stock. Do you want to add it anyway?"),
              actions: [
                ElevatedButton(
                  style: AppButtons.neutral,
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text("No"),
                ),
                ElevatedButton(
                  style: AppButtons.primary,
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text("Yes"),
                ),
              ],
            );
          },
        );

        if (proceed != true) {
          return;
        }
        if (!mounted) return;
      }

      // Narcotics warning
      if ((selectedProduct!['type']?.toString() ?? '') == "Narcotics" &&
          (selectedCustomerObj!['isNarcoticsAllowed'] as bool? ?? true) ==
              false) {
        AppToast.show(context, "Narcotics not allowed to this customer",
            type: ToastType.warning);
      }

      final price = (selectedProduct!['price'] as num? ?? 0).toDouble();

      final productName = selectedProduct!['name'];

      final existingIndex = selectedProducts.indexWhere(
        (p) => p['name'] == productName,
      );

      setState(() {
        if (existingIndex != -1) {
          /// UPDATE EXISTING PRODUCT
          selectedProducts[existingIndex]['qty'] = qty;
          selectedProducts[existingIndex]['total'] = qty * price;
        } else {
          /// ADD NEW PRODUCT
          selectedProducts.add({
            "id": selectedProduct!['id'],
            "name": productName,
            "qty": qty,
            "price": price,
            "total": qty * price,
          });
        }

        /// Update available quantity
        selectedProduct!['availableQty'] = available - qty;

        qtyController.clear();
        selectedProduct = null;
      });
      _productFocusNode?.requestFocus();
      await _saveDraft();
    }
  }

  double get totalAmount => selectedProducts.fold(
      0.0, (sum, item) => sum + (item['total'] as num).toDouble());

  /// LOAD EXISTING ORDER

  Future<void> _loadExistingTransaction(int transactionId) async {
    setState(() => _isLoading = true);

    final rows = await AppDatabase.getTransactionWithDetails(transactionId);

    if (rows.isNotEmpty) {
      final header = rows.first;

      final db = await AppDatabase.init();
      final custId = header['CustomerID'] as int?;
      if (custId != null) {
        final custRows = await db.query('Customer',
            where: 'CustomerID = ?', whereArgs: [custId], limit: 1);
        if (custRows.isNotEmpty) {
          selectedCustomer = custRows.first['Name'] as String?;
          selectedCustomerObj = {
            "id": custId,
            "name": selectedCustomer,
            "isNarcoticsAllowed": custRows.first['IsNarcotics'] == 1,
          };
          _fetchCustomerBalance(custId);
        }
      }

      selectedProducts = rows
          .where((r) => r['TransactionDetailID'] != null)
          .map((r) => <String, dynamic>{
                "id": r['ProductID'],
                "name": r['ProductName'],
                "qty": (r['Qty'] as num).toInt(),
                "price": (r['UnitPrice'] as num).toDouble(),
                "total": (r['TotalPrice'] as num).toDouble(),
              })
          .toList();
    }

    if (mounted) setState(() => _isLoading = false);
  }

  /// --------------------- SAVE ORDER ---------------------

  void _saveOrderAs(String type) async {
    if (selectedCustomer == null) {
      AppToast.show(context, "Please select a customer",
          type: ToastType.warning);
      return;
    }

    if (selectedProducts.isEmpty) {
      AppToast.show(context, "Add at least one product",
          type: ToastType.warning);
      return;
    }

    final custId = selectedCustomerObj?['id'] as int?;
    if (custId == null) {
      AppToast.show(context, "Select the customer from the list",
          type: ToastType.warning);
      return;
    }

    final details = <Map<String, dynamic>>[];

    for (final p in selectedProducts) {
      final prodId = p['id'] as int? ??
          await AppDatabase.insertProductIfNotExists(
            p['name'],
            unitPrice: (p['price'] as num).toDouble(),
            availableQty: 0,
          );

      details.add({
        'productId': prodId,
        'qty': p['qty'],
        'unitPrice': (p['price'] as num).toDouble(),
      });
    }

    if (widget.transactionId != null) {
      /// UPDATE EXISTING TRANSACTION

      await AppDatabase.updateTransactionAndReplaceDetails(
        transactionId: widget.transactionId!,
        customerId: custId,
        type: type,
        details: details,
      );

      /// CLEAR DRAFT AFTER SUCCESS
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);

      if (!mounted) return;

      AppToast.show(context, "$type updated (local)", type: ToastType.success);

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
        (route) => false,
      );

      return;
    }

    /// NEW ORDER

    final existingId = await AppDatabase.findTransactionForCustomerOnDate(
      custId,
      type,
      DateTime.now(),
    );

    if (existingId != null) {
      await AppDatabase.updateTransactionAndReplaceDetails(
        transactionId: existingId,
        customerId: custId,
        type: type,
        details: details,
      );

      if (!mounted) return;

      AppToast.show(context, "$type updated (local)", type: ToastType.success);
    } else {
      final txnId = await AppDatabase.createTransactionWithDetails(
        customerId: custId,
        type: type,
        details: details,
      );

      if (!mounted) return;

      AppToast.show(context, "$type saved (local) id: $txnId",
          type: ToastType.success);
    }

    /// CLEAR DRAFT AFTER SUCCESS
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey);

    if (mounted) {
      setState(() {
        selectedCustomer = null;
        selectedCustomerObj = null;
        selectedProduct = null;
        selectedProducts = [];
        qtyController.clear();
      });
      // Ready for the next customer straight away.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _customerFocusNode?.requestFocus();
      });
    }
  }

  void _cancelOrder() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            "Cancel Order",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          content: const Text(
            "Are you sure you want to cancel this order?",
          ),
          actions: [
            ElevatedButton(
              style: AppButtons.neutral,
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "No",
              ),
            ),
            ElevatedButton(
              style: AppButtons.danger,
              onPressed: () {
                Navigator.pop(context);

                if (widget.transactionId != null) {
                  /// Editing → go back to Home
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const HomeScreen(),
                    ),
                    (route) => false,
                  );
                } else {
                  /// New Order → clear form
                  setState(() {
                    selectedCustomer = null;
                    selectedCustomerObj = null;
                    selectedProduct = null;
                    selectedProducts.clear();
                    qtyController.clear();
                    customerBalance = 0.0;
                  });
                }
              },
              child: const Text(
                "Yes",
              ),
            ),
          ],
        );
      },
    );
  }

  /// UI (UNCHANGED)

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.transactionId == null ? "Order" : "Edit Order"),
        ),
        body: const FormSkeleton(),
      );
    }

    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: Text(widget.transactionId == null ? "Order" : "Edit Order"),
      ),

      /// YOUR UI BELOW IS EXACTLY SAME
      /// (I DID NOT CHANGE ANY UI STRUCTURE)

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PageHero(
              icon: Icons.shopping_cart_outlined,
              title: widget.transactionId == null ? "New order" : "Edit order",
              subtitle: "Pick a customer, add products, then save",
            ),
            const Text("Select Customer",
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Autocomplete<Map<String, dynamic>>(
              initialValue: selectedCustomer != null
                  ? TextEditingValue(text: selectedCustomer!)
                  : const TextEditingValue(),
              displayStringForOption: (option) =>
                  option['name']?.toString() ?? '',
              optionsBuilder: (TextEditingValue textEditingValue) {
                return customers.where(
                  (customer) => (customer['name']?.toString() ?? '')
                      .toLowerCase()
                      .contains(textEditingValue.text.toLowerCase()),
                );
              },
              optionsViewBuilder: (
                context,
                AutocompleteOnSelected<Map<String, dynamic>> onSelected,
                Iterable<Map<String, dynamic>> options,
              ) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    elevation: 6,
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    clipBehavior: Clip.antiAlias,
                    child: Container(
                      width: MediaQuery.of(context).size.width - 32,
                      constraints: const BoxConstraints(maxHeight: 300),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
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
                                border: Border.all(color: AppColors.hairline),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                            fontSize: 20,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    customer['address'] ?? '',
                                    style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 14,
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
              onSelected: (selection) async {
                final custId = selection['id'];

                setState(() {
                  selectedCustomer = selection['name']?.toString() ?? '';
                  selectedCustomerObj = selection;
                });

                _fetchCustomerBalance(selection['id']);
                await _saveDraft();
                _productFocusNode?.requestFocus();

                final existingId =
                    await AppDatabase.findTransactionForCustomerOnDate(
                  custId,
                  "Order",
                  DateTime.now(),
                );

                if (existingId != null) {
                  await _loadExistingTransaction(existingId);

                  AppToast.show(context, "Previous order loaded",
                      type: ToastType.info);
                } else {
                  setState(() {
                    selectedProducts.clear();
                  });
                }

                _productFocusNode?.requestFocus();
              },
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
                _customerFocusNode = focusNode;
                controller.text = selectedCustomer ?? '';

                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  // Enter picks the top match (then the cursor jumps to Product).
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => onFieldSubmitted(),
                  decoration: AppInput.decoration("Customer",
                      hint: "Search customer..."),
                );
              },
            ),
            const SizedBox(height: 20),
            const Text("Select Product",
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Autocomplete<Map<String, dynamic>>(
              displayStringForOption: (option) => "${option['name']}  ",
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text.isEmpty) {
                  return const Iterable<Map<String, dynamic>>.empty();
                }

                final query = textEditingValue.text.toLowerCase();
                return products.where((p) {
                  final nameLow = p['name'].toLowerCase();
                  return nameLow.startsWith(query);
                });
              },
              onSelected: (selection) {
                final productName = selection['name'];

                setState(() {
                  selectedProduct = selection;
                });

                /// Check if product already exists in list
                final existingIndex = selectedProducts.indexWhere(
                  (p) => p['name'] == productName,
                );

                if (existingIndex != -1) {
                  final existingQty = selectedProducts[existingIndex]['qty'];

                  qtyController.text = existingQty.toString();
                } else {
                  qtyController.clear();
                }

                _qtyFocusNode.requestFocus();
              },
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
                _productFocusNode = focusNode;
                controller.text = selectedProduct?['name'] ?? '';

                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  // Enter picks the top match (then the cursor jumps to QTY).
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) => onFieldSubmitted(),
                  decoration:
                      AppInput.decoration("Product", hint: "Search product..."),
                );
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: qtyController,
                    focusNode: _qtyFocusNode,
                    decoration: AppInput.decoration("QTY"),
                    keyboardType: TextInputType.number,
                    // Enter adds the product; the cursor goes back to Product.
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => addProduct(),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    readOnly: true,
                    decoration: AppInput.decoration("Available",
                        icon: Icons.inventory_2_outlined,
                        hint: selectedProduct != null
                            ? selectedProduct!['availableQty'].toString()
                            : "Available QTY"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: addProduct,
                style: AppButtons.primarySoft,
                child: const Text("Add Product"),
              ),
            ),
            const SizedBox(height: 20),
            if (selectedProducts.isNotEmpty) ...[
              const Text("Selected Products",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              SizedBox(
                height: 240,
                child: ListView.builder(
                  itemCount: selectedProducts.length,
                  itemBuilder: (context, i) {
                    final p = selectedProducts[i];

                    return Card(
                      elevation: 3,
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        title: Text(p['name'],
                            style:
                                const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle:
                            Text("Qty: ${p['qty']}   Price: Rs.${p['price']}"),
                        trailing: IconButton(
                          icon: Icon(Icons.delete, color: AppColors.red),
                          onPressed: () async {
                            setState(() => selectedProducts.removeAt(i));

                            await _saveDraft();
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Total Amount: Rs.${totalAmount.toStringAsFixed(2)}",
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                isBalanceLoading
                    ? const Text("Loading balance...")
                    : Text(
                        "Remaining Balance: Rs.${customerBalance.toStringAsFixed(2)}",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: AppColors.red,
                        ),
                      ),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _cancelOrder,
                    style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14))
                        .merge(AppButtons.neutral),
                    child: const Text("Cancel"),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _saveOrderAs("Order"),
                    style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14))
                        .merge(AppButtons.primary),
                    child: _isSaving
                        ? SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                color: AppColors.onBrand, strokeWidth: 2),
                          )
                        : const Text("Save"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
