import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'dashboard.dart'; // Import to access TwinProvider and DailyLog

class InsightsPage extends StatelessWidget {
  const InsightsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<TwinProvider>(context);
    final logs = provider.logs;

    if (logs.isEmpty) {
      return const Center(
        child: Text("Log data to unlock insights.", style: TextStyle(color: Colors.grey)),
      );
    }

    // 1. Get Most Recent Log for "Why am I in this state?"
    final currentLog = logs.first;
    
    // 2. Calculate Weekly Stats
    final weeklyLogs = logs.take(7).toList();
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "AI Wellness Analysis",
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 20),

          // --- SECTION 1: EXPLAINABLE AI (WHY?) ---
          _buildExplanationCard(currentLog),
          
          const SizedBox(height: 24),

          // --- SECTION 2: TOP 3 IMPACT FACTORS ---
          const Text("Top Impact Factors (Today)", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _buildImpactList(currentLog),

          const SizedBox(height: 24),

          // --- SECTION 3: WEEKLY SUMMARY ---
          const Text("Weekly Summary", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _buildWeeklySummary(weeklyLogs),
        ],
      ),
    );
  }

  // --- WIDGET: WHY AM I IN THIS STATE? ---
  Widget _buildExplanationCard(DailyLog log) {
    // Logic: Compare current inputs to "Ideal" baselines
    // Ideal: Sleep 8, Steps 10k, Mood 10, Screen < 4
    
    List<String> reasons = [];
    if (log.sleepHours < 6) reasons.add("Sleep dropped significantly");
    if (log.screenTimeHours > 6) reasons.add("Screen time is very high");
    if (log.moodRating < 5) reasons.add("Mood reported low");
    if (log.steps < 3000) reasons.add("Physical activity low");
    
    // Fallback if everything is good
    if (reasons.isEmpty) reasons.add("You are maintaining good balance across all metrics.");

    String mainReason = reasons.join(" and ");

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade700, Colors.blue.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.blue.withOpacity(0.3), blurRadius: 10, offset: const Offset(0, 5))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Text(
                "Why ${log.state.name.toUpperCase()}?",
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            "$mainReason → ${log.state.name == 'balanced' ? 'Keep it up!' : 'Triggered this state.'}",
            style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.4),
          ),
        ],
      ),
    );
  }

  // --- WIDGET: TOP 3 IMPACT FACTORS ---
  Widget _buildImpactList(DailyLog log) {
    // 1. Calculate Score Contributions vs Max Possible
    // Max Sleep Pts = 35. Actual = (sleep/8)*35
    double sleepLoss = ((log.sleepHours / 8.0) * 35) - 35; 
    
    // Max Step Pts = 30.
    double stepLoss = ((log.steps / 10000.0) * 30) - 30;
    
    // Max Mood Pts = 25.
    double moodLoss = ((log.moodRating / 10.0) * 25) - 25;
    
    // Screen Penalty (starts at 0, goes negative)
    double screenLoss = (log.screenTimeHours > 4) ? -((log.screenTimeHours - 4) * 5) : 0;

    // 2. Create a Map of factors
    List<Map<String, dynamic>> factors = [
      {'name': 'Sleep', 'loss': sleepLoss, 'icon': Icons.bed},
      {'name': 'Steps', 'loss': stepLoss, 'icon': Icons.directions_walk},
      {'name': 'Mood', 'loss': moodLoss, 'icon': Icons.mood},
      {'name': 'Screen Time', 'loss': screenLoss, 'icon': Icons.phone_android},
    ];

    // 3. Sort by biggest negative impact (lowest number)
    factors.sort((a, b) => (a['loss'] as double).compareTo(b['loss'] as double));

    // 4. Take Top 3
    final topFactors = factors.take(3).toList();

    return Column(
      children: topFactors.map((factor) {
        double loss = factor['loss'];
        bool isPositive = loss >= -2; // Tolerance threshold
        
        return Card(
          elevation: 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            side: BorderSide(color: Colors.grey.shade200),
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.only(bottom: 10),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: isPositive ? Colors.green.shade50 : Colors.red.shade50,
              child: Icon(factor['icon'], color: isPositive ? Colors.green : Colors.red, size: 20),
            ),
            title: Text(factor['name'], style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: Text(
              "${loss.toStringAsFixed(1)} pts",
              style: TextStyle(
                color: isPositive ? Colors.green.shade700 : Colors.red.shade700,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // --- WIDGET: WEEKLY SUMMARY ---
  Widget _buildWeeklySummary(List<DailyLog> logs) {
    if (logs.isEmpty) return const SizedBox();

    // Find Best and Worst Days
    logs.sort((a, b) => b.wellnessScore.compareTo(a.wellnessScore)); // Sort Descending
    final bestDay = logs.first;
    final worstDay = logs.last;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.blue.shade100),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildSummaryItem("Best Day", DateFormat('E').format(bestDay.date), bestDay.wellnessScore, Colors.green),
          ),
          Container(width: 1, height: 40, color: Colors.grey.shade300),
          Expanded(
            child: _buildSummaryItem("Worst Day", DateFormat('E').format(worstDay.date), worstDay.wellnessScore, Colors.red),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, int score, Color color) {
    return Column(
      children: [
        Text(label, style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
        Text("$score/100", style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
      ],
    );
  }
}