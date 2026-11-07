// lib/screens/return_screen.dart
import 'package:flutter/material.dart';
import 'package:dmc/widgets/app_toast.dart';
import 'package:dmc/theme/app_theme.dart';
import 'package:dmc/widgets/page_hero.dart';
import 'package:dmc/widgets/skeleton.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../db/database.dart';
import 'services/api_service.dart';
import 'home_screen.dart';
import 'dart:convert';

class ReturnScreen extends StatefulWidget {
  final int? transactionId;
  const ReturnScreen({super.key, this.transactionId});

  @override
  State<ReturnScreen> createState() => _ReturnScreenState();
}

class _ReturnScreenState extends State<ReturnScreen> {
  List<Map<String, dynamic>> customers = [];
  List<Map<String, dynamic>> products = [];

  String? selectedCustomer;
  Map<String, dynamic>? selectedProduct;
  final TextEditingController qtyController = TextEditingController();
  final TextEditingController batchController = TextEditingController();
  final TextEditingController remarksController = TextEditingController();
  final TextEditingController productController = TextEditingController();
  TextEditingController? _productFieldController;
  final FocusNode _qtyFocusNode = FocusNode();
  final FocusNode _batchFocusNode = FocusNode();
  final FocusNode _remarksFocusNode = FocusNode();
  static const String _draftKey = "return_draft";
  List<Map<String, dynamic>> selectedProducts = [];
  Map<String, dynamic>? selectedCustomerObj;
  bool _isLoading = false;
  bool _isSaving = false;
  bool _isLoadingData = true;
  bool _isCheckingBatch = false;
  Key _customerFieldKey = UniqueKey();
  FocusNode? _productFocusNode;
  FocusNode? _customerFocusNode; // fast entry: back here after each save

  @override
  void initState() {
    super.initState();

    _loadInitialData();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _restoreDraft();
    });
  }

  Future<void> _autoSaveDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      final draft = {
        "customer": selectedCustomer,
        "customerObj": selectedCustomerObj,
        "products": selectedProducts,
        "remarks": remarksController.text,
      };

      await prefs.setString(_draftKey, jsonEncode(draft));

      print("RETURN DRAFT SAVED");
    } catch (e) {
      print("Draft save error: $e");
    }
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
            "Resume Last Return",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          content: const Text(
            "You have an unfinished return.\nDo you want to continue?",
          ),
          actions: [
            /// START NEW
            ElevatedButton(
              style: AppButtons.dangerSoft,
              onPressed: () async {
                await prefs.remove(_draftKey);

                Navigator.pop(context);

                if (mounted) {
                  setState(() {
                    selectedCustomer = null;
                    selectedCustomerObj = null;
                    selectedProduct = null;

                    selectedProducts.clear();

                    qtyController.clear();
                    batchController.clear();
                    remarksController.clear();
                  });
                }
              },
              child: const Text(
                "Start New",
              ),
            ),

            /// RESUME
            ElevatedButton(
              style: AppButtons.primary,
              onPressed: () {
                setState(() {
                  selectedCustomer = draft["customer"];
                  selectedCustomerObj = draft["customerObj"] == null
                      ? null
                      : Map<String, dynamic>.from(draft["customerObj"]);

                  selectedProducts =
                      List<Map<String, dynamic>>.from(draft["products"] ?? []);

                  remarksController.text = draft["remarks"] ?? "";

                  /// IMPORTANT — force Autocomplete rebuild
                  _customerFieldKey = UniqueKey();
                });

                Navigator.pop(context);

                print("RETURN DRAFT RESTORED");
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
      await _loadExisting(widget.transactionId!);
    }
    if (mounted) setState(() => _isLoadingData = false);
  }

  Future<void> _fetchCustomersAndProducts() async {
    try {
      await ApiService.fetchCustomers(); // sync DB

      final prod = await ApiService.fetchProducts();

      await _loadCustomersFromDB();

      if (mounted) {
        setState(() {
          products = prod;
        });
      }
    } catch (e) {
      debugPrint("API Error: $e");
    }
  }

  Future<void> _loadCustomersFromDB() async {
    try {
      final rows = await (await AppDatabase.init()).query('Customer');

      if (mounted) {
        setState(() {
          customers = rows.map((r) {
            return {
              "id": r['CustomerID'],
              "name": r['Name'],
              "address": r['Address'] ?? '',
              "isNarcoticsAllowed": r['IsNarcotics'] == 1,
            };
          }).toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading customers from DB: $e');
    }
  }

  Future<void> _loadProductsFromDB() async {
    try {
      final rows = await (await AppDatabase.init()).query('Product');
      final Map<String, Map<String, dynamic>> unique = {};
      for (var r in rows) {
        final name = r['Name'] as String;
        final id = r['ProductID'] as int;
        if (!unique.containsKey(name) || (unique[name]!['id'] ?? 0) < id) {
          unique[name] = {
            'id': id,
            'name': name,
            'price': (r['UnitPrice'] as num).toDouble(),
            'availableQty': r['AvailableQty'] as int,
          };
        }
      }
      if (mounted) {
        setState(() {
          products = unique.values.toList();
        });
      }
    } catch (e) {
      debugPrint('Error loading products from DB: $e');
    }
  }

  Future<void> _loadExisting(int transactionId) async {
    setState(() => _isLoading = true);
    try {
      final rows = await AppDatabase.getTransactionWithDetails(transactionId);
      if (rows.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }
      final header = rows.first;
      final db = await AppDatabase.init();
      final custRows = await db.query('Customer',
          where: 'CustomerID = ?', whereArgs: [header['CustomerID']], limit: 1);
      if (custRows.isNotEmpty) {
        selectedCustomer = custRows.first['Name'] as String;
        selectedCustomerObj = {
          'id': header['CustomerID'],
          'name': selectedCustomer,
        };
      }
      remarksController.text = header['Remarks'] ?? '';
      final loaded = <Map<String, dynamic>>[];
      for (var r in rows) {
        if (r['TransactionDetailID'] != null) {
          loaded.add({
            'id': r['ProductID'],
            'name': r['ProductName'] as String,
            'qty': (r['Qty'] as num).toInt(),
            'batch': r['BatchNo'] as String? ?? '',
            'price': (r['UnitPrice'] as num).toDouble(),
          });
        }
      }
      if (mounted) setState(() => selectedProducts = loaded);
    } catch (e) {
      debugPrint('Error loading return transaction: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> addProduct() async {
    if (selectedCustomerObj?['id'] == null) {
      AppToast.show(context, "Please select a customer",
          type: ToastType.warning);
      return;
    }

    if (selectedProduct == null) {
      AppToast.show(context, "Please select a product",
          type: ToastType.warning);
      return;
    }

    final qtyText = qtyController.text.trim();
    final batchText = batchController.text.trim();

    if (qtyText.isEmpty ||
        int.tryParse(qtyText) == null ||
        int.parse(qtyText) <= 0) {
      AppToast.show(context, "Enter a valid quantity", type: ToastType.warning);
      _qtyFocusNode.requestFocus(); // cursor goes to what needs fixing
      return;
    }

    if (batchText.isEmpty) {
      AppToast.show(context, "Enter batch number", type: ToastType.warning);
      _batchFocusNode.requestFocus();
      return;
    }

    // ── Batch API check ─────────────────────────────────────────
    setState(() => _isCheckingBatch = true);

    try {
      final productId = selectedProduct!['id'] as int;
      final customerId = selectedCustomerObj!['id'] as int;

      final result = await ApiService.checkBatch(
        productId: productId,
        batchNo: batchText,
        customerId: customerId,
      );

      if (!result['valid']) {
        final msg = result['message'] as String? ?? 'Invalid batch number';

        debugPrint('checkBatch failed: $msg');

        if (!mounted) return;

        AppToast.show(context, msg, type: ToastType.error);
        // Server refused the batch: back to the field so it can be corrected.
        _batchFocusNode.requestFocus();

        return;
      }
    } finally {
      if (mounted) {
        setState(() => _isCheckingBatch = false);
      }
    }

    // ── Add / Update Product ────────────────────────────────────

    final productName = selectedProduct!['name'] as String;
    final qty = int.parse(qtyText);

    if (mounted) {
      setState(() {
        final index = selectedProducts.indexWhere(
          (item) => item['name'] == productName && item['batch'] == batchText,
        );

        if (index != -1) {
          // UPDATE existing product + batch
          selectedProducts[index] = {
            "id": selectedProduct!['id'],
            "name": productName,
            "qty": qty,
            "batch": batchText,
            "price": selectedProduct!['price'],
          };
        } else {
          // ADD new product + batch
          selectedProducts.add({
            "id": selectedProduct!['id'],
            "name": productName,
            "qty": qty,
            "batch": batchText,
            "price": selectedProduct!['price'],
          });
        }

        // Clear fields
        selectedProduct = null;
        _productFieldController?.clear();
        qtyController.clear();
        batchController.clear();

        _productFocusNode?.requestFocus();
      });
      await _autoSaveDraft();
      // Focus back to Product field
      _productFocusNode?.requestFocus();
    }
  }

  void cancel() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            "Cancel Return",
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          content: const Text(
            "Are you sure you want to cancel this return?",
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
                  /// EDIT RETURN → go back to Home
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const HomeScreen(),
                    ),
                    (route) => false,
                  );
                } else {
                  /// NEW RETURN → clear form
                  setState(() {
                    selectedCustomer = null;
                    selectedCustomerObj = null;
                    selectedProduct = null;
                    qtyController.clear();
                    batchController.clear();
                    remarksController.clear();
                    selectedProducts.clear();
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

  Future<void> saveAs(String type) async {
    final custId = selectedCustomerObj?['id'] as int?;
    if (custId == null) {
      AppToast.show(context, "Please select customer", type: ToastType.warning);
      return;
    }

    if (selectedProducts.isEmpty) {
      AppToast.show(context, "Add at least one product to return",
          type: ToastType.warning);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final details = <Map<String, dynamic>>[];

      for (var p in selectedProducts) {
        final prodId = p['id'] as int? ??
            await AppDatabase.insertProductIfNotExists(
              p['name'],
              unitPrice: (p['price'] as num).toDouble(),
              availableQty: 0,
            );

        details.add({
          'productId': prodId,
          'batchNo': p['batch'],
          'qty': p['qty'],
          'unitPrice': (p['price'] as num).toDouble(),
        });
      }

      /// -----------------------------
      /// UPDATE EXISTING TRANSACTION
      /// -----------------------------
      if (widget.transactionId != null) {
        await AppDatabase.updateTransactionAndReplaceDetails(
          transactionId: widget.transactionId!,
          customerId: custId,
          type: type,
          details: details,
          remarks: remarksController.text.trim(),
        );

        /// NEW — Remove Draft
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_draftKey);

        if (!mounted) return;

        AppToast.show(context, "Return updated (local)",
            type: ToastType.success);

        Navigator.pushAndRemoveUntil(
          context,
          MaterialPageRoute(builder: (_) => const HomeScreen()),
          (route) => false,
        );

        return;
      }

      /// -----------------------------
      /// CHECK EXISTING TODAY RETURN
      /// -----------------------------
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
          remarks: remarksController.text.trim(),
        );

        if (!mounted) return;

        AppToast.show(context, "Return updated (local)",
            type: ToastType.success);
      } else {
        final txnId = await AppDatabase.createTransactionWithDetails(
          customerId: custId,
          type: type,
          details: details,
          remarks: remarksController.text.trim(),
        );

        if (!mounted) return;

        AppToast.show(context, "Saved as $type (local) id: $txnId",
            type: ToastType.success);
      }

      /// NEW — Remove Draft After Successful Save
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);

      /// CLEAR SCREEN
      if (mounted) {
        setState(() {
          selectedCustomer = null;
          selectedCustomerObj = null;
          selectedProduct = null;

          qtyController.clear();
          batchController.clear();
          remarksController.clear();

          selectedProducts.clear();
        });
        // Ready for the next customer straight away.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _customerFocusNode?.requestFocus();
        });
      }
    } catch (e) {
      AppToast.show(context, "Error: $e", type: ToastType.error);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // Themed field (readable in light and dark), with an icon from the label.
  InputDecoration _inputDecoration(String label) => AppInput.decoration(label);

  @override
  @override
  void dispose() {
    qtyController.dispose();
    batchController.dispose();
    remarksController.dispose();
    productController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return Scaffold(
          appBar: AppBar(
            title: const Text('Return'),
          ),
          body: const FormSkeleton());
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.transactionId == null ? 'Return' : 'Edit Return'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18.0),
          child: SingleChildScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: MediaQuery.of(context).size.height - kToolbarHeight,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  PageHero(
                    icon: Icons.assignment_return_outlined,
                    title: widget.transactionId == null
                        ? "New return"
                        : "Edit return",
                    subtitle: "Goods coming back from a customer",
                  ),
                  Autocomplete<Map<String, dynamic>>(
                    key: _customerFieldKey,
                    initialValue: selectedCustomer != null
                        ? TextEditingValue(text: selectedCustomer!)
                        : const TextEditingValue(),
                    displayStringForOption: (option) =>
                        option['name']?.toString() ?? '',
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      return customers.where((customer) {
                        return (customer['name'] ?? '')
                            .toString()
                            .toLowerCase()
                            .contains(textEditingValue.text.toLowerCase());
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
                                      border:
                                          Border.all(color: AppColors.hairline),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
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
                    onSelected: (selection) async {
                      setState(() {
                        selectedCustomer = selection['name']?.toString() ?? '';
                        selectedCustomerObj = selection;
                      });

                      final custId = selection['id'];

                      final existingId =
                          await AppDatabase.findTransactionForCustomerOnDate(
                        custId,
                        "Return",
                        DateTime.now(),
                      );

                      if (existingId != null) {
                        await _loadExisting(existingId);

                        AppToast.show(context, "Previous return loaded",
                            type: ToastType.info);
                      } else {
                        setState(() {
                          selectedProducts.clear();
                        });
                      }

                      await _autoSaveDraft();

                      _productFocusNode?.requestFocus();
                    },
                    fieldViewBuilder:
                        (context, controller, focusNode, onEditingComplete) {
                      _customerFocusNode = focusNode;
                      controller.text = selectedCustomer ?? '';

                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        textInputAction: TextInputAction.next,
                        onEditingComplete: onEditingComplete,
                        decoration: _inputDecoration("Select Customer..."),
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Autocomplete<Map<String, dynamic>>(
                    initialValue: selectedProduct != null
                        ? TextEditingValue(text: selectedProduct!['name'])
                        : const TextEditingValue(),
                    optionsBuilder: (TextEditingValue textEditingValue) {
                      if (textEditingValue.text.isEmpty) {
                        return products;
                      }
                      final query = textEditingValue.text.toLowerCase();
                      return products.where((p) {
                        final nameLow = p['name'].toString().toLowerCase();
                        return nameLow.startsWith(query);
                      });
                    },
                    displayStringForOption: (p) => p['name'] as String,
                    fieldViewBuilder:
                        (context, controller, focusNode, onEditingComplete) {
                      _productFocusNode = focusNode;
                      _productFieldController = controller;

                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        textInputAction: TextInputAction.next,
                        onEditingComplete: onEditingComplete,
                        decoration: _inputDecoration("Select Product...."),
                        onChanged: (val) {
                          final found = products.firstWhere(
                            (p) =>
                                p['name'].toString().toLowerCase() ==
                                val.toLowerCase(),
                            orElse: () => {},
                          );

                          setState(() {
                            selectedProduct = found.isNotEmpty ? found : null;
                          });
                        },
                      );
                    },
                    onSelected: (p) {
                      setState(() {
                        selectedProduct = p;

                        final productName = p['name'];

                        // Check if product already exists in list
                        final index = selectedProducts.indexWhere(
                          (item) => item['name'] == productName,
                        );

                        if (index != -1) {
                          // Load existing qty & batch
                          qtyController.text =
                              selectedProducts[index]['qty'].toString();

                          batchController.text =
                              selectedProducts[index]['batch'].toString();
                        } else {
                          // Clear if new product
                          qtyController.clear();
                          batchController.clear();
                        }
                      });

                      _qtyFocusNode.requestFocus();
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: qtyController,
                          focusNode: _qtyFocusNode,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          onSubmitted: (_) => _batchFocusNode.requestFocus(),
                          decoration: _inputDecoration("QTY"),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: batchController,
                          focusNode: _batchFocusNode,
                          onChanged: (batch) {
                            if (selectedProduct == null) return;

                            final productName = selectedProduct!['name'];

                            final index = selectedProducts.indexWhere(
                              (item) =>
                                  item['name'] == productName &&
                                  item['batch'] == batch,
                            );

                            if (index != -1) {
                              // Load existing qty
                              qtyController.text =
                                  selectedProducts[index]['qty'].toString();
                            }
                          },
                          // Enter adds the product; cursor back to Product.
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => addProduct(),
                          decoration: _inputDecoration("Batch No"),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: remarksController,
                    onChanged: (_) => _autoSaveDraft(),
                    focusNode: _remarksFocusNode,
                    textInputAction: TextInputAction.done,
                    decoration: _inputDecoration("Remarks"),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isCheckingBatch ? null : addProduct,
                      style: AppButtons.primarySoft,
                      child: _isCheckingBatch
                          ? SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                  color: AppColors.onBrand, strokeWidth: 2),
                            )
                          : const Text("Add Product"),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    "Selected Products",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),
                  selectedProducts.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(
                              "No products added",
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: selectedProducts.length,
                          itemBuilder: (context, i) {
                            final p = selectedProducts[i];

                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: ListTile(
                                title: Text(
                                  p['name'],
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  "QTY: ${p['qty']}    Batch: ${p['batch']}",
                                ),
                                trailing: IconButton(
                                  icon: Icon(
                                    Icons.delete,
                                    color: AppColors.red,
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      selectedProducts.removeAt(i);
                                    });
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8.0, top: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: cancel,
                            style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14))
                                .merge(AppButtons.neutral),
                            child: const Text("Cancel"),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => saveAs("Return"),
                            style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                        vertical: 14))
                                .merge(AppButtons.primary),
                            child: _isSaving
                                ? SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                        color: AppColors.onBrand,
                                        strokeWidth: 2),
                                  )
                                : const Text("Save"),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(height: MediaQuery.of(context).padding.bottom),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
