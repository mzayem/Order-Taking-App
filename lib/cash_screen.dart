import 'package:flutter/material.dart';
import '../db/database.dart';
// import 'dart:convert';
// import 'package:http/http.dart' as http;

class CashScreen extends StatefulWidget {
  const CashScreen({super.key});

  @override
  State<CashScreen> createState() => _CashScreenState();
}

class _CashScreenState extends State<CashScreen> {
  final List<String> customers = [
    "Ali",
    "Ahmed",
    "Sara",
    "Hassan"
  ]; // ✅ dummy customers

  // 🔹 Later replace with API call:
  /*
  List<String> customers = [];
  Future<void> fetchCustomersFromApi() async {
    try {
      final response = await http.get(Uri.parse('https://yourapi/customers'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          customers = List<String>.from(data.map((e) => e['name']));
        });
      }
    } catch (e) {
      print("Error fetching customers: $e");
    }
  }

  @override
  void initState() {
    super.initState();
    fetchCustomersFromApi();
  }
  */

  String? selectedCustomer;
  final TextEditingController amountController = TextEditingController();
  final TextEditingController remarksController = TextEditingController();

  bool isSaving = false;

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

  void cancel() {
    setState(() {
      selectedCustomer = null;
      amountController.clear();
      remarksController.clear();
    });
  }

  Future<void> saveCash() async {
    if (selectedCustomer == null) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Please select customer")));
      return;
    }
    if (amountController.text.trim().isEmpty ||
        double.tryParse(amountController.text.trim()) == null ||
        double.parse(amountController.text.trim()) <= 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text("Enter valid amount")));
      return;
    }

    setState(() => isSaving = true);

    try {
      final custId =
          await AppDatabase.insertCustomerIfNotExists(selectedCustomer!);

      await AppDatabase.createTransactionWithDetails(
        customerId: custId,
        type: "Cash",
        details: const [],
        cashAmount: double.parse(amountController.text.trim()),
        remarks: remarksController.text.trim(),
      );

      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Cash payment saved locally!")));

      cancel();
    } catch (e) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Error: $e")));
    } finally {
      setState(() => isSaving = false);
    }
  }

  @override
  void dispose() {
    amountController.dispose();
    remarksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Cash Payment"),
        centerTitle: true,
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18.0),
          child: Column(
            children: [
              const SizedBox(height: 58),
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
              TextField(
                controller: amountController,
                keyboardType: TextInputType.number,
                decoration: _inputDecoration("Enter Cash Amount"),
              ),
              const SizedBox(height: 12),
              // TextField(
              //   controller: remarksController,
              //   decoration: _inputDecoration("Remarks (optional)"),
              //   maxLines: 2,
              // ),
              const SizedBox(height: 18),
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
                        onPressed: isSaving ? null : saveCash,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: isSaving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
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
