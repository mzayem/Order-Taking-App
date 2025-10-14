// lib/screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Screens
import 'order_screen.dart';
import 'cash_screen.dart';
import 'return_screen.dart';
import 'profile_screen.dart';

// Local database + Sync
import '../db/database.dart';
import '../sync/sync_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = const [
    OverviewScreen(),
    OrderScreen(),
    CashScreen(),
    ReturnScreen(),
    ProfileScreen(),
  ];

  void _onItemTapped(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _screens[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.black,
        selectedItemColor: Colors.teal,
        unselectedItemColor: Colors.grey,
        showUnselectedLabels: true,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: "Home"),
          BottomNavigationBarItem(
              icon: Icon(Icons.shopping_cart), label: "Order"),
          BottomNavigationBarItem(
              icon: Icon(Icons.attach_money), label: "Cash"),
          BottomNavigationBarItem(
              icon: Icon(Icons.assignment_return), label: "Return"),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: "Profile"),
        ],
      ),
    );
  }
}

/// -------------------- OVERVIEW TAB -------------------- ///
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  String selectedFilter = "All";
  bool _selectionMode = false;
  bool _isUploading = false;
  double _uploadProgress = 0.0;

  final Set<int> _selectedTxIds = {};
  List<Map<String, dynamic>> _transactions = [];

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions() async {
    try {
      final db = await AppDatabase.init();
      final rows = await AppDatabase.getAllTransactionsForOverview();
      final List<Map<String, dynamic>> items = [];

      for (final r in rows) {
        print("Loaded Transaction Row: $r"); // 👈 DEBUG PRINT

        // dummy customer data if API not fetched yet
        final custRows = await db.query(
          'Customer',
          where: 'CustomerID = ?',
          whereArgs: [r['CustomerID']],
          limit: 1,
        );
        final custName = custRows.isNotEmpty
            ? custRows.first['Name'] as String
            : 'Customer #${r['CustomerID']}';

        // use correct total depending on type
        final type = r['Type'] as String? ?? 'Order';
        final totalAmount = (r['TotalAmount'] ?? 0) as num;
        final cashAmount = (r['CashAmount'] ?? 0) as num;

        items.add({
          'transactionId': r['TransactionID'] as int,
          'customer': custName,
          'date':
              DateTime.tryParse(r['Date'] as String? ?? '') ?? DateTime.now(),
          'total': type == 'Cash' ? cashAmount.toInt() : totalAmount.toInt(),
          'type': type,
          'syncStatus': r['SyncStatus'] as String? ?? 'Pending',
          'uploadedAt': r['SyncStatus'] == 'Synced'
              ? DateTime.tryParse(r['UpdatedAt'] as String? ?? '')
              : null,
          'town': '',
        });
      }

      if (!mounted) return;
      setState(() => _transactions = items);
    } catch (e) {
      debugPrint('Error loading transactions: $e');
    }
  }

  Future<void> _uploadSelected() async {
    if (_selectedTxIds.isEmpty) return;
    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString('baseUrl') ?? '';
    final sync = SyncService(baseUrl);

    if (baseUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('API URL not configured.')));
      setState(() => _isUploading = false);
      return;
    }

    final ids = _selectedTxIds.toList();
    final total = ids.length;
    int done = 0;

    for (final id in ids) {
      final rows = await AppDatabase.getTransactionWithDetails(id);
      if (rows.isEmpty) {
        done++;
        setState(() => _uploadProgress = done / total);
        continue;
      }

      final header = rows.first;
      final details = <Map<String, dynamic>>[];
      for (final r in rows) {
        if (r['TransactionDetailID'] != null) {
          details.add({
            'product_id': r['ProductID'],
            'batch_no': r['BatchNo'],
            'qty': r['Qty'],
            'unit_price': r['UnitPrice'],
            'total_price': r['TotalPrice'],
          });
        }
      }

      final payload = {
        'customer_id': header['CustomerID'],
        'type': header['Type'],
        'date': header['Date'],
        'total_amount': header['TotalAmount'],
        'cash_amount': header['CashAmount'],
        'remarks': header['Remarks'],
        'lines': details,
      };

      final res = await sync.uploadTransaction(id, payload);
      if (res['ok'] == true) {
        await AppDatabase.markTransactionSynced(id,
            remoteId: res['remoteId'] as int?);
      } else {
        await AppDatabase.markTransactionFailed(id);
      }

      done++;
      setState(() => _uploadProgress = done / total);
    }

    await _loadTransactions();
    setState(() {
      _isUploading = false;
      _selectionMode = false;
      _selectedTxIds.clear();
      _uploadProgress = 0.0;
    });

    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text("Upload finished.")));
  }

  void _toggleSelection(int txnId) {
    setState(() {
      if (_selectedTxIds.contains(txnId)) {
        _selectedTxIds.remove(txnId);
        if (_selectedTxIds.isEmpty) _selectionMode = false;
      } else {
        _selectedTxIds.add(txnId);
        _selectionMode = true;
      }
    });
  }

  String _shortDate(DateTime dt) {
    const months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec"
    ];
    return "${dt.day} ${months[dt.month - 1]}";
  }

  String _formatDayDate(DateTime dt) {
    const weekdays = [
      "Sunday",
      "Monday",
      "Tuesday",
      "Wednesday",
      "Thursday",
      "Friday",
      "Saturday"
    ];
    const months = [
      "Jan",
      "Feb",
      "Mar",
      "Apr",
      "May",
      "Jun",
      "Jul",
      "Aug",
      "Sep",
      "Oct",
      "Nov",
      "Dec"
    ];
    final dayName = weekdays[dt.weekday % 7];
    final monthName = months[dt.month - 1];
    return "$dayName, ${dt.day} $monthName";
  }

  Widget _buildOrderCard(Map<String, dynamic> order) {
    final int txnId = order['transactionId'] as int;
    final bool uploaded = order['syncStatus'] == 'Synced';
    final bool uploadFailed = order['syncStatus'] == 'Failed';
    final bool isSelected = _selectedTxIds.contains(txnId);
    final type = order['type'] ?? 'Order';
    final date = order['date'] as DateTime;
    final town = order['town'] ?? '';
    final total = order['total'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Material(
        elevation: isSelected ? 10 : 4,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? Colors.teal.withOpacity(0.08) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border:
                isSelected ? Border.all(color: Colors.teal, width: 2) : null,
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              if (_selectionMode)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(
                    isSelected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: isSelected ? Colors.teal : Colors.grey,
                    size: 26,
                  ),
                )
              else
                const SizedBox(width: 6),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color:
                                type == 'Draft' ? Colors.orange : Colors.black,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(type,
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
                        if (uploaded)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(6)),
                            child: const Text("Uploaded",
                                style: TextStyle(
                                    color: Colors.white, fontSize: 12)),
                          ),
                        if (uploadFailed)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            margin: const EdgeInsets.only(left: 8),
                            decoration: BoxDecoration(
                                color: Colors.red.shade100,
                                borderRadius: BorderRadius.circular(6)),
                            child: const Text("Upload Failed",
                                style:
                                    TextStyle(color: Colors.red, fontSize: 11)),
                          ),
                      ]),
                      const SizedBox(height: 10),
                      Text(order['customer'].toString().toUpperCase(),
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 6),
                      Text("$town | ${_shortDate(date)}",
                          style: const TextStyle(color: Colors.grey)),
                    ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text("Rs.$total",
                    style: const TextStyle(
                        fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 8),
                const Text("AMOUNT",
                    style: TextStyle(color: Colors.grey, fontSize: 11)),
              ])
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final headerDate = _transactions.isNotEmpty
        ? _transactions.first['date'] as DateTime
        : DateTime.now();

    final filtered = selectedFilter == 'All'
        ? _transactions
        : _transactions
            .where((t) => (t['type'] ?? '') == selectedFilter)
            .toList();

    final showUploadFab =
        _selectionMode && _selectedTxIds.isNotEmpty && !_isUploading;

    final orderTotal = _transactions.fold<int>(
        0, (sum, t) => sum + (t['type'] == 'Order' ? (t['total'] as int) : 0));
    final cashTotal = _transactions.fold<int>(
        0, (sum, t) => sum + (t['type'] == 'Cash' ? (t['total'] as int) : 0));

    print("Order total: $orderTotal | Cash total: $cashTotal");
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(_selectionMode
            ? "${_selectedTxIds.length} Selected"
            : "Home Screen"),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (_selectionMode)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _selectionMode = false;
                _selectedTxIds.clear();
              }),
            )
        ],
      ),
      floatingActionButton: _isUploading
          ? FloatingActionButton(
              onPressed: () {},
              backgroundColor: Colors.grey,
              child: SizedBox(
                width: 56,
                height: 56,
                child: Stack(alignment: Alignment.center, children: [
                  CircularProgressIndicator(
                      value: _uploadProgress, color: Colors.white),
                  const Icon(Icons.cloud_upload, color: Colors.white)
                ]),
              ),
            )
          : (showUploadFab
              ? FloatingActionButton.extended(
                  backgroundColor: Colors.green,
                  icon: const Icon(Icons.cloud_upload, color: Colors.white),
                  label: const Text("Upload",
                      style: TextStyle(color: Colors.white)),
                  onPressed: _uploadSelected,
                )
              : null),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
            child: Row(children: [
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Overview",
                          style: TextStyle(
                              fontSize: 34, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text(_formatDayDate(headerDate),
                          style: const TextStyle(
                              fontSize: 16, color: Colors.grey)),
                      const SizedBox(height: 12),
                      Row(children: [
                        const Icon(Icons.shopping_bag_outlined, size: 18),
                        const SizedBox(width: 6),
                        Text("Rs.$orderTotal"),
                        const SizedBox(width: 20),
                        const Icon(Icons.attach_money, size: 18),
                        const SizedBox(width: 6),
                        Text("Rs.$cashTotal"),
                      ])
                    ]),
              ),
              Column(children: [
                ElevatedButton(
                    onPressed: () {},
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8))),
                    child: const Text("Export",
                        style: TextStyle(color: Colors.white))),
                const SizedBox(height: 10),
                ElevatedButton(
                    onPressed: () async {
                      await AppDatabase.deleteDatabaseFile();
                      await AppDatabase.init();
                      await _loadTransactions();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('Local DB reset (dev)')));
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8))),
                    child: const Text("Clear",
                        style: TextStyle(color: Colors.white))),
              ])
            ]),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                for (final f in ['All', 'Draft', 'Order', 'Cash', 'Return'])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(f),
                      selected: selectedFilter == f,
                      onSelected: (_) => setState(() => selectedFilter = f),
                    ),
                  ),
              ]),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text("No Orders Yet",
                        style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: filtered.length,
                    itemBuilder: (context, i) {
                      final order = filtered[i];
                      final txnId = order['transactionId'] as int;
                      return GestureDetector(
                        onLongPress: () => setState(() {
                          _selectionMode = true;
                          _selectedTxIds.add(txnId);
                        }),
                        onTap: () {
                          if (_selectionMode) _toggleSelection(txnId);
                        },
                        child: _buildOrderCard(order),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
