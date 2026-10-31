// ==========================================
// PART 1 OF 3 (Start of Application & Logic)
// ==========================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const PipeStoreApp());
}

class PipeStoreApp extends StatelessWidget {
  const PipeStoreApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SAARI OIL FIELD SERVICES PIPE LINE',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0A2540),
          primary: const Color(0xFF0A2540),
          secondary: const Color(0xFFF25F22),
          surface: const Color(0xFFF8FAFC),
        ),
      ),
      home: const MainInventoryScreen(),
    );
  }
}

class MainInventoryScreen extends StatefulWidget {
  const MainInventoryScreen({super.key});
  @override
  State<MainInventoryScreen> createState() => _MainInventoryScreenState();
}

class _MainInventoryScreenState extends State<MainInventoryScreen> {
  int _navIndex = 0;
  List<Map<String, dynamic>> transactions = [];
  List<String> deletedTxIds = [];

  // Recycle Bin & Edit Audit Logs
  List<Map<String, dynamic>> recycleBin = [];
  List<Map<String, dynamic>> editAuditLogs = [];

  // Tombstone lists for deleted locations & JPs
  List<String> deletedLocations = [];
  List<String> deletedJpNames = [];

  List<String> receivingLocations = ['Main Yard Receiving', 'Warehouse Gate 1', 'Bay 4 Discharge'];
  List<String> issueLocations = ['Yard 1', 'Yard 2', 'Warehouse A', 'Main Site Line'];
  List<String> jpNames = ['JP-Alpha', 'JP-Beta', 'JP-North', 'JP-Pipeline-01'];

  List<String> pinnedLocations = [];
  List<String> pinnedJpNames = [];
  List<String> pinnedCategories = ['Bare Pipe'];

  String _securityPin = '1234';
  String _firebaseUrl = '';
  String _cloudStoreId = 'store_main';
  bool _isSyncing = false;
  String _lastSyncStatus = 'Not Synced';
  bool _isSettingsUnlocked = false;
  String _appDirPath = '';

  final List<String> categories = [
    'Bare Pipe', 'Bare Bend', 'Painting Bend', 'Painting Pipe',
    '3LPP Pipe', '3LPP Bend', 'Spool', 'Cut Piece',
    'Elbow', 'Flange'
  ];

  final List<String> coatingOptions = ['Internal Coated', 'Without Internal Coating'];
  String _stockSearchQuery = '';
  String _historySearchQuery = '';
  String _historyTypeFilter = 'ALL';
  String _historyCoatingFilter = 'ALL';

  DateTime? _historyStartDate;
  DateTime? _historyEndDate;
  String? _highlightedTxId;

  // Stable Form Controllers
  final TextEditingController _formSizeCtrl = TextEditingController();
  final TextEditingController _formGradeCtrl = TextEditingController();
  final TextEditingController _formSchCtrl = TextEditingController();
  final TextEditingController _formQtyCtrl = TextEditingController();
  final TextEditingController _formMetersCtrl = TextEditingController();
  final TextEditingController _formPersonCtrl = TextEditingController();
  final TextEditingController _formRemarksCtrl = TextEditingController();

  // Settings Controllers
  final TextEditingController _rLocInputCtrl = TextEditingController();
  final TextEditingController _iLocInputCtrl = TextEditingController();
  final TextEditingController _jpInputCtrl = TextEditingController();
  final TextEditingController _restoreTextCtrl = TextEditingController();
  final TextEditingController _firebaseUrlCtrl = TextEditingController();
  final TextEditingController _cloudIdCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _firebaseUrlCtrl.text = _firebaseUrl;
    _cloudIdCtrl.text = _cloudStoreId;
    _loadData().then((_) {
      _checkAndRunDailyAutoBackup();
      _cacheCompanyLogo();
      if (_firebaseUrl.isNotEmpty) _syncWithCloud(silent: true);
    });
  }

  @override
  void dispose() {
    _formSizeCtrl.dispose();
    _formGradeCtrl.dispose();
    _formSchCtrl.dispose();
    _formQtyCtrl.dispose();
    _formMetersCtrl.dispose();
    _formPersonCtrl.dispose();
    _formRemarksCtrl.dispose();
    _rLocInputCtrl.dispose();
    _iLocInputCtrl.dispose();
    _jpInputCtrl.dispose();
    _restoreTextCtrl.dispose();
    _firebaseUrlCtrl.dispose();
    _cloudIdCtrl.dispose();
    super.dispose();
  }

  void _clearFormInputs() {
    _formSizeCtrl.clear();
    _formGradeCtrl.clear();
    _formSchCtrl.clear();
    _formQtyCtrl.clear();
    _formMetersCtrl.clear();
    _formPersonCtrl.clear();
    _formRemarksCtrl.clear();
  }

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    _appDirPath = dir.path;
    return File('${dir.path}/pipe_inventory_master.json');
  }

  Future<void> _loadData() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final data = jsonDecode(await file.readAsString());
        if (!mounted) return;
        setState(() {
          transactions = List<Map<String, dynamic>>.from(data['transactions'] ?? []);
          if (data['deletedTxIds'] != null) deletedTxIds = List<String>.from(data['deletedTxIds']);
          if (data['recycleBin'] != null) recycleBin = List<Map<String, dynamic>>.from(data['recycleBin']);
          if (data['editAuditLogs'] != null) editAuditLogs = List<Map<String, dynamic>>.from(data['editAuditLogs']);
          if (data['deletedLocations'] != null) deletedLocations = List<String>.from(data['deletedLocations']);
          if (data['deletedJpNames'] != null) deletedJpNames = List<String>.from(data['deletedJpNames']);
          if (data['receivingLocations'] != null) receivingLocations = List<String>.from(data['receivingLocations']);
          if (data['issueLocations'] != null) issueLocations = List<String>.from(data['issueLocations']);
          if (data['jpNames'] != null) jpNames = List<String>.from(data['jpNames']);
          if (data['pinnedLocations'] != null) pinnedLocations = List<String>.from(data['pinnedLocations']);
          if (data['pinnedJpNames'] != null) pinnedJpNames = List<String>.from(data['pinnedJpNames']);
          if (data['pinnedCategories'] != null) pinnedCategories = List<String>.from(data['pinnedCategories']);
          if (data['securityPin'] != null) _securityPin = data['securityPin'].toString();
          if (data['firebaseUrl'] != null) {
            _firebaseUrl = data['firebaseUrl'].toString();
            _firebaseUrlCtrl.text = _firebaseUrl;
          }
          if (data['cloudStoreId'] != null) {
            _cloudStoreId = data['cloudStoreId'].toString();
            _cloudIdCtrl.text = _cloudStoreId;
          }

          receivingLocations.removeWhere((l) => deletedLocations.contains(l));
          issueLocations.removeWhere((l) => deletedLocations.contains(l));
          jpNames.removeWhere((j) => deletedJpNames.contains(j));
        });
      }
    } catch (_) {}
  }

  Future<void> _saveData() async {
    try {
      final file = await _getFile();
      await file.writeAsString(jsonEncode({
        'version': '5.0',
        'updatedAt': DateTime.now().toIso8601String(),
        'transactions': transactions,
        'deletedTxIds': deletedTxIds,
        'recycleBin': recycleBin,
        'editAuditLogs': editAuditLogs,
        'deletedLocations': deletedLocations,
        'deletedJpNames': deletedJpNames,
        'receivingLocations': receivingLocations,
        'issueLocations': issueLocations,
        'jpNames': jpNames,
        'pinnedLocations': pinnedLocations,
        'pinnedJpNames': pinnedJpNames,
        'pinnedCategories': pinnedCategories,
        'securityPin': _securityPin,
        'firebaseUrl': _firebaseUrl,
        'cloudStoreId': _cloudStoreId,
      }));
    } catch (_) {}
  }

  Future<void> _cacheCompanyLogo() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final logoFile = File('${dir.path}/saari_logo.png');
      if (!await logoFile.exists()) {
        final res = await http.get(Uri.parse('https://raw.githubusercontent.com/abrarch6548-pixel/pipe-inventory/main/logo.png')).timeout(const Duration(seconds: 8));
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          await logoFile.writeAsBytes(res.bodyBytes);
          if (mounted) setState(() {});
        }
      }
    } catch (_) {}
  }

  Future<void> _checkAndRunDailyAutoBackup() async {
    try {
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final dir = await getApplicationDocumentsDirectory();
      final backupDir = Directory('${dir.path}/Daily_Backups');
      if (!await backupDir.exists()) await backupDir.create(recursive: true);
      final todayFile = File('${backupDir.path}/auto_backup_$todayStr.json');
      if (!await todayFile.exists() && transactions.isNotEmpty) {
        await todayFile.writeAsString(jsonEncode({
          'backupDate': todayStr,
          'createdAt': DateTime.now().toIso8601String(),
          'transactions': transactions,
          'recycleBin': recycleBin,
          'editAuditLogs': editAuditLogs,
          'receivingLocations': receivingLocations,
          'issueLocations': issueLocations,
          'jpNames': jpNames,
        }));
      }
    } catch (_) {}
  }

  String _norm(dynamic s) => (s ?? '').toString().replaceAll('"', '').replaceAll("'", '').replaceAll(' ', '').trim().toLowerCase();

  bool _matchStrict(Map<String, dynamic> t, String size, String grade, String schOrClass, String coat) {
    return _norm(t['pipeSize']) == _norm(size) &&
        _norm(t['pipeGrade']) == _norm(grade) &&
        _norm(t['pipeSch'] ?? t['itemClass']) == _norm(schOrClass) &&
        _norm(t['internalCoating']) == _norm(coat);
  }

  Map<String, Map<String, double>> _calculateSpecStocks(String size, String grade, String schOrClass, String coating) {
    final Map<String, Map<String, double>> stocks = {
      for (var c in categories) c: {'qty': 0.0, 'meters': 0.0}
    };

    for (var t in transactions) {
      if (_matchStrict(t, size, grade, schOrClass, coating)) {
        double q = (t['quantity'] as num?)?.toDouble() ?? 0.0;
        double m = (t['lengthMeters'] as num?)?.toDouble() ?? 0.0;
        final cat = t['category'] ?? '';
        final type = t['type'] ?? '';

        stocks.putIfAbsent(cat, () => {'qty': 0.0, 'meters': 0.0});

        if (cat == 'Painting Pipe') {
          if (type == 'RECEIVE' || type == 'RETURN') {
            stocks['Painting Pipe']!['qty'] = stocks['Painting Pipe']!['qty']! + q;
          } else if (type == 'ISSUE') {
            double ready = stocks['Painting Pipe']!['qty']!;
            if (ready >= q) {
              stocks['Painting Pipe']!['qty'] = ready - q;
            } else {
              double rem = q - ready;
              stocks['Painting Pipe']!['qty'] = 0;
              stocks['Bare Pipe']!['qty'] = (stocks['Bare Pipe']!['qty'] ?? 0) - rem;
            }
          }
        } else if (cat == 'Painting Bend') {
          if (type == 'RECEIVE' || type == 'RETURN') {
            stocks['Painting Bend']!['qty'] = stocks['Painting Bend']!['qty']! + q;
          } else if (type == 'ISSUE') {
            double ready = stocks['Painting Bend']!['qty']!;
            if (ready >= q) {
              stocks['Painting Bend']!['qty'] = ready - q;
            } else {
              double rem = q - ready;
              stocks['Painting Bend']!['qty'] = 0;
              stocks['Bare Bend']!['qty'] = (stocks['Bare Bend']!['qty'] ?? 0) - rem;
            }
          }
        } else {
          if (type == 'RECEIVE' || type == 'RETURN') {
            stocks[cat]!['qty'] = stocks[cat]!['qty']! + q;
            stocks[cat]!['meters'] = stocks[cat]!['meters']! + m;
          } else if (type == 'ISSUE') {
            stocks[cat]!['qty'] = stocks[cat]!['qty']! - q;
            stocks[cat]!['meters'] = stocks[cat]!['meters']! - m;
          }
        }
      }
    }
    return stocks;
  }

  double _getPhysicalStockQty(String size, String grade, String schOrClass, String cat, String coating) {
    if (size.trim().isEmpty || grade.trim().isEmpty) return 0.0;
    return _calculateSpecStocks(size, grade, schOrClass, coating)[cat]?['qty'] ?? 0.0;
  }

  double _getPhysicalStockMeters(String size, String grade, String schOrClass, String cat, String coating) {
    if (size.trim().isEmpty || grade.trim().isEmpty) return 0.0;
    return _calculateSpecStocks(size, grade, schOrClass, coating)[cat]?['meters'] ?? 0.0;
  }

  double _getTotalAvailableToIssue(String size, String grade, String schOrClass, String cat, String coating) {
    if (size.trim().isEmpty || grade.trim().isEmpty) return 0.0;
    final spec = _calculateSpecStocks(size, grade, schOrClass, coating);
    if (cat == 'Painting Pipe') {
      final ready = spec['Painting Pipe']?['qty'] ?? 0.0;
      final bare = spec['Bare Pipe']?['qty'] ?? 0.0;
      return ready + (bare > 0 ? bare : 0.0);
    } else if (cat == 'Painting Bend') {
      final ready = spec['Painting Bend']?['qty'] ?? 0.0;
      final bare = spec['Bare Bend']?['qty'] ?? 0.0;
      return ready + (bare > 0 ? bare : 0.0);
    }
    return spec[cat]?['qty'] ?? 0.0;
  }

  List<String> _getSortedList(List<String> allItems, List<String> pinnedItems) {
    final list = List<String>.from(allItems);
    list.sort((a, b) {
      final aPin = pinnedItems.contains(a);
      final bPin = pinnedItems.contains(b);
      if (aPin && !bPin) return -1;
      if (!aPin && bPin) return 1;
      return a.compareTo(b);
    });
    return list;
  }
// --- PART 1 ENDS HERE (Go to Part 2) ---// ==========================================
// PART 2 OF 3 (Core Logic, Sync, Export & Dialogs)
// ==========================================

  Future<void> _exportDocument({required String reportType, required String format, List<Map<String, dynamic>>? customList}) async {
    final nowStr = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
    final printDate = DateFormat('yyyy-MM-dd hh:mm a').format(DateTime.now());
    final isPdf = format == 'PDF';
    final dir = await getApplicationDocumentsDirectory();

    if (!isPdf) {
      final StringBuffer excel = StringBuffer();
      excel.write('\uFEFF');
      excel.writeln('SAARI OIL FIELD SERVICES PIPE LINE');
      excel.writeln('Material Inventory Report - $reportType');
      excel.writeln('Date: $printDate\n');

      if (reportType == 'STOCK') {
        excel.writeln('Category,Size,Grade,SCH / Class,Coating,In-Store Balance Qty (Pcs),Length (Meters),Stock Nature');
        for (var cat in categories) {
          final specMap = <String, Map<String, String>>{};
          for (var t in transactions) {
            final s = (t['pipeSize'] ?? '').toString().trim();
            final g = (t['pipeGrade'] ?? '').toString().trim();
            final sch = (t['pipeSch'] ?? t['itemClass'] ?? '').toString().trim();
            specMap['$s|$g|$sch'] = {'size': s, 'grade': g, 'sch': sch};
          }
          for (var spec in specMap.values) {
            final s = spec['size']!; final g = spec['grade']!; final sch = spec['sch']!;
            for (var coat in coatingOptions) {
              double qty = _getPhysicalStockQty(s, g, sch, cat, coat);
              double meters = _getPhysicalStockMeters(s, g, sch, cat, coat);
              if (qty > 0 || meters > 0) {
                String note = (cat == 'Painting Pipe' || cat == 'Painting Bend') ? 'Ready in Yard' : 'Physical Stock';
                excel.writeln('"$cat","$s","$g","$sch","$coat",$qty,${meters > 0 ? meters : "-"},"$note"');
              }
            }
          }
        }
      } else {
        final list = customList ?? transactions;
        excel.writeln('Type,Date,Category,Size,Grade,SCH / Class,Coating,Quantity (Pcs),Length (Meters),Location / Person,JP Name,Remarks');
        for (var t in list) {
          if (reportType == 'RECEIVE' && t['type'] != 'RECEIVE') continue;
          if (reportType == 'ISSUE' && t['type'] != 'ISSUE') continue;
          if (reportType == 'RETURN' && t['type'] != 'RETURN') continue;

          excel.writeln('"${t['type'] ?? ''}","${t['date'] ?? ''}","${t['category'] ?? ''}","${t['pipeSize'] ?? ''}","${t['pipeGrade'] ?? ''}","${t['pipeSch'] ?? t['itemClass'] ?? ''}","${t['internalCoating'] ?? ''}",${t['quantity'] ?? 0},${(t['lengthMeters'] ?? 0) > 0 ? t['lengthMeters'] : "-"},"${(t['entity'] ?? t['location'] ?? '').toString().replaceAll('"', '""')}","${(t['jpName'] ?? '').toString().replaceAll('"', '""')}","${(t['remarks'] ?? '').toString().replaceAll('"', '""')}"');
        }
      }

      final fileName = 'SOFS_${reportType}_$nowStr.csv';
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(excel.toString());

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(children: [Icon(Icons.table_chart, color: Colors.green), SizedBox(width: 8), Text('Worksheet Ready!')]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Report file save ho gayi:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                SelectableText(file.path, style: const TextStyle(fontSize: 11, color: Colors.blueGrey)),
              ],
            ),
            actions: [
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy CSV Data'),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: excel.toString()));
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV Data clipboard mein copy ho gaya!')));
                },
              ),
              ElevatedButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      }
    } else {
      final StringBuffer html = StringBuffer();
      html.writeln('''<!DOCTYPE html><html><head><meta charset="utf-8">
      <title>SOFS - Material Report</title>
      <style>
        body { font-family: 'Segoe UI', Arial, sans-serif; margin: 25px; color: #0f172a; }
        .head { border-bottom: 3px solid #0A2540; padding-bottom: 10px; margin-bottom: 15px; display: flex; justify-content: space-between; }
        .logo-title { color: #0A2540; font-size: 22px; font-weight: 900; }
        .logo-sub { color: #F25F22; font-size: 12px; font-weight: bold; }
        table { width: 100%; border-collapse: collapse; margin-top: 10px; font-size: 12px; }
        th { background: #0A2540; color: white; padding: 8px; text-align: left; }
        td { padding: 8px; border-bottom: 1px solid #e2e8f0; }
        tr:nth-child(even) { background: #f8fafc; }
        .btn { background: #0A2540; color: white; border: none; padding: 8px 18px; font-weight: bold; border-radius: 4px; cursor: pointer; margin-bottom: 15px; }
        @media print { .no-print { display: none; } body { margin: 0; } }
      </style></head><body>
      <div class="no-print"><button class="btn" onclick="window.print()">Print / Save as PDF</button></div>
      <div class="head">
        <div><div class="logo-title">SAARI OIL FIELD SERVICES</div><div class="logo-sub">MATERIAL CONTROL & PIPELINE LOGISTICS</div></div>
        <div style="text-align:right;font-size:11px;color:#64748b;">Report: <b>$reportType</b><br>Date: $printDate</div>
      </div>''');

      if (reportType == 'STOCK') {
        html.writeln('<table><thead><tr><th>Category</th><th>Size</th><th>Grade</th><th>SCH/Class</th><th>Coating</th><th>In-Yard Qty</th><th>Meters</th><th>Status</th></tr></thead><tbody>');
        for (var cat in categories) {
          final specMap = <String, Map<String, String>>{};
          for (var t in transactions) {
            final s = (t['pipeSize'] ?? '').toString().trim();
            final g = (t['pipeGrade'] ?? '').toString().trim();
            final sch = (t['pipeSch'] ?? t['itemClass'] ?? '').toString().trim();
            specMap['$s|$g|$sch'] = {'size': s, 'grade': g, 'sch': sch};
          }
          for (var spec in specMap.values) {
            final s = spec['size']!; final g = spec['grade']!; final sch = spec['sch']!;
            for (var coat in coatingOptions) {
              double qty = _getPhysicalStockQty(s, g, sch, cat, coat);
              double meters = _getPhysicalStockMeters(s, g, sch, cat, coat);
              if (qty > 0 || meters > 0) {
                String note = (cat == 'Painting Pipe' || cat == 'Painting Bend') ? 'Ready in Yard' : 'Physical Stock';
                html.writeln('<tr><td><b>$cat</b></td><td>$s</td><td>$g</td><td>$sch</td><td>$coat</td><td><b>$qty Pcs</b></td><td>${meters > 0 ? "$meters m" : "-"}</td><td>$note</td></tr>');
              }
            }
          }
        }
      } else {
        final list = customList ?? transactions;
        html.writeln('<table><thead><tr><th>Type</th><th>Date</th><th>Category</th><th>Size</th><th>Grade</th><th>SCH/Class</th><th>Coating</th><th>Qty</th><th>Meters</th><th>Location/Person</th><th>JP</th><th>Remarks</th></tr></thead><tbody>');
        for (var t in list) {
          if (reportType == 'RECEIVE' && t['type'] != 'RECEIVE') continue;
          if (reportType == 'ISSUE' && t['type'] != 'ISSUE') continue;
          if (reportType == 'RETURN' && t['type'] != 'RETURN') continue;

          html.writeln('<tr><td><b>${t['type']}</b></td><td>${t['date']}</td><td>${t['category']}</td><td>${t['pipeSize']}</td><td>${t['pipeGrade']}</td><td>${t['pipeSch'] ?? t['itemClass'] ?? ''}</td><td>${t['internalCoating']}</td><td><b>${t['quantity']}</b></td><td>${(t['lengthMeters'] ?? 0) > 0 ? "${t['lengthMeters']}m" : "-"}</td><td>${t['entity'] ?? t['location'] ?? ''}</td><td>${t['jpName'] ?? ''}</td><td>${t['remarks'] ?? ''}</td></tr>');
        }
      }
      html.writeln('</tbody></table></body></html>');

      final file = File('${dir.path}/SOFS_${reportType}_$nowStr.html');
      await file.writeAsString(html.toString());

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(children: [Icon(Icons.picture_as_pdf, color: Colors.red), SizedBox(width: 8), Text('Printable PDF Ready!')]),
            content: SelectableText('File saved at:\n${file.path}\n\nBrowser mein open kar ke Print / Save as PDF karein.'),
            actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
      }
    }
  }

  void _showExportChoiceDialog(String reportType, {List<Map<String, dynamic>>? customList}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Export $reportType Report', style: const TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Select file format:'),
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade800),
            icon: const Icon(Icons.table_chart, color: Colors.white, size: 18),
            label: const Text('Excel Sheet', style: TextStyle(color: Colors.white)),
            onPressed: () {
              Navigator.pop(ctx);
              _exportDocument(reportType: reportType, format: 'EXCEL', customList: customList);
            },
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade800),
            icon: const Icon(Icons.picture_as_pdf, color: Colors.white, size: 18),
            label: const Text('Printable PDF', style: TextStyle(color: Colors.white)),
            onPressed: () {
              Navigator.pop(ctx);
              _exportDocument(reportType: reportType, format: 'PDF', customList: customList);
            },
          ),
        ],
      ),
    );
  }

  // FIXED: Cloud Sync prevents re-deleting restored entries
  Future<void> _syncWithCloud({bool silent = false}) async {
    if (_isSyncing) return;
    if (_firebaseUrl.trim().isEmpty) {
      if (!silent && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Pehle Settings mein Firebase URL daalein!')));
      return;
    }

    setState(() => _isSyncing = true);
    try {
      String baseUrl = _firebaseUrl.trim();
      if (!baseUrl.startsWith('http')) baseUrl = 'https://$baseUrl';
      if (baseUrl.endsWith('/')) baseUrl = baseUrl.substring(0, baseUrl.length - 1);

      final syncUri = Uri.parse('$baseUrl/$_cloudStoreId.json');
      final res = await http.get(syncUri).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200 && res.body != 'null' && res.body.isNotEmpty) {
        final remoteData = jsonDecode(res.body);
        if (remoteData is Map) {
          final remoteDeleted = List<String>.from(remoteData['deletedTxIds'] ?? []);
          
          // CRITICAL FIX: Only treat as deleted if NOT actively present locally
          final localActiveIds = transactions.map((t) => t['id'].toString()).toSet();
          final allDeleted = {...deletedTxIds, ...remoteDeleted}
              .where((id) => !localActiveIds.contains(id))
              .toList();
          deletedTxIds = allDeleted;

          final remoteDeletedLocs = List<String>.from(remoteData['deletedLocations'] ?? []);
          deletedLocations = {...deletedLocations, ...remoteDeletedLocs}.toList();

          final remoteDeletedJps = List<String>.from(remoteData['deletedJpNames'] ?? []);
          deletedJpNames = {...deletedJpNames, ...remoteDeletedJps}.toList();

          final remoteTx = List<Map<String, dynamic>>.from(remoteData['transactions'] ?? []);
          remoteTx.removeWhere((rt) => allDeleted.contains(rt['id']));

          final localMap = {for (var t in transactions) t['id']: t};
          localMap.removeWhere((id, t) => allDeleted.contains(id));

          for (var rt in remoteTx) {
            final id = rt['id'];
            if (!localMap.containsKey(id)) {
              localMap[id] = rt;
            } else {
              final localTime = DateTime.tryParse(localMap[id]!['updatedAt'] ?? '') ?? DateTime(2000);
              final remoteTime = DateTime.tryParse(rt['updatedAt'] ?? '') ?? DateTime(2000);
              if (remoteTime.isAfter(localTime)) {
                localMap[id] = rt;
              }
            }
          }

          List<String> combinedRec = {...receivingLocations, ...List<String>.from(remoteData['receivingLocations'] ?? [])}.toList();
          combinedRec.removeWhere((l) => deletedLocations.contains(l));

          List<String> combinedIss = {...issueLocations, ...List<String>.from(remoteData['issueLocations'] ?? [])}.toList();
          combinedIss.removeWhere((l) => deletedLocations.contains(l));

          List<String> combinedJp = {...jpNames, ...List<String>.from(remoteData['jpNames'] ?? [])}.toList();
          combinedJp.removeWhere((j) => deletedJpNames.contains(j));

          if (mounted) {
            setState(() {
              transactions = localMap.values.toList();
              receivingLocations = combinedRec;
              issueLocations = combinedIss;
              jpNames = combinedJp;
            });
          }
        }
      }

      await http.put(syncUri, headers: {'Content-Type': 'application/json'}, body: jsonEncode({
        'updatedAt': DateTime.now().toIso8601String(),
        'transactions': transactions,
        'deletedTxIds': deletedTxIds,
        'deletedLocations': deletedLocations,
        'deletedJpNames': deletedJpNames,
        'receivingLocations': receivingLocations,
        'issueLocations': issueLocations,
        'jpNames': jpNames,
      })).timeout(const Duration(seconds: 10));

      await _saveData();
      if (mounted) {
        setState(() => _lastSyncStatus = 'Synced at ${DateFormat('hh:mm a').format(DateTime.now())}');
        if (!silent) ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.green.shade800, content: Text('Cloud Sync Complete! (${transactions.length} entries)')));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _lastSyncStatus = 'Sync Error');
        if (!silent) ScaffoldMessenger.of(context).showSnackBar(SnackBar(backgroundColor: Colors.red.shade800, content: Text('Sync Error: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<bool> _authenticateAction(String title) async {
    final pinResult = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final pinCtrl = TextEditingController();
        String errorMsg = '';
        return StatefulBuilder(
          builder: (context, setDState) => AlertDialog(
            title: Row(children: [const Icon(Icons.lock, color: Color(0xFF0A2540)), const SizedBox(width: 8), Expanded(child: Text('PIN - $title', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)))]),
            content: TextField(
              controller: pinCtrl,
              obscureText: true,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(labelText: 'Master PIN', errorText: errorMsg.isNotEmpty ? errorMsg : null, border: const OutlineInputBorder()),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0A2540)),
                onPressed: () {
                  if (pinCtrl.text.trim() == _securityPin.trim()) {
                    Navigator.pop(ctx, true);
                  } else {
                    setDState(() => errorMsg = 'Incorrect PIN!');
                  }
                },
                child: const Text('OK', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
    return pinResult ?? false;
  }

  void _editTransactionById(String id) async {
    final index = transactions.indexWhere((item) => item['id'] == id);
    if (index == -1) return;
    if (!await _authenticateAction('Edit Record')) return;

    final t = transactions[index];
    final String type = t['type'] ?? 'RECEIVE';
    final bool isIssue = (type == 'ISSUE');
    final bool isReceive = (type == 'RECEIVE');

    final sizeCtrl = TextEditingController(text: t['pipeSize'] ?? '');
    final gradeCtrl = TextEditingController(text: t['pipeGrade'] ?? '');
    final schCtrl = TextEditingController(text: t['pipeSch'] ?? t['itemClass'] ?? '');
    final qtyCtrl = TextEditingController(text: t['quantity']?.toString() ?? '1');
    final metersCtrl = TextEditingController(text: (t['lengthMeters'] ?? 0) > 0 ? t['lengthMeters'].toString() : '');
    final remarksCtrl = TextEditingController(text: t['remarks'] ?? '');

    final personCtrl = TextEditingController(text: isReceive ? '' : (t['entity'] ?? ''));
    String rLoc = isReceive ? (t['entity'] ?? (receivingLocations.isNotEmpty ? receivingLocations.first : 'Yard')) : '';
    String iLoc = isIssue ? (t['location'] ?? (issueLocations.isNotEmpty ? issueLocations.first : 'Yard 1')) : '';
    String jName = isIssue ? (t['jpName'] ?? (jpNames.isNotEmpty ? jpNames.first : 'JP-1')) : '';

    String cat = categories.contains(t['category']) ? t['category'] : categories.first;
    String coat = coatingOptions.contains(t['internalCoating']) ? t['internalCoating'] : coatingOptions.first;
    DateTime editDate = DateTime.tryParse(t['date'] ?? '') ?? DateTime.now();

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          title: Text('Edit $type Entry', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Date: ${DateFormat('yyyy-MM-dd').format(editDate)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    TextButton.icon(
                      icon: const Icon(Icons.calendar_month, size: 16),
                      label: const Text('Change'),
                      onPressed: () async {
                        final p = await showDatePicker(context: context, initialDate: editDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
                        if (p != null) setDState(() => editDate = p);
                      },
                    ),
                  ],
                ),
                DropdownButtonFormField<String>(
                  value: cat,
                  items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setDState(() => cat = v!),
                  decoration: const InputDecoration(labelText: 'Item Category'),
                ),
                TextField(controller: sizeCtrl, decoration: const InputDecoration(labelText: 'Size')),
                TextField(controller: gradeCtrl, decoration: const InputDecoration(labelText: 'Grade')),
                TextField(controller: schCtrl, decoration: InputDecoration(labelText: (cat == 'Elbow' || cat == 'Flange') ? 'Class' : 'SCH')),
                DropdownButtonFormField<String>(
                  value: coat,
                  items: coatingOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setDState(() => coat = v!),
                  decoration: const InputDecoration(labelText: 'Coating'),
                ),
                TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity (Pcs)')),
                if (cat == 'Cut Piece') TextField(controller: metersCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Meters (Length)')),

                if (isReceive) ...[
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: receivingLocations.contains(rLoc) ? rLoc : (receivingLocations.isNotEmpty ? receivingLocations.first : null),
                    items: receivingLocations.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                    onChanged: (v) => setDState(() => rLoc = v ?? ''),
                    decoration: const InputDecoration(labelText: 'Receiving Location'),
                  ),
                ],
                if (isIssue) ...[
                  TextField(controller: personCtrl, decoration: const InputDecoration(labelText: 'Issued To (Person)')),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: issueLocations.contains(iLoc) ? iLoc : (issueLocations.isNotEmpty ? issueLocations.first : null),
                    items: issueLocations.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                    onChanged: (v) => setDState(() => iLoc = v ?? ''),
                    decoration: const InputDecoration(labelText: 'Destination Yard/Location'),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    value: jpNames.contains(jName) ? jName : (jpNames.isNotEmpty ? jpNames.first : null),
                    items: jpNames.map((j) => DropdownMenuItem(value: j, child: Text(j))).toList(),
                    onChanged: (v) => setDState(() => jName = v ?? ''),
                    decoration: const InputDecoration(labelText: 'JP Name'),
                  ),
                ],
                if (type == 'RETURN')
                  TextField(controller: personCtrl, decoration: const InputDecoration(labelText: 'Returned From (Site/Person)')),

                TextField(controller: remarksCtrl, decoration: const InputDecoration(labelText: 'Remarks')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0A2540)),
              onPressed: () {
                final newQty = double.tryParse(qtyCtrl.text) ?? 0;
                if (newQty <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Quantity valid honi chahiye!')));
                  return;
                }

                final oldTx = Map<String, dynamic>.from(transactions[index]);
                final newTx = {
                  ...transactions[index],
                  'date': DateFormat('yyyy-MM-dd').format(editDate),
                  'category': cat,
                  'pipeSize': sizeCtrl.text.trim(),
                  'pipeGrade': gradeCtrl.text.trim(),
                  'pipeSch': schCtrl.text.trim(),
                  'itemClass': (cat == 'Elbow' || cat == 'Flange') ? schCtrl.text.trim() : '',
                  'internalCoating': coat,
                  'quantity': newQty,
                  'lengthMeters': double.tryParse(metersCtrl.text) ?? 0.0,
                  'entity': isReceive ? rLoc : personCtrl.text.trim(),
                  'location': isIssue ? iLoc : '',
                  'jpName': isIssue ? jName : '',
                  'remarks': remarksCtrl.text.trim(),
                  'updatedAt': DateTime.now().toIso8601String(),
                };

                final List<Map<String, String>> diffs = [];
                final keys = [
                  {'k': 'category', 'l': 'Category'},
                  {'k': 'pipeSize', 'l': 'Size'},
                  {'k': 'pipeGrade', 'l': 'Grade'},
                  {'k': 'pipeSch', 'l': 'SCH / Class'},
                  {'k': 'internalCoating', 'l': 'Coating'},
                  {'k': 'quantity', 'l': 'Quantity'},
                  {'k': 'lengthMeters', 'l': 'Meters'},
                  {'k': 'entity', 'l': isReceive ? 'Location' : 'Person'},
                  {'k': 'location', 'l': 'Destination'},
                  {'k': 'jpName', 'l': 'JP Name'},
                  {'k': 'date', 'l': 'Date'},
                  {'k': 'remarks', 'l': 'Remarks'},
                ];

                for (var f in keys) {
                  final k = f['k']!;
                  final l = f['l']!;
                  final ov = (oldTx[k] ?? '').toString().trim();
                  final nv = (newTx[k] ?? '').toString().trim();
                  if (ov != nv) {
                    diffs.add({'field': l, 'old': ov.isEmpty ? '-' : ov, 'new': nv.isEmpty ? '-' : nv});
                  }
                }

                setState(() {
                  transactions[index] = newTx;
                  if (diffs.isNotEmpty) {
                    editAuditLogs.insert(0, {
                      'id': const Uuid().v4(),
                      'txId': id,
                      'type': type,
                      'category': cat,
                      'size': sizeCtrl.text.trim(),
                      'grade': gradeCtrl.text.trim(),
                      'editedAt': DateTime.now().toIso8601String(),
                      'changes': diffs,
                      'oldSnapshot': oldTx,
                      'newSnapshot': newTx,
                    });
                  }
                });

                _saveData();
                _syncWithCloud(silent: true);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Updated & Audit Log Created!')));
              },
              child: const Text('Save Changes', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteTransactionById(String id) async {
    if (!await _authenticateAction('Delete Record')) return;
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Move to Recycle Bin?', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
        content: const Text('Yeh entry main list se hat kar Settings ke "Recycle Bin" mein chali jayegi. Aap wahan se ise baad mein wapis RESTORE bhi kar sakte hain.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              final deletedItem = transactions.firstWhere((item) => item['id'] == id);
              setState(() {
                final trashItem = Map<String, dynamic>.from(deletedItem);
                trashItem['deletedAt'] = DateTime.now().toIso8601String();
                recycleBin.insert(0, trashItem);

                transactions.removeWhere((item) => item['id'] == id);
                if (!deletedTxIds.contains(id)) {
                  deletedTxIds.add(id);
                }
              });
              _saveData();
              _syncWithCloud(silent: true);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Moved to Recycle Bin! (Settings se restore karein)')));
            },
            child: const Text('MOVE TO TRASH', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // FIXED: Restore from Recycle Bin Function
  Future<void> _restoreFromRecycleBin(Map<String, dynamic> item) async {
    final String restoreId = item['id'].toString();

    setState(() {
      recycleBin.removeWhere((x) => x['id'].toString() == restoreId);
      deletedTxIds.removeWhere((id) => id == restoreId);

      final restoredItem = Map<String, dynamic>.from(item);
      restoredItem.remove('deletedAt');
      restoredItem['updatedAt'] = DateTime.now().toIso8601String();

      transactions.removeWhere((t) => t['id'].toString() == restoreId);
      transactions.add(restoredItem);
    });

    await _saveData();

    if (_firebaseUrl.isNotEmpty) {
      try {
        String baseUrl = _firebaseUrl.trim();
        if (!baseUrl.startsWith('http')) baseUrl = 'https://$baseUrl';
        if (baseUrl.endsWith('/')) baseUrl = baseUrl.substring(0, baseUrl.length - 1);
        final syncUri = Uri.parse('$baseUrl/$_cloudStoreId.json');

        await http.put(
          syncUri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'updatedAt': DateTime.now().toIso8601String(),
            'transactions': transactions,
            'deletedTxIds': deletedTxIds,
            'deletedLocations': deletedLocations,
            'deletedJpNames': deletedJpNames,
            'receivingLocations': receivingLocations,
            'issueLocations': issueLocations,
            'jpNames': jpNames,
          }),
        ).timeout(const Duration(seconds: 8));
      } catch (_) {}
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        backgroundColor: Colors.green.shade800,
        content: Text('Restored: ${item['category']} (${item['pipeSize']}) wapis active ho gaya!'),
      ));
    }
  }

  void _permanentDeleteFromTrash(String id) {
    setState(() {
      recycleBin.removeWhere((x) => x['id'] == id);
    });
    _saveData();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Permanently removed from Trash!')));
  }

  void _openRecycleBinAndAuditScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              backgroundColor: const Color(0xFF0A2540),
              foregroundColor: Colors.white,
              title: const Text('Recycle Bin & Edit History', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              bottom: const TabBar(
                indicatorColor: Color(0xFFF25F22),
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white60,
                tabs: [
                  Tab(icon: Icon(Icons.delete_sweep), text: 'Recycle Bin'),
                  Tab(icon: Icon(Icons.history_edu), text: 'Edit Audit Log'),
                ],
              ),
            ),
            body: TabBarView(
              children: [
                StatefulBuilder(
                  builder: (ctx, setTrashState) => recycleBin.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.delete_outline, size: 64, color: Colors.grey),
                              SizedBox(height: 8),
                              Text('Recycle Bin is Empty!', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                              Text('Deleted records yahan nazar aayenge.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(10),
                          itemCount: recycleBin.length,
                          itemBuilder: (ctx, idx) {
                            final item = recycleBin[idx];
                            final delDate = DateTime.tryParse(item['deletedAt'] ?? '') ?? DateTime.now();
                            final formattedDate = DateFormat('yyyy-MM-dd hh:mm a').format(delDate);
                            final isCut = (item['category'] == 'Cut Piece');

                            return Card(
                              elevation: 2,
                              margin: const EdgeInsets.only(bottom: 10),
                              child: Padding(
                                padding: const EdgeInsets.all(12.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                          decoration: BoxDecoration(color: Colors.red.shade100, borderRadius: BorderRadius.circular(4)),
                                          child: Text('DELETED: ${item['type']}', style: TextStyle(color: Colors.red.shade900, fontWeight: FontWeight.bold, fontSize: 11)),
                                        ),
                                        Text('Deleted: $formattedDate', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text('${item['category']} - Size: ${item['pipeSize']} | Grade: ${item['pipeGrade']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    const SizedBox(height: 2),
                                    Text('SCH/Class: ${item['pipeSch'] ?? item['itemClass'] ?? ''} | Coating: ${item['internalCoating']}', style: const TextStyle(fontSize: 12, color: Colors.black87)),
                                    Text('Qty: ${item['quantity']} Pcs ${isCut ? "(${item['lengthMeters']}m)" : ""} | Original Date: ${item['date']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                                    if ((item['entity'] ?? '').toString().isNotEmpty || (item['location'] ?? '').toString().isNotEmpty)
                                      Text('Loc/Person: ${item['entity'] ?? item['location']}${(item['jpName'] != null && item['jpName'].toString().isNotEmpty) ? " | JP: ${item['jpName']}" : ""}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                    const Divider(height: 16),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.end,
                                      children: [
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                                          icon: const Icon(Icons.delete_forever, size: 16),
                                          label: const Text('Permanent Delete', style: TextStyle(fontSize: 11)),
                                          onPressed: () {
                                            _permanentDeleteFromTrash(item['id']);
                                            setTrashState(() {});
                                            setState(() {});
                                          },
                                        ),
                                        const SizedBox(width: 8),
                                        ElevatedButton.icon(
                                          style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade800),
                                          icon: const Icon(Icons.restore, color: Colors.white, size: 16),
                                          label: const Text('Restore', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                                          onPressed: () async {
                                            await _restoreFromRecycleBin(item);
                                            setTrashState(() {});
                                            setState(() {});
                                          },
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                editAuditLogs.isEmpty
                    ? const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.edit_note, size: 64, color: Colors.grey),
                            SizedBox(height: 8),
                            Text('No Edit History Found', style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)),
                            Text('Koi bhi entry edit karne par uski before/after changes yahan dikhengi.', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.all(10),
                        itemCount: editAuditLogs.length,
                        itemBuilder: (ctx, idx) {
                          final log = editAuditLogs[idx];
                          final editTime = DateTime.tryParse(log['editedAt'] ?? '') ?? DateTime.now();
                          final formattedTime = DateFormat('yyyy-MM-dd hh:mm:ss a').format(editTime);
                          final List changes = log['changes'] ?? [];

                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.only(bottom: 10),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                        decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(4)),
                                        child: Text('${log['type']} UPDATED', style: TextStyle(color: Colors.blue.shade900, fontWeight: FontWeight.bold, fontSize: 11)),
                                      ),
                                      Text(formattedTime, style: const TextStyle(fontSize: 10, color: Colors.grey)),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text('${log['category']} (${log['size']}) - Grade: ${log['grade']}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                  const SizedBox(height: 8),
                                  Container(
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(color: Colors.amber.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.amber.shade200)),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Text('Field Changes (Pehle ➔ Ab Naya):', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0A2540))),
                                        const SizedBox(height: 4),
                                        ...changes.map((ch) => Padding(
                                              padding: const EdgeInsets.symmetric(vertical: 2.0),
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text('• ${ch['field']}: ', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                                                  Expanded(
                                                    child: RichText(
                                                      text: TextSpan(
                                                        style: const TextStyle(fontSize: 11, color: Colors.black),
                                                        children: [
                                                          TextSpan(text: '${ch['old']}', style: TextStyle(color: Colors.red.shade700, decoration: TextDecoration.lineThrough)),
                                                          const TextSpan(text: '  ➔  ', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
                                                          TextSpan(text: '${ch['new']}', style: TextStyle(color: Colors.green.shade800, fontWeight: FontWeight.bold)),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            )),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _renameLocationOrJpDialog({required bool isLocation, required String oldName}) {
    final newCtrl = TextEditingController(text: oldName);
    bool cascade = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          title: Text('Edit & Rename ${isLocation ? "Location" : "JP Name"}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: newCtrl, decoration: const InputDecoration(labelText: 'New Name', border: OutlineInputBorder())),
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: cascade,
                title: const Text('Purani tamam entries mein bhi naya naam update karein?', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                subtitle: const Text('One-click bulk update across all past records.', style: TextStyle(fontSize: 11, color: Colors.grey)),
                onChanged: (v) => setDState(() => cascade = v ?? true),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0A2540)),
              onPressed: () {
                final newName = newCtrl.text.trim();
                if (newName.isEmpty || newName == oldName) {
                  Navigator.pop(ctx);
                  return;
                }
                setState(() {
                  if (isLocation) {
                    final rIdx = receivingLocations.indexOf(oldName);
                    if (rIdx != -1) receivingLocations[rIdx] = newName;
                    final iIdx = issueLocations.indexOf(oldName);
                    if (iIdx != -1) issueLocations[iIdx] = newName;
                    final pIdx = pinnedLocations.indexOf(oldName);
                    if (pIdx != -1) pinnedLocations[pIdx] = newName;
                    deletedLocations.remove(newName);
                  } else {
                    final jIdx = jpNames.indexOf(oldName);
                    if (jIdx != -1) jpNames[jIdx] = newName;
                    final pjIdx = pinnedJpNames.indexOf(oldName);
                    if (pjIdx != -1) pinnedJpNames[pjIdx] = newName;
                    deletedJpNames.remove(newName);
                  }
                  if (cascade) {
                    for (var t in transactions) {
                      if (isLocation) {
                        if (t['entity'] == oldName) {
                          t['entity'] = newName;
                          t['updatedAt'] = DateTime.now().toIso8601String();
                        }
                        if (t['location'] == oldName) {
                          t['location'] = newName;
                          t['updatedAt'] = DateTime.now().toIso8601String();
                        }
                      } else {
                        if (t['jpName'] == oldName) {
                          t['jpName'] = newName;
                          t['updatedAt'] = DateTime.now().toIso8601String();
                        }
                      }
                    }
                  }
                });
                _saveData();
                _syncWithCloud(silent: true);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Renamed & Updated across all records!')));
              },
              child: const Text('Update & Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteLocationOrJp({required bool isLocation, required String name}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete ${isLocation ? "Location" : "JP Name"}?'),
        content: Text('Kya aap "$name" ko permanent delete karna chahte hain? Yeh cloud se bhi mit jayega aur dobara wapis nahi aayega.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() {
                if (isLocation) {
                  receivingLocations.remove(name);
                  issueLocations.remove(name);
                  pinnedLocations.remove(name);
                  if (!deletedLocations.contains(name)) {
                    deletedLocations.add(name);
                  }
                } else {
                  jpNames.remove(name);
                  pinnedJpNames.remove(name);
                  if (!deletedJpNames.contains(name)) {
                    deletedJpNames.add(name);
                  }
                }
              });
              _saveData();
              _syncWithCloud(silent: true);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Permanently Deleted: $name')));
            },
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
// --- PART 2 ENDS HERE (Go to Part 3) ---// ==========================================
// PART 3 OF 4 (UI Widgets, Monogram, Dashboard & Forms)
// ==========================================

  Widget _buildOfficialMonogram() {
    File? cachedLogo;
    if (_appDirPath.isNotEmpty) {
      final f = File('$_appDirPath/saari_logo.png');
      if (f.existsSync()) cachedLogo = f;
    }

    if (cachedLogo != null) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
            child: Image.file(cachedLogo, height: 32, fit: BoxFit.contain),
          ),
          const SizedBox(width: 8),
          const Text('SAARI OIL FIELD SERVICES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white)),
        ],
      );
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('S', style: TextStyle(color: Color(0xFF103778), fontWeight: FontWeight.w900, fontSize: 16)),
              const Text('A', style: TextStyle(color: Color(0xFF103778), fontWeight: FontWeight.w900, fontSize: 16)),
              const Text('A', style: TextStyle(color: Color(0xFFF26522), fontWeight: FontWeight.w900, fontSize: 16)),
              const Text('R', style: TextStyle(color: Color(0xFF103778), fontWeight: FontWeight.w900, fontSize: 16)),
              Stack(
                alignment: Alignment.center,
                children: [
                  const Text('I', style: TextStyle(color: Color(0xFF103778), fontWeight: FontWeight.w900, fontSize: 16)),
                  Positioned(bottom: 1, child: Icon(Icons.architecture, color: Colors.amber.shade900, size: 8)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('SAARI OIL FIELD SERVICES', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white), overflow: TextOverflow.ellipsis),
              Text('PIPE LINE INVENTORY CONTROL', style: TextStyle(fontSize: 8.5, fontWeight: FontWeight.bold, color: Color(0xFFF25F22), letterSpacing: 0.8)),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A2540),
        foregroundColor: Colors.white,
        elevation: 2,
        title: _buildOfficialMonogram(),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: _isSyncing
                ? const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
                : IconButton(icon: const Icon(Icons.cloud_sync, color: Colors.white, size: 24), tooltip: 'Sync', onPressed: () => _syncWithCloud(silent: false)),
          ),
        ],
      ),
      body: _buildCurrentScreen(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (i) async {
          if (i == 6 && !_isSettingsUnlocked) {
            if (await _authenticateAction('Open Settings')) {
              setState(() {
                _isSettingsUnlocked = true;
                _navIndex = i;
              });
            }
            return;
          }
          setState(() => _navIndex = i);
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.download), label: 'Receive'),
          NavigationDestination(icon: Icon(Icons.upload), label: 'Issue'),
          NavigationDestination(icon: Icon(Icons.assignment_return), label: 'Return'),
          NavigationDestination(icon: Icon(Icons.inventory_2), label: 'Stock'),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Settings'),
        ],
      ),
    );
  }

  Widget _buildCurrentScreen() {
    if (_navIndex == 0) return _buildDashboard();
    if (_navIndex == 1) return _buildTransactionForm('RECEIVE');
    if (_navIndex == 2) return _buildTransactionForm('ISSUE');
    if (_navIndex == 3) return _buildTransactionForm('RETURN');
    if (_navIndex == 4) return _buildStock();
    if (_navIndex == 5) return _buildHistory();
    return _buildManageAndBackup();
  }

  Widget _buildDashboard() {
    double rec = 0, iss = 0, ret = 0;
    for (var t in transactions) {
      double q = (t['quantity'] as num?)?.toDouble() ?? 0.0;
      if (t['type'] == 'RECEIVE') rec += q;
      if (t['type'] == 'ISSUE') iss += q;
      if (t['type'] == 'RETURN') ret += q;
    }
    double bal = (rec + ret) - iss;

    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Inventory KPI Summary', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0A2540))),
            Chip(
              avatar: Icon(Icons.cloud, size: 12, color: _lastSyncStatus.startsWith('Synced') ? Colors.green : Colors.blue),
              label: Text(_lastSyncStatus, style: const TextStyle(fontSize: 10)),
              backgroundColor: Colors.blue.shade50,
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 2,
          color: const Color(0xFF0A2540),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Available Physical Material in Store', style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                Text('$bal Total Pcs', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.white)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: Card(color: Colors.green.shade50, child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Total Received', style: TextStyle(fontSize: 11, color: Colors.grey)), Text('$rec Pcs', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 16))])))),
            Expanded(child: Card(color: Colors.teal.shade50, child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Total Returned', style: TextStyle(fontSize: 11, color: Colors.grey)), Text('$ret Pcs', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.teal, fontSize: 16))])))),
            Expanded(child: Card(color: Colors.orange.shade50, child: Padding(padding: const EdgeInsets.all(10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Total Issued', style: TextStyle(fontSize: 11, color: Colors.grey)), Text('$iss Pcs', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 16))])))),
          ],
        ),
        const SizedBox(height: 14),
        const Text('Recent Activities', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0A2540))),
        ...transactions.reversed.take(6).map((t) {
          IconData icon = t['type'] == 'RECEIVE' ? Icons.arrow_downward : (t['type'] == 'RETURN' ? Icons.assignment_return : Icons.arrow_upward);
          Color color = t['type'] == 'RECEIVE' ? Colors.green : (t['type'] == 'RETURN' ? Colors.teal : Colors.orange);
          final meters = (t['lengthMeters'] ?? 0) > 0 ? " (${t['lengthMeters']}m)" : "";
          return Card(
            margin: const EdgeInsets.only(top: 6),
            child: ListTile(
              leading: CircleAvatar(backgroundColor: color.withOpacity(0.12), radius: 20, child: Icon(icon, color: color, size: 20)),
              title: Text('${t['category']} (${t['pipeSize']}) - ${t['internalCoating']}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              subtitle: Text('Grade: ${t['pipeGrade']} | SCH/Class: ${t['pipeSch'] ?? t['itemClass'] ?? ''}\nQty: ${t['quantity']} Pcs$meters | Date: ${t['date']}'),
              trailing: Chip(label: Text(t['type'], style: const TextStyle(color: Colors.white, fontSize: 9)), backgroundColor: color),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTransactionForm(String type) {
    final isReceive = type == 'RECEIVE';
    final isIssue = type == 'ISSUE';
    final isReturn = type == 'RETURN';

    final sortedCats = _getSortedList(categories, pinnedCategories);
    String cat = (pinnedCategories.isNotEmpty && categories.contains(pinnedCategories.first))
        ? pinnedCategories.first
        : categories.first;

    String coat = coatingOptions.first;
    DateTime selectedDate = DateTime.now();

    final sortedRecLocs = _getSortedList(receivingLocations, pinnedLocations);
    final sortedIssLocs = _getSortedList(issueLocations, pinnedLocations);
    final sortedJps = _getSortedList(jpNames, pinnedJpNames);

    String rLoc = sortedRecLocs.isNotEmpty ? sortedRecLocs.first : 'Yard Receiving';
    String iLoc = sortedIssLocs.isNotEmpty ? sortedIssLocs.first : 'Yard 1';
    String jp = sortedJps.isNotEmpty ? sortedJps.first : 'JP-1';

    Color themeColor = isReceive ? const Color(0xFF0A2540) : (isReturn ? Colors.teal : const Color(0xFFF25F22));

    return StatefulBuilder(
      builder: (context, setSub) {
        final isElbowOrFlange = (cat == 'Elbow' || cat == 'Flange');
        final isCutPiece = (cat == 'Cut Piece');
        final curSize = _formSizeCtrl.text.trim();
        final curGrade = _formGradeCtrl.text.trim();
        final curSch = _formSchCtrl.text.trim();

        final totalAvail = isIssue ? _getTotalAvailableToIssue(curSize, curGrade, curSch, cat, coat) : 0.0;
        final readyInYard = isIssue ? _getPhysicalStockQty(curSize, curGrade, curSch, cat, coat) : 0.0;

        return ListView(
          padding: const EdgeInsets.all(14),
          children: [
            Text(isReceive ? 'Stock Receiving' : (isReturn ? 'Stock Return (Wapsi)' : 'Stock Issuing'), style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: themeColor)),
            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(color: themeColor.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Date: ${DateFormat('yyyy-MM-dd').format(selectedDate)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  TextButton.icon(
                    icon: const Icon(Icons.calendar_month, size: 16),
                    label: const Text('Change'),
                    onPressed: () async {
                      final p = await showDatePicker(context: context, initialDate: selectedDate, firstDate: DateTime(2000), lastDate: DateTime(2100));
                      if (p != null) setSub(() => selectedDate = p);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),

            DropdownButtonFormField<String>(
              value: cat,
              items: sortedCats.map((c) {
                final isPin = pinnedCategories.contains(c);
                return DropdownMenuItem(
                  value: c,
                  child: Row(
                    children: [
                      if (isPin) const Icon(Icons.star, size: 14, color: Colors.amber),
                      if (isPin) const SizedBox(width: 4),
                      Text(c, style: TextStyle(fontSize: 13, fontWeight: isPin ? FontWeight.bold : FontWeight.normal)),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (v) => setSub(() => cat = v!),
              decoration: const InputDecoration(labelText: 'Item Category (⭐ Starred is Default) *'),
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(child: TextField(controller: _formSizeCtrl, decoration: const InputDecoration(labelText: 'Size *'), onChanged: (_) => setSub(() {}))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: _formGradeCtrl, decoration: const InputDecoration(labelText: 'Grade *'), onChanged: (_) => setSub(() {}))),
              ],
            ),
            const SizedBox(height: 8),

            TextField(
              controller: _formSchCtrl,
              decoration: InputDecoration(labelText: isElbowOrFlange ? 'Class / Rating (Strict) *' : 'Pipe SCH (Strict) *'),
              onChanged: (_) => setSub(() {}),
            ),
            const SizedBox(height: 8),

            DropdownButtonFormField<String>(
              value: coat,
              items: coatingOptions.map((c) => DropdownMenuItem(value: c, child: Text(c, style: const TextStyle(fontSize: 13)))).toList(),
              onChanged: (v) => setSub(() => coat = v!),
              decoration: const InputDecoration(labelText: 'Coating *'),
            ),
            const SizedBox(height: 8),

            if (isIssue) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: totalAvail > 0 ? Colors.green.shade50 : Colors.red.shade50, borderRadius: BorderRadius.circular(6)),
                child: Text('Available: $totalAvail Pcs (Yard Ready: $readyInYard)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: totalAvail > 0 ? Colors.green.shade800 : Colors.red.shade800)),
              ),
              const SizedBox(height: 8),
            ],

            Row(
              children: [
                Expanded(child: TextField(controller: _formQtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity (Pieces) *'), onChanged: (_) => setSub(() {}))),
                if (isCutPiece) ...[
                  const SizedBox(width: 8),
                  Expanded(child: TextField(controller: _formMetersCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Kul Length (Meters) *'))),
                ],
              ],
            ),
            const SizedBox(height: 8),

            if (isReceive)
              DropdownButtonFormField<String>(
                value: sortedRecLocs.contains(rLoc) ? rLoc : (sortedRecLocs.isNotEmpty ? sortedRecLocs.first : null),
                items: sortedRecLocs.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                onChanged: (v) => setSub(() => rLoc = v!),
                decoration: const InputDecoration(labelText: 'Receiving Location *'),
              ),

            if (isIssue) ...[
              TextField(controller: _formPersonCtrl, decoration: const InputDecoration(labelText: 'Issued To / Person *')),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: sortedIssLocs.contains(iLoc) ? iLoc : (sortedIssLocs.isNotEmpty ? sortedIssLocs.first : null),
                items: sortedIssLocs.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
                onChanged: (v) => setSub(() => iLoc = v!),
                decoration: const InputDecoration(labelText: 'Destination Location *'),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: sortedJps.contains(jp) ? jp : (sortedJps.isNotEmpty ? sortedJps.first : null),
                items: sortedJps.map((j) => DropdownMenuItem(value: j, child: Text(j))).toList(),
                onChanged: (v) => setSub(() => jp = v!),
                decoration: const InputDecoration(labelText: 'JP Name *'),
              ),
            ],

            if (isReturn)
              TextField(controller: _formPersonCtrl, decoration: const InputDecoration(labelText: 'Returned From (Site / Person) *')),

            const SizedBox(height: 8),
            TextField(controller: _formRemarksCtrl, decoration: const InputDecoration(labelText: 'Remarks')),
            const SizedBox(height: 16),

            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: themeColor, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () async {
                final s = _formSizeCtrl.text.trim();
                final g = _formGradeCtrl.text.trim();
                final sch = _formSchCtrl.text.trim();
                double req = double.tryParse(_formQtyCtrl.text) ?? 0;
                double reqM = double.tryParse(_formMetersCtrl.text) ?? 0.0;

                if (s.isEmpty || g.isEmpty || req <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill mandatory fields!')));
                  return;
                }

                if (isIssue) {
                  final fresh = _getTotalAvailableToIssue(s, g, sch, cat, coat);
                  if (req > fresh) {
                    showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Insufficient Stock', style: TextStyle(color: Colors.red)), content: Text('Available only: $fresh Pcs'), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))]));
                    return;
                  }
                }

                if (!await _authenticateAction('$type Material')) return;

                setState(() {
                  transactions.add({
                    'id': const Uuid().v4(),
                    'type': type,
                    'category': cat,
                    'pipeSize': s,
                    'pipeGrade': g,
                    'pipeSch': sch,
                    'itemClass': isElbowOrFlange ? sch : '',
                    'internalCoating': coat,
                    'quantity': req,
                    'lengthMeters': reqM,
                    'entity': isReceive ? rLoc : _formPersonCtrl.text.trim(),
                    'location': isIssue ? iLoc : '',
                    'jpName': isIssue ? jp : '',
                    'date': DateFormat('yyyy-MM-dd').format(selectedDate),
                    'remarks': _formRemarksCtrl.text.trim(),
                    'updatedAt': DateTime.now().toIso8601String(),
                  });
                });
                _clearFormInputs();
                _saveData();
                _syncWithCloud(silent: true);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved: $cat $type successfully!')));
                  setState(() => _navIndex = 0);
                }
              },
              child: Text('AUTHORIZE & SUBMIT $type', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }
// --- PART 3 ENDS HERE (Go to Part 4) ---// ==========================================
// PART 4 OF 4 (Stock View, History & Settings)
// ==========================================

  Widget _buildStock() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search, size: 18), hintText: 'Search Grade, Class, Size, SCH...', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0)),
                  onChanged: (v) => setState(() => _stockSearchQuery = v.trim().toLowerCase()),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0A2540)), icon: const Icon(Icons.file_download, color: Colors.white, size: 16), label: const Text('Export', style: TextStyle(color: Colors.white)), onPressed: () => _showExportChoiceDialog('STOCK')),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: categories.map((cat) {
              final isPainted = (cat == 'Painting Pipe' || cat == 'Painting Bend');
              final isCutPiece = (cat == 'Cut Piece');
              final isElbowOrFlange = (cat == 'Elbow' || cat == 'Flange');

              final specMap = <String, Map<String, String>>{};
              for (var t in transactions) {
                final s = (t['pipeSize'] ?? '').toString().trim();
                final g = (t['pipeGrade'] ?? '').toString().trim();
                final sch = (t['pipeSch'] ?? t['itemClass'] ?? '').toString().trim();
                if (_stockSearchQuery.isEmpty || s.toLowerCase().contains(_stockSearchQuery) || g.toLowerCase().contains(_stockSearchQuery) || sch.toLowerCase().contains(_stockSearchQuery)) {
                  specMap['$s|$g|$sch'] = {'size': s, 'grade': g, 'sch': sch};
                }
              }

              final relevant = specMap.values.where((spec) {
                double c = _getPhysicalStockQty(spec['size']!, spec['grade']!, spec['sch']!, cat, 'Internal Coated');
                double u = _getPhysicalStockQty(spec['size']!, spec['grade']!, spec['sch']!, cat, 'Without Internal Coating');
                return (c > 0 || u > 0);
              }).toList();

              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ExpansionTile(
                  initiallyExpanded: relevant.isNotEmpty,
                  title: Row(
                    children: [
                      Text(cat, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0A2540))),
                      if (isPainted) ...[const SizedBox(width: 6), Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1), decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.teal)), child: const Text('Ready in Yard', style: TextStyle(fontSize: 9, color: Colors.teal, fontWeight: FontWeight.bold)))],
                    ],
                  ),
                  children: relevant.isEmpty
                      ? [const Padding(padding: EdgeInsets.all(12.0), child: Text('No stock recorded.', style: TextStyle(color: Colors.grey, fontSize: 12)))]
                      : relevant.map((spec) {
                          final s = spec['size']!; final g = spec['grade']!; final sch = spec['sch']!;
                          double c = _getPhysicalStockQty(s, g, sch, cat, 'Internal Coated');
                          double u = _getPhysicalStockQty(s, g, sch, cat, 'Without Internal Coating');
                          double cm = _getPhysicalStockMeters(s, g, sch, cat, 'Internal Coated');
                          double um = _getPhysicalStockMeters(s, g, sch, cat, 'Without Internal Coating');

                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.black12)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  Text('Size: $s | Grade: $g | ${isElbowOrFlange ? "Class" : "SCH"}: $sch', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                  Text('Total: ${c + u} Pcs', style: TextStyle(fontWeight: FontWeight.bold, color: isPainted ? Colors.teal : Colors.blueAccent)),
                                ]),
                                if (isCutPiece) Text('Length: ${cm + um} Meters', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                                const Divider(height: 10),
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  const Text('Internal Coated:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                  Text('$c Pcs${isCutPiece ? " ($cm m)" : ""}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: c > 0 ? Colors.green.shade800 : Colors.grey)),
                                ]),
                                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                                  const Text('Without Coating:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
                                  Text('$u Pcs${isCutPiece ? " ($um m)" : ""}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: u > 0 ? Colors.green.shade800 : Colors.grey)),
                                ]),
                              ],
                            ),
                          );
                        }).toList(),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildHistory() {
    final filtered = transactions.where((t) {
      if (_historyTypeFilter == 'RECEIVE' && t['type'] != 'RECEIVE') return false;
      if (_historyTypeFilter == 'ISSUE' && t['type'] != 'ISSUE') return false;
      if (_historyTypeFilter == 'RETURN' && t['type'] != 'RETURN') return false;

      if (_historyCoatingFilter != 'ALL') {
        if ((t['internalCoating'] ?? '') != _historyCoatingFilter) return false;
      }

      if (_historyStartDate != null && _historyEndDate != null) {
        final tDate = DateTime.tryParse(t['date'] ?? '');
        if (tDate != null) {
          final entryDay = DateTime(tDate.year, tDate.month, tDate.day);
          final startDay = DateTime(_historyStartDate!.year, _historyStartDate!.month, _historyStartDate!.day);
          final endDay = DateTime(_historyEndDate!.year, _historyEndDate!.month, _historyEndDate!.day);
          if (entryDay.isBefore(startDay) || entryDay.isAfter(endDay)) return false;
        }
      }

      if (_historySearchQuery.isNotEmpty) {
        final q = _historySearchQuery;
        final loc = (t['entity'] ?? t['location'] ?? '').toString().toLowerCase();
        final g = (t['pipeGrade'] ?? '').toString().toLowerCase();
        final s = (t['pipeSize'] ?? '').toString().toLowerCase();
        final sch = (t['pipeSch'] ?? t['itemClass'] ?? '').toString().toLowerCase();
        final cat = (t['category'] ?? '').toString().toLowerCase();
        final dt = (t['date'] ?? '').toString().toLowerCase();
        final coat = (t['internalCoating'] ?? '').toString().toLowerCase();
        return loc.contains(q) || g.contains(q) || s.contains(q) || sch.contains(q) || cat.contains(q) || dt.contains(q) || coat.contains(q);
      }
      return true;
    }).toList();

    final Map<String, double> summaryTotals = {};
    double cpMeters = 0.0;
    for (var t in filtered) {
      final c = t['category'] ?? 'Other';
      final q = (t['quantity'] as num?)?.toDouble() ?? 0.0;
      summaryTotals[c] = (summaryTotals[c] ?? 0.0) + q;
      if (c == 'Cut Piece') cpMeters += (t['lengthMeters'] as num?)?.toDouble() ?? 0.0;
    }

    String dateRangeLabel = (_historyStartDate != null && _historyEndDate != null)
        ? '${DateFormat('dd/MM/yy').format(_historyStartDate!)} - ${DateFormat('dd/MM/yy').format(_historyEndDate!)}'
        : 'Date Range';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search, size: 18),
                    hintText: 'Search Grade, Class, Coating...',
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    suffixIcon: _historySearchQuery.isNotEmpty ? IconButton(icon: const Icon(Icons.clear, size: 16), onPressed: () => setState(() => _historySearchQuery = '')) : null,
                  ),
                  onChanged: (v) => setState(() => _historySearchQuery = v.trim().toLowerCase()),
                ),
              ),
              const SizedBox(width: 6),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: (_historyStartDate != null) ? Colors.teal : const Color(0xFF0A2540),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                ),
                icon: const Icon(Icons.date_range, color: Colors.white, size: 16),
                label: Text(dateRangeLabel, style: const TextStyle(color: Colors.white, fontSize: 11)),
                onPressed: () async {
                  final range = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                    initialDateRange: (_historyStartDate != null && _historyEndDate != null)
                        ? DateTimeRange(start: _historyStartDate!, end: _historyEndDate!)
                        : null,
                  );
                  if (range != null) {
                    setState(() {
                      _historyStartDate = range.start;
                      _historyEndDate = range.end;
                    });
                  }
                },
              ),
              if (_historyStartDate != null)
                IconButton(
                  icon: const Icon(Icons.cancel, color: Colors.red, size: 20),
                  tooltip: 'Clear Date Filter',
                  onPressed: () => setState(() {
                    _historyStartDate = null;
                    _historyEndDate = null;
                  }),
                ),
            ],
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(label: const Text('All Types'), selected: _historyTypeFilter == 'ALL', onSelected: (_) => setState(() => _historyTypeFilter = 'ALL')),
                const SizedBox(width: 4),
                FilterChip(label: const Text('Receiving'), selected: _historyTypeFilter == 'RECEIVE', onSelected: (_) => setState(() => _historyTypeFilter = 'RECEIVE')),
                const SizedBox(width: 4),
                FilterChip(label: const Text('Issuing'), selected: _historyTypeFilter == 'ISSUE', onSelected: (_) => setState(() => _historyTypeFilter = 'ISSUE')),
                const SizedBox(width: 4),
                FilterChip(label: const Text('Returns'), selected: _historyTypeFilter == 'RETURN', onSelected: (_) => setState(() => _historyTypeFilter = 'RETURN')),
              ],
            ),
          ),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Text('Coating: ', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF0A2540))),
                FilterChip(
                  label: const Text('All Coatings', style: TextStyle(fontSize: 11)),
                  selected: _historyCoatingFilter == 'ALL',
                  onSelected: (_) => setState(() => _historyCoatingFilter = 'ALL'),
                ),
                const SizedBox(width: 4),
                FilterChip(
                  label: const Text('Internal Coated', style: TextStyle(fontSize: 11)),
                  selected: _historyCoatingFilter == 'Internal Coated',
                  selectedColor: Colors.blue.shade100,
                  onSelected: (_) => setState(() => _historyCoatingFilter = 'Internal Coated'),
                ),
                const SizedBox(width: 4),
                FilterChip(
                  label: const Text('Without Internal Coating', style: TextStyle(fontSize: 11)),
                  selected: _historyCoatingFilter == 'Without Internal Coating',
                  selectedColor: Colors.amber.shade100,
                  onSelected: (_) => setState(() => _historyCoatingFilter = 'Without Internal Coating'),
                ),
              ],
            ),
          ),
        ),

        if (summaryTotals.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(color: Colors.blueGrey.shade50, borderRadius: BorderRadius.circular(6)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text('Filtered Summary (${filtered.length} entries):', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0A2540), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2)),
                    icon: const Icon(Icons.file_download, color: Colors.white, size: 12),
                    label: const Text('Export Excel/PDF', style: TextStyle(color: Colors.white, fontSize: 10)),
                    onPressed: () => _showExportChoiceDialog(_historyTypeFilter, customList: filtered),
                  ),
                ]),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  children: summaryTotals.entries.map((e) {
                    final isCp = e.key == 'Cut Piece';
                    return Chip(visualDensity: VisualDensity.compact, label: Text('${e.key}: ${e.value.toStringAsFixed(0)} Pcs${isCp ? " ($cpMeters m)" : ""}', style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold)));
                  }).toList(),
                ),
              ],
            ),
          ),

        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No records found for this filter.'))
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final t = filtered[index];
                    final tId = t['id'];
                    final isHighlighted = (_highlightedTxId == tId);

                    IconData icon = t['type'] == 'RECEIVE' ? Icons.arrow_downward : (t['type'] == 'RETURN' ? Icons.assignment_return : Icons.arrow_upward);
                    Color color = t['type'] == 'RECEIVE' ? Colors.green : (t['type'] == 'RETURN' ? Colors.teal : Colors.orange);
                    final meters = (t['lengthMeters'] ?? 0) > 0 ? " (${t['lengthMeters']}m)" : "";

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
                      color: isHighlighted ? const Color(0xFFFEF3C7) : Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: isHighlighted ? const Color(0xFFF25F22) : Colors.black12,
                          width: isHighlighted ? 2.2 : 1,
                        ),
                      ),
                      child: InkWell(
                        onTap: () {
                          setState(() {
                            _highlightedTxId = (isHighlighted ? null : tId);
                          });
                        },
                        child: ListTile(
                          leading: CircleAvatar(backgroundColor: color.withOpacity(0.12), radius: 18, child: Icon(icon, color: color, size: 16)),
                          title: Row(
                            children: [
                              Expanded(child: Text('${t['category']} (${t['pipeSize']}) - ${t['internalCoating']}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                              if (isHighlighted)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: const Color(0xFFF25F22), borderRadius: BorderRadius.circular(4)),
                                  child: const Text('TOUCHED', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                                ),
                            ],
                          ),
                          subtitle: Text('Grade: ${t['pipeGrade']} | SCH/Class: ${t['pipeSch'] ?? t['itemClass'] ?? ''}\nQty: ${t['quantity']} Pcs$meters | Date: ${t['date']}\nLoc: ${t['entity'] ?? t['location']}${(t['jpName'] != null && t['jpName'].toString().isNotEmpty) ? ' | JP: ${t['jpName']}' : ''}', style: const TextStyle(fontSize: 11)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(icon: const Icon(Icons.edit, color: Colors.blue, size: 18), onPressed: () => _editTransactionById(tId)),
                              IconButton(icon: const Icon(Icons.delete, color: Colors.red, size: 18), onPressed: () => _deleteTransactionById(tId)),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // Settings Screen
  Widget _buildManageAndBackup() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Settings & Database', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0A2540))),
          IconButton(icon: const Icon(Icons.lock, color: Colors.red), tooltip: 'Lock', onPressed: () { setState(() { _isSettingsUnlocked = false; _navIndex = 0; }); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings Locked!'))); }),
        ]),
        const SizedBox(height: 6),

        Card(
          color: const Color(0xFFFFF7ED),
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Color(0xFFF25F22), width: 1.2)),
          child: ListTile(
            leading: const CircleAvatar(
              backgroundColor: Color(0xFFF25F22),
              child: Icon(Icons.restore_from_trash, color: Colors.white, size: 24),
            ),
            title: const Text('Recycle Bin & Edit History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0A2540))),
            subtitle: Text('Deleted items: ${recycleBin.length} | Edit Audit logs: ${editAuditLogs.length}', style: const TextStyle(fontSize: 11, color: Colors.black87)),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Color(0xFFF25F22)),
            onTap: _openRecycleBinAndAuditScreen,
          ),
        ),
        const SizedBox(height: 10),

        Card(
          color: Colors.amber.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(children: [Icon(Icons.star, color: Colors.amber, size: 20), SizedBox(width: 6), Text('Category Default Priority (Star ⭐ to Set Default)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))]),
                const SizedBox(height: 4),
                const Text('Jis category par tap karenge wo Receive/Issue form mein pehle se auto-select hogi:', style: TextStyle(fontSize: 11)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: categories.map((c) {
                    final isPin = pinnedCategories.contains(c);
                    return FilterChip(
                      avatar: Icon(isPin ? Icons.star : Icons.star_border, size: 14, color: isPin ? Colors.amber.shade900 : Colors.grey),
                      label: Text(c, style: TextStyle(fontSize: 11, fontWeight: isPin ? FontWeight.bold : FontWeight.normal)),
                      selected: isPin,
                      onSelected: (val) {
                        setState(() {
                          if (val) {
                            pinnedCategories.insert(0, c);
                          } else {
                            pinnedCategories.remove(c);
                          }
                        });
                        _saveData();
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 20),

        Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Firebase Cloud Sync', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), Text(_lastSyncStatus, style: TextStyle(fontSize: 10, color: _lastSyncStatus.startsWith('Synced') ? Colors.green.shade800 : Colors.blue))]),
                const SizedBox(height: 6),
                TextField(controller: _firebaseUrlCtrl, decoration: const InputDecoration(labelText: 'Firebase URL', border: OutlineInputBorder(), hintText: 'https://...firebaseio.com')),
                const SizedBox(height: 6),
                Row(children: [
                  Expanded(child: TextField(controller: _cloudIdCtrl, decoration: const InputDecoration(labelText: 'Branch Key', border: OutlineInputBorder()))),
                  const SizedBox(width: 8),
                  ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0A2540)), onPressed: () { setState(() { _firebaseUrl = _firebaseUrlCtrl.text.trim(); _cloudStoreId = _cloudIdCtrl.text.trim(); }); _saveData(); _syncWithCloud(silent: false); }, child: const Text('Connect', style: TextStyle(color: Colors.white))),
                ]),
              ],
            ),
          ),
        ),
        const Divider(height: 20),

        Card(
          color: Colors.amber.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Master PIN Security', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)), Text('Current: $_securityPin', style: const TextStyle(fontSize: 11))]),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0A2540)),
                onPressed: () {
                  final oCtrl = TextEditingController(); final nCtrl = TextEditingController();
                  showDialog(context: context, builder: (ctx) => AlertDialog(
                    title: const Text('Change PIN'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(controller: oCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Current PIN')),
                      TextField(controller: nCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'New PIN')),
                    ]),
                    actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), ElevatedButton(onPressed: () { if (oCtrl.text.trim() == _securityPin.trim() && nCtrl.text.trim().isNotEmpty) { setState(() => _securityPin = nCtrl.text.trim()); _saveData(); Navigator.pop(ctx); } }, child: const Text('Save'))],
                  ));
                },
                child: const Text('Change', style: TextStyle(color: Colors.white)),
              ),
            ]),
          ),
        ),
        const Divider(height: 20),

        const Text('Backup & Data Protection', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Card(
          color: Colors.green.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Daily Auto-Backup Active', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green, fontSize: 12)),
                const SizedBox(height: 6),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0A2540)),
                  icon: const Icon(Icons.download, color: Colors.white, size: 14),
                  label: const Text('Export Backup File', style: TextStyle(color: Colors.white)),
                  onPressed: () async {
                    final dir = await getApplicationDocumentsDirectory();
                    final bFile = File('${dir.path}/SOFS_Backup_${DateTime.now().millisecondsSinceEpoch}.json');
                    final str = jsonEncode({
                      'timestamp': DateTime.now().toIso8601String(),
                      'transactions': transactions,
                      'deletedTxIds': deletedTxIds,
                      'recycleBin': recycleBin,
                      'editAuditLogs': editAuditLogs,
                      'deletedLocations': deletedLocations,
                      'deletedJpNames': deletedJpNames,
                      'receivingLocations': receivingLocations,
                      'issueLocations': issueLocations,
                      'jpNames': jpNames,
                      'securityPin': _securityPin
                    });
                    await bFile.writeAsString(str);
                    Clipboard.setData(ClipboardData(text: str));
                    if (mounted) showDialog(context: context, builder: (ctx) => AlertDialog(title: const Text('Backup Saved!'), content: Text('File:\n${bFile.path}\n\nClipboard mein bhi copy ho gaya hai.'), actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))]));
                  },
                ),
                const SizedBox(height: 8),
                TextField(controller: _restoreTextCtrl, maxLines: 2, decoration: const InputDecoration(hintText: 'Paste backup JSON to restore...', border: OutlineInputBorder())),
                const SizedBox(height: 6),
                ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade800), onPressed: () async {
                  if (_restoreTextCtrl.text.isEmpty || !await _authenticateAction('Restore')) return;
                  try {
                    final data = jsonDecode(_restoreTextCtrl.text.trim());
                    setState(() {
                      if (data['transactions'] != null) transactions = List<Map<String, dynamic>>.from(data['transactions']);
                      if (data['deletedTxIds'] != null) deletedTxIds = List<String>.from(data['deletedTxIds']);
                      if (data['recycleBin'] != null) recycleBin = List<Map<String, dynamic>>.from(data['recycleBin']);
                      if (data['editAuditLogs'] != null) editAuditLogs = List<Map<String, dynamic>>.from(data['editAuditLogs']);
                      if (data['deletedLocations'] != null) deletedLocations = List<String>.from(data['deletedLocations']);
                      if (data['deletedJpNames'] != null) deletedJpNames = List<String>.from(data['deletedJpNames']);
                      if (data['receivingLocations'] != null) receivingLocations = List<String>.from(data['receivingLocations']);
                      if (data['issueLocations'] != null) issueLocations = List<String>.from(data['issueLocations']);
                      if (data['jpNames'] != null) jpNames = List<String>.from(data['jpNames']);
                    });
                    _saveData();
                    _syncWithCloud(silent: true);
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Restored Successfully!')));
                  } catch (_) {}
                }, child: const Text('Restore from Text', style: TextStyle(color: Colors.white))),
              ],
            ),
          ),
        ),
        const Divider(height: 20),

        const Text('Receiving Locations (Tap to Edit/Rename | 🗑️ to Delete)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: TextField(controller: _rLocInputCtrl, decoration: const InputDecoration(labelText: 'New Receiving Location', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0)))),
          const SizedBox(width: 6),
          IconButton(icon: const Icon(Icons.add_circle, color: Colors.blue, size: 28), onPressed: () {
            if (_rLocInputCtrl.text.isNotEmpty) {
              final newL = _rLocInputCtrl.text.trim();
              setState(() {
                receivingLocations.add(newL);
                deletedLocations.remove(newL);
              });
              _saveData();
              _syncWithCloud(silent: true);
              _rLocInputCtrl.clear();
            }
          }),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: receivingLocations.map((l) {
          final isP = pinnedLocations.contains(l);
          return Chip(
            avatar: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(isP ? Icons.star : Icons.star_border, size: 16, color: Colors.amber.shade900),
              onPressed: () { setState(() { isP ? pinnedLocations.remove(l) : pinnedLocations.add(l); }); _saveData(); },
            ),
            label: InkWell(
              onTap: () => _renameLocationOrJpDialog(isLocation: true, oldName: l),
              child: Text(l, style: const TextStyle(fontSize: 11)),
            ),
            deleteIcon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
            onDeleted: () => _deleteLocationOrJp(isLocation: true, name: l),
          );
        }).toList()),
        const Divider(height: 16),

        const Text('Issue Locations (Tap to Edit/Rename | 🗑️ to Delete)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: TextField(controller: _iLocInputCtrl, decoration: const InputDecoration(labelText: 'New Issue Location', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0)))),
          const SizedBox(width: 6),
          IconButton(icon: const Icon(Icons.add_circle, color: Colors.green, size: 28), onPressed: () {
            if (_iLocInputCtrl.text.isNotEmpty) {
              final newL = _iLocInputCtrl.text.trim();
              setState(() {
                issueLocations.add(newL);
                deletedLocations.remove(newL);
              });
              _saveData();
              _syncWithCloud(silent: true);
              _iLocInputCtrl.clear();
            }
          }),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: issueLocations.map((l) {
          final isP = pinnedLocations.contains(l);
          return Chip(
            avatar: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(isP ? Icons.star : Icons.star_border, size: 16, color: Colors.amber.shade900),
              onPressed: () { setState(() { isP ? pinnedLocations.remove(l) : pinnedLocations.add(l); }); _saveData(); },
            ),
            label: InkWell(
              onTap: () => _renameLocationOrJpDialog(isLocation: true, oldName: l),
              child: Text(l, style: const TextStyle(fontSize: 11)),
            ),
            deleteIcon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
            onDeleted: () => _deleteLocationOrJp(isLocation: true, name: l),
          );
        }).toList()),
        const Divider(height: 16),

        const Text('JP Names (Tap to Edit/Rename | 🗑️ to Delete)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Row(children: [
          Expanded(child: TextField(controller: _jpInputCtrl, decoration: const InputDecoration(labelText: 'New JP Name', border: OutlineInputBorder(), contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 0)))),
          const SizedBox(width: 6),
          IconButton(icon: const Icon(Icons.add_circle, color: Colors.orange, size: 28), onPressed: () {
            if (_jpInputCtrl.text.isNotEmpty) {
              final newJ = _jpInputCtrl.text.trim();
              setState(() {
                jpNames.add(newJ);
                deletedJpNames.remove(newJ);
              });
              _saveData();
              _syncWithCloud(silent: true);
              _jpInputCtrl.clear();
            }
          }),
        ]),
        const SizedBox(height: 6),
        Wrap(spacing: 6, children: jpNames.map((j) {
          final isP = pinnedJpNames.contains(j);
          return Chip(
            avatar: IconButton(
              padding: EdgeInsets.zero,
              icon: Icon(isP ? Icons.star : Icons.star_border, size: 16, color: Colors.amber.shade900),
              onPressed: () { setState(() { isP ? pinnedJpNames.remove(j) : pinnedJpNames.add(j); }); _saveData(); },
            ),
            label: InkWell(
              onTap: () => _renameLocationOrJpDialog(isLocation: false, oldName: j),
              child: Text(j, style: const TextStyle(fontSize: 11)),
            ),
            deleteIcon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
            onDeleted: () => _deleteLocationOrJp(isLocation: false, name: j),
          );
        }).toList()),
      ],
    );
  }
}
// ==========================================
// END OF COMPLETE APPLICATION
// ==========================================
