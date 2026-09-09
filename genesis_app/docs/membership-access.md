# 全局 VIP 状态

入口：`AppServices.membership`（`MembershipAccessStore`）。复用现有
`GemWalletStore` 请求 `/api/v1/gem/wallet`，只读取其中的 `membership`。

## 业务调用

```dart
final services = AppServicesScope.read(context);
services.membership.checkVip((isVip) {
  if (!context.mounted) return; // 回调需要操作页面时检查页面是否仍存在。
  if (isVip == true) {
    // 已确认会员有效，继续会员操作。
  } else if (isVip == false) {
    // 已确认非会员；按业务需要进入订阅流程。
  } else {
    // 暂时无法确认，保留重试机会，不能当作已确认非会员。
  }
});
```

- 业务方只使用 `checkVip(callback)`，返回类型为 `void`，不需要 `await`。
  回调参数是 `bool?`：`true / false / null` 分别表示有效 / 无会员 / 未知。
- 缓存有效时使用缓存；数据缺失或过期时内部请求钱包。并发调用共用请求，
  每个调用方分别收到一次回调，也复用 Me 页已经发起的钱包请求。
- 无论使用缓存还是请求接口，回调都在 `checkVip` 返回之后执行一次；失败或超时
  会回调 `null`。迟到的网络响应只更新缓存，不再次通知同一次调用。
- 结果送达前发生退出、切换账号或服务释放时，回调 `null`，不交付旧账号权益。
- 原 `isVip` getter 和 `ensureFresh()` 不再作为公开业务入口；
  缓存状态只通过标注 `visibleForTesting` 的 `debugState` 提供测试诊断。

## 判断与刷新

1. 未登录不请求需要登录态的钱包接口；当前账号权益返回 `inactive`。
   已有 UID 但后端 token 缺失时返回 `unknown`，不清除登录态。
2. `membership_status=0/2` 是已知无效；`membership` 缺失或解析失败是 `unknown`。
3. `membership_status=1` 且已知到期时间晚于服务器时间时有效。
   缓存显示已到期时重新请求确认；仍返回已过期时间时维持 `unknown`，
   等服务端同步完成，不能单凭本地缓存推断自动续费失败。
4. `expires_at=null` 或服务器时间尚未校准时，采用刚拉取的服务端状态，
   有效会员缓存缩短至 30 秒。其他缓存最长 5 分钟。
5. 服务器时间来自现有 Gateway 时间校准，之后按单调计时推进，
   到期比较不直接使用设备 `DateTime.now()`。
6. 启动时恢复会话后后台预取，不阻塞首页；缺失后端 token 时先尝试原有恢复流程。
   登录/换号后刷新，退出登录立即清空会员缓存并隔离旧请求。
7. 返回前台时，距上次有效响应不足 30 秒不重复请求。前台会员到期时请求确认；
   后台到期等回前台处理。普通缓存到期仅发布 `unknown`，不持续轮询接口。
8. 购买、恢复、claim 完成后，复用原有 `refreshAfterMembershipChanged()` 的最新
   钱包响应更新全局状态，不额外再发一次钱包请求。
9. 单次查询最多等待 20 秒。没有可用信息时失败返回 `unknown`；后续调用经过
   2、4、8、16、30 秒（上限）冷却后可重试。没有无限后台重试任务；
   已知且仍有效的旧缓存不会因一次刷新失败被清空。

现有 Gems 金额计算、购买、UI 和 VIP 订单/claim 重试逻辑不作调整。
这里的缓存用于客户端业务判断，购买及权益的最终确认仍来自服务端。

## 验证

在项目目录执行，Flutter SDK 路径为 `/opt/homebrew/share/flutter/bin`：

```sh
dart format lib/app/membership/membership_access_store.dart test/app/membership/membership_access_store_test.dart test/widget_test.dart
PUB_HOSTED_URL=https://pub.flutter-io.cn flutter test --no-pub test/app/membership/membership_access_store_test.dart test/app/gems/gem_wallet_store_test.dart
PUB_HOSTED_URL=https://pub.flutter-io.cn flutter test --no-pub test/widget_test.dart --plain-name 'membership '
dart analyze lib/app/membership/membership_access_store.dart lib/app/bootstrap/app_bootstrap.dart lib/app/bootstrap/service_registry.dart test/app/membership/membership_access_store_test.dart test/widget_test.dart
git diff --check
```

2026-09-09 回调接口验证结果：会员状态及回调 24 项、钱包 9 项、启动/登录 2 项均通过；
静态分析和差异检查通过。此前全局服务实现还通过了时钟、Gateway、购买/恢复/claim
及 Gems 页面相关测试。
覆盖失败重试、并发合并、缓存与到期、时钟、登录隔离、迟到响应、启动及登录接入。
真机弱网、后台挂起及服务端真实续费场景仍需联调验证。
