// lib/home_screen.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'order_screen.dart';
import 'cash_screen.dart';
import 'return_screen.dart';
import 'profile_screen.dart';

/// Global saved orders list (other screens add to this list)
List<Map<String, dynamic>> savedOrders = [];

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

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

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

/// -------------------------
/// OverviewScreen (Home tab)
/// -------------------------
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  String selectedFilter = "All";

  // selection/upload state
  bool _selectionMode = false;
  final Set<int> _selectedIndexes = {};

  bool _isUploading = false;
  double _uploadProgress = 0.0;

  String _formatDayDate(DateTime dt) {
    final weekdays = [
      "Sunday",
      "Monday",
      "Tuesday",
      "Wednesday",
      "Thursday",
      "Friday",
      "Saturday"
    ];
    final months = [
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

  String _shortDate(DateTime dt) {
    final months = [
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

  // compute totals (keeps previous behaviour)
  int _totalOrdersSum() {
    return savedOrders
        .where((o) => (o['type'] ?? '') == 'Order')
        .fold<int>(0, (s, o) => s + (o['total'] as int? ?? 0));
  }

  int _cashSum() {
    return savedOrders
        .where((o) => (o['type'] ?? '') == 'Cash')
        .fold<int>(0, (s, o) => s + (o['total'] as int? ?? 0));
  }

  // Toggle selection of a reversed-indexed card (we display reversed list)
  void _toggleSelection(int savedOrdersIndex) {
    setState(() {
      if (_selectedIndexes.contains(savedOrdersIndex)) {
        _selectedIndexes.remove(savedOrdersIndex);
        if (_selectedIndexes.isEmpty) _selectionMode = false;
      } else {
        _selectedIndexes.add(savedOrdersIndex);
        _selectionMode = true;
      }
    });
  }

  // Simulates uploading a single order to an API.
  // Replace this with your real API call when available.
  Future<bool> _uploadOrderToApi(Map<String, dynamic> order) async {
    // simulate network latency & small chance of failure
    await Future.delayed(const Duration(milliseconds: 800));
    return true; // return true on success, false on failure
  }

  // Bulk upload selected orders. Marks uploaded: true and sets uploadedAt on success.
  Future<void> _uploadSelectedOrders() async {
    if (_selectedIndexes.isEmpty) return;

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    final indexes = _selectedIndexes.toList();
    final total = indexes.length;
    int done = 0;

    // sequential upload so we can show progress; you can convert to parallel if needed
    for (final idx in indexes) {
      // defensive: skip if already uploaded
      if (savedOrders[idx]['uploaded'] == true) {
        done++;
        setState(() {
          _uploadProgress = done / total;
        });
        continue;
      }

      final success = await _uploadOrderToApi(savedOrders[idx]);

      if (success) {
        savedOrders[idx]['uploaded'] = true;
        savedOrders[idx]['uploadedAt'] = DateTime.now();
      } else {
        // mark failure - user can retry later; here we add a 'uploadFailed' flag
        savedOrders[idx]['uploadFailed'] = true;
      }

      done++;
      setState(() {
        _uploadProgress = done / total;
      });
    }

    // small delay so progress reaches 100% visibly
    await Future.delayed(const Duration(milliseconds: 250));

    setState(() {
      _isUploading = false;
      _selectedIndexes.clear();
      _selectionMode = false;
      _uploadProgress = 0.0;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text("Selected orders uploaded (simulated).")),
    );
  }

  // Build filter chip
  Widget _filterButton(String text) {
    final isSelected = selectedFilter == text;
    return ChoiceChip(
      label: Text(text),
      selected: isSelected,
      onSelected: (_) => setState(() => selectedFilter = text),
      selectedColor: Colors.white,
      backgroundColor: Colors.black,
      labelStyle: TextStyle(color: isSelected ? Colors.black : Colors.white),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  // Build the order card UI (index is index in savedOrders list)
  Widget _buildOrderCard(
      Map<String, dynamic> order, int index, int displayIndex) {
    final String type = (order['type'] ?? 'Order').toString();
    final colorChip = (type == 'Draft') ? Colors.orange : Colors.black;
    final uploaded = order['uploaded'] == true;
    final uploadFailed = order['uploadFailed'] == true;

    final date =
        order['date'] is DateTime ? order['date'] as DateTime : DateTime.now();
    final town = order['town'] ?? '';
    final total = order['total'] ?? 0;

    final isSelected = _selectedIndexes.contains(index);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Material(
        elevation: isSelected ? 10 : 4,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? Colors.teal.withOpacity(0.08) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: isSelected
                ? Border.all(color: Colors.teal, width: 2)
                : Border.all(color: Colors.transparent),
          ),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // selection checkbox or spacing
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

              // main content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // chips row: type + uploaded indicator
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: colorChip,
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
                              borderRadius: BorderRadius.circular(6),
                            ),
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
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text("Upload Failed",
                                style:
                                    TextStyle(color: Colors.red, fontSize: 11)),
                          ),
                      ],
                    ),

                    const SizedBox(height: 10),

                    Text(
                      (order['customer'] ?? 'Customer Name')
                          .toString()
                          .toUpperCase(),
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold),
                    ),

                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Text("$town  |  ${_shortDate(date)}",
                            style: const TextStyle(color: Colors.grey)),
                        const SizedBox(width: 8),
                        if (order['uploadedAt'] != null)
                          Text(
                              " • ${_shortDate(order['uploadedAt'] as DateTime)}",
                              style: const TextStyle(
                                  color: Colors.green, fontSize: 12)),
                      ],
                    ),
                  ],
                ),
              ),

              // amount column
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("Rs.$total",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  const Text("AMOUNT",
                      style: TextStyle(color: Colors.grey, fontSize: 11)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // prepare filtered list (display reversed so latest first)
    final filteredOrders = selectedFilter == "All"
        ? savedOrders.reversed.toList()
        : savedOrders.reversed
            .where((o) => (o['type'] ?? '') == selectedFilter)
            .toList();

    final headerDate = savedOrders.isNotEmpty
        ? (savedOrders.last['date'] as DateTime)
        : DateTime.now();

    // floating upload FAB shown only when selection mode and at least 1 selected
    final showUploadFab =
        _selectionMode && _selectedIndexes.isNotEmpty && !_isUploading;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(_selectionMode
            ? "${_selectedIndexes.length} Selected"
            : _formatDayDate(headerDate)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_selectionMode)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () {
                setState(() {
                  _selectionMode = false;
                  _selectedIndexes.clear();
                });
              },
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
                  onPressed: _uploadSelectedOrders,
                )
              : null),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: title, totals, actions
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // left block
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
                          Text("Rs.${_totalOrdersSum()}"),
                          const SizedBox(width: 20),
                          const Icon(Icons.attach_money, size: 18),
                          const SizedBox(width: 6),
                          Text("Rs.${_cashSum()}"),
                        ])
                      ]),
                ),

                // right buttons
                Column(children: [
                  ElevatedButton(
                    onPressed: () {
                      // placeholder for export logic
                      ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("Export placeholder")));
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8))),
                    child: const Text("Export",
                        style: TextStyle(color: Colors.white)),
                  ),
                  const SizedBox(height: 10),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        savedOrders.clear();
                        _selectedIndexes.clear();
                        _selectionMode = false;
                      });
                    },
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8))),
                    child: const Text("Clear",
                        style: TextStyle(color: Colors.white)),
                  ),
                ])
              ],
            ),
          ),

          // Filter chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  _filterButton("All"),
                  const SizedBox(width: 8),
                  _filterButton("Draft"),
                  const SizedBox(width: 8),
                  _filterButton("Order"),
                  const SizedBox(width: 8),
                  _filterButton("Cash"),
                  const SizedBox(width: 8),
                  _filterButton("Return"),
                ])),
          ),

          const SizedBox(height: 12),

          // Orders list
          Expanded(
            child: filteredOrders.isEmpty
                ? const Center(
                    child: Text("No Orders Yet",
                        style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: filteredOrders.length,
                    itemBuilder: (context, displayIndex) {
                      // convert displayIndex (reversed list) to savedOrders index
                      final reversedIndex =
                          savedOrders.length - 1 - displayIndex;
                      final order = filteredOrders[displayIndex];
                      return GestureDetector(
                        onLongPress: () {
                          setState(() {
                            _selectionMode = true;
                            _selectedIndexes.add(reversedIndex);
                          });
                        },
                        onTap: () {
                          if (_selectionMode) {
                            _toggleSelection(reversedIndex);
                          } else {
                            // optional: open order detail
                          }
                        },
                        child:
                            _buildOrderCard(order, reversedIndex, displayIndex),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
