import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/invoice_provider.dart';
import '../models/invoice_item.dart';
import '../models/payment_method.dart';
import '../models/already_added_item.dart';
import '../models/visit_route.dart';
import '../models/package_details.dart';
import '../services/session_service.dart';
import '../services/order_database_helper.dart';
import '../services/api_service.dart';
import '../services/order_data_normalizer.dart';
import '../services/draft_order_service.dart';
import '../services/payment_deal_service.dart';
import '../services/already_added_item_service.dart';
import '../services/visit_service.dart';
import '../utils/order_search_util.dart';
import '../utils/order_upload_formatter.dart';
import '../utils/package_eligibility_checker.dart';

class OrderAddScreen extends StatefulWidget {
  const OrderAddScreen({super.key});

  @override
  State<OrderAddScreen> createState() => _OrderAddScreenState();
}

class _OrderAddScreenState extends State<OrderAddScreen> {
  static const int _primaryColor = 0xFF2563EB;

  final TextEditingController _qtyController = TextEditingController();
  final TextEditingController _specialRemarksController =
      TextEditingController();
  final TextEditingController _specialPriceController = TextEditingController();
  final TextEditingController _deliveryAddressController =
      TextEditingController();

  // Item price display
  String _selectedItemPrice = '';

  // Fixed date/time when screen opens (not runtime)
  late String _fixedDateTime;
  late String _fixedOrderDate;

  // Android parity: Package-based pricing
  List<PackageDetails1> _packageDetails1 = [];
  List<PackageDetails2> _packageDetails2 = [];
  final Map<String, double> _itemPackagePrices =
      {}; // bookid -> calculated price
  final Map<String, double> _itemDiscounts = {}; // bookid -> discount %

  bool _loading = true;
  bool _fetchingFromApi = false;
  bool _savingDraft = false;
  bool _loadingDraft = false;
  bool _loadingPartyDependencies = false;
  String? _errorMessage;

  // Master/local reference data
  List<Map<String, dynamic>> _parties = [];
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _allPackages = [];
  List<Map<String, dynamic>> _packages = [];
  List<Map<String, dynamic>> _deliveryPoints = [];
  List<Map<String, dynamic>> _agencies = [];
  List<Map<String, dynamic>> _visits = [];

  // Android parity: payment deals, already-added items, visit/route data
  List<PaymentMethod> _paymentMethods = [];
  List<AlreadyAddedItem> _alreadyAddedItems = [];
  List<AgentApprovedVisit> _approvedVisits = [];
  VisitRouteData? _selectedRouteData;

  int? _selectedPartyIndex;
  int? _selectedItemIndex;
  int? _selectedPackageIndex;
  int? _selectedDeliveryPointIndex;
  int? _selectedAgencyIndex;
  int? _selectedVisitIndex;

  // Current draft/order state
  int? _currentDraftId;
  String? _currentLocalOrderId;
  String? _selectedPaymentDealId;

  String _userId = '';
  int? _currentUserId; // numeric user ID for eligibility checks

  @override
  void initState() {
    super.initState();
    // Set fixed date/time when screen opens
    final now = DateTime.now();
    _fixedDateTime = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
    _fixedOrderDate = DateFormat('dd-MMM-yyyy').format(now);

    _loadUserId();
    _loadLocalData();
    _loadPackageDetails();
  }

  Map<String, dynamic>? get _selectedParty {
    if (_selectedPartyIndex == null) return null;
    if (_selectedPartyIndex! < 0 || _selectedPartyIndex! >= _parties.length) {
      return null;
    }
    return _parties[_selectedPartyIndex!];
  }

  Map<String, dynamic>? get _selectedPackage {
    if (_selectedPackageIndex == null) return null;
    if (_selectedPackageIndex! < 0 ||
        _selectedPackageIndex! >= _packages.length) {
      return null;
    }
    return _packages[_selectedPackageIndex!];
  }

  String get _selectedPartyId =>
      _selectedParty?['partyid']?.toString().trim() ?? '';

  String get _currentOrderIdForDisplay {
    if (_currentLocalOrderId != null && _currentLocalOrderId!.isNotEmpty) {
      return _currentLocalOrderId!;
    }
    if (_currentDraftId != null) return _currentDraftId.toString();
    return 'NEW';
  }

  String get _currentOrderIdForUpload {
    if (_currentLocalOrderId != null && _currentLocalOrderId!.isNotEmpty) {
      return _currentLocalOrderId!;
    }
    if (_currentDraftId != null) return _currentDraftId.toString();
    return DateTime.now().millisecondsSinceEpoch.toString();
  }

  String get _currentPaymentDealForOrder {
    if (_selectedPaymentDealId != null && _selectedPaymentDealId!.isNotEmpty) {
      return _selectedPaymentDealId!;
    }
    return '';
  }

  Future<void> _loadUserId() async {
    final userId = await SessionService.getUserId();
    final username = await SessionService.getSavedUsername();
    if (mounted) {
      setState(() {
        _userId = userId != null ? '${userId}_${username ?? "user"}' : '—';
        _currentUserId = userId;
      });
    }
    // Load approved visits for visit/route selection
    await _loadApprovedVisits();
  }

  Future<void> _loadApprovedVisits() async {
    try {
      final visits = await VisitService.instance.getCachedApprovedVisits();
      if (mounted) {
        setState(() {
          _approvedVisits = visits;
        });
      }
    } catch (e) {
      debugPrint('[OrderAdd] Failed to load approved visits: $e');
    }
  }

  Future<void> _loadPackageDetails() async {
    try {
      final helper = OrderDatabaseHelper.instance;
      _packageDetails1 = await helper.getPackageDetails1();
      _packageDetails2 = await helper.getPackageDetails2();
      debugPrint(
        '[OrderAdd] Loaded PackageDetails1: ${_packageDetails1.length}',
      );
      debugPrint(
        '[OrderAdd] Loaded PackageDetails2: ${_packageDetails2.length}',
      );
    } catch (e) {
      debugPrint('[OrderAdd] Failed to load package details: $e');
    }
  }

  Future<void> _loadLocalData() async {
    await _reloadFromLocal(triggerSyncIfNeeded: true);
    await _loadDraftIfAny();
  }

  List<Map<String, dynamic>> _extractVisits(
    List<Map<String, dynamic>> storeData,
  ) {
    if (storeData.isEmpty) return [];
    if (storeData.first.containsKey('stores')) {
      final stores = storeData.first['stores'];
      if (stores is List) {
        return stores
            .map(
              (e) => e is Map
                  ? OrderDataNormalizer.normalizeDeliveryPoint(
                      Map<String, dynamic>.from(e),
                    )
                  : <String, dynamic>{},
            )
            .where((e) => e.isNotEmpty)
            .toList();
      }
    }
    return storeData
        .map(OrderDataNormalizer.normalizeDeliveryPoint)
        .where(
          (m) => (m['display_name']?.toString().trim().isNotEmpty ?? false),
        )
        .toList();
  }

  Future<void> _reloadFromLocal({required bool triggerSyncIfNeeded}) async {
    final helper = OrderDatabaseHelper.instance;
    final parties = await helper.getParties();
    final items = (await helper.getItems())
        .map(OrderDataNormalizer.normalizeItem)
        .toList();
    final rawPackages = (await helper.getPackages())
        .map(OrderDataNormalizer.normalizePackage)
        .toList();

    final selectedPartyId =
        _selectedPartyIndex != null && _selectedPartyIndex! < parties.length
        ? parties[_selectedPartyIndex!]['partyid']?.toString() ?? ''
        : '';
    final packages = _filterPackagesForParty(
      allPackages: rawPackages,
      partyId: selectedPartyId,
    );

    final deliveryPoints = await helper.getDeliveryPoints();
    final agencies = await helper.getGoodsAgencies();
    final storeData = await helper.getStoreData();
    final visits = _extractVisits(storeData);

    if (items.isNotEmpty) {
      debugPrint(
        '[OrderAdd] local items=${items.length}, sampleKeys=${items.first.keys.take(8).join(',')}',
      );
    } else {
      debugPrint('[OrderAdd] local items=0');
    }
    if (packages.isNotEmpty) {
      debugPrint(
        '[OrderAdd] local packages=${packages.length} (filtered), sampleKeys=${packages.first.keys.take(8).join(',')}',
      );
    } else {
      debugPrint('[OrderAdd] local packages=0 (after eligibility filter)');
    }

    if (mounted) {
      setState(() {
        _parties = parties;
        _items = items;
        _allPackages = rawPackages;
        _packages = packages;
        _deliveryPoints = deliveryPoints;
        _agencies = agencies;
        _visits = visits;
        if (_parties.isNotEmpty && _selectedPartyIndex == null) {
          _selectedPartyIndex = 0;
        }
      });

      if (_selectedPartyIndex != null && _parties.isNotEmpty) {
        await _onPartySelected(_selectedPartyIndex!, persistDraft: false);
      }

      final missingCriticalData = items.isEmpty || packages.isEmpty;
      if (triggerSyncIfNeeded && missingCriticalData) {
        await _fetchFromApiIfNeeded();
        return;
      }

      final errorText = missingCriticalData
          ? 'Items or packages are missing. Please run Update DB and try again.'
          : null;

      if (mounted) {
        setState(() {
          _loading = false;
          _fetchingFromApi = false;
          _errorMessage = errorText;
        });
      }
    }
  }

  List<Map<String, dynamic>> _filterPackagesForParty({
    required List<Map<String, dynamic>> allPackages,
    required String partyId,
  }) {
    return PackageEligibilityChecker.filterAllowedPackages(
      packages: allPackages,
      partyId: partyId,
      userId: _currentUserId?.toString() ?? '',
    );
  }

  /// Fetch data from API if local DB is empty - graceful fallback
  Future<void> _fetchFromApiIfNeeded() async {
    if (!mounted) return;

    setState(() {
      _fetchingFromApi = true;
      _errorMessage = null;
    });

    try {
      final result = await ApiService.fetchAndSaveLocalData();

      if (!mounted) return;

      if (result['success'] == true) {
        await _reloadFromLocal(triggerSyncIfNeeded: false);
      } else {
        if (mounted) {
          setState(() {
            _fetchingFromApi = false;
            _loading = false;
            _errorMessage =
                'Could not load data. Please sync from Update DB menu.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _fetchingFromApi = false;
          _loading = false;
          _errorMessage = 'Network error. Please check internet connection.';
        });
      }
    }
  }

  Future<void> _onPartySelected(int index, {bool persistDraft = true}) async {
    if (index < 0 || index >= _parties.length) return;
    final p = _parties[index];

    if (mounted) {
      setState(() {
        _selectedPartyIndex = index;
      });
    }

    final address = p['address'] ?? p['Address'] ?? p['delivery_address'] ?? '';
    _deliveryAddressController.text = address is String ? address : '';
    _clearSelectedItemSelection();
    _selectedPaymentDealId = null;

    await _reloadPartyDependentData();
    _recalculateTotals();

    if (persistDraft) {
      await _saveDraft();
    }
  }

  Future<void> _reloadPartyDependentData() async {
    final partyId = _selectedPartyId;
    if (_loadingPartyDependencies || partyId.isEmpty) {
      return;
    }

    _loadingPartyDependencies = true;
    try {
      final paymentMethodsFuture = PaymentDealService.instance
          .getPaymentMethods(partyId);
      final alreadyAddedFuture = AlreadyAddedItemService.instance
          .getAlreadyAddedItems();

      final paymentMethods = await paymentMethodsFuture;
      final alreadyAdded = await alreadyAddedFuture;

      final filteredPackages = _filterPackagesForParty(
        allPackages: _allPackages,
        partyId: partyId,
      );

      if (!mounted) return;

      setState(() {
        _paymentMethods = paymentMethods;
        _alreadyAddedItems = alreadyAdded;
        _packages = filteredPackages;
      });

      _ensurePackageSelectionStillValid();
      await _refreshSelectedPackagePricingIfNeeded();
      final selectedPackage = _selectedPackage;
      if (selectedPackage != null &&
          PaymentDealService.instance.isPaymentDealRequired(selectedPackage) &&
          _selectedPaymentDealId == null &&
          _paymentMethods.isNotEmpty) {
        _selectedPaymentDealId = _paymentMethods.first.id?.toString();
      }
    } catch (e) {
      debugPrint('[OrderAdd] Failed party dependent reload: $e');
    } finally {
      _loadingPartyDependencies = false;
    }
  }

  void _clearSelectedItemSelection() {
    _selectedItemIndex = null;
    _selectedItemPrice = '';
    _specialPriceController.clear();
  }

  void _ensurePackageSelectionStillValid() {
    var changed = false;
    if (_selectedPackageIndex == null || _packages.isEmpty) {
      _selectedPackageIndex = null;
      _itemPackagePrices.clear();
      _itemDiscounts.clear();
      changed = true;
      if (changed && mounted) {
        setState(() {});
      }
      return;
    }

    if (_selectedPackageIndex! >= _packages.length) {
      _selectedPackageIndex = null;
      _itemPackagePrices.clear();
      _itemDiscounts.clear();
      _clearSelectedItemSelection();
      changed = true;
      if (changed && mounted) {
        setState(() {});
      }
      return;
    }

    final pkg = _packages[_selectedPackageIndex!];
    final isAllowed = PackageEligibilityChecker.isPackageAllowed(
      package: pkg,
      partyId: _selectedPartyId,
      userId: _currentUserId?.toString() ?? '',
    );
    if (!isAllowed) {
      _selectedPackageIndex = null;
      _itemPackagePrices.clear();
      _itemDiscounts.clear();
      _clearSelectedItemSelection();
      changed = true;
    }

    if (changed && mounted) {
      setState(() {});
    }
  }

  Future<void> _refreshSelectedPackagePricingIfNeeded() async {
    final package = _selectedPackage;
    if (package == null) {
      _itemPackagePrices.clear();
      _itemDiscounts.clear();
      return;
    }

    final packageId =
        package['packageid']?.toString() ?? package['id']?.toString() ?? '';
    if (packageId.isEmpty) {
      _itemPackagePrices.clear();
      _itemDiscounts.clear();
      return;
    }
    await _calculateItemPricesForPackage(packageId);
  }

  Future<int?> _showSearchSelectionDialog({
    required String title,
    required List<Map<String, dynamic>> rows,
    required int? selectedIndex,
    required String Function(Map<String, dynamic> row) labelBuilder,
    String Function(Map<String, dynamic> row)? searchTextBuilder,
  }) async {
    if (rows.isEmpty) return null;

    final queryController = TextEditingController();
    return showDialog<int>(
      context: context,
      builder: (ctx) {
        var filteredIndices = List<int>.generate(rows.length, (i) => i);
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void applyFilter(String q) {
              final query = q.trim();
              if (query.isEmpty) {
                setDialogState(() {
                  filteredIndices = List<int>.generate(rows.length, (i) => i);
                });
                return;
              }

              // Android parity: use OrderSearchUtil for multi-token search with relevance scoring
              List<Map<String, dynamic>> searchResults;
              if (title.contains('Item')) {
                searchResults = OrderSearchUtil.searchItems(
                  items: rows,
                  query: query,
                );
              } else if (title.contains('Package')) {
                searchResults = OrderSearchUtil.searchPackages(
                  packages: rows,
                  query: query,
                );
              } else if (title.contains('Party')) {
                searchResults = OrderSearchUtil.searchParties(
                  parties: rows,
                  query: query,
                );
              } else {
                // Fallback to simple search for other types
                searchResults = rows.where((row) {
                  final base = labelBuilder(row).toLowerCase();
                  final extra = (searchTextBuilder?.call(row) ?? '')
                      .toLowerCase();
                  return base.contains(query.toLowerCase()) ||
                      extra.contains(query.toLowerCase());
                }).toList();
              }

              setDialogState(() {
                filteredIndices = searchResults
                    .map((result) => rows.indexWhere((r) => r == result))
                    .where((idx) => idx != -1)
                    .toList();
              });
            }

            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: queryController,
                      onChanged: applyFilter,
                      decoration: const InputDecoration(
                        hintText: 'Search...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: filteredIndices.isEmpty
                          ? const Center(child: Text('No results found'))
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount: filteredIndices.length,
                              itemBuilder: (context, i) {
                                final originalIndex = filteredIndices[i];
                                final row = rows[originalIndex];
                                final selected = selectedIndex == originalIndex;

                                // Show already-added indicator for items
                                final isAlreadyAdded =
                                    title.contains('Item') &&
                                    _alreadyAddedItems.any(
                                      (item) =>
                                          item.bookId ==
                                          (row['bookid']?.toString() ??
                                              row['id']?.toString()),
                                    );

                                return ListTile(
                                  dense: true,
                                  title: Row(
                                    children: [
                                      Expanded(child: Text(labelBuilder(row))),
                                      if (isAlreadyAdded)
                                        Container(
                                          margin: const EdgeInsets.only(
                                            left: 4,
                                          ),
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 4,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: Colors.orange,
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: const Text(
                                            'ADDED',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 9,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                  trailing: selected
                                      ? const Icon(Icons.check)
                                      : null,
                                  onTap: () =>
                                      Navigator.pop(ctx, originalIndex),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _pickItem() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No items available. Sync data first.')),
      );
      return;
    }

    // Android parity: validate package selection first
    if (_selectedPackageIndex == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select package first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final selected = await _showSearchSelectionDialog(
      title: 'Select Item',
      rows: _items,
      selectedIndex: _selectedItemIndex,
      labelBuilder: (row) => _itemDisplayWithPriceDiscount(row),
      searchTextBuilder: (row) {
        final name =
            row['name']?.toString() ?? row['bookname']?.toString() ?? '';
        final code =
            row['code']?.toString() ?? row['bookcode']?.toString() ?? '';
        return '$name $code';
      },
    );

    if (!mounted || selected == null) return;

    final selectedItem = _items[selected];
    final bookId =
        selectedItem['bookid']?.toString() ??
        selectedItem['id']?.toString() ??
        '';
    final price = _getItemPackagePrice(selectedItem);
    final discount = _getItemDiscount(selectedItem);
    final basePrice = _getBaseItemPriceForSelectedPackage(
      selectedItem,
      _selectedPackage,
    );

    _logPriceResolution(
      item: selectedItem,
      selectedPackage: _selectedPackage,
      basePrice: basePrice,
      finalPrice: price,
      discount: discount,
    );

    // Android parity: validate price (reject "no price" items)
    if (price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${itemDisplay(selectedItem)} has no price available'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Check duplicate in current cart
    final provider = context.read<InvoiceProvider>();
    final isDuplicateInCart = provider.items.any(
      (cartItem) => cartItem.id == bookId,
    );

    if (isDuplicateInCart) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${itemDisplay(selectedItem)} is already added to cart',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _selectedItemIndex = selected;
      // Show price with discount info
      if (discount > 0) {
        _selectedItemPrice =
            'Rs. ${price.toStringAsFixed(2)} (Discount: ${discount.toStringAsFixed(1)}%)';
      } else {
        _selectedItemPrice = 'Rs. ${price.toStringAsFixed(2)}';
      }
      _specialPriceController.text = price.toString();
    });
  }

  Future<void> _pickParty() async {
    if (_parties.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No parties available. Sync data first.')),
      );
      return;
    }
    final selected = await _showSearchSelectionDialog(
      title: 'Select Party',
      rows: _parties,
      selectedIndex: _selectedPartyIndex,
      labelBuilder: partyDisplay,
      searchTextBuilder: (row) {
        final name = partyDisplay(row);
        final address = row['address']?.toString() ?? '';
        return '$name $address';
      },
    );
    if (!mounted || selected == null) return;
    await _onPartySelected(selected);
  }

  Future<void> _pickAgency() async {
    if (_agencies.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No agencies available. Sync data first.'),
        ),
      );
      return;
    }
    final selected = await _showSearchSelectionDialog(
      title: 'Select Goods Agency',
      rows: _agencies,
      selectedIndex: _selectedAgencyIndex,
      labelBuilder: agencyDisplay,
      searchTextBuilder: (row) => agencyDisplay(row),
    );
    if (!mounted || selected == null) return;
    setState(() => _selectedAgencyIndex = selected);
    _recalculateTotals();
    await _saveDraft(syncItems: true);
  }

  Future<void> _pickPackage() async {
    if (_packages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No packages available. Sync data first.'),
        ),
      );
      return;
    }
    final selected = await _showSearchSelectionDialog(
      title: 'Select Package',
      rows: _packages,
      selectedIndex: _selectedPackageIndex,
      labelBuilder: packageDisplay,
      searchTextBuilder: (row) =>
          row['name']?.toString() ?? row['package_title']?.toString() ?? '',
    );
    if (!mounted || selected == null) return;
    await _onPackageSelected(selected);
  }

  Future<void> _pickDeliveryPoint() async {
    if (_deliveryPoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No delivery points available. Sync data first.'),
        ),
      );
      return;
    }
    final selected = await _showSearchSelectionDialog(
      title: 'Select Delivery Address',
      rows: _deliveryPoints,
      selectedIndex: _selectedDeliveryPointIndex,
      labelBuilder: (row) =>
          row['address']?.toString() ??
          row['name']?.toString() ??
          row['location']?.toString() ??
          '',
      searchTextBuilder: (row) =>
          row['address']?.toString() ??
          row['name']?.toString() ??
          row['location']?.toString() ??
          '',
    );
    if (!mounted || selected == null) return;
    setState(() {
      _selectedDeliveryPointIndex = selected;
      final point = _deliveryPoints[selected];
      _deliveryAddressController.text =
          point['address']?.toString() ??
          point['name']?.toString() ??
          point['location']?.toString() ??
          '';
    });
    _recalculateTotals();
    await _saveDraft(syncItems: true);
  }

  Future<void> _onPackageSelected(
    int index, {
    bool showSuccessMessage = true,
    bool persistDraft = true,
  }) async {
    if (index < 0 || index >= _packages.length) return;

    final selectedPackage = _packages[index];
    final isAllowed = PackageEligibilityChecker.isPackageAllowed(
      package: selectedPackage,
      partyId: _selectedPartyId,
      userId: _currentUserId?.toString() ?? '',
    );

    if (!isAllowed) {
      final reason = PackageEligibilityChecker.getDisallowedReason(
        package: selectedPackage,
        partyId: _selectedPartyId,
        userId: _currentUserId?.toString() ?? '',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(reason.isEmpty ? 'Package not allowed' : reason),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() {
      _selectedPackageIndex = index;
      _clearSelectedItemSelection();
    });

    final packageId =
        selectedPackage['packageid']?.toString() ??
        selectedPackage['id']?.toString() ??
        '';
    if (packageId.isNotEmpty) {
      await _calculateItemPricesForPackage(packageId);
    }

    if (!PaymentDealService.instance.isPaymentDealRequired(selectedPackage)) {
      _selectedPaymentDealId = null;
    } else if (_selectedPaymentDealId == null && _paymentMethods.isNotEmpty) {
      _selectedPaymentDealId = _paymentMethods.first.id?.toString();
    }

    _recalculateTotals();
    if (persistDraft) {
      await _saveDraft();
    }

    if (showSuccessMessage && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Package loaded. Item prices calculated.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _recalculateTotals() {
    final provider = context.read<InvoiceProvider>();
    provider.updateInvoiceInfo(
      partyName: _selectedParty != null ? partyDisplay(_selectedParty!) : null,
      goodsAgency:
          _selectedAgencyIndex != null &&
              _selectedAgencyIndex! < _agencies.length
          ? agencyDisplay(_agencies[_selectedAgencyIndex!])
          : null,
      deliveryAddress: _deliveryAddressController.text.trim().isNotEmpty
          ? _deliveryAddressController.text.trim()
          : null,
    );
  }

  Future<void> _loadDraftIfAny() async {
    if (_loadingDraft) return;
    _loadingDraft = true;
    try {
      final draft = await DraftOrderService.instance.getCurrentDraft();
      if (draft == null) return;

      _currentDraftId = draft.order.id;
      _currentLocalOrderId = draft.order.localOrderId;

      final provider = context.read<InvoiceProvider>();
      provider.reset();
      for (final item in draft.items) {
        provider.addItem(
          InvoiceItem(
            id: item.itemId ?? 'draft_${item.id}',
            name: item.itemName,
            price: item.unitPrice,
            quantity: item.quantity,
            discountPercent: item.discountPercent,
          ),
        );
      }

      final draftPartyId = draft.order.billToPartyId?.trim() ?? '';
      if (draftPartyId.isNotEmpty) {
        final partyIndex = _parties.indexWhere(
          (p) => p['partyid']?.toString().trim() == draftPartyId,
        );
        if (partyIndex != -1) {
          await _onPartySelected(partyIndex, persistDraft: false);
        }
      }

      final draftPackageId = draft.order.packageId?.trim() ?? '';
      if (draftPackageId.isNotEmpty) {
        final packageIndex = _packages.indexWhere(
          (pkg) =>
              (pkg['packageid']?.toString().trim() ??
                  pkg['id']?.toString().trim() ??
                  '') ==
              draftPackageId,
        );
        if (packageIndex != -1) {
          await _onPackageSelected(
            packageIndex,
            showSuccessMessage: false,
            persistDraft: false,
          );
        }
      }

      final draftAgencyId = draft.order.goodsAgencyId?.trim() ?? '';
      if (draftAgencyId.isNotEmpty) {
        final agencyIndex = _agencies.indexWhere(
          (a) =>
              a['agency_id']?.toString().trim() == draftAgencyId ||
              a['id']?.toString().trim() == draftAgencyId,
        );
        if (agencyIndex != -1) {
          _selectedAgencyIndex = agencyIndex;
        }
      }

      final draftDeliveryPointId = draft.order.deliveryPointId?.trim() ?? '';
      if (draftDeliveryPointId.isNotEmpty) {
        final dpIndex = _deliveryPoints.indexWhere(
          (d) =>
              d['delivery_point_id']?.toString().trim() ==
                  draftDeliveryPointId ||
              d['id']?.toString().trim() == draftDeliveryPointId,
        );
        if (dpIndex != -1) {
          _selectedDeliveryPointIndex = dpIndex;
        }
      }

      _selectedPaymentDealId = draft.order.paymentDealId?.trim();
      if ((draft.order.deliveryAddress ?? '').trim().isNotEmpty) {
        _deliveryAddressController.text = draft.order.deliveryAddress!.trim();
      }

      _recalculateTotals();
      if (mounted) {
        setState(() {});
      }
    } catch (e) {
      debugPrint('[OrderAdd] Failed to load draft: $e');
    } finally {
      _loadingDraft = false;
    }
  }

  Map<String, dynamic> _buildCurrentDraftOrder() {
    final party = _selectedParty;
    final package = _selectedPackage;

    final goodsAgency =
        _selectedAgencyIndex != null && _selectedAgencyIndex! < _agencies.length
        ? _agencies[_selectedAgencyIndex!]
        : null;
    final deliveryPoint =
        _selectedDeliveryPointIndex != null &&
            _selectedDeliveryPointIndex! < _deliveryPoints.length
        ? _deliveryPoints[_selectedDeliveryPointIndex!]
        : null;
    final visit =
        _selectedVisitIndex != null && _selectedVisitIndex! < _visits.length
        ? _visits[_selectedVisitIndex!]
        : null;

    return {
      'bill_to_party_id': party?['partyid']?.toString(),
      'party_name': party != null ? partyDisplay(party) : null,
      'package_id':
          package?['packageid']?.toString() ?? package?['id']?.toString(),
      'package_name': package != null ? packageDisplay(package) : null,
      'payment_deal_id': _currentPaymentDealForOrder,
      'goods_agency_id':
          goodsAgency?['agency_id']?.toString() ??
          goodsAgency?['id']?.toString(),
      'goods_agency_name': goodsAgency != null
          ? agencyDisplay(goodsAgency)
          : null,
      'delivery_point_id':
          deliveryPoint?['delivery_point_id']?.toString() ??
          deliveryPoint?['id']?.toString(),
      'delivery_point_name': deliveryPoint != null
          ? deliveryPointDisplay(deliveryPoint)
          : null,
      'visit_id': visit?['visit_id']?.toString(),
      'route_id': _selectedRouteData?.routeId,
      'delivery_address': _deliveryAddressController.text.trim(),
    };
  }

  Future<void> _saveDraft({bool syncItems = false}) async {
    if (_savingDraft) return;
    _savingDraft = true;
    try {
      final current = await DraftOrderService.instance.getCurrentDraft();
      if (current == null) return;

      _currentDraftId = current.order.id;
      _currentLocalOrderId = current.order.localOrderId;

      final header = _buildCurrentDraftOrder();
      if (!syncItems) {
        await DraftOrderService.instance.updateDraftHeader(
          _currentDraftId!,
          header,
        );
      } else {
        await DraftOrderService.instance.resetDraft(_currentDraftId!);
        await DraftOrderService.instance.updateDraftHeader(
          _currentDraftId!,
          header,
        );

        final provider = context.read<InvoiceProvider>();
        for (final item in provider.items) {
          await DraftOrderService.instance.insertLineItem(
            draftOrderId: _currentDraftId!,
            itemId: item.id,
            itemName: item.name,
            quantity: item.quantity,
            unitPrice: item.price,
            discountPercent: item.discountPercent,
            specialRemarks: _specialRemarksController.text.trim().isEmpty
                ? null
                : _specialRemarksController.text.trim(),
          );
        }
      }
    } catch (e) {
      debugPrint('[OrderAdd] Failed to save draft: $e');
    } finally {
      _savingDraft = false;
    }
  }

  static String _mapDisplay(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    }
    return m['id']?.toString() ?? '—';
  }

  static String partyDisplay(Map<String, dynamic> m) => _mapDisplay(m, [
    'display_name',
    'name',
    'partyname',
    'PartyName',
    'party_name',
    'title',
  ]);

  static String itemDisplay(Map<String, dynamic> m) {
    // Android format: "bookcode : bookname"
    final bookcode = m['bookcode']?.toString() ?? m['code']?.toString() ?? '';
    final bookname = m['bookname']?.toString() ?? m['name']?.toString() ?? '';

    if (bookcode.isNotEmpty && bookname.isNotEmpty) {
      return '$bookcode : $bookname';
    }

    return _mapDisplay(m, [
      'display_name',
      'bookname',
      'name',
      'itemname',
      'ItemName',
      'description',
      'title',
    ]);
  }

  static String packageDisplay(Map<String, dynamic> m) => _mapDisplay(m, [
    'display_name',
    'package_title',
    'name',
    'package_name',
    'PackageName',
    'title',
  ]);
  static String deliveryPointDisplay(Map<String, dynamic> m) =>
      _mapDisplay(m, ['name', 'store_name', 'StoreName', 'title', 'point']);
  static String agencyDisplay(Map<String, dynamic> m) =>
      _mapDisplay(m, ['name', 'agency_name', 'AgencyName', 'title']);

  double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  DateTime? _tryParseDate(String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final v = value.trim();
    for (final format in const [
      'yyyy-MM-dd',
      'dd-MM-yyyy',
      'MM-dd-yyyy',
      'dd/MM/yyyy',
      'MM/dd/yyyy',
      'yyyy/MM/dd',
      'dd-MMM-yyyy',
    ]) {
      try {
        return DateFormat(format).parseStrict(v);
      } catch (_) {}
    }
    return DateTime.tryParse(v);
  }

  String _normalizedItemId(Map<String, dynamic> item) {
    return item['bookid']?.toString().trim() ??
        item['id']?.toString().trim() ??
        '';
  }

  String _selectedPackageCountryId(Map<String, dynamic>? selectedPackage) {
    if (selectedPackage == null) return '';
    return selectedPackage['country_id']?.toString().trim() ??
        selectedPackage['countryid']?.toString().trim() ??
        selectedPackage['country']?.toString().trim() ??
        '';
  }

  Map<String, double> _parseAllPricesMap(String rawAllPrices) {
    final result = <String, double>{};
    final raw = rawAllPrices.trim();
    if (raw.isEmpty) return result;

    // Common Android payload pattern: "countryId-price" style pairs in one string.
    final pairRegex = RegExp(
      r'([A-Za-z0-9]+)\s*[:=_\-/]\s*([0-9]+(?:\.[0-9]+)?)',
    );
    for (final match in pairRegex.allMatches(raw)) {
      final key = match.group(1)?.trim() ?? '';
      final value = _toDouble(match.group(2));
      if (key.isNotEmpty && value != null && value > 0) {
        result[key] = value;
      }
    }
    if (result.isNotEmpty) return result;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((key, value) {
          final p = _toDouble(value);
          if (p != null && p > 0) {
            result[key.toString().trim()] = p;
          }
        });
        if (result.isNotEmpty) return result;
      }
      if (decoded is List) {
        for (final entry in decoded) {
          if (entry is Map) {
            final key =
                entry['country_id']?.toString().trim() ??
                entry['countryid']?.toString().trim() ??
                entry['country']?.toString().trim() ??
                entry['id']?.toString().trim() ??
                '';
            final p = _toDouble(
              entry['price'] ??
                  entry['rate'] ??
                  entry['value'] ??
                  entry['amount'],
            );
            if (key.isNotEmpty && p != null && p > 0) {
              result[key] = p;
            }
          } else {
            final p = _toDouble(entry);
            if (p != null && p > 0) {
              result['default'] = p;
            }
          }
        }
        if (result.isNotEmpty) return result;
      }
    } catch (_) {
      // Non-JSON string format is expected for many Android payloads.
    }

    final entries = raw.split(RegExp(r'[|;,#~]'));
    for (final entry in entries) {
      final token = entry.trim();
      if (token.isEmpty) continue;

      final keyValue = token.split(RegExp(r'[:=_-]'));
      if (keyValue.length >= 2) {
        final key = keyValue.first.trim();
        final valuePart = keyValue.sublist(1).join('').trim();
        final p = _toDouble(valuePart);
        if (key.isNotEmpty && p != null && p > 0) {
          result[key] = p;
          continue;
        }
      }

      final p = _toDouble(token);
      if (p != null && p > 0) {
        result['default'] = p;
      }
    }

    return result;
  }

  void _logPriceResolution({
    required Map<String, dynamic> item,
    required Map<String, dynamic>? selectedPackage,
    required double basePrice,
    required double finalPrice,
    required double discount,
  }) {
    if (!kDebugMode) return;

    final itemId = _normalizedItemId(item);
    final itemName = itemDisplay(item);
    final packageId =
        selectedPackage?['packageid']?.toString() ??
        selectedPackage?['id']?.toString() ??
        'none';
    final countryId = _selectedPackageCountryId(selectedPackage);
    final rawAllPrices = item['allprices']?.toString() ?? '';

    debugPrint(
      '[OrderAdd][Price] item=$itemId "$itemName" pkg=$packageId country=$countryId '
      'base=${basePrice.toStringAsFixed(2)} final=${finalPrice.toStringAsFixed(2)} '
      'discount=${discount.toStringAsFixed(2)} allprices="$rawAllPrices"',
    );
  }

  double _getBaseItemPriceForSelectedPackage(
    Map<String, dynamic> item,
    Map<String, dynamic>? selectedPackage,
  ) {
    final countryId = _selectedPackageCountryId(selectedPackage);
    final allPricesRaw = item['allprices']?.toString() ?? '';
    final allPricesMap = _parseAllPricesMap(allPricesRaw);

    if (countryId.isNotEmpty && allPricesMap.containsKey(countryId)) {
      return allPricesMap[countryId]!;
    }

    // Secondary fallback in case country id format differs between payloads.
    final normalizedCountryId = countryId.replaceAll(
      RegExp(r'[^0-9A-Za-z]'),
      '',
    );
    if (normalizedCountryId.isNotEmpty) {
      for (final entry in allPricesMap.entries) {
        final normalizedKey = entry.key.replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
        if (normalizedKey == normalizedCountryId) {
          return entry.value;
        }
      }
    }

    if (allPricesMap['default'] != null) {
      return allPricesMap['default']!;
    }

    // Final fallback: normalized item default price.
    final itemDefaultPrice = _itemPrice(item);
    if (itemDefaultPrice > 0) {
      return itemDefaultPrice;
    }
    return 0;
  }

  bool _isItemInPackageGroup({
    required String packageId,
    required String groupId,
    required String itemId,
  }) {
    if (packageId.isEmpty || groupId.isEmpty || itemId.isEmpty) return false;
    for (final group in _packageDetails2) {
      if (group.packageId != packageId) continue;
      if ((group.groupId ?? '').trim() != groupId.trim()) continue;
      final list = (group.items ?? '')
          .split(RegExp(r'[|,\s]+'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toSet();
      if (list.contains(itemId)) {
        return true;
      }
    }
    return false;
  }

  bool _isRuleApplicable({
    required PackageDetails1 rule,
    required String packageId,
    required String itemId,
    required int quantity,
    required double orderAmount,
    required DateTime now,
  }) {
    if ((rule.packageId ?? '').trim() != packageId.trim()) return false;

    final ruleItemId = (rule.itemId ?? '').trim();
    final ruleGroupId = (rule.groupId ?? '').trim();
    final byItem = ruleItemId.isNotEmpty && ruleItemId == itemId;
    final byGroup =
        ruleGroupId.isNotEmpty &&
        _isItemInPackageGroup(
          packageId: packageId,
          groupId: ruleGroupId,
          itemId: itemId,
        );

    if (!byItem && !byGroup) return false;

    final minQty = int.tryParse((rule.minQty ?? '').trim());
    final maxQty = int.tryParse((rule.maxQty ?? '').trim());
    if (minQty != null && quantity < minQty) return false;
    if (maxQty != null && quantity > maxQty) return false;

    final minAmt = _toDouble(rule.minAmt);
    final maxAmt = _toDouble(rule.maxAmt);
    if (minAmt != null && orderAmount < minAmt) return false;
    if (maxAmt != null && orderAmount > maxAmt) return false;

    final start = _tryParseDate(rule.startDate);
    final end = _tryParseDate(rule.endDate);
    if (start != null && now.isBefore(start)) return false;
    if (end != null && now.isAfter(end)) return false;

    return true;
  }

  Map<String, double> _applyPackageRulePriceIfAny({
    required Map<String, dynamic> item,
    required Map<String, dynamic>? selectedPackage,
    required double basePrice,
    int quantity = 1,
    double? orderAmount,
    DateTime? now,
  }) {
    final packageId =
        selectedPackage?['packageid']?.toString().trim() ??
        selectedPackage?['id']?.toString().trim() ??
        '';
    final itemId = _normalizedItemId(item);
    if (packageId.isEmpty || itemId.isEmpty) {
      return {'price': basePrice, 'discount': 0};
    }

    // Keep helper context-free; callers can provide current order amount.
    final totalAmount = orderAmount ?? 0;
    final at = now ?? DateTime.now();

    var appliedPrice = basePrice;
    var appliedDiscount = 0.0;

    for (final rule in _packageDetails1) {
      if (!_isRuleApplicable(
        rule: rule,
        packageId: packageId,
        itemId: itemId,
        quantity: quantity,
        orderAmount: totalAmount,
        now: at,
      )) {
        continue;
      }

      // Android parity: only explicit rule price should override base price.
      final overridePrice = _toDouble(rule.price);
      if (overridePrice != null && overridePrice > 0) {
        appliedPrice = overridePrice;
      }

      final percentage = _toDouble(rule.percentage);
      if (percentage != null && percentage > 0) {
        appliedDiscount = percentage;
      }

      break;
    }

    return {'price': appliedPrice, 'discount': appliedDiscount};
  }

  double _getFinalItemPrice(
    Map<String, dynamic> item,
    Map<String, dynamic>? selectedPackage,
  ) {
    final basePrice = _getBaseItemPriceForSelectedPackage(
      item,
      selectedPackage,
    );
    final applied = _applyPackageRulePriceIfAny(
      item: item,
      selectedPackage: selectedPackage,
      basePrice: basePrice,
    );
    return applied['price'] ?? basePrice;
  }

  static double _itemPrice(Map<String, dynamic> m) {
    final v =
        m['price'] ??
        m['Price'] ??
        m['rate'] ??
        m['Rate'] ??
        m['sale_price'] ??
        m['allprices'];
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  void _cachePricingForItem(
    Map<String, dynamic> item,
    Map<String, dynamic>? selectedPackage,
  ) {
    final bookId = _normalizedItemId(item);
    if (bookId.isEmpty) return;

    if (_itemPackagePrices.containsKey(bookId) &&
        _itemDiscounts.containsKey(bookId)) {
      return;
    }

    final basePrice = _getBaseItemPriceForSelectedPackage(
      item,
      selectedPackage,
    );
    final applied = _applyPackageRulePriceIfAny(
      item: item,
      selectedPackage: selectedPackage,
      basePrice: basePrice,
    );

    _itemPackagePrices[bookId] = applied['price'] ?? basePrice;
    _itemDiscounts[bookId] = applied['discount'] ?? 0;
  }

  // Keep package change fast: reset cache and compute only currently selected item.
  Future<void> _calculateItemPricesForPackage(String packageId) async {
    _itemPackagePrices.clear();
    _itemDiscounts.clear();

    final selectedPackage = _packages.firstWhere(
      (p) =>
          (p['packageid']?.toString().trim() ?? p['id']?.toString().trim()) ==
          packageId,
      orElse: () => _selectedPackage ?? <String, dynamic>{},
    );

    if (_selectedItemIndex != null &&
        _selectedItemIndex! >= 0 &&
        _selectedItemIndex! < _items.length) {
      _cachePricingForItem(_items[_selectedItemIndex!], selectedPackage);
    }

    if (mounted) {
      setState(() {});
    }
  }

  // Get package-calculated price for item
  double _getItemPackagePrice(Map<String, dynamic> item) {
    final bookId = _normalizedItemId(item);
    _cachePricingForItem(item, _selectedPackage);
    return _itemPackagePrices[bookId] ??
        _getFinalItemPrice(item, _selectedPackage);
  }

  // Get package discount for item
  double _getItemDiscount(Map<String, dynamic> item) {
    final bookId = _normalizedItemId(item);
    _cachePricingForItem(item, _selectedPackage);
    return _itemDiscounts[bookId] ?? 0;
  }

  // Item display with price & discount (Android UI format)
  String _itemDisplayWithPriceDiscount(Map<String, dynamic> item) {
    final display = itemDisplay(item);
    final price = _getItemPackagePrice(item);
    final discount = _getItemDiscount(item);

    if (discount > 0) {
      return '$display\nRs : ${price.toStringAsFixed(2)} _ Discount : ${discount.toStringAsFixed(1)}%';
    } else {
      return '$display\nRs : ${price.toStringAsFixed(2)}';
    }
  }

  /// Android parity: comprehensive order finalization with validation and upload
  Future<void> _finalizeAndUploadOrder() async {
    final provider = context.read<InvoiceProvider>();

    // Validation: items
    if (provider.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add items before finalizing')),
      );
      return;
    }

    // Validation: party selection
    if (_selectedPartyIndex == null ||
        _selectedPartyIndex! >= _parties.length) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a party')));
      return;
    }

    // Validation: package selection
    if (_selectedPackageIndex == null ||
        _selectedPackageIndex! >= _packages.length) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a package')));
      return;
    }

    await _saveDraft();

    final selectedParty = _parties[_selectedPartyIndex!];
    final selectedPackage = _packages[_selectedPackageIndex!];

    // Android parity: validate minimum order amount
    if (!PackageEligibilityChecker.meetsMinimumAmount(
      package: selectedPackage,
      orderTotal: provider.netAmount,
    )) {
      final minAmount = selectedPackage['minorderamount']?.toString() ?? '0';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Order amount (${provider.netAmount.toStringAsFixed(0)}) is below minimum ($minAmount)',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => WillPopScope(
        onWillPop: () async => false,
        child: const AlertDialog(
          content: Row(
            children: [
              CircularProgressIndicator(),
              SizedBox(width: 20),
              Text('Uploading order...'),
            ],
          ),
        ),
      ),
    );

    try {
      // Android parity: format order using OrderUploadFormatter
      final now = DateTime.now();
      final timestamp = now.millisecondsSinceEpoch.toString();
      final orderId = _currentOrderIdForUpload;

      final orderHeader = OrderUploadFormatter.formatOrderHeader(
        orderId: orderId,
        partyName: partyDisplay(selectedParty),
        packageName: packageDisplay(selectedPackage),
        deliveryPoint: _deliveryAddressController.text,
        orderBy: _userId,
        timestamp: timestamp,
        remarks: _specialRemarksController.text,
        grossTotal: provider.grossAmount.toStringAsFixed(2),
        discount: provider.totalDiscount.toStringAsFixed(2),
        netTotal: provider.netAmount.toStringAsFixed(2),
        deliveryParty: '',
        advancePaymentDeal: _currentPaymentDealForOrder,
        deliveryPartyRemarks: '',
        deliveryPointRemarks: '',
        visitId:
            _selectedVisitIndex != null && _selectedVisitIndex! < _visits.length
            ? _visits[_selectedVisitIndex!]['visit_id']?.toString() ?? ''
            : '',
        cityId: _selectedRouteData?.cities ?? '',
        location: '',
        routeId: _selectedRouteData?.routeId ?? '',
        goodsAgencyId:
            _selectedAgencyIndex != null &&
                _selectedAgencyIndex! < _agencies.length
            ? _agencies[_selectedAgencyIndex!]['agency_id']?.toString() ?? ''
            : '',
        goodsAgencyName:
            _selectedAgencyIndex != null &&
                _selectedAgencyIndex! < _agencies.length
            ? agencyDisplay(_agencies[_selectedAgencyIndex!])
            : '',
      );

      // Convert InvoiceItem list to Map list for formatter
      final itemMaps = provider.items
          .map(
            (item) => {
              'name': item.name,
              'price': item.price.toString(),
              'quantity': item.quantity.toString(),
              'discount_percent': item.discountPercent.toString(),
              'total': item.subtotal.toString(),
              'remarks': '',
              'direction_store': '',
              'special_remarks': '',
              'special_price': '0',
            },
          )
          .toList();

      final orderItems = OrderUploadFormatter.formatOrderItems(
        items: itemMaps,
        orderId: orderId,
      );

      // Android parity: send order using postOrderZ endpoint
      final response = await ApiService.postOrder(
        orderHeader: orderHeader,
        orderItems: orderItems,
      );

      // Convert Map response to OrderUploadResult
      final status = response['status']?.toString().toLowerCase() ?? '';
      final uploadResult = OrderUploadResult(
        success: status == 'success',
        message:
            response['message']?.toString() ??
            (status == 'success'
                ? 'Order uploaded successfully'
                : 'Upload failed'),
        bookingId: response['booking_id']?.toString(),
        error: status != 'success' ? response['error']?.toString() : null,
      );

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog

      if (uploadResult.success) {
        // Android parity: couple with attendance upload (matching Android uploadSuccess behavior)
        // Note: attendance upload would be triggered here in full implementation

        provider.finalize();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(uploadResult.message),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(uploadResult.message),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Upload failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  void dispose() {
    _qtyController.dispose();
    _specialRemarksController.dispose();
    _specialPriceController.dispose();
    _deliveryAddressController.dispose();
    super.dispose();
  }

  Future<void> _addItem() async {
    if (_selectedItemIndex == null || _selectedItemIndex! >= _items.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select item and enter quantity')),
      );
      return;
    }
    if (_qtyController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please enter quantity')));
      return;
    }

    final itemMap = _items[_selectedItemIndex!];
    final name = itemDisplay(itemMap);

    // Android parity: use package price calculation
    final packagePrice = _getItemPackagePrice(itemMap);
    final discount = _getItemDiscount(itemMap);

    // Allow special price override, but use package price as default
    final price = _specialPriceController.text.trim().isNotEmpty
        ? (double.tryParse(_specialPriceController.text) ?? packagePrice)
        : packagePrice;

    final itemId =
        itemMap['bookid']?.toString() ??
        itemMap['id']?.toString() ??
        itemMap['item_id']?.toString() ??
        DateTime.now().millisecondsSinceEpoch.toString();

    if (name.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selected item data is invalid. Please reselect item.'),
        ),
      );
      return;
    }

    // Android parity: validate price before adding
    if (price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name has no valid price. Cannot add to cart.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Android parity: check duplicate in cart
    final provider = context.read<InvoiceProvider>();
    final isDuplicateInCart = provider.items.any(
      (cartItem) => cartItem.id == itemId,
    );

    if (isDuplicateInCart) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$name is already in cart'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Android parity: warn about already-added items in previous orders
    final isAlreadyAdded = _alreadyAddedItems.any(
      (item) => item.bookId == itemId,
    );
    if (isAlreadyAdded) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            '⚠️ This item is already in an order for this party',
          ),
          backgroundColor: Colors.orange[700],
          duration: const Duration(seconds: 3),
        ),
      );
    }

    final item = InvoiceItem(
      id: itemId,
      name: name,
      price: price,
      quantity: int.tryParse(_qtyController.text) ?? 1,
      discountPercent: discount, // Android parity: apply package discount
    );
    await _addItemToOrder(item: item, showSuccessSnack: discount > 0);

    _qtyController.clear();
    _specialPriceController.clear();
    setState(() {
      _selectedItemIndex = null;
      _selectedItemPrice = '';
    });
  }

  Future<void> _addItemToOrder({
    required InvoiceItem item,
    bool showSuccessSnack = false,
  }) async {
    final provider = context.read<InvoiceProvider>();
    provider.addItem(item);
    _recalculateTotals();
    await _saveDraft();

    if (showSuccessSnack && mounted && item.discountPercent > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${item.name} added with ${item.discountPercent.toStringAsFixed(1)}% discount',
          ),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _removeItemFromOrder(InvoiceItem item) async {
    final provider = context.read<InvoiceProvider>();
    provider.removeItem(item.id);
    _recalculateTotals();
    await _saveDraft();
  }

  Future<void> _showDeleteConfirmation(
    BuildContext context,
    InvoiceItem item,
  ) async {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Delete Item'),
          content: Text('Remove "${item.name}" from cart?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                await _removeItemFromOrder(item);
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${item.name} removed from cart'),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              child: const Text('Delete', style: TextStyle(color: Colors.red)),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showEditQuantityDialog(
    BuildContext context,
    InvoiceProvider provider,
    InvoiceItem item,
  ) async {
    final qtyController = TextEditingController(text: item.quantity.toString());

    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Edit Quantity - ${item.name}'),
          content: TextField(
            controller: qtyController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Quantity',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final newQty = int.tryParse(qtyController.text);
                if (newQty == null || newQty <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please enter a valid quantity'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                provider.updateItemQuantity(item.id, newQty);
                _recalculateTotals();
                await _saveDraft(syncItems: true);
                Navigator.of(context).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${item.name} quantity updated to $newQty'),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
              child: const Text('Update'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = const Color(_primaryColor);
    if (_loading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: primary,
          title: const Text(
            'Add New Order',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: primary,
        elevation: 0,
        title: const Text(
          'Add New Order',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            child: Column(
              children: [
                // Show error message if API fetch failed
                if (_errorMessage != null)
                  Container(
                    color: Colors.red[50],
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.warning_rounded, color: Colors.red[700]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: TextStyle(
                              color: Colors.red[700],
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (!_fetchingFromApi && (_items.isEmpty || _packages.isEmpty))
                  Container(
                    color: Colors.amber[50],
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.amber[900]),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Items: ${_items.length} | Packages: ${_packages.length}. Run sync to refresh local cache.',
                            style: TextStyle(color: Colors.amber[900]),
                          ),
                        ),
                        TextButton(
                          onPressed: _fetchingFromApi
                              ? null
                              : () => _fetchFromApiIfNeeded(),
                          child: const Text('Retry Sync'),
                        ),
                      ],
                    ),
                  ),
                _buildTopSection(primary),
                _buildItemEntrySection(primary),
                _buildOrderDetailsSection(primary),
                _buildItemsListSection(primary),
                _buildSummarySection(primary),
                _buildBottomActionsSection(primary),
              ],
            ),
          ),
          // Show fetching overlay while API is being called
          if (_fetchingFromApi)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: Center(
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Loading data from server...'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopSection(Color primary) {
    return Container(
      color: primary.withOpacity(0.9),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _buildFieldRow(
            'Visit:',
            DropdownButton<int>(
              value: _visits.isEmpty ? null : _selectedVisitIndex,
              hint: const Text(
                'Select Visit',
                style: TextStyle(color: Colors.white),
              ),
              isExpanded: true,
              dropdownColor: primary,
              style: const TextStyle(color: Colors.white),
              underline: Container(),
              items: _visits
                  .asMap()
                  .entries
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(deliveryPointDisplay(e.value)),
                    ),
                  )
                  .toList(),
              onChanged: _visits.isEmpty
                  ? null
                  : (val) async {
                      setState(() => _selectedVisitIndex = val);
                      _recalculateTotals();
                      await _saveDraft(syncItems: true);
                    },
            ),
          ),
          const SizedBox(height: 8),
          _buildFieldRow(
            'Party :',
            InkWell(
              onTap: _parties.isEmpty ? null : _pickParty,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedPartyIndex != null &&
                                _selectedPartyIndex! < _parties.length
                            ? partyDisplay(_parties[_selectedPartyIndex!])
                            : (_parties.isEmpty
                                  ? 'No parties available'
                                  : 'Select Party'),
                        style: const TextStyle(color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.search, color: Colors.white, size: 18),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildFieldRow(
            'Goods\nAgency :',
            InkWell(
              onTap: _agencies.isEmpty ? null : _pickAgency,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedAgencyIndex != null &&
                                _selectedAgencyIndex! < _agencies.length
                            ? agencyDisplay(_agencies[_selectedAgencyIndex!])
                            : (_agencies.isEmpty
                                  ? 'No agencies available'
                                  : 'Select Agency'),
                        style: const TextStyle(color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.search, color: Colors.white, size: 18),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildFieldRow(
            'Delivery\nAddress:',
            InkWell(
              onTap: _deliveryPoints.isEmpty ? null : _pickDeliveryPoint,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _deliveryAddressController.text.trim().isNotEmpty
                            ? _deliveryAddressController.text
                            : (_deliveryPoints.isEmpty
                                  ? 'No delivery points available'
                                  : 'Select Delivery Address'),
                        style: const TextStyle(color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.search, color: Colors.white, size: 18),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _buildFieldRow(
            'Package :',
            InkWell(
              onTap: _packages.isEmpty ? null : _pickPackage,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _selectedPackageIndex != null &&
                                _selectedPackageIndex! < _packages.length
                            ? packageDisplay(_packages[_selectedPackageIndex!])
                            : (_packages.isEmpty
                                  ? 'No packages available'
                                  : 'Select Package'),
                        style: const TextStyle(color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.search, color: Colors.white, size: 18),
                  ],
                ),
              ),
            ),
          ),
          // Android parity: conditionally show payment deals when package scheme == 2
          if (_selectedPackageIndex != null &&
              _selectedPackageIndex! < _packages.length &&
              PaymentDealService.instance.isPaymentDealRequired(
                _packages[_selectedPackageIndex!],
              )) ...[
            const SizedBox(height: 8),
            _buildFieldRow(
              'Payment\nMethods:',
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: _paymentMethods.isEmpty
                      ? [
                          const Text(
                            'No payment methods available',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                        ]
                      : _paymentMethods.take(3).map((pm) {
                          return Text(
                            '${pm.id}: Rs.${pm.amount} - ${pm.remarks}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          );
                        }).toList(),
                ),
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            _buildFieldRow(
              'Payment\nDeal :',
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  _currentPaymentDealForOrder.isEmpty
                      ? '-'
                      : _currentPaymentDealForOrder,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ],
          // Android parity: show already-added items warning
          if (_alreadyAddedItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.3),
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: Colors.orange, width: 2),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${_alreadyAddedItems.length} items already in order for this party',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFieldRow(String label, Widget field) {
    return Row(
      children: [
        SizedBox(
          width: 90,
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(child: field),
      ],
    );
  }

  Widget _buildItemEntrySection(Color primary) {
    return Container(
      color: primary.withOpacity(0.15),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: InkWell(
                  onTap: _items.isEmpty ? null : _pickItem,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.grey),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _selectedItemIndex != null &&
                                        _selectedItemIndex! < _items.length
                                    ? itemDisplay(_items[_selectedItemIndex!])
                                    : (_items.isEmpty
                                          ? 'No items available'
                                          : 'Search Item'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              if (_selectedItemPrice.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 2),
                                  child: Text(
                                    _selectedItemPrice,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: primary,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.search, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _qtyController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  decoration: InputDecoration(
                    hintText: 'QTY',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                      borderRadius: BorderRadius.zero,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(
                onPressed: () async {
                  await _addItem();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 16,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                child: const Text(
                  'ADD',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _specialRemarksController,
                  decoration: InputDecoration(
                    hintText: 'Special Remarks',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                      borderRadius: BorderRadius.zero,
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ),
              Container(width: 2, height: 48, color: Colors.grey),
              Expanded(
                child: TextField(
                  controller: _specialPriceController,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Special Price',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.grey),
                      borderRadius: BorderRadius.zero,
                    ),
                    contentPadding: const EdgeInsets.all(12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrderDetailsSection(Color primary) {
    return Container(
      color: primary.withOpacity(0.15),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: primary,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Date : $_fixedDateTime',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: primary,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'ID : $_currentOrderIdForDisplay',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemsListSection(Color primary) {
    return Consumer<InvoiceProvider>(
      builder: (context, provider, child) {
        if (provider.items.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(32),
            child: const Text(
              'No items added yet',
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: primary, width: 2),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Column(
            children: [
              Container(
                color: primary,
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
                child: const Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Text(
                        'ITEM NAME',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'PRICE',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'QTY',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'TOTAL',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                    SizedBox(
                      width: 40,
                      child: Icon(
                        Icons.delete_outline,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                  ],
                ),
              ),
              ...provider.items.map(
                (item) => Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: primary.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: primary),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(
                          item.name,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          item.price.toStringAsFixed(1),
                          style: const TextStyle(fontSize: 12),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () =>
                              _showEditQuantityDialog(context, provider, item),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 4,
                              horizontal: 8,
                            ),
                            decoration: BoxDecoration(
                              color: primary.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: primary),
                            ),
                            child: Text(
                              item.quantity.toString(),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              item.subtotal.toStringAsFixed(0),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (item.discountAmount > 0)
                              Text(
                                '(_${item.discountAmount.toStringAsFixed(0)})',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.red,
                                ),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 40,
                        child: IconButton(
                          icon: const Icon(
                            Icons.delete,
                            color: Colors.red,
                            size: 18,
                          ),
                          onPressed: () =>
                              _showDeleteConfirmation(context, item),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummarySection(Color primary) {
    return Consumer<InvoiceProvider>(
      builder: (context, provider, child) {
        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: primary,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(4),
                    topRight: Radius.circular(4),
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Gross Amount',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Discount',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'Net Amount',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 16,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: primary),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(4),
                    bottomRight: Radius.circular(4),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      provider.grossAmount.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      '-${provider.totalDiscount.toStringAsFixed(1)}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.red,
                      ),
                    ),
                    Text(
                      provider.netAmount.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomActionsSection(Color primary) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Text(
                    _userId,
                    style: const TextStyle(fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    // Add remarks dialog
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(12),
                    side: const BorderSide(color: Colors.grey),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                  child: const Text(
                    'Want to add Remarks?',
                    style: TextStyle(fontSize: 13, color: Colors.black87),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                'Delivery:',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: DropdownButton<int>(
                    value: _deliveryPoints.isEmpty
                        ? null
                        : _selectedDeliveryPointIndex,
                    hint: const Text('Select Via Delivery Point'),
                    isExpanded: true,
                    underline: Container(),
                    items: _deliveryPoints
                        .asMap()
                        .entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(deliveryPointDisplay(e.value)),
                          ),
                        )
                        .toList(),
                    onChanged: _deliveryPoints.isEmpty
                        ? null
                        : (val) async {
                            setState(() => _selectedDeliveryPointIndex = val);
                            if (val != null && val < _deliveryPoints.length) {
                              final dp = _deliveryPoints[val];
                              _deliveryAddressController.text =
                                  dp['address']?.toString() ??
                                  dp['name']?.toString() ??
                                  dp['location']?.toString() ??
                                  '';
                            }
                            _recalculateTotals();
                            await _saveDraft();
                          },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    context.read<InvoiceProvider>().reset();
                    _clearSelectedItemSelection();
                    _recalculateTotals();
                    await _saveDraft(syncItems: true);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Order reset')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: const Text(
                    'RESET',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    await _finalizeAndUploadOrder();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  child: const Text(
                    'FINALIZE',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
