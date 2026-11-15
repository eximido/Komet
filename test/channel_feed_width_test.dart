import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:komet/backend/modules/messages.dart';
import 'package:komet/frontend/widgets/attachment/bubbles/photo_bubble.dart';
import 'package:komet/frontend/widgets/attachment/bubbles/video_bubble.dart';
import 'package:komet/frontend/widgets/bubble_geometry.dart';
import 'package:komet/frontend/widgets/message_bubble.dart';
import 'package:komet/l10n/app_localizations.dart';
import 'package:komet/main.dart' show animojiModule;
import 'package:komet/models/attachment.dart';

const int _me = 900401;
const int _channelId = -900501;
const String _channel = 'Синтетический канал';

/// Ширина списка сообщений в тесте.
const double _listWidth = 432;

/// Ширина блока поста канала: список минус горизонтальные отступы строки
/// (8 + 8) и гутер выделения (40), который держится справа.
const double _feedWidth = _listWidth - 56;

/// Сам блок поста (фон бабла), без внешних отступов строки.
final Finder _block = find.byWidgetPredicate(
  (w) => w is BubbleGeometryReporter && w.slot == BubbleSlot.background,
);

CachedMessage _post({
  String id = '1',
  String text = 'Первый пост канала с обычной длиной текста',
  List<MessageAttachment>? attaches,
  int reactions = 0,
}) => CachedMessage(
  id: id,
  accountId: _me,
  chatId: _channelId,
  senderId: _me,
  text: text,
  time: DateTime(2026, 1, 1, 12).millisecondsSinceEpoch,
  status: 'sent',
  attachments: attaches,
  payload: reactions > 0
      ? {
          'reactionInfo': {
            'counters': [
              for (var i = 0; i < reactions; i++)
                {
                  'reaction': ['👍', '❤️', '🔥'][i % 3],
                  'count': 40 - i * 4,
                },
            ],
            'totalCount': 100,
          },
        }
      : null,
);

MessageBubble _bubble(
  CachedMessage message, {
  bool channelPost = true,
  String chatType = 'CHANNEL',
  VoidCallback? onCommentsTap,
}) => MessageBubble(
  message: message,
  isMe: true,
  channelPost: channelPost,
  myId: _me,
  chatType: chatType,
  peerName: _channel,
  senderNameOverride: _channel,
  onCommentsTap: onCommentsTap,
);

Future<void> _pump(WidgetTester tester, List<Widget> bubbles) async {
  tester.view
    ..devicePixelRatio = 1
    ..physicalSize = const Size(_listWidth, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: bubbles,
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  setUpAll(() => expect(animojiModule, isNotNull));

  testWidgets('a tall narrow photo does not shrink a channel post', (
    tester,
  ) async {
    // 640x1280: раньше блок поста сжимался до 200 — ширины самой картинки
    await _pump(tester, [
      _bubble(
        _post(
          text:
              'Длинная подпись к узкой вертикальной иллюстрации, которая '
              'раньше сжимала весь блок поста до своей ширины и текст '
              'переносился в узкую полосу.',
          attaches: const [
            PhotoAttachment(
              baseUrl: 'https://example.com/tall.jpg',
              width: 640,
              height: 1280,
            ),
          ],
        ),
      ),
    ]);

    final photo = tester.getSize(find.byType(PhotoBubble));
    expect(photo.width, closeTo(_feedWidth, 0.5));

    final caption = tester.getSize(find.textContaining('Длинная подпись'));
    expect(caption.width, greaterThan(_feedWidth * 0.8));
  });

  testWidgets('every channel post takes the same feed width', (tester) async {
    await _pump(tester, [
      _bubble(
        _post(
          id: '1',
          text:
              'Текстовый пост без иллюстраций, но достаточно длинный, '
              'чтобы раньше упираться в узкую ширину блока.',
        ),
      ),
      _bubble(
        _post(
          id: '2',
          text: 'Пост с квадратной картинкой и подписью',
          attaches: const [
            PhotoAttachment(
              baseUrl: 'https://example.com/square.jpg',
              width: 500,
              height: 500,
            ),
          ],
        ),
      ),
      _bubble(
        _post(
          id: '3',
          text: '',
          attaches: const [
            PhotoAttachment(
              baseUrl: 'https://example.com/tall.jpg',
              width: 640,
              height: 1280,
            ),
          ],
        ),
      ),
    ]);

    expect(find.byType(MessageBubble), findsNWidgets(3));
    expect(_block, findsNWidgets(3));

    for (var i = 0; i < 3; i++) {
      final size = tester.getSize(_block.at(i));
      expect(size.width, closeTo(_feedWidth, 0.5));
    }
  });

  testWidgets('the feed block keeps the selection gutter free', (tester) async {
    await _pump(tester, [
      _bubble(
        _post(
          text:
              'Пост, у которого справа должен остаться запас '
              'под сдвиг при выделении сообщений.',
        ),
      ),
    ]);

    final rect = tester.getRect(_block);
    expect(rect.left, closeTo(8, 0.5));
    // Справа от блока остаются свободными отступ строки (8) и гутер
    // выделения (40): на них блок сдвигается при долгом тапе
    expect(rect.right, closeTo(_listWidth - 48, 0.5));
  });

  testWidgets('a video post also spans the feed width', (tester) async {
    await _pump(tester, [
      _bubble(
        _post(
          text: 'Подпись к вертикальному видео',
          attaches: const [
            VideoAttachment(
              baseUrl: 'https://example.com/vertical.mp4',
              width: 640,
              height: 1280,
            ),
          ],
        ),
      ),
    ]);

    final video = tester.getSize(find.byType(VideoBubble));
    expect(video.width, closeTo(_feedWidth, 0.5));
  });

  testWidgets('a post with a comments footer keeps the feed width', (
    tester,
  ) async {
    await _pump(tester, [
      _bubble(
        _post(
          text: 'Пост с включёнными комментариями',
          attaches: const [
            PhotoAttachment(
              baseUrl: 'https://example.com/tall.jpg',
              width: 640,
              height: 1280,
            ),
          ],
        ),
        onCommentsTap: () {},
      ),
    ]);

    // И блок, и кнопка комментариев занимают всю ширину поста
    final block = tester.getSize(_block);
    expect(block.width, closeTo(_feedWidth, 0.5));

    final footer = tester.getSize(find.byType(Divider));
    expect(footer.width, closeTo(_feedWidth, 0.5));
  });

  testWidgets('reactions under a channel photo span the feed width', (
    tester,
  ) async {
    await _pump(tester, [
      _bubble(
        _post(
          text: 'Пост с реакциями',
          reactions: 6,
          attaches: const [
            PhotoAttachment(
              baseUrl: 'https://example.com/tall.jpg',
              width: 640,
              height: 1280,
            ),
          ],
        ),
      ),
    ]);

    final flow = tester.getSize(
      find.byWidgetPredicate(
        (w) => w.runtimeType.toString() == '_ReactionsFlow',
      ),
    );
    // Ширина поста минус горизонтальные отступы самого ряда реакций (8+8)
    expect(flow.width, closeTo(_feedWidth - 16, 0.5));
  });

  testWidgets('regular chats keep the old bubble sizing', (tester) async {
    await _pump(tester, [
      _bubble(
        _post(
          text: 'Подпись к узкой картинке в обычном чате',
          attaches: const [
            PhotoAttachment(
              baseUrl: 'https://example.com/tall.jpg',
              width: 640,
              height: 1280,
            ),
          ],
        ),
        channelPost: false,
        chatType: 'CHAT',
      ),
    ]);

    // В обычном чате узкая картинка с подписью занимает прежние 200
    final photo = tester.getSize(find.byType(PhotoBubble));
    expect(photo.width, closeTo(200, 0.5));

    final block = tester.getSize(_block);
    expect(block.width, closeTo(200, 0.5));
  });
}
