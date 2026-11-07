// lib/screens/home_screen.dart

import 'package:flutter/material.dart';
import 'package:dmc/widgets/app_toast.dart';
import 'package:dmc/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Screens
import 'order_screen.dart';
import 'cash_screen.dart';
import 'return_screen.dart';
import 'profile_screen.dart';
import 'widgets/floating_nav_bar.dart';
import 'widgets/overview_hero.dart';
import 'widgets/motion.dart';
import 'services/transaction_export.dart';
import 'widgets/notification_dropdown.dart';
import 'widgets/skeleton.dart';
import 'services/local_notifier.dart';

// Local database + Sync
import '../db/database.dart';
import '../services/api_service.dart';
import '../utils/ui_utils.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'dart:io';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  final List<Widget> _screens = [
    const OverviewScreen(),
    const OrderScreen(), // Initially empty, we'll update it dynamically
    const CashScreen(),
    const ReturnScreen(),
    const ProfileScreen(),
  ];

  List<Map<String, dynamic>> _customers = [];
  List<Map<String, dynamic>> _products = [];
  bool _isLoadingData = true;

  @override
  void initState() {
    super.initState();
    _loadLocalData();
  }

  Future<void> _loadLocalData() async {
    setState(() => _isLoadingData = true);
    final db = await AppDatabase.init();

    // Load Customers
    final custRows = await db.query('Customer');
    final Map<String, Map<String, dynamic>> uniqueCustomers = {};
    for (var r in custRows) {
      final name = r['Name'] as String;
      final id = r['CustomerID'] as int;
      if (!uniqueCustomers.containsKey(name) ||
          id > (uniqueCustomers[name]!['id'] as int)) {
        uniqueCustomers[name] = {
          "id": id,
          "name": name,
          "isNarcoticsAllowed": (r['IsNarcotics'] as int? ?? 0) == 1,
          "townId": r['Town']?.toString() ?? ''
        };
      }
    }
    _customers = uniqueCustomers.values.toList();

    // Load Products
    final prodRows = await db.query('Product');
    final Map<String, Map<String, dynamic>> uniqueProducts = {};
    for (var r in prodRows) {
      final name = r['Name'] as String;
      final id = r['ProductID'] as int;
      if (!uniqueProducts.containsKey(name) ||
          id > (uniqueProducts[name]!['id'] as int)) {
        uniqueProducts[name] = {
          'id': id,
          'name': name,
          'price': ((r['UnitPrice'] as num?)?.toDouble() ?? 0.0),
          'availableQty': (r['AvailableQty'] as int?) ?? 0,
          'type': r['ProductType']?.toString() ?? 'Medicine',
        };
      }
    }
    _products = uniqueProducts.values.toList();

    if (mounted) {
      setState(() {
        _isLoadingData = false;
        _screens[1] = OrderScreen(customers: _customers, products: _products);
        _screens[3] = const ReturnScreen();
      });
    }
  }

  void _onItemTapped(int index) {
    if (index == 1) {
      // Order tab
      // refresh order screen data when tapped
      _screens[1] = OrderScreen(customers: _customers, products: _products);
    }
    setState(() => _selectedIndex = index);
  }

  void refreshData() {
    _loadLocalData();
  }

  @override
  Widget build(BuildContext context) {
    // The bar floats over the page background (not over content), so tab
    // screens keep their own bottom layout untouched.
    // Back from Order / Cash / Return / Profile goes to Home first; Back on
    // Home leaves the app.
    return PopScope(
        canPop: _selectedIndex == 0,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) setState(() => _selectedIndex = 0);
        },
        child: Scaffold(
          // Tabs cross-fade with a slight zoom (220 ms); off with reduce motion.
          body: AnimatedSwitcher(
            duration: MediaQuery.of(context).disableAnimations
                ? Duration.zero
                : const Duration(milliseconds: 220),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: ScaleTransition(
                  scale: Tween(begin: 0.985, end: 1.0).animate(a),
                  child: child),
            ),
            child: KeyedSubtree(
                key: ValueKey(_selectedIndex), child: _screens[_selectedIndex]),
          ),
          bottomNavigationBar: FloatingNavBar(
            currentIndex: _selectedIndex,
            onTap: _onItemTapped,
            items: const [
              NavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home_rounded,
                  label: "Home"),
              NavItem(
                  icon: Icons.shopping_cart_outlined,
                  activeIcon: Icons.shopping_cart_rounded,
                  label: "Order"),
              NavItem(
                  icon: Icons.payments_outlined,
                  activeIcon: Icons.payments_rounded,
                  label: "Cash"),
              NavItem(
                  icon: Icons.assignment_return_outlined,
                  activeIcon: Icons.assignment_return_rounded,
                  label: "Return"),
              NavItem(
                  icon: Icons.person_outline,
                  activeIcon: Icons.person_rounded,
                  label: "Profile"),
            ],
          ),
        ));
  }
}

/// -------------------- OVERVIEW TAB -------------------- ///
class OverviewScreen extends StatefulWidget {
  const OverviewScreen({super.key});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen>
    with WidgetsBindingObserver {
  String selectedFilter = "All";
  bool _selectionMode = false;
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  DateTime _selectedDate = DateTime.now();
  bool _isInit = true;
  bool _isOnline = true;
  bool _paused = false;
  Timer? _connectivityTimer;
  int _unreadNotifications = 0;
  DateTime? _lastNotificationCheck;

  /// No polling: notifications are checked on open, on return to the app,
  /// when the connection comes back, and on Refresh — at most this often
  /// unless the user asks.
  static const _notificationCheckGap = Duration(minutes: 5);
  final Set<int> _selectedTxIds = {};
  List<Map<String, dynamic>> _transactions = [];
  bool _transactionsLoaded =
      false; // first local read done (skeleton until then)

  /// Last list from the server, shown at once when the bell dropdown opens.
  /// Null until the first successful check.
  List<Map<String, dynamic>>? _notifications;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _loadTransactions();
    _checkConnectivity();
    _connectivityTimer = Timer.periodic(
        const Duration(seconds: 45), (_) => _checkConnectivity());
    WidgetsBinding.instance.addObserver(this);
    _checkNotifications(force: true);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _paused = state != AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      _checkConnectivity();
      _checkNotifications();
      _refreshIfNewDay(); // app left open overnight
    }
  }

  /// Updates the bell badge and rings for anything new. Offline: no change.
  Future<void> _checkNotifications({bool force = false}) async {
    final last = _lastNotificationCheck;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < _notificationCheckGap) {
      return;
    }
    _lastNotificationCheck = DateTime.now();

    final res = await ApiService.fetchNotifications();
    if (res == null) {
      _lastNotificationCheck = last; // failed: allow the next trigger to retry
      return;
    }
    if (!mounted) return;
    setState(() {
      _unreadNotifications = res['unread'] as int? ?? 0;
      _notifications = List<Map<String, dynamic>>.from(
          (res['notifications'] as List)
              .map((n) => Map<String, dynamic>.from(n)));
    });
    await LocalNotifier.alertNew(res['notifications'] as List);
  }

  Future<void> _checkConnectivity() async {
    // Only while the app is on screen, and only a DNS lookup of OUR server
    // (not google.com): cheap on battery and data.
    if (_paused) return;
    bool online = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      final host = Uri.tryParse(prefs.getString('baseUrl') ?? '')?.host ?? '';
      if (host.isNotEmpty) {
        final r = await InternetAddress.lookup(host)
            .timeout(const Duration(seconds: 4));
        online = r.isNotEmpty && r[0].rawAddress.isNotEmpty;
      }
    } catch (_) {
      online = false;
    }
    if (mounted && _isOnline != online) {
      if (online) _checkNotifications(); // back online
      setState(() {
        _isOnline = online;
      });
    }
  }

  @override
  void dispose() {
    _connectivityTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_isInit) {
      _isInit = false;
      Future.microtask(_refreshIfNewDay);
    }
  }

  /// Customers/products/stock are downloaded on the first open of the day
  /// (and after every push), not on every app open.
  Future<void> _refreshIfNewDay() async {
    if (await ApiService.needsDailyRefresh()) {
      await _fetchCustomersAndProducts();
    }
  }

  /// After a push the server's stock and balances have changed.
  Future<void> _refreshAfterPush(Map<String, dynamic> res) async {
    if ((res['synced'] as int? ?? 0) > 0) await _fetchCustomersAndProducts();
  }

  // Status Tracking: 0 = Loading, 1 = Success, -1 = Error, null = Not Started
  void _showSyncDialog(
    BuildContext context,
    ValueNotifier<int?> customerStatus,
    ValueNotifier<int?> productStatus,
    ValueNotifier<int?> vendorGroupStatus,
    ValueNotifier<String?> errorMessage,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            backgroundColor: AppColors.surface,
            title: Text(
              "Syncing Data",
              style: TextStyle(
                  fontWeight: FontWeight.w600, color: AppColors.textPrimary),
            ),
            content: ValueListenableBuilder<String?>(
                valueListenable: errorMessage,
                builder: (context, errorTxt, child) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Customers Row
                      ValueListenableBuilder<int?>(
                        valueListenable: customerStatus,
                        builder: (context, status, child) {
                          return _buildSyncRow("Fetch Customers", status);
                        },
                      ),
                      const SizedBox(height: 16),
                      // Products Row
                      ValueListenableBuilder<int?>(
                        valueListenable: productStatus,
                        builder: (context, status, child) {
                          return _buildSyncRow("Fetch Products", status);
                        },
                      ),
                      const SizedBox(height: 16),
                      // Vendor Groups Row
                      ValueListenableBuilder<int?>(
                        valueListenable: vendorGroupStatus,
                        builder: (context, status, child) {
                          return _buildSyncRow("Fetch Vendor Groups", status);
                        },
                      ),
                      if (errorTxt != null) ...[
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: AppColors.redSoft,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: AppColors.redLine)),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.error_outline,
                                  color: AppColors.red, size: 20),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  errorTxt,
                                  style: TextStyle(
                                      color: AppColors.red, fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        )
                      ]
                    ],
                  );
                }),
            actions: [
              // Close appears once all three steps have finished.
              ListenableBuilder(
                  listenable: Listenable.merge(
                      [customerStatus, productStatus, vendorGroupStatus]),
                  builder: (context, _) {
                    final isDone = [
                      customerStatus.value,
                      productStatus.value,
                      vendorGroupStatus.value,
                    ].every((s) => s != null && s != 0);
                    if (!isDone) return const SizedBox.shrink();

                    return TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text("Close",
                          style: TextStyle(
                              color: AppColors.brand,
                              fontWeight: FontWeight.w600)),
                    );
                  })
            ],
          ),
        );
      },
    );
  }

  Widget _buildSyncRow(String title, int? status) {
    Widget icon;
    if (status == null || status == 0) {
      icon = SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: AppColors.brand));
    } else if (status == 1) {
      icon = Icon(Icons.check_circle, color: AppColors.green, size: 24);
    } else {
      icon = Icon(Icons.cancel, color: AppColors.red, size: 24);
    }

    return Row(
      children: [
        icon,
        const SizedBox(width: 16),
        Expanded(
          child: Text(title,
              style: TextStyle(fontSize: 16, color: AppColors.textPrimary)),
        ),
      ],
    );
  }

  void _showInvalidAccessPopup() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text("InValid Access",
            style:
                TextStyle(fontWeight: FontWeight.w600, color: AppColors.red)),
        content: const Text(
            "Your access is invalid. The server configuration has been changed."),
        actions: [
          ElevatedButton(
            style: AppButtons.primary,
            onPressed: () => Navigator.pop(ctx),
            child: const Text("OK"),
          )
        ],
      ),
    );
  }

  Future<void> _fetchCustomersAndProducts({bool showDialog = false}) async {
    final customerStatus = ValueNotifier<int?>(0);
    final productStatus = ValueNotifier<int?>(0);
    final vendorGroupStatus = ValueNotifier<int?>(0);
    final errorMessage = ValueNotifier<String?>(null);

    if (mounted && showDialog) {
      _showSyncDialog(context, customerStatus, productStatus, vendorGroupStatus,
          errorMessage);
    }

    /// ------------------- CUSTOMERS -------------------
    try {
      final customers = await ApiService.fetchCustomers();

      if (customers.isNotEmpty) {
        customerStatus.value = 1;
      } else {
        customerStatus.value = -1;
        errorMessage.value = "No customers found";
      }
    } catch (e) {
      customerStatus.value = -1;
      errorMessage.value = "Customer fetch error";
      debugPrint("Customer API error: $e");
    }

    /// ------------------- PRODUCTS -------------------
    try {
      final products = await ApiService.fetchProducts();

      if (products.isNotEmpty) {
        productStatus.value = 1;
      } else {
        productStatus.value = -1;
        errorMessage.value ??= "No products found";
      }
    } catch (e) {
      productStatus.value = -1;
      errorMessage.value ??= "Product fetch error";
      debugPrint("Product API error: $e");
    }

    /// ------------------- VENDOR GROUPS (Cash screen) -------------------
    // Zero groups is fine (not every company uses them); only "unreachable"
    // is a failure, and then the cached list is kept.
    final groups = await ApiService.fetchVendorGroups();
    if (groups != null) {
      vendorGroupStatus.value = 1;
    } else {
      vendorGroupStatus.value = -1;
      errorMessage.value ??= "Vendor group fetch error";
    }

    /// Refresh local DB → UI
    await _loadTransactions();

    // Command the parent HomeScreen to forcefully reload arrays and recreate child screens
    if (mounted) {
      context.findAncestorStateOfType<_HomeScreenState>()?.refreshData();
    }
  }
  // Future<void> testPushTransaction() async {
  //   try {
  //     const baseUrl = "http://app.dmcgroup.pk:2004";

  //     final url = Uri.parse("$baseUrl/api/Transaction/createTransaction");

  //     final body = {
  //       "userId": "57a85261-fe6b-4865-bfa5-aabfdd771611",
  //       "date": DateTime.now().toUtc().toIso8601String(),
  //       "customerId": 11807,
  //       "type": 0,
  //       "remarks": "Test Order",
  //       "totalAmount": 140,
  //       "transactionDetails": [
  //         {
  //           "productId": 101002,
  //           "batchNo": "",
  //           "qty": 10,
  //           "unitPrice": 14,
  //           "totalAmount": 140
  //         }
  //       ]
  //     };

  //     print("======= TEST API REQUEST =======");
  //     print("URL: $url");
  //     print("BODY: ${jsonEncode(body)}");

  //     final response = await http.post(
  //       url,
  //       headers: {
  //         "accept": "*/*",
  //         "Content-Type": "application/json",
  //       },
  //       body: jsonEncode(body),
  //     );

  //     print("======= TEST API RESPONSE =======");
  //     print("STATUS: ${response.statusCode}");
  //     print("BODY: ${response.body}");
  //   } catch (e) {
  //     print("TEST API ERROR: $e");
  //   }
  // }

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
        final type = (r['Type'] ?? 'Order').toString();

        final totalField = r['TotalAmount'];
        final cashField = r['CashAmount'];

        double parseValue(dynamic value) {
          if (value == null) return 0;
          if (value is num) return value.toDouble();
          if (value is String) return double.tryParse(value) ?? 0;
          return 0;
        }

        if (type == 'Cash') {
          totalAmount = parseValue(cashField);
        } else {
          totalAmount = parseValue(totalField);
        }
        items.add({
          'transactionId': r['TransactionID'] as int,
          'customer': custName,
          'date':
              DateTime.tryParse(r['Date'] as String? ?? '') ?? DateTime.now(),
          'total': totalAmount,
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
    if (mounted && !_transactionsLoaded) {
      setState(() => _transactionsLoaded = true); // skeleton off, even on error
    }
  }

  Future<void> _uploadSelected() async {
    if (_selectedTxIds.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final baseUrl = prefs.getString('baseUrl') ?? '';
    final savedHeaderRef = prefs.getString('headerRef');

    if (baseUrl.isNotEmpty) {
      try {
        final settingRes = await http
            .get(Uri.parse("$baseUrl/api/Setting"))
            .timeout(const Duration(seconds: 10));
        if (settingRes.statusCode == 200) {
          final settingBody = jsonDecode(settingRes.body);
          final currentHeaderRef = settingBody['headerRef']?.toString();

          if (savedHeaderRef != null && currentHeaderRef != savedHeaderRef) {
            if (mounted) {
              _showInvalidAccessPopup();
            }
            return;
          } else if (savedHeaderRef == null && currentHeaderRef != null) {
            await prefs.setString('headerRef', currentHeaderRef);
          }
        }
      } catch (e) {
        debugPrint("HeaderRef sync error: $e");
      }
    }

    final ids = _selectedTxIds.toList();
    int alreadyUploadedCount = 0;
    final List<int> validIdsToUpload = [];

    for (var id in ids) {
      final tx = _transactions.firstWhere((t) => t['transactionId'] == id,
          orElse: () => <String, dynamic>{});
      if (tx.isNotEmpty && tx['syncStatus'] == 'Synced') {
        alreadyUploadedCount++;
      } else {
        validIdsToUpload.add(id);
      }
    }

    if (alreadyUploadedCount == ids.length) {
      UiUtils.showBeautifulSnackBar(context, 'Already upload',
          isSuccess: false);
      setState(() {
        _selectionMode = false;
        _selectedTxIds.clear();
      });
      return;
    }

    if (alreadyUploadedCount > 0 && ids.length > 1) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Upload Summary'),
          content: Text(
              'Total cards selected: ${ids.length}\nAlready uploaded: $alreadyUploadedCount\nReady to upload: ${validIdsToUpload.length}'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: TextStyle(color: AppColors.red)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: AppButtons.primary,
              child: const Text('Proceed'),
            ),
          ],
        ),
      );

      if (proceed != true) {
        setState(() {
          _selectionMode = false;
          _selectedTxIds.clear();
        });
        return;
      }
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
    });

    final res = await ApiService.uploadTransactionIds(validIdsToUpload);
    if (mounted) {
      UiUtils.showBeautifulSnackBar(context, res['message'].toString(),
          isSuccess: res['ok'] == true);
    }
    await _refreshAfterPush(res);

    await _loadTransactions();

    setState(() {
      _isUploading = false;
      _selectionMode = false;
      _selectedTxIds.clear();
      _uploadProgress = 0;
    });
  }

  Future<void> _exportSelected() async {
    if (_selectedTxIds.isEmpty) return;

    final ids = _selectedTxIds.toList();
    await _exportTransactions(ids);
  }

  Future<void> _exportTransactions(List<int> ids) async {
    // CSV layout lives in TransactionExport (shared with Settings).
    final csvText = await TransactionExport.buildCsv(ids);
    if (csvText == null) {
      if (mounted) {
        UiUtils.showBeautifulSnackBar(context, "No transactions to export",
            isSuccess: false);
      }
      return;
    }

    try {
      if (!mounted) return;
      // Saves to Downloads, shows a toast with the location, opens share.
      await TransactionExport.saveAndShare(context, csvText);
      if (mounted) {
        setState(() {
          _selectionMode = false;
          _selectedTxIds.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        UiUtils.showBeautifulSnackBar(context, "Export failed: $e",
            isSuccess: false);
      }
    }
  }

  void _prevDay() => setState(
      () => _selectedDate = _selectedDate.subtract(const Duration(days: 1)));

  void _nextDay() => setState(
      () => _selectedDate = _selectedDate.add(const Duration(days: 1)));

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
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
      "Monday",
      "Tuesday",
      "Wednesday",
      "Thursday",
      "Friday",
      "Saturday",
      "Sunday"
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

    final dayName = weekdays[dt.weekday - 1];
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
    final total = (order['total'] ?? 0) as num;
    // Per-type tint for the chip (Order / Cash / Return / Draft).
    final (Color typeFg, Color typeBg) = switch (type) {
      'Cash' => (AppColors.green, AppColors.greenSoft),
      'Return' => (AppColors.red, AppColors.redSoft),
      'Draft' => (AppColors.orange, AppColors.orangeSoft),
      _ => (AppColors.brand, AppColors.brandSoft),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          // Glass card; the selected one gets a brand rim.
          decoration: BoxDecoration(
            color: isSelected ? AppColors.brandSoft : AppColors.glassFill,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
                color: isSelected ? AppColors.brand : AppColors.glassBorder,
                width: isSelected ? 1.6 : 1),
            boxShadow: [
              BoxShadow(
                  color: AppColors.shadow,
                  blurRadius: 12,
                  offset: const Offset(0, 4)),
            ],
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
                    color:
                        isSelected ? AppColors.brand : AppColors.textSecondary,
                    size: 26,
                  ),
                )
              else
                const SizedBox(width: 6),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(spacing: 8, runSpacing: 6, children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: typeBg,
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                          ),
                          child: Text(type,
                              style: TextStyle(
                                  color: typeFg,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                        ),
                        if (uploaded)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                                color: AppColors.green,
                                borderRadius: BorderRadius.circular(6)),
                            child: Text("Uploaded",
                                style: TextStyle(
                                    color: AppColors.onBrand, fontSize: 12)),
                          ),
                        if (uploadFailed)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                                color: AppColors.redSoft,
                                borderRadius: BorderRadius.circular(6)),
                            child: Text("Upload Failed",
                                style: TextStyle(
                                    color: AppColors.red, fontSize: 11)),
                          ),
                      ]),
                      const SizedBox(height: 10),
                      Text(order['customer'].toString().toUpperCase(),
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 6),
                      Text("ID: $txnId | $town | ${_shortDate(date)}",
                          style: TextStyle(color: AppColors.textSecondary)),
                    ]),
              ),
              const SizedBox(width: 8),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(
                  "Rs.${(total).toStringAsFixed(0)}",
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 8),
                Text("AMOUNT",
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
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
    final syncStatus = tx['syncStatus'] as String?;

    if (syncStatus == 'Synced') {
      if (mounted) {
        UiUtils.showBeautifulSnackBar(context, 'Cannot edit an uploaded $type',
            isSuccess: false);
      }
      setState(() {
        _selectionMode = false;
        _selectedTxIds.clear();
      });
      return;
    }

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
      AppToast.show(context, 'Edit for "$type" not implemented yet.',
          type: ToastType.warning);
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
      AppToast.show(context, 'Transaction not found', type: ToastType.error);
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
    final syncStatus = header['SyncStatus'] as String?;

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
              color: AppColors.surface,
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
                        backgroundColor: AppColors.brandSoft,
                        child: Icon(
                          type == 'Cash'
                              ? Icons.attach_money
                              : type == 'Return'
                                  ? Icons.assignment_return
                                  : Icons.shopping_cart,
                          color: AppColors.brandDark,
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
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              "$type • ${_shortDate(date)}",
                              style: TextStyle(color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: AppColors.brandSoft,
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
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerRight,
                                child: Text(
                                  'Rs.${(type == 'Cash' ? cashAmount : totalAmount).toStringAsFixed(0)}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.w600,
                                      color: AppColors.brand),
                                ),
                              ),
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
                                style: TextStyle(fontWeight: FontWeight.w600),
                              ),
                              Expanded(
                                child: Text(
                                  remarks.toString(),
                                  style:
                                      TextStyle(color: AppColors.textPrimary),
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
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const Divider(),
                  if (lines.isEmpty)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Text(
                          'No product lines',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: lines.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 12, color: AppColors.textSecondary),
                      itemBuilder: (context, i) {
                        final l = lines[i];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            l['productName'].toString(),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            'Qty: ${l['qty']}  |  Batch: ${l['batchNo'] ?? ''}',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                          trailing: Text(
                            'Rs.${l['totalPrice']}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
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
                          foregroundColor: AppColors.textSecondary,
                        ),
                        child: const Text('Close'),
                      ),
                      const SizedBox(width: 8),
                      if (syncStatus != 'Synced')
                        ElevatedButton.icon(
                          onPressed: () async {
                            Navigator.of(ctx).pop();
                            if (type == 'Order') {
                              await Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => OrderScreen(
                                    transactionId: transactionId,
                                    customers: context
                                            .findAncestorStateOfType<
                                                _HomeScreenState>()
                                            ?._customers ??
                                        [],
                                    products: context
                                            .findAncestorStateOfType<
                                                _HomeScreenState>()
                                            ?._products ??
                                        [],
                                  ),
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
                                  builder: (_) => ReturnScreen(
                                      transactionId: transactionId),
                                ),
                              );
                            } else {
                              AppToast.show(context,
                                  'Edit for "$type" not implemented yet.',
                                  type: ToastType.warning);
                            }
                            await _loadTransactions();
                            if (mounted) setState(() {});
                          },
                          style: AppButtons.primarySoft,
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
    final filteredByDate = _transactions.where((t) {
      final tDate = t['date'] as DateTime;
      return tDate.year == _selectedDate.year &&
          tDate.month == _selectedDate.month &&
          tDate.day == _selectedDate.day;
    }).toList();

    final filtered = selectedFilter == 'All'
        ? filteredByDate
        : filteredByDate
            .where((t) => (t['type'] ?? '') == selectedFilter)
            .toList();

    final showUploadFab =
        _selectionMode && _selectedTxIds.isNotEmpty && !_isUploading;

    final orderTotal = filteredByDate.fold<double>(
      0.0,
      (sum, t) =>
          sum +
          (t['type'] == 'Order' ? ((t['total'] ?? 0) as num).toDouble() : 0.0),
    );

    final cashTotal = filteredByDate.fold<double>(
      0.0,
      (sum, t) =>
          sum +
          (t['type'] == 'Cash' ? ((t['total'] ?? 0) as num).toDouble() : 0.0),
    );
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "Softifex",
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _isOnline ? AppColors.greenSoft : AppColors.redSoft,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: _isOnline ? AppColors.green : AppColors.red,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      _isOnline ? "Online" : "Offline",
                      style: TextStyle(
                        fontSize: 10,
                        color: _isOnline ? AppColors.green : AppColors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (!_selectionMode)
            Builder(
              builder: (bellContext) => IconButton(
                tooltip: "Notifications",
                icon: Badge(
                  isLabelVisible: _unreadNotifications > 0,
                  label: Text('$_unreadNotifications'),
                  child: const Icon(Icons.notifications_none),
                ),
                onPressed: () {
                  // Drop-down under the bell: 5 latest + "View all".
                  final box = bellContext.findRenderObject() as RenderBox;
                  final anchor = box.localToGlobal(Offset.zero) & box.size;
                  showNotificationDropdown(
                    context: context,
                    anchor: anchor,
                    initial: _notifications,
                    onChanged: (items, unread) {
                      if (!mounted) return;
                      setState(() {
                        _notifications = items;
                        _unreadNotifications = unread;
                      });
                    },
                  );
                },
              ),
            ),
          if (!_selectionMode)
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: "Refresh Data",
              onPressed: () {
                _fetchCustomersAndProducts(showDialog: true);
                _checkNotifications(force: true);
              },
            ),

          /// Select All Button (only when selecting)
          if (_selectionMode)
            // Tonal pill: readable on light and dark app bars.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _selectedTxIds
                        .addAll(filtered.map((t) => t['transactionId'] as int));
                  });
                },
                // Same raised look as every other button, in pill shape.
                style: AppButtons.primarySoft.merge(ElevatedButton.styleFrom(
                  minimumSize: const Size(0, 36),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  shape: const StadiumBorder(),
                )),
                icon: const Icon(Icons.select_all_rounded, size: 18),
                label: Text(
                  "All (${_selectedTxIds.length})",
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ),

          /// Sync Button (only when not selecting)
          if (!_selectionMode)
            IconButton(
              icon: const Icon(Icons.sync),
              tooltip: "Sync Transactions",
              onPressed: () async {
                final proceed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Sync Transactions'),
                    content: const Text(
                        'Do you want to sync all pending transactions to the server?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text('Cancel',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: AppButtons.primary,
                        child: const Text('Sync'),
                      ),
                    ],
                  ),
                );

                if (proceed != true) return;

                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => const Center(
                    child: CircularProgressIndicator(),
                  ),
                );

                final result = await ApiService.syncAllTransactions();

                if (mounted) Navigator.pop(context);

                if (mounted) {
                  UiUtils.showBeautifulSnackBar(
                      context, result['message']?.toString() ?? 'Sync failed',
                      isSuccess: result['ok'] == true);
                }

                _loadTransactions();
                await _refreshAfterPush(result);
              },
            ),

          /// Export Button (only if something is selected)
          if (_selectionMode && _selectedTxIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: 'Export selected',
              onPressed: _exportSelected,
            ),

          /// Delete Button (only if something is selected)
          if (_selectionMode && _selectedTxIds.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete),
              tooltip: 'Delete selected',
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Delete Items'),
                    content: Text(
                        'Are you sure you want to delete ${_selectedTxIds.length} item(s)?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text('Cancel',
                            style: TextStyle(color: AppColors.textSecondary)),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          Navigator.pop(ctx);
                          for (final id in _selectedTxIds) {
                            await AppDatabase.deleteTransaction(id);
                          }
                          setState(() {
                            _selectionMode = false;
                            _selectedTxIds.clear();
                          });
                          await _loadTransactions();
                        },
                        style: AppButtons.danger,
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
              },
            ),

          /// Edit Button (only if 1 selected)
          if (_selectionMode && _selectedTxIds.length == 1)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: 'Edit selected',
              onPressed: _onEditSelected,
            ),

          /// Close Selection Mode
          if (_selectionMode)
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: "Cancel Selection",
              onPressed: () {
                setState(() {
                  _selectionMode = false;
                  _selectedTxIds.clear();
                });
              },
            ),
        ],
      ),
      floatingActionButton: _isUploading
          ? FloatingActionButton(
              onPressed: () {},
              backgroundColor: AppColors.textSecondary,
              child: SizedBox(
                width: 56,
                height: 56,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CircularProgressIndicator(
                        value: _uploadProgress, color: AppColors.onBrand),
                    Icon(Icons.cloud_upload, color: AppColors.onBrand),
                  ],
                ),
              ),
            )
          : (showUploadFab
              ? FloatingActionButton.extended(
                  backgroundColor: AppColors.green,
                  icon: Icon(Icons.cloud_upload, color: AppColors.onBrand),
                  label: const Text("Upload"),
                  onPressed: _uploadSelected,
                )
              : null),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OverviewHero(
            dateLabel: _formatDayDate(_selectedDate),
            orderTotal: orderTotal,
            cashTotal: cashTotal,
            entries: filteredByDate.length,
            // Drafts are not meant to be uploaded, so they are not counted.
            notSynced: filteredByDate
                .where(
                    (t) => t['type'] != 'Draft' && t['syncStatus'] != 'Synced')
                .length,
            onExport: () {
              final ids =
                  filtered.map((e) => e['transactionId'] as int).toList();
              _exportTransactions(ids);
            },
            onPrevDay: _prevDay,
            onNextDay: _nextDay,
            onPickDate: _pickDate,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in ['All', 'Order', 'Cash', 'Return'])
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
            child: !_transactionsLoaded
                ? const TransactionListSkeleton()
                : filtered.isEmpty
                    ? Center(
                        child: Text("No Orders Yet",
                            style: TextStyle(color: AppColors.textSecondary)))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final order = filtered[i];
                          final txnId = order['transactionId'] as int;
                          return FadeSlideIn(
                            key: ValueKey(txnId),
                            index: i,
                            child: Pressable(
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
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
