class OrderDataNormalizer {
  OrderDataNormalizer._();

  static const List<String> _itemIdKeys = ['bookid', 'item_id', 'itemid', 'id'];

  static const List<String> _itemNameKeys = [
    'bookname',
    'name',
    'itemname',
    'ItemName',
    'description',
    'title',
  ];

  static const List<String> _itemCodeKeys = [
    'bookcode',
    'code',
    'item_code',
    'itemcode',
  ];

  static const List<String> _itemPriceKeys = [
    'price',
    'Price',
    'rate',
    'Rate',
    'sale_price',
    'allprices',
    'all_price',
  ];

  static const List<String> _packageIdKeys = ['package_id', 'id', 'PackageID'];

  static const List<String> _packageNameKeys = [
    'package_title',
    'name',
    'package_name',
    'PackageName',
    'title',
  ];

  static const List<String> _partyNameKeys = [
    'name',
    'partyname',
    'PartyName',
    'party_name',
    'title',
  ];

  static const List<String> _agencyNameKeys = [
    'name',
    'agency_name',
    'AgencyName',
    'goods_agency',
    'title',
  ];

  static const List<String> _deliveryNameKeys = [
    'name',
    'store_name',
    'StoreName',
    'point',
    'title',
  ];

  static String _stringFromKeys(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;
      final str = value.toString().trim();
      if (str.isNotEmpty) return str;
    }
    return '';
  }

  static double _doubleFromKeys(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;
      if (value is num) return value.toDouble();
      final parsed = double.tryParse(value.toString().trim());
      if (parsed != null) return parsed;
    }
    return 0;
  }

  static Map<String, dynamic> normalizeItem(Map<String, dynamic> map) {
    final id = _stringFromKeys(map, _itemIdKeys);
    final name = _stringFromKeys(map, _itemNameKeys);
    final code = _stringFromKeys(map, _itemCodeKeys);
    final price = _doubleFromKeys(map, _itemPriceKeys);
    final fallbackId =
        '${name.isNotEmpty ? name : 'item'}_${code.isNotEmpty ? code : 'na'}';

    final normalized = Map<String, dynamic>.from(map);
    normalized['id'] = id.isNotEmpty ? id : fallbackId;
    normalized['item_id'] = normalized['id'];
    normalized['bookid'] = normalized['id']; // Android key
    normalized['name'] = name;
    normalized['itemname'] = name;
    normalized['bookname'] = name; // Android key
    normalized['code'] = code;
    normalized['bookcode'] = code;
    normalized['item_code'] = code;
    normalized['price'] = price;
    normalized['allprices'] =
        map['allprices']?.toString() ?? price.toString(); // Android key
    normalized['display_name'] = code.isNotEmpty ? '$name ($code)' : name;

    // Preserve Android-specific fields
    normalized['group_id'] =
        map['group_id']?.toString() ?? map['groupid']?.toString() ?? '';
    normalized['category'] = map['category']?.toString() ?? '';
    normalized['unit'] = map['unit']?.toString() ?? '';

    return normalized;
  }

  static Map<String, dynamic> normalizePackage(Map<String, dynamic> map) {
    final id = _stringFromKeys(map, _packageIdKeys);
    final name = _stringFromKeys(map, _packageNameKeys);
    final normalized = Map<String, dynamic>.from(map);
    normalized['id'] = id;
    normalized['package_id'] = id;
    normalized['name'] = name;
    normalized['package_name'] = name;
    normalized['package_title'] = name; // Android key
    normalized['display_name'] = name;

    // Android package eligibility fields
    normalized['scheme'] = map['scheme']?.toString() ?? '';
    normalized['parties_allowed'] = map['parties_allowed']?.toString() ?? '';
    normalized['users_active'] = map['users_active']?.toString() ?? '';
    normalized['allowed_users'] = map['allowed_users']?.toString() ?? '';
    normalized['minorderamount'] = map['minorderamount']?.toString() ?? '0';

    return normalized;
  }

  static Map<String, dynamic> normalizeParty(Map<String, dynamic> map) {
    final name = _stringFromKeys(map, _partyNameKeys);
    final normalized = Map<String, dynamic>.from(map);
    normalized['name'] = name;
    normalized['display_name'] = name;
    return normalized;
  }

  static Map<String, dynamic> normalizeAgency(Map<String, dynamic> map) {
    final name = _stringFromKeys(map, _agencyNameKeys);
    final normalized = Map<String, dynamic>.from(map);
    normalized['name'] = name;
    normalized['display_name'] = name;
    return normalized;
  }

  static Map<String, dynamic> normalizeDeliveryPoint(Map<String, dynamic> map) {
    final name = _stringFromKeys(map, _deliveryNameKeys);
    final normalized = Map<String, dynamic>.from(map);
    normalized['name'] = name;
    normalized['display_name'] = name;
    return normalized;
  }
}
