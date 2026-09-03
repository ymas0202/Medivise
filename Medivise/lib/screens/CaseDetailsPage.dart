import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:medivise/auth_service.dart';
import 'chat_page.dart';

class CaseDetailsPage extends StatefulWidget {
  final String caseId;

  const CaseDetailsPage({
    super.key,
    required this.caseId,
  });

  @override
  State<CaseDetailsPage> createState() => _CaseDetailsPageState();
}

class _CaseDetailsPageState extends State<CaseDetailsPage> {
  late Future<Map<String, dynamic>> _caseFuture;
  bool _isLoading = true;
  Map<String, dynamic>? _caseData;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _caseFuture = _fetchCaseDetails();
  }

  Future<Map<String, dynamic>> _fetchCaseDetails() async {
    try {
      final authToken = AuthService.getToken();
      if (authToken == null) {
        throw Exception('No authentication token');
      }

      final response = await http.get(
        Uri.parse('http://localhost:3000/api/cases/${widget.caseId}'),
        headers: {'Authorization': 'Bearer $authToken'},
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          final caseData = data['case'];
          
          // Debug logs
          print('🔍 CASE DATA:');
          print('• diagnosisEn: ${caseData['diagnosisEn']}');
          print('• treatment_en: ${caseData['treatment_en']}');
          print('• analysisResults: ${caseData['analysisResults']}');
          print('• conditionNameEn: ${caseData['conditionNameEn']}');
          
          setState(() {
            _caseData = caseData;
            _isLoading = false;
          });
          return caseData;
        } else {
          throw Exception(data['message'] ?? 'Failed to load case details');
        }
      } else {
        throw Exception('HTTP ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('❌ Error loading case details: $e');
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
      rethrow;
    }
  }

  void _refreshCaseData() {
    setState(() {
      _isLoading = true;
      _caseFuture = _fetchCaseDetails();
    });
  }

  String _formatDate(dynamic dateValue) {
    if (dateValue == null) return 'Date not available';
    
    try {
      if (dateValue is String) {
        try {
          final date = DateTime.parse(dateValue);
          return DateFormat('MMMM d, y').format(date);
        } catch (e) {
          return dateValue;
        }
      }
      
      if (dateValue is DateTime) {
        return DateFormat('MMMM d, y').format(dateValue);
      }
      
      return 'Date not available';
    } catch (e) {
      return 'Date not available';
    }
  }

  String _dashIfNull(dynamic value, {String suffix = ''}) {
    if (value == null) return '-';
    if (value.toString().trim().isEmpty) return '-';
    return '$value$suffix';
  }

  bool _hasVitalSigns(Map<String, dynamic> data) {
    return data['heartRate'] != null ||
           data['prInterval'] != null ||
           data['qrsDuration'] != null ||
           data['qtcInterval'] != null;
  }

  // Helper to get the actual diagnosis name - FIXED VERSION
  String _getDiagnosisName(Map<String, dynamic> data) {
    final diagnosisEn = data['diagnosisEn']?.toString() ?? '';
    final conditionNameEn = data['conditionNameEn']?.toString() ?? '';
    final analysisResults = data['analysisResults']?.toString() ?? '';

    print('🔍 DIAGNOSIS DEBUG:');
    print('• Raw diagnosisEn: "$diagnosisEn"');
    print('• Raw conditionNameEn: "$conditionNameEn"');
    print('• Raw analysisResults: "$analysisResults"');

    // List of common cardiac conditions to look for
    final cardiacConditions = [
      'Acute Myocardial Infarction',
      'Myocardial Infarction',
      'Heart Attack',
      'Cardiac Arrest',
      'Ventricular Tachycardia',
      'Ventricular Fibrillation',
      'Atrial Fibrillation',
      'Atrial Flutter',
      'Bradycardia',
      'Tachycardia',
      'Arrhythmia',
      'Myocardial Ischemia',
      'STEMI',
      'NSTEMI',
      'Heart Block',
      'Supraventricular Tachycardia',
      'Premature Ventricular Contractions',
      'Bundle Branch Block'
    ];

    // Check if diagnosisEn contains any actual medical condition
    if (diagnosisEn.isNotEmpty) {
      for (final condition in cardiacConditions) {
        if (diagnosisEn.toLowerCase().contains(condition.toLowerCase())) {
          print('✅ Found condition in diagnosisEn: $condition');
          return condition;
        }
      }

      // If diagnosisEn is generic text like "Comprehensive analysis complete", ignore it
      final lowerDiagnosis = diagnosisEn.toLowerCase();
      final isGenericText = lowerDiagnosis.contains('comprehensive analysis') ||
                           lowerDiagnosis.contains('analysis complete') ||
                           lowerDiagnosis.contains('based on') ||
                           lowerDiagnosis.contains('assessment') ||
                           lowerDiagnosis.contains('review') ||
                           lowerDiagnosis.contains('evaluation');
      
      if (isGenericText) {
        print('❌ diagnosisEn contains generic text, ignoring');
      } else if (diagnosisEn.length < 30) {
        // If it's short and not generic, use it
        print('✅ Using short diagnosisEn: $diagnosisEn');
        return diagnosisEn;
      }
    }

    // Check conditionNameEn
    if (conditionNameEn.isNotEmpty) {
      for (final condition in cardiacConditions) {
        if (conditionNameEn.toLowerCase().contains(condition.toLowerCase())) {
          print('✅ Found condition in conditionNameEn: $condition');
          return condition;
        }
      }
      
      // If conditionNameEn is short and looks like a medical term, use it
      if (conditionNameEn.length < 50 && 
          !conditionNameEn.toLowerCase().contains('analysis') &&
          !conditionNameEn.toLowerCase().contains('complete')) {
        print('✅ Using conditionNameEn: $conditionNameEn');
        return conditionNameEn;
      }
    }

    // Check analysisResults for medical conditions
    if (analysisResults.isNotEmpty) {
      for (final condition in cardiacConditions) {
        if (analysisResults.toLowerCase().contains(condition.toLowerCase())) {
          print('✅ Found condition in analysisResults: $condition');
          return condition;
        }
      }
    }

    // Final fallback - if we have ECG data but no diagnosis yet
    if (data['ecgContent'] != null && data['ecgContent'].toString().isNotEmpty) {
      print('⚠️ ECG data exists but no diagnosis found');
      return ''; // Return empty to show "Awaiting Diagnosis"
    }

    print('❌ No valid diagnosis found');
    return ''; // No diagnosis available
  }

  // Helper to clean up markdown formatting for analysis
  String _cleanAnalysisText(String analysis) {
    // Remove markdown symbols but keep the structure
    return analysis
        .replaceAll('**', '') // Remove bold markers
        .replaceAll('*', '')  // Remove italic markers
        .replaceAll('#', '')  // Remove header markers
        .replaceAll('###', '') // Remove header markers
        .replaceAll('##', '')  // Remove header markers
        .replaceAll('`', '')   // Remove code markers
        .trim();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _caseFuture,
      builder: (ctx, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading case details...'),
                ],
              ),
            ),
          );
        }

        if (snap.hasError || !snap.hasData) {
          return Scaffold(
            appBar: AppBar(
              backgroundColor: const Color(0xFF003366),
              iconTheme: const IconThemeData(color: Colors.white),
            ),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                    const SizedBox(height: 16),
                    Text(
                      'Error loading case',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.red),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      snap.error?.toString() ?? _error,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: _refreshCaseData,
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final data = snap.data!;
        final String title = data['conditionNameEn']?.toString() ?? 'Case Details';
        final diagnosisName = _getDiagnosisName(data);
        final treatmentEn = data['treatment_en']?.toString() ?? '';
        final analysisResults = data['analysisResults']?.toString() ?? '';
        final formattedDate = _formatDate(data['recordedAt']);
        final cleanAnalysis = _cleanAnalysisText(analysisResults);

        return Scaffold(
          appBar: AppBar(
            backgroundColor: const Color(0xFF003366),
            iconTheme: const IconThemeData(color: Colors.white),
            title: Text(title, style: const TextStyle(color: Colors.white)),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _refreshCaseData,
                tooltip: 'Refresh',
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Patient Information
              _InfoCard(
                title: 'Patient Information',
                children: [
                  _InfoRow(
                    label: 'Name', 
                    value: '${data['patientFirstName'] ?? ''} ${data['patientLastName'] ?? ''}'.trim().isEmpty 
                        ? '-' 
                        : '${data['patientFirstName'] ?? ''} ${data['patientLastName'] ?? ''}'.trim()
                  ),
                  _InfoRow(label: 'Date', value: formattedDate),
                  if (data['patientDob'] != null) 
                    _InfoRow(label: 'Date of Birth', value: data['patientDob'].toString()),
                  if (data['isSmoker'] != null)
                    _InfoRow(label: 'Smoker', value: data['isSmoker'] ? 'Yes' : 'No'),
                  if (data['hasChestPain'] != null)
                    _InfoRow(label: 'Chest Pain', value: data['hasChestPain'] ? 'Yes' : 'No'),
                  if (data['hasFamilyHistory'] != null)
                    _InfoRow(label: 'Family History', value: data['hasFamilyHistory'] ? 'Yes' : 'No'),
                  
                  if (data['ecgFileName'] != null)
                    _InfoRow(label: 'ECG File', value: data['ecgFileName'].toString()),
                ],
              ),
              
              const SizedBox(height: 16),

              // MEDICAL DIAGNOSIS - Just the condition name
              _InfoCard(
                title: 'Medical Diagnosis',
                children: [
                  if (diagnosisName.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: const Color(0xFF003366).withOpacity(0.05),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF003366).withOpacity(0.3)),
                      ),
                      child: Center(
                        child: Text(
                          diagnosisName,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: const Color(0xFF003366),
                            fontSize: 24,
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.orange[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange[100]!),
                      ),
                      child: Column(
                        children: [
                          const CircularProgressIndicator(
                            strokeWidth: 2, 
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.orange)
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Awaiting Diagnosis',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.orange[800],
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Chat with AI to analyze ECG data and get diagnosis',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.orange[700],
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              
              const SizedBox(height: 16),

              // TREATMENT PLAN - Emergency care instructions (GREEN background)
              if (treatmentEn.isNotEmpty)
                Column(
                  children: [
                    _InfoCard(
                      title: '🚑 Emergency Treatment Plan',
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.green[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.green[100]!),
                          ),
                          child: MarkdownBody(
                            data: treatmentEn,
                            styleSheet: MarkdownStyleSheet(
                              p: const TextStyle(fontSize: 14, height: 1.5, color: Colors.black87),
                              strong: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF2E7D32)),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),

              // AI ANALYSIS - Clean, readable format
              if (cleanAnalysis.isNotEmpty)
                Column(
                  children: [
                    _InfoCard(
                      title: '🔍 AI Analysis',
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.blue[100]!),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.analytics,
                                    color: Colors.blue[700],
                                    size: 20,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    'How this diagnosis was determined:',
                                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue[700],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  cleanAnalysis,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    height: 1.5,
                                    color: Colors.grey[800],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),

              // VITAL SIGNS
              if (_hasVitalSigns(data))
                Column(
                  children: [
                    _InfoCard(
                      title: 'Vital Signs',
                      children: [
                        _VitalsRow(
                          label: 'Heart Rate',
                          value: _dashIfNull(data['heartRate'], suffix: ' bpm'),
                        ),
                        _VitalsRow(
                          label: 'PR Interval',
                          value: _dashIfNull(data['prInterval'], suffix: ' ms'),
                        ),
                        _VitalsRow(
                          label: 'QRS Duration',
                          value: _dashIfNull(data['qrsDuration'], suffix: ' ms'),
                        ),
                        _VitalsRow(
                          label: 'QTc Interval',
                          value: _dashIfNull(data['qtcInterval'], suffix: ' ms'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                  ],
                ),

              const SizedBox(height: 24),
              
              // CHAT WITH BOT BUTTON
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF003366),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () async {
                    final chatId = data['chatId'] ?? widget.caseId;
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatPage(chatId: chatId),
                      ),
                    );
                    
                    // Refresh when returning from chat
                    if (mounted) {
                      _refreshCaseData();
                    }
                  },
                  child: Text(
                    'Chat with Medivise AI Assistant',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _InfoCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color.fromARGB(25, 0, 0, 0),
            blurRadius: 12,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF003366),
                ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: Colors.grey[700],
                  ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w400,
                  ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _VitalsRow extends StatelessWidget {
  final String label;
  final String value;

  const _VitalsRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: value == '-' ? null : 'Monospace',
                    color: value == '-' ? Colors.grey : null,
                  ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}