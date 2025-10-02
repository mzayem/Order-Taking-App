import 'package:dmc/cash_screen.dart';
import 'package:dmc/profile_screen.dart';
import 'package:dmc/return_screen.dart';
import 'package:flutter/material.dart';
import 'order_screen.dart';

List<Map<String, dynamic>> savedOrders = [];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  final List<Widget> _screens = [
    const OverviewScreen(), // ✅ this is your existing home logic
    const OrderScreen(),
    const CashScreen(),
    const ReturnScreen(),
    const ProfileScreen(),
  ];

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

// 📊 Your original home content moved here

class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  String selectedFilter = "All";

  // simple date formatter: 19 Jul
  String _formatDate(DateTime dt) {
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

  @override
  Widget build(BuildContext context) {
    final filteredOrders = selectedFilter == "All"
        ? savedOrders.reversed.toList()
        : savedOrders.reversed
            .where((o) => (o['type'] ?? '') == selectedFilter)
            .toList();

    // compute totals for header
    final totalSum = savedOrders
        .where((o) => (o['type'] ?? '') == 'Order')
        .fold<int>(0, (s, o) => s + (o['total'] as int? ?? 0));
    final cashSum = savedOrders
        .where((o) => (o['type'] ?? '') == 'Cash')
        .fold<int>(0, (s, o) => s + (o['total'] as int? ?? 0));

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Overview"),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black,
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // header: date and totals
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Overview",
                        style: TextStyle(
                            fontSize: 34, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        savedOrders.isNotEmpty
                            ? _formatDate(savedOrders.last['date'] as DateTime)
                            : _formatDate(DateTime.now()),
                        style:
                            const TextStyle(fontSize: 16, color: Colors.grey),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Icon(Icons.shopping_bag_outlined, size: 18),
                          const SizedBox(width: 6),
                          Text("Rs.${totalSum.toString()}"),
                          const SizedBox(width: 20),
                          const Icon(Icons.attach_money, size: 18),
                          const SizedBox(width: 6),
                          Text("Rs.${cashSum.toString()}"),
                        ],
                      )
                    ],
                  ),
                ),

                // right side small action buttons (Export / Clear placeholders)
                Column(
                  children: [
                    ElevatedButton(
                      onPressed: () {},
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 18, vertical: 8),
                        elevation: 4,
                      ),
                      child: const Text("Export",
                          style: TextStyle(color: Colors.white)),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton(
                      onPressed: () {
                        setState(() {
                          savedOrders.clear();
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 22, vertical: 8),
                        elevation: 4,
                      ),
                      child: const Text("Clear",
                          style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // filter chips
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _filterButton("All"),
                  const SizedBox(width: 8),
                  _filterButton("Draft"),
                  const SizedBox(width: 8),
                  _filterButton("Order"),
                  const SizedBox(width: 8),
                  _filterButton("Cash"),
                  const SizedBox(width: 8),
                  _filterButton("Return"),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // orders list
          Expanded(
            child: filteredOrders.isEmpty
                ? const Center(
                    child: Text("No Orders Yet",
                        style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    itemCount: filteredOrders.length,
                    itemBuilder: (context, index) {
                      final order = filteredOrders[index];
                      return _buildOrderCard(order);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  // choice-like filter
  Widget _filterButton(String text) {
    final isSelected = selectedFilter == text;
    return ChoiceChip(
      label: Text(text),
      selected: isSelected,
      onSelected: (_) => setState(() => selectedFilter = text),
      selectedColor: Colors.black,
      backgroundColor: Colors.white,
      labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );
  }

  // order card UI
  Widget _buildOrderCard(Map<String, dynamic> order) {
    final String type = (order['type'] ?? 'Order').toString();
    final colorChip = (type == 'Draft') ? Colors.orange : Colors.black;
    IconData leftIcon;
    Widget leftCircle;

    switch (type) {
      case 'Draft':
        leftIcon = Icons.access_time;
        leftCircle = CircleAvatar(
          backgroundColor: Colors.orange.shade50,
          child: Icon(leftIcon, color: Colors.orange),
        );
        break;
      case 'Cash':
        leftIcon = Icons.attach_money;
        leftCircle = CircleAvatar(
          backgroundColor: Colors.green.shade50,
          child: Icon(leftIcon, color: Colors.green),
        );
        break;
      case 'Return':
        leftIcon = Icons.replay;
        leftCircle = CircleAvatar(
          backgroundColor: Colors.grey.shade100,
          child: Icon(leftIcon, color: Colors.black),
        );
        break;
      default:
        leftIcon = Icons.assignment_turned_in_outlined;
        leftCircle = CircleAvatar(
          backgroundColor: Colors.grey.shade100,
          child: Icon(leftIcon, color: Colors.black),
        );
    }

    final date =
        order['date'] is DateTime ? order['date'] as DateTime : DateTime.now();
    final town = order['town'] ?? '';
    final total = order['total'] ?? 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              // left icon
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: leftCircle,
              ),

              // center info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // type chip(s)
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text("Type",
                              style:
                                  TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                        const SizedBox(width: 8),
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
                      ],
                    ),

                    const SizedBox(height: 10),

                    // customer name
                    Text(
                      (order['customer'] ?? 'Customer Name')
                          .toString()
                          .toUpperCase(),
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.bold),
                    ),

                    const SizedBox(height: 6),
                    Text("$town | ${_shortDate(date)}",
                        style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ),

              // right amount
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("Rs.$total",
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 18)),
                  const SizedBox(height: 8),
                  const Text("AMOUNT",
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
}
