import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:medivise/auth_service.dart';
import 'CaseDetailsPage.dart';
import 'homepage.dart';
import 'new_diagnosis_page.dart';
import 'settings.dart';

class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<Map<String, dynamic>> _allCases = [];
  List<Map<String, dynamic>> _filteredCases = [];
  bool _isLoading = true;
  bool _sortDescending = true;
  String _searchQuery = '';
  int _selectedIndex = 1;

  @override
  void initState() {
    super.initState();
    _fetchCases();
  }

  Future<void> _fetchCases() async {
    try {
      final authToken = AuthService.getToken();
      if (authToken == null) {
        print('❌ No auth token for history API');
        setState(() {
          _isLoading = false;
          _allCases = [];
          _filteredCases = [];
        });
        return;
      }

      print('📋 Fetching cases history from API...');
      
      final response = await http.get(
        Uri.parse('http://localhost:3000/api/cases/history?sort=${_sortDescending ? 'desc' : 'asc'}'),
        headers: {'Authorization': 'Bearer $authToken'},
      );

      print('📋 History API response status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print('✅ History API success! Cases count: ${data['cases']?.length ?? 0}');
        
        if (data['success'] == true) {
          setState(() {
            _allCases = List<Map<String, dynamic>>.from(data['cases'] ?? []);
            _filteredCases = _filterCases(_allCases, _searchQuery);
            _isLoading = false;
          });
        } else {
          print('❌ History API returned error: ${data['message']}');
          setState(() {
            _isLoading = false;
            _allCases = [];
            _filteredCases = [];
          });
        }
      } else {
        print('❌ History API call failed with status ${response.statusCode}');
        print('❌ Response body: ${response.body}');
        setState(() {
          _isLoading = false;
          _allCases = [];
          _filteredCases = [];
        });
      }
    } catch (e) {
      print('❌ Error loading history: $e');
      setState(() {
        _isLoading = false;
        _allCases = [];
        _filteredCases = [];
      });
    }
  }

  void _toggleSort() {
    setState(() {
      _sortDescending = !_sortDescending;
      _isLoading = true;
    });
    _fetchCases();
  }

  void _onSearchChanged(String query) {
    setState(() {
      _searchQuery = query;
      _filteredCases = _filterCases(_allCases, query);
    });
  }

  List<Map<String, dynamic>> _filterCases(List<Map<String, dynamic>> cases, String query) {
    if (query.trim().isEmpty) return cases;
    final q = query.toLowerCase();
    return cases.where((c) {
      final name = '${c['patientFirstName'] ?? ''} ${c['patientLastName'] ?? ''}'.toLowerCase();
      final issue = (c['conditionNameEn'] ?? '').toString().toLowerCase();
      final date = c['recordedAt'] != null ? DateTime.parse(c['recordedAt']) : null;
      final dateStr = date != null ? DateFormat('yyyy-MM-dd').format(date) : '';
      return name.contains(q) || issue.contains(q) || dateStr.contains(q);
    }).toList();
  }

  void _onNavBarTapped(int idx) {
    setState(() => _selectedIndex = idx);
    if (idx == 0) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const HomePage()));
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
    if (i.contains('fracture') || i.contains('bone')) return FontAwesomeIcons.bone;
    if (i.contains('burn')) return FontAwesomeIcons.fire;
    if (i.contains('diabetes') || i.contains('sugar')) return FontAwesomeIcons.syringe;
    if (i.contains('stroke')) return FontAwesomeIcons.brain;
    if (i.contains('pregnancy')) return FontAwesomeIcons.baby;
    return FontAwesomeIcons.stethoscope;
  }

  Color getCaseColor(String issue) {
    final i = issue.toLowerCase();
    if (i.contains('heart')) return Colors.red;
    if (i.contains('asthma')) return Colors.teal;
    if (i.contains('fracture')) return Colors.orange;
    if (i.contains('burn')) return Colors.deepOrange;
    if (i.contains('diabetes')) return Colors.purple;
    if (i.contains('stroke')) return Colors.indigo;
    if (i.contains('pregnancy')) return Colors.pinkAccent;
    return Colors.blueGrey;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('All Cases', style: const TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF1A3B66),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            onPressed: _toggleSort,
            icon: Icon(_sortDescending ? Icons.arrow_downward : Icons.arrow_upward, color: Colors.white),
            tooltip: 'Sort by date',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: 'Search by name, condition, or date...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: Theme.of(context).cardColor,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredCases.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.folder_open, size: 64, color: Colors.grey),
                            SizedBox(height: 16),
                            Text(
                              'No cases found',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.grey),
                            ),
                            SizedBox(height: 8),
                            Text(
                              _allCases.isEmpty ? 'Create your first case to get started' : 'Try adjusting your search',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _filteredCases.length,
                        itemBuilder: (_, i) {
                          final c = _filteredCases[i];
                          final id = c['id'];
                          final name = '${c['patientFirstName'] ?? ''} ${c['patientLastName'] ?? ''}'.trim();
                          final issue = c['conditionNameEn'] ?? 'Unknown Condition';
                          final date = c['recordedAt'] != null 
                              ? DateFormat('MMM dd, yyyy').format(DateTime.parse(c['recordedAt']))
                              : 'Unknown date';
                          
                          return Card(
                            margin: EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: getCaseColor(issue).withOpacity(0.2),
                                child: FaIcon(getCaseIcon(issue), color: getCaseColor(issue), size: 20),
                              ),
                              title: Text(name.isEmpty ? 'Unnamed Patient' : name),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(issue),
                                  Text(date, style: TextStyle(fontSize: 12, color: Colors.grey)),
                                ],
                              ),
                              trailing: Icon(Icons.chevron_right, color: Colors.grey),
                              onTap: () {
                                Navigator.of(context).push(MaterialPageRoute(
                                  builder: (_) => CaseDetailsPage(caseId: id),
                                ));
                              },
                            ),
                          );
                        },
                      ),
          ),
        ],
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