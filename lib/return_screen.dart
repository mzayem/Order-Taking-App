// lib/screens/return_screen.dart
import 'package:flutter/material.dart';
import '../db/database.dart';

class ReturnScreen extends StatefulWidget {
  final int? transactionId;
  const ReturnScreen({super.key, this.transactionId});

  @override
  State<ReturnScreen> createState() => _ReturnScreenState();
}

class _ReturnScreenState extends State<ReturnScreen> {
  final List<String> customers = ["Ali", "Ahmed", "Sara", "Hassan"];
  final List<Map<String, dynamic>> products = [
    {"name": "Product A", "price": 100, "availableQty": 50},
    {"name": "Product B", "price": 200, "availableQty": 30},
    {"name": "Product C", "price": 150, "availableQty": 20},
  ];

  final Map<String, List<String>> productBatches = {
    "Product A": ["A-1001", "A-1002", "A-1003"],
    "Product B": ["B-2001", "B-2002"],
    "Product C": ["C-3001"]
  };

  String? selectedCustomer;
  Map<String, dynamic>? selectedProduct;
  final TextEditingController qtyController = TextEditingController();
  final TextEditingController batchController = TextEditingController();
  final TextEditingController remarksController = TextEditingController();

  List<Map<String, dynamic>> selectedProducts = [];

  bool _isLoading = false;
  bool _isSaving = false;

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
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final header = rows.first;
      final db = await AppDatabase.init();
      final custId = header['CustomerID'] as int?;
      if (custId != null) {
        final custRows = await db.query('Customer',
            where: 'CustomerID = ?', whereArgs: [custId], limit: 1);
        if (custRows.isNotEmpty) {
          selectedCustomer = custRows.first['Name'] as String?;
        }
      }

      remarksController.text = (header['Remarks'] ?? '') as String;

      final List<Map<String, dynamic>> loaded = [];
      for (final r in rows) {
        if (r['TransactionDetailID'] == null) continue;
        loaded.add({
          'productId': r['ProductID'] as int?,
          'name': r['ProductName'] as String? ?? '',
          'qty': (r['Qty'] as num?)?.toInt() ?? 0,
          'price': (r['UnitPrice'] as num?)?.toInt() ?? 0,
          'batch': r['BatchNo'] as String? ?? '',
        });
      }

      setState(() {
        selectedProducts = loaded;
      });
    } catch (e) {
      debugPrint('Error loading return transaction: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void addProduct() {
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

    final productName = selectedProduct!['name'] as String;
    final allowedBatches = productBatches[productName] ?? [];

    if (!allowedBatches.contains(batchText)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("This batch is not from our company")));
      return;
    }

    final qty = int.parse(qtyText);
    final available = (selectedProduct!['availableQty'] as int);

    if (qty > available) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Quantity exceeds available stock")));
      return;
    }

    setState(() {
      selectedProducts.add({
        "name": productName,
        "qty": qty,
        "batch": batchText,
        "price": selectedProduct!['price'],
        // productId will be resolved on save (insertProductIfNotExists)
      });

      selectedProduct!['availableQty'] = available - qty;
      selectedProduct = null;
      qtyController.clear();
      batchController.clear();
    });
  }

  void cancel() {
    setState(() {
      selectedCustomer = null;
      selectedProduct = null;
      qtyController.clear();
      batchController.clear();
      remarksController.clear();
      selectedProducts.clear();
    });
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
      for (final p in selectedProducts) {
        final prodId = await AppDatabase.insertProductIfNotExists(p['name'],
            unitPrice: (p['price'] as num).toDouble(), availableQty: 0);
        details.add({
          'productId': prodId,
          'batchNo': p['batch'],
          'qty': p['qty'],
          'unitPrice': (p['price'] as num).toDouble(),
        });
      }

      // If opened for editing a specific transaction, update that
      if (widget.transactionId != null) {
        await AppDatabase.updateTransactionAndReplaceDetails(
          transactionId: widget.transactionId!,
          customerId: custId,
          type: type,
          details: details,
          remarks: remarksController.text.trim(),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Return updated (local)")));
      } else {
        // fallback: same-customer same-day -> update
        final existingId = await AppDatabase.findTransactionForCustomerOnDate(
            custId, type, DateTime.now());

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
              const SnackBar(content: Text("Return updated (local)")));
        } else {
          final txnId = await AppDatabase.createTransactionWithDetails(
            customerId: custId,
            type: type,
            details: details,
            remarks: remarksController.text.trim(),
          );
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text("Saved as $type (local) id: $txnId")));
        }
      }

      setState(() {
        selectedCustomer = null;
        selectedProduct = null;
        qtyController.clear();
        batchController.clear();
        remarksController.clear();
        selectedProducts.clear();
      });
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
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFEBEBEB))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFEBEBEB))),
      );

  @override
  void dispose() {
    qtyController.dispose();
    batchController.dispose();
    remarksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
          appBar: AppBar(
            title: Text('Return', style: TextStyle(color: Colors.white)),
            backgroundColor: Colors.black,
          ),
          body: Center(child: CircularProgressIndicator()));
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
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    onEditingComplete: onEditingComplete,
                    decoration: _inputDecoration("Select Customer"),
                    onChanged: (val) {
                      setState(() {
                        selectedCustomer = val;
                      });
                    },
                  );
                },
                onSelected: (String selection) {
                  setState(() {
                    selectedCustomer = selection;
                  });
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
                      .toLowerCase()
                      .contains(textEditingValue.text.toLowerCase()));
                },
                displayStringForOption: (p) =>
                    "${p['name']}  (Available: ${p['availableQty']})",
                fieldViewBuilder:
                    (context, controller, focusNode, onEditingComplete) {
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    onEditingComplete: onEditingComplete,
                    decoration: _inputDecoration("Select Product"),
                    onChanged: (val) {
                      final found = products.firstWhere(
                          (p) => p['name'].toLowerCase() == val.toLowerCase(),
                          orElse: () => {});
                      setState(() {
                        selectedProduct = found.isNotEmpty ? found : null;
                      });
                    },
                  );
                },
                onSelected: (p) {
                  setState(() {
                    selectedProduct = p;
                  });
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: qtyController,
                      keyboardType: TextInputType.number,
                      decoration: _inputDecoration("QTY"),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: batchController,
                      decoration: _inputDecoration("Batch No"),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: remarksController,
                decoration: _inputDecoration("Remarks"),
                maxLines: 2,
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: addProduct,
                  style:
                      ElevatedButton.styleFrom(backgroundColor: Colors.black),
                  child: const Text("Add Product",
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
                        onPressed: () => saveAs("Draft"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[300],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text("Draft"),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => saveAs("Return"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
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
