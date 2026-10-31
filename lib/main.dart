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
  List<String> receivingLocations = ['Main Yard Receiving', 'Warehouse Gate 1', 'Bay 4 Discharge'];
  List<String> issueLocations = ['Yard 1', 'Yard 2', 'Warehouse A', 'Main Site Line'];
  List<String> jpNames = ['JP-Alpha', 'JP-Beta', 'JP-North', 'JP-Pipeline-01'];

  List<String> pinnedLocations = [];
  List<String> pinnedJpNames = [];
  List<String> pinnedCategories = [];

  String _securityPin = '1234';
  String _firebaseUrl = '';
  String _cloudStoreId = 'store_main';
  bool _isSyncing = false;
  String _lastSyncStatus = 'Not Synced';
  bool _isSettingsUnlocked = false;

  final List<String> categories = [
    'Bare Pipe', 'Bare Bend', 'Painting Bend', 'Painting Pipe',
    '3LPP Pipe', '3LPP Bend', 'Spool', 'Cut Piece',
    'Elbow', 'Flange'
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
    _loadData().then((_) {
      _checkAndRunDailyAutoBackup();
      if (_firebaseUrl.isNotEmpty) {
        _syncWithCloud(silent: true);
      }
    });
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
          if (data['pinnedLocations'] != null) {
            pinnedLocations = List<String>.from(data['pinnedLocations']);
          }
          if (data['pinnedJpNames'] != null) {
            pinnedJpNames = List<String>.from(data['pinnedJpNames']);
          }
          if (data['pinnedCategories'] != null) {
            pinnedCategories = List<String>.from(data['pinnedCategories']);
          }
          if (data['securityPin'] != null) {
            _securityPin = data['securityPin'].toString();
          }
          if (data['firebaseUrl'] != null) {
            _firebaseUrl = data['firebaseUrl'].toString();
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
        'version': '4.0',
        'updatedAt': DateTime.now().toIso8601String(),
        'transactions': transactions,
        'receivingLocations': receivingLocations,
        'issueLocations': issueLocations,
        'jpNames': jpNames,
        'pinnedLocations': pinnedLocations,
        'pinnedJpNames': pinnedJpNames,
        'pinnedCategories': pinnedCategories,
        'securityPin': _securityPin,
        'firebaseUrl': _firebaseUrl,
        'cloudStoreId': _cloudStoreId,
      };
      await file.writeAsString(jsonEncode(payload));
    } catch (_) {}
  }

  Future<void> _checkAndRunDailyAutoBackup() async {
    try {
      final todayStr = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final dir = await getApplicationDocumentsDirectory();
      final backupDir = Directory('${dir.path}/Daily_Backups');
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
      final todayBackupFile = File('${backupDir.path}/auto_backup_$todayStr.json');
      if (!await todayBackupFile.exists() && transactions.isNotEmpty) {
        final payload = {
          'backupDate': todayStr,
          'createdAt': DateTime.now().toIso8601String(),
          'transactions': transactions,
          'receivingLocations': receivingLocations,
          'issueLocations': issueLocations,
          'jpNames': jpNames,
        };
        await todayBackupFile.writeAsString(jsonEncode(payload));
      }
    } catch (_) {}
  }

  String _norm(dynamic s) => (s ?? '')
      .toString()
      .replaceAll('"', '')
      .replaceAll("'", '')
      .replaceAll(' ', '')
      .trim()
      .toLowerCase();

  bool _matchStrict(Map<String, dynamic> t, String size, String grade, String schOrClass, String coat) {
    final s1 = _norm(t['pipeSize']);
    final g1 = _norm(t['pipeGrade']);
    final sch1 = _norm(t['pipeSch'] ?? t['itemClass']);
    final c1 = _norm(t['internalCoating']);

    return s1 == _norm(size) &&
        g1 == _norm(grade) &&
        sch1 == _norm(schOrClass) &&
        c1 == _norm(coat);
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
    final spec = _calculateSpecStocks(size, grade, schOrClass, coating);
    return spec[cat]?['qty'] ?? 0.0;
  }

  double _getPhysicalStockMeters(String size, String grade, String schOrClass, String cat, String coating) {
    if (size.trim().isEmpty || grade.trim().isEmpty) return 0.0;
    final spec = _calculateSpecStocks(size, grade, schOrClass, coating);
    return spec[cat]?['meters'] ?? 0.0;
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
      final aPinned = pinnedItems.contains(a);
      final bPinned = pinnedItems.contains(b);
      if (aPinned && !bPinned) return -1;
      if (!aPinned && bPinned) return 1;
      return a.compareTo(b);
    });
    return list;
  }Future<void> _syncWithCloud({bool silent = false}) async {
    if (_isSyncing) return;
    if (_firebaseUrl.trim().isEmpty) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Pehle Settings mein ja kar Firebase URL paste karein!')),
        );
      }
      return;
    }

    setState(() => _isSyncing = true);

    try {
      String baseUrl = _firebaseUrl.trim();
      if (!baseUrl.startsWith('http://') && !baseUrl.startsWith('https://')) {
        baseUrl = 'https://$baseUrl';
      }
      if (baseUrl.endsWith('/')) {
        baseUrl = baseUrl.substring(0, baseUrl.length - 1);
      }

      final syncUri = Uri.parse('$baseUrl/$_cloudStoreId.json');

      final response = await http.get(syncUri).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        if (response.body.isNotEmpty && response.body != 'null') {
          final remoteData = jsonDecode(response.body);
          if (remoteData is Map) {
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
        }
      }

      final uploadPayload = {
        'updatedAt': DateTime.now().toIso8601String(),
        'transactions': transactions,
        'receivingLocations': receivingLocations,
        'issueLocations': issueLocations,
        'jpNames': jpNames,
      };

      await http.put(
        syncUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(uploadPayload),
      ).timeout(const Duration(seconds: 12));

      await _saveData();

      setState(() {
        _lastSyncStatus = 'Synced at ${DateFormat('hh:mm a').format(DateTime.now())}';
      });

      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade800,
            content: Text('Cloud Sync Successful! (${transactions.length} total entries)'),
          ),
        );
      }
    } catch (e) {
      setState(() => _lastSyncStatus = 'Sync Error');
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: Colors.red.shade800, content: Text('Sync Error: $e')),
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
                const Icon(Icons.lock, color: Color(0xFF0A2540)),
                const SizedBox(width: 8),
                Expanded(child: Text('Security Lock - $actionTitle', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold))),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Please enter Master PIN to authorize:'),
                const SizedBox(height: 12),
                TextField(
                  controller: pinCtrl,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Master PIN',
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
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0A2540)),
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

  void _editTransactionById(String id) async {
    final index = transactions.indexWhere((item) => item['id'] == id);
    if (index == -1) return;

    final authorized = await _authenticateAction('Edit Record');
    if (!authorized) return;

    if (!mounted) return;
    final t = transactions[index];
    final sizeCtrl = TextEditingController(text: t['pipeSize'] ?? '');
    final gradeCtrl = TextEditingController(text: t['pipeGrade'] ?? '');
    final schCtrl = TextEditingController(text: t['pipeSch'] ?? t['itemClass'] ?? '');
    final qtyCtrl = TextEditingController(text: t['quantity']?.toString() ?? '1');
    final metersCtrl = TextEditingController(text: t['lengthMeters']?.toString() ?? '');
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
                  decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Date: ${DateFormat('yyyy-MM-dd').format(editDate)}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.calendar_month, color: Color(0xFF0A2540)),
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
                DropdownButtonFormField<String>(
                  value: cat,
                  items: categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setDState(() => cat = v!),
                  decoration: const InputDecoration(labelText: 'Category / Item'),
                ),
                TextField(controller: sizeCtrl, decoration: const InputDecoration(labelText: 'Size')),
                TextField(controller: gradeCtrl, decoration: const InputDecoration(labelText: 'Grade')),
                TextField(
                  controller: schCtrl,
                  decoration: InputDecoration(
                    labelText: (cat == 'Elbow' || cat == 'Flange') ? 'Class / Rating (e.g. 150#, 300#)' : 'Pipe SCH',
                  ),
                ),
                DropdownButtonFormField<String>(
                  value: coat,
                  items: coatingOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setDState(() => coat = v!),
                  decoration: const InputDecoration(labelText: 'Coating'),
                ),
                TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity (Pcs)')),
                if (cat == 'Cut Piece')
                  TextField(controller: metersCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Total Length (Meters)')),
                TextField(controller: entityCtrl, decoration: InputDecoration(labelText: t['type'] == 'RECEIVE' ? 'Receiving Location' : 'Destination / Person')),
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
                final newMeters = double.tryParse(metersCtrl.text) ?? 0.0;
                if (newQty <= 0) return;

                setState(() {
                  transactions[index]['date'] = DateFormat('yyyy-MM-dd').format(editDate);
                  transactions[index]['category'] = cat;
                  transactions[index]['pipeSize'] = sizeCtrl.text.trim();
                  transactions[index]['pipeGrade'] = gradeCtrl.text.trim();
                  if (cat == 'Elbow' || cat == 'Flange') {
                    transactions[index]['itemClass'] = schCtrl.text.trim();
                    transactions[index]['pipeSch'] = schCtrl.text.trim();
                  } else {
                    transactions[index]['pipeSch'] = schCtrl.text.trim();
                  }
                  transactions[index]['internalCoating'] = coat;
                  transactions[index]['quantity'] = newQty;
                  transactions[index]['lengthMeters'] = newMeters;
                  transactions[index]['entity'] = entityCtrl.text.trim();
                  transactions[index]['remarks'] = remarksCtrl.text.trim();
                });
                _saveData();
                _syncWithCloud(silent: true);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entry updated successfully!')));
              },
              child: const Text('Save Changes', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _deleteTransactionById(String id) async {
    final authorized = await _authenticateAction('Delete Record');
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
              _syncWithCloud(silent: true);
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Entry deleted successfully!')));
            },
            child: const Text('DELETE', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _renameLocationOrJpDialog({required bool isLocation, required String oldName}) {
    final newNameCtrl = TextEditingController(text: oldName);
    bool updateAllExisting = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDState) => AlertDialog(
          title: Text('Edit ${isLocation ? "Location" : "JP Name"}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: newNameCtrl, decoration: InputDecoration(labelText: 'New ${isLocation ? "Location" : "JP"} Name')),
              const SizedBox(height: 12),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: updateAllExisting,
                title: const Text('Purani tamam entries mein bhi yeh naya naam update karein?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                subtitle: const Text('One-click bulk rename across all past records.', style: TextStyle(fontSize: 11)),
                onChanged: (val) => setDState(() => updateAllExisting = val ?? true),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0A2540)),
              onPressed: () {
                final newName = newNameCtrl.text.trim();
                if (newName.isEmpty || newName == oldName) {
                  Navigator.pop(ctx);
                  return;
                }

                setState(() {
                  if (isLocation) {
                    final idxR = receivingLocations.indexOf(oldName);
                    if (idxR != -1) receivingLocations[idxR] = newName;
                    final idxI = issueLocations.indexOf(oldName);
                    if (idxI != -1) issueLocations[idxI] = newName;
                  } else {
                    final idxJ = jpNames.indexOf(oldName);
                    if (idxJ != -1) jpNames[idxJ] = newName;
                  }

                  if (updateAllExisting) {
                    for (var t in transactions) {
                      if (isLocation) {
                        if (t['entity'] == oldName) t['entity'] = newName;
                        if (t['location'] == oldName) t['location'] = newName;
                      } else {
                        if (t['jpName'] == oldName) t['jpName'] = newName;
                      }
                    }
                  }
                });

                _saveData();
                _syncWithCloud(silent: true);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('${isLocation ? "Location" : "JP Name"} renamed & updated successfully!')),
                );
              },
              child: const Text('Update & Save', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _exportDocument({required String reportType, required String format, List<Map<String, dynamic>>? customList}) async {
    final nowStr = DateFormat('yyyy-MM-dd_HH-mm').format(DateTime.now());
    final printDate = DateFormat('yyyy-MM-dd hh:mm a').format(DateTime.now());
    final isPdf = format == 'PDF';
    final ext = isPdf ? 'html' : 'csv';
    final fileName = 'SOFS_${reportType}_$nowStr.$ext';

    String content = '';

    if (reportType == 'STOCK') {
      if (!isPdf) {
        final StringBuffer csv = StringBuffer();
        csv.writeln('Company: SAARI OIL FIELD SERVICES PIPE LINE');
        csv.writeln('Report: Current Store Inventory Balance');
        csv.writeln('Date: $printDate\n');
        csv.writeln('Category,Size,Grade,SCH / Class,Coating,In-Store Balance Qty,Total Length (Meters),Stock Nature');
        for (var cat in categories) {
          final specMap = <String, Map<String, String>>{};
          for (var t in transactions) {
            final s = (t['pipeSize'] ?? '').toString().trim();
            final g = (t['pipeGrade'] ?? '').toString().trim();
            final sch = (t['pipeSch'] ?? t['itemClass'] ?? '').toString().trim();
            specMap['$s|$g|$sch'] = {'size': s, 'grade': g, 'sch': sch};
          }
          for (var spec in specMap.values) {
            final s = spec['size']!;
            final g = spec['grade']!;
            final sch = spec['sch']!;
            for (var coat in coatingOptions) {
              double qty = _getPhysicalStockQty(s, g, sch, cat, coat);
              double meters = _getPhysicalStockMeters(s, g, sch, cat, coat);
              if (qty > 0 || meters > 0) {
                String note = (cat == 'Painting Pipe' || cat == 'Painting Bend')
                    ? 'Ready Painted in Yard'
                    : 'Physical Stock';
                csv.writeln('"$cat","$s","$g","$sch","$coat",$qty,$meters,"$note"');
              }
            }
          }
        }
        content = csv.toString();
      } else {
        final StringBuffer html = StringBuffer();
        html.writeln('''<!DOCTYPE html><html><head><meta charset="utf-8">
        <title>SOFS - Inventory Balance Report</title>
        <style>
          body { font-family: 'Segoe UI', Tahoma, Arial, sans-serif; margin: 30px; color: #0f172a; }
          .header-box { border-bottom: 3px solid #0A2540; padding-bottom: 12px; margin-bottom: 20px; display: flex; justify-content: space-between; align-items: center; }
          .logo-text { color: #0A2540; font-size: 24px; font-weight: 900; letter-spacing: 0.5px; }
          .logo-sub { color: #F25F22; font-size: 13px; font-weight: bold; letter-spacing: 1px; }
          .meta-box { text-align: right; font-size: 12px; color: #64748b; }
          table { width: 100%; border-collapse: collapse; margin-top: 15px; }
          th { background-color: #0A2540; color: white; padding: 10px 12px; text-align: left; font-size: 12px; text-transform: uppercase; }
          td { padding: 9px 12px; border-bottom: 1px solid #e2e8f0; font-size: 12px; }
          tr:nth-child(even) { background-color: #f8fafc; }
          .badge-qty { font-weight: bold; color: #047857; font-size: 13px; }
          .btn-print { background: #0A2540; color: white; border: none; padding: 10px 24px; font-weight: bold; border-radius: 6px; cursor: pointer; margin-bottom: 20px; }
          @media print { .no-print { display: none; } body { margin: 0; } }
        </style></head><body>
        <div class="no-print"><button class="btn-print" onclick="window.print()">🖨️ Print / Save as PDF</button></div>
        <div class="header-box">
          <div>
            <div class="logo-text">SAARI OIL FIELD SERVICES PIPE LINE</div>
            <div class="logo-sub">WAREHOUSE & MATERIAL INVENTORY CONTROL</div>
          </div>
          <div class="meta-box">
            <div>Report: <b>Live Stock Balance</b></div>
            <div>Generated: $printDate</div>
          </div>
        </div>
        <table><thead><tr>
          <th>Category</th><th>Size</th><th>Grade</th><th>SCH / Class</th><th>Coating</th><th>In-Yard Qty</th><th>Length (Meters)</th><th>Status</th>
        </tr></thead><tbody>''');

        for (var cat in categories) {
          final specMap = <String, Map<String, String>>{};
          for (var t in transactions) {
            final s = (t['pipeSize'] ?? '').toString().trim();
            final g = (t['pipeGrade'] ?? '').toString().trim();
            final sch = (t['pipeSch'] ?? t['itemClass'] ?? '').toString().trim();
            specMap['$s|$g|$sch'] = {'size': s, 'grade': g, 'sch': sch};
          }
          for (var spec in specMap.values) {
            final s = spec['size']!;
            final g = spec['grade']!;
            final sch = spec['sch']!;
            for (var coat in coatingOptions) {
              double qty = _getPhysicalStockQty(s, g, sch, cat, coat);
              double meters = _getPhysicalStockMeters(s, g, sch, cat, coat);
              if (qty > 0 || meters > 0) {
                String note = (cat == 'Painting Pipe' || cat == 'Painting Bend')
                    ? '<span style="color:#0d9488;font-weight:bold;">Ready in Yard</span>'
                    : 'Physical Stock';
                html.writeln('<tr><td><b>$cat</b></td><td>$s</td><td>$g</td><td>$sch</td><td>$coat</td><td class="badge-qty">$qty Pcs</td><td>${meters > 0 ? "$meters m" : "-"}</td><td>$note</td></tr>');
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
        csv.writeln('Company: SAARI OIL FIELD SERVICES PIPE LINE');
        csv.writeln('Report: $reportType Ledger Records');
        csv.writeln('Date: $printDate\n');
        csv.writeln('Type,Date,Category,Size,Grade,SCH / Class,Coating,Quantity (Pcs),Length (Meters),Location / Person,JP Name,Remarks');
        for (var t in list) {
          if (reportType == 'RECEIVE' && t['type'] != 'RECEIVE') continue;
          if (reportType == 'ISSUE' && t['type'] != 'ISSUE') continue;
          if (reportType == 'RETURN' && t['type'] != 'RETURN') continue;

          final type = t['type'] ?? '';
          final date = t['date'] ?? '';
          final cat = t['category'] ?? '';
          final size = t['pipeSize'] ?? '';
          final grade = t['pipeGrade'] ?? '';
          final sch = t['pipeSch'] ?? t['itemClass'] ?? '';
          final coat = t['internalCoating'] ?? '';
          final qty = t['quantity'] ?? 0;
          final meters = t['lengthMeters'] ?? 0;
          final loc = (t['entity'] ?? t['location'] ?? '').toString().replaceAll('"', '""');
          final jp = (t['jpName'] ?? '').toString().replaceAll('"', '""');
          final remarks = (t['remarks'] ?? '').toString().replaceAll('"', '""');

          csv.writeln('"$type","$date","$cat","$size","$grade","$sch","$coat",$qty,$meters,"$loc","$jp","$remarks"');
        }
        content = csv.toString();
      } else {
        final StringBuffer html = StringBuffer();
        html.writeln('''<!DOCTYPE html><html><head><meta charset="utf-8">
        <title>SOFS - $reportType Report</title>
        <style>
          body { font-family: 'Segoe UI', Tahoma, Arial, sans-serif; margin: 30px; color: #0f172a; }
          .header-box { border-bottom: 3px solid #0A2540; padding-bottom: 12px; margin-bottom: 20px; display: flex; justify-content: space-between; align-items: center; }
          .logo-text { color: #0A2540; font-size: 24px; font-weight: 900; }
          .logo-sub { color: #F25F22; font-size: 13px; font-weight: bold; }
          .meta-box { text-align: right; font-size: 12px; color: #64748b; }
          table { width: 100%; border-collapse: collapse; margin-top: 15px; }
          th { background-color: #0A2540; color: white; padding: 10px 12px; text-align: left; font-size: 12px; }
          td { padding: 9px 12px; border-bottom: 1px solid #e2e8f0; font-size: 12px; }
          tr:nth-child(even) { background-color: #f8fafc; }
          .btn-print { background: #0A2540; color: white; border: none; padding: 10px 24px; font-weight: bold; border-radius: 6px; cursor: pointer; margin-bottom: 20px; }
          @media print { .no-print { display: none; } body { margin: 0; } }
        </style></head><body>
        <div class="no-print"><button class="btn-print" onclick="window.print()">🖨️ Print / Save as PDF</button></div>
        <div class="header-box">
          <div>
            <div class="logo-text">SAARI OIL FIELD SERVICES PIPE LINE</div>
            <div class="logo-sub">MATERIAL TRANSACTION REPORT - $reportType</div>
          </div>
          <div class="meta-box">
            <div>Generated: $printDate</div>
            <div>Records: ${list.length}</div>
          </div>
        </div>
        <table><thead><tr>
          <th>Type</th><th>Date</th><th>Category</th><th>Size</th><th>Grade</th><th>SCH/Class</th><th>Coating</th><th>Qty</th><th>Meters</th><th>Location/Person</th><th>JP Name</th><th>Remarks</th>
        </tr></thead><tbody>''');

        for (var t in list) {
          if (reportType == 'RECEIVE' && t['type'] != 'RECEIVE') continue;
          if (reportType == 'ISSUE' && t['type'] != 'ISSUE') continue;
          if (reportType == 'RETURN' && t['type'] != 'RETURN') continue;

          html.writeln('<tr><td><b>${t['type']}</b></td><td>${t['date']}</td><td>${t['category']}</td><td>${t['pipeSize']}</td><td>${t['pipeGrade']}</td><td>${t['pipeSch'] ?? t['itemClass'] ?? ''}</td><td>${t['internalCoating']}</td><td><b>${t['quantity']}</b></td><td>${(t['lengthMeters'] ?? 0) > 0 ? "${t['lengthMeters']}m" : "-"}</td><td>${t['entity'] ?? t['location'] ?? ''}</td><td>${t['jpName'] ?? ''}</td><td>${t['remarks'] ?? ''}</td></tr>');
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
                Text(isPdf ? 'Printable PDF Ready' : 'Excel Sheet Generated'),
              ],
            ),
            content: Text(
              'File saved at:\n${file.path}\n\n${isPdf ? "Aap browser mein open kar ke 'Save as PDF' ya direct print kar sakte hain." : "Yeh file Microsoft Excel mein cleanly formatted columns ke sath khulegi."}\n\nData clipboard mein bhi copy ho gaya hai.',
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
        content: const Text('Select format to download:'),
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
            label: const Text('Corporate PDF', style: TextStyle(color: Colors.white)),
            onPressed: () {
              Navigator.pop(ctx);
              _exportDocument(reportType: reportType, format: 'PDF', customList: customList);
            },
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildCompanyAppBar() {
    return AppBar(
      backgroundColor: const Color(0xFF0A2540),
      foregroundColor: Colors.white,
      elevation: 2,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFFF25F22),
              border: Border.all(color: Colors.amber, width: 2),
            ),
            child: const Icon(Icons.oil_barrel, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'SAARI OIL FIELD SERVICES',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900, letterSpacing: 0.8, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'PIPE LINE INVENTORY CONTROL',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1.2, color: Color(0xFFF25F22)),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8.0),
          child: _isSyncing
              ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)))
              : IconButton(
                  icon: const Icon(Icons.cloud_sync, color: Colors.white, size: 26),
                  tooltip: 'Sync Mobile & PC Data',
                  onPressed: () => _syncWithCloud(silent: false),
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildCompanyAppBar(),
      body: _buildCurrentScreen(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _navIndex,
        onDestinationSelected: (i) async {
          if (i == 6 && !_isSettingsUnlocked) {
            final ok = await _authenticateAction('Open Settings & Manage');
            if (ok) {
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
    if (_navIndex == 1) return _buildReceiving();
    if (_navIndex == 2) return _buildIssuing();
    if (_navIndex == 3) return _buildReturning();
    if (_navIndex == 4) return _buildStock();
    if (_navIndex == 5) return _buildHistory();
    return _buildManageAndBackup();
  }Widget _buildDashboard() {
    double received = 0;
    double issued = 0;
    double returned = 0;

    for (var t in transactions) {
      double q = (t['quantity'] as num?)?.toDouble() ?? 0.0;
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
            const Text('Inventory KPI Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0A2540))),
            Chip(
              avatar: Icon(Icons.cloud, size: 14, color: _lastSyncStatus.startsWith('Synced') ? Colors.green : Colors.blue),
              label: Text(_lastSyncStatus, style: const TextStyle(fontSize: 11)),
              backgroundColor: Colors.blue.shade50,
            ),
          ],
        ),
        const SizedBox(height: 12),
        Card(
          elevation: 2,
          color: const Color(0xFF0A2540),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Available Physical Material in Store', style: TextStyle(color: Colors.white70, fontSize: 13)),
                const SizedBox(height: 4),
                Text('$balance Total Pcs', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white)),
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
                      Text('$received Pcs', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
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
                      Text('$returned Pcs', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.teal)),
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
                      Text('$issued Pcs', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.orange)),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        const Text('Recent Activities', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0A2540))),
        ...transactions.reversed.take(6).map((t) {
          IconData icon = t['type'] == 'RECEIVE' ? Icons.arrow_downward : (t['type'] == 'RETURN' ? Icons.assignment_return : Icons.arrow_upward);
          Color color = t['type'] == 'RECEIVE' ? Colors.green : (t['type'] == 'RETURN' ? Colors.teal : Colors.orange);

          final schClass = t['pipeSch'] ?? t['itemClass'] ?? '';
          final meters = (t['lengthMeters'] ?? 0) > 0 ? " | Length: ${t['lengthMeters']}m" : "";

          return Card(
            margin: const EdgeInsets.only(top: 8),
            child: ListTile(
              leading: CircleAvatar(backgroundColor: color.withOpacity(0.12), child: Icon(icon, color: color)),
              title: Text('${t['category']} (${t['pipeSize']}) - ${t['internalCoating']}'),
              subtitle: Text('Grade: ${t['pipeGrade']} | SCH/Class: $schClass\nQty: ${t['quantity']} Pcs$meters | Date: ${t['date']}'),
              trailing: Chip(
                label: Text(t['type'], style: const TextStyle(color: Colors.white, fontSize: 10)),
                backgroundColor: color,
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildReceiving() {
    final sizeCtrl = TextEditingController();
    final gradeCtrl = TextEditingController();
    final schCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final metersCtrl = TextEditingController();
    final remarksCtrl = TextEditingController();

    String cat = categories.first;
    String coat = coatingOptions.first;
    final sortedLocs = _getSortedList(receivingLocations, pinnedLocations);
    String rLoc = sortedLocs.isNotEmpty ? sortedLocs.first : 'Yard Receiving';
    DateTime selectedDate = DateTime.now();

    return StatefulBuilder(
      builder: (context, setSub) {
        final isElbowOrFlange = (cat == 'Elbow' || cat == 'Flange');
        final isCutPiece = (cat == 'Cut Piece');

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Stock Receiving Module', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0A2540))),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.blue.shade50, borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Receiving Date (Auto-filled)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      Text(DateFormat('yyyy-MM-dd').format(selectedDate), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0A2540)),
                    icon: const Icon(Icons.calendar_month, color: Colors.white, size: 16),
                    label: const Text('Change Date', style: TextStyle(color: Colors.white, fontSize: 12)),
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

            DropdownButtonFormField<String>(
              value: cat,
              items: _getSortedList(categories, pinnedCategories)
                  .map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setSub(() => cat = v!),
              decoration: const InputDecoration(labelText: 'Item Category *'),
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: TextField(controller: sizeCtrl, decoration: const InputDecoration(labelText: 'Size (e.g. 24", 8") *')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(controller: gradeCtrl, decoration: const InputDecoration(labelText: 'Grade (e.g. X52, A105) *')),
                ),
              ],
            ),
            const SizedBox(height: 8),

            TextField(
              controller: schCtrl,
              decoration: InputDecoration(
                labelText: isElbowOrFlange
                    ? 'Class / Rating (e.g. 150#, 300#, 600#, 900#) *'
                    : 'Pipe SCH (e.g. 12.7, SCH 80) *',
              ),
            ),
            const SizedBox(height: 8),

            DropdownButtonFormField<String>(
              value: coat,
              items: coatingOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setSub(() => coat = v!),
              decoration: const InputDecoration(labelText: 'Internal Coating *'),
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Quantity (Pieces) *'),
                  ),
                ),
                if (isCutPiece) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: metersCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Kul Length (Meters) *'),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),

            DropdownButtonFormField<String>(
              value: rLoc,
              items: sortedLocs.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
              onChanged: (v) => setSub(() => rLoc = v!),
              decoration: const InputDecoration(labelText: 'Receiving Location *'),
            ),
            const SizedBox(height: 8),

            TextField(controller: remarksCtrl, decoration: const InputDecoration(labelText: 'Remarks / Heat Number')),
            const SizedBox(height: 20),

            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF0A2540),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              onPressed: () async {
                if (qtyCtrl.text.isEmpty || sizeCtrl.text.isEmpty || gradeCtrl.text.isEmpty || schCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill all mandatory fields!')));
                  return;
                }

                final authorized = await _authenticateAction('Add Receiving Entry');
                if (!authorized) return;

                final qtyVal = double.parse(qtyCtrl.text);
                final metersVal = double.tryParse(metersCtrl.text) ?? 0.0;

                setState(() {
                  transactions.add({
                    'id': const Uuid().v4(),
                    'type': 'RECEIVE',
                    'category': cat,
                    'pipeSize': sizeCtrl.text.trim(),
                    'pipeGrade': gradeCtrl.text.trim(),
                    'pipeSch': schCtrl.text.trim(),
                    'itemClass': isElbowOrFlange ? schCtrl.text.trim() : '',
                    'internalCoating': coat,
                    'quantity': qtyVal,
                    'lengthMeters': metersVal,
                    'entity': rLoc,
                    'date': DateFormat('yyyy-MM-dd').format(selectedDate),
                    'remarks': remarksCtrl.text.trim(),
                  });
                });
                _saveData();
                _syncWithCloud(silent: true);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Material Received & Saved!')));
                  setState(() => _navIndex = 0);
                }
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock, color: Colors.white, size: 18),
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

  Widget _buildIssuing() {
    final sizeCtrl = TextEditingController();
    final gradeCtrl = TextEditingController();
    final schCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final metersCtrl = TextEditingController();
    final personCtrl = TextEditingController();

    String cat = categories.first;
    String coat = coatingOptions.first;
    final sortedLocs = _getSortedList(issueLocations, pinnedLocations);
    String loc = sortedLocs.isNotEmpty ? sortedLocs.first : 'Yard 1';
    final sortedJps = _getSortedList(jpNames, pinnedJpNames);
    String jp = sortedJps.isNotEmpty ? sortedJps.first : 'JP-1';
    DateTime selectedDate = DateTime.now();

    return StatefulBuilder(
      builder: (context, setSub) {
        final curSize = sizeCtrl.text.trim();
        final curGrade = gradeCtrl.text.trim();
        final curSch = schCtrl.text.trim();

        final totalAvail = _getTotalAvailableToIssue(curSize, curGrade, curSch, cat, coat);
        final readyInYard = _getPhysicalStockQty(curSize, curGrade, curSch, cat, coat);
        final readyMeters = _getPhysicalStockMeters(curSize, curGrade, curSch, cat, coat);

        final isPainted = (cat == 'Painting Pipe' || cat == 'Painting Bend');
        final isElbowOrFlange = (cat == 'Elbow' || cat == 'Flange');
        final isCutPiece = (cat == 'Cut Piece');
        final parentName = (cat == 'Painting Pipe') ? 'Bare Pipe' : 'Bare Bend';

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('Stock Issuing Module', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0A2540))),
            const SizedBox(height: 8),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.orange.shade50, borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Issue Date (Auto-filled)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      Text(DateFormat('yyyy-MM-dd').format(selectedDate), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF25F22)),
                    icon: const Icon(Icons.calendar_month, color: Colors.white, size: 16),
                    label: const Text('Change Date', style: TextStyle(color: Colors.white, fontSize: 12)),
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
            const SizedBox(height: 10),

            DropdownButtonFormField<String>(
              value: cat,
              items: _getSortedList(categories, pinnedCategories)
                  .map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setSub(() => cat = v!),
              decoration: const InputDecoration(labelText: 'Item Category *'),
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(child: TextField(controller: sizeCtrl, decoration: const InputDecoration(labelText: 'Size *'), onChanged: (_) => setSub(() {}))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: gradeCtrl, decoration: const InputDecoration(labelText: 'Grade *'), onChanged: (_) => setSub(() {}))),
              ],
            ),
            const SizedBox(height: 8),

            TextField(
              controller: schCtrl,
              decoration: InputDecoration(
                labelText: isElbowOrFlange ? 'Class / Rating (Strict) *' : 'Pipe SCH (Strict) *',
              ),
              onChanged: (_) => setSub(() {}),
            ),
            const SizedBox(height: 8),

            DropdownButtonFormField<String>(
              value: coat,
              items: coatingOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setSub(() => coat = v!),
              decoration: const InputDecoration(labelText: 'Coating *'),
            ),
            const SizedBox(height: 10),

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
                  if (curSize.isEmpty || curGrade.isEmpty) ...[
                    const Text('Size aur Grade enter karein taake verified stock nazar aaye.', style: TextStyle(fontSize: 12, color: Colors.blueGrey)),
                  ] else if (isPainted) ...[
                    Text('Ready Painted in Yard: $readyInYard Pcs', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.teal)),
                    Text('Total Available to Issue (Yard + $parentName): $totalAvail Pcs', style: TextStyle(fontWeight: FontWeight.bold, color: totalAvail > 0 ? Colors.green.shade800 : Colors.red.shade800)),
                    Text('* Pehle yard ka ready pipe ($readyInYard Pcs) use hoga, baaqi $parentName se minus hoga.', style: const TextStyle(fontSize: 11, color: Colors.black87)),
                  ] else ...[
                    Text('Available Physical Stock in Yard: $totalAvail Pcs${isCutPiece ? " ($readyMeters Meters)" : ""}', style: TextStyle(fontWeight: FontWeight.bold, color: totalAvail > 0 ? Colors.green.shade800 : Colors.red.shade800)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity (Pieces) *'), onChanged: (_) => setSub(() {})),
                ),
                if (isCutPiece) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(controller: metersCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Length (Meters) *')),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),

            TextField(controller: personCtrl, decoration: const InputDecoration(labelText: 'Issued To / Person Name *')),
            const SizedBox(height: 8),

            DropdownButtonFormField<String>(
              value: loc,
              items: sortedLocs.map((l) => DropdownMenuItem(value: l, child: Text(l))).toList(),
              onChanged: (v) => setSub(() => loc = v!),
              decoration: const InputDecoration(labelText: 'Destination Location *'),
            ),
            const SizedBox(height: 8),

            DropdownButtonFormField<String>(
              value: jp,
              items: sortedJps.map((j) => DropdownMenuItem(value: j, child: Text(j))).toList(),
              onChanged: (v) => setSub(() => jp = v!),
              decoration: const InputDecoration(labelText: 'JP Name *'),
            ),
            const SizedBox(height: 20),

            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF25F22), padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () async {
                final s = sizeCtrl.text.trim();
                final g = gradeCtrl.text.trim();
                final sch = schCtrl.text.trim();
                double req = double.tryParse(qtyCtrl.text) ?? 0;
                double reqMeters = double.tryParse(metersCtrl.text) ?? 0.0;

                if (s.isEmpty || g.isEmpty || req <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter valid fields!')));
                  return;
                }

                final freshTotal = _getTotalAvailableToIssue(s, g, sch, cat, coat);
                if (req > freshTotal) {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Insufficient Stock Blocked', style: TextStyle(color: Colors.red)),
                      content: Text('Cannot issue $req pieces. Only $freshTotal available in store.'),
                      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                    ),
                  );
                  return;
                }

                final authorized = await _authenticateAction('Issue Material');
                if (!authorized) return;

                setState(() {
                  transactions.add({
                    'id': const Uuid().v4(),
                    'type': 'ISSUE',
                    'category': cat,
                    'pipeSize': s,
                    'pipeGrade': g,
                    'pipeSch': sch,
                    'itemClass': isElbowOrFlange ? sch : '',
                    'internalCoating': coat,
                    'quantity': req,
                    'lengthMeters': reqMeters,
                    'entity': personCtrl.text.trim(),
                    'location': loc,
                    'jpName': jp,
                    'date': DateFormat('yyyy-MM-dd').format(selectedDate),
                    'remarks': isPainted ? 'Painted issue deduction' : '',
                  });
                });
                _saveData();
                _syncWithCloud(silent: true);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Authorized: $cat Issued Successfully!')));
                  setState(() => _navIndex = 0);
                }
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock, color: Colors.white, size: 18),
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

  Widget _buildReturning() {
    final sizeCtrl = TextEditingController();
    final gradeCtrl = TextEditingController();
    final schCtrl = TextEditingController();
    final qtyCtrl = TextEditingController();
    final metersCtrl = TextEditingController();
    final returnFromCtrl = TextEditingController();
    final remarksCtrl = TextEditingController();

    String cat = categories.first;
    String coat = coatingOptions.first;
    DateTime selectedDate = DateTime.now();

    return StatefulBuilder(
      builder: (context, setSub) {
        final isElbowOrFlange = (cat == 'Elbow' || cat == 'Flange');
        final isCutPiece = (cat == 'Cut Piece');

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Row(
              children: [
                Icon(Icons.assignment_return, color: Colors.teal, size: 26),
                SizedBox(width: 8),
                Text('Material Return (Site Wapsi)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.teal)),
              ],
            ),
            const SizedBox(height: 6),
            const Text('Returned pipes, elbows, aur flanges usi category ke ready stock mein add honge.', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(color: Colors.teal.shade50, borderRadius: BorderRadius.circular(8)),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Return Date (Auto-filled)', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      Text(DateFormat('yyyy-MM-dd').format(selectedDate), style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
                    icon: const Icon(Icons.calendar_month, color: Colors.white, size: 16),
                    label: const Text('Change Date', style: TextStyle(color: Colors.white, fontSize: 12)),
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

            DropdownButtonFormField<String>(
              value: cat,
              items: _getSortedList(categories, pinnedCategories)
                  .map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setSub(() => cat = v!),
              decoration: const InputDecoration(labelText: 'Item Category *'),
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(child: TextField(controller: sizeCtrl, decoration: const InputDecoration(labelText: 'Size *'))),
                const SizedBox(width: 8),
                Expanded(child: TextField(controller: gradeCtrl, decoration: const InputDecoration(labelText: 'Grade *'))),
              ],
            ),
            const SizedBox(height: 8),

            TextField(
              controller: schCtrl,
              decoration: InputDecoration(
                labelText: isElbowOrFlange ? 'Class / Rating (Strict) *' : 'Pipe SCH (Strict) *',
              ),
            ),
            const SizedBox(height: 8),

            DropdownButtonFormField<String>(
              value: coat,
              items: coatingOptions.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
              onChanged: (v) => setSub(() => coat = v!),
              decoration: const InputDecoration(labelText: 'Coating *'),
            ),
            const SizedBox(height: 8),

            Row(
              children: [
                Expanded(
                  child: TextField(controller: qtyCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Quantity (Pcs) Returned *')),
                ),
                if (isCutPiece) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(controller: metersCtrl, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Length (Meters) *')),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),

            TextField(controller: returnFromCtrl, decoration: const InputDecoration(labelText: 'Returned From (Site / Person) *')),
            const SizedBox(height: 8),

            TextField(controller: remarksCtrl, decoration: const InputDecoration(labelText: 'Reason for Return (Surplus / Complete)')),
            const SizedBox(height: 20),

            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal, padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () async {
                if (qtyCtrl.text.isEmpty || sizeCtrl.text.isEmpty || gradeCtrl.text.isEmpty || returnFromCtrl.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please fill mandatory fields!')));
                  return;
                }

                final authorized = await _authenticateAction('Add Return Entry');
                if (!authorized) return;

                setState(() {
                  transactions.add({
                    'id': const Uuid().v4(),
                    'type': 'RETURN',
                    'category': cat,
                    'pipeSize': sizeCtrl.text.trim(),
                    'pipeGrade': gradeCtrl.text.trim(),
                    'pipeSch': schCtrl.text.trim(),
                    'itemClass': isElbowOrFlange ? schCtrl.text.trim() : '',
                    'internalCoating': coat,
                    'quantity': double.parse(qtyCtrl.text),
                    'lengthMeters': double.tryParse(metersCtrl.text) ?? 0.0,
                    'entity': returnFromCtrl.text.trim(),
                    'date': DateFormat('yyyy-MM-dd').format(selectedDate),
                    'remarks': remarksCtrl.text.trim(),
                  });
                });
                _saveData();
                _syncWithCloud(silent: true);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Success: Returned $cat added back to yard stock!')));
                  setState(() => _navIndex = 0);
                }
              },
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.lock, color: Colors.white, size: 18),
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
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0A2540)),
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
              final isCutPiece = (cat == 'Cut Piece');
              final isElbowOrFlange = (cat == 'Elbow' || cat == 'Flange');

              final specMap = <String, Map<String, String>>{};
              for (var t in transactions) {
                final s = (t['pipeSize'] ?? '').toString().trim();
                final g = (t['pipeGrade'] ?? '').toString().trim();
                final sch = (t['pipeSch'] ?? t['itemClass'] ?? '').toString().trim();
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

              final relevantSpecs = specMap.values.where((spec) {
                final s = spec['size']!;
                final g = spec['grade']!;
                final sch = spec['sch']!;
                double cBal = _getPhysicalStockQty(s, g, sch, cat, 'Internal Coated');
                double uBal = _getPhysicalStockQty(s, g, sch, cat, 'Without Internal Coating');
                return (cBal > 0 || uBal > 0);
              }).toList();

              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                elevation: 2,
                child: ExpansionTile(
                  initiallyExpanded: relevantSpecs.isNotEmpty,
                  title: Row(
                    children: [
                      Text(cat, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Color(0xFF0A2540))),
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
                                  ? 'Abhi yard mein koi ready $cat nahi hai (Wapsi aane par yahan show hoga).'
                                  : 'No material in stock under this category.',
                              style: const TextStyle(color: Colors.grey),
                            ),
                          )
                        ]
                      : relevantSpecs.map((spec) {
                          final size = spec['size']!;
                          final grade = spec['grade']!;
                          final sch = spec['sch']!;

                          double cBal = _getPhysicalStockQty(size, grade, sch, cat, 'Internal Coated');
                          double uBal = _getPhysicalStockQty(size, grade, sch, cat, 'Without Internal Coating');
                          double cMeters = _getPhysicalStockMeters(size, grade, sch, cat, 'Internal Coated');
                          double uMeters = _getPhysicalStockMeters(size, grade, sch, cat, 'Without Internal Coating');

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
                                    Expanded(child: Text('Size: $size | Grade: $grade | ${isElbowOrFlange ? "Class" : "SCH"}: $sch', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF0F172A)))),
                                    Text(
                                      isPainted ? 'In Yard: ${cBal + uBal}' : 'Available: ${cBal + uBal}',
                                      style: TextStyle(fontWeight: FontWeight.bold, color: isPainted ? Colors.teal : Colors.blueAccent),
                                    ),
                                  ],
                                ),
                                if (isCutPiece) ...[
                                  const SizedBox(height: 2),
                                  Text('Kul Length: ${cMeters + uMeters} Meters', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.deepOrange)),
                                ],
                                const Divider(height: 14),
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    const Row(
                                      children: [
                                        Icon(Icons.circle, size: 8, color: Colors.teal),
                                        SizedBox(width: 6),
                                        Text('Internal Coated:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                      ],
                                    ),
                                    Text('$cBal Pcs${isCutPiece ? " ($cMeters m)" : ""}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: cBal > 0 ? Colors.green.shade800 : Colors.grey.shade600)),
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
                                        Text('Without Internal Coating:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                                      ],
                                    ),
                                    Text('$uBal Pcs${isCutPiece ? " ($uMeters m)" : ""}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: uBal > 0 ? Colors.green.shade800 : Colors.grey.shade600)),
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
        final schMatch = (t['pipeSch'] ?? t['itemClass'] ?? '').toString().toLowerCase().contains(q);
        final catMatch = (t['category'] ?? '').toString().toLowerCase().contains(q);
        final dateMatch = (t['date'] ?? '').toString().toLowerCase().contains(q);
        final remarksMatch = (t['remarks'] ?? '').toString().toLowerCase().contains(q);

        return locMatch || gradeMatch || sizeMatch || schMatch || catMatch || dateMatch || remarksMatch;
      }
      return true;
    }).toList();

    final Map<String, double> summaryTotals = {};
    double cutPieceTotalMeters = 0.0;
    for (var t in filtered) {
      final cat = t['category'] ?? 'Other';
      final q = (t['quantity'] as num?)?.toDouble() ?? 0.0;
      summaryTotals[cat] = (summaryTotals[cat] ?? 0.0) + q;
      if (cat == 'Cut Piece') {
        cutPieceTotalMeters += (t['lengthMeters'] as num?)?.toDouble() ?? 0.0;
      }
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
          child: TextField(
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Search Location, Grade, Class, Size, SCH...',
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
                  label: const Text('Returns'),
                  selected: _historyTypeFilter == 'RETURN',
                  selectedColor: Colors.teal.shade100,
                  onSelected: (_) => setState(() => _historyTypeFilter = 'RETURN'),
                ),
              ],
            ),
          ),
        ),

        if (summaryTotals.isNotEmpty)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.blueGrey.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.blueGrey.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Search Results Summary (${filtered.length} entries):', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Color(0xFF0A2540))),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0A2540), padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2)),
                      icon: const Icon(Icons.file_download, color: Colors.white, size: 14),
                      label: const Text('Export Excel/PDF', style: TextStyle(color: Colors.white, fontSize: 11)),
                      onPressed: () => _showExportChoiceDialog(_historyTypeFilter, customList: filtered),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: summaryTotals.entries.map((e) {
                    final isCp = e.key == 'Cut Piece';
                    return Chip(
                      visualDensity: VisualDensity.compact,
                      label: Text('${e.key}: ${e.value.toStringAsFixed(0)} Pcs${isCp ? " ($cutPieceTotalMeters m)" : ""}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      backgroundColor: Colors.white,
                    );
                  }).toList(),
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

                    IconData icon = t['type'] == 'RECEIVE' ? Icons.download : (t['type'] == 'RETURN' ? Icons.assignment_return : Icons.upload);
                    Color color = t['type'] == 'RECEIVE' ? Colors.green : (t['type'] == 'RETURN' ? Colors.teal : Colors.orange);

                    final schClass = t['pipeSch'] ?? t['itemClass'] ?? '';
                    final meters = (t['lengthMeters'] ?? 0) > 0 ? " | Length: ${t['lengthMeters']}m" : "";

                    return Card(
                      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      child: ListTile(
                        leading: CircleAvatar(backgroundColor: color.withOpacity(0.12), child: Icon(icon, color: color)),
                        title: Text('${t['category']} (${t['pipeSize']}) - ${t['internalCoating']}'),
                        subtitle: Text('Grade: ${t['pipeGrade']} | SCH/Class: $schClass\nQty: ${t['quantity']} Pcs$meters | Date: ${t['date']}\nLoc: ${t['entity'] ?? t['location']}${t['jpName'] != null ? ' | JP: ${t['jpName']}' : ''}'),
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

  Widget _buildManageAndBackup() {
    final rLocCtrl = TextEditingController();
    final iLocCtrl = TextEditingController();
    final jpCtrl = TextEditingController();
    final restoreTextCtrl = TextEditingController();
    final firebaseUrlCtrl = TextEditingController(text: _firebaseUrl);
    final cloudIdCtrl = TextEditingController(text: _cloudStoreId);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Security & Management', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF0A2540))),
            IconButton(
              icon: const Icon(Icons.lock, color: Colors.red),
              tooltip: 'Lock Settings Again',
              onPressed: () {
                setState(() {
                  _isSettingsUnlocked = false;
                  _navIndex = 0;
                });
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Settings Locked!')));
              },
            ),
          ],
        ),
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
                    const Text('Google Firebase Realtime Sync', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text(_lastSyncStatus, style: TextStyle(fontSize: 11, color: _lastSyncStatus.startsWith('Synced') ? Colors.green.shade800 : Colors.blue.shade800, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('Apna Google Firebase URL yahan paste karein taake Mobile aur PC ka data shared rahe.'),
                const SizedBox(height: 8),
                TextField(
                  controller: firebaseUrlCtrl,
                  decoration: const InputDecoration(labelText: 'Firebase URL', border: OutlineInputBorder(), hintText: 'https://...firebaseio.com'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(controller: cloudIdCtrl, decoration: const InputDecoration(labelText: 'Store Key', border: OutlineInputBorder())),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0A2540)),
                      onPressed: () {
                        setState(() {
                          _firebaseUrl = firebaseUrlCtrl.text.trim();
                          _cloudStoreId = cloudIdCtrl.text.trim();
                        });
                        _saveData();
                        _syncWithCloud(silent: false);
                      },
                      child: const Text('Save & Connect', style: TextStyle(color: Colors.white)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const Divider(height: 28),

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
                    const Text('Master PIN Security', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                    Text('Current PIN: $_securityPin', style: const TextStyle(color: Colors.black87)),
                  ],
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0A2540)),
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
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PIN Updated!')));
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

        const Text('Backup & Data Protection', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 6),
        Card(
          color: Colors.green.shade50,
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Daily Auto-Backup Active', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                const Text('App rozana pehli entry par automatically date ke hisab se backup file save karti hai.', style: TextStyle(fontSize: 12)),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0A2540)),
                  icon: const Icon(Icons.download, color: Colors.white, size: 16),
                  label: const Text('EXPORT MANUAL BACKUP', style: TextStyle(color: Colors.white)),
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
                        content: Text('File saved at:\n${bFile.path}\n\nData clipboard mein copy ho gaya hai!'),
                        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),
                TextField(controller: restoreTextCtrl, maxLines: 2, decoration: const InputDecoration(hintText: 'Paste backup JSON to restore...', border: OutlineInputBorder())),
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
                      });
                      _saveData();
                      _syncWithCloud(silent: true);
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

        const Text('Receiving Locations (Pin ⭐ to Top / Edit)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Row(
          children: [
            Expanded(child: TextField(controller: rLocCtrl, decoration: const InputDecoration(labelText: 'New Location'))),
            IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.blue, size: 30),
              onPressed: () {
                if (rLocCtrl.text.isNotEmpty) {
                  setState(() => receivingLocations.add(rLocCtrl.text.trim()));
                  _saveData();
                  rLocCtrl.clear();
                }
              },
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: receivingLocations.map((l) {
            final isPinned = pinnedLocations.contains(l);
            return InputChip(
              avatar: Icon(isPinned ? Icons.star : Icons.star_border, size: 16, color: Colors.amber.shade900),
              label: Text(l),
              onPressed: () {
                setState(() {
                  if (isPinned) {
                    pinnedLocations.remove(l);
                  } else {
                    pinnedLocations.add(l);
                  }
                });
                _saveData();
              },
              deleteIcon: const Icon(Icons.edit, size: 16),
              onDeleted: () => _renameLocationOrJpDialog(isLocation: true, oldName: l),
            );
          }).toList(),
        ),
        const Divider(height: 24),

        const Text('Issue Locations (Pin ⭐ to Top / Edit)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Row(
          children: [
            Expanded(child: TextField(controller: iLocCtrl, decoration: const InputDecoration(labelText: 'New Destination'))),
            IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.green, size: 30),
              onPressed: () {
                if (iLocCtrl.text.isNotEmpty) {
                  setState(() => issueLocations.add(iLocCtrl.text.trim()));
                  _saveData();
                  iLocCtrl.clear();
                }
              },
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: issueLocations.map((l) {
            final isPinned = pinnedLocations.contains(l);
            return InputChip(
              avatar: Icon(isPinned ? Icons.star : Icons.star_border, size: 16, color: Colors.amber.shade900),
              label: Text(l),
              onPressed: () {
                setState(() {
                  if (isPinned) {
                    pinnedLocations.remove(l);
                  } else {
                    pinnedLocations.add(l);
                  }
                });
                _saveData();
              },
              deleteIcon: const Icon(Icons.edit, size: 16),
              onDeleted: () => _renameLocationOrJpDialog(isLocation: true, oldName: l),
            );
          }).toList(),
        ),
        const Divider(height: 24),

        const Text('JP Names (Pin ⭐ to Top / Edit)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        Row(
          children: [
            Expanded(child: TextField(controller: jpCtrl, decoration: const InputDecoration(labelText: 'New JP Name'))),
            IconButton(
              icon: const Icon(Icons.add_circle, color: Colors.orange, size: 30),
              onPressed: () {
                if (jpCtrl.text.isNotEmpty) {
                  setState(() => jpNames.add(jpCtrl.text.trim()));
                  _saveData();
                  jpCtrl.clear();
                }
              },
            ),
          ],
        ),
        Wrap(
          spacing: 8,
          children: jpNames.map((j) {
            final isPinned = pinnedJpNames.contains(j);
            return InputChip(
              avatar: Icon(isPinned ? Icons.star : Icons.star_border, size: 16, color: Colors.amber.shade900),
              label: Text(j),
              onPressed: () {
                setState(() {
                  if (isPinned) {
                    pinnedJpNames.remove(j);
                  } else {
                    pinnedJpNames.add(j);
                  }
                });
                _saveData();
              },
              deleteIcon: const Icon(Icons.edit, size: 16),
              onDeleted: () => _renameLocationOrJpDialog(isLocation: false, oldName: j),
            );
          }).toList(),
        ),
      ],
    );
  }
}
