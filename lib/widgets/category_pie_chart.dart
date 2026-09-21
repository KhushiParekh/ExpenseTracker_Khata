import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/constants.dart';
import '../models/models.dart';

const _palette = [
  Color(0xFFFF7A59),
  Color(0xFFFFC24B),
  Color(0xFF4DA3FF),
  Color(0xFF34C759),
  Color(0xFFB388FF),
  Color(0xFFFF6B9D),
  Color(0xFF64D8CB),
  Color(0xFFFFD166),
];

class CategoryPieChart extends StatelessWidget {
  final List<CategorySlice> slices;
  const CategoryPieChart({super.key, required this.slices});

  @override
  Widget build(BuildContext context) {
    if (slices.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: Text('No data for this period', style: TextStyle(color: Colors.grey))),
      );
    }

    return Column(
      children: [
        SizedBox(
          height: 220,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 50,
              sections: [
                for (int i = 0; i < slices.length; i++)
                  PieChartSectionData(
                    value: slices[i].amount,
                    title: '${slices[i].percent.toStringAsFixed(0)}%',
                    color: _palette[i % _palette.length],
                    radius: 70,
                    titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        ...List.generate(slices.length, (i) {
          final s = slices[i];
          return ListTile(
            dense: true,
            leading: CircleAvatar(radius: 6, backgroundColor: _palette[i % _palette.length]),
            title: Text('${s.icon}  ${s.name}'),
            trailing: Text('$kCurrencySymbol${s.amount.toStringAsFixed(2)}'),
          );
        }),
      ],
    );
  }
}
