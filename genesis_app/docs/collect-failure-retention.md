# Collect 失败保留策略

日期：2026-09-07（Asia/Shanghai）。代码位于 `/Users/long/Project/GenesisApp_2/genesis_app`，分支 `main`；基线提交 `488ef8f621e3bfd16c70f23a6565a86ab4628a2f`，作者 nikos，时间 2026-09-07 18:16:05 +08:00，标题「FIX·踢登录清除uid缓存问题」。本记录描述基线之上的未提交修复。

当前删除条件：必须完成请求，收到 HTTP 2xx、合法 JSON 对象且 `err_no` 为数值 0 或字符串 `"0"`。失败、重试次数、请求大小和内存数量均不再作为删除未确认事件的依据。

## 修改内容

| 情况 | 当前处理 |
|---|---|
| 断网、超时、取消、HTTP 5xx、401/403/408/429 等 | 保留原事件，按退避策略重试 |
| 缺失、空值或非零 `err_no`，无效 JSON、非对象响应 | 不认定成功，也不认定事件永久无效；保留重试 |
| HTTP 400/413/422 | 可拆成子请求尝试；失败单条仍留队，不再放入会丢失的内存隔离区 |
| 单条超过本地请求字节上限 | 保留原内容与 ID，记录失败，等待后续重试或容量配置调整 |
| 子批次成功，另一部分失败 | 仅确认成功 ID；失败项继续排队 |
| 服务端成功，但本地删除失败 | 记录仍在 in-flight，避免立即重发；重启可用原 ID 恢复 |
| 一个批次持续失败 | 失败记录移到待发送队尾，不占住队首；ID、内容、原时间戳和身份快照保持不变 |
| 数据库暂时不可写、内存超过原 300 条阈值 | 不淘汰旧事件，也不因阈值为 0 丢弃；保留内存副本 |
| 数据库恢复、网络仍在退避等待 | 每次检查有界补写内存队列；确认落库后才移除内存副本 |
| 补写超时后迟到完成 | 沿用按 ID 的确认状态核对，已成功上传的迟到副本只清理，不再发送 |

SQLite 表结构和事件 wire 格式没有变化。失败排队顺序通过事务内更新 `sequence_id` 实现，不删除再插入，不改变用于幂等的 `event_id`。进程中断时事务要么完整生效，要么保留原记录。内存 store 和内存 fallback 采用对应的队尾重试顺序。

`CollectUploadFailureKind.permanent` 保留旧枚举名以兼容调用点，现在只表示允许拆批，不能触发丢弃。`deadLetterCount` 兼容字段现在为 0，生产上传器已移除写入内存 dead letter 的路径。`memoryFallbackLimit` 保留旧参数名，用于限制未完成的异步写库数量，不再作为事件淘汰上限。

## 验证

完整相关回归 348 项通过，其中新增 27 项验证本次保留策略。静态分析无问题，`dart format` 与 `git diff --check` 通过。

[保留策略测试](/Users/long/Project/GenesisApp_2/genesis_app/test/app/telemetry/collect_delivery_retention_test.dart) 覆盖 17 类失败响应的连续重试和 SQLite 重开，真实本机 HTTP 400 → 200 请求，子批次失败、单条超限、失败队尾重试、网络退避中的恢复补写、迟到补写和内存原阈值 0/2 下的数据保留。测试直接经过 `SdkCollectTelemetryClient` 与真实 SQLite，不向生产 Collect 发送数据。

原先用于诊断错误行为的 `.dart_tool/collect_delivery_safety_audit_test.dart` 是修复前复现脚本，不是当前正确行为的测试；正式验收使用上述新测试。

实际测试命令：

```sh
flutter test --no-pub \
  test/network/platform_http3_transport_test.dart \
  test/network/dio_http_transport_test.dart \
  test/network/io_http_transport_test.dart \
  test/network/http_transport_deadline_test.dart \
  test/network/collect_protocol_fallback_test.dart \
  test/network/dio_http_fallback_integration_test.dart \
  test/network/genesis_http_cache_manager_test.dart \
  test/network/network_runtime_factory_test.dart \
  test/network/devtools_http_profile_test.dart \
  test/app/telemetry/collect_telemetry_test.dart \
  test/app/telemetry/collect_upload_recovery_test.dart \
  test/app/telemetry/collect_delivery_retention_test.dart \
  test/app/startup/app_startup_coordinator_test.dart \
  test/network/api_client_test.dart \
  test/network/api_client_deadline_test.dart \
  test/network/api_client_collect_telemetry_test.dart \
  test/network/genesis_api_test.dart \
  test/network/local_mock_genesis_transport_test.dart \
  test/network/gateway_auth_test.dart

dart analyze lib/app/telemetry/collect_telemetry.dart \
  test/app/telemetry/collect_telemetry_test.dart \
  test/app/telemetry/collect_upload_recovery_test.dart \
  test/app/telemetry/collect_delivery_retention_test.dart
```

日志：`/tmp/worldo-collect-retention-regression.log`、`/tmp/worldo-collect-retention-analyze.log`。

最终代码的双端 release 编译均通过：

```sh
flutter build ios --release --flavor production --no-codesign --no-pub
flutter build apk --release --flavor production --target-platform android-arm64 --no-pub
```

- iOS：Xcode 编译 26.3 秒，生成 `build/ios/iphoneos/Worldo.AI.app`（46.9 MB），未签名。
- Android：Gradle 编译 50.8 秒，生成 `build/app/outputs/flutter-apk/app-production-release.apk`（29.0 MB）。现有插件的 Built-in Kotlin 迁移警告没有阻断编译。

编译日志：`/tmp/worldo-collect-retention-ios-build.log`、`/tmp/worldo-collect-retention-android-build.log`。本轮未进行真机安装、代码提交、推送或发布。

## 保留范围与边界

本次保证的是不因一次上报失败、累计失败次数、单条超限或内存数量阈值主动移除未成功事件。已经成功落库的失败记录能在重开数据库后继续上传，ID 和原内容不变。

如果数据库持续完全无法写入，备用数据只能留在进程内存，内存占用会随积压增加；在重新落库或上传成功前，进程被系统终止仍可能丢失这些内存记录。本轮没有新增独立磁盘备份文件，不能声称在存储不可用、磁盘满或进程异常终止的组合故障下也能绝对不丢。已经被旧版本清理的历史数据也不能凭此恢复。

服务端已处理但客户端未收到确认时，保留重试可能再次发送相同 ID，仍需要接收端幂等。服务端是否先持久化再返回成功，以及真机弱网/进程终止场景，未在本地测试中证明。
