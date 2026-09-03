import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;
import 'package:syncfusion_flutter_pdf/pdf.dart';

class ECGAnalyzer {
  static Future<String> extractText(PlatformFile file) async {
    final ext = file.extension?.toLowerCase();

    // Get bytes (cross-platform safe)
    final fileBytes = file.bytes ?? await File(file.path!).readAsBytes();

    if (ext == 'pdf') {
      final document = PdfDocument(inputBytes: fileBytes);
      final text = PdfTextExtractor(document).extractText();
      document.dispose();
      return text;
    }

    if (ext == 'csv' || ext == 'hea' || ext == 'dat') {
      return utf8.decode(fileBytes);
        }

    if (ext == 'jpg' || ext == 'jpeg' || ext== 'png') {
      // CHECK IF RUNNING ON WEB/DESKTOP - DISABLE OCR
      if (kIsWeb || !Platform.isAndroid && !Platform.isIOS) {
        return '[Image file detected - OCR not available on web/desktop. Please use PDF or CSV files for text extraction.]';
      }

    final Uint8List fileBytes = file.bytes ?? await File(file.path!).readAsBytes();

      // Decode image to get its dimensions
      final img.Image? decodedImage = img.decodeImage(fileBytes);
      if (decodedImage == null) return '';

      final inputImage = InputImage.fromBytes(
        bytes: fileBytes,
        metadata: InputImageMetadata(
          size: Size(decodedImage.width.toDouble(), decodedImage.height.toDouble()),
          rotation: InputImageRotation.rotation0deg,
          format: InputImageFormat.nv21, // best-effort assumption
          bytesPerRow: decodedImage.width, // assumes 1 byte per pixel
        ),
      );

      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      textRecognizer.close();

      return recognizedText.text;
    }
    return '';
  }

  
}