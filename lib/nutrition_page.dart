import 'dart:convert'; // Import for JSON encoding/decoding
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:csv/csv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

// -----------------------------------------------------------------------------
// 1. DATA MODEL
// -----------------------------------------------------------------------------

class FoodItem {
  final String name;
  final String category;
  final double calories;
  final double protein;
  final double fiber;
  final double water;

  FoodItem({
    required this.name,
    required this.category,
    required this.calories,
    required this.protein,
    required this.fiber,
    required this.water,
  });

  // From CSV
  factory FoodItem.fromCsv(List<dynamic> row) {
    return FoodItem(
      name: row[0].toString(),
      category: row[1].toString(),
      calories: double.tryParse(row[2].toString()) ?? 0.0,
      protein: double.tryParse(row[3].toString()) ?? 0.0,
      fiber: double.tryParse(row[6].toString()) ?? 0.0,
      water: (row.length > 11)
          ? (double.tryParse(row[11].toString()) ?? 0.0)
          : 0.0,
    );
  }

  // --- NEW: Convert to JSON for Database ---
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'category': category,
      'calories': calories,
      'protein': protein,
      'fiber': fiber,
      'water': water,
    };
  }

  // --- NEW: Create from JSON from Database ---
  factory FoodItem.fromJson(Map<String, dynamic> json) {
    return FoodItem(
      name: json['name'] ?? '',
      category: json['category'] ?? '',
      calories: (json['calories'] as num).toDouble(),
      protein: (json['protein'] as num).toDouble(),
      fiber: (json['fiber'] as num).toDouble(),
      water: (json['water'] as num).toDouble(),
    );
  }
}

// -----------------------------------------------------------------------------
// 2. UI & LOGIC
// -----------------------------------------------------------------------------

class NutritionPage extends StatefulWidget {
  const NutritionPage({super.key});

  @override
  State<NutritionPage> createState() => _NutritionPageState();
}

class _NutritionPageState extends State<NutritionPage> {
  final _supabase = Supabase.instance.client;

  List<FoodItem> _allFoods = [];
  List<FoodItem> _filteredFoods = [];
  List<FoodItem> _consumedFoods = [];

  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _targetWeightController = TextEditingController();

  bool _isLoading = true;

  // --- TARGETS ---
  double _targetCalories = 2000;
  double _targetProtein = 60;
  double _targetFiber = 30;
  double _targetWater = 2000;

  double _currentWeight = 60;
  double _userHeight = 170;
  double _goalWeight = 60;
  int _daysToReachGoal = 0;

  // --- LIVE DATA ---
  double _manualWater = 0.0;
  double _totalCalories = 0;
  double _totalProtein = 0;
  double _totalFiber = 0;
  double _totalWater = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    await Future.wait([_loadCsvData(), _loadProfileAndLog()]);
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadCsvData() async {
    try {
      final rawData = await rootBundle.loadString(
        "assets/daily_food_nutrition_dataset.csv",
      );
      List<List<dynamic>> listData = const CsvToListConverter().convert(
        rawData,
        eol: '\n',
        shouldParseNumbers: true,
      );
      final parsedFoods = listData
          .skip(1)
          .map((row) => FoodItem.fromCsv(row))
          .toList();

      if (mounted) {
        setState(() {
          _allFoods = parsedFoods;
          _filteredFoods = parsedFoods;
        });
      }
    } catch (e) {
      debugPrint("Error loading CSV: $e");
    }
  }

  Future<void> _loadProfileAndLog() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) return;

      // 1. Fetch Profile (Current Weight & Goal Weight)
      final profile = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .maybeSingle();

      if (!mounted) return;

      if (profile != null) {
        setState(() {
          _currentWeight = (profile['weight'] as num?)?.toDouble() ?? 60.0;
          _userHeight = (profile['height'] as num?)?.toDouble() ?? 170.0;
          // Load saved goal, or default to current
          _goalWeight =
              (profile['goal_weight'] as num?)?.toDouble() ?? _currentWeight;

          _targetWeightController.text = _goalWeight.toString();
          _recalculateTargets();
        });
      }

      // 2. Fetch Today's Log (Totals & Food List)
      final String today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final log = await _supabase
          .from('nutrition_logs')
          .select()
          .eq('user_id', user.id)
          .eq('log_date', today)
          .maybeSingle();

      if (!mounted) return;

      if (log != null) {
        setState(() {
          _totalCalories = (log['total_calories'] as num).toDouble();
          _totalProtein = (log['total_protein'] as num).toDouble();
          _totalFiber = (log['total_fiber'] as num).toDouble();
          _totalWater = (log['total_water'] as num).toDouble();

          // Reconstruct Manual Water (Total - Sum of Food Water if we tracked it, but here we assume total is mostly manual + logic)
          // For simplicity in this logic we restore manual water as total water
          _manualWater = _totalWater;

          // RESTORE FOOD LIST FROM JSON
          if (log['consumed_foods'] != null) {
            final List<dynamic> foodJson = log['consumed_foods'];
            _consumedFoods = foodJson
                .map((json) => FoodItem.fromJson(json))
                .toList();
          }
        });
      }
    } catch (e) {
      debugPrint("Error loading log: $e");
    }
  }

  // --- SAVE TOTALS + FOOD LIST ---
  Future<void> _saveDailyLog() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return;
    final String today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    try {
      await _supabase.from('nutrition_logs').upsert({
        'user_id': user.id,
        'log_date': today,
        'total_calories': _totalCalories,
        'total_protein': _totalProtein,
        'total_fiber': _totalFiber,
        'total_water': _totalWater,
        'consumed_foods': _consumedFoods
            .map((e) => e.toJson())
            .toList(), // <--- Save List
      }, onConflict: 'user_id, log_date');
    } catch (e) {
      debugPrint("Error saving log: $e");
    }
  }

  void _showHistory() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      builder: (context) {
        return FutureBuilder(
          future: _supabase
              .from('nutrition_logs')
              .select()
              .eq('user_id', _supabase.auth.currentUser!.id)
              .order('log_date', ascending: false)
              .limit(7),
          builder: (context, snapshot) {
            if (!snapshot.hasData)
              return const Center(child: CircularProgressIndicator());
            final logs = snapshot.data as List<dynamic>;

            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "7-Day History",
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: ListView.separated(
                      itemCount: logs.length,
                      separatorBuilder: (_, __) => const Divider(),
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            DateFormat(
                              'MMM d',
                            ).format(DateTime.parse(log['log_date'])),
                          ),
                          subtitle: Text(
                            "Cal: ${log['total_calories']} | Water: ${log['total_water']}ml",
                          ),
                          trailing:
                              ((log['total_water'] as num) >= _targetWater)
                              ? const Icon(
                                  Icons.check_circle,
                                  color: Colors.green,
                                )
                              : const Icon(
                                  Icons.water_drop,
                                  color: Colors.grey,
                                ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _recalculateTargets() {
    double adjustedCalories = _currentWeight * 30 * 1.2;
    double weightDiff = _goalWeight - _currentWeight;

    if (weightDiff > 0.5) {
      adjustedCalories += 500;
      _daysToReachGoal = (weightDiff / 0.065).round();
    } else if (weightDiff < -0.5) {
      adjustedCalories -= 500;
      if (adjustedCalories < 1200) adjustedCalories = 1200;
      _daysToReachGoal = (weightDiff.abs() / 0.065).round();
    } else {
      _daysToReachGoal = 0;
    }

    setState(() {
      _targetCalories = adjustedCalories;
      _targetProtein = _currentWeight * (weightDiff > 0 ? 1.6 : 1.0);
      _targetWater = _currentWeight * 35;
      _targetFiber = (adjustedCalories / 1000) * 14;
    });
  }

  // --- SAVE GOAL TO PROFILE ---
  Future<void> _updateGoal(String value) async {
    double? val = double.tryParse(value);
    if (val != null && val > 0) {
      setState(() {
        _goalWeight = val;
        _recalculateTargets();
      });

      // Save to Supabase Profile
      try {
        final user = _supabase.auth.currentUser;
        if (user != null) {
          await _supabase
              .from('profiles')
              .update({'goal_weight': val})
              .eq('id', user.id);
        }
      } catch (e) {
        debugPrint("Error saving goal: $e");
      }
    }
  }

  void _filterFoods(String query) {
    if (query.isEmpty) {
      setState(() => _filteredFoods = _allFoods);
    } else {
      setState(() {
        _filteredFoods = _allFoods
            .where(
              (food) => food.name.toLowerCase().contains(query.toLowerCase()),
            )
            .toList();
      });
    }
  }

  int get _balanceScore {
    double score = 100;
    if (_totalProtein < _targetProtein * 0.5) score -= 20;
    if (_totalFiber < _targetFiber * 0.5) score -= 15;
    if (_totalWater < _targetWater * 0.5) score -= 15;
    if (_totalCalories > _targetCalories * 1.15) score -= 15;
    return score.clamp(0, 100).toInt();
  }

  List<String> get _risks {
    List<String> list = [];
    if (_totalCalories < _targetCalories * 0.4)
      list.add("Low Energy Availability");
    if (_totalCalories > _targetCalories * 1.2) list.add("Caloric Surplus");
    if (_totalProtein < _targetProtein * 0.5) list.add("Muscle Atrophy Risk");
    if (_totalWater < _targetWater * 0.3) list.add("Severe Dehydration Risk");
    return list;
  }

  void _addFood(FoodItem food) {
    setState(() {
      _consumedFoods.add(food);
      _totalCalories += food.calories;
      _totalProtein += food.protein;
      _totalFiber += food.fiber;
    });

    _saveDailyLog();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Added ${food.name}"),
          duration: const Duration(milliseconds: 500),
          backgroundColor: Colors.blue.shade700,
        ),
      );
    }
  }

  void _addManualWater(double amount) {
    setState(() {
      _manualWater += amount;
      _totalWater += amount;
    });
    _saveDailyLog();
  }

  void _resetDay() {
    setState(() {
      _consumedFoods.clear();
      _manualWater = 0;
      _totalCalories = 0;
      _totalProtein = 0;
      _totalFiber = 0;
      _totalWater = 0;
    });
    _saveDailyLog();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF5F7FA),
        body: Center(child: CircularProgressIndicator(color: Colors.blue)),
      );
    }

    final score = _balanceScore;
    final risks = _risks;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      // --- APP BAR REMOVED ---
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // --- HEADER ---
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    "Nutrition Digital Twin",
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1565C0),
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.history, color: Colors.black54),
                        onPressed: _showHistory,
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Colors.black54),
                        onPressed: _resetDay,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // --- 1. GOAL SETTING ---
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Current Weight",
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            "${_currentWeight} kg",
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward, color: Colors.blue),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 4,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Target Weight (kg)",
                            style: TextStyle(
                              color: Colors.blue.shade700,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(
                            height: 40,
                            child: TextField(
                              controller: _targetWeightController,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                isDense: true,
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                              ),
                              onSubmitted: _updateGoal,
                              // Note: We use onSubmitted for DB save to avoid too many writes while typing
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // --- 2. TWIN STATUS ---
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade800, Colors.blue.shade500],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 5),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        SizedBox(
                          width: 70,
                          height: 70,
                          child: CircularProgressIndicator(
                            value: score / 100,
                            backgroundColor: Colors.white24,
                            color: score > 70
                                ? Colors.greenAccent
                                : Colors.orangeAccent,
                            strokeWidth: 8,
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                "Daily Requirement",
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                "${_targetCalories.toInt()} kcal",
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 24,
                                ),
                              ),
                              Text(
                                _goalWeight > _currentWeight
                                    ? "Surplus Mode (Gain)"
                                    : _goalWeight < _currentWeight
                                    ? "Deficit Mode (Loss)"
                                    : "Maintenance Mode",
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (_daysToReachGoal > 0) ...[
                      const Divider(color: Colors.white24, height: 24),
                      Row(
                        children: [
                          const Icon(
                            Icons.timer,
                            color: Colors.white,
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "Est. time to reach ${_goalWeight}kg: $_daysToReachGoal days",
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // --- 3. LIVE DASHBOARD ---
              _buildNutrientBar(
                "Calories",
                _totalCalories,
                _targetCalories,
                Colors.orange,
                "kcal",
              ),
              _buildNutrientBar(
                "Protein",
                _totalProtein,
                _targetProtein,
                Colors.redAccent,
                "g",
              ),
              _buildNutrientBar(
                "Fiber",
                _totalFiber,
                _targetFiber,
                Colors.green,
                "g",
              ),

              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildNutrientBar(
                    "Water Intake",
                    _totalWater,
                    _targetWater,
                    Colors.blue,
                    "ml",
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      _buildWaterButton(250),
                      const SizedBox(width: 8),
                      _buildWaterButton(500),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),

              const SizedBox(height: 24),

              // --- 4. FOOD SEARCH ---
              const Text(
                "Add Food",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                onChanged: _filterFoods,
                decoration: InputDecoration(
                  hintText: "Search food...",
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // --- 5. SEARCH RESULTS LIST ---
              Container(
                height: 350,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: _filteredFoods.isEmpty
                    ? const Center(
                        child: Text(
                          "No foods found",
                          style: TextStyle(color: Colors.grey),
                        ),
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.all(8),
                        itemCount: _filteredFoods.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final food = _filteredFoods[index];
                          return ListTile(
                            title: Text(
                              food.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              "${food.calories.toInt()} kcal • ${food.protein}g Prot",
                            ),
                            trailing: const Icon(
                              Icons.add_circle_outline,
                              color: Colors.blue,
                            ),
                            onTap: () => _addFood(food),
                          );
                        },
                      ),
              ),

              const SizedBox(height: 24),

              // --- 6. EATEN TODAY ---
              if (_consumedFoods.isNotEmpty) ...[
                const Text(
                  "Eaten Today",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.blue.shade50),
                  ),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _consumedFoods
                        .map(
                          (f) => Chip(
                            label: Text(f.name),
                            backgroundColor: Colors.blue.shade50,
                            side: BorderSide.none,
                            labelStyle: TextStyle(
                              color: Colors.blue.shade900,
                              fontWeight: FontWeight.bold,
                            ),
                            onDeleted: () {
                              setState(() {
                                _consumedFoods.remove(f);
                                _totalCalories -= f.calories;
                                _totalProtein -= f.protein;
                                _totalFiber -= f.fiber;
                              });
                              _saveDailyLog();
                            },
                            deleteIconColor: Colors.blue.shade300,
                          ),
                        )
                        .toList(),
                  ),
                ),
              ],

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWaterButton(double amount) {
    return InkWell(
      onTap: () => _addManualWater(amount),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.blue.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.blue.shade200),
        ),
        child: Row(
          children: [
            const Icon(Icons.add, size: 14, color: Colors.blue),
            Text(
              " ${amount.toInt()}ml",
              style: TextStyle(
                color: Colors.blue.shade800,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNutrientBar(
    String label,
    double current,
    double target,
    Color color,
    String unit,
  ) {
    double progress = (target > 0) ? (current / target).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(
                "${current.toInt()} / ${target.toInt()} $unit",
                style: const TextStyle(color: Colors.grey, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          LinearProgressIndicator(
            value: progress,
            color: color,
            backgroundColor: color.withOpacity(0.15),
            minHeight: 10,
            borderRadius: BorderRadius.circular(5),
          ),
        ],
      ),
    );
  }
}
