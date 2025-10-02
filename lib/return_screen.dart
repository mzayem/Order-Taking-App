// lib/return_screen.dart
import 'package:flutter/material.dart';
import 'home_screen.dart'; // uses the global savedOrders list

class ReturnScreen extends StatefulWidget {
  const ReturnScreen({super.key});

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

  /// Dummy batch data (simulate API): productName -> list of valid batch ids
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

  // Add product to selectedProducts after validation
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

    // Check batch validity (dummy API replacement)
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
      });

      // Optionally adjust available qty locally for UX
      selectedProduct!['availableQty'] = available - qty;

      // reset product-specific fields but keep customer selected
      selectedProduct = null;
      qtyController.clear();
      batchController.clear();
    });
  }

  // Cancel/clear form
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

  // Save as Return or Draft
  void saveAs(String type) {
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

    final total = selectedProducts.fold<int>(
        0, (s, p) => s + ((p['qty'] as int) * (p['price'] as int)));

    savedOrders.add({
      "customer": selectedCustomer!,
      "products": List<Map<String, dynamic>>.from(selectedProducts),
      "total": total,
      "date": DateTime.now(),
      "type": type, // "Return" or "Draft"
      "town": "", // placeholder
      "remark": remarksController.text.trim(),
    });

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text("Saved as $type")));

    // clear form for next input (but keep customer optional — here we clear it)
    setState(() {
      selectedCustomer = null;
      selectedProduct = null;
      qtyController.clear();
      batchController.clear();
      remarksController.clear();
      selectedProducts.clear();
    });
  }

  @override
  void dispose() {
    qtyController.dispose();
    batchController.dispose();
    remarksController.dispose();
    super.dispose();
  }

  // small input decoration for consistent UI
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Return"),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18.0),
          child: Column(
            children: [
              const SizedBox(height: 18),

              // Customer dropdown
              DropdownButtonFormField<String>(
                value: selectedCustomer,
                decoration: _inputDecoration("Select Customers"),
                items: customers
                    .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                    .toList(),
                onChanged: (val) => setState(() => selectedCustomer = val),
              ),

              const SizedBox(height: 16),

              // Product dropdown
              DropdownButtonFormField<Map<String, dynamic>>(
                value: selectedProduct,
                decoration: _inputDecoration("Select Product"),
                items: products
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(
                              "${p['name']}  (Available: ${p['availableQty']})"),
                        ))
                    .toList(),
                onChanged: (val) => setState(() => selectedProduct = val),
              ),

              const SizedBox(height: 16),

              // QTY and Batch No
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

              // Remarks
              TextField(
                controller: remarksController,
                decoration: _inputDecoration("Remarks"),
                maxLines: 2,
              ),

              const SizedBox(height: 18),

              // Add product button
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

              // Selected products list
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

              // Buttons row
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
                        child: const Text("Save"),
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
