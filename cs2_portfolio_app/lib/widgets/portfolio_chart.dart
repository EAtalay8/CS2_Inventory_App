import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

class PortfolioChart extends StatelessWidget {
  final List<Map<String, dynamic>> history;
  final bool isItemHistory; // If true, format differently (e.g. price vs total value)
  final bool showBothPrices;
  final String activePriceSource;

  const PortfolioChart({
    super.key, 
    required this.history,
    this.isItemHistory = false,
    this.showBothPrices = false,
    this.activePriceSource = 'steam',
  });

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) {
      return const Center(
        child: Text("No history data available yet.", style: TextStyle(color: Colors.grey)),
      );
    }

    final pointsSteam = <FlSpot>[];
    final pointsBp = <FlSpot>[];

    for (var e in history) {
      final time = (e['time'] as int).toDouble();
      
      if (isItemHistory) {
         double? steamVal = e['steam_price'] != null ? (e['steam_price'] as num).toDouble() : null;
         double? bpVal = e['bp_price'] != null ? (e['bp_price'] as num).toDouble() : null;
         
         // Legacy fallback
         double? legacyPrice = e['price'] != null ? (e['price'] as num).toDouble() : null;
         if (steamVal == null && bpVal == null && legacyPrice != null) {
            steamVal = legacyPrice;
         }

         if (steamVal != null) pointsSteam.add(FlSpot(time, steamVal));
         if (bpVal != null) pointsBp.add(FlSpot(time, bpVal));
      } else {
         double? legacyValue = e['value'] != null ? (e['value'] as num).toDouble() : null;
         double? steamVal = e['steam_value'] != null ? (e['steam_value'] as num).toDouble() : legacyValue;
         double? bpVal = e['bp_value'] != null ? (e['bp_value'] as num).toDouble() : legacyValue;
         
         if (steamVal != null) pointsSteam.add(FlSpot(time, steamVal));
         if (bpVal != null) pointsBp.add(FlSpot(time, bpVal));
      }
    }

    // Determine min/max
    double minY = double.infinity;
    double maxY = double.negativeInfinity;
    
    final activePoints = activePriceSource == 'steam' ? pointsSteam : pointsBp;

    if (showBothPrices) {
       for (var p in pointsSteam) { if(p.y < minY) minY = p.y; if(p.y > maxY) maxY = p.y; }
       for (var p in pointsBp) { if(p.y < minY) minY = p.y; if(p.y > maxY) maxY = p.y; }
    } else {
       for (var p in activePoints) { if(p.y < minY) minY = p.y; if(p.y > maxY) maxY = p.y; }
    }
    
    if (minY == double.infinity) { minY = 0; maxY = 1; }
    
    double range = maxY - minY;
    if (range == 0) range = 1; // Avoid division by zero
    
    minY -= range * 0.1;
    maxY += range * 0.1;

    // Build the lines
    List<LineChartBarData> lineBars = [];
    
    if ((showBothPrices || activePriceSource == 'steam') && pointsSteam.isNotEmpty) {
      lineBars.add(LineChartBarData(
        spots: pointsSteam,
        isCurved: false,
        color: Colors.lightBlue[300]!, // Steam color
        barWidth: 3,
        isStrokeCapRound: true,
        dotData: FlDotData(show: pointsSteam.length < 2),
        belowBarData: BarAreaData(show: true, color: Colors.lightBlue[300]!.withAlpha(30)),
      ));
    }
    
    if ((showBothPrices || activePriceSource == 'bp') && pointsBp.isNotEmpty) {
      lineBars.add(LineChartBarData(
        spots: pointsBp,
        isCurved: false,
        color: Colors.amber[400]!, // Backpack color
        barWidth: 3,
        isStrokeCapRound: true,
        dotData: FlDotData(show: pointsBp.length < 2),
        belowBarData: BarAreaData(show: true, color: Colors.amber[400]!.withAlpha(30)),
      ));
    }

    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false), // Hide axis labels for clean look
        borderData: FlBorderData(show: false),
        minY: minY,
        maxY: maxY,
        lineBarsData: lineBars,
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return touchedSpots.map((spot) {
                final date = DateTime.fromMillisecondsSinceEpoch(spot.x.toInt());
                const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
                final formattedDate = "${date.day} ${months[date.month - 1]} ${date.year}";
                final formattedTime = "${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}";
                return LineTooltipItem(
                  "\$${spot.y.toStringAsFixed(2)}",
                  TextStyle(
                    color: spot.barIndex == 0 ? (showBothPrices || activePriceSource == 'steam' ? Colors.lightBlue[200] : Colors.amber[200]) : Colors.amber[200],
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                  children: [
                    TextSpan(
                      text: "\n$formattedDate",
                      style: const TextStyle(
                        color: Colors.white70,
                        fontWeight: FontWeight.normal,
                        fontSize: 12,
                      ),
                    ),
                    TextSpan(
                      text: "\n$formattedTime",
                      style: const TextStyle(
                        color: Colors.white54,
                        fontWeight: FontWeight.normal,
                        fontSize: 11,
                      ),
                    ),
                  ],
                );
              }).toList();
            },
          ),
        ),
      ),
    );
  }
}
