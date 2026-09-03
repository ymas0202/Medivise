import 'dart:convert';
import 'dart:io';
import '../utils/ecg_analyzer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:medivise/auth_service.dart';

class NewDiagnosisPage extends StatefulWidget {
  const NewDiagnosisPage({super.key});

  @override
  State<NewDiagnosisPage> createState() => _NewDiagnosisPageState();
}

class _NewDiagnosisPageState extends State<NewDiagnosisPage> {
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  final _dobCtrl = TextEditingController();
  final _additionalNotesCtrl = TextEditingController();

  bool? _isSmoker;
  bool? _chestPain;
  bool? _familyHistory;

  PlatformFile? _ecgFile;
  bool _uploading = false;

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _dobCtrl.dispose();
    _additionalNotesCtrl.dispose();
    super.dispose();
  }

  Future<void> _showExitConfirmation() async {
    final hasData = _firstNameCtrl.text.isNotEmpty ||
        _lastNameCtrl.text.isNotEmpty ||
        _dobCtrl.text.isNotEmpty ||
        _additionalNotesCtrl.text.isNotEmpty ||
        _isSmoker != null ||
        _chestPain != null ||
        _familyHistory != null ||
        _ecgFile != null;

    if (!hasData) {
      // If no data entered, just go back without warning
      Navigator.of(context).pop();
      return;
    }

    final shouldExit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancel Diagnosis?'),
        content: const Text('All entered information will be lost. Are you sure you want to cancel?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (shouldExit == true) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _pickEcgFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'csv', 'hea', 'dat'],
    );
    if (result == null || result.files.isEmpty) return;

    setState(() => _ecgFile = result.files.first);
    await _autoExtractMeta(_ecgFile!);
  }

  Future<void> _pickDob() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime(2000),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
    );

    if (pickedDate != null) {
      _dobCtrl.text = DateFormat('yyyy-MM-dd').format(pickedDate);
    }
  }

  Future<void> _autoExtractMeta(PlatformFile file) async {
    final ext = file.extension?.toLowerCase();
    if (ext == 'pdf') {
      final bytes = await File(file.path!).readAsBytes();
      final doc = PdfDocument(inputBytes: bytes);
      final text = PdfTextExtractor(doc).extractText();
      doc.dispose();
      _parseTextForPatientInfo(text);
    } else if (['jpg', 'jpeg', 'png'].contains(ext)) {
      final inputImage = InputImage.fromFilePath(file.path!);
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final recognizedText = await textRecognizer.processImage(inputImage);
      textRecognizer.close();
      _parseTextForPatientInfo(recognizedText.text);
    }
  }

  void _parseTextForPatientInfo(String text) {
    final nameMatch = RegExp(r'Name[:\s]+([A-Za-z]+)\s+([A-Za-z]+)', caseSensitive: false).firstMatch(text);
    if (nameMatch != null) {
      _firstNameCtrl.text = nameMatch.group(1)!;
      _lastNameCtrl.text = nameMatch.group(2)!;
    }
    final dobMatch = RegExp(r'DOB[:\s]+(\d{2}/\d{2}/\d{4})').firstMatch(text);
    if (dobMatch != null) _dobCtrl.text = dobMatch.group(1)!;
  }

  Future<void> _onAnalyze() async {
    // Validate required fields
    if (_firstNameCtrl.text.isEmpty || _lastNameCtrl.text.isEmpty) {
      _snack('Please enter patient name');
      return;
    }

    if (_ecgFile == null) {
      _snack('Please select an ECG file');
      return;
    }

    setState(() => _uploading = true);

    try {
      final authToken = AuthService.getToken();
      if (authToken == null) {
        _snack('Authentication required');
        setState(() => _uploading = false);
        return;
      }

      // 1. Extract text from ECG file FIRST
      print('🔍 Extracting text from ECG file...');
      String extractedText;

      try {
        extractedText = await ECGAnalyzer.extractText(_ecgFile!);
      } catch (e) {
        print('⚠️ OCR failed, using fallback: $e');
        // For testing on web, use a placeholder or file name
        extractedText = '[ECG File: ${_ecgFile!.name} - Content extraction not available on web. For full analysis, please use the mobile app.]';
      }
      
      if (extractedText.isEmpty) {
        extractedText = '[ECG File: ${_ecgFile!.name} - No text content extracted]';
      }

      print('✅ ECG text extracted successfully, length: ${extractedText.length} characters');

      // 2. Create case with ALL data including ECG content
      print('📝 Creating new case with full data...');
      
      final caseResponse = await http.post(
        Uri.parse('http://localhost:3000/api/cases'),
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'patientFirstName': _firstNameCtrl.text,
          'patientLastName': _lastNameCtrl.text,
          'patientDob': _dobCtrl.text.isEmpty ? null : _dobCtrl.text,
          'isSmoker': _isSmoker,
          'hasChestPain': _chestPain,
          'hasFamilyHistory': _familyHistory,
          'additionalNotes': _additionalNotesCtrl.text.isEmpty ? null : _additionalNotesCtrl.text,
          'ecgContent': extractedText, // ← INCLUDING ECG EXTRACTED TEXT
          'ecgFileName': _ecgFile!.name,
          'conditionNameEn': 'Analysis in Progress...',
        }),
      );

      if (caseResponse.statusCode != 201) {
        throw Exception('Failed to create case: ${caseResponse.body}');
      }

      final caseData = jsonDecode(caseResponse.body);
      final caseId = caseData['caseId'];
      
      print('✅ Case created with ID: $caseId');

      // 3. Get comprehensive AI analysis with ALL the data
      print('🤖 Getting comprehensive AI analysis...');
      
      final analysisResponse = await http.post(
        Uri.parse('http://localhost:3000/api/cases/$caseId/analyze'),
        headers: {
          'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'analyzeFullContext': true,
        }),
      );

      if (analysisResponse.statusCode != 200) {
        throw Exception('Failed to get AI analysis: ${analysisResponse.body}');
      }

      final analysisData = jsonDecode(analysisResponse.body);
      print('✅ AI analysis completed successfully');

      _snack('Analysis complete! Case saved successfully.');
      
      // Navigate back to homepage
      Navigator.of(context).pop();

    } catch (e) {
      print('❌ Analysis failed: $e');
      _snack('Analysis failed: ${e.toString()}');
    }

    setState(() => _uploading = false);
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: const Color(0xFF003366),
        automaticallyImplyLeading: false, // Remove default back button
        title: Row(children: [
          Image.asset('lib/assets/logo.png', height: 40, width: 40),
          const SizedBox(width: 12),
          Text(
            'Medivise',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 22, color: Colors.white),
          ),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white),
            onPressed: _showExitConfirmation,
            tooltip: 'Cancel',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: _Sheet(
          title: 'New Diagnosis & Patient Intake',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionHeader(text: 'Upload ECG'),
              const SizedBox(height: 8),
              OutlinedButton(
                onPressed: _uploading ? null : _pickEcgFile,
                child: _ecgFile == null ? Text('Browse Files') : Text(_ecgFile!.name),
              ),
              const SizedBox(height: 20),
              _SectionHeader(text: 'Patient Information'),
              const SizedBox(height: 8),
              _LinedTextField(controller: _firstNameCtrl, hint: 'First Name'),
              const SizedBox(height: 10),
              _LinedTextField(controller: _lastNameCtrl, hint: 'Last Name'),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: _pickDob,
                child: AbsorbPointer(
                  child: _LinedTextField(controller: _dobCtrl, hint: 'DOB (yyyy-mm-dd)'),
                ),
              ),
              const SizedBox(height: 20),
              _SectionHeader(text: 'Patient Questions'),
              _YesNoQuestion(text: 'Is the patient a smoker?', value: _isSmoker, onChanged: (v) => setState(() => _isSmoker = v)),
              _YesNoQuestion(text: 'Does the patient suffer from chest pain?', value: _chestPain, onChanged: (v) => setState(() => _chestPain = v)),
              _YesNoQuestion(text: 'Family history of heart problems?', value: _familyHistory, onChanged: (v) => setState(() => _familyHistory = v)),
              const SizedBox(height: 20),
              _SectionHeader(text: 'Additional Notes'),
              const SizedBox(height: 8),
              _LinedTextArea(
                controller: _additionalNotesCtrl,
                hint: 'Enter any additional symptoms, observations, or context that may help with diagnosis...',
                maxLines: 4,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _uploading ? null : _onAnalyze,
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF003366), padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _uploading
                    ? const CircularProgressIndicator(color: Colors.white)
                    : Text('Analyze and Chat', style: const TextStyle(fontSize: 18, color: Colors.white)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/*───────── Helper Widgets ─────────*/

class _Sheet extends StatelessWidget {
  final String title;
  final Widget child;
  const _Sheet({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(borderRadius: const BorderRadius.vertical(top: Radius.circular(12)), color: Theme.of(context).scaffoldBackgroundColor),
              child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            ),
            Padding(padding: const EdgeInsets.all(14), child: child),
          ],
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader({required this.text});

  @override
  Widget build(BuildContext context) => Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold));
}

class _LinedTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  const _LinedTextField({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade400)),
          filled: true,
          fillColor: Theme.of(context).scaffoldBackgroundColor,
        ),
      );
}

class _LinedTextArea extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;

  const _LinedTextArea({required this.controller, required this.hint, this.maxLines = 4});

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        maxLines: maxLines,
        decoration: InputDecoration(
          hintText: hint,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: Colors.grey.shade400)),
          filled: true,
          fillColor: Theme.of(context).scaffoldBackgroundColor,
          alignLabelWithHint: true,
        ),
      );
}

class _YesNoQuestion extends StatelessWidget {
  final String text;
  final bool? value;
  final ValueChanged<bool?> onChanged;

  const _YesNoQuestion({required this.text, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Expanded(child: Text(text)),
            _YesNoToggle(label: 'Yes', selected: value == true, onTap: () => onChanged(true)),
            _YesNoToggle(label: 'No', selected: value == false, onTap: () => onChanged(false)),
          ],
        ),
      );
}

class _YesNoToggle extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _YesNoToggle({required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.grey.shade500),
              color: selected ? Colors.blue.shade100 : Colors.transparent,
            ),
            child: Text(label, style: TextStyle(fontWeight: FontWeight.bold, color: selected ? Colors.blue.shade800 : Colors.grey.shade700)),
          ),
        ),
      );
}