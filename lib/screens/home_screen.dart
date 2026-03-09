import 'package:flutter/material.dart';

import 'update_db_screen.dart';
import 'order_add_screen.dart';
import 'orders_screen.dart';
import 'login_screen.dart';
import 'local_db_testing_screen.dart';
import 'login_testing_screen.dart';
import 'order_testing_screen.dart';
import 'created_order_testing_screen.dart';
import '../services/session_service.dart';
import '../services/api_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final Map<String, bool> _expandedSections = {
    'ORDERS': true,
    'ACCOUNTS': true,
    'LEDGERS': false,
    'STOCK COLLECTION': false,
    'DAMAGE RETURN': false,
    'RAW MATERIAL': false,
    'SURVEY': false,
  };

  static const Color _primaryColor = Color(0xFF2563EB);

  @override
  void initState() {
    super.initState();
    _fetchDataAutomatically();
  }

  /// Automatically fetch local data after login (runs silently in background)
  Future<void> _fetchDataAutomatically() async {
    try {
      await ApiService.fetchAndSaveLocalData();
      // Data fetched and saved silently - Order Add screen will use it
    } catch (e) {
      debugPrint('Auto-fetch data error: $e');
      // Fail silently - user can manually sync from Update DB screen if needed
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FC),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: const BoxDecoration(color: _primaryColor),
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Text(
                  'Menu',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.update),
              title: const Text('Update DB'),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const UpdateDBScreen()),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.science, color: Colors.purple),
              title: const Text(
                'Testing',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Development & Debug Tools'),
            ),
            ListTile(
              leading: const Icon(Icons.storage),
              title: const Text('Local DB Testing'),
              contentPadding: const EdgeInsets.only(left: 32, right: 16),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const LocalDbTestingScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.login),
              title: const Text('Login Testing'),
              contentPadding: const EdgeInsets.only(left: 32, right: 16),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const LoginTestingScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_check_circle_outlined),
              title: const Text('Order Testing'),
              subtitle: const Text('Delivery points from local DB'),
              contentPadding: const EdgeInsets.only(left: 32, right: 16),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const OrderTestingScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.fact_check_outlined),
              title: const Text('Created Order Testing'),
              subtitle: const Text('Offline + online created orders'),
              contentPadding: const EdgeInsets.only(left: 32, right: 16),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const CreatedOrderTestingScreen(),
                  ),
                );
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Logout'),
              onTap: () async {
                Navigator.of(context).pop();
                await SessionService.clearSession();
                if (!context.mounted) return;
                Navigator.of(context).pushAndRemoveUntil(
                  MaterialPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
            ),
          ],
        ),
      ),
      appBar: AppBar(
        backgroundColor: _primaryColor,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
        title: Text(
          'HOME',
          style: TextStyle(
            color: theme.colorScheme.onPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        actions: [
          IconButton(
            icon: Icon(Icons.more_vert, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 20),
        child: Column(
          children: [
            // Header Section
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF2563EB), Color(0xFF1D4ED8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: _primaryColor.withValues(alpha: 0.22),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Center(
                          child: Text(
                            'TCL',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Welcome Back',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'TCL Order App',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildInfoChip('Version 4.24'),
                      const SizedBox(width: 8),
                      _buildInfoChip('Fast Sync Ready'),
                    ],
                  ),
                ],
              ),
            ),

            // Menu Sections
            const SizedBox(height: 14),
            Container(
              color: Colors.transparent,
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Column(
                children: [
                  _buildSection(theme, 'ORDERS', [
                    {'label': 'ORDER ADD', 'icon': Icons.add},
                    {'label': 'MY ORDERS', 'icon': Icons.list},
                    {'label': 'UPDATE DB', 'icon': Icons.refresh},
                    {'label': 'ORDERS COUNTER', 'icon': Icons.numbers},
                    {'label': 'ADD PAYMENT', 'icon': Icons.payment},
                    {'label': 'PAYMENT DETAILS', 'icon': Icons.description},
                    {'label': 'ADD INVOICE', 'icon': Icons.receipt},
                    {'label': 'MY INVOICE', 'icon': Icons.receipt_long},
                    {'label': 'CLEARANCE', 'icon': Icons.check_circle},
                  ], Colors.orange),
                  _buildSection(theme, 'LEDGERS', [
                    {'label': 'VIEW LEDGERS', 'icon': Icons.book},
                    {'label': 'LEDGER REPORT', 'icon': Icons.report},
                  ], Colors.purple),
                  _buildSection(theme, 'ACCOUNTS', [
                    {'label': 'ADD RECEIPT', 'icon': Icons.add_circle},
                    {'label': 'MY RECEIPT', 'icon': Icons.receipt},
                    {'label': 'AGENT ROUTE VISIT', 'icon': Icons.map},
                    {
                      'label': 'AGENT APPROVED VISIT',
                      'icon': Icons.verified_user,
                    },
                    {'label': 'DEPOSIT', 'icon': Icons.account_balance},
                    {
                      'label': 'PARTY BANK ACCOUNTS',
                      'icon': Icons.account_balance_wallet,
                    },
                    {'label': 'AGENT PARTY ALLOCATION', 'icon': Icons.people},
                  ], Colors.blue),
                  _buildSection(theme, 'STOCK COLLECTION', [
                    {'label': 'ADD STOCK', 'icon': Icons.inventory_2},
                    {'label': 'VIEW STOCK', 'icon': Icons.list},
                  ], Colors.green),
                  _buildSection(theme, 'DAMAGE RETURN', [
                    {'label': 'REPORT DAMAGE', 'icon': Icons.error},
                    {'label': 'DAMAGE LIST', 'icon': Icons.list},
                  ], Colors.red),
                  _buildSection(theme, 'RAW MATERIAL', [
                    {'label': 'ADD MATERIAL', 'icon': Icons.add},
                    {'label': 'MATERIAL LIST', 'icon': Icons.list},
                  ], Colors.brown),
                  _buildSection(theme, 'SURVEY', [
                    {'label': 'NEW SURVEY', 'icon': Icons.assignment},
                    {'label': 'SURVEY LIST', 'icon': Icons.list},
                  ], const Color(0xFF8B4789)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoChip(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildSection(
    ThemeData theme,
    String title,
    List<Map<String, dynamic>> items,
    Color sectionColor,
  ) {
    return Column(
      children: [
        // Section Header
        GestureDetector(
          onTap: () {
            setState(() {
              _expandedSections[title] = !_expandedSections[title]!;
            });
          },
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 9,
                      height: 26,
                      decoration: BoxDecoration(
                        color: sectionColor,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                Icon(
                  _expandedSections[title]!
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: theme.colorScheme.onSurface,
                  size: 24,
                ),
              ],
            ),
          ),
        ),

        // Section Content
        if (_expandedSections[title]!)
          Container(
            margin: const EdgeInsets.only(top: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(10),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.55,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) {
                final item = items[index];
                return _buildActionButton(
                  label: item['label'],
                  icon: item['icon'],
                  color: sectionColor,
                );
              },
            ),
          ),

        const SizedBox(height: 10),
      ],
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required Color color,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (label == 'ORDER ADD') {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const OrderAddScreen()));
            return;
          }
          if (label == 'UPDATE DB') {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const UpdateDBScreen()));
            return;
          }
          if (label == 'MY ORDERS') {
            Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const OrdersScreen()));
            return;
          }

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$label tapped')));
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            border: Border.all(color: color.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 5),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF1F2937),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
