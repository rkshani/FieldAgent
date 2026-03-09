import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../providers/draft_order_provider.dart';
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
  bool _isExitingScreen = false;
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
  int? _selectedShipToOptionIndex;
  int? _selectedItemIndex;
  int? _selectedPackageIndex;
  int? _selectedDeliveryPointIndex;
  int? _selectedAgencyIndex;
  int? _selectedVisitIndex;

  // Current draft/order state
  int? _currentDraftId;
  int? _currentOrderSerialNo;
  String? _currentLocalOrderId;
  String? _selectedPaymentDealId;

  String _userId = '';
  int? _currentUserId; // numeric user ID for eligibility checks

  static const String _shipToDirect = 'direct';
  static const String _shipToUnavailable = 'unavailable';
  static const String _shipToParty = 'party';

  String? _selectedShipToPartyId;
  String? _selectedShipToPartyName;
  bool _showManualDeliveryAddressField = false;

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
    if (_currentOrderSerialNo != null) {
      return _currentOrderSerialNo.toString();
    }
    if (_currentDraftId != null) return _currentDraftId.toString();
    if (_currentLocalOrderId != null && _currentLocalOrderId!.isNotEmpty) {
      return _currentLocalOrderId!;
    }
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

  AgentApprovedVisit? get _selectedApprovedVisit {
    if (_selectedVisitIndex == null) return null;
    if (_selectedVisitIndex! < 0 ||
        _selectedVisitIndex! >= _approvedVisits.length) {
      return null;
    }
    return _approvedVisits[_selectedVisitIndex!];
  }

  String _visitRouteLabel(AgentApprovedVisit visit) {
    final route = visit.routes?.trim() ?? '';
    final visitId = (visit.visitId ?? '').trim();
    final cityId = (visit.cityIds ?? '').trim();
    if (route.isNotEmpty && visitId.isNotEmpty && cityId.isNotEmpty) {
      return '$route (Visit ID: $visitId, City: $cityId)';
    }
    if (route.isNotEmpty && visitId.isNotEmpty) {
      return '$route (Visit ID: $visitId)';
    }
    if (route.isNotEmpty) return route;
    return 'Visit ${visitId.isEmpty ? '-' : visitId}'.trim();
  }

  bool get _isShipToSelected =>
      (_selectedShipToPartyId ?? '').trim().isNotEmpty;

  String get _shipToDisplayLabel {
    final name = (_selectedShipToPartyName ?? '').trim();
    final id = (_selectedShipToPartyId ?? '').trim();
    if (name.isEmpty) return 'Select Ship To / Delivery Party';
    if (id.isEmpty) return name;
    return '$name _ $id';
  }

  List<Map<String, dynamic>> _buildShipToOptions() {
    final options = <Map<String, dynamic>>[
      {
        'type': _shipToDirect,
        'ship_to_party_id': '0',
        'delivery_party_name': 'Direct to Party',
        'display': 'Direct to Party _ 0',
      },
      {
        'type': _shipToUnavailable,
        'ship_to_party_id': '0',
        'delivery_party_name': 'Unavailable Party',
        'display': 'Unavailable Party _ 0',
      },
    ];

    for (final party in _parties) {
      final partyId =
          party['partyid']?.toString().trim() ??
          party['id']?.toString().trim() ??
          '';
      final partyName = partyDisplay(party).trim();
      if (partyId.isEmpty || partyName.isEmpty) continue;
      options.add({
        'type': _shipToParty,
        'ship_to_party_id': partyId,
        'delivery_party_name': partyName,
        'display': '$partyName _ $partyId',
      });
    }

    return options;
  }

  Future<void> _pickShipToDeliveryAddress() async {
    final options = _buildShipToOptions();
    final selected = await _showSearchSelectionDialog(
      title: 'Select Ship To / Delivery Address',
      rows: options,
      selectedIndex: _selectedShipToOptionIndex,
      labelBuilder: (row) => row['display']?.toString() ?? '',
      searchTextBuilder: (row) => row['display']?.toString() ?? '',
    );

    if (!mounted || selected == null) return;
    await _onShipToSelected(selected, options[selected]);
  }

  Future<void> _onShipToSelected(int index, Map<String, dynamic> option) async {
    final type = option['type']?.toString() ?? _shipToParty;
    final shipToId = option['ship_to_party_id']?.toString().trim() ?? '';
    final shipToName = option['delivery_party_name']?.toString().trim() ?? '';
    final shipToChanged =
        (_selectedShipToPartyId ?? '').trim() != shipToId ||
        (_selectedShipToPartyName ?? '').trim() != shipToName;

    setState(() {
      _selectedShipToOptionIndex = index;
      _selectedShipToPartyId = shipToId;
      _selectedShipToPartyName = shipToName;

      if (shipToChanged) {
        _selectedPackageIndex = null;
      }

      if (type == _shipToUnavailable) {
        _showManualDeliveryAddressField = true;
      } else {
        _showManualDeliveryAddressField = false;
        _deliveryAddressController.clear();
      }
    });

    DraftOrderProvider? draftProvider;
    try {
      draftProvider = Provider.of<DraftOrderProvider>(context, listen: false);
    } catch (_) {
      draftProvider = null;
    }

    if (draftProvider != null) {
      await draftProvider.updateShipTo(
        shipToId.isEmpty ? null : shipToId,
        shipToName.isEmpty ? null : shipToName,
      );
    }

    await _saveDraft();
  }

  String _deliveryPointIdFromMap(Map<String, dynamic> point) {
    return point['store_id']?.toString().trim() ??
        point['storeid']?.toString().trim() ??
        point['delivery_point_id']?.toString().trim() ??
        point['id']?.toString().trim() ??
        '';
  }

  String _deliveryPointNameFromMap(Map<String, dynamic> point) {
    return point['store_name']?.toString().trim() ??
        point['storename']?.toString().trim() ??
        point['name']?.toString().trim() ??
        point['display_name']?.toString().trim() ??
        '';
  }

  String _deliveryPointLocationFromMap(Map<String, dynamic> point) {
    return point['location']?.toString().trim() ??
        point['address']?.toString().trim() ??
        point['city']?.toString().trim() ??
        '';
  }

  Future<void> _onDeliveryPointSelected(
    int? index, {
    bool persistDraft = true,
  }) async {
    if (index == null || index < 0 || index >= _deliveryPoints.length) return;

    final point = _deliveryPoints[index];
    final deliveryPointId = _deliveryPointIdFromMap(point);
    final deliveryPointName = _deliveryPointNameFromMap(point);
    final location = _deliveryPointLocationFromMap(point);

    setState(() {
      _selectedDeliveryPointIndex = index;
      if (!_showManualDeliveryAddressField && location.isNotEmpty) {
        _deliveryAddressController.text = location;
      }
    });

    DraftOrderProvider? draftProvider;
    try {
      draftProvider = Provider.of<DraftOrderProvider>(context, listen: false);
    } catch (_) {
      draftProvider = null;
    }

    if (draftProvider != null) {
      await draftProvider.updateDeliveryPoint(
        deliveryPointId.isEmpty ? null : deliveryPointId,
        deliveryPointName.isEmpty ? null : deliveryPointName,
      );
    }

    _recalculateTotals();
    if (persistDraft) {
      await _saveDraft();
    }
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
      debugPrint('[OrderAdd] loading approved visits...');
      final visits = await VisitService.instance.getApprovedVisits(
        preferRemote: true,
      );
      if (mounted) {
        setState(() {
          _approvedVisits = visits;
        });

        debugPrint(
          '[OrderAdd] approved visits loaded=${_approvedVisits.length}',
        );
        if (_approvedVisits.isNotEmpty) {
          final first = _approvedVisits.first;
          debugPrint(
            '[OrderAdd] first visit visitId=${first.visitId} routeId=${first.routeId} cityIds=${first.cityIds} route=${first.routes}',
          );
        }

        if (_currentDraftId != null && _approvedVisits.isNotEmpty) {
          final draft = await DraftOrderService.instance.getCurrentDraft();
          final visitId = draft?.order.visitId?.trim() ?? '';
          if (visitId.isNotEmpty) {
            final idx = _approvedVisits.indexWhere(
              (v) => (v.visitId ?? '').trim() == visitId,
            );
            if (idx != -1 && mounted) {
              setState(() {
                _selectedVisitIndex = idx;
              });
              await _syncVisitedPartiesForSelectedVisit();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('[OrderAdd] Failed to load approved visits: $e');
    }
  }

  Future<void> _syncVisitedPartiesForSelectedVisit() async {
    final selectedVisit = _selectedApprovedVisit;
    if (selectedVisit == null) return;
    final visitId = (selectedVisit.visitId ?? '').trim();
    final routeId = (selectedVisit.routeId ?? '').trim();
    final cityId = (selectedVisit.cityIds ?? '').trim();
    debugPrint(
      '[OrderAdd] sync visited parties visitId=$visitId routeId=$routeId cityId=$cityId',
    );
    if (visitId.isEmpty || routeId.isEmpty) return;

    final parties = await VisitService.instance.fetchAndSaveVisitedParties(
      visitId: visitId,
      routeId: routeId,
      cityId: cityId,
    );
    debugPrint('[OrderAdd] visited parties synced count=${parties.length}');
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

    final deliveryPoints = await helper.getAllDeliveryPointsName();
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
      });

      if (_selectedPartyIndex != null &&
          _selectedPartyIndex! < _parties.length &&
          _parties.isNotEmpty) {
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
        // Keep package flow smooth: default ship-to as Direct to Party on party change.
        _selectedShipToOptionIndex = 0;
        _selectedShipToPartyId = '0';
        _selectedShipToPartyName = 'Direct to Party';
        _showManualDeliveryAddressField = false;
        _selectedPackageIndex = null;
      });
    }

    final address = p['address'] ?? p['Address'] ?? p['delivery_address'] ?? '';
    _deliveryAddressController.text = address is String ? address : '';
    _clearSelectedItemSelection();
    _selectedPaymentDealId = null;

    DraftOrderProvider? draftProvider;
    try {
      draftProvider = Provider.of<DraftOrderProvider>(context, listen: false);
    } catch (_) {
      draftProvider = null;
    }
    if (draftProvider != null) {
      await draftProvider.updateShipTo('0', 'Direct to Party');
    }

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
    String? defaultOptionLabel,
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
                      child:
                          (filteredIndices.isEmpty &&
                              (defaultOptionLabel == null ||
                                  defaultOptionLabel.trim().isEmpty))
                          ? const Center(child: Text('No results found'))
                          : ListView.builder(
                              shrinkWrap: true,
                              itemCount:
                                  filteredIndices.length +
                                  ((defaultOptionLabel != null &&
                                          defaultOptionLabel.trim().isNotEmpty)
                                      ? 1
                                      : 0),
                              itemBuilder: (context, i) {
                                final hasDefaultOption =
                                    defaultOptionLabel != null &&
                                    defaultOptionLabel.trim().isNotEmpty;

                                if (hasDefaultOption && i == 0) {
                                  final defaultSelected = selectedIndex == null;
                                  return ListTile(
                                    dense: true,
                                    title: Text(defaultOptionLabel),
                                    trailing: defaultSelected
                                        ? const Icon(Icons.check)
                                        : null,
                                    onTap: () => Navigator.pop(ctx, -1),
                                  );
                                }

                                final listIndex = hasDefaultOption ? i - 1 : i;
                                final originalIndex =
                                    filteredIndices[listIndex];
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
      defaultOptionLabel: 'Select Party',
      searchTextBuilder: (row) {
        final name = partyDisplay(row);
        final address = row['address']?.toString() ?? '';
        return '$name $address';
      },
    );
    if (!mounted || selected == null) return;
    if (selected == -1) {
      setState(() {
        _selectedPartyIndex = null;
        _selectedShipToOptionIndex = null;
        _selectedShipToPartyId = null;
        _selectedShipToPartyName = null;
        _showManualDeliveryAddressField = false;
        _selectedPackageIndex = null;
        _selectedAgencyIndex = null;
      });
      _deliveryAddressController.clear();
      _clearSelectedItemSelection();
      _selectedPaymentDealId = null;
      _paymentMethods = [];
      _alreadyAddedItems = [];
      _packages = _filterPackagesForParty(
        allPackages: _allPackages,
        partyId: '',
      );
      _recalculateTotals();
      await _saveDraft(syncItems: true);
      return;
    }
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
    if (!_isShipToSelected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select Ship To first.')),
      );
      return;
    }
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
      defaultOptionLabel: 'Select Package',
      searchTextBuilder: (row) =>
          row['name']?.toString() ?? row['package_title']?.toString() ?? '',
    );
    if (!mounted || selected == null) return;
    if (selected == -1) {
      setState(() {
        _selectedPackageIndex = null;
        _clearSelectedItemSelection();
        _itemPackagePrices.clear();
        _itemDiscounts.clear();
      });
      _recalculateTotals();
      await _saveDraft();
      return;
    }
    await _onPackageSelected(selected);
  }

  Future<void> _pickDeliveryPoint() async {
    final helper = OrderDatabaseHelper.instance;
    final directDeliveryPoints = await helper.getDeliveryPoints();
    final storeData = await helper.getStoreData();

    final mergedDeliveryPoints = <Map<String, dynamic>>[];
    final seen = <String>{};

    void addDeliveryPoint(Map<String, dynamic> raw) {
      final normalized = OrderDataNormalizer.normalizeDeliveryPoint(
        Map<String, dynamic>.from(raw),
      );
      final id = _deliveryPointIdFromMap(normalized);
      final name = _deliveryPointNameFromMap(normalized);
      if (name.isEmpty) return;

      final key = '${id.toLowerCase()}|${name.toLowerCase()}';
      if (seen.contains(key)) return;
      seen.add(key);

      normalized['store_id'] = id;
      normalized['store_name'] = name;
      normalized['display_name'] = name;
      mergedDeliveryPoints.add(normalized);
    }

    for (final row in directDeliveryPoints) {
      addDeliveryPoint(row);
    }

    for (final row in storeData) {
      if (row['stores'] is List) {
        final stores = row['stores'] as List;
        for (final store in stores) {
          if (store is Map) {
            addDeliveryPoint(Map<String, dynamic>.from(store));
          }
        }
      }
      addDeliveryPoint(row);
    }

    mergedDeliveryPoints.sort((a, b) {
      final an = _deliveryPointNameFromMap(a).toLowerCase();
      final bn = _deliveryPointNameFromMap(b).toLowerCase();
      return an.compareTo(bn);
    });

    if (mergedDeliveryPoints.isNotEmpty) {
      final selectedId =
          (_selectedDeliveryPointIndex != null &&
              _selectedDeliveryPointIndex! >= 0 &&
              _selectedDeliveryPointIndex! < _deliveryPoints.length)
          ? _deliveryPointIdFromMap(
              _deliveryPoints[_selectedDeliveryPointIndex!],
            )
          : '';

      int? refreshedSelectedIndex;
      if (selectedId.isNotEmpty) {
        final idx = mergedDeliveryPoints.indexWhere(
          (d) => _deliveryPointIdFromMap(d) == selectedId,
        );
        if (idx != -1) {
          refreshedSelectedIndex = idx;
        }
      }

      if (mounted) {
        setState(() {
          _deliveryPoints = mergedDeliveryPoints;
          _selectedDeliveryPointIndex = refreshedSelectedIndex;
        });
      }
    }

    if (_deliveryPoints.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No delivery points available. Sync data first.'),
        ),
      );
      return;
    }
    final selected = await _showSearchSelectionDialog(
      title: 'Select Via Delivery Point',
      rows: _deliveryPoints,
      selectedIndex: _selectedDeliveryPointIndex,
      labelBuilder: (row) => _deliveryPointNameFromMap(row),
      searchTextBuilder: (row) =>
          '${_deliveryPointNameFromMap(row)} ${_deliveryPointLocationFromMap(row)}',
    );
    if (!mounted || selected == null) return;
    await _onDeliveryPointSelected(selected, persistDraft: true);
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
      _currentOrderSerialNo = draft.order.orderSerialNo;
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
              d['store_id']?.toString().trim() == draftDeliveryPointId ||
              d['delivery_point_id']?.toString().trim() ==
                  draftDeliveryPointId ||
              d['id']?.toString().trim() == draftDeliveryPointId,
        );
        if (dpIndex != -1) {
          _selectedDeliveryPointIndex = dpIndex;
        }
      }

      final shipToPartyId = draft.order.shipToPartyId?.trim() ?? '';
      final deliveryPartyName = draft.order.deliveryPartyName?.trim() ?? '';
      if (shipToPartyId.isNotEmpty || deliveryPartyName.isNotEmpty) {
        _selectedShipToPartyId = shipToPartyId;
        _selectedShipToPartyName = deliveryPartyName;
        _showManualDeliveryAddressField =
            deliveryPartyName.toLowerCase() == 'unavailable party';

        final options = _buildShipToOptions();
        final idx = options.indexWhere(
          (o) =>
              (o['ship_to_party_id']?.toString().trim() ?? '') ==
                  shipToPartyId &&
              (o['delivery_party_name']?.toString().trim().toLowerCase() ??
                      '') ==
                  deliveryPartyName.toLowerCase(),
        );
        if (idx != -1) {
          _selectedShipToOptionIndex = idx;
        }
      }

      final draftVisitId = draft.order.visitId?.trim() ?? '';
      if (draftVisitId.isNotEmpty) {
        final visitIndex = _approvedVisits.indexWhere(
          (v) => (v.visitId ?? '').trim() == draftVisitId,
        );
        if (visitIndex != -1) {
          _selectedVisitIndex = visitIndex;
        }
      }

      _selectedPaymentDealId = draft.order.paymentDealId?.trim();
      _specialRemarksController.text = draft.order.orderRemarks?.trim() ?? '';
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
        _selectedVisitIndex != null &&
            _selectedVisitIndex! < _approvedVisits.length
        ? _approvedVisits[_selectedVisitIndex!]
        : null;

    return {
      'bill_to_party_id': party?['partyid']?.toString(),
      'party_name': party != null ? partyDisplay(party) : null,
      'ship_to_party_id': _selectedShipToPartyId,
      'delivery_party_name': _selectedShipToPartyName,
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
      'delivery_point_id': deliveryPoint != null
          ? _deliveryPointIdFromMap(deliveryPoint)
          : null,
      'delivery_point_name': deliveryPoint != null
          ? _deliveryPointNameFromMap(deliveryPoint)
          : null,
      'visit_id': visit?.visitId,
      'route_id': visit?.routeId,
      'delivery_address': _deliveryAddressController.text.trim(),
      'order_remarks': _specialRemarksController.text.trim(),
    };
  }

  Future<void> _showOrderRemarksDialog() async {
    final remarksController = TextEditingController(
      text: _specialRemarksController.text,
    );

    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Order Remarks'),
          content: TextField(
            controller: remarksController,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'Write remarks for this order',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(null),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(''),
              child: const Text('Clear'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(remarksController.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (!mounted || result == null) return;

    setState(() {
      _specialRemarksController.text = result;
    });
    await _saveDraft(syncItems: false);
  }

  Future<void> _saveDraft({bool syncItems = false}) async {
    if (_savingDraft) return;
    _savingDraft = true;
    try {
      final current = await DraftOrderService.instance.getCurrentDraft();
      if (current == null) return;

      _currentDraftId = current.order.id;
      _currentOrderSerialNo = current.order.orderSerialNo;
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

  Future<void> _resetWholeOrderScreen({bool showSnackBar = true}) async {
    try {
      context.read<InvoiceProvider>().reset();

      final current = await DraftOrderService.instance.getCurrentDraft();
      if (current != null) {
        await DraftOrderService.instance.resetDraft(current.order.id);
      }

      if (!mounted) return;

      setState(() {
        _selectedVisitIndex = null;
        _selectedPartyIndex = null;
        _selectedShipToOptionIndex = null;
        _selectedShipToPartyId = null;
        _selectedShipToPartyName = null;
        _showManualDeliveryAddressField = false;

        _selectedItemIndex = null;
        _selectedPackageIndex = null;
        _selectedDeliveryPointIndex = null;
        _selectedAgencyIndex = null;

        _selectedPaymentDealId = null;
        _selectedItemPrice = '';
        _paymentMethods = [];
        _alreadyAddedItems = [];

        _itemPackagePrices.clear();
        _itemDiscounts.clear();
        _packages = _filterPackagesForParty(
          allPackages: _allPackages,
          partyId: '',
        );
      });

      _qtyController.clear();
      _specialRemarksController.clear();
      _specialPriceController.clear();
      _deliveryAddressController.clear();

      _recalculateTotals();
      await _saveDraft(syncItems: true);

      if (!mounted || !showSnackBar) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Order screen reset')));
    } catch (e) {
      if (!mounted || !showSnackBar) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Reset failed: $e')));
    }
  }

  Future<bool> _handleBackNavigation() async {
    if (_isExitingScreen) return true;
    _isExitingScreen = true;
    try {
      await _resetWholeOrderScreen(showSnackBar: false);
      return true;
    } finally {
      _isExitingScreen = false;
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

    // Validation: ship-to selection
    if (!_isShipToSelected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select Ship To before finalizing'),
        ),
      );
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

    // Validation: via / delivery point selection
    if (_selectedDeliveryPointIndex == null ||
        _selectedDeliveryPointIndex! < 0 ||
        _selectedDeliveryPointIndex! >= _deliveryPoints.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select Via / Delivery Point before finalizing'),
        ),
      );
      return;
    }

    // Validation: remarks required for unavailable party flow
    if (_showManualDeliveryAddressField &&
        _deliveryAddressController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter Delivery Address / Remarks'),
        ),
      );
      return;
    }

    // Validation: visit selection
    if (_selectedVisitIndex == null ||
        _selectedVisitIndex! < 0 ||
        _selectedVisitIndex! >= _approvedVisits.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a visit before finalizing'),
        ),
      );
      return;
    }

    await _saveDraft(syncItems: true);

    if (_currentDraftId == null) {
      final current = await DraftOrderService.instance.getCurrentDraft();
      _currentDraftId = current?.order.id;
      _currentOrderSerialNo = current?.order.orderSerialNo;
      _currentLocalOrderId = current?.order.localOrderId;
    }

    if (_currentDraftId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not prepare local order record.')),
      );
      return;
    }

    final finalizedLocalDraft = await DraftOrderService.instance.finalizeDraft(
      _currentDraftId!,
    );
    if (finalizedLocalDraft == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Failed to save finalized order locally.'),
        ),
      );
      return;
    }

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

      const dummyLocation = '24.8607,67.0011';

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
        deliveryParty: (_selectedShipToPartyName ?? '').trim(),
        advancePaymentDeal: _currentPaymentDealForOrder,
        deliveryPartyRemarks: _showManualDeliveryAddressField
            ? _deliveryAddressController.text.trim()
            : '',
        deliveryPointRemarks: '',
        visitId: _selectedApprovedVisit?.visitId ?? '',
        cityId: (_selectedApprovedVisit?.cityIds ?? '').trim(),
        location: dummyLocation,
        routeId: _selectedApprovedVisit?.routeId ?? '',
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
        // Attendance intentionally skipped for now (as requested).

        provider.finalize();
        await DraftOrderService.instance.createNewDraft();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${uploadResult.message} (saved locally + uploaded)'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${uploadResult.message} (saved locally, upload failed)',
            ),
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

    // Price stays package-driven; item-level manual editing is disabled.
    final price = packagePrice;

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

    return WillPopScope(
      onWillPop: _handleBackNavigation,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F7FC),
        appBar: AppBar(
          backgroundColor: primary,
          foregroundColor: Colors.white,
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
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
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
                  if (!_fetchingFromApi &&
                      (_items.isEmpty || _packages.isEmpty))
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
      ),
    );
  }

  Widget _buildTopSection(Color primary) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, primary.withValues(alpha: 0.9)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _buildFieldRow(
            'Visit:',
            DropdownButton<int>(
              value: _approvedVisits.isEmpty ? null : _selectedVisitIndex,
              hint: const Text(
                'Select Visit',
                style: TextStyle(color: Colors.white),
              ),
              isExpanded: true,
              dropdownColor: primary,
              style: const TextStyle(color: Colors.white),
              underline: Container(),
              items: _approvedVisits
                  .asMap()
                  .entries
                  .map(
                    (e) => DropdownMenuItem(
                      value: e.key,
                      child: Text(_visitRouteLabel(e.value)),
                    ),
                  )
                  .toList(),
              onChanged: _approvedVisits.isEmpty
                  ? null
                  : (val) async {
                      setState(() => _selectedVisitIndex = val);
                      await _syncVisitedPartiesForSelectedVisit();

                      final selectedVisit = _selectedApprovedVisit;

                      DraftOrderProvider? draftProvider;
                      try {
                        draftProvider = Provider.of<DraftOrderProvider>(
                          context,
                          listen: false,
                        );
                      } catch (_) {
                        draftProvider = null;
                      }
                      if (selectedVisit != null && draftProvider != null) {
                        await draftProvider.updateVisit(
                          selectedVisit.visitId,
                          selectedVisit.routeId,
                        );
                      }

                      _recalculateTotals();
                      await _saveDraft();
                    },
            ),
          ),
          if (_approvedVisits.isEmpty)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () async {
                  await _loadApprovedVisits();
                  if (!mounted) return;
                  if (_approvedVisits.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'No approved visits found. Please sync visits/API.',
                        ),
                      ),
                    );
                  }
                },
                child: const Text(
                  'Refresh Visits',
                  style: TextStyle(color: Colors.white),
                ),
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
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
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
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
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
              onTap: _pickShipToDeliveryAddress,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        _shipToDisplayLabel,
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
          if (_showManualDeliveryAddressField) ...[
            const SizedBox(height: 8),
            _buildFieldRow(
              'Remarks:',
              TextField(
                controller: _deliveryAddressController,
                minLines: 2,
                maxLines: 4,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Enter delivery address / remarks',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.7)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.18),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (_) {
                  _saveDraft(syncItems: false);
                },
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (_isShipToSelected)
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
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selectedPackageIndex != null &&
                                  _selectedPackageIndex! < _packages.length
                              ? packageDisplay(
                                  _packages[_selectedPackageIndex!],
                                )
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
            )
          else
            _buildFieldRow(
              'Package :',
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Text(
                  'Select Ship To first',
                  style: TextStyle(color: Colors.white70),
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
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
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
                color: Colors.orange.withValues(alpha: 0.32),
                borderRadius: BorderRadius.circular(10),
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
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
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
                      border: Border.all(color: const Color(0xFFD1D9E6)),
                      borderRadius: BorderRadius.circular(10),
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
                      borderSide: const BorderSide(color: Color(0xFFD1D9E6)),
                      borderRadius: BorderRadius.circular(10),
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
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: const Text(
                  'ADD',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(10),
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
                color: primary.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                'Order ID: $_currentOrderIdForDisplay',
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
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: const Text(
              'No items added yet',
              style: TextStyle(color: Colors.grey, fontSize: 15),
              textAlign: TextAlign.center,
            ),
          );
        }

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: primary.withValues(alpha: 0.25)),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
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
                  margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: primary.withValues(alpha: 0.25)),
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
                              color: primary.withValues(alpha: 0.15),
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
              const SizedBox(height: 8),
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
          margin: const EdgeInsets.only(bottom: 10),
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
                    topLeft: Radius.circular(12),
                    topRight: Radius.circular(12),
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
                  border: Border.all(color: primary.withValues(alpha: 0.3)),
                  borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    border: Border.all(color: const Color(0xFFD1D9E6)),
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
                  onPressed: _showOrderRemarksDialog,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.all(12),
                    side: const BorderSide(color: Color(0xFFD1D9E6)),
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
          if (_specialRemarksController.text.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF4FF),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFCBDCFB)),
              ),
              child: Text(
                'Remarks: ${_specialRemarksController.text.trim()}',
                style: const TextStyle(
                  color: Color(0xFF1E3A8A),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
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
                    color: const Color(0xFFF8FAFC),
                    border: Border.all(color: const Color(0xFFD1D9E6)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: InkWell(
                    onTap: _pickDeliveryPoint,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _selectedDeliveryPointIndex != null &&
                                      _selectedDeliveryPointIndex! <
                                          _deliveryPoints.length
                                  ? _deliveryPointNameFromMap(
                                          _deliveryPoints[_selectedDeliveryPointIndex!],
                                        ).isNotEmpty
                                        ? _deliveryPointNameFromMap(
                                            _deliveryPoints[_selectedDeliveryPointIndex!],
                                          )
                                        : deliveryPointDisplay(
                                            _deliveryPoints[_selectedDeliveryPointIndex!],
                                          )
                                  : 'Select Via Delivery Point',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.search, size: 18),
                        ],
                      ),
                    ),
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
                    await _resetWholeOrderScreen();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
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
                      borderRadius: BorderRadius.circular(10),
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
