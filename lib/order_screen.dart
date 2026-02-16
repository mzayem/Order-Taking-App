// lib/screens/order_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../db/database.dart';

class OrderScreen extends StatefulWidget {
  final int? transactionId;
  const OrderScreen({super.key, this.transactionId});

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  List<String> customers = [];
  List<Map<String, dynamic>> products = [];

  String? selectedCustomer;
  Map<String, dynamic>? selectedProduct;
  final TextEditingController qtyController = TextEditingController();
  List<Map<String, dynamic>> selectedProducts = [];

  bool _isLoading = false;
  bool _isSaving = false;
  bool _isLoadingData = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoadingData = true);
    await _fetchCustomersAndProducts();
    if (widget.transactionId != null) {
      await _loadExistingTransaction(widget.transactionId!);
    }
    setState(() => _isLoadingData = false);
  }

  Future<void> _fetchCustomersAndProducts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final baseUrl = prefs.getString('baseUrl') ?? '';
      if (baseUrl.isEmpty) {
        await _loadCustomersFromDB();
      } else {
        // Fetch customers
        try {
          final resp = await http
              .get(Uri.parse('$baseUrl/customers_604281180'))
              .timeout(const Duration(seconds: 10));
          if (resp.statusCode == 200) {
            final data = jsonDecode(resp.body);
            if (data['status'] == 'success' && data['result'] != null) {
              final list = data['result'] as List;
              setState(() {
                customers = list.map((c) => c['Name'] as String).toList();
              });
              for (var c in list) {
                await AppDatabase.upsertCustomer({
                  'CustomerID': c['CustomerId'],
                  'Name': c['Name'],
                  'Town': c['Town'] ?? '',
                });
              }
            }
          }
        } catch (_) {
          await _loadCustomersFromDB();
        }
      }

      if (baseUrl.isEmpty) {
        await _loadProductsFromDB();
      } else {
        // Fetch products
        try {
          final resp = await http
              .get(Uri.parse('$baseUrl/product_604281180'))
              .timeout(const Duration(seconds: 10));
          if (resp.statusCode == 200) {
            final data = jsonDecode(resp.body);
            if (data['status'] == 'success' && data['result'] != null) {
              final list = data['result'] as List;
              setState(() {
                products = list
                    .map((p) => {
                          'name': p['Name'] as String,
                          'price': (p['UnitPrice'] as num).toInt(),
                          'availableQty': p['AvailableQty'] as int,
                          'code': p['Code'] ?? '',
                        })
                    .toList();
              });
              for (var p in list) {
                await AppDatabase.upsertProduct({
                  'ProductID': p['ProductID'],
                  'Name': p['Name'],
                  'Code': p['Code'] ?? '',
                  'UnitPrice': (p['UnitPrice'] as num).toDouble(),
                  'AvailableQty': p['AvailableQty'] as int,
                });
              }
            }
          }
        } catch (_) {
          await _loadProductsFromDB();
        }
      }
    } catch (e) {
      debugPrint('Error in _fetchCustomersAndProducts: $e');
      await _loadCustomersFromDB();
      await _loadProductsFromDB();
    }
  }

  Future<void> _loadCustomersFromDB() async {
    final rows = await (await AppDatabase.init()).query('Customer');
    setState(() {
      customers = rows.map((r) => r['Name'] as String).toList();
    });
  }

  Future<void> _loadProductsFromDB() async {
    final rows = await (await AppDatabase.init()).query('Product');
    setState(() {
      products = rows
          .map((r) => {
                'name': r['Name'] as String,
                'price': (r['UnitPrice'] as num).toInt(),
                'availableQty': r['AvailableQty'] as int,
                'code': r['Code'] ?? '',
              })
          .toList();
    });
  }

  Future<void> _loadExistingTransaction(int transactionId) async {
    setState(() => _isLoading = true);
    final rows = await AppDatabase.getTransactionWithDetails(transactionId);
    if (rows.isNotEmpty) {
      final header = rows.first;
      final db = await AppDatabase.init();
      final custRows = await db.query('Customer',
          where: 'CustomerID = ?', whereArgs: [header['CustomerID']], limit: 1);
      if (custRows.isNotEmpty) {
        selectedCustomer = custRows.first['Name'] as String;
      }
      final loaded = <Map<String, dynamic>>[];
      for (var r in rows) {
        if (r['TransactionDetailID'] != null) {
          loaded.add({
            'transactionDetailId': r['TransactionDetailID'],
            'productId': r['ProductID'],
            'name': r['ProductName'],
            'qty': (r['Qty'] as num).toInt(),
            'price': (r['UnitPrice'] as num).toInt(),
            'total': (r['TotalPrice'] as num).toInt(),
          });
        }
      }
      selectedProducts = loaded;
    }
    setState(() => _isLoading = false);
  }

  void addProduct() {
    if (selectedProduct != null && qtyController.text.isNotEmpty) {
      final qty = int.tryParse(qtyController.text) ?? 0;
      final available = selectedProduct!['availableQty'] as int;
      if (qty <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Enter a valid quantity")));
        return;
      }
      if (qty > available) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Quantity exceeds available stock")));
        return;
      }
      final price = selectedProduct!['price'] as int;
      setState(() {
        selectedProducts.add({
          "name": selectedProduct!['name'],
          "qty": qty,
          "price": price,
          "total": qty * price,
        });
        selectedProduct!['availableQty'] = available - qty;
        qtyController.clear();
        selectedProduct = null;
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Select product and enter quantity")));
    }
  }

  int get totalAmount =>
      selectedProducts.fold(0, (sum, item) => sum + (item['total'] as int));

  Future<void> _saveOrderAs(String type) async {
    if (selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please select a customer")));
      return;
    }
    if (selectedProducts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Add at least one product")));
      return;
    }
    setState(() => _isSaving = true);
    try {
      final custId =
          await AppDatabase.insertCustomerIfNotExists(selectedCustomer!);
      final details = <Map<String, dynamic>>[];
      for (var p in selectedProducts) {
        final pid = await AppDatabase.insertProductIfNotExists(p['name'],
            unitPrice: (p['price'] as num).toDouble(), availableQty: 0);
        details.add({
          'productId': pid,
          'qty': p['qty'],
          'unitPrice': (p['price'] as num).toDouble(),
        });
      }
      final existingId = await AppDatabase.findTransactionForCustomerOnDate(
          custId, type, DateTime.now());
      if (existingId != null) {
        await AppDatabase.updateTransactionAndReplaceDetails(
          transactionId: existingId,
          customerId: custId,
          type: type,
          details: details,
        );
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Order updated (local)")));
      } else {
        final txnId = await AppDatabase.createTransactionWithDetails(
          customerId: custId,
          type: type,
          details: details,
        );
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Order saved (local) id: $txnId")));
      }
      setState(() {
        selectedCustomer = null;
        selectedProducts.clear();
        qtyController.clear();
      });
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() => _isSaving = false);
    }
  }

  void _cancelOrder() {
    setState(() {
      selectedCustomer = null;
      selectedProducts.clear();
      qtyController.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoadingData) {
      return Scaffold(
        appBar: AppBar(
          centerTitle: true,
          title: Text(widget.transactionId == null ? "Order" : "Edit Order"),
          backgroundColor: Colors.black,
        ),
        body: const Center(child: CircularProgressIndicator()),
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
