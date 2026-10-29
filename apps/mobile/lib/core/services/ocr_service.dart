import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class OcrService {
  final TextRecognizer _recognizer = TextRecognizer();

  Future<String?> extractText(File file) async {
    try {
      final inputImage = await _getInputImage(file);
      if (inputImage == null) return null;

      final recognized = await _recognizer.processImage(inputImage);
      return recognized.text.isNotEmpty ? recognized.text : null;
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> extractTextWithMetadata(File file) async {
    try {
      final inputImage = await _getInputImage(file);
      if (inputImage == null) return null;

      final recognized = await _recognizer.processImage(inputImage);

      if (recognized.text.isEmpty) return null;

      final blocks = recognized.blocks.map((b) => {
        'text': b.text,
        'lines': b.lines.map((l) => l.text).toList(),
        'rect': {'left': b.boundingBox.left, 'top': b.boundingBox.top, 'right': b.boundingBox.right, 'bottom': b.boundingBox.bottom},
      }).toList();

      return {
        'text': recognized.text,
        'blocks': blocks,
      };
    } catch (e) {
      return null;
    }
  }

  Future<InputImage?> _getInputImage(File file) async {
    final path = file.path;
    final ext = path.toLowerCase();

    if (ext.endsWith('.jpg') || ext.endsWith('.jpeg') ||
        ext.endsWith('.png') || ext.endsWith('.gif') ||
        ext.endsWith('.bmp') || ext.endsWith('.webp')) {
      return InputImage.fromFile(file);
    } else if (ext.endsWith('.pdf')) {
      return null;
    }

    return null;
  }

  Future<List<String>> extractKeywords(String text, {int maxKeywords = 20}) async {
    if (text.isEmpty) return [];

    final stopWords = {
      'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
      'of', 'with', 'by', 'from', 'as', 'is', 'was', 'are', 'were', 'been',
      'be', 'have', 'has', 'had', 'do', 'does', 'did', 'will', 'would',
      'could', 'should', 'may', 'might', 'must', 'shall', 'can', 'need',
      'this', 'that', 'these', 'those', 'i', 'you', 'he', 'she', 'it',
      'we', 'they', 'what', 'which', 'who', 'whom', 'whose', 'where', 'when', 'why', 'how',
    };

    final words = text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 3 && !stopWords.contains(w))
        .toList();

    final freq = <String, int>{};
    for (final w in words) {
      freq[w] = (freq[w] ?? 0) + 1;
    }

    final sorted = freq.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.take(maxKeywords).map((e) => e.key).toList();
  }

  void dispose() {
    _recognizer.close();
  }
}