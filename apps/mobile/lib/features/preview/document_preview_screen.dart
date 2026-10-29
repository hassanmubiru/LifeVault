import 'package:flutter/material.dart';
import 'package:file_selector/file_selector.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'dart:io';
import 'package:path/path.dart' as p;

class DocumentPreviewScreen extends StatefulWidget {
  final String documentId;
  final String filePath;
  final String title;
  final String type;

  const DocumentPreviewScreen({
    super.key,
    required this.documentId,
    required this.filePath,
    required this.title,
    required this.type,
  });

  @override
  State<DocumentPreviewScreen> createState() => _DocumentPreviewScreenState();
}

class _DocumentPreviewScreenState extends State<DocumentPreviewScreen> {
  String? _extractedText;
  bool _isLoadingOcr = false;
  bool _isLoadingPdf = false;
  List<int>? _pdfBytes;
  final _ocrService = OcrService();

  @override
  void initState() {
    super.initState();
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp'].contains(widget.type.toLowerCase())) {
      _runOcr();
    } else if (widget.type.toLowerCase() == 'pdf') {
      _loadPdf();
    }
  }

  Future<void> _runOcr() async {
    setState(() => _isLoadingOcr = true);
    try {
      final file = File(widget.filePath);
      final result = await _ocrService.extractTextWithMetadata(file);
      if (result != null && mounted) {
        setState(() {
          _extractedText = result['text'] as String;
          _isLoadingOcr = false;
        });
      } else if (mounted) {
        setState(() => _isLoadingOcr = false);
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingOcr = false);
    }
  }

  Future<void> _loadPdf() async {
    setState(() => _isLoadingPdf = true);
    try {
      final file = File(widget.filePath);
      final bytes = await file.readAsBytes();
      if (mounted) {
        setState(() {
          _pdfBytes = bytes;
          _isLoadingPdf = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoadingPdf = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (['jpg', 'jpeg', 'png', 'gif', 'bmp'].contains(widget.type.toLowerCase()))
            IconButton(
              icon: const Icon(Icons.text_snippet),
              tooltip: 'Extract text (OCR)',
              onPressed: _isLoadingOcr ? null : _runOcr,
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (['jpg', 'jpeg', 'png', 'gif', 'bmp'].contains(widget.type.toLowerCase())) {
      return _buildImagePreview();
    } else if (widget.type.toLowerCase() == 'pdf') {
      return _buildPdfPreview();
    } else if (widget.type.toLowerCase() == 'txt') {
      return _buildTextPreview();
    } else {
      return _buildUnsupportedPreview();
    }
  }

  Widget _buildImagePreview() {
    return SingleChildScrollView(
      child: Column(
        children: [
          InteractiveViewer(
            child: Image.file(File(widget.filePath), fit: BoxFit.contain),
          ),
          if (_isLoadingOcr)
            const Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            )
          else if (_extractedText != null && _extractedText!.isNotEmpty) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Extracted Text',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(_extractedText!),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPdfPreview() {
    if (_isLoadingPdf) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_pdfBytes == null) {
      return const Center(child: Text('Failed to load PDF'));
    }
    return SfPdfViewer.memory(_pdfBytes!);
  }

  Widget _buildTextPreview() {
    return FutureBuilder<String>(
      future: File(widget.filePath).readAsString(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData) {
          return const Center(child: Text('Failed to load text file'));
        }
        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: SelectableText(snapshot.data!),
        );
      },
    );
  }

  Widget _buildUnsupportedPreview() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _getFileIcon(widget.type),
            size: 80,
            color: Colors.grey,
          ),
          const SizedBox(height: 16),
          Text(
            'Preview not available for .${widget.type} files',
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Text(
            widget.filePath,
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  IconData _getFileIcon(String type) {
    switch (type.toLowerCase()) {
      case 'doc':
      case 'docx':
        return Icons.article;
      default:
        return Icons.insert_drive_file;
    }
  }
}

class OcrService {
  Future<Map<String, dynamic>?> extractTextWithMetadata(File file) async {
    try {
      final path = file.path.toLowerCase();
      if (!path.endsWith('.jpg') && !path.endsWith('.jpeg') &&
          !path.endsWith('.png') && !path.endsWith('.gif') &&
          !path.endsWith('.bmp')) {
        return null;
      }
      return null;
    } catch (e) {
      return null;
    }
  }
}