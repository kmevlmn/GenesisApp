import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:genesis_flutter_android/components/common/genesis_upload_progress_overlay.dart';
import 'package:genesis_flutter_android/components/discuss/discuss_post_input.dart';
import 'package:genesis_flutter_android/ui/system/genesis_system_ui.dart';
import 'package:genesis_flutter_android/ui/tokens/genesis_colors.dart';
import 'package:image/image.dart' as img;

void main() {
  setUp(() {
    debugDiscussImageProcessorOverride = _testPrepareDiscussImageForUpload;
  });

  tearDown(() {
    debugDiscussImageProcessorOverride = null;
  });

  test('estimates compression progress from original image size', () {
    final halfwayProgress = estimateDiscussCompressionProgressForTesting(
      byteCount: 4 * 1024 * 1024,
      elapsed: const Duration(seconds: 1),
    );
    expect(halfwayProgress, closeTo(0.05, 0.01));

    final cappedProgress = estimateDiscussCompressionProgressForTesting(
      byteCount: 4 * 1024 * 1024,
      elapsed: const Duration(seconds: 5),
    );
    expect(cappedProgress, lessThan(0.10));
    expect(cappedProgress, greaterThan(0.09));
  });

  testWidgets('uses the collapsed input background color', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: DiscussPostInput(bizId: 'o_test_1')),
      ),
    );

    final inputContainer = find
        .ancestor(
          of: find.text('Write a post'),
          matching: find.byType(Container),
        )
        .first;
    final decoration =
        tester.widget<Container>(inputContainer).decoration as BoxDecoration;
    expect(decoration.color, const Color(0xFFF8F8F8));
  });

  testWidgets('supports a dark sheet collapsed-input palette', (
    WidgetTester tester,
  ) async {
    const backgroundColor = Color(0x12FFFFFF);
    const placeholderColor = Color(0x52FFFFFF);
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DiscussPostInput(
            bizId: 'o_test_1',
            backgroundColor: backgroundColor,
            placeholderColor: placeholderColor,
          ),
        ),
      ),
    );

    final placeholder = find.text('Write a post');
    final inputContainer = find
        .ancestor(of: placeholder, matching: find.byType(Container))
        .first;
    final decoration =
        tester.widget<Container>(inputContainer).decoration as BoxDecoration;
    expect(decoration.color, backgroundColor);
    expect(tester.widget<Text>(placeholder).style?.color, placeholderColor);
  });

  testWidgets('hides the image picker button by default', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiscussPostInput(
            bizId: 'o_test_1',
            requireLogin: false,
            submitter: (content, images) async => <String, dynamic>{},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Write a post').first);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('discuss-image-picker-button')),
      findsNothing,
    );
  });

  testWidgets('keeps the global status bar transparent while composer opens', (
    WidgetTester tester,
  ) async {
    final calls = <Map<dynamic, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setSystemUIOverlayStyle') {
            calls.add(Map<dynamic, dynamic>.from(call.arguments as Map));
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: AnnotatedRegion<SystemUiOverlayStyle>(
          value: kGenesisDefaultSystemUiOverlayStyle,
          child: Scaffold(
            body: DiscussPostInput(
              bizId: 'o_test_1',
              requireLogin: false,
              showImagePickerButton: true,
              imagePicker: (limit) async => const <DiscussPickedImage>[],
              submitter: (content, images) async => <String, dynamic>{},
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Write a post').first);
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(calls, isNotEmpty);
    expect(calls.last['statusBarColor'], Colors.transparent.toARGB32());
    expect(calls.last['statusBarIconBrightness'], Brightness.dark.toString());
    expect(
      tester
          .widget<Icon>(find.byIcon(Icons.add_photo_alternate_outlined))
          .color,
      GenesisColors.brand,
    );

    await tester.tapAt(const Offset(20, 20));
    await tester.pumpAndSettle();

    expect(calls.last['statusBarColor'], Colors.transparent.toARGB32());
    expect(calls.last['statusBarIconBrightness'], Brightness.dark.toString());
  });

  testWidgets('dismisses composer when tapping outside the sheet', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiscussPostInput(
            bizId: 'o_test_1',
            requireLogin: false,
            imagePicker: (limit) async => const <DiscussPickedImage>[],
            submitter: (content, images) async => <String, dynamic>{},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Write a post').first);
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('discuss-composer-sheet')),
      findsOneWidget,
    );
    final composerInput = tester.widget<TextField>(
      find.widgetWithText(TextField, 'Write a post').last,
    );
    expect(composerInput.minLines, 3);
    expect(composerInput.maxLines, 6);
    expect(composerInput.expands, isFalse);
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tapAt(const Offset(20, 20));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('discuss-composer-sheet')), findsNothing);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.text('New post'), findsNothing);
  });

  testWidgets('composer grows from three to six lines then scrolls', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiscussPostInput(
            bizId: 'o_test_1',
            requireLogin: false,
            imagePicker: (limit) async => const <DiscussPickedImage>[],
            submitter: (content, images) async => <String, dynamic>{},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Write a post').first);
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    final sheet = find.byKey(const ValueKey('discuss-composer-sheet'));
    final input = find.widgetWithText(TextField, 'Write a post').last;
    final initialHeight = tester.getSize(sheet).height;

    await tester.enterText(input, 'one\ntwo\nthree\nfour\nfive\nsix');
    await tester.pump();
    final sixLineHeight = tester.getSize(sheet).height;

    expect(sixLineHeight, greaterThan(initialHeight));

    await tester.enterText(
      input,
      'one\ntwo\nthree\nfour\nfive\nsix\nseven\neight',
    );
    await tester.pump();

    expect(tester.getSize(sheet).height, sixLineHeight);
  });

  testWidgets('dismisses composer directly when route back is pressed', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiscussPostInput(
            bizId: 'o_test_1',
            requireLogin: false,
            imagePicker: (limit) async => const <DiscussPickedImage>[],
            submitter: (content, images) async => <String, dynamic>{},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Write a post').first);
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('discuss-composer-sheet')),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('discuss-composer-sheet')), findsNothing);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.text('New post'), findsNothing);
  });

  testWidgets('dismisses composer when keyboard back is consumed by IME', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiscussPostInput(
            bizId: 'o_test_1',
            requireLogin: false,
            imagePicker: (limit) async => const <DiscussPickedImage>[],
            submitter: (content, images) async => <String, dynamic>{},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Write a post').first);
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('discuss-composer-sheet')),
      findsOneWidget,
    );

    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    tester.binding.handleMetricsChanged();
    await tester.pump();

    tester.view.viewInsets = FakeViewPadding.zero;
    tester.binding.handleMetricsChanged();
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('discuss-composer-sheet')), findsNothing);
    expect(tester.testTextInput.isVisible, isFalse);
    expect(find.text('New post'), findsNothing);
  });

  testWidgets('picks up to six images and waits for uploads before posting', (
    WidgetTester tester,
  ) async {
    final uploadCompleters = <Completer<String>>[];
    var submittedContent = '';
    var submittedImages = const <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiscussPostInput(
            bizId: 'o_test_1',
            requireLogin: false,
            showImagePickerButton: true,
            imagePicker: (limit) async => List<DiscussPickedImage>.generate(
              8,
              (index) => _pickedImage(index),
            ),
            imageUploader: (image) {
              final completer = Completer<String>();
              uploadCompleters.add(completer);
              return completer.future;
            },
            submitter: (content, images) async {
              submittedContent = content;
              submittedImages = images;
              return <String, dynamic>{'discuss_id': 'dis_new'};
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Write a post').first);
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    final sheetSizeBeforeImages = tester.getSize(
      find.byKey(const ValueKey('discuss-composer-sheet')),
    );
    expect(find.byKey(const ValueKey('discuss-image-strip')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('discuss-image-picker-button')));
    await tester.pump();
    await tester.pump();

    await _pumpUntil(tester, () => uploadCompleters.length == 6);
    expect(uploadCompleters, hasLength(6));
    for (var i = 0; i < discussPostMaxImages; i++) {
      expect(find.byKey(ValueKey('discuss-image-thumb-$i')), findsOneWidget);
    }
    final sheetSizeAfterImages = tester.getSize(
      find.byKey(const ValueKey('discuss-composer-sheet')),
    );
    expect(
      sheetSizeAfterImages.height,
      greaterThan(sheetSizeBeforeImages.height),
    );
    final stripRect = tester.getRect(
      find.byKey(const ValueKey('discuss-image-strip')),
    );
    final firstThumbRect = tester.getRect(
      find.byKey(const ValueKey('discuss-image-thumb-0')),
    );
    final lastThumbRect = tester.getRect(
      find.byKey(const ValueKey('discuss-image-thumb-5')),
    );
    expect(firstThumbRect.left, closeTo(stripRect.left, 0.01));
    expect(lastThumbRect.right, closeTo(stripRect.right, 0.01));
    expect(
      find.byKey(const ValueKey('discuss-image-add-button')),
      findsNothing,
    );
    expect(find.byType(GenesisUploadProgressOverlay), findsNWidgets(6));
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextField, 'Write a post').last,
      'Post with images',
    );
    await tester.pump();
    await tester.tap(find.text('Send'));
    await tester.pump();

    expect(submittedContent, isEmpty);
    expect(find.byType(CircularProgressIndicator), findsWidgets);

    for (var i = 0; i < uploadCompleters.length; i++) {
      uploadCompleters[i].complete('https://cdn.example.com/$i.jpg');
    }
    await tester.pumpAndSettle();

    expect(submittedContent, 'Post with images');
    expect(submittedImages, [
      for (var i = 0; i < discussPostMaxImages; i++)
        'https://cdn.example.com/$i.jpg',
    ]);
    expect(find.text('New post'), findsNothing);
  });

  testWidgets('submits UGC without manually escaping backslashes', (
    WidgetTester tester,
  ) async {
    String? submittedContent;
    const raw = '  first\r\n${r'literal \n \u300c \\'}  ';
    const expected = '  first\n${r'literal \n \u300c \\'}  ';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiscussPostInput(
            bizId: 'o_test_1',
            requireLogin: false,
            imagePicker: (limit) async => const <DiscussPickedImage>[],
            submitter: (content, images) async {
              submittedContent = content;
              return <String, dynamic>{'discuss_id': 'dis_new'};
            },
          ),
        ),
      ),
    );

    await tester.tap(find.text('Write a post').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), raw);
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'Send'));
    await tester.pumpAndSettle();

    expect(submittedContent, expected);
  });

  testWidgets('shows selected thumbnails with compression progress', (
    WidgetTester tester,
  ) async {
    final pickerCompleter = Completer<List<DiscussPickedImage>>();
    final uploadCompleter = Completer<String>();
    var uploadCallCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiscussPostInput(
            bizId: 'o_test_1',
            requireLogin: false,
            showImagePickerButton: true,
            imagePicker: (limit) => pickerCompleter.future,
            imageUploader: (image) {
              uploadCallCount += 1;
              return uploadCompleter.future;
            },
            submitter: (content, images) async => <String, dynamic>{},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Write a post').first);
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('discuss-image-picker-button')));
    await tester.pump();
    await tester.pump();

    pickerCompleter.complete(<DiscussPickedImage>[_pickedImage(0)]);
    await tester.pump();

    expect(find.byKey(const ValueKey('discuss-image-thumb-0')), findsOneWidget);
    await _pumpUntil(tester, () => uploadCallCount == 1);
    expect(uploadCallCount, 1);
    await tester.pump();
    expect(find.text('10%'), findsOneWidget);

    uploadCompleter.complete('https://cdn.example.com/0.jpg');
    await tester.pumpAndSettle();
  });

  testWidgets('shows add tile below limit and removes selected images', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiscussPostInput(
            bizId: 'o_test_1',
            requireLogin: false,
            showImagePickerButton: true,
            imagePicker: (limit) async => <DiscussPickedImage>[_pickedImage(0)],
            imageUploader: (image) async => 'https://cdn.example.com/0.jpg',
            submitter: (content, images) async => <String, dynamic>{},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Write a post').first);
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('discuss-image-picker-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('discuss-image-thumb-0')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('discuss-image-add-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('discuss-image-remove-0')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('discuss-image-thumb-0')), findsNothing);
    expect(
      find.byKey(const ValueKey('discuss-image-add-button')),
      findsNothing,
    );
  });

  testWidgets('can add images again after removing a selected image', (
    WidgetTester tester,
  ) async {
    var pickCount = 0;
    final requestedLimits = <int>[];
    final uploadedFilenames = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiscussPostInput(
            bizId: 'o_test_1',
            requireLogin: false,
            showImagePickerButton: true,
            imagePicker: (limit) async {
              pickCount += 1;
              requestedLimits.add(limit);
              if (pickCount == 1) {
                return List<DiscussPickedImage>.generate(
                  6,
                  (index) => _pickedImage(index),
                );
              }
              return <DiscussPickedImage>[_pickedImage(99)];
            },
            imageUploader: (image) async {
              uploadedFilenames.add(image.filename);
              return 'https://cdn.example.com/${image.filename}';
            },
            submitter: (content, images) async => <String, dynamic>{},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Write a post').first);
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('discuss-image-picker-button')));
    await tester.pumpAndSettle();

    expect(pickCount, 1);
    expect(requestedLimits, <int>[6]);
    expect(uploadedFilenames, hasLength(6));
    expect(
      find.byKey(const ValueKey('discuss-image-add-button')),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('discuss-image-remove-2')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('discuss-image-add-button')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('discuss-image-add-button')));
    await tester.pumpAndSettle();

    expect(pickCount, 2);
    expect(requestedLimits, <int>[6, 1]);
    expect(uploadedFilenames, contains('image_99.jpg'));
    expect(find.byKey(const ValueKey('discuss-image-thumb-6')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('discuss-image-add-button')),
      findsNothing,
    );
  });

  testWidgets('keeps composer visible while image picker is open', (
    WidgetTester tester,
  ) async {
    final pickerCompleter = Completer<List<DiscussPickedImage>>();
    var pickerStarted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiscussPostInput(
            bizId: 'o_test_1',
            requireLogin: false,
            showImagePickerButton: true,
            imagePicker: (limit) {
              pickerStarted = true;
              return pickerCompleter.future;
            },
            imageUploader: (image) async => 'https://cdn.example.com/0.jpg',
            submitter: (content, images) async => <String, dynamic>{},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Write a post').first);
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('discuss-composer-sheet')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('discuss-image-picker-button')));
    await tester.pump();
    await tester.pump();

    expect(pickerStarted, isTrue);
    expect(
      find.byKey(const ValueKey('discuss-composer-sheet')),
      findsOneWidget,
    );

    pickerCompleter.complete(const <DiscussPickedImage>[]);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('discuss-composer-sheet')),
      findsOneWidget,
    );
  });

  testWidgets('reshows keyboard when image picker hides text input', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiscussPostInput(
            bizId: 'o_test_1',
            requireLogin: false,
            showImagePickerButton: true,
            imagePicker: (limit) async {
              tester.testTextInput.hide();
              tester.view.viewInsets = FakeViewPadding.zero;
              tester.binding.handleMetricsChanged();
              return <DiscussPickedImage>[_pickedImage(0)];
            },
            imageUploader: (image) async => 'https://cdn.example.com/0.jpg',
            submitter: (content, images) async => <String, dynamic>{},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Write a post').first);
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.tap(find.byKey(const ValueKey('discuss-image-picker-button')));
    await tester.pump();
    await tester.pump();
    expect(tester.testTextInput.isVisible, isTrue);
    expect(
      find.byKey(const ValueKey('discuss-composer-sheet')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('discuss-image-thumb-0')), findsOneWidget);
  });

  testWidgets('keeps composer above keyboard after images are added', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiscussPostInput(
            bizId: 'o_test_1',
            requireLogin: false,
            showImagePickerButton: true,
            imagePicker: (limit) async => <DiscussPickedImage>[_pickedImage(0)],
            imageUploader: (image) async => 'https://cdn.example.com/0.jpg',
            submitter: (content, images) async => <String, dynamic>{},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Write a post').first);
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();

    final keyboardTop = tester.view.physicalSize.height - 320;
    final sheetRectBeforeImages = tester.getRect(
      find.byKey(const ValueKey('discuss-composer-sheet')),
    );
    expect(sheetRectBeforeImages.bottom, lessThanOrEqualTo(keyboardTop));

    await tester.tap(find.byKey(const ValueKey('discuss-image-picker-button')));
    await tester.pumpAndSettle();

    final sheetRectAfterImages = tester.getRect(
      find.byKey(const ValueKey('discuss-composer-sheet')),
    );
    expect(sheetRectAfterImages.bottom, lessThanOrEqualTo(keyboardTop));
    expect(
      sheetRectAfterImages.height,
      greaterThan(sheetRectBeforeImages.height),
    );
  });

  testWidgets('updates composer position from viewInsets after picker', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(800, 900);
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DiscussPostInput(
            bizId: 'o_test_1',
            requireLogin: false,
            showImagePickerButton: true,
            imagePicker: (limit) async {
              tester.view.viewInsets = const FakeViewPadding(bottom: 80);
              return const <DiscussPickedImage>[];
            },
            imageUploader: (image) async => 'https://cdn.example.com/0.jpg',
            submitter: (content, images) async => <String, dynamic>{},
          ),
        ),
      ),
    );

    await tester.tap(find.text('Write a post').first);
    await tester.pump();
    await tester.pump();
    await tester.pumpAndSettle();
    final sheetSizeBeforePicker = tester.getSize(
      find.byKey(const ValueKey('discuss-composer-sheet')),
    );

    await tester.tap(find.byKey(const ValueKey('discuss-image-picker-button')));
    await tester.pump(const Duration(milliseconds: 20));
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    tester.binding.handleMetricsChanged();
    await tester.pump();

    final keyboardTop = tester.view.physicalSize.height - 320;
    final sheetRectAfterKeyboardSettles = tester.getRect(
      find.byKey(const ValueKey('discuss-composer-sheet')),
    );
    expect(
      sheetRectAfterKeyboardSettles.bottom,
      lessThanOrEqualTo(keyboardTop),
    );
    expect(
      sheetRectAfterKeyboardSettles.width,
      closeTo(sheetSizeBeforePicker.width, 0.01),
    );
    expect(
      sheetRectAfterKeyboardSettles.height,
      closeTo(sheetSizeBeforePicker.height, 0.01),
    );
  });

  testWidgets(
    'keeps selected images in composer when picker returns before keyboard',
    (WidgetTester tester) async {
      final uploadCompleter = Completer<String>();
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(800, 900);
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DiscussPostInput(
              bizId: 'o_test_1',
              requireLogin: false,
              showImagePickerButton: true,
              imagePicker: (limit) async {
                tester.view.viewInsets = const FakeViewPadding(bottom: 80);
                tester.binding.handleMetricsChanged();
                return <DiscussPickedImage>[_pickedImage(0)];
              },
              imageUploader: (image) => uploadCompleter.future,
              submitter: (content, images) async => <String, dynamic>{},
            ),
          ),
        ),
      );

      await tester.tap(find.text('Write a post').first);
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('discuss-image-picker-button')),
      );
      await tester.pump();

      tester.view.viewInsets = FakeViewPadding.zero;
      tester.binding.handleMetricsChanged();
      await tester.pump();

      expect(
        find.byKey(const ValueKey('discuss-composer-sheet')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('discuss-image-thumb-0')),
        findsOneWidget,
      );

      await tester.tapAt(const Offset(20, 20));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('discuss-composer-sheet')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('discuss-image-thumb-0')),
        findsOneWidget,
      );

      await tester.pump(const Duration(milliseconds: 1500));
      uploadCompleter.complete('https://cdn.example.com/0.jpg');
      await tester.pump();

      expect(
        find.byKey(const ValueKey('discuss-composer-sheet')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('discuss-image-thumb-0')),
        findsOneWidget,
      );

      await tester.pump(const Duration(milliseconds: 500));
      await tester.tapAt(const Offset(20, 20));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('discuss-composer-sheet')),
        findsNothing,
      );
    },
  );
}

DiscussPickedImage _pickedImage(int index) {
  return DiscussPickedImage(
    bytes: _opaquePng(),
    filename: 'image_$index.png',
    contentType: 'image/png',
  );
}

Uint8List _opaquePng() {
  final image = img.Image(width: 1, height: 1);
  image.setPixelRgba(0, 0, 25, 139, 100, 255);
  return Uint8List.fromList(img.encodePng(image));
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 20,
}) async {
  for (var index = 0; index < maxPumps; index += 1) {
    if (condition()) return;
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<Map<String, Object>> _testPrepareDiscussImageForUpload(
  Map<String, Object> request,
) async {
  final decoded = img.decodeImage(request['bytes']! as Uint8List);
  if (decoded == null) {
    throw StateError('Image decode failed');
  }
  final filename = request['filename']! as String;
  final base = filename.replaceFirst(RegExp(r'\.[^.]+$'), '');
  return <String, Object>{
    'bytes': Uint8List.fromList(img.encodeJpg(decoded, quality: 85)),
    'filename': '${base.isEmpty ? 'upload' : base}.jpg',
    'content_type': 'image/jpeg',
  };
}
