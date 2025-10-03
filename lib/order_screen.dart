import 'package:flutter/material.dart';
import 'home_screen.dart'; // savedOrders list is here

class OrderScreen extends StatefulWidget {
  const OrderScreen({super.key});

  @override
  State<OrderScreen> createState() => _OrderScreenState();
}

class _OrderScreenState extends State<OrderScreen> {
  final List<String> customers = ["Ali", "Ahmed", "Sara"];
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
            const SnackBar(content: Text("Enter a valid quantity")));
        return;
      }
      final available = selectedProduct!['availableQty'] as int;
      if (qty > available) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Quantity exceeds available stock")));
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
        // optionally reduce availableQty locally for user's UX:
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

  // Save as given type: "Order" or "Draft"
  void _saveOrderAs(String type) {
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

    savedOrders.add({
      "customer": selectedCustomer!,
      "products": List<Map<String, dynamic>>.from(selectedProducts),
      "total": totalAmount,
      "date": DateTime.now(),
      "type": type,
      "town": "Town", // replace with real town if available
    });

    // clear local form
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
      appBar: AppBar(
        title: const Text("Order"),
        backgroundColor: Colors.black,
        elevation: 0,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Customer
            DropdownButtonFormField<String>(
              value: selectedCustomer,
              decoration: const InputDecoration(labelText: "Select Customer"),
              items: customers
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (val) => setState(() => selectedCustomer = val),
            ),
            const SizedBox(height: 16),

            // Product
            DropdownButtonFormField<Map<String, dynamic>>(
              value: selectedProduct,
              decoration: const InputDecoration(labelText: "Select Product"),
              items: products
                  .map((p) => DropdownMenuItem(
                      value: p,
                      child: Text(
                          "${p['name']} - Rs.${p['price']} (${p['availableQty']} pcs)")))
                  .toList(),
              onChanged: (val) => setState(() => selectedProduct = val),
            ),
            const SizedBox(height: 16),

            // qty & available
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: qtyController,
                    decoration: const InputDecoration(labelText: "QTY"),
                    keyboardType: TextInputType.number,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    readOnly: true,
                    decoration: InputDecoration(
                      labelText: "Available QTY",
                      hintText: selectedProduct != null
                          ? selectedProduct!['availableQty'].toString()
                          : "-",
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

            // selected products - scrollable
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

            const SizedBox(height: 16),
            Text("Total Amount: Rs.$totalAmount",
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 18),

            // action buttons: Cancel | Draft | Save
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
