# Order Add Screen – Android Parity Architecture

This document defines the revised Flutter architecture so the Order Add flow matches Android Java behavior (hybrid: local DB + SharedPreferences + live APIs).

---

## A) Revised Architecture

### High-level

- **Session / config**: `SharedPreferences` (SessionService) – logged-in user, employeeid, account, static IP, data update date, etc.
- **Master data cache**: SQLite `local_api_cache` (LocalDbService) – parties, items, packages, delivery points, etc., refreshed by Update DB.
- **Draft order + line items**: SQLite tables `draft_orders` and `draft_order_items` (DraftOrderService). One current draft per user; updated on every field change and line add/remove.
- **Live APIs**: Used for goods agency refresh, approved visits/routes, payment methods (when package rules require), already-in-order items, and post-finalize sync/attendance. Base URL for agent APIs comes from SessionService (static IP).
- **State**: Provider (DraftOrderProvider) holds current draft id and notifies UI; data of record is in SQLite. Optional later: migrate to Riverpod/Bloc.

### Layer diagram

```
┌─────────────────────────────────────────────────────────────────┐
│  Order Add Screen (UI)                                          │
│  - Reads/writes via DraftOrderProvider                          │
│  - Calls VisitService, PaymentDealService, etc. when needed     │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│  DraftOrderProvider (ChangeNotifier)                             │
│  - currentDraftId, loadDraft(), updateHeader(), addLineItem(),   │
│    removeLineItem(), reset(), finalize()                         │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│  Services (data + APIs)                                          │
│  DraftOrderService    → SQLite draft_orders, draft_order_items   │
│  SessionService       → SharedPreferences (user, static IP, etc.)│
│  LocalDbService       → SQLite local_api_cache (master data)     │
│  OrderDatabaseHelper  → Read/parse from local_api_cache          │
│  GoodsAgencyService   → API refresh + cache                      │
│  VisitService         → Approved visit/route API + local save    │
│  PaymentDealService   → getPaymentMethods(partyId) when needed   │
│  AlreadyAddedItemService → get_already_in_order_items + cache    │
│  SyncService          → uploadIfInterNetAvailable after finalize│
└─────────────────────────────────────────────────────────────────┘
```

### Concepts (aligned with Android)

| Concept | Meaning | Stored / used where |
|--------|---------|----------------------|
| **Bill-to party** | Party for billing | draft_orders.bill_to_party_id, partyName; from local Party list |
| **Ship-to party** | Delivery party (can differ from bill-to) | draft_orders.ship_to_party_id / delivery_party_id |
| **Delivery point / Via** | Via delivery point | draft_orders.delivery_point_id or similar |
| **Goods agency** | Goods agency for the order | draft_orders.goods_agency_id, goods_agency_name |
| **Visit / route** | Approved visit; has visit_id, routeid, cityids | From VisitService API; can store visit_id on draft |
| **Payment deal** | Selected when package rules require; from getPaymentMethods(partyId) | draft_orders.payment_deal_id or payment_method_id |

---

## B) Full API Inventory (Purpose, Params, Response Usage)

### 1. Goods Agency API

- **Purpose**: Refresh list of goods agencies for dropdown.
- **URL**: `{baseUrl} + AndroidAPIroot + order_web_api_z.php?get_goodsagency=1`  
  Example: `https://www.hisaab.org/tclorder_apis/order_web_api_z.php?get_goodsagency=1`
- **Method**: GET.
- **Request params**: None (or as per Android).
- **Response usage**: Parse list; save to LocalDbService cache key `local_goods_agency`; Order Add uses it for Goods Agency dropdown.

### 2. Approved Visit / Route API

- **Purpose**: Fetch approved visits/routes for the agent (visit_id, routes, cityids, routeid) and save locally.
- **URL**: `{staticIP} + AGENT_APPROVED_VISIT + "&userid=" + employeeId`  
  `staticIP` = SessionService.getStaticIP(); `userid` = SessionService.getEmployeeId().
- **Method**: GET.
- **Request params**: `userid` (required).
- **Response usage**: Extract visit_id, routeid, cityids, routes; save to local (e.g. SharedPreferences or a dedicated cache key like `local_approved_visit`); Order Add Visit dropdown and draft visit_id.

### 3. Payment Methods API

- **Purpose**: When package rules require payment deals, fetch payment methods for the selected party.
- **URL**: From Android `getPaymentMethods(partyId)` – e.g. `{base}/order_web_api_z.php?get_payment_methods=1&party_id={partyId}` (adjust path/params to match backend).
- **Method**: GET (or POST if Android uses POST).
- **Request params**: `party_id` (bill-to party id).
- **Response usage**: List of payment methods; show in Payment Deal selector; save selected id on draft (payment_deal_id).

### 4. Already-in-Order Items API

- **Purpose**: Fetch items already added to the current order (e.g. from server or session) and save locally so UI can show or merge.
- **URL**: `{base}/order_web_api_z.php?get_already_in_order_items=1&...` (add userid, orderid, or session params as in Android).
- **Method**: GET (or POST).
- **Request params**: Typically userid, order_id or draft_id, etc. (match Android).
- **Response usage**: Save to local cache (e.g. `local_already_in_order_items`); when loading draft, optionally merge or display these with local line items.

### 5. Final Sync / Upload (after finalize)

- **Purpose**: When order is finalized, upload order and insert attendance when internet is available.
- **URL / flow**: Android `uploadIfInterNetAvailable()` – likely POST order data and attendance to server endpoints.
- **Request params**: Order header + line items + attendance payload (match Android).
- **Response usage**: On success, clear or mark uploaded; on failure, keep for retry.

### 6. Existing APIs (unchanged)

- **Login**: `tclorder_apis/new.php` (POST) – SessionService + user data.
- **Update DB / Local data**: Party, Items, Packages, Deliver Points, Store Data, etc. – already in ApiService/LocalDbService; Order Add reads via OrderDatabaseHelper.

---

## C) Local DB / SharedPreferences Mapping

### SharedPreferences (SessionService)

| Key (logical) | Purpose |
|---------------|---------|
| user_data | Full User JSON (username, employeeid, account, etc.) |
| saved_username / saved_password | Pre-fill login |
| static_ip | Base URL for agent APIs (e.g. approved visit, sync) |
| user_rec_id | User receipt/id from login |
| user_account | Account from login |
| data_update_date | Last master data update date |
| previous_bilty_no / previous_bilty_time | Bilty info |
| data_update_id, is_activity_running, is_app_update_important | App state flags |

### SQLite – LocalDbService

**Table: local_api_cache** (existing)

- cache_key TEXT PRIMARY KEY  
- payload TEXT  
- updated_at TEXT  
- Used for: local_party, local_items, local_packages, local_deliver_points, local_goods_agency, local_store_data, etc.

**Table: draft_orders** (new)

- id INTEGER PRIMARY KEY AUTOINCREMENT  
- local_order_id TEXT UNIQUE (e.g. UUID or device-specific id)  
- bill_to_party_id TEXT  
- party_name TEXT  
- ship_to_party_id TEXT (delivery party)  
- delivery_party_name TEXT  
- delivery_point_id TEXT  
- delivery_point_name TEXT  
- goods_agency_id TEXT  
- goods_agency_name TEXT  
- visit_id TEXT  
- route_id TEXT  
- package_id TEXT  
- package_name TEXT  
- payment_deal_id TEXT  
- delivery_address TEXT  
- status TEXT (draft | finalized)  
- finalized_at TEXT (nullable)  
- created_at TEXT, updated_at TEXT  
- user_id / employee_id TEXT (for multi-user or single-user)

**Table: draft_order_items** (new)

- id INTEGER PRIMARY KEY AUTOINCREMENT  
- draft_order_id INTEGER (FK to draft_orders.id)  
- item_id TEXT (product id)  
- item_name TEXT  
- quantity INTEGER  
- unit_price REAL  
- discount_percent REAL  
- special_remarks TEXT  
- sort_order INTEGER  
- created_at TEXT  

Totals (gross, discount, net) are computed from draft_order_items when reading the draft, not stored on header (or stored as cache only).

---

## D) Corrected Flutter Data Flow

### Add item

1. User selects item from local items list, enters QTY (and optional special price/remarks).
2. UI calls `DraftOrderProvider.addLineItem(...)` with item id, name, price, qty, discount, remarks.
3. DraftOrderProvider calls `DraftOrderService.insertLineItem(draftId, ...)`.
4. Service inserts row into `draft_order_items`, then optionally recalculates and updates draft `updated_at`.
5. Provider loads updated draft from DB (`DraftOrderService.getDraft(draftId)`) and notifies listeners.
6. UI (Consumer) rebuilds; items list and summary come from draft in DB.

### Reset

1. User taps RESET.
2. Provider calls `DraftOrderService.resetDraft(draftId)` or deletes all line items and clears header fields for current draft (or creates a new blank draft and sets it as current).
3. Android: “creates a fresh blank draft order” – so either delete current draft’s items and reset header, or create new draft and replace currentDraftId.
4. Provider reloads draft from DB and notifies listeners.

### Finalize

1. User taps FINALIZE; validation (e.g. at least one item, required fields).
2. Provider calls `DraftOrderService.finalizeDraft(draftId)`:
   - Update draft_orders set status = 'finalized', finalized_at = now(), and any header fields.
   - Do not delete the draft or items (keep for sync and history).
3. SyncService.uploadIfInterNetAvailable() – enqueue or immediately upload order + attendance when online.
4. DraftOrderService.createNewDraft() – create a new draft row, set as current.
5. Provider sets currentDraftId to the new draft, loads it, notifies listeners.
6. UI can show “Order finalized” and stay on Order Add with blank draft, or pop back (as today); both are valid.

### Sync (background / after finalize)

1. When a order is finalized, SyncService runs upload logic (when internet available).
2. Payload: order header + line items + attendance (match Android).
3. On success: mark order as synced (e.g. sync_status column or separate table).
4. On failure: keep in DB for retry; optional retry later or on next app open.

### Field updates (party, ship-to, agency, package, payment deal, delivery point, visit)

1. User selects Party → UI calls `DraftOrderProvider.updateParty(partyId, partyName)` (and optionally load payment methods if package requires).
2. DraftOrderService updates draft_orders row: bill_to_party_id, party_name; optionally delivery_address from party.
3. User selects Ship-to → update ship_to_party_id, delivery_party_name.
4. User selects Goods Agency → update goods_agency_id, goods_agency_name.
5. User selects Package → update package_id, package_name; if rules require payment deal, call PaymentDealService.fetch(partyId) and show selector; on select update payment_deal_id.
6. User selects Delivery point / Via → update delivery_point_id, delivery_point_name.
7. User selects Visit → update visit_id, route_id from VisitService data.
8. Each update persists to SQLite and Provider notifies so UI reflects draft from DB.

---

## Implementation order (modules)

1. **DB schema**: Extend LocalDbService – add `draft_orders` and `draft_order_items` tables (migration from v1 to v2).
2. **DraftOrderService**: CRUD for draft + line items; getCurrentDraft(), createNewDraft(), reset, finalize.
3. **SessionService**: Ensure getStaticIP(), getEmployeeId(), getUserId(), getDataUpdateDate() used by new services.
4. **GoodsAgencyService**: Call goods agency API, save to local_api_cache; Order Add already reads from cache.
5. **VisitService**: Call approved visit API with static IP + userid; save result; expose visit list for dropdown and set visit_id on draft.
6. **PaymentDealService**: getPaymentMethods(partyId); used when package requires payment deal; result drives Payment Deal dropdown.
7. **AlreadyAddedItemService**: get_already_in_order_items; save to cache; optionally merge into draft or show in UI.
8. **SyncService**: uploadIfInterNetAvailable() after finalize (order + attendance).
9. **DraftOrderProvider**: State that holds currentDraftId; methods that call DraftOrderService and the above services where needed; notifyListeners after each DB write.
10. **Order Add Screen**: Bind to DraftOrderProvider; load draft on init; every field change and add item goes through Provider → Service → DB; RESET/FINALIZE as above; use local data for dropdowns and payment deal when applicable.

This keeps Order Add hybrid (local + APIs), matches Android behavior, and fixes the previous simplifications (payment deal, items in DB, dynamic order id, bill-to vs ship-to vs delivery vs agency vs visit).

---

## Implementation summary (Flutter)

- **LocalDbService**: DB version 2; tables `draft_orders` and `draft_order_items` added.
- **DraftOrderService**: CRUD for draft + line items; getCurrentDraft, createNewDraft, updateDraftHeader, insertLineItem, deleteLineItem, resetDraft, finalizeDraft. Current draft id in SharedPreferences (`current_draft_id`).
- **DraftOrderProvider**: Loads draft from DB; updateParty, updateGoodsAgency, updatePackage, updatePaymentDeal, updateDeliveryPoint, updateVisit, updateDeliveryAddress; addLineItem, removeLineItem, reset, finalize (finalize → sync → new draft).
- **ApiClient (Dio)**: Agent base URL from SessionService.getStaticIP(); TCL APIs via getTclOrderWebUrl (order_web_api_z.php).
- **GoodsAgencyService**: GET goods agency API → save to `local_goods_agency`.
- **VisitService**: GET approved visit (static IP + path + userid) → save to `local_approved_visit`. Replace `agentApprovedVisitPath` with actual Android `URLs.AGENT_APPROVED_VISIT` if different.
- **PaymentDealService**: getPaymentMethods(partyId) for Payment Deal dropdown when party is selected.
- **AlreadyAddedItemService**: get_already_in_order_items → cache; optional merge in UI.
- **SyncService**: uploadIfInterNetAvailable(order, items) after finalize; adjust `uploadOrderPath` to match Android.
- **Order Add Screen**: Uses DraftOrderProvider; all selections persist to draft in DB; order ID = draft.localOrderId; RESET/FINALIZE use provider; payment deal loaded when party is selected.
