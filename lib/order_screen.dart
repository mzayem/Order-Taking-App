// lib/screens/order_screen.dart
import 'package:flutter/material.dart';
import '../db/database.dart';

class OrderScreen extends StatefulWidget {
  final int? transactionId;
  const OrderScreen({super.key, this.transactionId});

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  final List<String> customers = ["Ali", "Ahmed", "Sara", "Salman", "Ayesha"];
  final List<Map<String, dynamic>> products = [
    {"name": "Product A", "price": 100, "availableQty": 50},
    {"name": "Product B", "price": 200, "availableQty": 30},
    {"name": "Product C", "price": 150, "availableQty": 20},
  ];

  String? selectedCustomer;
  Map<String, dynamic>? selectedProduct;
  final TextEditingController qtyController = TextEditingController();
  List<Map<String, dynamic>> selectedProducts = [];

  bool _isLoading = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    if (widget.transactionId != null) {
      _loadExistingTransaction(widget.transactionId!);
    }
  }

  Future<void> _loadExistingTransaction(int transactionId) async {
    setState(() => _isLoading = true);
    final rows = await AppDatabase.getTransactionWithDetails(transactionId);
    if (rows.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }

    final db = await AppDatabase.init();
    final header = rows.first;
    final custId = header['CustomerID'] as int?;
    String custName = '';
    if (custId != null) {
      final custRows = await db.query('Customer',
          where: 'CustomerID = ?', whereArgs: [custId], limit: 1);
      if (custRows.isNotEmpty) custName = custRows.first['Name'] as String;
    }

    final List<Map<String, dynamic>> loadedProducts = [];
    for (final r in rows) {
      if (r['TransactionDetailID'] == null) continue;
      final tdId = r['TransactionDetailID'] as int?;
      final productId = r['ProductID'] as int?;
      final productName = r['ProductName'] as String? ?? '';
      final qty = (r['Qty'] as num?)?.toInt() ?? 0;
      final unitPrice = (r['UnitPrice'] as num?)?.toDouble() ?? 0.0;
      final total =
          (r['TotalPrice'] as num?)?.toInt() ?? (qty * unitPrice).toInt();

      loadedProducts.add({
        'transactionDetailId': tdId,
        'productId': productId,
        'name': productName,
        'qty': qty,
        'price': unitPrice.toInt(),
        'total': total,
      });
    }

    setState(() {
      selectedCustomer = custName.isNotEmpty ? custName : null;
      selectedProducts = loadedProducts;
      _isLoading = false;
    });
  }

  void addProduct() {
    if (selectedProduct != null && qtyController.text.isNotEmpty) {
      final qty = int.tryParse(qtyController.text) ?? 0;
      if (qty <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Enter a valid quantity")),
        );
        return;
      }
      final available = selectedProduct!['availableQty'] as int;
      if (qty > available) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Quantity exceeds available stock")),
        );
        return;
      }

      final price = selectedProduct!['price'] as int;
      final total = qty * price;

      setState(() {
        selectedProducts.add({
          "name": selectedProduct!['name'],
          "qty": qty,
          "price": price,
          "total": total,
        });
        selectedProduct!['availableQty'] = available - qty;
        qtyController.clear();
        selectedProduct = null;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Select product and enter quantity")),
      );
    }
  }

  int get totalAmount =>
      selectedProducts.fold(0, (sum, item) => sum + (item['total'] as int));

  Future<void> _saveOrderAs(String type) async {
    if (selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select a customer")),
      );
      return;
    }
    if (selectedProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Add at least one product")),
      );
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
          'qty': p['qty'],
          'unitPrice': (p['price'] as num).toDouble(),
        });
      }

      // check existing transaction for same customer, same type, same day
      final existingId = await AppDatabase.findTransactionForCustomerOnDate(
          custId, type, DateTime.now());

      if (existingId != null) {
        // update existing
        await AppDatabase.updateTransactionAndReplaceDetails(
          transactionId: existingId,
          customerId: custId,
          type: type,
          details: details,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Order updated (local)")));
      } else {
        final txnId = await AppDatabase.createTransactionWithDetails(
          customerId: custId,
          type: type,
          details: details,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Order saved (local) id: $txnId")));
      }

      setState(() {
        selectedCustomer = null;
        selectedProduct = null;
        selectedProducts = [];
        qtyController.clear();
      });
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _cancelOrder() {
    setState(() {
      selectedCustomer = null;
      selectedProduct = null;
      selectedProducts.clear();
      qtyController.clear();
    });
  }

  @override
  void dispose() {
    qtyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text("Order", style: TextStyle(color: Colors.white)),
          backgroundColor: Colors.black,
        ),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        centerTitle: true,
        title: Text(widget.transactionId == null ? "Order" : "Edit Order"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Select Customer",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Autocomplete<String>(
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text.isEmpty) {
                  return const Iterable<String>.empty();
                }
                return customers.where((customer) => customer
                    .toLowerCase()
                    .contains(textEditingValue.text.toLowerCase()));
              },
              onSelected: (selection) {
                setState(() => selectedCustomer = selection);
              },
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
                controller.text = selectedCustomer ?? '';
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: "Search Customer...",
                  ),
                );
              },
            ),
            const SizedBox(height: 20),
            const Text("Select Product",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Autocomplete<Map<String, dynamic>>(
              displayStringForOption: (option) => option['name'],
              optionsBuilder: (TextEditingValue textEditingValue) {
                if (textEditingValue.text.isEmpty) {
                  return const Iterable<Map<String, dynamic>>.empty();
                }
                return products.where((p) => p['name']
                    .toLowerCase()
                    .contains(textEditingValue.text.toLowerCase()));
              },
              onSelected: (selection) {
                setState(() => selectedProduct = selection);
              },
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
                controller.text = selectedProduct?['name'] ?? '';
                return TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: "Search Product...",
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: qtyController,
                    decoration: const InputDecoration(
                      labelText: "QTY",
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    readOnly: true,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: selectedProduct != null
                          ? selectedProduct!['availableQty'].toString()
                          : "Available QTY",
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: addProduct,
                style: ElevatedButton.styleFrom(backgroundColor: Colors.black),
                child: const Text("Add Product",
                    style: TextStyle(color: Colors.white)),
              ),
            ),
            const SizedBox(height: 20),
            if (selectedProducts.isNotEmpty) ...[
              const Text("Selected Products",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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
                                const TextStyle(fontWeight: FontWeight.bold)),
                        subtitle:
                            Text("Qty: ${p['qty']}   Price: Rs.${p['price']}"),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () {
                            setState(() => selectedProducts.removeAt(i));
                          },
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 16),
            Text("Total Amount: Rs.$totalAmount",
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _cancelOrder,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[400],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text("Cancel", style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _saveOrderAs("Draft"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue[300],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 3,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text("Draft", style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _saveOrderAs("Order"),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      elevation: 3,
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
                        : const Text("Save", style: TextStyle(fontSize: 16)),
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
