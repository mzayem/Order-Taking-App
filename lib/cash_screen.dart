// lib/cash_screen.dart
import 'package:flutter/material.dart';
import 'home_screen.dart'; // uses the global savedOrders list from home_screen.dart

class CashScreen extends StatefulWidget {
  const CashScreen({super.key});

  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  final List<String> customers = ["Ali", "Ahmed", "Sara", "Hassan", "Ahsan"];
  String? selectedCustomer;
  final TextEditingController amountController = TextEditingController();

  void _clearForm() {
    setState(() {
      selectedCustomer = null;
      amountController.clear();
    });
  }

  int? _parseAmount() {
    final text = amountController.text.trim();
    if (text.isEmpty) return null;
    final value = int.tryParse(text);
    return value;
  }

  void _saveAs(String type) {
    final amount = _parseAmount();
    if (selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please select a customer")));
      return;
    }
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please enter a valid amount")));
      return;
    }

    savedOrders.add({
      "customer": selectedCustomer!,
      "products": <Map<String, dynamic>>[], // no products for cash entry
      "total": amount,
      "date": DateTime.now(),
      "type": type, // "Cash" or "Draft"
      "town": "", // placeholder — you can add a town input later
    });

    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text("Saved as $type")));

    // clear form for next input
    _clearForm();
  }

  @override
  Widget build(BuildContext context) {
    // input decoration reused
    InputDecoration inputDecoration(String label) => InputDecoration(
          labelText: label,
          filled: true,
          fillColor: const Color(0xFFF6F6F6),
          contentPadding:
              const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFEBEBEB)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFEBEBEB)),
          ),
        );

    return Scaffold(
      // Note: in your app the main AppBar may be provided by the parent Home scaffold.
      // Keeping a local AppBar here will show a header when this screen is pushed standalone.
      appBar: AppBar(
        title: const Text("Cash"),
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
              const SizedBox(height: 20),

              // Customer dropdown
              DropdownButtonFormField<String>(
                value: selectedCustomer,
                decoration: inputDecoration("Select Customers"),
                items: customers
                    .map((c) => DropdownMenuItem<String>(
                          value: c,
                          child: Text(c),
                        ))
                    .toList(),
                onChanged: (val) => setState(() => selectedCustomer = val),
              ),

              const SizedBox(height: 20),

              // Amount field
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: inputDecoration("Amount"),
              ),

              const SizedBox(height: 28),

              // Center helper text
              const Center(
                child: Text(
                  "Enter Amount you received",
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54),
                ),
              ),

              // spacer to push bottom buttons down but keep scrollable room
              const Spacer(),

              // Action buttons row (Cancel, Draft, Save)
              Padding(
                padding: const EdgeInsets.only(bottom: 14.0),
                child: Row(
                  children: [
                    // Cancel
                    Expanded(
                      child: ElevatedButton(
                        onPressed: _clearForm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[400],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text("Cancel",
                            style: TextStyle(fontSize: 16)),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Draft
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _saveAs("Draft"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue[300],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child:
                            const Text("Draft", style: TextStyle(fontSize: 16)),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Save
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _saveAs("Cash"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          elevation: 3,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child:
                            const Text("Save", style: TextStyle(fontSize: 16)),
                      ),
                    ),
                  ],
                ),
              ),

              // safe bottom padding for device bottom nav
              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        ),
      ),
    );
  }
}
