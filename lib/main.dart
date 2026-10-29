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
      title: 'Pipe Store Inventory',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1E3A8A),
          primary: const Color(0xFF1E3A8A),
          secondary: const Color(0xFFEA580C),
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
  List<String> receivingLocations = ['Main Yard Receiving', 'Warehouse Gate 1', 'Bay 4 Discharge'];
  List<String> issueLocations = ['Yard 1', 'Yard 2', 'Warehouse A', 'Main Site Line'];
  List<String> jpNames = ['JP-Alpha', 'JP-Beta', 'JP-North', 'JP-Pipeline-01'];

  String _securityPin = '1234';
  String _cloudStoreId = 'my_pipe_store_01';
  bool _isSyncing = false;
  String _lastSyncStatus = 'Not Synced Yet';

  final List<String> categories = [
    'Bare Pipe', 'Bare Bend', 'Painting Bend', 'Painting Pipe',
    '3LPP Pipe', '3LPP Bend', 'Spool', 'Cut Piece'
  ];

  final List<String> coatingOptions = [
    'Internal Coated', 'Without Internal Coating'
  ];

  String _stockSearchQuery = '';
  String _historySearchQuery = '';
  String _historyTypeFilter = 'ALL';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/pipe_inventory_master.json');
  }

  Future<void> _loadData() async {
    try {
      final file = await _getFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content);
        setState(() {
          transactions = List<Map<String, dynamic>>.from(data['transactions'] ?? []);
          if (data['receivingLocations'] != null) {
            receivingLocations = List<String>.from(data['receivingLocations']);
          }
          if (data['issueLocations'] != null) {
            issueLocations = List<String>.from(data['issueLocations']);
          }
          if (data['jpNames'] != null) {
            jpNames = List<String>.from(data['jpNames']);
          }
          if (data['securityPin'] != null) {
            _securityPin = data['securityPin'].toString();
          }
          if (data['cloudStoreId'] != null) {
            _cloudStoreId = data['cloudStoreId'].toString();
          }
        });
      }
    } catch (_) {}
  }

  Future<void> _saveData() async {
    try {
      final file = await _getFile();
      final payload = {
        'version': '3.4',
        'updatedAt': DateTime.now().toIso8601String(),
        'transactions': transactions,
        'receivingLocations': receivingLocations,
        'issueLocations': issueLocations,
        'jpNames': jpNames,
        'securityPin': _securityPin,
        'cloudStoreId': _cloudStoreId,
      };
      await file.writeAsString(jsonEncode(payload));
    } catch (_) {}
  }

  // --- ACCURATE REAL-TIME STOCK BALANCE ENGINE ---
  // Calculates live physical stock in yard for all categories.
  // Painting returns stay in Painting pool!
  // Painting issues first consume ready painted stock; excess consumes Bare stock.
  Map<String, double> _calculateSpecStocks(String size, String grade, String sch, String coating) {
    final Map<String, double> stocks = {for (var c in categories) c: 0.0};

    for (var t in transactions) {
      final tSize = (t['pipeSize'] ?? '').toString().trim().toLowerCase();
      final tGrade = (t['pipeGrade'] ?? '').toString().trim().toLowerCase();
      final tSch = (t['pipeSch'] ?? '').toString().trim().toLowerCase();
      final tCoat = (t['internalCoating'] ?? '').toString().trim();

      if (tSize == size.trim().toLowerCase() &&
          tGrade == grade.trim().toLowerCase() &&
          tSch == sch.trim().toLowerCase() &&
          tCoat == coating.trim()) {

        double q = (t['quantity'] as num).toDouble();
        final cat = t['category'] ?? '';
        final type = t['type'] ?? '';

        if (cat == 'Painting Pipe') {
          if (type == 'RECEIVE' || type == 'RETURN') {
            // Returned painted pipes sit in Painting Pipe pool!
            stocks['Painting Pipe'] = (stocks['Painting Pipe'] ?? 0) + q;
          } else if (type == 'ISSUE') {
            double ready = stocks['Painting Pipe'] ?? 0;
            if (ready >= q) {
              stocks['Painting Pipe'] = ready - q;
            } else {
              double rem = q - ready;
              stocks['Painting Pipe'] = 0;
              stocks['Bare Pipe'] = (stocks['Bare Pipe'] ?? 0) - rem;
            }
          }
        } else if (cat == 'Painting Bend') {
          if (type == 'RECEIVE' || type == 'RETURN') {
            // Returned painted bends sit in Painting Bend pool!
            stocks['Painting Bend'] = (stocks['Painting Bend'] ?? 0) + q;
          } else if (type == 'ISSUE') {
            double ready = stocks['Painting Bend'] ?? 0;
            if (ready >= q) {
              stocks['Painting Bend'] = ready - q;
            } else {
              double rem = q - ready;
              stocks['Painting Bend'] = 0;
              stocks['Bare Bend'] = (stocks['Bare Bend'] ?? 0) - rem;
            }
          }
        } else {
          // Standard Categories (Bare Pipe, Bare Bend, 3LPP, Spool, Cut Piece)
          if (type == 'RECEIVE' || type == 'RETURN') {
            stocks[cat] = (stocks[cat] ?? 0) + q;
          } else if (type == 'ISSUE') {
            stocks[cat] = (stocks[cat] ?? 0) - q;
          }
        }
      }
    }
    return stocks;
  }

  // Returns physical stock sitting in store for this category
  double _getPhysicalStock(String size, String grade, String sch, String cat, String coating) {
    final specStocks = _calculateSpecStocks(size, grade, sch, coating);
    return specStocks[cat] ?? 0.0;
  }

  // Returns total quantity available to issue (including bare pipes that can be painted)
  double _getTotalAvailableToIssue(String size, String grade, String sch, String cat, String coating) {
    final specStocks = _calculateSpecStocks(size, grade, sch, coating);
    if (cat == 'Painting Pipe') {
      final ready = specStocks['Painting Pipe'] ?? 0.0;
      final bare = specStocks['Bare Pipe'] ?? 0.0;
      return ready + (bare > 0 ? bare : 0.0);
    } else if (cat == 'Painting Bend') {
      final ready = specStocks['Painting Bend'] ?? 0.0;
      final bare = specStocks['Bare Bend'] ?? 0.0;
      return ready + (bare > 0 ? bare : 0.0);
    }
    return specStocks[cat] ?? 0.0;
  }

  // --- EXCEL (.CSV) & PDF (.HTML PRINTABLE) EXPORT ENGINE ---
  Future<void> _exportDocument({required String reportType, required String format, List<Map<String, dynamic>>? customList}) async {
    final nowStr = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
    final printDate = DateFormat('yyyy-MM-dd hh:mm a').format(DateTime.now());
    final isPdf = format == 'PDF';
    final ext = isPdf ? 'html' : 'csv';
    final fileName = 'Pipe_${reportType}_${isPdf ? "PDF_Report" : "Excel"}_$nowStr.$ext';

    String content = '';

    if (reportType == 'STOCK') {
      if (!isPdf) {
        final StringBuffer csv = StringBuffer();
        csv.writeln('Category,Size,Grade,SCH,Coating,In-Store Physical Balance,Notes');
        for (var cat in categories) {
          final specMap = <String, Map<String, String>>{};
          for (var t in transactions) {
            final s = (t['pipeSize'] ?? '').toString().trim();
            final g = (t['pipeGrade'] ?? '').toString().trim();
            final sch = (t['pipeSch'] ?? '').toString().trim();
            specMap['$s|$g|$sch'] = {'size': s, 'grade': g, 'sch': sch};
          }
          for (var spec in specMap.values) {
            final s = spec['size']!;
            final g = spec['grade']!;
            final sch = spec['sch']!;
            for (var coat in coatingOptions) {
              double bal = _getPhysicalStock(s, g, sch, cat, coat);
              String note = (cat == 'Painting Pipe' || cat == 'Painting Bend')
                  ? 'Returned / Ready Painted Stock in Yard'
                  : 'Unpainted Physical Stock';
              if (bal > 0) {
                csv.writeln('"$cat","$s","$g","$sch","$coat",$bal,"$note"');
              }
            }
          }
        }
        content = csv.toString();
      } else {
        final StringBuffer html = StringBuffer();
        html.writeln('''<!DOCTYPE html><html><head><meta charset="utf-8">
        <title>Pipe Store Inventory - Stock Balance Report</title>
        <style>
          body { font-family: Segoe UI, Arial, sans-serif; margin: 25px; color: #1e293b; }
          .header { border-bottom: 3px solid #1E3A8A; padding-bottom: 10px; margin-bottom: 20px; }
          h1 { color: #1E3A8A; margin: 0 0 5px 0; font-size: 24px; }
          .sub { font-size: 13px; color: #64748b; }
          table { width: 100%; border-collapse: collapse; margin-top: 15px; }
          th { background-color: #1E3A8A; color: white; padding: 10px; text-align: left; font-size: 12px; }
          td { padding: 9px 10px; border-bottom: 1px solid #e2e8f0; font-size: 12px; }
          tr:nth-child(even) { background-color: #f8fafc; }
          .bal { font-weight: bold; color: #047857; }
          .btn-print { background: #1E3A8A; color: white; border: none; padding: 10px 20px; font-weight: bold; border-radius: 6px; cursor: pointer; margin-bottom: 20px; }
          @media print { .no-print { display: none; } body { margin: 0; } }
        </style></head><body>
        <div class="no-print"><button class="btn-print" onclick="window.print()">🖨️ Print / Save as PDF</button></div>
        <div class="header">
          <h1>Pipe Store Inventory Management System</h1>
          <div class="sub">Report: <b>Live Stock Balance Sheet</b> | Date: $printDate<br><i>*Painting Pipe & Painting Bend show ready-painted pipes physically present in yard.</i></div>
        </div>
        <table><thead><tr>
          <th>Category</th><th>Size</th><th>Grade</th><th>SCH</th><th>Coating</th><th>In-Yard Physical Balance</th><th>Stock Type</th>
        </tr></thead><tbody>''');

        for (var cat in categories) {
          final specMap = <String, Map<String, String>>{};
          for (var t in transactions) {
            final s = (t['pipeSize'] ?? '').toString().trim();
            final g = (t['pipeGrade'] ?? '').toString().trim();
            final sch = (t['pipeSch'] ?? '').toString().trim();
            specMap['$s|$g|$sch'] = {'size': s, 'grade': g, 'sch': sch};
          }
          for (var spec in specMap.values) {
            final s = spec['size']!;
            final g = spec['grade']!;
            final sch = spec['sch']!;
            for (var coat in coatingOptions) {
              double bal = _getPhysicalStock(s, g, sch, cat, coat);
              String note = (cat == 'Painting Pipe' || cat == 'Painting Bend')
                  ? '<span style="color:#0284c7;font-weight:bold;">Ready Painted in Yard</span>'
                  : 'Physical Stock';
              if (bal > 0) {
                html.writeln('<tr><td><b>$cat</b></td><td>$s</td><td>$g</td><td>$sch</td><td>$coat</td><td class="bal">$bal Qty</td><td>$note</td></tr>');
              }
            }
          }
        }
        html.writeln('</tbody></table></body></html>');
        content = html.toString();
      }
    } else {
      final list = customList ?? transactions;
      if (!isPdf) {
        final StringBuffer csv = StringBuffer();
        csv.writeln('Type,Date,Category,Size,Grade,SCH,Coating,Quantity,Location / Person,JP Name,Remarks');
        for (var t in list) {
          if (reportType == 'RECEIVE' && t['type'] != 'RECEIVE') continue;
          if (reportType == 'ISSUE' && t['type'] != 'ISSUE') continue;
          if (reportType == 'RETURN' && t['type'] != 'RETURN') continue;

          final type = t['type'] ?? '';
          final date = t['date'] ?? '';
          final cat = t['category'] ?? '';
          final size = t['pipeSize'] ?? '';
          final grade = t['pipeGrade'] ?? '';
          final sch = t['pipeSch'] ?? '';
          final coat = t['internalCoating'] ?? '';
          final qty = t['quantity'] ?? 0;
          final loc = (t['entity'] ?? t['location'] ?? '').toString().replaceAll('"', '""');
          final jp = (t['jpName'] ?? '').toString().replaceAll('"', '""');
          final remarks = (t['remarks'] ?? '').toString().replaceAll('"', '""');

          csv.writeln('"$type","$date","$cat","$size","$grade","$sch","$coat",$qty,"$loc","$jp","$remarks"');
        }
        content = csv.toString();
      } else {
        final StringBuffer html = StringBuffer();
        html.writeln('''<!DOCTYPE html><html><head><meta charset="utf-8">
        <title>Pipe Store Inventory - $reportType Report</title>
        <style>
          body { font-family: Segoe UI, Arial, sans-serif; margin: 25px; color: #1e293b; }
          .header { border-bottom: 3px solid #1E3A8A; padding-bottom: 10px; margin-bottom: 20px; }
          h1 { color: #1E3A8A; margin: 0 0 5px 0; font-size: 24px; }
          .sub { font-size: 13px; color: #64748b; }
          table { width: 100%; border-collapse: collapse; margin-top: 15px; }
          th { background-color: #1E3A8A; color: white; padding: 10px; text-align: left; font-size: 12px; }
          td { padding: 9px 10px; border-bottom: 1px solid #e2e8f0; font-size: 12px; }
          tr:nth-child(even) { background-color: #f8fafc; }
          .btn-print { background: #1E3A8A; color: white; border: none; padding: 10px 20px; font-weight: bold; border-radius: 6px; cursor: pointer; margin-bottom: 20px; }
          @media print { .no-print { display: none; } body { margin: 0; } }
        </style></head><body>
        <div class="no-print"><button class="btn-print" onclick="window.print()">🖨️ Print / Save as PDF</button></div>
        <div class="header">
          <h1>Pipe Store Inventory Management System</h1>
          <div class="sub">Ledger Report: <b>$reportType</b> | Generated: $printDate | Records: ${list.length}</div>
        </div>
        <table><thead><tr>
          <th>Type</th><th>Date</th><th>Category</th><th>Size</th><th>Grade</th><th>SCH</th><th>Coating</th><th>Qty</th><th>Location / Person</th><th>JP Name</th><th>Remarks</th>
        </tr></thead><tbody>''');

        for (var t in list) {
          if (reportType == 'RECEIVE' && t['type'] != 'RECEIVE') continue;
          if (reportType == 'ISSUE' && t['type'] != 'ISSUE') continue;
          if (reportType == 'RETURN' && t['type'] != 'RETURN') continue;

          html.writeln('<tr><td><b>${t['type']}</b></td><td>${t['date']}</td><td>${t['category']}</td><td>${t['pipeSize']}</td><td>${t['pipeGrade']}</td><td>${t['pipeSch']}</td><td>${t['internalCoating']}</td><td><b>${t['quantity']}</b></td><td>${t['entity'] ?? t['location'] ?? ''}</td><td>${t['jpName'] ?? ''}</td><td>${t['remarks'] ?? ''}</td></tr>');
        }
        html.writeln('</tbody></table></body></html>');
        content = html.toString();
      }
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsString(content);

      Clipboard.setData(ClipboardData(text: content));

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Row(
              children: [
                Icon(isPdf ? Icons.picture_as_pdf : Icons.table_chart, color: isPdf ? Colors.red : Colors.green),
                const SizedBox(width: 8),
                Text(isPdf ? 'PDF / Printable Report' : 'Excel (.CSV) Exported'),
              ],
            ),
            content: Text(
              'File saved successfully:\n${file.path}\n\n${isPdf ? "Yeh file direct Browser mein open ho kar 'Print / Save as PDF' ke liye tayyar hai." : "Yeh file Microsoft Excel aur Google Sheets mein direct open hogi."}\n\nData clipboard mein bhi copy ho gaya hai.',
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export Error: $e')));
      }
    }
  }

  void _showExportChoiceDialog(String reportType, {List<Map<String, dynamic>>? customList}) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Export $reportType Report', style: const TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Aap kis format mein export karna chahte hain?'),
        actions: [
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade800),
            icon: const Icon(Icons.table_chart, color: Colors.white, size: 18),
            label: const Text('Excel (.csv)', style: TextStyle(color: Colors.white)),
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

  // --- ONLINE CLOUD DATABASE SYNC ENGINE ---
  Future<void> _syncWithCloud() async {
    if (_isSyncing) return;
    setState(() => _isSyncing = true);

    try {
      final syncUrl = Uri.parse('https://kvdb.io/7v99E2F4gqC1Fj7746zQfH/$_cloudStoreId');
      final response = await http.get(syncUrl).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200 && response.body.isNotEmpty) {
        final remoteData = jsonDecode(response.body);
        final remoteTxList = List<Map<String, dynamic>>.from(remoteData['transactions'] ?? []);

        final localMap = {for (var t in transactions) t['id']: t};
        for (var rt in remoteTxList) {
          localMap[rt['id']] = rt;
        }

        setState(() {
          transactions = localMap.values.toList();
          if (remoteData['receivingLocations'] != null) {
            receivingLocations = List<String>.from({...receivingLocations, ...remoteData['receivingLocations']});
          }
          if (remoteData['issueLocations'] != null) {
            issueLocations = List<String>.from({...issueLocations, ...remoteData['issueLocations']});
          }
          if (remoteData['jpNames'] != null) {
            jpNames = List<String>.from({...jpNames, ...remoteData['jpNames']});
          }
        });
      }

      final uploadPayload = {
        'updatedAt': DateTime.now().toIso8601String(),
        'transactions': transactions,
        'receivingLocations': receivingLocations,
        'issueLocations': issueLocations,
        'jpNames': jpNames,
      };

      await http.post(syncUrl, body: jsonEncode(uploadPayload)).timeout(const Duration(seconds: 8));
      await _saveData();

      setState(() {
        _lastSyncStatus = 'Synced at ${DateFormat('hh:mm a').format(DateTime.now())}';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cloud Sync Successful! ($_lastSyncStatus)')),
        );
      }
    } catch (e) {
      setState(() {
        _lastSyncStatus = 'Offline (Saved Locally)';
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cloud Notice: Saved locally. Will sync when connected.')),
        );
      }
    } finally {
      setState(() => _isSyncing = false);
    }
  }

  Future<bool> _authenticateAction(String actionTitle) async {
    final pinResult = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final pinCtrl = TextEditingController();
        String errorMsg = '';
        return StatefulBuilder(
          builder: (context, setDState) => AlertDialog(
            title: Row(
              children: [
                const Icon(Icons.lock, color: Color(0xFF1E3A8A)),
                const SizedBox(width: 8),
                Expanded(child: Text('Security Lock - $actionTitle', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Please enter authorization PIN to proceed:'),
                const SizedBox(height: 12),
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Master PIN (Default: 1234)',
                    errorText: errorMsg.isNotEmpty ? errorMsg : null,
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.pin),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A)),
                onPressed: () {
                  if (pinCtrl.text.trim() == _securityPin.trim()) {
                    Navigator.pop(ctx, true);
                  } else {
                    setDState(() => errorMsg = 'Incorrect PIN!');
                  }
                },
                child: const Text('Authorize', style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      },
    );
    return pinResult ?? false;
  }

  void _deleteTransactionById(String id) async {
    final authorized = await _authenticateAction('Delete Entry');
    if (!authorized) return;

    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Entry Confirmation', style: TextStyle(color: Colors.red)),
        content: const Text('Are you sure you want to delete this entry? Stock balance will update automatically.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              setState(() {
                transactions.removeWhere((item) => item['id'] == id);
              });
              _saveData();
              _syncWithCloud();
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entry deleted & synced!')));
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _editTransactionById(String id) async {
    final index = transactions.indexWhere((item) => item['id'] == id);
    if (index == -1) return;

    final authorized = await _authenticateAction('Edit Entry');
    if (!authorized) return;

    if (!mounted) return;
    final t = transactions[index];
    final sizeCtrl = TextEditingController(text: t['pipeSize'] ?? '');
    final gradeCtrl = TextEditingController(text: t['pipeGrade'] ?? '');
    final schCtrl = TextEditingController(text: t['pipeSch'] ?? '');
    final qtyCtrl = TextEditingController(text: t['quantity']?.toString() ?? '1');
    final entityCtrl = TextEditingController(text: t['entity'] ?? '');
    final remarksCtrl = TextEditingController(text: t['remarks'] ?? '');
    String cat = t['category'] ?? categories.first;
    String coat = t['internalCoating'] ?? coatingOptions.first;
    DateTime editDate = DateTime.tryParse(t['date'] ?? '') ?? DateTime.now();

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          title: Text('Edit ${t['type']} Entry', style: const TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Date: ${DateFormat('yyyy-MM-dd').format(editDate)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.calendar_month, color: Color(0xFF1E3A8A)),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: editDate,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) setDState(() => editDate = picked);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                TextField(controller: sizeCtrl, decoration: const InputDecoration(labelText: 'Pipe Size')),
                TextField(controller: gradeCtrl, decoration: const InputDecoration(labelText: 'Pipe Grade')),
                TextField(controller: schCtrl, decoration: const InputDecoration(labelText: 'Pipe SCH')),
                DropdownButtonFormField<String>(
                  value: cat,
                  items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setDState(() => cat = v!),
                  decoration: const InputDecoration(labelText: 'Category'),
                ),
                DropdownButtonFormField<String>(
                  value: coat,
                  items: coatingOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setDState(() => coat = v!),
                  decoration: const InputDecoration(labelText: 'Coating'),
                ),
                TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity')),
                TextField(controller: entityCtrl, decoration: InputDecoration(labelText: t['type'] == 'RECEIVE' ? 'Receiving Location' : (t['type'] == 'RETURN' ? 'Returned From' : 'Issued To'))),
                TextField(controller: remarksCtrl, decoration: const InputDecoration(labelText: 'Remarks / Reason')),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final newQty = double.tryParse(qtyCtrl.text) ?? 0;
                if (newQty <= 0) return;
                setState(() {
                  transactions[index]['date'] = DateFormat('yyyy-MM-dd').format(editDate);
                  transactions[index]['pipeSize'] = sizeCtrl.text.trim();
                  transactions[index]['pipeGrade'] = gradeCtrl.text.trim();
                  transactions[index]['pipeSch'] = schCtrl.text.trim();
                  transactions[index]['category'] = cat;
                  transactions[index]['internalCoating'] = coat;
                  transactions[index]['quantity'] = newQty;
                  transactions[index]['entity'] = entityCtrl.text.trim();
                  transactions[index]['remarks'] = remarksCtrl.text.trim();
                });
                _saveData();
                _syncWithCloud();
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entry updated & synced!')));
              },
              child: const Text('Save Changes'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pipe Store Inventory', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: const Color(0xFF1E3A8A),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: _isSyncing
                ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
                : IconButton(
                    icon: const Icon(Icons.cloud_sync, color: Colors.white, size: 28),
                    tooltip: 'Sync Mobile & PC Data',
                    onPressed: _syncWithCloud,
                  ),
          ),
        ],
      ),
      body: _buildCurrentScreen(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (i) => setState(() => _navIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.download), label: 'Receive'),
          NavigationDestination(icon: Icon(Icons.upload), label: 'Issue'),
          NavigationDestination(icon: Icon(Icons.assignment_return), label: 'Return'),
          NavigationDestination(icon: Icon(Icons.inventory_2), label: 'Stock'),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
          NavigationDestination(icon: Icon(Icons.settings), label: 'Manage & Reports'),
        ],
      ),
    );
  }

  Widget _buildCurrentScreen() {
    if (_navIndex == 0) return _buildDashboard();
    if (_navIndex == 1) return _buildReceiving();
    if (_navIndex == 2) return _buildIssuing();
    if (_navIndex == 3) return _buildReturning();
    if (_navIndex == 4) return _buildStock();
    if (_navIndex == 5) return _buildHistory();
    return _buildManageAndBackup();
  }

  Widget _buildDashboard() {
    double received = 0;
    double issued = 0;
    double returned = 0;

    for (var t in transactions) {
      double q = (t['quantity'] as num).toDouble();
      if (t['type'] == 'RECEIVE') received += q;
      if (t['type'] == 'ISSUE') issued += q;
      if (t['type'] == 'RETURN') returned += q;
    }
    double balance = (received + returned) - issued;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Store Inventory Overview', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            Chip(
              avatar: const Icon(Icons.cloud, size: 16, color: Colors.blue),
              label: Text(_lastSyncStatus, style: const TextStyle(fontSize: 11)),
              backgroundColor: Colors.blue.shade50,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Current Total Available Physical Stock in Store', style: TextStyle(color: Colors.grey)),
                Text('$balance Qty', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Color(0xFF1E3A8A))),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Card(
                color: Colors.green.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Received', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text('$received', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Card(
                color: Colors.teal.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Returned', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text('$returned', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: Card(
                color: Colors.orange.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Total Issued', style: TextStyle(color: Colors.grey, fontSize: 12)),
                      Text('$issued', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Recent Activities', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        ...transactions.reversed.take(5).map((t) {
          IconData icon;
          Color color;
          if (t['type'] == 'RECEIVE') {
            icon = Icons.arrow_downward;
            color = Colors.green;
          } else if (t['type'] == 'RETURN') {
            icon = Icons.assignment_return;
            color = Colors.teal;
          } else {
            icon = Icons.arrow_upward;
            color = Colors.orange;
          }

          return Card(
            child: ListTile(
              leading: Icon(icon, color: color),
              title: Text('${t['category']} (${t['pipeSize']}) - ${t['internalCoating']}'),
              subtitle: Text('Grade: ${t['pipeGrade']} | SCH: ${t['pipeSch']}\nQty: ${t['quantity']} | Date: ${t['date']}'),
              trailing: Chip(
                label: Text(t['type'], style: const TextStyle(color: Colors.white, fontSize: 11)),
                backgroundColor: color,
              ),
            ),
          );
        }),
      ],
    );
  }

  // --- 1. RECEIVING MODULE ---
  Widget _buildReceiving() {
    final sizeCtrl = TextEditingController();
    final gradeCtrl = TextEditingController();
    final schCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final remarksCtrl = TextEditingController();
    String cat = categories.first;
    String coat = coatingOptions.first;
    String rLoc = receivingLocations.isNotEmpty ? receivingLocations.first : 'Yard Receiving';
    DateTime selectedDate = DateTime.now();

    return StatefulBuilder(
      builder: (context, setSub) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Stock Receiving Module', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blue.shade200)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Receiving Date (Auto-filled)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text(DateFormat('yyyy-MM-dd').format(selectedDate), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A)),
                    icon: const Icon(Icons.calendar_month, color: Colors.white, size: 18),
                    label: const Text('Change Date', style: TextStyle(color: Colors.white)),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setSub(() => selectedDate = picked);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: sizeCtrl, decoration: const InputDecoration(labelText: 'Pipe Size (e.g., 24") *')),
            TextField(controller: gradeCtrl, decoration: const InputDecoration(labelText: 'Pipe Grade (e.g., X52, X65) *')),
            TextField(controller: schCtrl, decoration: const InputDecoration(labelText: 'Pipe SCH (e.g., 12.7, SCH 80) *')),
            DropdownButtonFormField<String>(
              value: cat,
              items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setSub(() => cat = v!),
              decoration: const InputDecoration(labelText: 'Category *'),
            ),
            DropdownButtonFormField<String>(
              value: coat,
              items: coatingOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setSub(() => coat = v!),
              decoration: const InputDecoration(labelText: 'Internal Coating Type *'),
            ),
            TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity Received *')),
            DropdownButtonFormField<String>(
              value: rLoc,
              items: receivingLocations.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
              onChanged: (v) => setSub(() => rLoc = v!),
              decoration: const InputDecoration(labelText: 'Receiving Location *'),
            ),
            TextField(controller: remarksCtrl, decoration: const InputDecoration(labelText: 'Remarks / Heat Number')),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A), padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () async {
                if (qtyCtrl.text.isEmpty || sizeCtrl.text.isEmpty || gradeCtrl.text.isEmpty || schCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all mandatory fields!')));
                  return;
                }

                final authorized = await _authenticateAction('Add Receiving Entry');
                if (!authorized) return;

                setState(() {
                  transactions.add({
                    'id': const Uuid().v4(),
                    'type': 'RECEIVE',
                    'pipeSize': sizeCtrl.text.trim(),
                    'pipeGrade': gradeCtrl.text.trim(),
                    'pipeSch': schCtrl.text.trim(),
                    'category': cat,
                    'internalCoating': coat,
                    'quantity': double.parse(qtyCtrl.text),
                    'entity': rLoc,
                    'date': DateFormat('yyyy-MM-dd').format(selectedDate),
                    'remarks': remarksCtrl.text.trim(),
                  });
                });
                _saveData();
                _syncWithCloud();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Authorized: Pipes Received & Synced!')));
                  setState(() => _navIndex = 0);
                }
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('AUTHORIZE & SUBMIT RECEIVING', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // --- 2. ISSUING MODULE ---
  Widget _buildIssuing() {
    final sizeCtrl = TextEditingController();
    final gradeCtrl = TextEditingController();
    final schCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final personCtrl = TextEditingController();
    String cat = categories.first;
    String coat = coatingOptions.first;
    String loc = issueLocations.isNotEmpty ? issueLocations.first : 'Yard 1';
    String jp = jpNames.isNotEmpty ? jpNames.first : 'JP-1';
    DateTime selectedDate = DateTime.now();

    return StatefulBuilder(
      builder: (context, setSub) {
        final totalAvail = _getTotalAvailableToIssue(sizeCtrl.text.trim(), gradeCtrl.text.trim(), schCtrl.text.trim(), cat, coat);
        final readyInYard = _getPhysicalStock(sizeCtrl.text.trim(), gradeCtrl.text.trim(), schCtrl.text.trim(), cat, coat);
        final isPainted = (cat == 'Painting Pipe' || cat == 'Painting Bend');

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Stock Issuing Module', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.orange.shade200)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Issue Date (Auto-filled)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text(DateFormat('yyyy-MM-dd').format(selectedDate), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEA580C)),
                    icon: const Icon(Icons.calendar_month, color: Colors.white, size: 18),
                    label: const Text('Change Date', style: TextStyle(color: Colors.white)),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setSub(() => selectedDate = picked);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: totalAvail > 0 ? Colors.green.shade50 : Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: totalAvail > 0 ? Colors.green : Colors.red),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isPainted) ...[
                    Text(
                      'Ready Painted in Yard: $readyInYard Qty',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.teal),
                    ),
                    Text(
                      'Total Available to Issue (Yard + Bare to paint): $totalAvail Qty',
                      style: TextStyle(fontWeight: FontWeight.bold, color: totalAvail > 0 ? Colors.green.shade800 : Colors.red.shade800),
                    ),
                    const Text(
                      '* Pehle yard mein pada painted pipe use hoga, baaqi Bare stock se paint hoga.',
                      style: TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                  ] else ...[
                    Text(
                      'Available Stock in Yard: $totalAvail Qty',
                      style: TextStyle(fontWeight: FontWeight.bold, color: totalAvail > 0 ? Colors.green.shade800 : Colors.red.shade800),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            TextField(controller: sizeCtrl, decoration: const InputDecoration(labelText: 'Pipe Size *'), onChanged: (_) => setSub(() {})),
            TextField(controller: gradeCtrl, decoration: const InputDecoration(labelText: 'Pipe Grade (e.g. X52) *'), onChanged: (_) => setSub(() {})),
            TextField(controller: schCtrl, decoration: const InputDecoration(labelText: 'Pipe SCH (e.g. 12.7) *'), onChanged: (_) => setSub(() {})),
            DropdownButtonFormField<String>(
              value: cat,
              items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setSub(() => cat = v!),
              decoration: const InputDecoration(labelText: 'Category *'),
            ),
            DropdownButtonFormField<String>(
              value: coat,
              items: coatingOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setSub(() => coat = v!),
              decoration: const InputDecoration(labelText: 'Internal Coating *'),
            ),
            TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity to Issue *')),
            TextField(controller: personCtrl, decoration: const InputDecoration(labelText: 'Issued To / Person Name *')),
            DropdownButtonFormField<String>(
              value: loc,
              items: issueLocations.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
              onChanged: (v) => setSub(() => loc = v!),
              decoration: const InputDecoration(labelText: 'Destination Location *'),
            ),
            DropdownButtonFormField<String>(
              value: jp,
              items: jpNames.map((j) => DropdownMenuItem(value: j, child: Text(j))).toList(),
              onChanged: (v) => setSub(() => jp = v!),
              decoration: const InputDecoration(labelText: 'JP Name *'),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEA580C), padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () async {
                double req = double.tryParse(qtyCtrl.text) ?? 0;
                if (req <= 0) return;
                if (req > totalAvail) {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Insufficient Stock Blocked', style: TextStyle(color: Colors.red)),
                      content: Text('Cannot issue $req pipes. Only $totalAvail available for Size: ${sizeCtrl.text}, Grade: ${gradeCtrl.text}, SCH: ${schCtrl.text}.'),
                      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                    ),
                  );
                  return;
                }

                final authorized = await _authenticateAction('Issue Pipe Stock');
                if (!authorized) return;

                setState(() {
                  transactions.add({
                    'id': const Uuid().v4(),
                    'type': 'ISSUE',
                    'pipeSize': sizeCtrl.text.trim(),
                    'pipeGrade': gradeCtrl.text.trim(),
                    'pipeSch': schCtrl.text.trim(),
                    'category': cat,
                    'internalCoating': coat,
                    'quantity': req,
                    'entity': personCtrl.text.trim(),
                    'location': loc,
                    'jpName': jp,
                    'date': DateFormat('yyyy-MM-dd').format(selectedDate),
                  });
                });
                _saveData();
                _syncWithCloud();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Authorized: $cat Issued & Synced!')));
                  setState(() => _navIndex = 0);
                }
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('AUTHORIZE & SUBMIT ISSUING', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // --- 3. RETURN MODULE (WAPSI S DIRECT PAINTED POOL MEIN) ---
  Widget _buildReturning() {
    final sizeCtrl = TextEditingController();
    final gradeCtrl = TextEditingController();
    final schCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final returnFromCtrl = TextEditingController();
    final remarksCtrl = TextEditingController();
    String cat = categories.first;
    String coat = coatingOptions.first;
    DateTime selectedDate = DateTime.now();

    return StatefulBuilder(
      builder: (context, setSub) {
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Row(
              children: [
                Icon(Icons.assignment_return, color: Colors.teal, size: 26),
                SizedBox(width: 8),
                Text('Stock Return (Pipe Wapsi)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal)),
              ],
            ),
            const SizedBox(height: 6),
            const Text('Site se wapis aane wale pipes usi category (e.g. Painting Pipe) ke ready stock mein add honge.', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.teal.shade200)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Return Date (Auto-filled)', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      Text(DateFormat('yyyy-MM-dd').format(selectedDate), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                    icon: const Icon(Icons.calendar_month, color: Colors.white, size: 18),
                    label: const Text('Change Date', style: TextStyle(color: Colors.white)),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setSub(() => selectedDate = picked);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(controller: sizeCtrl, decoration: const InputDecoration(labelText: 'Pipe Size (e.g. 24") *')),
            TextField(controller: gradeCtrl, decoration: const InputDecoration(labelText: 'Pipe Grade (e.g. X52) *')),
            TextField(controller: schCtrl, decoration: const InputDecoration(labelText: 'Pipe SCH (e.g. 12.7) *')),
            DropdownButtonFormField<String>(
              value: cat,
              items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setSub(() => cat = v!),
              decoration: const InputDecoration(labelText: 'Category *'),
            ),
            DropdownButtonFormField<String>(
              value: coat,
              items: coatingOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setSub(() => coat = v!),
              decoration: const InputDecoration(labelText: 'Internal Coating *'),
            ),
            TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity Returned to Store *')),
            TextField(controller: returnFromCtrl, decoration: const InputDecoration(labelText: 'Returned From (Site / Location) *')),
            TextField(controller: remarksCtrl, decoration: const InputDecoration(labelText: 'Reason for Return (Surplus / Complete)')),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () async {
                if (qtyCtrl.text.isEmpty || sizeCtrl.text.isEmpty || gradeCtrl.text.isEmpty || schCtrl.text.isEmpty || returnFromCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all mandatory fields!')));
                  return;
                }

                final authorized = await _authenticateAction('Add Return Entry');
                if (!authorized) return;

                setState(() {
                  transactions.add({
                    'id': const Uuid().v4(),
                    'type': 'RETURN',
                    'pipeSize': sizeCtrl.text.trim(),
                    'pipeGrade': gradeCtrl.text.trim(),
                    'pipeSch': schCtrl.text.trim(),
                    'category': cat,
                    'internalCoating': coat,
                    'quantity': double.parse(qtyCtrl.text),
                    'entity': returnFromCtrl.text.trim(),
                    'date': DateFormat('yyyy-MM-dd').format(selectedDate),
                    'remarks': remarksCtrl.text.trim(),
                  });
                });
                _saveData();
                _syncWithCloud();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Success: Returned pipes added to $cat ready stock!')));
                  setState(() => _navIndex = 0);
                }
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('AUTHORIZE & ADD RETURN TO STOCK', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // --- 4. DETAILED STOCK BREAKDOWN ---
  Widget _buildStock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search Grade, SCH, Size...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
                  ),
                  onChanged: (val) => setState(() => _stockSearchQuery = val.trim().toLowerCase()),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A)),
                icon: const Icon(Icons.file_download, color: Colors.white, size: 16),
                label: const Text('Export', style: TextStyle(color: Colors.white)),
                onPressed: () => _showExportChoiceDialog('STOCK'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: categories.map((cat) {
              final isPainted = (cat == 'Painting Pipe' || cat == 'Painting Bend');

              final specMap = <String, Map<String, String>>{};
              for (var t in transactions) {
                final s = (t['pipeSize'] ?? '').toString().trim();
                final g = (t['pipeGrade'] ?? '').toString().trim();
                final sch = (t['pipeSch'] ?? '').toString().trim();
                final key = '$s|$g|$sch';

                if (_stockSearchQuery.isNotEmpty) {
                  final match = s.toLowerCase().contains(_stockSearchQuery) ||
                      g.toLowerCase().contains(_stockSearchQuery) ||
                      sch.toLowerCase().contains(_stockSearchQuery);
                  if (!match) continue;
                }

                if (!specMap.containsKey(key)) {
                  specMap[key] = {'size': s, 'grade': g, 'sch': sch};
                }
              }

              // Filter specs that have transactions related to this category or bare
              final relevantSpecs = specMap.values.where((spec) {
                final s = spec['size']!;
                final g = spec['grade']!;
                final sch = spec['sch']!;
                double cBal = _getPhysicalStock(s, g, sch, cat, 'Internal Coated');
                double uBal = _getPhysicalStock(s, g, sch, cat, 'Without Internal Coating');
                return (cBal > 0 || uBal > 0);
              }).toList();

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                elevation: 2,
                child: ExpansionTile(
                  initiallyExpanded: relevantSpecs.isNotEmpty,
                  title: Row(
                    children: [
                      Text(cat, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E3A8A))),
                      if (isPainted) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(4), border: Border.all(color: Colors.teal)),
                          child: const Text('Ready in Yard', style: TextStyle(fontSize: 10, color: Colors.teal, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ],
                  ),
                  children: relevantSpecs.isEmpty
                      ? [
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Text(
                              isPainted
                                  ? 'Abhi yard mein koi ready $cat nahi hai (Site se return aane par yahan show hoga).'
                                  : 'No pipes in stock under this category.',
                              style: const TextStyle(color: Colors.grey),
                            ),
                          )
                        ]
                      : relevantSpecs.map((spec) {
                          final size = spec['size']!;
                          final grade = spec['grade']!;
                          final sch = spec['sch']!;

                          double cBal = _getPhysicalStock(size, grade, sch, cat, 'Internal Coated');
                          double uBal = _getPhysicalStock(size, grade, sch, cat, 'Without Internal Coating');

                          return Container(
                            margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(color: Colors.grey.shade50, borderRadius: BorderRadius.circular(8), border: Border.all(color: Colors.blueGrey.shade100)),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(child: Text('Size: $size | Grade: $grade | SCH: $sch', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF0F172A)))),
                                    Text(
                                      isPainted ? 'In Yard: ${cBal + uBal}' : 'Available: ${cBal + uBal}',
                                      style: TextStyle(fontWeight: FontWeight.bold, color: isPainted ? Colors.teal : Colors.blueAccent),
                                    ),
                                  ],
                                ),
                                const Divider(height: 14),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.circle, size: 8, color: Colors.teal),
                                        SizedBox(width: 6),
                                        Text('Internal Coated:', style: TextStyle(fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                    Text('$cBal Qty', style: TextStyle(fontWeight: FontWeight.bold, color: cBal > 0 ? Colors.green.shade800 : Colors.grey.shade600)),
                                  ],
                                ),
                                const SizedBox(height: 6),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.circle, size: 8, color: Colors.amber),
                                        SizedBox(width: 6),
                                        Text('Without Internal Coating:', style: TextStyle(fontWeight: FontWeight.w600)),
                                      ],
                                    ),
                                    Text('$uBal Qty', style: TextStyle(fontWeight: FontWeight.bold, color: uBal > 0 ? Colors.green.shade800 : Colors.grey.shade600)),
                                  ],
                                ),
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

  // --- 5. HISTORY & SEARCH ---
  Widget _buildHistory() {
    final filtered = transactions.where((t) {
      if (_historyTypeFilter == 'RECEIVE' && t['type'] != 'RECEIVE') return false;
      if (_historyTypeFilter == 'ISSUE' && t['type'] != 'ISSUE') return false;
      if (_historyTypeFilter == 'RETURN' && t['type'] != 'RETURN') return false;

      if (_historySearchQuery.isNotEmpty) {
        final q = _historySearchQuery;
        final locMatch = (t['entity'] ?? '').toString().toLowerCase().contains(q) ||
            (t['location'] ?? '').toString().toLowerCase().contains(q) ||
            (t['jpName'] ?? '').toString().toLowerCase().contains(q);
        final gradeMatch = (t['pipeGrade'] ?? '').toString().toLowerCase().contains(q);
        final sizeMatch = (t['pipeSize'] ?? '').toString().toLowerCase().contains(q);
        final schMatch = (t['pipeSch'] ?? '').toString().toLowerCase().contains(q);
        final catMatch = (t['category'] ?? '').toString().toLowerCase().contains(q);
        final dateMatch = (t['date'] ?? '').toString().toLowerCase().contains(q);
        final remarksMatch = (t['remarks'] ?? '').toString().toLowerCase().contains(q);

        return locMatch || gradeMatch || sizeMatch || schMatch || catMatch || dateMatch || remarksMatch;
      }
      return true;
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search Location, Grade, Size, SCH, Date...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 12),
              suffixIcon: _historySearchQuery.isNotEmpty
                  ? IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _historySearchQuery = ''))
                  : null,
            ),
            onChanged: (val) => setState(() => _historySearchQuery = val.trim().toLowerCase()),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                FilterChip(
                  label: const Text('All (Both)'),
                  selected: _historyTypeFilter == 'ALL',
                  selectedColor: Colors.blue.shade100,
                  onSelected: (_) => setState(() => _historyTypeFilter = 'ALL'),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: const Text('Receiving'),
                  selected: _historyTypeFilter == 'RECEIVE',
                  selectedColor: Colors.green.shade100,
                  onSelected: (_) => setState(() => _historyTypeFilter = 'RECEIVE'),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: const Text('Issuing'),
                  selected: _historyTypeFilter == 'ISSUE',
                  selectedColor: Colors.orange.shade100,
                  onSelected: (_) => setState(() => _historyTypeFilter = 'ISSUE'),
                ),
                const SizedBox(width: 6),
                FilterChip(
                  label: const Text('Returns (Wapsi)'),
                  selected: _historyTypeFilter == 'RETURN',
                  selectedColor: Colors.teal.shade100,
                  onSelected: (_) => setState(() => _historyTypeFilter = 'RETURN'),
                ),
              ],
            ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          color: Colors.blue.shade50,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Showing ${filtered.length} of ${transactions.length} entries', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4)),
                icon: const Icon(Icons.file_download, color: Colors.white, size: 16),
                label: const Text('Export (Excel / PDF)', style: TextStyle(color: Colors.white, fontSize: 12)),
                onPressed: () => _showExportChoiceDialog(_historyTypeFilter, customList: filtered),
              ),
            ],
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Center(child: Text('No matching records found.'))
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, index) {
                    final t = filtered[index];
                    final tId = t['id'];

                    IconData icon;
                    Color color;
                    if (t['type'] == 'RECEIVE') {
                      icon = Icons.download;
                      color = Colors.green;
                    } else if (t['type'] == 'RETURN') {
                      icon = Icons.assignment_return;
                      color = Colors.teal;
                    } else {
                      icon = Icons.upload;
                      color = Colors.orange;
                    }

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: color.withOpacity(0.15),
                          child: Icon(icon, color: color),
                        ),
                        title: Text('${t['category']} (${t['pipeSize']}) - ${t['internalCoating']}'),
                        subtitle: Text('Grade: ${t['pipeGrade']} | SCH: ${t['pipeSch']}\nQty: ${t['quantity']} | Date: ${t['date']}\nLoc: ${t['entity'] ?? t['location']}${t['jpName'] != null ? ' | JP: ${t['jpName']}' : ''}'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(icon: const Icon(Icons.edit, color: Colors.blue), tooltip: 'Edit', onPressed: () => _editTransactionById(tId)),
                            IconButton(icon: const Icon(Icons.delete, color: Colors.red), tooltip: 'Delete', onPressed: () => _deleteTransactionById(tId)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // --- 6. MANAGE, BACKUP, EXCEL & PDF REPORTS ---
  Widget _buildManageAndBackup() {
    final rLocCtrl = TextEditingController();
    final iLocCtrl = TextEditingController();
    final jpCtrl = TextEditingController();
    final restoreTextCtrl = TextEditingController();
    final cloudIdCtrl = TextEditingController(text: _cloudStoreId);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Excel & Printable PDF Reports', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Card(
          color: Colors.green.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.print, color: Color(0xFF1E3A8A), size: 26),
                    SizedBox(width: 8),
                    Text('Download Reports (Excel & PDF)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('Aap har report ko Excel Spreadsheet ya Printable PDF document mein save kar sakte hain.'),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A)),
                      icon: const Icon(Icons.inventory, color: Colors.white, size: 16),
                      label: const Text('Live Stock Report', style: TextStyle(color: Colors.white)),
                      onPressed: () => _showExportChoiceDialog('STOCK'),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade800),
                      icon: const Icon(Icons.download, color: Colors.white, size: 16),
                      label: const Text('Receiving Report', style: TextStyle(color: Colors.white)),
                      onPressed: () => _showExportChoiceDialog('RECEIVE'),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade800),
                      icon: const Icon(Icons.upload, color: Colors.white, size: 16),
                      label: const Text('Issuing Report', style: TextStyle(color: Colors.white)),
                      onPressed: () => _showExportChoiceDialog('ISSUE'),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: Colors.teal.shade800),
                      icon: const Icon(Icons.assignment_return, color: Colors.white, size: 16),
                      label: const Text('Returns Report', style: TextStyle(color: Colors.white)),
                      onPressed: () => _showExportChoiceDialog('RETURN'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 28),
        const Text('Internet Cloud Synchronization (Mobile & PC)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Shared Store Sync ID', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(_lastSyncStatus, style: const TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('Mobile aur Computer dono par yeh SAME ID honi chahiye taake dono ka data aapas mein sync ho.'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: cloudIdCtrl,
                        decoration: const InputDecoration(labelText: 'Store Sync ID', border: OutlineInputBorder()),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A)),
                      onPressed: () {
                        if (cloudIdCtrl.text.trim().isNotEmpty) {
                          setState(() => _cloudStoreId = cloudIdCtrl.text.trim());
                          _saveData();
                          _syncWithCloud();
                        }
                      },
                      child: const Text('Save & Sync', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                    icon: _isSyncing
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                        : const Icon(Icons.sync, color: Colors.white),
                    label: Text(_isSyncing ? 'Syncing with Cloud...' : 'SYNC DATA NOW (UPLOAD & DOWNLOAD)', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    onPressed: _syncWithCloud,
                  ),
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 28),
        const Text('Security & Access Protection', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(
          color: Colors.amber.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Master PIN Authorization', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text('Current PIN:  $_securityPin', style: const TextStyle(color: Colors.black87)),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A)),
                  icon: const Icon(Icons.pin, color: Colors.white, size: 16),
                  label: const Text('Change PIN', style: TextStyle(color: Colors.white)),
                  onPressed: () {
                    final oldPinCtrl = TextEditingController();
                    final newPinCtrl = TextEditingController();
                    String errorTxt = '';

                    showDialog(
                      context: context,
                      builder: (ctx) => StatefulBuilder(
                        builder: (context, setDState) => AlertDialog(
                          title: const Text('Change Security PIN'),
                          content: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TextField(controller: oldPinCtrl, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Current PIN')),
                              const SizedBox(height: 8),
                              TextField(controller: newPinCtrl, obscureText: true, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'New PIN')),
                              if (errorTxt.isNotEmpty) ...[const SizedBox(height: 8), Text(errorTxt, style: const TextStyle(color: Colors.red))],
                            ],
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
                            ElevatedButton(
                              onPressed: () {
                                if (oldPinCtrl.text.trim() != _securityPin.trim()) {
                                  setDState(() => errorTxt = 'Current PIN is incorrect!');
                                  return;
                                }
                                if (newPinCtrl.text.trim().isEmpty) {
                                  setDState(() => errorTxt = 'Enter valid new PIN!');
                                  return;
                                }
                                setState(() => _securityPin = newPinCtrl.text.trim());
                                _saveData();
                                Navigator.pop(ctx);
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Master Security PIN Updated!')));
                              },
                              child: const Text('Update PIN'),
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
        const Divider(height: 28),
        const Text('Manual File Backup', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Export & Restore File Backup', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1E3A8A)),
                        icon: const Icon(Icons.download, color: Colors.white, size: 16),
                        label: const Text('EXPORT BACKUP', style: TextStyle(color: Colors.white)),
                        onPressed: () async {
                          final payload = {
                            'timestamp': DateTime.now().toIso8601String(),
                            'transactions': transactions,
                            'receivingLocations': receivingLocations,
                            'issueLocations': issueLocations,
                            'jpNames': jpNames,
                            'securityPin': _securityPin,
                          };
                          final jsonStr = jsonEncode(payload);
                          Clipboard.setData(ClipboardData(text: jsonStr));

                          final dir = await getApplicationDocumentsDirectory();
                          final bFile = File('${dir.path}/pipe_backup_${DateTime.now().millisecondsSinceEpoch}.json');
                          await bFile.writeAsString(jsonStr);

                          showDialog(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Backup Created!'),
                              content: Text('Saved to: ${bFile.path}\n\nData clipboard mein bhi copy ho gaya hai!'),
                              actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(controller: restoreTextCtrl, maxLines: 2, decoration: const InputDecoration(hintText: 'Paste backup JSON here to restore...', border: OutlineInputBorder())),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade800),
                  icon: const Icon(Icons.restore, color: Colors.white),
                  label: const Text('RESTORE DATA FROM TEXT', style: TextStyle(color: Colors.white)),
                  onPressed: () async {
                    if (restoreTextCtrl.text.isEmpty) return;
                    final authorized = await _authenticateAction('Restore Database');
                    if (!authorized) return;

                    try {
                      final data = jsonDecode(restoreTextCtrl.text.trim());
                      setState(() {
                        if (data['transactions'] != null) transactions = List<Map<String, dynamic>>.from(data['transactions']);
                        if (data['receivingLocations'] != null) receivingLocations = List<String>.from(data['receivingLocations']);
                        if (data['issueLocations'] != null) issueLocations = List<String>.from(data['issueLocations']);
                        if (data['jpNames'] != null) jpNames = List<String>.from(data['jpNames']);
                        if (data['securityPin'] != null) _securityPin = data['securityPin'].toString();
                      });
                      _saveData();
                      _syncWithCloud();
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Data Restored Successfully!')));
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Invalid Backup Data!')));
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 28),
        const Text('Receiving Locations Management', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Row(
          children: [
            Expanded(child: TextField(controller: rLocCtrl, decoration: const InputDecoration(labelText: 'New Receiving Location'))),
            IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.blue, size: 30),
              onPressed: () {
                if (rLocCtrl.text.isNotEmpty) {
                  setState(() => receivingLocations.add(rLocCtrl.text.trim()));
                  _saveData();
                  _syncWithCloud();
                  rLocCtrl.clear();
                }
              },
            ),
          ],
        ),
        Wrap(spacing: 8, children: receivingLocations.map((l) => Chip(
          label: Text(l),
          onDeleted: () {
            setState(() => receivingLocations.remove(l));
            _saveData();
            _syncWithCloud();
          },
        )).toList()),
        const Divider(height: 28),
        const Text('Issue Destination Locations', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Row(
          children: [
            Expanded(child: TextField(controller: iLocCtrl, decoration: const InputDecoration(labelText: 'New Issue Location'))),
            IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.green, size: 30),
              onPressed: () {
                if (iLocCtrl.text.isNotEmpty) {
                  setState(() => issueLocations.add(iLocCtrl.text.trim()));
                  _saveData();
                  _syncWithCloud();
                  iLocCtrl.clear();
                }
              },
            ),
          ],
        ),
        Wrap(spacing: 8, children: issueLocations.map((l) => Chip(
          label: Text(l),
          onDeleted: () {
            setState(() => issueLocations.remove(l));
            _saveData();
            _syncWithCloud();
          },
        )).toList()),
        const Divider(height: 28),
        const Text('JP Names (Joint Proposals)', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Row(
          children: [
            Expanded(child: TextField(controller: jpCtrl, decoration: const InputDecoration(labelText: 'New JP Name'))),
            IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.orange, size: 30),
              onPressed: () {
                if (jpCtrl.text.isNotEmpty) {
                  setState(() => jpNames.add(jpCtrl.text.trim()));
                  _saveData();
                  _syncWithCloud();
                  jpCtrl.clear();
                }
              },
            ),
          ],
        ),
        Wrap(spacing: 8, children: jpNames.map((j) => Chip(
          label: Text(j),
          onDeleted: () {
            setState(() => jpNames.remove(j));
            _saveData();
            _syncWithCloud();
          },
        )).toList()),
      ],
    );
  }
}
