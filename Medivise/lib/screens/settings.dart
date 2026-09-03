import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../theme_notifier.dart';
import 'package:medivise/auth_service.dart';
import 'homepage.dart';
import 'history_page.dart';
import 'new_diagnosis_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _twoStep = false;
  String? _username;
  String? _userEmail;
  int _selectedIndex = 3;

  @override
  void initState() {
    super.initState();
    _loadUserInfo();
  }

  Future<void> _loadUserInfo() async {
    try {
      final authToken = AuthService.getToken();
      if (authToken == null) {
        print('❌ No token found - please login again');
        return;
      }

      print('🔐 Using token: ${authToken.substring(0, 30)}...');
      
      final response = await http.get(
        Uri.parse('http://localhost:3000/api/user/profile'),
        headers: {'Authorization': 'Bearer $authToken'},
      );

      print('📡 Profile response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _username = data['user']['username'] ?? 'Paramedic Name';
          _userEmail = data['user']['email'] ?? '';
        });
        print('✅ Profile loaded from backend: $_username');
      } else {
        print('❌ Failed to load profile: ${response.statusCode}');
        print('Response body: ${response.body}');
      }
    } catch (e) {
      print('❌ Error loading user info: $e');
    }
  }

  void _onNavBarTapped(int idx) {
    setState(() => _selectedIndex = idx);
    if (idx == 0) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
    } else if (idx == 1) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HistoryPage()));
    } else if (idx == 2) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const NewDiagnosisPage()));
    }
    // idx == 3 is Settings, so we stay here
  }

  Future<void> _showInputDialog({
    required String title,
    required String labelText,
    required Function(String) onConfirm,
  }) async {
    final controller = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            decoration: InputDecoration(
              labelText: labelText,
              border: const OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              child: Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            ElevatedButton(
              child: Text('Save'),
              onPressed: () {
                onConfirm(controller.text.trim());
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _updateEmailDialog() async {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Change Email'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: emailController,
              decoration: InputDecoration(
                labelText: 'New Email',
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: passwordController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: 'Current Password',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            child: Text('Cancel'),
            onPressed: () => Navigator.pop(context),
          ),
          ElevatedButton(
            child: Text('Update'),
            onPressed: () async {
              final newEmail = emailController.text.trim();
              final currentPassword = passwordController.text.trim();
              Navigator.pop(context);

              if (newEmail.isEmpty || currentPassword.isEmpty) return;

              try {
                final authToken = AuthService.getToken();
                if (authToken == null) return;

                final response = await http.put(
                  Uri.parse('http://localhost:3000/api/user/email'),
                  headers: {
                    'Authorization': 'Bearer $authToken',
                    'Content-Type': 'application/json'
                  },
                  body: jsonEncode({
                    'newEmail': newEmail,
                    'currentPassword': currentPassword,
                  }),
                );

                final responseData = jsonDecode(response.body);

                if (response.statusCode == 200 && responseData['success'] == true) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Email updated successfully!'),
                  ));

                  setState(() {
                    _userEmail = newEmail;
                    _username = newEmail.split('@').first; // Use email prefix as username
                  });
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Error: ${responseData['message']}'),
                  ));
                }
              } catch (e) {
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text('Error: $e'),
                ));
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _updatePassword(String newPassword) async {
    final authToken = AuthService.getToken();
    if (authToken == null || newPassword.isEmpty) return;

    try {
      final response = await http.put(
        Uri.parse('http://localhost:3000/api/user/password'),
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json'
        },
        body: jsonEncode({
          'newPassword': newPassword,
        }),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 200 && responseData['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Password updated successfully!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: ${responseData['message']}')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeNotifier = Provider.of<ThemeNotifier>(context);
    final isDarkMode = themeNotifier.mode == ThemeMode.dark;
    const primary = Color(0xFF1A3B66);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: primary,
        automaticallyImplyLeading: false, // This removes the back button
        title: Row(
          children: [
            Image.asset('lib/assets/logo.png', height: 28),
            const SizedBox(width: 12),
            Text(
              'Settings',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 22,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Profile
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Theme.of(context).scaffoldBackgroundColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(.25),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  )
                ],
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: primary,
                    backgroundImage:
                        const AssetImage('lib/assets/profile_placeholder.png'),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _username ?? 'Loading...',
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          _userEmail ?? '',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.camera_alt_outlined),
                    onPressed: () {},
                    color: primary,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            _SectionHeader(text: 'Account'),
            _SettingsTile(
              icon: Icons.email_outlined,
              label: 'Change Email',
              onTap: _updateEmailDialog,
            ),
            _SettingsTile(
              icon: Icons.lock_outline,
              label: 'Change Password',
              onTap: () {
                _showInputDialog(
                  title: 'Change Password',
                  labelText: 'Enter new password',
                  onConfirm: _updatePassword,
                );
              },
            ),
            _SettingsSwitch(
              icon: Icons.security,
              label: 'Two‑Step Authentication',
              value: _twoStep,
              onChanged: (v) => setState(() => _twoStep = v),
            ),

            const SizedBox(height: 24),
            _SectionHeader(text: 'Preferences'),
            _SettingsSwitch(
              icon: Icons.dark_mode_outlined,
              label: 'Dark Mode',
              value: isDarkMode,
              onChanged: themeNotifier.setDark,
            ),
            _SettingsTile(
              icon: FontAwesomeIcons.star,
              label: 'Starred Cases',
              onTap: () {},
            ),

            const SizedBox(height: 24),
            _SectionHeader(text: 'Help & Support'),
            _SettingsTile(
              icon: Icons.help_outline,
              label: 'FAQ',
              onTap: () {},
            ),
            _SettingsTile(
              icon: Icons.bug_report_outlined,
              label: 'Report a Problem',
              onTap: () {},
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF1A3B66),
        unselectedItemColor: Colors.grey,
        currentIndex: _selectedIndex,
        onTap: _onNavBarTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(icon: Icon(Icons.add_circle), label: 'New'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}

/*────────── reusable ──────────*/

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader({required this.text});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                text,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _SettingsTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: ListTile(
          leading: Icon(icon, color: const Color(0xFF1A3B66)),
          title: Text(label),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap,
        ),
      );
}

class _SettingsSwitch extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SettingsSwitch({
    required this.icon,
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: SwitchListTile(
          secondary: Icon(icon, color: const Color(0xFF1A3B66)),
          title: Text(label),
          value: value,
          onChanged: onChanged,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
}