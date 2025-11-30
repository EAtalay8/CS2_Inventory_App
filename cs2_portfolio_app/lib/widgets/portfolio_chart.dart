import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'dart:math';

class PortfolioChart extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  final bool isItemHistory; // If true, format differently (e.g. price vs total value)

  const PortfolioChart({
    super.key, 
    required this.history,
    this.isItemHistory = false,
  });

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const Center(
        child: Text("No history data available yet.", style: TextStyle(color: Colors.grey)),
      );
    }

    // Convert history to FlSpots
    // History format: { "time": 171..., "value": 123.45 } (or "price")
    
    // We need to normalize X axis (time) to fit in the chart
    // Let's use index as X for simplicity, or relative time?
    // Using timestamp as X is better but numbers are huge.
    // Let's map timestamp to a double.
    
    final points = history.map((e) {
      final time = (e['time'] as int).toDouble();
      final value = (e['value'] ?? e['price'] ?? 0).toDouble();
      return FlSpot(time, value);
    }).toList();

    // Calculate Min/Max for Y axis to add padding
    double minY = points.map((e) => e.y).reduce(min);
    double maxY = points.map((e) => e.y).reduce(max);
    double range = maxY - minY;
    if (range == 0) range = 1; // Avoid division by zero
    
    minY -= range * 0.1;
    maxY += range * 0.1;

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false), // Hide axis labels for clean look
        borderData: FlBorderData(show: false),
        minY: minY,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: points,
            isCurved: true,
            color: isItemHistory ? Colors.orangeAccent : Colors.greenAccent,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: (isItemHistory ? Colors.orangeAccent : Colors.greenAccent).withOpacity(0.2),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final date = DateTime.fromMillisecondsSinceEpoch(spot.x.toInt());
                final formattedDate = "${date.hour}:${date.minute.toString().padLeft(2, '0')}";
                return LineTooltipItem(
                  "\$${spot.y.toStringAsFixed(2)}\n$formattedDate",
                  const TextStyle(color: Colors.white),
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }
}
