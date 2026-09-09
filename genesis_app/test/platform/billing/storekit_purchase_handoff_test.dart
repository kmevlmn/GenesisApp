import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase_storekit/in_app_purchase_storekit.dart';
import 'package:in_app_purchase_storekit/src/storekit_purchase_handoff.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';

Future<bool> nativeReady(String id) async {
  const codec = StandardMethodCodec();
  final reply = Completer<bool>();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'worldo/storekit_purchase_handoff',
        codec.encodeMethodCall(MethodCall('ready', id)),
        (data) => reply.complete(codec.decodeEnvelope(data!) as bool),
      );
  return reply.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const purchaseChannel = BasicMessageChannel<Object?>(
    'dev.flutter.pigeon.in_app_purchase_storekit.InAppPurchase2API.purchase',
    InAppPurchase2API.pigeonChannelCodec,
  );
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockDecodedMessageHandler(purchaseChannel, null));

  final product = AppStoreProduct2Details.fromSK2Product(
    SK2Product(
      id: 'test-gems',
      displayName: 'Test',
      displayPrice: r'$1',
      description: 'Test',
      price: 1,
      type: SK2ProductType.consumable,
      priceLocale: SK2PriceLocale(currencyCode: 'USD', currencySymbol: r'$'),
    ),
  );

  test(
    'handoff occurs after native preparation and before purchase result',
    () async {
      final prepared = Completer<void>();
      final userFinished = Completer<void>();
      var handedOff = false;
      var purchaseReturned = false;
      String? nativeId;
      messenger.setMockDecodedMessageHandler(purchaseChannel, (message) async {
        final args = message! as List<Object?>;
        final options = args[1]! as SK2ProductPurchaseOptionsMessage;
        expect(options.appAccountToken, '4b74ec68-7abc-4cce-a223-e997e31dc811');
        nativeId = options.handoffId;
        await prepared.future;
        expect(await nativeReady(nativeId!), isTrue);
        await userFinished.future;
        return [SK2ProductPurchaseResultMessage.success];
      });
      final purchase = InAppPurchaseStoreKitPlatform()
          .buyConsumable(
            purchaseParam: Sk2PurchaseParam(
              productDetails: product,
              applicationUserName: '4b74ec68-7abc-4cce-a223-e997e31dc811',
              onStoreHandoff: () {
                handedOff = true;
                return true;
              },
            ),
          )
          .then((_) => purchaseReturned = true);
      await pumpEventQueue();
      expect(handedOff, isFalse);
      expect(nativeId, isNotEmpty);
      prepared.complete();
      await pumpEventQueue();
      expect(handedOff, isTrue);
      expect(purchaseReturned, isFalse);
      expect(await nativeReady(nativeId!), isFalse);
      userFinished.complete();
      await purchase;
    },
  );

  test(
    'expired native preparation cannot authorize a platform payment',
    () async {
      final prepared = Completer<void>();
      var active = true;
      var launched = false;
      messenger.setMockDecodedMessageHandler(purchaseChannel, (message) async {
        final options =
            (message! as List<Object?>)[1]! as SK2ProductPurchaseOptionsMessage;
        await prepared.future;
        launched = await nativeReady(options.handoffId!);
        if (!launched) return ['purchase_preparation_expired', 'expired', null];
        return [SK2ProductPurchaseResultMessage.success];
      });
      final purchase = InAppPurchaseStoreKitPlatform().buyNonConsumable(
        purchaseParam: Sk2PurchaseParam(
          productDetails: product,
          onStoreHandoff: () => active,
        ),
      );
      final rejected = expectLater(purchase, throwsA(isA<PlatformException>()));
      await pumpEventQueue();
      active = false;
      prepared.complete();
      await rejected;
      expect(launched, isFalse);
    },
  );

  test(
    'handoff ids isolate concurrent requests and clean up failures',
    () async {
      final first = Completer<void>();
      final second = Completer<void>();
      late String firstId;
      late String secondId;
      var secondCalls = 0;
      final old = StoreKitPurchaseHandoff.run(() => false, (id) {
        firstId = id;
        return first.future;
      });
      final current = StoreKitPurchaseHandoff.run(
        () {
          secondCalls++;
          return true;
        },
        (id) {
          secondId = id;
          return second.future;
        },
      );
      expect(firstId, isNot(secondId));
      expect(await nativeReady(firstId), isFalse);
      expect(secondCalls, 0);
      expect(await nativeReady(secondId), isTrue);
      first.complete();
      second.complete();
      await Future.wait([old, current]);
      expect(await nativeReady(secondId), isFalse);
      late String failedId;
      await expectLater(
        StoreKitPurchaseHandoff.run(() => true, (id) async {
          failedId = id;
          throw StateError('prepare failed');
        }),
        throwsStateError,
      );
      expect(await nativeReady(failedId), isFalse);
    },
  );
}
