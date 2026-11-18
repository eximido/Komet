import 'package:flutter/widgets.dart';

/// #***! строка ленты с датой для всплывающей пометки при листании
class FloatingDateRow {
  const FloatingDateRow({
    required this.top,
    required this.bottom,
    required this.day,
  });

  /// Верх и низ элемента относительно видимой области списка.
  final double top;
  final double bottom;

  /// День элемента: у разделителя — его дата, у сообщения — дата
  /// сообщения, усечённая до дня.
  final DateTime day;
}

/// Дата просматриваемого сообщения для всплывающей пометки при листании.
///
/// Раньше её искали только по разделителям дней, целиком ушедшим за
/// верхний край экрана. В каналах и больших группах посты высокие:
/// разделитель дня часто оказывается выше края, но вне зоны ленивой
/// постройки списка (у его GlobalKey нет context), и дата то находится,
/// то нет — без закономерности. Теперь дата берётся у верхнего
/// ПОСТРОЕННОГО элемента, пересекающего верхний край, — разделителя или
/// строки сообщения: у самого края элементы построены всегда, поэтому
/// поведение одинаково во всех типах чатов.
class FloatingDateResolver {
  /// Порог: элементы, целиком выше него, считаются проскролленными.
  static const double edge = 4.0;

  static DateTime dayOf(int millis) {
    final d = DateTime.fromMillisecondsSinceEpoch(millis);
    return DateTime(d.year, d.month, d.day);
  }

  /// Геометрия элемента относительно видимой области [list]; null, если
  /// элемент сейчас не построен (за пределами зоны кэша списка).
  static FloatingDateRow? rowOf(
    RenderBox list,
    BuildContext? context,
    DateTime day,
  ) {
    if (context == null) return null;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached) return null;
    final top = box.localToGlobal(Offset.zero, ancestor: list).dy;
    return FloatingDateRow(
      top: top,
      bottom: top + box.size.height,
      day: day,
    );
  }

  /// День верхнего элемента, пересекающего верхний край ленты: это и
  /// есть дата сообщения, которое сейчас просматривают. null — если
  /// ни один элемент с датой не построен.
  static DateTime? resolve(List<FloatingDateRow> rows) {
    if (rows.isEmpty) return null;
    final sorted = [...rows]..sort((a, b) => a.top.compareTo(b.top));
    for (final row in sorted) {
      if (row.bottom > edge) return row.day;
    }
    return null;
  }
}
