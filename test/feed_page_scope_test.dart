import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:auryel/widgets/feed_page_scope.dart';

void main() {
  testWidgets('isActive vrai quand pageIndex == activeIndex', (t) async {
    late BuildContext ctx;
    await t.pumpWidget(
      FeedPageScope(
        pageIndex: 2,
        activeIndex: 2,
        child: Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(FeedPageScope.maybeOf(ctx)!.isActive, isTrue);
  });

  testWidgets('isActive faux quand pageIndex != activeIndex', (t) async {
    late BuildContext ctx;
    await t.pumpWidget(
      FeedPageScope(
        pageIndex: 1,
        activeIndex: 3,
        child: Builder(
          builder: (context) {
            ctx = context;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(FeedPageScope.maybeOf(ctx)!.isActive, isFalse);
  });

  testWidgets('absent -> maybeOf renvoie null (usage hors feed)', (t) async {
    late BuildContext ctx;
    await t.pumpWidget(
      Builder(
        builder: (context) {
          ctx = context;
          return const SizedBox();
        },
      ),
    );
    expect(FeedPageScope.maybeOf(ctx), isNull);
  });

  testWidgets(
    'updateShouldNotify -> true si activeIndex OU pageIndex change',
    (t) async {
      final widgetA = FeedPageScope(
        pageIndex: 0,
        activeIndex: 0,
        child: Container(),
      );
      final widgetB = FeedPageScope(
        pageIndex: 0,
        activeIndex: 1,
        child: Container(),
      );
      final widgetC = FeedPageScope(
        pageIndex: 0,
        activeIndex: 0,
        child: Container(),
      );
      expect(widgetB.updateShouldNotify(widgetA), isTrue);
      expect(widgetC.updateShouldNotify(widgetA), isFalse);
    },
  );
}
