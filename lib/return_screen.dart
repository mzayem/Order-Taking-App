// lib/screens/return_screen.dart
import 'package:flutter/material.dart';
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
  List<String> customers = [];
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
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Text(
            "You have an unfinished return.\nDo you want to continue?",
          ),
          actions: [
            /// START NEW
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              onPressed: () async {
                await prefs.remove(_draftKey);

                Navigator.pop(context);

                if (mounted) {
                  setState(() {
                    selectedCustomer = null;
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
                style: TextStyle(color: Colors.white),
              ),
            ),

            /// RESUME
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
              ),
              onPressed: () {
                setState(() {
                  selectedCustomer = draft["customer"];

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
                style: TextStyle(color: Colors.white),
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
      final cust = await ApiService.fetchCustomers();
      final prod = await ApiService.fetchProducts();

      if (mounted) {
        setState(() {
          customers = cust;
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
          customers = rows.map((r) => r['Name'] as String).toSet().toList();
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
            'price': (r['UnitPrice'] as num).toInt(),
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
      }
      remarksController.text = header['Remarks'] ?? '';
      final loaded = <Map<String, dynamic>>[];
      for (var r in rows) {
        if (r['TransactionDetailID'] != null) {
          loaded.add({
            'name': r['ProductName'] as String,
            'qty': (r['Qty'] as num).toInt(),
            'batch': r['BatchNo'] as String? ?? '',
            'price': (r['UnitPrice'] as num).toInt(),
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
    if (selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please select a customer")));
      return;
    }

    if (selectedProduct == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please select a product")));
      return;
    }

    final qtyText = qtyController.text.trim();
    final batchText = batchController.text.trim();

    if (qtyText.isEmpty ||
        int.tryParse(qtyText) == null ||
        int.parse(qtyText) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Enter a valid quantity")));
      return;
    }

    if (batchText.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Enter batch number")));
      return;
    }

    // ── Batch API check ─────────────────────────────────────────
    setState(() => _isCheckingBatch = true);

    try {
      final db = await AppDatabase.init();

      final productName = selectedProduct!['name'] as String;

      // Resolve ProductID
      final prodRows = await db.query(
        'Product',
        where: 'Name = ?',
        whereArgs: [productName],
        limit: 1,
      );

      final productId =
          prodRows.isNotEmpty ? (prodRows.first['ProductID'] as int) : 0;

      // Resolve CustomerID
      final custRows = await db.query(
        'Customer',
        where: 'Name = ?',
        whereArgs: [selectedCustomer!],
        limit: 1,
      );

      final customerId =
          custRows.isNotEmpty ? (custRows.first['CustomerID'] as int) : 0;

      final result = await ApiService.checkBatch(
        productId: productId,
        batchNo: batchText,
        customerId: customerId,
      );

      if (!result['valid']) {
        final msg = result['message'] as String? ?? 'Invalid batch number';

        debugPrint('checkBatch failed: $msg');

        if (!mounted) return;

        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(msg)));

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
            "name": productName,
            "qty": qty,
            "batch": batchText,
            "price": selectedProduct!['price'],
          };
        } else {
          // ADD new product + batch
          selectedProducts.add({
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
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: const Text(
            "Are you sure you want to cancel this return?",
          ),
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              onPressed: () => Navigator.pop(context),
              child: const Text(
                "No",
                style: TextStyle(color: Colors.white),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
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
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> saveAs(String type) async {
    if (selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please select customer")));
      return;
    }

    if (selectedProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Add at least one product to return")));
      return;
    }

    setState(() => _isSaving = true);

    try {
      final custId =
          await AppDatabase.insertCustomerIfNotExists(selectedCustomer!);

      final details = <Map<String, dynamic>>[];

      for (var p in selectedProducts) {
        final prodId = await AppDatabase.insertProductIfNotExists(
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

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Return updated (local)")),
        );

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

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Return updated (local)")),
        );
      } else {
        final txnId = await AppDatabase.createTransactionWithDetails(
          customerId: custId,
          type: type,
          details: details,
          remarks: remarksController.text.trim(),
        );

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Saved as $type (local) id: $txnId")),
        );
      }

      /// NEW — Remove Draft After Successful Save
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftKey);

      /// CLEAR SCREEN
      if (mounted) {
        setState(() {
          selectedCustomer = null;
          selectedProduct = null;

          qtyController.clear();
          batchController.clear();
          remarksController.clear();

          selectedProducts.clear();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  InputDecoration _inputDecoration(String label) => InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF6F6F6),
        contentPadding:
            const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
        border: const OutlineInputBorder(
            // borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Color(0xFFEBEBEB))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFEBEBEB))),
      );

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
            title: const Text('Return', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.black,
          ),
          body: const Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.transactionId == null ? 'Return' : 'Edit Return'),
        centerTitle: true,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18.0),
          child: Column(
            children: [
              const SizedBox(height: 18),
              Autocomplete<String>(
                key: _customerFieldKey,
                initialValue: selectedCustomer != null
                    ? TextEditingValue(text: selectedCustomer!)
                    : const TextEditingValue(),
                optionsBuilder: (TextEditingValue textEditingValue) {
                  if (textEditingValue.text.isEmpty) {
                    return customers;
                  }
                  return customers.where((String option) {
                    return option
                        .toLowerCase()
                        .contains(textEditingValue.text.toLowerCase());
                  });
                },
                fieldViewBuilder:
                    (context, controller, focusNode, onEditingComplete) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onEditingComplete: onEditingComplete,
                    decoration: _inputDecoration("Select Customer..."),
                    onChanged: (val) {
                      setState(() {
                        selectedCustomer = val;
                      });
                    },
                  );
                },
                onSelected: (String selection) async {
                  setState(() {
                    selectedCustomer = selection;
                  });

                  final custId =
                      await AppDatabase.insertCustomerIfNotExists(selection);

                  final existingId =
                      await AppDatabase.findTransactionForCustomerOnDate(
                    custId,
                    "Return",
                    DateTime.now(),
                  );

                  if (existingId != null) {
                    await _loadExisting(existingId);

                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("Previous return loaded"),
                        backgroundColor: Colors.blue,
                      ),
                    );
                  } else {
                    setState(() {
                      selectedProducts.clear();
                    });
                  }

                  await _autoSaveDraft();

                  _productFocusNode?.requestFocus();
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
                  return products.where((p) => p['name']
                      .toString()
                      .toLowerCase()
                      .contains(textEditingValue.text.toLowerCase()));
                },
                displayStringForOption: (p) => p['name'] as String,
                fieldViewBuilder:
                    (context, controller, focusNode, onEditingComplete) {
                  _productFocusNode = focusNode;
                  _productFieldController = controller;

                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
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
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => _remarksFocusNode.requestFocus(),
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
                  style:
                      ElevatedButton.styleFrom(backgroundColor: Colors.black),
                  child: _isCheckingBatch
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2),
                        )
                      : const Text("Add Product",
                          style: TextStyle(color: Colors.white)),
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("Selected Products",
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    Expanded(
                      child: selectedProducts.isEmpty
                          ? const Center(
                              child: Text("No products added",
                                  style: TextStyle(color: Colors.grey)))
                          : ListView.builder(
                              itemCount: selectedProducts.length,
                              itemBuilder: (context, i) {
                                final p = selectedProducts[i];
                                return Card(
                                  margin:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12)),
                                  child: ListTile(
                                    title: Text(p['name'],
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w600)),
                                    subtitle: Text(
                                        "QTY: ${p['qty']}    Batch: ${p['batch']}"),
                                    trailing: IconButton(
                                      icon: const Icon(Icons.delete,
                                          color: Colors.red),
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
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 8.0, top: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: cancel,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[400],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text("Cancel"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => saveAs("Return"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: _isSaving
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2),
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
    );
  }
}
