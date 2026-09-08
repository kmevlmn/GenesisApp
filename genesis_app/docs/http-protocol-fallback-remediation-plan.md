**Worldo HTTP 协议回退与日志重复整改方案**

状态（2026-09-07 修复更新）：失败保留策略也已完成，当前 348 项相关回归通过，详见 [失败保留策略](/Users/long/Project/GenesisApp_2/genesis_app/docs/collect-failure-retention.md)。以下保留前几轮实施记录。基础协议整改及复查发现的 4 处遗漏均已完成客户端修复，当前 321 项相关回归和静态检查通过。详见[复查及修复记录](/Users/long/Project/GenesisApp_2/genesis_app/docs/http-protocol-fallback-review.md)。服务端入库去重、真实设备网络切换和上线效果仍待核验。

代码基线：`/Users/long/Project/GenesisApp_2/genesis_app`，分支 `main`，完整提交 `488ef8f621e3bfd16c70f23a6565a86ab4628a2f`。该提交时间为 2026-09-07 18:16:05（Asia/Shanghai），作者 nikos，标题为「FIX·踢登录清除uid缓存问题」。方案日期：2026-09-07。编写方案前工作区无未提交改动。

**1. 整改目标**

采用“HTTP/3 可用时优先使用，允许回退 HTTP/2、HTTP/1.1”的兼容策略。所有 HTTPS 请求继续保持证书和 TLS 校验。HTTP/1.1 是允许的 HTTP 版本，不表示改用明文 HTTP。

“优先”由实际连接的网络引擎依据服务发现、连接状态和网络可达性实现，不要求每个请求机械地按 3、2、1 顺序尝试；首次请求使用 HTTP/2 不直接判定为异常。HTTP/3 的可用性需要 App 直连的 CDN/网关支持，不能仅凭源站配置判断。

完成后应满足：

- 成功响应不再因使用 HTTP/1.1 或协议元数据缺失而变成网络错误。
- 协议选择由连接层执行，不在应用层捕获一个不确定是否执行成功的 POST 后，切换网络实现再发一次。
- 超时、取消、证书错误、响应损坏、HTTP 错误和业务错误继续按各自规则处理。
- API、Gateway、Collect、图片共享一致策略，WebSocket 消息协议保持独立。
- 同一 Collect 事件在重试时保留原 `event_id`；最终业务统计只计算一次。

**2. 已确认的问题与证据边界**

| 编号 | 当前问题 | 影响及证据 |
|---|---|---|
| 1 | 原生网络层收到响应后，发现 HTTP/1.1 就中止并抛异常 | 当前代码和可控 POST 测试均确认；成功响应体无法交给业务层 |
| 2 | Dio 收到响应后要求协议必须是 `2.0` | HTTP/1.1 和协议未知都被当成连接失败 |
| 3 | Dio 的 HTTP/2 连接不支持时，项目自定义回调直接抛异常 | 已有 HTTP/1.1 备用适配器没有得到使用机会；依赖源码确认此回调发生在创建业务请求流之前 |
| 4 | iOS 用单独 URLSession 探测 `/robots.txt` 并长期缓存选路 | 探测连接不能代表后续业务连接；一次失败可能让该实例一直选择 HTTP/2 |
| 5 | iOS 预热、探测与底层请求超时分离 | 等待可能超出调用方预期；单独对 Future 设置超时不会自动取消实际请求 |
| 6 | Collect 对协议异常保留原批次并重试 | 可造成重发；线上是否重复入库、报表是否去重，需接收端及统计端证据 |
| 7 | 原生响应协议读取器只识别 Android Cronet | iOS 原生通道返回未知，不能把它标记为已确认使用 HTTP/3 |

已完成的可控复现使用生产 `PlatformHttp3Transport`、`SdkCollectTelemetryClient`、`CollectTelemetryUploader`，替换底层接收端与协议读取结果：只生成 3 条事件，接收端返回 HTTP 200 和 `err_no=0`。首次协议为 HTTP/1.1 时，共收到 2 次完全相同的 POST、6 条事件；HTTP/2 对照组只收到 1 次 POST、3 条事件。这证明客户端机制，未证明具体线上事件的完整因果链。

**3. 客户端整改项目**

| 编号 | 优先级 | 文件 | 具体修改 | 验收结果 |
|---|---|---|---|---|
| C1 | P0 | [platform_http3_transport.dart](/Users/long/Project/GenesisApp_2/genesis_app/lib/network/platform_http3_transport.dart) | 删除 HTTP/1.1 响应触发 `abort()` 和异常的分支；继续读取完整响应，保留实际协议元数据 | h3、h2、HTTP/1.1、未知协议均可返回真实响应 |
| C2 | P0 | [dio_http_transport.dart](/Users/long/Project/GenesisApp_2/genesis_app/lib/network/dio_http_transport.dart) | 删除响应必须为 `2.0` 的判断；保留协议归一化和响应记录 | HTTP/1.1 成功不再被改写为连接失败 |
| C3 | P0 | [dio_http_transport.dart](/Users/long/Project/GenesisApp_2/genesis_app/lib/network/dio_http_transport.dart) | 移除直接抛异常的 `onNotSupported`，使用已配置的 HTTP/1.1 备用适配器；不新增对任意失败 POST 的重发 | HTTP/2 建连不支持时，业务请求只由备用通道发送一次 |
| C4 | P1 | [genesis_http_transport_pool.dart](/Users/long/Project/GenesisApp_2/genesis_app/lib/network/genesis_http_transport_pool.dart)；已删除 `ios_adaptive_http_transport.dart` | iOS 默认直接使用 URLSession 原生网络实现，让系统处理协议选择；移除按独立探测结果切换 HTTP/3 与 Dio 的业务必经路径 | 请求不再等待 `/robots.txt` 探测，也不会因应用自建探测缓存长期固定在 HTTP/2 |
| C5 | P1 | [AppDelegate.swift](/Users/long/Project/GenesisApp_2/genesis_app/ios/Runner/AppDelegate.swift) | C4 生效且确认无其他调用后，删除 `probeHttpProtocol`、探测实例容器和 `GenesisHttpProtocolProbe`；只清理这条专用能力 | 无残留方法调用、无无用探测请求；其他原生通道正常 |
| C6 | P1 | [genesis_http_cache_manager.dart](/Users/long/Project/GenesisApp_2/genesis_app/lib/network/genesis_http_cache_manager.dart)、[genesis_http_transport_pool.dart](/Users/long/Project/GenesisApp_2/genesis_app/lib/network/genesis_http_transport_pool.dart) | 图片预热作为可失败的优化，不再成为真实资源请求的必经等待；原生初始化失败时可选择兼容的 Dio 通道 | 预热失败不直接导致后续图片请求失败 |
| C7 | P1 | [http_transport.dart](/Users/long/Project/GenesisApp_2/genesis_app/lib/network/http_transport.dart)、三个 HTTP 实现、[collect_telemetry.dart](/Users/long/Project/GenesisApp_2/genesis_app/lib/app/telemetry/collect_telemetry.dart) | 明确单次发送总预算覆盖准备、连接、发送、响应头和响应体；到期取消底层任务；排队请求在真正发出前再次检查取消状态 | 超时后不会因为之前的准备工作结束而新发出业务 POST；持续到来的响应分片也不能无限延长总时间 |
| C8 | P1 | HTTP 响应元数据、开发网络诊断与相关测试 | 记录能确认的协议、状态码、耗时和取消/失败类别；iOS 未取得实际协议时保留未知；协议指标采集不得阻塞业务结果 | 不把未知误标为 h3；不再把正常 HTTP/1.1 计为 `tech_client_1015` |

C4 的推荐实现采用现有 `cupertino_http`，不新增强制 HTTP/3 的私有接口。Android 保留 Cronet 的 HTTP/2、QUIC 开关及已有 QUIC hints。HTTP/3 的服务发现由服务端 DNS HTTPS 记录或 Alt-Svc 等能力配合；不把“每次冷启动首个请求必须是 h3”设为本轮验收条件。若以后提出这一要求，应单独评估 URLRequest 提示能力及原生桥接成本。

C7 作为可独立回退的逻辑改动实施。保留原有预算数值，将各阶段独立超时改为单次总预算；持续响应体及延迟准备的本地回归已通过，发布前仍需真机网络切换对照。Collect 外层超时保护已与取消令牌联动。取消不能撤回服务端已经完成的操作，因此此项不能替代去重。

网络实现切换仅允许发生在明确尚未发送业务请求的连接准备阶段，或为后续独立请求选择通道。不得在不知道 POST 是否到达服务端时，自动切换 Cronet、URLSession、Dio 后重发。普通 API 的 `ApiRetryPolicy.safe` 继续只处理现有 GET/HEAD 重试范围。

**4. Collect、服务端与报表整改**

| 编号 | 负责范围 | 内容 | 验收结果 |
|---|---|---|---|
| D1 | 客户端 | 保持事件生成时的 `event_id`、时间和内容；只有完整的 2xx 且合法 JSON `err_no=0` 才认定正常上传成功；保留当前永久无效事件隔离机制 | 三种协议下正常成功只发送一次，真实临时失败仍按原 ID 重试 |
| D2 | 服务端接收与写入 | 核对同一应用/环境范围内按 `event_id` 去重的实际实现；采用原子唯一约束或等价机制；已接收的重复事件返回成功确认 | 同批重发、并发重复请求、跨进程补发均不会重复产生业务统计效果 |
| D3 | 服务端批次确认 | 核对响应与持久化顺序，批次中所有合法事件已持久化或已去重后才返回成功；单个服务端响应仍不支持部分事件成功确认；客户端拆成多个请求后的子批次已独立确认 | 不出现客户端删除整批但部分合法事件未保存的情况 |
| D4 | 报表 | 若原始日志为追加存储并保留重复行，查询先按环境及 `event_id` 去重，再计算 PV、事件次数、成功率和漏斗 | 原始接收行数与有效事件数分开；不同 `event_id` 的真实事件不被误合并 |
| D5 | 联合排查 | 用同一 `event_id` 关联客户端上传尝试、接收端请求记录与最终写入/统计结果；检查导出是否只包含 monitor | 能区分客户端重发、服务端重复写入和报表重复计数 |

当前没有核对服务端实现，因此 D2—D4 是待确认和待实施项，不能直接认定服务端已经缺少去重。正常响应超时、进程退出和本地删除失败仍可触发重发；客户端协议修复不能承诺网络请求恰好发送一次。

Collect 自身继续排除在普通 API 打点之外，避免递归。需要诊断 Collect 时使用有界本地日志、开发抓包或接收端记录；记录批次事件 ID、尝试次数、协议（未知须注明）、状态码与错误类别，不记录登录凭证和完整敏感请求内容。

**5. 实施顺序与提交边界**

| 顺序 | 工作包 | 交付及前置条件 |
|---|---|---|
| 1 | A：恢复协议兼容 | C1—C3 与对应回归测试；同步修改“HTTP/1.1 应失败”的旧断言。先消除已确认的成功响应误判，不依赖 iOS 选路重构 |
| 2 | B：iOS 选路简化 | C4—C6 与 native 编译、图片/启动性能验证；单独提交，便于回退 |
| 3 | C：超时取消与可观测性 | C7—C8；验证取消传播及真实协议记录，不扩大普通 POST 重试范围 |
| 并行 | D：去重核对与补齐 | 服务端及报表负责人核对 D2—D5；不阻塞客户端 A 的修复，但全链路“重复事件只计一次”的结论依赖该项完成 |

客户端技术说明同步更新 [接口契约](/Users/long/Project/GenesisApp_2/genesis_app/docs/apifox-http-api-contract.md) 和 [接口监控说明](/Users/long/Project/GenesisApp_2/genesis_app/docs/api-request-monitoring-report-spec.md)。普通协议回退不再归为 `tech_client_1015`，真正的连接/协议异常仍保留技术失败记录。Collect 实际默认批次为 100 条，契约中的旧默认描述和身份快照描述应按生产代码校准；接口允许上限与客户端默认批次分别说明。

**6. 验收矩阵**

以下是实施后必须完成的验证，不是当前已通过的结果。

| 场景 | 预期 |
|---|---|
| 服务支持 h3，设备网络可达 | Android/iOS 能实际使用 h3；用原生网络指标或接入端记录确认，不能用注入的测试协议值代替 |
| 服务仅支持 h2 | 正常请求，不产生客户端人为的协议失败 |
| 服务仅支持 HTTPS + HTTP/1.1 | 原生路径正常接收；Dio 路径先确认 h2 不可用再由备用通道发送，接收端业务 POST 为一次 |
| UDP 不通、TCP/TLS 正常 | 系统可以选择可用的 h2/HTTP/1.1，不由应用层依次重发同一业务 POST |
| 协议元数据缺失 | 业务结果正常；诊断显示未知 |
| HTTP/1.1 返回 200、合法 JSON、`err_no=0` | Collect 队列清除，后续检查不再次发送该批；正常 API 可进入成功处理 |
| HTTP/1.1 返回业务 `10001` | 进入踢登录处理，清理本地会话与打点 UID |
| HTTP 401/403/500、业务错误、无效 JSON | 原状态和错误能进入现有处理；不能因放开协议而误判成功 |
| 证书不可信或 TLS 失败 | 继续失败，不能通过关闭证书验证来实现协议回退 |
| 私信、发帖、创建、领取返回成功 | 客户端成功状态与服务端一致；没有因协议产生的二次提交 |
| 商店支付成功、订单确认返回成功 | 正常完成订单确认、成功提示与余额刷新；故障补单保留同一交易身份 |
| 预热失败、准备阶段取消/超时 | 正常请求不依赖失败预热；被取消/超时的旧任务不晚发业务请求 |
| 响应持续缓慢返回 | 单次总预算到期后任务取消，不因持续分片无限等待 |
| 服务端已写入但响应丢失 | 客户端可能重试；同一 `event_id` 最终只计一次，重复确认可结束队列重试 |
| 旧版本遗留队列、成功后本地删除失败、重启恢复 | 事件 ID 不变；与服务端去重共同保证有效事件数正确 |
| 开发代理开启 | 明确记录这是代理路径；接口、图片和日志仍可用，不将代理协议当成线上 h3 使用证明 |

拟运行的定向验证命令：

```sh
flutter test --no-pub test/network/platform_http3_transport_test.dart test/network/dio_http_transport_test.dart test/network/ios_adaptive_http_transport_test.dart test/network/network_runtime_factory_test.dart test/network/genesis_http_cache_manager_test.dart
flutter test --no-pub test/app/telemetry/collect_telemetry_test.dart test/network/api_client_collect_telemetry_test.dart test/network/api_client_test.dart
```

B 若删除 iOS 自适应类，应将相应测试迁移到最终网络构造/路由测试，命令随最终文件更新。补充实际 POST + HTTP/1.1-only TLS 服务集成测试，不能只用假响应检查分支。API、登录、踢登录、私信、签到和支付按最终改动运行相关窄用例；运行 `dart format` 与文件相关 `flutter analyze --no-pub`。原生桥接删除后需要 Android/iOS 编译及真机验证，单元测试通过不能代替安装验证。

**7. 发布与回退**

先内部测试，再按 Android/iOS 和版本小范围发布。分别比较登录成功、私信发送、订单确认、首屏/图片加载、技术失败率和耗时分位数；Collect 另看“收到的事件行数、去重后的事件数、客户端队列积压”。比较时使用相同平台、版本范围、网络条件和时间窗口，不能只看 `1015` 降低。

A、B、C 独立提交。若 B 的 iOS 原生选路出现性能回退，可以回退 B 并保留 A 的协议兼容修复；不恢复“HTTP/1.1 成功也抛异常”的行为。C 的超时语义变更同样独立回退。

现有 `GENESIS_HTTP_ENGINE=http2` 可用于构建不启用 h3 的对照/应急版本，前提是保留 A 后的 HTTP/1.1 备用能力。它目前是构建参数，不能描述成已经具备远程切换能力；应急切换需要重新构建和分发版本。

出现新的登录、发消息或支付确认阻断时停止扩大范围，依据接入端和客户端记录定位。只有完成服务端及报表核对后，才能宣布重复计数问题整体关闭。

**8. 本轮不扩大的范围**

本方案不改变用户触发登录后等待二次操作、聊天自动重连、签到弹窗范围和余额字号等已确定行为；不重写 WebSocket 消息重试，不让所有 POST 自动重试，也不调整支付发奖或交易去重规则。私信、发帖等接口的服务端幂等能力可单独审查，不能用协议兼容整改代替该项工作。

**9. 外部依据**

- [Apple：HTTP/3 in your app](https://developer.apple.com/documentation/technotes/tn3102-http3-in-your-app)：HTTP/3 服务发现、请求提示和网络/服务不支持时的协议回退；支持能力不等于每次请求一定使用 h3。
- [Android：CronetEngine.Builder](https://developer.android.com/develop/connectivity/cronet/reference/org/chromium/net/CronetEngine.Builder)：HTTP/2、QUIC 开关及 QUIC hints。现有客户端继续使用这些公开能力。
- [RFC 9110 §9.2.2](https://www.rfc-editor.org/rfc/rfc9110.html#section-9.2.2)：自动重试非幂等请求需要已知幂等语义或确认原操作未执行；业务失败后换协议重发不能作为通用回退方案。

本方案参考了既有排查记录，涉及当前行为的结论均重新核对了本分支代码及锁定的网络依赖。

**10. 实施记录**

- Android 保留 Cronet HTTP/2、QUIC 配置；iOS 直接进入 Cupertino/URLSession。删除专用探测 MethodChannel、实例容器和旧自适应类，其他原生通道未改。
- 原生和 Dio 收到 HTTP/1.1、h2、h3 或未知协议响应时均返回真实结果；Dio 使用原有 HTTP/1.1 fallback。真实 loopback TLS 测试先确认未信任证书不能发送 POST，再在测试信任库中加入临时证书，确认 h1 接收端只收到一次 POST。测试需要 `openssl`，证书即时生成并在结束后删除。
- 总超时覆盖 metric 准备、发送、完整响应体。Collect 外层取消传递至 SDK；子请求到期不取消可复用的调用方 token。原生 abort、Dio CancelToken、IO request abort 和响应流取消均接入。Dio HTTP/2 建连返回后再次检查取消状态，防止创建迟到请求或迟到 fallback；共享建连本身可能继续完成供其他请求复用，不因此关闭全局连接池。
- 保留原事件 ID、确认条件及 GET/HEAD 安全重试。可控 Collect 回归在 h1/h2/h3/未知四种元数据下均为 3 个事件、1 次 POST，后续检查不再重传；真实失败仍保留原 ID。
- 协议指标支持 `http/1.1`，iOS 无元数据仍返回未知；DevTools 和 metric 收尾不等待业务结果。`http2` 仅由已有的间接依赖改为直接依赖，版本仍为 2.3.1，没有升级其他依赖。
- 已同步 Collect 客户端默认 100 条/256 KiB、入队身份快照和 `tech_client_1015` 的文档口径。
- 服务端核查：当前客户端仓库没有 Collect 接收/入库实现。已只读核对本机 `worldo-api-dashboard/dashboard.go` 的 `seenEvents[event.EventID]` 去重，但它仅覆盖该看板读取到的 API/启动事件，不能证明 Collect 原始存储及所有业务报表具备原子去重。D2–D5 的服务端/全量统计验收仍未完成，未修改外部仓库。

验证：15 个修改涉及的 Dart 文件静态分析通过，`xcrun swiftc -frontend -parse ios/Runner/AppDelegate.swift` 通过；以下测试命令共 294 项通过：

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
  test/app/startup/app_startup_coordinator_test.dart \
  test/network/api_client_test.dart \
  test/network/api_client_collect_telemetry_test.dart \
  test/network/genesis_api_test.dart \
  test/network/local_mock_genesis_transport_test.dart \
  test/network/gateway_auth_test.dart
```

编译通过：

```sh
flutter build ios --release --flavor production --no-codesign --no-pub
flutter build apk --release --flavor production --target-platform android-arm64 --no-pub
```

本地输出：`build/ios/iphoneos/Worldo.AI.app`（46.9 MB，未签名）和 `build/app/outputs/flutter-apk/app-production-release.apk`（29.0 MB）。没有安装到设备、提交或发布。本轮编译保留了 Android 插件已有的 Built-in Kotlin 迁移提示，未升级插件。

发布前剩余验证：Android/iOS 真机 h3/h2/h1 实际协议、UDP 不可达和 Wi-Fi/蜂窝切换、页面交互及服务端同 ID 的原子去重/确认顺序。上述编译和本地测试不能替代这些验收。

**11. 四处遗漏修复验证（2026-09-07）**

已完成：子批次按 ID 确认、迟到入库归并、Dio 未入池 TLS socket 释放、ApiClient 从请求头开始的总预算。增加 27 项回归；总预算到期时保留原 API 监控传输耗时口径，避免等待 Gateway 的时间混入已发出的接口耗时。SQLite 表结构、依赖版本、普通 POST 重试范围保持原有约束。

最终完整测试命令（321 项通过）：

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
  test/app/startup/app_startup_coordinator_test.dart \
  test/network/api_client_test.dart \
  test/network/api_client_deadline_test.dart \
  test/network/api_client_collect_telemetry_test.dart \
  test/network/genesis_api_test.dart \
  test/network/local_mock_genesis_transport_test.dart \
  test/network/gateway_auth_test.dart
```

修改涉及的 22 个 Dart 文件及本地 `dio_http2_adapter/lib` 静态分析：`No issues found!`。`dart format` 与 `git diff --check` 通过。


最终代码双端编译通过（包含 API 耗时口径兼容保护）：

```sh
flutter build ios --release --flavor production --no-codesign --no-pub
flutter build apk --release --flavor production --target-platform android-arm64 --no-pub
```

iOS：27.8 秒，`build/ios/iphoneos/Worldo.AI.app`，46.9 MB，未签名。Android：53.9 秒，`build/app/outputs/flutter-apk/app-production-release.apk`，29.0 MB。Android 仍提示既有插件的 Built-in Kotlin 迁移事项，本轮未升级插件。

测试、静态检查和双端编译日志分别保存在 `/tmp/worldo-four-fixes-regression.log`、`/tmp/worldo-four-fixes-analyze.log`、`/tmp/worldo-four-fixes-ios-build.log`、`/tmp/worldo-four-fixes-android-build.log`。未提交、推送、安装或发布；真机网络场景与服务端去重仍按前述边界单独验证。
