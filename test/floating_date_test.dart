import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komet/frontend/screens/chats/chat/view/anchored_message_list.dart';
import 'package:komet/frontend/screens/chats/chat/view/floating_date.dart';

const double _viewport = 600;
const EdgeInsets _padding = EdgeInsets.only(top: 30, bottom: 8);
const double _separatorHeight = 30;
const double _cacheExtent = 250;

DateTime _day(int index) => DateTime(2025, 3, 1 + index);

class _Post {
  const _Post(this.dayIndex, this.index);

  final int dayIndex;
  final int index;

  String get id => 'd${dayIndex}m$index';
  DateTime get day => _day(dayIndex);
}

/// Лента как в чате: разделитель дня, затем посты дня; дни сверху вниз
/// от старых к новым.
class _Harness {
  _Harness(this.tester, {required this.postHeight, this.days = 6})
    : posts = [
        for (var d = 0; d < days; d++)
          for (var i = 0; i < 3; i++) _Post(d, i),
      ];

  final WidgetTester tester;
  final double postHeight;
  final int days;
  final List<_Post> posts;

  final GlobalKey listKey = GlobalKey();
  final ScrollController controller = ScrollController();
  final Map<String, GlobalKey> postKeys = {};
  final Map<int, GlobalKey> separatorKeys = {};

  List<Object> get items => [
    for (var d = 0; d < days; d++) ...[
      d, // разделитель дня d
      ...posts.where((p) => p.dayIndex == d),
    ],
  ];

  GlobalKey _postKey(String id) => postKeys.putIfAbsent(id, GlobalKey.new);

  GlobalKey _separatorKey(int dayIndex) =>
      separatorKeys.putIfAbsent(dayIndex, GlobalKey.new);

  Future<void> pump({int? anchorIndex}) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            key: listKey,
            height: _viewport,
            child: AnchoredMessageList(
              controller: controller,
              cacheExtent: _cacheExtent,
              padding: _padding,
              epoch: 0,
              itemCount: items.length,
              anchorIndex: anchorIndex,
              bottomSpacer: const SizedBox(height: 40),
              itemBuilder: (context, index) {
                final item = items[index];
                if (item is int) {
                  return SizedBox(
                    key: _separatorKey(item),
                    height: _separatorHeight,
                    child: Text('sep $item'),
                  );
                }
                final post = item as _Post;
                return SizedBox(
                  key: _postKey(post.id),
                  height: postHeight,
                  child: Text(post.id),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  /// Ставит верх поста [post] на [alignment] высоты экрана — как
  /// получается при обычном листании.
  Future<void> anchorAt(_Post post, double alignment) async {
    final index = items.indexOf(post);
    await pump();
    controller.jumpTo(
      AnchoredMessageList.anchoredPixels(
        alignment: alignment,
        viewport: _viewport,
        anchorHeight: postHeight,
      ),
    );
    await pump(anchorIndex: index);
  }

  /// Геометрия построенных элементов, как её собирает чат.
  List<FloatingDateRow> collectRows() {
    final listBox = listKey.currentContext?.findRenderObject();
    if (listBox is! RenderBox) return const [];
    final rows = <FloatingDateRow>[];
    separatorKeys.forEach((dayIndex, gkey) {
      final row = FloatingDateResolver.rowOf(
        listBox,
        gkey.currentContext,
        _day(dayIndex),
      );
      if (row != null) rows.add(row);
    });
    for (final post in posts) {
      final row = FloatingDateResolver.rowOf(
        listBox,
        postKeys[post.id]?.currentContext,
        post.day,
      );
      if (row != null) rows.add(row);
    }
    return rows;
  }

  /// Прежний алгоритм: последний построенный разделитель, целиком
  /// ушедший за верхний край.
  DateTime? oldApproach() {
    final listBox = listKey.currentContext?.findRenderObject();
    if (listBox is! RenderBox) return null;
    DateTime? result;
    separatorKeys.forEach((dayIndex, gkey) {
      final ctx = gkey.currentContext;
      if (ctx == null) return;
      final box = ctx.findRenderObject();
      if (box is! RenderBox) return;
      final pos = box.localToGlobal(Offset.zero, ancestor: listBox);
      if (pos.dy + box.size.height < 4) {
        final date = _day(dayIndex);
        if (result == null || date.isAfter(result!)) result = date;
      }
    });
    return result;
  }
}

void main() {
  test('dayOf усекает время до дня', () {
    final millis = DateTime(2025, 3, 4, 13, 37).millisecondsSinceEpoch;
    expect(FloatingDateResolver.dayOf(millis), DateTime(2025, 3, 4));
  });

  test('resolve берёт день верхнего элемента, пересекающего край', () {
    final dayA = DateTime(2025, 3, 1);
    final dayB = DateTime(2025, 3, 2);
    final dayC = DateTime(2025, 3, 3);

    // Разделитель дня B пересекает верхний край, выше — посты дня A.
    final rows = [
      FloatingDateRow(top: -100, bottom: -50, day: dayA),
      FloatingDateRow(top: -10, bottom: 30, day: dayB),
      FloatingDateRow(top: 50, bottom: 90, day: dayC),
    ];
    expect(FloatingDateResolver.resolve(rows), dayB);
  });

  test('resolve без пересекающих элементов даёт null', () {
    final day = DateTime(2025, 3, 1);
    expect(FloatingDateResolver.resolve(const []), isNull);
    expect(
      FloatingDateResolver.resolve([
        FloatingDateRow(top: -100, bottom: -50, day: day),
      ]),
      isNull,
    );
  });

  testWidgets('высокий пост канала: разделитель дня не построен, дата всё равно находится', (
    tester,
  ) async {
    // Посты как в канале: 520 px — выше кэша постройки списка.
    final h = _Harness(tester, postHeight: 520);
    addTearDown(h.controller.dispose);

    final post = h.posts.firstWhere((p) => p.id == 'd3m1');
    await h.anchorAt(post, 0.0);

    // Разделитель дня 3 ушёл за край дальше зоны кэша — не построен.
    // Из-за этого прежний алгоритм дату не находил и всплывающая строка
    // не появлялась.
    expect(h.separatorKeys[3]?.currentContext, isNull);
    expect(h.oldApproach(), isNull);

    // Новый алгоритм берёт дату верхнего построенного элемента — сам
    // просматриваемый пост.
    expect(h.collectRows(), isNotEmpty);
    expect(FloatingDateResolver.resolve(h.collectRows()), _day(3));
  });

  testWidgets('высокий пост: разделитель виден на краю — показывается его день', (
    tester,
  ) async {
    final h = _Harness(tester, postHeight: 520);
    addTearDown(h.controller.dispose);

    final post = h.posts.firstWhere((p) => p.id == 'd3m0');
    await h.anchorAt(post, 0.05);

    // Разделитель дня 3 пересекает верхний край: прежний алгоритм его
    // игнорировал (не «ушёл» за край) и ничего не показывал.
    expect(h.oldApproach(), isNull);

    expect(FloatingDateResolver.resolve(h.collectRows()), _day(3));
  });

  testWidgets('низкие сообщения лички: старый и новый алгоритм согласны', (
    tester,
  ) async {
    final h = _Harness(tester, postHeight: 60);
    addTearDown(h.controller.dispose);

    final post = h.posts.firstWhere((p) => p.id == 'd3m1');
    await h.anchorAt(post, 0.0);

    // Разделитель дня 3 построен и ушёл за край — оба подхода дают
    // одну и ту же дату.
    expect(h.separatorKeys[3]?.currentContext, isNotNull);
    expect(h.oldApproach(), _day(3));
    expect(FloatingDateResolver.resolve(h.collectRows()), _day(3));
  });
}
