import 'package:flutter/material.dart';

import 'update_db_screen.dart';
import 'order_add_screen.dart';
import 'login_screen.dart';
import 'local_db_testing_screen.dart';
import 'login_testing_screen.dart';
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
        child: Column(
          children: [
            // Header Section
            Container(
              color: theme.cardTheme.color ?? theme.scaffoldBackgroundColor,
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: _primaryColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            'TCL',
                            style: TextStyle(
                              color: theme.colorScheme.onPrimary,
                              fontSize: 32,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'TCL Order App!',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                                color: _primaryColor,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Updated: 4.24',
                              style: TextStyle(
                                fontSize: 14,
                                color: theme.hintColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Divider(color: theme.dividerColor, thickness: 1),
                ],
              ),
            ),

            // Menu Sections
            Container(
              color: theme.scaffoldBackgroundColor,
              padding: const EdgeInsets.symmetric(vertical: 8),
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
            color: theme.cardTheme.color ?? theme.scaffoldBackgroundColor,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 24,
                      decoration: BoxDecoration(
                        color: sectionColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 12),
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
                      ? Icons.expand_less
                      : Icons.expand_more,
                  color: theme.colorScheme.onSurface,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
        Divider(color: theme.dividerColor, thickness: 1, height: 0),

        // Section Content
        if (_expandedSections[title]!)
          Container(
            color: theme.cardTheme.color ?? theme.scaffoldBackgroundColor,
            padding: const EdgeInsets.all(12),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                childAspectRatio: 1.4,
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

        const SizedBox(height: 8),
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

          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('$label tapped')));
        },
        borderRadius: BorderRadius.circular(8),
        child: Container(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            border: Border.all(color: color.withValues(alpha: 0.3)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 6),
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
                    color: Colors.grey[800],
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
