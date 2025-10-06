import 'package:flutter/material.dart';
import 'home_screen.dart'; // savedOrders list is here

class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key});

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

  void _saveOrderAs(String type) {
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

    savedOrders.add({
      "customer": selectedCustomer!,
      "products": List<Map<String, dynamic>>.from(selectedProducts),
      "total": totalAmount,
      "date": DateTime.now(),
      "type": type,
      "town": "Town",
    });

    setState(() {
      selectedCustomer = null;
      selectedProduct = null;
      selectedProducts = [];
      qtyController.clear();
    });

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text("Order saved as $type")));
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        centerTitle: true,
        title: const Text("Order"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ Customer Autocomplete
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

            // ✅ Product Autocomplete
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

            // qty & available
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
                      // labelText: "Available QTY",
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

            // Add button
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

            // selected products
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

            // buttons row
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
                    child: const Text("Save", style: TextStyle(fontSize: 16)),
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
