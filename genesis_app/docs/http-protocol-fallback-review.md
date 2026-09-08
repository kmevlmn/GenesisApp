# HTTP 协议整改复查及修复记录

最新更新：下文“补充复查”发现的失败清理问题现已修复，当前策略为未确认成功不删除，348 项相关回归通过。以 [Collect 失败保留策略](/Users/long/Project/GenesisApp_2/genesis_app/docs/collect-failure-retention.md) 为准；下文保留前几轮实现和诊断记录。

日期：2026-09-07（Asia/Shanghai）。检查对象为 `main` 分支、基线提交 `488ef8f621e3bfd16c70f23a6565a86ab4628a2f` 之上的当前未提交整改；基线作者 nikos，时间 2026-09-07 18:16:05 +08:00，标题「FIX·踢登录清除uid缓存问题」。

前次复查确认的 4 处遗漏均已修复。当前本地 321 项相关回归通过，所有修改涉及的 Dart 文件与本地适配器静态检查无问题；最终 Android arm64 与 iOS production release 编译均通过（iOS 未签名）。以下区分修复前复现、修复后行为和仍需外部验证的边界。

| 序号 | 原问题 | 修复后行为 | 证据 |
|---|---|---|---|
| 1 | 拆批一部分成功、一部分失败，成功部分整批重发 | 成功或永久隔离的子批次按 ID 立即确认；仅重试未成功部分 | 大小拆批、永久错误隔离分别覆盖 SQLite、内存 store、内存 fallback；接收结果由 `A,A,B` 变为 `A,B` |
| 2 | 入库超时转内存后，迟到入库导致跨队列重复 | 跟踪未结束写入及上传确认，迟到记录与内存副本归并；已确认 ID 清理后不再发送 | 入库发生在内存上传前、上传中、上传后，以及入库已提交但 Future 未结束等时序均只收到一次 |
| 3 | Dio 不支持 h2 时遗留未入池 TLS socket | 抛出回退信号前释放该 socket；成功 h2 连接仍入池复用 | 真正的本机 TLS 服务连续 4 次 h1 POST，连接数均归零；2 个并发和 1 个后续 h2 POST 共用 1 条 TLS 连接 |
| 4 | ApiClient 请求头和 Gateway 等待不计入总超时 | 从 API 准备阶段起共享原有超时预算；超时/取消后禁止迟到发送及处理响应 | 请求头、拦截器、连续响应体、取消、迟到响应和共享 Gateway 初始化回归；超时只产生一个技术失败终态，实际传输耗时不混入 Gateway 准备时间 |

## 1. 子批次独立确认

[上传器与拆批处理](/Users/long/Project/GenesisApp_2/genesis_app/lib/app/telemetry/collect_telemetry.dart:837) 在每个子批次成功或永久隔离后立即确认对应 `event_id`。SQLite 使用按 ID 删除，内存队列同步移除成功部分。无需修改数据库表结构或重建旧队列。

本地删除失败时，成功事件留在 in-flight，不立即放回待发送队列；尚未成功的同批事件仍可单独重试，后续新事件可以继续处理。已经取得成功响应但来不及持久化确认就退出进程的情况，仍沿用重启恢复及原 ID 重试语义，需要服务端按 ID 去重。

这是既有队列逻辑的遗漏，不能据此认定某次线上重复的唯一原因。

## 2. 迟到写入与内存副本归并

[写入与归并](/Users/long/Project/GenesisApp_2/genesis_app/lib/app/telemetry/collect_telemetry.dart:730) 保留原异步写入的完成通知，按事件 ID 记录其落库、内存接管和确认状态。数据库领取事件时接管未确认的内存副本；已上传成功的迟到写入只清理，不再进入网络上传。

确认信息在本地删除失败时保留，恢复后继续清理；数据库已经返回旧批次快照、清理任务同时完成的交错时序也有回归保护。跟踪数量受内存 fallback 上限约束，存储长期卡住时不无限增加异步写入和确认缓存。

可控延迟 store 用于证明上述时序处理；真实 SQLite 用于验证按 ID 确认、批次释放、持久化和旧版本迁移，不代表已测出真机慢写的发生频率。

## 3. Dio TLS 连接回收

[本地依赖修补](/Users/long/Project/GenesisApp_2/genesis_app/third_party/dio_http2_adapter/lib/src/connection_manager_imp.dart:304) 基于锁定版本 2.8.0。唯一运行逻辑差异是在 `_throwIfH2NotSelected` 中先保存协议值、销毁未入池 socket，再抛出原有异常。补丁和 LICENSE 随仓库保存，通过 path override 接入，没有修改本机 pub cache，也没有升级依赖版本。

h1 测试接收端在每个响应后主动关闭业务连接，修复前闲置连接为 `1,2,3,4`，修复后每次均为 0；每次请求仍只有一个业务 POST。h2 测试明确设置测试服务的 ALPN，并确认成功连接复用。原有不信任证书拒绝、建连期间取消不关闭共享池的用例继续通过。

适用范围是 Dio 及其 fallback；默认 Cronet/URLSession 自身的协议协商不经过此依赖。

## 4. API 准备阶段总预算

[ApiClient](/Users/long/Project/GenesisApp_2/genesis_app/lib/network/api_client.dart:311) 让运行时 headers、拦截器/Gateway、实际发送及安全重试共享原有 `timeoutMs`，总预算到期不再发起下一次尝试。请求使用关联调用方 token 的独立子 token，超时不取消可复用的调用方 token。

[Gateway](/Users/long/Project/GenesisApp_2/genesis_app/lib/network/gateway_auth.dart:31) 在准备、签名及发送的异步边界检查取消；单个请求结束不会取消其他请求共用的注册/时间初始化。超时调用的迟到准备或响应不会再次发出业务请求或执行 API 响应处理器。普通 POST 自动重试范围没有扩大。

## 本地验证

完整定向测试：321 项通过。覆盖 transport、API、Gateway、启动、图片缓存和 Collect；其中新增 27 项回归。新增/扩展测试入口：

- [Collect 队列恢复](/Users/long/Project/GenesisApp_2/genesis_app/test/app/telemetry/collect_upload_recovery_test.dart)
- [API 总预算](/Users/long/Project/GenesisApp_2/genesis_app/test/network/api_client_deadline_test.dart)
- [真实 TLS 回退与 h2 复用](/Users/long/Project/GenesisApp_2/genesis_app/test/network/dio_http_fallback_integration_test.dart)
- [API 失败终态](/Users/long/Project/GenesisApp_2/genesis_app/test/network/api_client_collect_telemetry_test.dart)
- [Gateway 共享初始化](/Users/long/Project/GenesisApp_2/genesis_app/test/network/gateway_auth_test.dart)

原有 token 引用相等断言改为请求独立 token，取消传播由行为测试验证；生命周期用例等待真实上传结束再检查事件，不依赖固定等待时间。完整测试命令和编译结果见[整改方案实施记录](/Users/long/Project/GenesisApp_2/genesis_app/docs/http-protocol-fallback-remediation-plan.md)。

真机 h3/h2/h1、弱网和网络切换、页面操作及服务端同 ID 原子去重仍需联调；本地测试和编译不能代替这些证据。未提交、推送、安装或发布。


## 补充复查：未成功事件是否会被移出队列（修复前记录）

2026-09-07，根据“担心未上报成功就被删除”的反馈，新增 SDK → 上传器 → 真实 SQLite 队列的故障响应检查。此次只诊断，没有进一步修改生产代码。原来的 4 处修复仍成立，但不能据此承诺“所有未成功事件都一直保留重试”。

- 超时、断网、HTTP 500/401/403/408/429、无效 JSON、非对象 JSON：失败后数据库保留同一 ID；接收端恢复成功响应后再次发送该 ID并正常清理。
- HTTP 200 + 缺失 `err_no`、HTTP 200 + 非零 `err_no`（诊断值 5000）、HTTP 400：均走现有 `permanent` 分支。失败后待发送记录为 0，内存 dead letter 为 1；随后接收端恢复成功响应，也不会再次发送。这是已复现的停止重试路径，不能当作已经成功投递。
- 该分类及 dead letter 行为在基线 HEAD 已存在，本轮保留了它。所有非零/缺失 `err_no` 都可证明失败，但没有足够的接口契约证明它们都意味着永久无效事件。
- dead letter 仅驻留内存，最多 100 条；独立内存 fallback 默认最多 300 条，满后淘汰旧记录。单条超过批次字节上限也会隔离并停止重试。这些路径均不能提供无条件的不丢失保证。

诊断命令：

```sh
flutter test --no-pub .dart_tool/collect_delivery_safety_audit_test.dart test/app/telemetry/collect_upload_recovery_test.dart test/network/collect_protocol_fallback_test.dart
```

32 个用例执行通过，其中 12 个用于验证当前失败响应处理，包含对上述风险现状的复现断言，不能当作已修复这些风险的证据。日志：`/tmp/worldo-collect-delivery-safety-audit.log`。诊断脚本留在忽略目录，未纳入正式回归。

后续应收紧为：只有明确成功才能从待发送存储删除；未知/临时失败保留重试；经契约确认的无效事件若需要隔离，应持久化保存并提供恢复策略，避免以一次非零响应直接作永久丢弃判断。
