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
        final custRows = await db.query(
          'Customer',
          where: 'CustomerID = ?',
          whereArgs: [r['CustomerID']],
          limit: 1,
        );
        final custName = custRows.isNotEmpty
            ? custRows.first['Name'] as String
            : 'Customer #${r['CustomerID']}';

        // Get customer town
        final custTown = custRows.isNotEmpty
            ? (custRows.first['Town'] as String? ?? '')
            : '';

        // calculate display total: Cash uses CashAmount, others use TotalAmount
        double totalAmount = 0.0;
        final type = r['Type'] as String? ?? 'Order';
        final totalField = (r['TotalAmount'] ?? 0.0) as num;
        final cashField = (r['CashAmount'] ?? 0.0) as num;
        if (type == 'Cash') {
          totalAmount = cashField.toDouble();
        } else {
          totalAmount = totalField.toDouble();
        }

        items.add({
          'transactionId': r['TransactionID'] as int,
          'customer': custName,
          'date':
              DateTime.tryParse(r['Date'] as String? ?? '') ?? DateTime.now(),
          'total': totalAmount.toInt(),
          'type': type,
          'syncStatus': r['SyncStatus'] as String? ?? 'Pending',
          'uploadedAt': r['SyncStatus'] == 'Synced'
              ? DateTime.tryParse(r['UpdatedAt'] as String? ?? '')
              : null,
          'town': custTown,
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
    final userId = prefs.getInt('userId') ?? 0;
    final sync = SyncService(baseUrl);

    if (baseUrl.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('API URL not configured.')));
      setState(() => _isUploading = false);
      return;
    }

    final ids = _selectedTxIds.toList();
    final List<Map<String, dynamic>> transactionsToUpload = [];

    for (final id in ids) {
      final rows = await AppDatabase.getTransactionWithDetails(id);
      if (rows.isEmpty) continue;
      final header = rows.first;
      final details = <Map<String, dynamic>>[];
      for (final r in rows) {
        if (r['TransactionDetailID'] != null) {
          details.add({
            'product_id': r['ProductID'],
            'product_name': r['ProductName'],
            'batch_no': r['BatchNo'],
            'qty': r['Qty'],
            'unit_price': r['UnitPrice'],
            'total_price': r['TotalPrice'],
          });
        }
      }

      transactionsToUpload.add({
        'TransactionID': id,
        'UserID': userId,
        'CustomerID': header['CustomerID'],
        'Type': header['Type'],
        'Date': header['Date'],
        'TotalAmount': header['TotalAmount'],
        'CashAmount': header['CashAmount'],
        'Remarks': header['Remarks'],
        'SyncStatus': 'Pending',
        'lines': details,
      });
    }
    final res = await sync.uploadTransactions(transactionsToUpload);

    if (res['ok'] == true) {
      for (final id in ids) {
        await AppDatabase.markTransactionSynced(id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              "Upload complete: ${ids.length} transactions uploaded successfully"),
          duration: const Duration(seconds: 3),
        ),
      );
    } else {
      for (final id in ids) {
        await AppDatabase.markTransactionFailed(id);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Upload failed: ${res['error']}"),
          duration: const Duration(seconds: 3),
        ),
      );

      print("Upload failed: ${res['error']}");
    }

    await _loadTransactions();

    setState(() {
      _isUploading = false;
      _selectionMode = false;
      _selectedTxIds.clear();
      _uploadProgress = 0.0;
    });
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

  Future<void> _onEditSelected() async {
    if (_selectedTxIds.length != 1) return;
    final id = _selectedTxIds.first;
    final tx = _transactions.firstWhere((t) => t['transactionId'] == id,
        orElse: () => {});
    final type = tx['type'] as String? ?? 'Order';

    if (type == 'Order') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => OrderScreen(transactionId: id)),
      );
    } else if (type == 'Cash') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => CashScreen(transactionId: id)),
      );
    } else if (type == 'Return') {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReturnScreen(transactionId: id)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Edit for "$type" not implemented yet.')),
      );
    }

    await _loadTransactions();
    setState(() {
      _selectionMode = false;
      _selectedTxIds.clear();
    });
  }

  Future<void> _showTransactionDetailsDialog(int transactionId) async {
    final rows = await AppDatabase.getTransactionWithDetails(transactionId);
    if (rows.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Transaction not found')));
      return;
    }

    final header = rows.first;
    final db = await AppDatabase.init();
    final custRows = await db.query('Customer',
        where: 'CustomerID = ?', whereArgs: [header['CustomerID']], limit: 1);
    final customerName =
        custRows.isNotEmpty ? custRows.first['Name'] as String : 'Customer';

    final type = header['Type'] as String? ?? 'Order';
    final date =
        DateTime.tryParse(header['Date'] as String? ?? '') ?? DateTime.now();
    final totalAmount = header['TotalAmount'] ?? 0;
    final cashAmount = header['CashAmount'] ?? 0;
    final remarks = header['Remarks'] ?? '';

    final lines = <Map<String, dynamic>>[];
    for (final r in rows) {
      if (r['TransactionDetailID'] != null) {
        lines.add({
          'productName': r['ProductName'] ?? '',
          'qty': r['Qty'],
          'unitPrice': r['UnitPrice'],
          'totalPrice': r['TotalPrice'],
          'batchNo': r['BatchNo'],
        });
      }
    }

    await showDialog(
      context: context,
      builder: (ctx) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.all(20),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: Colors.white,
            ),
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: Colors.teal.shade100,
                        child: Icon(
                          type == 'Cash'
                              ? Icons.attach_money
                              : type == 'Return'
                                  ? Icons.assignment_return
                                  : Icons.shopping_cart,
                          color: Colors.teal.shade700,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              customerName.toUpperCase(),
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              "$type • ${_shortDate(date)}",
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              type == 'Cash' ? 'Cash Amount' : 'Total Amount',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Rs.${type == 'Cash' ? cashAmount : totalAmount}',
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal),
                            ),
                          ],
                        ),
                        if (remarks.toString().isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Remarks: ',
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              Expanded(
                                child: Text(
                                  remarks.toString(),
                                  style: const TextStyle(color: Colors.black87),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Order Lines',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const Divider(),
                  if (lines.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(12.0),
                        child: Text(
                          'No product lines',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: lines.length,
                      separatorBuilder: (_, __) =>
                          const Divider(height: 12, color: Colors.grey),
                      itemBuilder: (context, i) {
                        final l = lines[i];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            l['productName'].toString(),
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(
                            'Qty: ${l['qty']}  |  Batch: ${l['batchNo'] ?? ''}',
                            style: const TextStyle(color: Colors.grey),
                          ),
                          trailing: Text(
                            'Rs.${l['totalPrice']}',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.grey[700],
                        ),
                        child: const Text('Close'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () async {
                          Navigator.of(ctx).pop();
                          if (type == 'Order') {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    OrderScreen(transactionId: transactionId),
                              ),
                            );
                          } else if (type == 'Cash') {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    CashScreen(transactionId: transactionId),
                              ),
                            );
                          } else if (type == 'Return') {
                            await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    ReturnScreen(transactionId: transactionId),
                              ),
                            );
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                content: Text(
                                    'Edit for "$type" not implemented yet.')));
                          }
                          await _loadTransactions();
                          if (mounted) setState(() {});
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        icon: const Icon(Icons.edit, size: 18),
                        label: const Text('Edit'),
                      ),
                    ],
                  )
                ],
              ),
            ),
          ),
        );
      },
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

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(_selectionMode
            ? "${_selectedTxIds.length} Selected"
            : _formatDayDate(headerDate)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          if (_selectionMode && _selectedTxIds.length == 1)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit selected',
              onPressed: _onEditSelected,
            ),
          if (_selectionMode)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => setState(() {
                _selectionMode = false;
                _selectedTxIds.clear();
              }),
            ),
        ],
      ),
      floatingActionButton: _isUploading
          ? FloatingActionButton(
              onPressed: () {},
              backgroundColor: Colors.grey,
              child: SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                        value: _uploadProgress, color: Colors.white),
                    const Icon(Icons.cloud_upload, color: Colors.white),
                  ],
                ),
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
                      ]),
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
              child: Row(
                children: [
                  for (final f in ['All', 'Draft', 'Order', 'Cash', 'Return'])
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                          label: Text(f),
                          selected: selectedFilter == f,
                          onSelected: (_) =>
                              setState(() => selectedFilter = f)),
                    ),
                ],
              ),
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
                          if (_selectionMode) {
                            _toggleSelection(txnId);
                          } else {
                            _showTransactionDetailsDialog(txnId);
                          }
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
