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
import '../services/order_package_pricing_service.dart';
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
  static const bool _uploadOnFinalize = false;

  final TextEditingController _qtyController = TextEditingController();
  final TextEditingController _specialRemarksController =
      TextEditingController();
  final TextEditingController _specialPriceController = TextEditingController();
  final TextEditingController _deliveryAddressController =
      TextEditingController();

  // Per-item inline qty editing controllers (keyed by InvoiceItem.id)
  final Map<String, TextEditingController> _itemQtyControllers = {};

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
  final Map<String, PackagePricingResult> _itemPricingResults = {};

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

  String get _paymentDealLookupPartyId {
    final shipToId = (_selectedShipToPartyId ?? '').trim();
    if (shipToId.isNotEmpty && shipToId != '0') {
      return shipToId;
    }
    return _selectedPartyId;
  }

  bool get _isPaymentDealRequiredForSelectedPackage {
    return OrderPackagePricingService.isPaymentDealRequired(_selectedPackage);
  }

  bool get _isPaymentDealStateResolved {
    if (!_isPaymentDealRequiredForSelectedPackage) return true;
    if (_paymentMethods.isEmpty) return false;
    final selected = (_selectedPaymentDealId ?? '').trim();
    if (selected.isEmpty) return false;
    return _paymentMethods.any(
      (m) => (m.id ?? '').toString().trim() == selected,
    );
  }

  Map<String, dynamic>? _findItemMapById(String id) {
    for (final item in _items) {
      final itemId = OrderPackagePricingService.itemIdFromMap(item);
      if (itemId == id) return item;
    }
    return null;
  }

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
    // CRITICAL: Android expects numeric DB ID, NOT UUID
    // 1. Prefer orderSerialNo (numeric local DB id, matches Android getId())
    if (_currentOrderSerialNo != null) {
      return _currentOrderSerialNo.toString();
    }
    // 2. Fallback to draftId if available
    if (_currentDraftId != null) return _currentDraftId.toString();
    // 3. Last resort: timestamp (should not reach here if draft is active)
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
        'delivery_party_name': 'Direct to Party (Bilty)',
        'display': 'Direct to Party (Bilty) _ 0',
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

      if (shipToChanged) {
        _selectedPaymentDealId = null;
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

    await _loadPaymentMethodsForCurrentContext();

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
      final alreadyAddedFuture = AlreadyAddedItemService.instance
          .getAlreadyAddedItems();

      final alreadyAdded = await alreadyAddedFuture;

      final filteredPackages = _filterPackagesForParty(
        allPackages: _allPackages,
        partyId: partyId,
      );

      if (!mounted) return;

      setState(() {
        _alreadyAddedItems = alreadyAdded;
        _packages = filteredPackages;
      });

      _ensurePackageSelectionStillValid();
      await _refreshSelectedPackagePricingIfNeeded();
      await _loadPaymentMethodsForCurrentContext();
    } catch (e) {
      debugPrint('[OrderAdd] Failed party dependent reload: $e');
    } finally {
      _loadingPartyDependencies = false;
    }
  }

  Future<void> _loadPaymentMethodsForCurrentContext() async {
    final package = _selectedPackage;
    if (!OrderPackagePricingService.isPaymentDealRequired(package)) {
      if (mounted) {
        setState(() {
          _paymentMethods = [];
          _selectedPaymentDealId = null;
        });
      }
      debugPrint('[OrderAdd] scheme!=2 payment deal not required, state reset');
      return;
    }

    final lookupPartyId = _paymentDealLookupPartyId;
    if (lookupPartyId.isEmpty) {
      if (mounted) {
        setState(() {
          _paymentMethods = [];
          _selectedPaymentDealId = null;
        });
      }
      debugPrint('[OrderAdd] payment deal required but lookup party is empty');
      return;
    }

    final methods = await PaymentDealService.instance.getPaymentMethods(
      lookupPartyId,
    );
    if (!mounted) return;

    setState(() {
      _paymentMethods = methods;
      final hasExisting = methods.any(
        (m) => (m.id ?? '').toString().trim() == (_selectedPaymentDealId ?? ''),
      );
      if (!hasExisting) {
        _selectedPaymentDealId = methods.isNotEmpty
            ? methods.first.id?.toString().trim()
            : null;
      }
    });

    debugPrint(
      '[OrderAdd] payment deal load required=true lookupParty=$lookupPartyId methods=${methods.length} selected=$_selectedPaymentDealId',
    );
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
      _itemPricingResults.clear();
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
      _itemPricingResults.clear();
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
      _itemPricingResults.clear();
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
      _itemPricingResults.clear();
      return;
    }

    final packageId =
        package['packageid']?.toString() ?? package['id']?.toString() ?? '';
    if (packageId.isEmpty) {
      _itemPackagePrices.clear();
      _itemDiscounts.clear();
      _itemPricingResults.clear();
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

    if (!_ensurePaymentDealResolvedForItemEntry()) {
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
    final result = _resolveItemPricing(item: selectedItem, quantity: 1);
    final price = result.finalPrice;
    final discount = result.discountPercent;

    if (!result.allowed) {
      _selectedItemPrice = '';
      _specialPriceController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.reason ?? 'Item Not Allowed'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Android parity: validate price (reject "no price" items)
    if (price <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Item Not Allowed'),
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
            'Rs : ${price.toStringAsFixed(2)} _ Discount : ${discount.toStringAsFixed(1)}%';
      } else {
        _selectedItemPrice = 'Rs : ${price.toStringAsFixed(2)}';
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
        _itemPricingResults.clear();
        _selectedPaymentDealId = null;
        _paymentMethods = [];
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
      setState(() {
        _selectedPackageIndex = null;
        _selectedPaymentDealId = null;
        _paymentMethods = [];
        _itemPackagePrices.clear();
        _itemDiscounts.clear();
        _itemPricingResults.clear();
        _clearSelectedItemSelection();
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              reason.isEmpty
                  ? 'Package not allowed to you, Please select another package'
                  : reason,
            ),
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

    await _loadPaymentMethodsForCurrentContext();

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

  Future<void> _saveDraft({bool syncItems = false}) async {
    if (_savingDraft) return;
    _savingDraft = true;
    try {
      final current = await DraftOrderService.instance.getCurrentDraft();
      if (current == null) {
        debugPrint('[OrderAdd] _saveDraft: No draft found!');
        return;
      }

      _currentDraftId = current.order.id;
      _currentOrderSerialNo = current.order.orderSerialNo;
      _currentLocalOrderId = current.order.localOrderId;

      final header = _buildCurrentDraftOrder();

      // Always update header
      await DraftOrderService.instance.updateDraftHeader(
        _currentDraftId!,
        header,
      );

      // CRITICAL: Only clear line items, never clear header (resetDraft wipes party/package).
      // Full and incremental sync both replace items only so draft header is preserved.
      if (syncItems) {
        debugPrint('[OrderAdd] _saveDraft: Full sync (syncItems=true)');
      } else {
        debugPrint('[OrderAdd] _saveDraft: Incremental sync (syncItems=false)');
      }
      await DraftOrderService.instance.deleteAllLineItems(_currentDraftId!);

      // Insert current items from InvoiceProvider into database
      final provider = context.read<InvoiceProvider>();
      debugPrint(
        '[OrderAdd] _saveDraft: Inserting ${provider.items.length} items into draft $_currentDraftId',
      );

      for (final item in provider.items) {
        debugPrint(
          '[OrderAdd] _saveDraft: Inserting item: ${item.name} x${item.quantity}',
        );
        await DraftOrderService.instance.insertLineItem(
          draftOrderId: _currentDraftId!,
          itemId: item.id,
          itemName: item.name,
          quantity: item.quantity,
          unitPrice: item.price,
          discountPercent: item.discountPercent,
          specialRemarks:
              null, // Per-item remarks (currently not supported in UI)
        );
      }
      debugPrint(
        '[OrderAdd] _saveDraft: Successfully saved draft with ${provider.items.length} items',
      );
    } catch (e) {
      debugPrint('[OrderAdd] _saveDraft: ERROR - $e');
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

  PackagePricingResult _resolveItemPricing({
    required Map<String, dynamic> item,
    required int quantity,
    List<InvoiceItem>? cartItems,
  }) {
    final provider = context.read<InvoiceProvider>();
    final result = OrderPackagePricingService.resolveItemPricing(
      package: _selectedPackage,
      item: item,
      quantity: quantity,
      packageDetails1: _packageDetails1,
      packageDetails2: _packageDetails2,
      cartItems: cartItems ?? provider.items,
    );
    final id = OrderPackagePricingService.itemIdFromMap(item);
    if (id.isNotEmpty) {
      _itemPricingResults[id] = result;
    }
    return result;
  }

  bool _ensurePaymentDealResolvedForItemEntry() {
    if (!_isPaymentDealRequiredForSelectedPackage) {
      return true;
    }
    if (_paymentMethods.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No payment deal available for selected party/ship-to'),
          backgroundColor: Colors.orange,
        ),
      );
      return false;
    }
    if (!_isPaymentDealStateResolved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please select a valid payment deal first'),
          backgroundColor: Colors.orange,
        ),
      );
      return false;
    }
    return true;
  }

  Future<void> _recalculateGroupwiseCartItems({String reason = ''}) async {
    final provider = context.read<InvoiceProvider>();
    if (provider.items.isEmpty) return;

    final itemById = <String, Map<String, dynamic>>{};
    for (final item in _items) {
      final id = OrderPackagePricingService.itemIdFromMap(item);
      if (id.isNotEmpty) {
        itemById[id] = item;
      }
    }

    var working = provider.items.map((e) => e.copyWith()).toList();
    for (var i = 0; i < 2; i++) {
      final next = <InvoiceItem>[];
      for (final cart in working) {
        final itemMap = itemById[cart.id];
        if (itemMap == null) {
          next.add(cart);
          continue;
        }
        final pricing = OrderPackagePricingService.resolveItemPricing(
          package: _selectedPackage,
          item: itemMap,
          quantity: cart.quantity,
          packageDetails1: _packageDetails1,
          packageDetails2: _packageDetails2,
          cartItems: working,
        );
        final updated = pricing.allowed
            ? cart.copyWith(
                price: pricing.finalPrice,
                discountPercent: pricing.discountPercent,
              )
            : cart;
        next.add(updated);
      }
      working = next;
    }

    provider.replaceItems(working);
    debugPrint('[OrderAdd] groupwise recalculation applied reason=$reason');
  }

  // Keep package change fast: reset cache and compute only currently selected item.
  Future<void> _calculateItemPricesForPackage(String packageId) async {
    _itemPackagePrices.clear();
    _itemDiscounts.clear();
    _itemPricingResults.clear();

    final selectedPackage = _packages.firstWhere(
      (p) =>
          (p['packageid']?.toString().trim() ?? p['id']?.toString().trim()) ==
          packageId,
      orElse: () => _selectedPackage ?? <String, dynamic>{},
    );

    if (_selectedItemIndex != null &&
        _selectedItemIndex! >= 0 &&
        _selectedItemIndex! < _items.length) {
      final item = _items[_selectedItemIndex!];
      final result = _resolveItemPricing(item: item, quantity: 1);
      final itemId = OrderPackagePricingService.itemIdFromMap(item);
      if (itemId.isNotEmpty && result.allowed) {
        _itemPackagePrices[itemId] = result.finalPrice;
        _itemDiscounts[itemId] = result.discountPercent;
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  // Get package-calculated price for item
  double _getItemPackagePrice(Map<String, dynamic> item) {
    final itemId = OrderPackagePricingService.itemIdFromMap(item);
    final result = _resolveItemPricing(item: item, quantity: 1);
    if (itemId.isNotEmpty && result.allowed) {
      _itemPackagePrices[itemId] = result.finalPrice;
      _itemDiscounts[itemId] = result.discountPercent;
      return result.finalPrice;
    }
    return 0;
  }

  // Get package discount for item
  double _getItemDiscount(Map<String, dynamic> item) {
    final itemId = OrderPackagePricingService.itemIdFromMap(item);
    final result = _resolveItemPricing(item: item, quantity: 1);
    if (itemId.isNotEmpty && result.allowed) {
      _itemPackagePrices[itemId] = result.finalPrice;
      _itemDiscounts[itemId] = result.discountPercent;
      return result.discountPercent;
    }
    return 0;
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

    final selectedParty = _parties[_selectedPartyIndex!];
    final selectedPackage = _packages[_selectedPackageIndex!];

    if (OrderPackagePricingService.isPaymentDealRequired(selectedPackage) &&
        !_isPaymentDealStateResolved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please resolve payment deal before finalizing order'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Android parity: validate minimum order amount
    if (!PackageEligibilityChecker.meetsMinimumAmount(
      package: selectedPackage,
      orderTotal: provider.netAmount,
    )) {
      final minAmount = selectedPackage['minorderamount']?.toString() ?? '0';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Add More Amount (Min: $minAmount)'),
          backgroundColor: Colors.red,
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

    final draftId = finalizedLocalDraft.order.id;

    // 1) Local save FIRST (Android parity: save to bookings before upload)
    int? bookingId;
    try {
      bookingId = await DraftOrderService.instance
          .saveFinalizedOrderToBookings(draftId);
      debugPrint(
        '[OrderAdd] saveFinalizedOrderToBookings(draftId=$draftId) -> bookingId=$bookingId',
      );
      if (bookingId == null) {
        debugPrint(
          '[OrderAdd] WARNING: saveFinalizedOrderToBookings returned null (draft may not be finalized in DB)',
        );
      }
    } catch (e) {
      debugPrint('[OrderAdd] saveFinalizedOrderToBookings ERROR: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Local save failed: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
      return;
    }

    if (!_uploadOnFinalize) {
      debugPrint('[OrderAdd] Upload on finalize disabled; local save only.');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order saved locally. Upload from My Orders.'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 3),
          ),
        );
      }

      await DraftOrderService.instance.createNewDraft();
      if (mounted) {
        await context.read<DraftOrderProvider>().loadDraft();
        Navigator.pop(context);
      }
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
      final invDate = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);
      final orderId = _currentOrderIdForUpload;

        // Keep token values in the same spirit as old Android createJson.
        // Prefer IDs when present, otherwise use saved display names.
        final partyToken =
          (finalizedLocalDraft.order.billToPartyId ?? '').trim().isNotEmpty
          ? (finalizedLocalDraft.order.billToPartyId ?? '').trim()
          : (finalizedLocalDraft.order.partyName ?? '').trim();
        final packageToken =
          (finalizedLocalDraft.order.packageId ?? '').trim().isNotEmpty
          ? (finalizedLocalDraft.order.packageId ?? '').trim()
          : (finalizedLocalDraft.order.packageName ?? '').trim();
        final deliveryPartyToken =
          (finalizedLocalDraft.order.shipToPartyId ?? '').trim().isNotEmpty
          ? (finalizedLocalDraft.order.shipToPartyId ?? '').trim()
          : (finalizedLocalDraft.order.deliveryPartyName ?? '').trim();

      const dummyLocation = '0,0';

      final orderHeader = OrderUploadFormatter.formatOrderHeader(
        orderId: orderId,
        partyName: partyToken,
        packageName: packageToken,
        deliveryPoint:
            _selectedDeliveryPointIndex != null &&
                _selectedDeliveryPointIndex! < _deliveryPoints.length
            ? _deliveryPointNameFromMap(
                _deliveryPoints[_selectedDeliveryPointIndex!],
              )
            : (finalizedLocalDraft.order.deliveryPointName ?? ''),
        orderBy: _userId,
        timestamp: invDate,
        // Use persisted draft remarks to mirror Android createJson(cartOrder).
        remarks: (finalizedLocalDraft.order.orderRemarks ?? '').trim(),
        grossTotal: provider.grossAmount.toStringAsFixed(2),
        discount: provider.totalDiscount.toStringAsFixed(2),
        netTotal: provider.netAmount.toStringAsFixed(2),
        deliveryParty: deliveryPartyToken,
        advancePaymentDeal: _currentPaymentDealForOrder,
        // Only use manual address if party is "unavailable"
        deliveryPartyRemarks: _showManualDeliveryAddressField
            ? _deliveryAddressController.text.trim()
            : '',
        deliveryPointRemarks: '',
        visitId: _selectedApprovedVisit?.visitId ??
            finalizedLocalDraft.order.visitId ??
            '',
        cityId: (_selectedApprovedVisit?.cityIds ?? '').trim(),
        location: dummyLocation,
        routeId: _selectedApprovedVisit?.routeId ??
            finalizedLocalDraft.order.routeId ??
            '',
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
      // CRITICAL: Get saved items from DB to include special_remarks and special_price
      // These were stored during draft save but are not in the InvoiceItem model
      List<Map<String, dynamic>> itemMaps = [];
      final savedDraft = await DraftOrderService.instance.getDraftById(
        finalizedLocalDraft.order.id,
      );
      if (savedDraft != null) {
        itemMaps = savedDraft.items
            .map(
              (dbItem) => {
                'name': dbItem.itemName,
                'price': dbItem.unitPrice.toString(),
                'quantity': dbItem.quantity.toString(),
                'discount_percent': dbItem.discountPercent.toString(),
                'total':
                    (dbItem.unitPrice * dbItem.quantity -
                            (dbItem.unitPrice *
                                dbItem.quantity *
                                (dbItem.discountPercent / 100)))
                        .toString(),
                'remarks': '',
                'direction_store': '',
                'special_remarks': dbItem.specialRemarks ?? '',
                'special_price': '0',
              },
            )
            .toList();
      } else {
        // Fallback: use InvoiceItem if DB query fails (should not happen)
        itemMaps = provider.items
            .map(
              (item) => {
                'name': item.name,
                'price': item.price.toString(),
                'quantity': item.quantity.toString(),
                'discount_percent': item.discountPercent.toString(),
                'total': item.total.toString(),
                'remarks': '',
                'direction_store': '',
                'special_remarks': '',
                'special_price': '0',
              },
            )
            .toList();
      }

      final orderItems = OrderUploadFormatter.formatOrderItems(
        items: itemMaps,
        orderId: orderId,
      );

      // Debug: token-wise header dump for SQL parity checks.
      final headerTokens = orderHeader.split('_');
      if (kDebugMode) {
        debugPrint('[OrderAdd] header token count=${headerTokens.length}');
        final labels = <String>[
          'localinvno/orderid',
          'partyid',
          'package_id',
          'deliverypoint',
          'orderby/employeeid',
          'invdate',
          'remarks',
          'gross',
          'discount',
          'net',
          'delivery_party',
          'deal_id',
          'delivery_party_remarks',
          'delivery_point_remarks',
          'visit_id',
          'city_id',
          'location',
          'route_id',
          'goodsagency_id',
          'goodsagency_name',
        ];

        for (var i = 0; i < labels.length; i++) {
          final value = i < headerTokens.length ? headerTokens[i] : '<missing>';
          debugPrint('[OrderAdd][HDR][$i] ${labels[i]} = $value');
        }
      }

      // Android parity: send order using postOrderZ endpoint
      final response = await ApiService.postOrder(
        orderHeader: orderHeader,
        orderItems: orderItems,
      );

      debugPrint('[OrderAdd] Upload response: $response');

      // Convert Map response to OrderUploadResult
      final status = response['status']?.toString().toLowerCase() ?? '';
      debugPrint('[OrderAdd] Response status: "$status"');

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

      debugPrint('[OrderAdd] uploadResult.success=${uploadResult.success}');

      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
      debugPrint('[OrderAdd] Closed loading dialog');

      if (uploadResult.success) {
        debugPrint(
          '[OrderAdd] Upload successful! Starting post-upload flow...',
        );

        // Already saved to bookings before upload; now mark as uploaded
        if (bookingId != null) {
          await DraftOrderService.instance.markBookingUploaded(bookingId);
          debugPrint('[OrderAdd] markBookingUploaded($bookingId) completed');
        }

        debugPrint('[OrderAdd] Calling markUploadSuccess for draft $draftId');
        await DraftOrderService.instance.markUploadSuccess(
          draftId,
          clearItems: true,
        );
        debugPrint('[OrderAdd] markUploadSuccess completed');

        // New blank draft and refresh provider
        debugPrint('[OrderAdd] Creating new draft');
        await DraftOrderService.instance.createNewDraft();
        if (mounted) await context.read<DraftOrderProvider>().loadDraft();
        debugPrint('[OrderAdd] New draft created');

        const snackContent =
            'Order uploaded successfully! ✅ (saved locally + uploaded)';
        debugPrint('[OrderAdd] Showing success snackbar: $snackContent');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(snackContent),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 3),
            ),
          );
        }

        debugPrint(
          '[OrderAdd] Calling Navigator.pop(context) to close Order Add screen',
        );
        if (mounted) Navigator.pop(context);
        debugPrint('[OrderAdd] Upload flow completed successfully!');
      } else {
        debugPrint(
          '[OrderAdd] Upload FAILED with message: ${uploadResult.message}',
        );
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
      debugPrint('[OrderAdd] EXCEPTION in finalize/upload flow: $e');
      if (!mounted) return;
      Navigator.pop(context); // Close loading dialog
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error during finalization: $e'),
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
    for (final c in _itemQtyControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _qtyCtrlFor(String itemId, int currentQty) {
    return _itemQtyControllers.putIfAbsent(
      itemId,
      () => TextEditingController(text: currentQty.toString()),
    );
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

    if (!_ensurePaymentDealResolvedForItemEntry()) {
      return;
    }

    final qty = int.tryParse(_qtyController.text.trim());
    if (qty == null || qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter valid quantity')),
      );
      return;
    }

    final itemMap = _items[_selectedItemIndex!];
    final name = itemDisplay(itemMap);
    final pricing = _resolveItemPricing(item: itemMap, quantity: qty);

    if (!pricing.allowed) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(pricing.reason ?? 'Item Not Allowed'),
          backgroundColor: Colors.red,
        ),
      );
      _selectedItemPrice = '';
      return;
    }

    var price = pricing.finalPrice;
    final discount = pricing.discountPercent;

    final specialPrice = OrderPackagePricingService.toDoubleSafe(
      _specialPriceController.text.trim(),
    );
    if (specialPrice != null && specialPrice > 0) {
      price = specialPrice;
      debugPrint(
        '[OrderAdd] special price override applied item=$name price=$price',
      );
    }

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
        const SnackBar(
          content: Text('Item Not Allowed'),
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
      debugPrint('[OrderAdd] duplicate blocked item=$itemId');
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
      quantity: qty,
      discountPercent: discount,
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
    await _recalculateGroupwiseCartItems(reason: 'add');
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
    await _recalculateGroupwiseCartItems(reason: 'delete');
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
                  _buildOrderDetailsSection(primary),
                  _buildTopSection(primary),
                  _buildItemEntrySection(primary),
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
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.tune, color: Colors.white70, size: 13),
              const SizedBox(width: 5),
              Text(
                'ORDER CONFIGURATION',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
                  borderRadius: BorderRadius.circular(10),
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
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 100,
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
    final itemEntryBlocked =
        _isPaymentDealRequiredForSelectedPackage &&
        !_isPaymentDealStateResolved;

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
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(Icons.add_shopping_cart, size: 14, color: primary),
                const SizedBox(width: 6),
                Text(
                  'ADD ITEM',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: primary,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: InkWell(
                  onTap: (_items.isEmpty || itemEntryBlocked)
                      ? null
                      : _pickItem,
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
                                    : (itemEntryBlocked
                                          ? 'Select payment deal first'
                                          : (_items.isEmpty
                                                ? 'No items available'
                                                : 'Search Item')),
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
                onPressed: itemEntryBlocked
                    ? null
                    : () async {
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
          if (itemEntryBlocked) ...[
            const SizedBox(height: 8),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Payment deal is required before adding items',
                style: TextStyle(color: Colors.orange, fontSize: 12),
              ),
            ),
          ],
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
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.today, color: Colors.white70, size: 14),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      _fixedOrderDate,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: primary.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.receipt, color: Colors.white70, size: 14),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      'Order #$_currentOrderIdForDisplay',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
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
          clipBehavior: Clip.antiAlias,
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
                        child: SizedBox(
                          height: 30,
                          child: TextField(
                            controller: _qtyCtrlFor(item.id, item.quantity),
                            keyboardType: TextInputType.number,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 4,
                              ),
                              isDense: true,
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(color: primary),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(4),
                                borderSide: BorderSide(
                                  color: primary,
                                  width: 2,
                                ),
                              ),
                              filled: true,
                              fillColor: primary.withValues(alpha: 0.12),
                            ),
                            onSubmitted: (val) async {
                              final newQty = int.tryParse(val);
                              if (newQty != null && newQty > 0) {
                                provider.updateItemQuantity(item.id, newQty);
                                await _recalculateGroupwiseCartItems(
                                  reason: 'qty_edit',
                                );
                                _recalculateTotals();
                                await _saveDraft(syncItems: true);
                              } else {
                                _itemQtyControllers[item.id]?.text = item
                                    .quantity
                                    .toString();
                              }
                            },
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
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(12)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                decoration: BoxDecoration(color: primary),
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
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      provider.grossAmount.toStringAsFixed(1),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      '-${provider.totalDiscount.toStringAsFixed(1)}',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.red,
                      ),
                    ),
                    Text(
                      'Rs\u00A0${provider.netAmount.toStringAsFixed(0)}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF16A34A),
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
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.person_outline,
                size: 16,
                color: Color(0xFF6B7280),
              ),
              const SizedBox(width: 6),
              const Text(
                'Agent:',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF6B7280),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFF1F5F9),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _userId,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Order Remarks',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _specialRemarksController,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Order Remarks (optional)',
              prefixIcon: const Icon(Icons.notes_outlined, size: 18),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              isDense: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Color(0xFFD1D9E6)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: Color(0xFF2563EB),
                  width: 2,
                ),
              ),
            ),
            onChanged: (_) => setState(() {}),
            onEditingComplete: () => _saveDraft(syncItems: false),
          ),
          const SizedBox(height: 12),
          const Text(
            'Via / Delivery Point',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF6B7280),
            ),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              border: Border.all(color: const Color(0xFFD1D9E6)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: InkWell(
              onTap: _pickDeliveryPoint,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    const Icon(
                      Icons.local_shipping,
                      size: 16,
                      color: Color(0xFF6B7280),
                    ),
                    const SizedBox(width: 8),
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
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    await _resetWholeOrderScreen();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red, width: 1.5),
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
                    backgroundColor: const Color(0xFF16A34A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.save_outlined, size: 18),
                      SizedBox(width: 6),
                      Text(
                        'SAVE OFFLINE',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
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
