import 'package:flutter_test/flutter_test.dart';
import 'package:waterflyiii/layout.dart';

void main() {
  group('LayoutProvider', () {
    late LayoutProvider layoutProvider;

    setUp(() {
      layoutProvider = LayoutProvider();
    });

    test('- getSize returns compact for width < 600', () {
      expect(layoutProvider.getSize(0), ScreenSize.compact);
      expect(layoutProvider.getSize(300), ScreenSize.compact);
      expect(layoutProvider.getSize(599), ScreenSize.compact);
    });

    test('- getSize returns medium for width 600-839', () {
      expect(layoutProvider.getSize(600), ScreenSize.medium);
      expect(layoutProvider.getSize(700), ScreenSize.medium);
      expect(layoutProvider.getSize(839), ScreenSize.medium);
    });

    test('- getSize returns expanded for width >= 840', () {
      expect(layoutProvider.getSize(840), ScreenSize.expanded);
      expect(layoutProvider.getSize(1024), ScreenSize.expanded);
      expect(layoutProvider.getSize(1920), ScreenSize.expanded);
    });
  });

  group('ScreenSize comparison operators', () {
    test('- Less than operator', () {
      expect(ScreenSize.compact < ScreenSize.medium, true);
      expect(ScreenSize.compact < ScreenSize.expanded, true);
      expect(ScreenSize.medium < ScreenSize.expanded, true);
      expect(ScreenSize.medium < ScreenSize.compact, false);
      expect(ScreenSize.expanded < ScreenSize.compact, false);
      expect(ScreenSize.compact < ScreenSize.compact, false);
    });

    test('- Less than or equal operator', () {
      expect(ScreenSize.compact <= ScreenSize.compact, true);
      expect(ScreenSize.compact <= ScreenSize.medium, true);
      expect(ScreenSize.compact <= ScreenSize.expanded, true);
      expect(ScreenSize.medium <= ScreenSize.compact, false);
      expect(ScreenSize.expanded <= ScreenSize.medium, false);
    });

    test('- Greater than operator', () {
      expect(ScreenSize.expanded > ScreenSize.medium, true);
      expect(ScreenSize.expanded > ScreenSize.compact, true);
      expect(ScreenSize.medium > ScreenSize.compact, true);
      expect(ScreenSize.compact > ScreenSize.medium, false);
      expect(ScreenSize.compact > ScreenSize.expanded, false);
      expect(ScreenSize.medium > ScreenSize.medium, false);
    });

    test('- Greater than or equal operator', () {
      expect(ScreenSize.expanded >= ScreenSize.expanded, true);
      expect(ScreenSize.expanded >= ScreenSize.medium, true);
      expect(ScreenSize.expanded >= ScreenSize.compact, true);
      expect(ScreenSize.compact >= ScreenSize.medium, false);
      expect(ScreenSize.medium >= ScreenSize.expanded, false);
    });
  });
}
