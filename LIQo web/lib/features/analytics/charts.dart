import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/theme.dart';

/// How long a chart takes to grow into place when it first appears.
const chartReveal = Duration(milliseconds: 650);
const _revealCurve = Curves.easeOutCubic;

/// One line (or one bar group) of a chart.
class ChartSeries {
  const ChartSeries({required this.name, required this.values, required this.color});

  final String name;
  final List<int> values;
  final Color color;
}

/// One slice of a donut or one bar.
class ChartSlice {
  const ChartSlice({required this.name, required this.value, required this.color});

  final String name;
  final int value;
  final Color color;
}

/// Shared "grow into place" behaviour. The parent passes [shown]: false draws
/// the chart empty, true draws the real values, and fl_chart animates between
/// them. Wrapped in a RevealOnScroll, a chart therefore grows into place the
/// moment the person scrolls to it. Reduced-motion devices skip the motion.
mixin _Reveal<T extends StatefulWidget> on State<T> {
  bool get shownInput;
  bool get animate => !MediaQuery.of(context).disableAnimations;
  bool get shown => shownInput || !animate;
  Duration get duration => animate ? chartReveal : Duration.zero;
}

/// Centered muted text where a chart would be.
class ChartEmpty extends StatelessWidget {
  const ChartEmpty(this.text, {super.key, this.height = 80});

  final String text;
  final double height;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return SizedBox(height: height, child: Center(child: Text(text, style: ts(12, color: p.muted))));
  }
}

class ChartLegend extends StatelessWidget {
  const ChartLegend(this.items, {super.key});

  final List<ChartSlice> items;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        for (final i in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 10, height: 10, decoration: BoxDecoration(color: i.color, borderRadius: BorderRadius.circular(3))),
              const SizedBox(width: 6),
              Flexible(child: Text(i.name, overflow: TextOverflow.ellipsis, style: ts(11, color: p.muted))),
            ],
          ),
      ],
    );
  }
}

/// Rounds a maximum up to a tidy axis top (1, 2, 5 × 10ⁿ), never below 4.
double niceMax(num maxValue) {
  if (maxValue <= 4) return 4;
  final exp = math.pow(10, (math.log(maxValue) / math.ln10).floor()).toDouble();
  for (final m in [1, 2, 5, 10]) {
    if (m * exp >= maxValue) return m * exp;
  }
  return 10 * exp;
}

/// Line chart by day. [dates] are 'yyyy-MM-dd'; every series has one value per date.
class LineSeriesChart extends StatefulWidget {
  const LineSeriesChart({super.key, required this.dates, required this.series, this.height = 220, this.emptyText = 'No activity in this period.', this.shown = true});

  final List<String> dates;
  final List<ChartSeries> series;
  final double height;
  final String emptyText;

  /// False until the chart is in view; see RevealOnScroll.
  final bool shown;

  @override
  State<LineSeriesChart> createState() => _LineSeriesChartState();
}

class _LineSeriesChartState extends State<LineSeriesChart> with _Reveal {
  static final _label = DateFormat('MMM d');

  @override
  bool get shownInput => widget.shown;

  String _fmt(String d) => _label.format(DateTime.parse(d));

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final dates = widget.dates;
    final series = widget.series;
    final maxValue = series.fold<int>(0, (m, s) => math.max(m, s.values.fold(0, math.max)));
    if (dates.isEmpty || maxValue == 0) return ChartEmpty(widget.emptyText, height: widget.height);

    final top = niceMax(maxValue);
    final yStep = top / 4;
    final xStep = math.max(1, (dates.length / 7).ceil());
    final scale = shown ? 1.0 : 0.0; // lines rise from the baseline

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: widget.height,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: top,
              minX: 0,
              maxX: (dates.length - 1).toDouble(),
              lineBarsData: [
                for (final s in series)
                  LineChartBarData(
                    spots: [for (var i = 0; i < dates.length; i++) FlSpot(i.toDouble(), (i < s.values.length ? s.values[i] : 0).toDouble() * scale)],
                    color: s.color,
                    barWidth: 2,
                    isCurved: false,
                    dotData: FlDotData(show: dates.length <= 14),
                    belowBarData: BarAreaData(show: true, color: s.color.withAlpha(shown ? 14 : 0)),
                  ),
              ],
              titlesData: FlTitlesData(
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 34,
                    interval: yStep,
                    getTitlesWidget: (v, meta) => Text(v.toInt().toString(), style: ts(10, color: p.chartText)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    interval: 1,
                    getTitlesWidget: (v, meta) {
                      final i = v.round();
                      if (i < 0 || i >= dates.length || (v - i).abs() > 0.01 || i % xStep != 0) return const SizedBox.shrink();
                      return Padding(padding: const EdgeInsets.only(top: 8), child: Text(_fmt(dates[i]), style: ts(10, color: p.chartText)));
                    },
                  ),
                ),
              ),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: yStep,
                getDrawingHorizontalLine: (_) => FlLine(color: p.softLine, strokeWidth: 1),
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => p.ink,
                  getTooltipItems: (spots) => [
                    for (var k = 0; k < spots.length; k++)
                      LineTooltipItem(
                        '${k == 0 ? '${_fmt(dates[spots[k].x.round()])}\n' : ''}${series[spots[k].barIndex].name}: ${spots[k].y.toInt()}',
                        ts(11, color: p.panel),
                      ),
                  ],
                ),
              ),
            ),
            duration: duration,
            curve: _revealCurve,
          ),
        ),
        const SizedBox(height: 10),
        ChartLegend([for (final s in series) ChartSlice(name: s.name, value: 0, color: s.color)]),
      ],
    );
  }
}

/// Donut with the total in the middle and a legend with counts and shares.
class DonutChart extends StatefulWidget {
  const DonutChart({super.key, required this.slices, this.size = 150, this.emptyText = 'No data yet.', this.shown = true});

  final List<ChartSlice> slices;
  final double size;
  final String emptyText;
  final bool shown;

  @override
  State<DonutChart> createState() => _DonutChartState();
}

class _DonutChartState extends State<DonutChart> with _Reveal {
  @override
  bool get shownInput => widget.shown;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final size = widget.size;
    final shownSlices = widget.slices.where((s) => s.value > 0).toList();
    final total = shownSlices.fold<int>(0, (n, s) => n + s.value);
    if (total == 0) return ChartEmpty(widget.emptyText);
    final radius = shown ? 22.0 : 1.0; // the ring thickens into place

    return Wrap(
      spacing: 18,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: Stack(
            alignment: Alignment.center,
            children: [
              PieChart(
                PieChartData(
                  sections: [for (final s in shownSlices) PieChartSectionData(value: s.value.toDouble(), color: s.color, radius: radius, showTitle: false)],
                  centerSpaceRadius: size / 2 - 26,
                  sectionsSpace: 2,
                  startDegreeOffset: shown ? -90 : -150,
                  pieTouchData: PieTouchData(enabled: false),
                ),
                duration: duration,
                curve: _revealCurve,
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CountUp(value: total, shown: shown, style: ts(20, w: FontWeight.w800, color: p.ink, height: 1.1)),
                  Text('total', style: ts(10, color: p.muted)),
                ],
              ),
            ],
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 300),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final s in shownSlices)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(width: 10, height: 10, decoration: BoxDecoration(color: s.color, borderRadius: BorderRadius.circular(3))),
                      const SizedBox(width: 8),
                      Flexible(child: Text(s.name, overflow: TextOverflow.ellipsis, style: ts(12, color: p.ink))),
                      const SizedBox(width: 10),
                      Text('${s.value} · ${(s.value * 100 / total).round()}%', style: ts(11, color: p.muted)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A few vertical bars with labels under them (status, time state).
class CategoryBars extends StatefulWidget {
  const CategoryBars({super.key, required this.items, this.height = 160, this.emptyText = 'No data yet.', this.shown = true});

  final List<ChartSlice> items;
  final double height;
  final String emptyText;
  final bool shown;

  @override
  State<CategoryBars> createState() => _CategoryBarsState();
}

class _CategoryBarsState extends State<CategoryBars> with _Reveal {
  @override
  bool get shownInput => widget.shown;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final items = widget.items;
    final maxValue = items.fold<int>(0, (m, s) => math.max(m, s.value));
    if (items.isEmpty || maxValue == 0) return ChartEmpty(widget.emptyText, height: widget.height);
    final top = niceMax(maxValue);
    final scale = shown ? 1.0 : 0.0;

    return SizedBox(
      height: widget.height,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          minY: 0,
          maxY: top,
          barGroups: [
            for (var i = 0; i < items.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: items[i].value.toDouble() * scale,
                    color: items[i].color,
                    width: 22,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                  ),
                ],
              ),
          ],
          titlesData: FlTitlesData(
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                interval: top / 4,
                getTitlesWidget: (v, meta) => Text(v.toInt().toString(), style: ts(10, color: p.chartText)),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 26,
                getTitlesWidget: (v, meta) {
                  final i = v.round();
                  if (i < 0 || i >= items.length) return const SizedBox.shrink();
                  return Padding(padding: const EdgeInsets.only(top: 8), child: Text('${items[i].name} (${items[i].value})', style: ts(10, color: p.chartText)));
                },
              ),
            ),
          ),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: top / 4,
            getDrawingHorizontalLine: (_) => FlLine(color: p.softLine, strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => p.ink,
              getTooltipItem: (group, gi, rod, ri) => BarTooltipItem('${items[gi].name}: ${rod.toY.toInt()}', ts(11, color: p.panel)),
            ),
          ),
        ),
        duration: duration,
        curve: _revealCurve,
      ),
    );
  }
}

class HBarItem {
  const HBarItem({required this.label, this.sub, required this.segments});

  final String label;
  final String? sub;
  final List<ChartSlice> segments;

  int get total => segments.fold(0, (n, s) => n + s.value);
}

/// Horizontal stacked bars, one per row: good for "per branch" where names are long.
/// Bars grow from the left when the chart appears.
class HBarList extends StatefulWidget {
  const HBarList({super.key, required this.items, this.emptyText = 'No data yet.', this.labelWidth = 170, this.shown = true});

  final List<HBarItem> items;
  final String emptyText;
  final double labelWidth;
  final bool shown;

  @override
  State<HBarList> createState() => _HBarListState();
}

class _HBarListState extends State<HBarList> with _Reveal {
  @override
  bool get shownInput => widget.shown;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final items = widget.items;
    final maxTotal = items.fold<int>(0, (m, i) => math.max(m, i.total));
    if (items.isEmpty) return ChartEmpty(widget.emptyText);
    final lw = Bp.isMobile(context) ? math.min(widget.labelWidth, 110.0) : widget.labelWidth;
    final legend = <String, Color>{};
    for (final i in items) {
      for (final s in i.segments) {
        legend.putIfAbsent(s.name, () => s.color);
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final i in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                SizedBox(
                  width: lw,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(i.label, overflow: TextOverflow.ellipsis, style: ts(12, w: FontWeight.w600, color: p.ink)),
                      if (i.sub != null) Text(i.sub!, overflow: TextOverflow.ellipsis, style: ts(10, color: p.muted)),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: SizedBox(
                      height: 14,
                      child: Stack(
                        children: [
                          Positioned.fill(child: Container(color: p.softLine.withAlpha(p.mix(255, 120).round()))),
                          AnimatedFractionallySizedBox(
                            duration: duration,
                            curve: _revealCurve,
                            alignment: Alignment.centerLeft,
                            widthFactor: shown && maxTotal > 0 ? i.total / maxTotal : 0,
                            heightFactor: 1,
                            child: Row(
                              children: [
                                for (final s in i.segments)
                                  if (s.value > 0) Flexible(flex: s.value, child: Container(color: s.color)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(width: 32, child: Text('${i.total}', textAlign: TextAlign.right, style: ts(11, w: FontWeight.w700, color: p.ink))),
              ],
            ),
          ),
        const SizedBox(height: 8),
        ChartLegend([for (final e in legend.entries) ChartSlice(name: e.key, value: 0, color: e.value)]),
      ],
    );
  }
}

/// A compact table with fixed column widths: the first column 200 px, the rest
/// 110 px unless [widths] says otherwise. Numbers are right-aligned from
/// [numericFrom] onwards. Scrolls sideways when the card is narrower.
/// (No LayoutBuilder on purpose: the page's grids measure intrinsic sizes.)
class BreakdownTable extends StatelessWidget {
  const BreakdownTable({super.key, required this.columns, required this.rows, this.numericFrom = 1, this.emptyText = 'Nothing to show.', this.widths, this.onRowTap});

  final List<String> columns;
  final List<List<String>> rows;
  final int numericFrom;
  final String emptyText;
  final List<double>? widths;

  /// Rows open something (by row index) when given.
  final ValueChanged<int>? onRowTap;

  double _w(int i) => widths != null && i < widths!.length ? widths![i] : (i == 0 ? 200 : 110);

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    if (rows.isEmpty) return ChartEmpty(emptyText, height: 60);
    Widget cell(String text, int i, {bool head = false}) => SizedBox(
          width: _w(i),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Text(
              text,
              textAlign: i >= numericFrom ? TextAlign.right : TextAlign.left,
              overflow: TextOverflow.ellipsis,
              style: head ? ts(10, w: FontWeight.w700, color: p.muted, ls: 0.3) : ts(12, color: p.ink),
            ),
          ),
        );
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            color: p.tableHead,
            child: Row(mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < columns.length; i++) cell(columns[i].toUpperCase(), i, head: true)]),
          ),
          for (var ri = 0; ri < rows.length; ri++)
            Container(
              decoration: BoxDecoration(border: Border(bottom: BorderSide(color: p.rowLine))),
              child: onRowTap == null
                  ? Row(mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < rows[ri].length; i++) cell(rows[ri][i], i)])
                  : Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => onRowTap!(ri),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [for (var i = 0; i < rows[ri].length; i++) cell(rows[ri][i], i)]),
                      ),
                    ),
            ),
        ],
      ),
    );
  }
}

/// A number that counts up from zero once it is shown.
class CountUp extends StatelessWidget {
  const CountUp({super.key, required this.value, required this.style, this.shown = true});

  final int value;
  final TextStyle style;
  final bool shown;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) return Text('$value', style: style);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: shown ? value.toDouble() : 0),
      duration: chartReveal,
      curve: _revealCurve,
      builder: (context, v, _) => Text('${v.round()}', style: style),
    );
  }
}

/// "142 · up from 98" with a colour for the direction.
class DeltaStat extends StatelessWidget {
  const DeltaStat({super.key, required this.label, required this.value, required this.previous, required this.color, this.shown = true});

  final String label;
  final int value;
  final int previous;
  final Color color;
  final bool shown;

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final diff = value - previous;
    final arrow = diff > 0 ? '▲' : diff < 0 ? '▼' : '•';
    final tone = diff > 0 ? p.green : diff < 0 ? p.warn : p.muted;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Flexible(child: Text(label, overflow: TextOverflow.ellipsis, style: ts(11, color: p.muted))),
          ],
        ),
        const SizedBox(height: 2),
        CountUp(value: value, shown: shown, style: ts(18, w: FontWeight.w800, color: p.ink, height: 1.1)),
        Text('$arrow ${diff.abs()} vs previous ($previous)', style: ts(10, color: tone)),
      ],
    );
  }
}
