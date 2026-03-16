// lib/screens/order_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:sqflite/sqflite.dart';
import 'dart:convert';
import '../db/database.dart';

class OrderScreen extends StatefulWidget {
  final int? transactionId;
  const OrderScreen({super.key, this.transactionId});

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  List<Map<String, dynamic>> customers = [];
  List<Map<String, dynamic>> products = [];

  String? selectedCustomer;
  Map<String, dynamic>? selectedCustomerObj;
  Map<String, dynamic>? selectedProduct;

  final TextEditingController qtyController = TextEditingController();
  List<Map<String, dynamic>> selectedProducts = [];

  bool _isLoading = false;
  bool _isSaving = false;
  bool _isLoadingData = true;

  double customerBalance = 0.0;
  bool isBalanceLoading = false;
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

  /// LOADING DIALOG

  void _showLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const SizedBox(width: 20),
              Expanded(child: Text(message)),
            ],
          ),
        );
      },
    );
  }

  void _hideLoadingDialog() {
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
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

      print("BALANCE API STATUS: ${response.statusCode}");
      print("BALANCE API BODY: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data['status'] == 'success') {
          setState(() {
            customerBalance = (data['balance'] ?? 0).toDouble();
          });
        }
      }
    } catch (e) {
      print("Balance fetch error: $e");
    } finally {
      setState(() {
        isBalanceLoading = false;
      });
    }
  }

  Future<void> _fetchCustomersAndProducts() async {
    final prefs = await SharedPreferences.getInstance();

    final baseUrl = prefs.getString('baseUrl') ?? '';
    final userId = prefs.getString('userId') ?? '';
    final townIds =
        prefs.getStringList('townIds')?.map(int.parse).toList() ?? [];

    // ------------------- CUSTOMERS -------------------
    bool customersLoaded = false;
    if (baseUrl.isNotEmpty && userId.isNotEmpty && townIds.isNotEmpty) {
      try {
        _showLoadingDialog("Fetching customers...");
        final response = await http
            .post(
              Uri.parse('$baseUrl/api/Customer/customerFetch'),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode({"userId": userId, "townIds": townIds}),
            )
            .timeout(const Duration(seconds: 15));

        if (Navigator.canPop(context)) Navigator.pop(context);

        debugPrint("Customer API status: ${response.statusCode}");
        debugPrint("Customer API body: ${response.body}");

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>?;

          if (data != null && data['status'] == 'success') {
            final List customersList = data['customers'] as List? ?? [];

            for (var c in customersList) {
              await AppDatabase.upsertCustomer({
                'CustomerID': c['customerId'] ?? 0,
                'Name': c['customerName']?.toString() ?? '',
                'Town': c['townID']?.toString() ?? '',
                'IsNarcotics':
                    (c['isNarcoticsAllowed'] as bool? ?? true) ? 1 : 0,
              });
            }

            customersLoaded = true;
          }
        }
      } catch (e) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        debugPrint("Customer fetch error: $e");
      }
    } else {
      debugPrint(
          "Skipping API customer fetch: missing baseUrl, userId, or townIds");
    }

    // Always load customers from local DB
    await _loadCustomersFromDB();
    if (!customersLoaded) {
      debugPrint("Customers loaded from local DB: ${customers.length}");
    }

    // ------------------- PRODUCTS -------------------
    bool productsLoaded = false;
    if (baseUrl.isNotEmpty && userId.isNotEmpty) {
      try {
        _showLoadingDialog("Fetching products...");
        final response = await http
            .post(
              Uri.parse('$baseUrl/api/Products/getProduct'),
              headers: {"Content-Type": "application/json"},
              body: jsonEncode({"userId": userId}),
            )
            .timeout(const Duration(seconds: 15));

        if (Navigator.canPop(context)) Navigator.pop(context);

        debugPrint("Product API status: ${response.statusCode}");
        debugPrint("Product API body: ${response.body}");

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body) as Map<String, dynamic>?;

          if (data != null && data['status'] == 'success') {
            final List productList = data['products'] as List? ?? [];

            for (var p in productList) {
              await AppDatabase.upsertProduct({
                'ProductID': p['productId'] ?? 0,
                'Name': p['productName']?.toString() ?? '',
                'Code': (p['productId'] ?? 0).toString(),
                'ProductType': p['productType']?.toString() ?? 'Medicine',
                'UnitPrice': ((p['latestPrice'] ?? 0) as num).toDouble(),
                'AvailableQty': p['totalQty'] ?? 0,
              });
            }

            productsLoaded = true;
          }
        }
      } catch (e) {
        if (Navigator.canPop(context)) Navigator.pop(context);
        debugPrint("Product fetch error: $e");
      }
    } else {
      debugPrint("Skipping API product fetch: missing baseUrl or userId");
    }

    // Always load products from local DB
    await _loadProductsFromDB();
    if (!productsLoaded) {
      debugPrint("Products loaded from local DB: ${products.length}");
    }
  }

  /// LOAD FROM LOCAL DB
  /// --------------------- FETCH PRODUCTS & CUSTOMERS ---------------------

  Future<void> _loadCustomersFromDB() async {
    final db = await AppDatabase.init();
    final rows = await db.query('Customer');

    customers = rows.map((r) {
      return {
        "id": r['CustomerID'] as int,
        "name": r['Name'] as String,
        "isNarcoticsAllowed": (r['IsNarcotics'] as int? ?? 0) == 1,
        "townId": r['Town']?.toString() ?? ''
      };
    }).toList();

    setState(() {});
  }

  Future<void> _loadProductsFromDB() async {
    final db = await AppDatabase.init();
    final rows = await db.query('Product');

    products = rows.map((r) {
      return {
        'id': r['ProductID'] as int,
        'name': r['Name'] as String,
        'price': ((r['UnitPrice'] as num?)?.toInt() ?? 0),
        'availableQty': (r['AvailableQty'] as int?) ?? 0,
        'type': r['ProductType']?.toString() ?? 'Medicine',
      };
    }).toList();

    setState(() {});
  }

  /// --------------------- ADD PRODUCT ---------------------

  void addProduct() {
    if (selectedCustomerObj == null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Select customer first")));
      return;
    }

    if (selectedProduct != null && qtyController.text.isNotEmpty) {
      final qty = int.tryParse(qtyController.text) ?? 0;
      final available = selectedProduct!['availableQty'] as int? ?? 0;

      if (qty <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Enter valid quantity")));
        return;
      }

      if (qty > available) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Quantity exceeds stock")));
        return;
      }

      // Narcotics warning
      if ((selectedProduct!['type']?.toString() ?? '') == "Narcotics" &&
          (selectedCustomerObj!['isNarcoticsAllowed'] as bool? ?? true) ==
              false) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("⚠ Narcotics not allowed to this customer"),
            backgroundColor: Colors.orange,
          ),
        );
      }

      final price = selectedProduct!['price'] as int? ?? 0;

      setState(() {
        selectedProducts.add({
          "name": selectedProduct!['name'] as String? ?? '',
          "qty": qty,
          "price": price,
          "total": qty * price,
        });

        selectedProduct!['availableQty'] = available - qty;

        qtyController.clear();
        selectedProduct = null;
      });
    }
  }

  int get totalAmount =>
      selectedProducts.fold(0, (sum, item) => sum + (item['total'] as int));

  /// LOAD EXISTING ORDER

  Future<void> _loadExistingTransaction(int transactionId) async {
    setState(() => _isLoading = true);

    final rows = await AppDatabase.getTransactionWithDetails(transactionId);

    if (rows.isNotEmpty) {
      final header = rows.first;

      selectedCustomer = header['CustomerName'];

      selectedProducts = rows.map((r) {
        return {
          "name": r['ProductName'],
          "qty": (r['Qty'] as num).toInt(),
          "price": (r['UnitPrice'] as num).toInt(),
          "total": (r['TotalPrice'] as num).toInt(),
        };
      }).toList();
    }

    setState(() => _isLoading = false);
  }

  /// --------------------- SAVE ORDER ---------------------

  void _saveOrderAs(String type) async {
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

    // Ensure customer exists
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

    final txnId = await AppDatabase.createTransactionWithDetails(
      customerId: custId,
      type: type,
      details: details,
    );

    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Order saved (local) id: $txnId")));

    setState(() {
      selectedCustomer = null;
      selectedProduct = null;
      selectedProducts = [];
      qtyController.clear();
    });
  }

  void _cancelOrder() {
    setState(() {
      selectedCustomer = null;
      selectedProducts.clear();
      qtyController.clear();
    });
  }

  /// UI (UNCHANGED)

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        centerTitle: true,
        title: Text(widget.transactionId == null ? "Order" : "Edit Order"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
      ),

      /// YOUR UI BELOW IS EXACTLY SAME
      /// (I DID NOT CHANGE ANY UI STRUCTURE)

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Select Customer",
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            Autocomplete<Map<String, dynamic>>(
              displayStringForOption: (option) =>
                  option['name']?.toString() ?? '',
              optionsBuilder: (TextEditingValue textEditingValue) {
                return customers.where((customer) =>
                    (customer['name']?.toString() ?? '')
                        .toLowerCase()
                        .contains(textEditingValue.text.toLowerCase()));
              },
              onSelected: (selection) {
                setState(() {
                  selectedCustomer = selection['name']?.toString() ?? '';
                  selectedCustomerObj = selection;
                });

                _fetchCustomerBalance(selection['id']);
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Total Amount: Rs.$totalAmount",
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                isBalanceLoading
                    ? const Text("Loading balance...")
                    : Text(
                        "Remaining Balance: Rs.${customerBalance.toStringAsFixed(2)}",
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
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
                      backgroundColor: Colors.red[400],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text("Cancel"),
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
                    ),
                    child: const Text("Draft"),
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
          ],
        ),
      ),
    );
  }
}
