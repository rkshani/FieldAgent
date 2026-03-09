# Order Add Screen – Complete Overview

Yeh document Order Add screen ka poora flow, data sources, aur UI sections explain karta hai.

---

## 1. Screen kya karta hai (Purpose)

- User **naya order** banata hai: Party select karta hai, items add karta hai, quantity/price daalta hai, phir **RESET** ya **FINALIZE** karta hai.
- Saari **dropdown/list data local cache** se aati hai (Update DB se pehle load hui).
- Har selection field pe **search** hai taake user jaldi option dhundh sake.

---

## 2. Data kahan se aata hai (Data Sources)

| Field / List | Source (Local cache key) | Kaise load hota hai |
|-------------|---------------------------|----------------------|
| **Parties** | `local_party` | `OrderDatabaseHelper.instance.getParties()` → SQLite se JSON parse |
| **Items** | `local_items` | `OrderDatabaseHelper.instance.getItems()` |
| **Packages** | `local_packages` | `OrderDatabaseHelper.instance.getPackages()` |
| **Delivery Points** | `local_deliver_points` | `OrderDatabaseHelper.instance.getDeliveryPoints()` |
| **Goods Agencies** | `local_goods_agency` | `OrderDatabaseHelper.instance.getGoodsAgencies()` |
| **Visits** | `local_store_data` | `OrderDatabaseHelper.instance.getStoreData()` → agar response mein `stores` array hai to woh use, warna poora list |

Yeh cache **Update DB** screen se `ApiService.fetchAndSaveLocalData()` chalane par banta hai. Order Add screen **sirf local DB** padhta hai, direct API nahi.

---

## 3. Screen open hote hi kya hota hai (Lifecycle)

1. **initState**
   - `_loadUserId()` – logged-in user ID + username **SessionService** se (SharedPreferences).
   - `_loadLocalData()` – **OrderDatabaseHelper** se saari lists (parties, items, packages, delivery points, agencies, store/visits) load karke state (`_parties`, `_items`, …) mein daalta hai.

2. **Default selection**
   - Agar parties load hain to `_selectedPartyIndex = 0` (pehla party).
   - Agar packages load hain to `_selectedPackageIndex = 0`.
   - Party select hone par `_onPartySelected(index)` se delivery address auto-fill (party map se `address` / `Address` / `delivery_address`).

3. **Loading**
   - Jab tak `_loadLocalData()` chal raha hota hai, `_loading = true` → screen **CircularProgressIndicator** dikhata hai.

---

## 4. UI Sections – Kya dikhta hai, kahan se data

### 4.1 Top Section (blue header)

- **Visit** – Searchable picker; options `_visits` se (store data). Display: `deliveryPointDisplay(map)` → name/store_name/StoreName/title/point.
- **Party** – Searchable picker; options `_parties` se. Display: `partyDisplay(map)`. Select par delivery address auto-fill.
- **Goods Agency** – Searchable picker; options `_agencies` se. Display: `agencyDisplay(map)`.
- **Delivery Address** – Simple **TextField** (`_deliveryAddressController`). Party select par auto-fill, user edit bhi kar sakta hai.
- **Package** – Searchable picker; options `_packages` se. Display: `packageDisplay(map)`.
- **Payment Deal** – Sirf display; value `_paymentDeal` (abhi fixed 0).

### 4.2 Item Entry Section

- **Item** – Searchable picker; options `_items` se. Display: `itemDisplay(map)`.
- **QTY** – TextField (`_qtyController`), number keyboard.
- **ADD** button – `_addItem()` call:
  - Selected item + QTY validate.
  - Price: agar **Special Price** field mein value hai to woh use, warna local item map se `_itemPrice(map)` (price/Price/rate/Rate/sale_price).
  - **InvoiceItem** banake **InvoiceProvider.addItem(item)**.
  - QTY + Special Price clear, item selection clear.
- **Special Remarks** – TextField (optional notes).
- **Special Price** – TextField; agar fill hai to ADD par isi se price use hota hai, warna item ki default price.

### 4.3 Order Details Section

- **Date** – `DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())` – current time.
- **ID** – `_orderId` (abhi static 1; baad mein API/DB se generate ho sakta hai).

### 4.4 Items List Section

- **InvoiceProvider** ka **Consumer** – `provider.items` list dikhata hai.
- Har row: Item name, Price, QTY, %age (discount), TOTAL (subtotal + discount amount in red).
- Data **InvoiceProvider** se; yeh wohi items hain jo ADD button se add hue.

### 4.5 Summary Section

- **InvoiceProvider** se: `grossAmount`, `totalDiscount`, `netAmount`.
- Gross, Discount, Net teen columns mein.

### 4.6 Bottom Actions

- **User ID** – `_userId` (SessionService se: `userId_username`).
- **Want to add Remarks?** – OutlinedButton (abhi sirf placeholder).
- **Delivery** – Searchable picker; options `_deliveryPoints` se. Display: `deliveryPointDisplay(map)`.
- **RESET** – `InvoiceProvider.reset()` + SnackBar. Order items clear, naya invoice state.
- **FINALIZE** – Agar items nahi hain to SnackBar; warna `provider.finalize()` → current invoice `savedInvoices` mein save, phir naya invoice, SnackBar + `Navigator.pop(context)`.

---

## 5. Searchable Picker – Kaise kaam karta hai

- Har dropdown ki jagah ek **tap-able field** hai (label + current value + search icon).
- Tap par **`_showSearchablePicker(...)`** ek **AlertDialog** kholta hai:
  - **Title** = hint (e.g. "Select Party", "Search Item").
  - Upar **TextField** "Search..." – `onChanged` par list filter hoti hai (display text `.toLowerCase().contains(query)`).
  - Neeche **ListView** – filtered indices se items; tap par `Navigator.pop(ctx, index)` → parent ko selected index milta hai.
- Parent `onSelected(index)` call karta hai → `setState` se `_selectedPartyIndex` / `_selectedItemIndex` etc. update.
- Display text har type ke liye alag helper se aata hai (partyDisplay, itemDisplay, packageDisplay, …).

---

## 6. Display helpers – API keys se label kaise banta hai

Sab **Map<String, dynamic>** se string nikalne ke liye; pehla non-empty value use hota hai:

- **partyDisplay** – name, partyname, PartyName, party_name, title.
- **itemDisplay** – name, itemname, ItemName, description, code, title.
- **packageDisplay** – name, package_name, PackageName, title.
- **deliveryPointDisplay** – name, store_name, StoreName, title, point.
- **agencyDisplay** – name, agency_name, AgencyName, title.

**Price (items)** – `_itemPrice(map)`: price, Price, rate, Rate, sale_price (number ya string parse).

---

## 7. State (Variables) – Short summary

| Variable | Type | Use |
|----------|------|-----|
| `_parties`, `_items`, `_packages`, `_deliveryPoints`, `_agencies`, `_visits` | `List<Map<String, dynamic>>` | Local data lists |
| `_selectedPartyIndex`, `_selectedItemIndex`, … | `int?` | Konsa option selected hai |
| `_loading` | bool | Initial load (spinner) |
| `_userId`, `_orderId`, `_paymentDeal` | String / int | Display values |
| `_qtyController`, `_specialRemarksController`, `_specialPriceController`, `_deliveryAddressController` | TextEditingController | User input |

---

## 8. Dependencies (Files / Services)

- **order_add_screen.dart** – UI + local state.
- **OrderDatabaseHelper** – Local cache se lists (getParties, getItems, …).
- **LocalDbService** – SQLite table `local_api_cache` (cache_key, payload).
- **SessionService** – getUserId(), getSavedUsername() (SharedPreferences).
- **InvoiceProvider** (Provider) – items list, addItem, reset, finalize, gross/discount/net.
- **InvoiceItem** – id, name, price, quantity, discountPercent; subtotal, discountAmount, total.

---

## 9. Flow summary (step-by-step)

1. Screen open → userId load, saari local lists load → agar parties/packages hain to first option pre-select, party se address fill.
2. User Visit / Party / Agency / Package / Item / Delivery tap karke search dialog se option select karta hai.
3. User item select karke QTY (aur optional Special Price) daal ke ADD dabata hai → line InvoiceProvider mein add hoti hai, list + summary update.
4. RESET → cart clear. FINALIZE → invoice save, screen close.

Is tara Order Add screen **pura local data** use karta hai aur **search** se har field mein option dhundhna easy hai.
