import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:medivise/auth_service.dart';
import 'dart:convert';
import 'CaseDetailsPage.dart';
import 'history_page.dart';
import 'new_diagnosis_page.dart';
import 'settings.dart';

// REMOVE this line: String? authToken;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String? _paramedicName;
  bool _isLoadingName = true;
  List<Map<String, dynamic>> _recentCases = [];
  bool _isLoadingCases = true;
  Timer? _casesTimer;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
    _startCasesPolling();
  }

  Future<void> _fetchUserData() async {
  try {
    print('=== 🏠 HOMEPAGE DEBUG START ===');
    
    // Test 1: Check AuthService directly
    print('1. 📋 Testing AuthService directly...');
    final authToken = AuthService.getToken();
    print('2. 🔍 AuthService.getToken() result: $authToken');
    print('3. 🔍 Token is null: ${authToken == null}');
    
    if (authToken == null) {
      print('4. ❌ CRITICAL: AuthService returned NULL token');
      print('5. 💡 This means the token was never stored or was cleared');
      setState(() {
        _paramedicName = 'Paramedic (No Token)';
        _isLoadingName = false;
      });
      return;
    }

    print('6. ✅ AuthService returned token, length: ${authToken.length}');
    print('7. 🔐 Token preview: ${authToken.substring(0, min(30, authToken.length))}...');

    // Test 2: Make API call
    print('8. 📡 Making API call to /api/user/profile...');
    final response = await http.get(
      Uri.parse('http://localhost:3000/api/user/profile'),
      headers: {'Authorization': 'Bearer $authToken'},
    );

    print('9. 📡 Response status: ${response.statusCode}');
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      print('10. ✅ API Success! Full response: $data');
      
      // Check every possible field
      final user = data['user'];
      print('11. 🔍 User object: $user');
      
      if (user != null) {
        print('12. 🔍 Available user fields:');
        user.forEach((key, value) {
          print('    - $key: $value');
        });
        
        final username = user['username'];
        final nameEn = user['name_en'];
        final displayName = user['displayName'];
        final email = user['email'];
        
        final chosenName = username ?? nameEn ?? displayName ?? email?.split('@').first ?? 'Paramedic';
        print('13. 🎯 Chosen name: $chosenName');
        
        setState(() {
          _paramedicName = chosenName;
          _isLoadingName = false;
        });
        print('14. 🎉 UI Updated with name: $_paramedicName');
      } else {
        print('15. ❌ User object is null in response');
        setState(() {
          _paramedicName = 'Paramedic (No User Data)';
          _isLoadingName = false;
        });
      }
    } else {
      print('16. ❌ API call failed with status ${response.statusCode}');
      print('17. ❌ Response body: ${response.body}');
      setState(() {
        _paramedicName = 'Paramedic (API Error)';
        _isLoadingName = false;
      });
    }
    
    print('=== 🏠 HOMEPAGE DEBUG END ===');
  } catch (e) {
    print('18. 💥 EXCEPTION: $e');
    setState(() {
      _paramedicName = 'Paramedic (Error)';
      _isLoadingName = false;
    });
  }
}

  Future<void> _fetchRecentCases() async {
  try {
    final authToken = AuthService.getToken();
    if (authToken == null) {
      print('❌ No auth token for cases API');
      setState(() {
        _recentCases = [];
        _isLoadingCases = false;
      });
      return;
    }

    print('📋 Fetching recent cases from API...');
    
    final response = await http.get(
      Uri.parse('http://localhost:3000/api/cases/recent'),
      headers: {'Authorization': 'Bearer $authToken'},
    );

    print('📋 Cases API response status: ${response.statusCode}');
    
    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      print('✅ Cases API success! Response: $data');
      
      if (data['success'] == true) {
        setState(() {
          _recentCases = List<Map<String, dynamic>>.from(data['cases'] ?? []);
          _isLoadingCases = false;
        });
        print('✅ Loaded ${_recentCases.length} recent cases');
      } else {
        print('❌ Cases API returned error: ${data['message']}');
        setState(() {
          _recentCases = [];
          _isLoadingCases = false;
        });
      }
    } else {
      print('❌ Cases API call failed with status ${response.statusCode}');
      print('❌ Response body: ${response.body}');
      setState(() {
        _recentCases = [];
        _isLoadingCases = false;
      });
    }
  } catch (e) {
    print('❌ Error loading cases: $e');
    setState(() {
      _recentCases = [];
      _isLoadingCases = false;
    });
  }
}

  void _startCasesPolling() {
  // Poll for cases every 30 seconds (less frequent since it's API calls)
  _casesTimer = Timer.periodic(Duration(seconds: 30), (timer) {
    final authToken = AuthService.getToken();
    if (authToken != null) {
      _fetchRecentCases();
    }
  });
  
  // Initial fetch
  _fetchRecentCases();
}

  @override
  void dispose() {
    _casesTimer?.cancel();
    super.dispose();
  }

  void _onNavBarTapped(int idx) {
    setState(() => _selectedIndex = idx);
    if (idx == 1) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const HistoryPage()));
    } else if (idx == 2) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const NewDiagnosisPage()));
    } else if (idx == 3) {
      Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsPage()));
    }
  }

  IconData getCaseIcon(String issue) {
    final i = issue.toLowerCase();
    if (i.contains('heart') || i.contains('cardiac')) return FontAwesomeIcons.heartPulse;
    if (i.contains('asthma') || i.contains('breath') || i.contains('respiratory')) return FontAwesomeIcons.lungs;
    if (i.contains('fracture') || i.contains('injury') || i.contains('bone')) return FontAwesomeIcons.bone;
    if (i.contains('burn')) return FontAwesomeIcons.fire;
    if (i.contains('diabetes') || i.contains('sugar')) return FontAwesomeIcons.syringe;
    if (i.contains('stroke')) return FontAwesomeIcons.brain;
    if (i.contains('pregnancy') || i.contains('delivery')) return FontAwesomeIcons.baby;
    return FontAwesomeIcons.stethoscope;
  }

  Color getCaseColor(String issue) {
    final i = issue.toLowerCase();
    if (i.contains('heart') || i.contains('cardiac')) return Colors.red;
    if (i.contains('asthma') || i.contains('breath') || i.contains('respiratory')) return Colors.teal;
    if (i.contains('fracture') || i.contains('injury') || i.contains('bone')) return Colors.orange;
    if (i.contains('burn')) return Colors.deepOrange;
    if (i.contains('diabetes') || i.contains('sugar')) return Colors.purple;
    if (i.contains('stroke')) return Colors.indigo;
    if (i.contains('pregnancy') || i.contains('delivery')) return Colors.pinkAccent;
    return Colors.blueGrey;
  }

  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A3B66),
        title: Row(
          children: [
            Image.asset('lib/assets/logo.png', width: 40, height: 40),
            const SizedBox(width: 12),
            Text('Medivise', style: const TextStyle(fontSize: 22, color: Colors.white)),
          ],
        ),
      ),
      body: _buildHomeBody(),
      bottomNavigationBar: BottomNavigationBar(
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF1A3B66),
        unselectedItemColor: Colors.grey,
        currentIndex: _selectedIndex,
        onTap: _onNavBarTapped,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(icon: Icon(Icons.add_circle), label: 'New Chat'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildHomeBody() {
    final nameToShow = _paramedicName ?? 'Paramedic';

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('👋', style: Theme.of(context).textTheme.headlineLarge),
              const SizedBox(width: 8),
              _isLoadingName
                  ? const CircularProgressIndicator()
                  : Text(
                      'Welcome Back, $nameToShow!',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
            ],
          ),
          const SizedBox(height: 8),
          Text('Ready to diagnose your next case?', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey[600])),
          const SizedBox(height: 24),
          _buildStartDiagnosisButton(),
          const SizedBox(height: 32),
          _buildRecentCasesSection(),
        ],
      ),
    );
  }

  Widget _buildStartDiagnosisButton() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF1A3B66),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.grey.withOpacity(.3), blurRadius: 5, offset: const Offset(0, 3))
        ],
      ),
      child: MaterialButton(
        padding: const EdgeInsets.symmetric(vertical: 18),
        onPressed: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const NewDiagnosisPage()));
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.local_hospital, color: Colors.white, size: 28),
            const SizedBox(width: 12),
            Text('Start New Diagnosis', style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentCasesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.folder_open, color: Colors.grey),
            const SizedBox(width: 8),
            Text('Recent Cases', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 16),
        _isLoadingCases
            ? const Center(child: CircularProgressIndicator())
            : _recentCases.isEmpty
                ? Center(
                    child: Column(
                      children: [
                        Text('No recent cases found.', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.grey)),
                        SizedBox(height: 8),
                        Text('Cases API coming soon...', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey)),
                      ],
                    ),
                  )
                : Column(
                    children: _recentCases.map((caseData) {
                      final name = '${caseData['patientFirstName'] ?? ''} ${caseData['patientLastName'] ?? ''}'.trim();
                      final issue = caseData['conditionNameEn'] ?? 'Unknown Condition';
                      return _buildCaseCard(caseData['id'], name, issue);
                    }).toList(),
                  ),
      ],
    );
  }

  Widget _buildCaseCard(String caseId, String name, String issue) {
    return InkWell(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => CaseDetailsPage(caseId: caseId)));
      },
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 2,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFFE0E0E0),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(color: Color(0xFF1A3B66), fontWeight: FontWeight.bold, fontSize: 20),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        FaIcon(getCaseIcon(issue), color: getCaseColor(issue), size: 18),
                        const SizedBox(width: 6),
                        Expanded(child: Text(issue, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]))),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}