import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:scalptamizhan/insights_page.dart';
import 'package:scalptamizhan/nutrition_page.dart';
import 'package:scalptamizhan/profile.dart'; // Ensure this matches your file name
import 'package:supabase_flutter/supabase_flutter.dart';

// -----------------------------------------------------------------------------
// 1. DATA MODEL & LOGIC
// -----------------------------------------------------------------------------

enum WellnessState { balanced, overloaded, recovery }

class DailyLog {
  final int? id;
  final DateTime date;
  final double sleepHours;
  final int steps;
  final double moodRating;
  final double screenTimeHours;
  final WellnessState state;

  DailyLog({
    this.id,
    required this.date,
    required this.sleepHours,
    required this.steps,
    required this.moodRating,
    required this.screenTimeHours,
    required this.state,
  });

  factory DailyLog.fromJson(Map<String, dynamic> json) {
    return DailyLog(
      id: json['id'],
      date: DateTime.parse(json['date']),
      sleepHours: (json['sleep_hours'] as num).toDouble(),
      steps: json['steps'],
      moodRating: (json['mood_rating'] as num).toDouble(),
      screenTimeHours: (json['screen_time_hours'] as num).toDouble(),
      state: WellnessState.values.byName(json['wellness_state'] ?? 'balanced'),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'date': DateFormat('yyyy-MM-dd').format(date),
      'sleep_hours': sleepHours,
      'steps': steps,
      'mood_rating': moodRating,
      'screen_time_hours': screenTimeHours,
      'wellness_state': state.name,
    };
  }

  int get wellnessScore {
    double sleepScore = (sleepHours / 8.0) * 35;
    double stepScore = (steps / 10000.0) * 30;
    double moodScore = (moodRating / 10.0) * 25;

    double screenPenalty = 0;
    if (screenTimeHours > 4) {
      screenPenalty = (screenTimeHours - 4) * 5;
    }

    double total = sleepScore + stepScore + moodScore - screenPenalty + 10;
    return total.clamp(0, 100).round();
  }

  String get burnoutRisk {
    int score = wellnessScore;
    if (score < 40) return "High";
    if (score < 70) return "Moderate";
    return "Low";
  }

  Color get color {
    switch (state) {
      case WellnessState.balanced:
        return Colors.green.shade600;
      case WellnessState.overloaded:
        return Colors.orange.shade700;
      case WellnessState.recovery:
        return Colors.red.shade600;
    }
  }

  static WellnessState calculateState(
    double sleep,
    int steps,
    double mood,
    double screen,
  ) {
    double sleepScore = (sleep / 8.0) * 35;
    double stepScore = (steps / 10000.0) * 30;
    double moodScore = (mood / 10.0) * 25;
    double screenPenalty = (screen > 4) ? (screen - 4) * 5 : 0;

    double total = sleepScore + stepScore + moodScore - screenPenalty + 10;
    int score = total.clamp(0, 100).round();

    if (score >= 75) return WellnessState.balanced;
    if (score >= 45) return WellnessState.overloaded;
    return WellnessState.recovery;
  }
}

// -----------------------------------------------------------------------------
// 2. STATE MANAGEMENT
// -----------------------------------------------------------------------------

class TwinProvider extends ChangeNotifier {
  final _supabase = Supabase.instance.client;
  List<DailyLog> _logs = [];
  bool _isLoading = false;

  List<DailyLog> get logs => _logs;
  bool get isLoading => _isLoading;

  Future<void> fetchLogs() async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _supabase
          .from('daily_logs')
          .select()
          .order('date', ascending: false);

      final data = response as List<dynamic>;
      _logs = data.map((json) => DailyLog.fromJson(json)).toList();
    } catch (e) {
      debugPrint('Error fetching logs: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addLog(DailyLog log) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) throw Exception("User not logged in");

      _logs.insert(0, log);
      notifyListeners();

      final data = log.toJson();
      data['user_id'] = user.id;

      await _supabase.from('daily_logs').insert(data);
      await fetchLogs();
    } catch (e) {
      debugPrint('Error adding log: $e');
      _logs.remove(log);
      notifyListeners();
      rethrow;
    }
  }
}

// -----------------------------------------------------------------------------
// 3. UI COMPONENTS
// -----------------------------------------------------------------------------

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  // REMOVED ProfilePage from this list
  final List<Widget> _pages = [
    const TimelineTab(),
    const InsightsPage(),
    const NutritionPage(),
    const HeatmapTab(),
    const InputTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text("Digital Twin Dashboard"),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        
        // --- MOVED PROFILE ICON TO ACTIONS ---
        actions: [
          IconButton(
            icon: const Icon(Icons.person, size: 28),
            onPressed: () {
              // Navigate to Profile Page
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const ProfilePage()),
              );
            },
          ),
          const SizedBox(width: 8),
        ],
        // -------------------------------------
      ),
      body: _pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.white,
        indicatorColor: Colors.blue.shade100,
        selectedIndex: _selectedIndex,
        onDestinationSelected: (int index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.timeline, color: Colors.black54),
              selectedIcon: Icon(Icons.timeline, color: Colors.blue),
              label: 'Timeline'),
          NavigationDestination(
              icon: Icon(Icons.lightbulb_outline), 
              selectedIcon: Icon(Icons.lightbulb, color: Colors.blue),
              label: 'Insights'),
          NavigationDestination(
              icon: Icon(Icons.restaurant_menu, color: Colors.black54),
              selectedIcon: Icon(Icons.restaurant_menu, color: Colors.blue),
              label: 'Nutrition',
              ),
          NavigationDestination(
              icon: Icon(Icons.grid_view, color: Colors.black54),
              selectedIcon: Icon(Icons.grid_view, color: Colors.blue),
              label: 'Heatmap'),
          NavigationDestination(
            icon: Icon(Icons.add_circle_outline, color: Colors.black54),
            selectedIcon: Icon(Icons.add_circle_outline, color: Colors.blue),
            label: 'Add Entry',
          ),
          // REMOVED Profile NavigationDestination
        ],
      ),
    );
  }
}

// --- TAB 1: TIMELINE VIEW ---

class TimelineTab extends StatelessWidget {
  const TimelineTab({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TwinProvider>(context);
    final logs = provider.logs;

    if (provider.isLoading && logs.isEmpty) {
      return const Center(child: CircularProgressIndicator(color: Colors.blue));
    }

    if (logs.isEmpty) {
      return const Center(
          child: Text("No data yet. Start tracking!",
              style: TextStyle(color: Colors.black54)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: logs.length,
      itemBuilder: (context, index) {
        final log = logs[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          elevation: 2,
          color: Colors.white,
          surfaceTintColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Colors.blue.shade100, width: 1),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      DateFormat('EEEE, MMM d').format(log.date),
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: Colors.black87,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: log.color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: log.color),
                      ),
                      child: Text(
                        "${log.state.name.toUpperCase()} (${log.wellnessScore})",
                        style: TextStyle(
                          color: log.color,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                Divider(height: 24, color: Colors.grey.shade200),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "INPUTS",
                            style: TextStyle(
                                fontSize: 10, color: Colors.blue.shade300),
                          ),
                          const SizedBox(height: 8),
                          _buildStatRow(
                              Icons.bed, "${log.sleepHours} hrs Sleep"),
                          _buildStatRow(
                              Icons.directions_walk, "${log.steps} Steps"),
                          _buildStatRow(Icons.mood,
                              "Mood: ${log.moodRating.toInt()}/10"),
                          _buildStatRow(Icons.phone_android,
                              "${log.screenTimeHours} hrs Screen"),
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Center(
                        child: Icon(
                          Icons.arrow_right_alt,
                          color: Colors.blue.shade200,
                          size: 30,
                        ),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            "OUTPUTS",
                            style: TextStyle(
                                fontSize: 10, color: Colors.blue.shade300),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Burnout Risk:",
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            log.burnoutRisk,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "Efficiency:",
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 12,
                            ),
                          ),
                          LinearProgressIndicator(
                            value: log.wellnessScore / 100,
                            color: log.color,
                            backgroundColor: Colors.grey.shade200,
                            minHeight: 6,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatRow(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.blue),
          const SizedBox(width: 8),
          Text(text,
              style: const TextStyle(fontSize: 13, color: Colors.black87)),
        ],
      ),
    );
  }
}

// --- TAB 2: HEATMAP VIEW ---

class HeatmapTab extends StatelessWidget {
  const HeatmapTab({super.key});

  @override
  Widget build(BuildContext context) {
    final logs = Provider.of<TwinProvider>(context).logs;

    if (logs.isEmpty) {
      return const Center(
          child: Text("Log data to see patterns.",
              style: TextStyle(color: Colors.black54)));
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Consistency Heatmap",
            style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.black87),
          ),
          const Text(
            "Visualizing your recovery patterns over time.",
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 20),
          Expanded(
            child: GridView.builder(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: logs.length,
              itemBuilder: (context, index) {
                final log = logs[index];
                return Container(
                  decoration: BoxDecoration(
                    color: log.color.withOpacity(0.8),
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      )
                    ],
                  ),
                  child: Center(
                    child: Text(
                      "${log.date.day}",
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildLegend(Colors.green.shade600, "Balanced"),
                _buildLegend(Colors.orange.shade700, "Overloaded"),
                _buildLegend(Colors.red.shade600, "Recovery"),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLegend(Color color, String label) {
    return Row(
      children: [
        Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(fontSize: 12, color: Colors.black87)),
      ],
    );
  }
}

// --- TAB 3: MANUAL INPUT VIEW ---

class InputTab extends StatefulWidget {
  const InputTab({super.key});

  @override
  State<InputTab> createState() => _InputTabState();
}

class _InputTabState extends State<InputTab> {
  final _formKey = GlobalKey<FormState>();

  DateTime _selectedDate = DateTime.now();
  double _sleep = 7.0;
  double _screenTime = 4.0;
  double _mood = 5.0;
  int _steps = 5000;
  bool _isSubmitting = false;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Update Your Twin",
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87),
            ),
            const SizedBox(height: 20),
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue.shade100),
              ),
              child: ListTile(
                title: const Text("Date",
                    style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text(
                  DateFormat('yyyy-MM-dd').format(_selectedDate),
                  style: TextStyle(color: Colors.blue.shade700),
                ),
                trailing: Icon(Icons.calendar_today, color: Colors.blue.shade700),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now(),
                    builder: (context, child) {
                      return Theme(
                        data: ThemeData.light().copyWith(
                          colorScheme:
                              const ColorScheme.light(primary: Colors.blue),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (picked != null) setState(() => _selectedDate = picked);
                },
              ),
            ),
            const SizedBox(height: 24),
            _buildSliderSection(
                "Sleep Hours", _sleep, 12, (v) => setState(() => _sleep = v)),
            const SizedBox(height: 20),
            TextFormField(
              initialValue: _steps.toString(),
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: "Step Count",
                labelStyle: TextStyle(color: Colors.blue.shade700),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.blue.shade100),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.blue.shade100),
                ),
                prefixIcon: Icon(Icons.directions_walk, color: Colors.blue),
              ),
              onChanged: (val) =>
                  setState(() => _steps = int.tryParse(val) ?? 0),
            ),
            const SizedBox(height: 20),
            _buildSliderSection(
                "Mood (1-10)", _mood, 10, (v) => setState(() => _mood = v),
                isMood: true),
            const SizedBox(height: 20),
            _buildSliderSection("Screen Time (Hours)", _screenTime, 16,
                (v) => setState(() => _screenTime = v)),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton.icon(
                onPressed: _isSubmitting ? null : _submitData,
                icon: _isSubmitting
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Icon(Icons.save),
                label: const Text(
                  "Sync to Digital Twin",
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderSection(
      String title, double value, double max, Function(double) onChanged,
      {bool isMood = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: Colors.black87)),
            Text(
              isMood ? value.round().toString() : "${value.toStringAsFixed(1)} hrs",
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: Colors.blue.shade700),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: isMood
                ? (value < 5 ? Colors.red.shade400 : Colors.green.shade400)
                : Colors.blue.shade600,
            inactiveTrackColor: Colors.blue.shade100,
            thumbColor: Colors.white,
            overlayColor: Colors.blue.withOpacity(0.1),
            valueIndicatorColor: Colors.blue,
            trackHeight: 4.0,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10.0),
          ),
          child: Slider(
            value: value,
            min: isMood ? 1 : 0,
            max: max,
            divisions: isMood ? 9 : (max * 2).toInt(),
            label: value.toString(),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Future<void> _submitData() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _isSubmitting = true);

      final derivedState = DailyLog.calculateState(
        _sleep,
        _steps,
        _mood,
        _screenTime,
      );

      final newLog = DailyLog(
        date: _selectedDate,
        sleepHours: _sleep,
        steps: _steps,
        moodRating: _mood,
        screenTimeHours: _screenTime,
        state: derivedState,
      );

      try {
        await Provider.of<TwinProvider>(context, listen: false).addLog(newLog);

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                "Data Synced! Wellness State: ${derivedState.name.toUpperCase()}",
                style: const TextStyle(color: Colors.white),
              ),
              backgroundColor: newLog.color,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Error syncing data"),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _isSubmitting = false);
      }
    }
  }
}