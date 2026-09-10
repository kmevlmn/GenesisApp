# VIP 游客购买、恢复与账号绑定实施方案

核对日期：2026-09-09。本文主体仍是实施方案，未完成整个流程或真机联调。后续用户已确认服务端移除上报、恢复、绑定请求中的 `base_plan_id`，商品列表与发起购买保留；该字段的客户端调整已单独实施，Apifox 暂未同步。

## 1. 接口基线与需要先对齐的事项

已刷新 Apifox 并核对现有 Flutter 实现。

| 接口 | 最新契约及客户端用途 |
| --- | --- |
| `POST /api/v1/membership/guest/prepare` | 请求仍为 `provider + device_id`；响应只有 `account_uuid`。购买前准备身份，不能据此认为已付款。 |
| `POST /api/v1/membership/guest/purchase/report` | 游客身份只传 `account_uuid`，同时提交平台购买信息、凭据及 `request_id`。 |
| `POST /api/v1/membership/guest/purchase/check` | 请求只有 `account_uuid`；成功响应只有 `has_unbound_order`。公开只读，只查服务端已有记录，不向商店验单。 |
| `POST /api/v1/membership/claim` | 最新文档要求真实登录，并提交 `account_uuid + 平台购买信息及凭据 + request_id`。客户端响应模型继续只读取 `status`。 |
| `GET /api/v1/gem/wallet` | claim 完成后重新获取，使用响应中的 membership 更新会员状态。 |

接口依据：[prepare](https://app.apifox.com/link/project/8297783/apis/api-512243338)、[check](https://app.apifox.com/link/project/8297783/apis/api-512807632)、[claim](https://app.apifox.com/link/project/8297783/apis/api-512243340)。

### 1.1 claim 参数存在一处待确认的表述差异

用户要求“去掉 guest_id，只保留 account_uuid”。最新文档明确禁止仅凭 UUID 或 device_id 认领，且 claim 请求引用游客 report 的同一请求模型。因此，本方案中“只保留 UUID”是指游客身份字段；整个请求仍需交易凭据。这个解释已单独提问，尚待用户确认。

按文档及用户后续确认，共同字段为 `account_uuid / provider / plan_code / store_product_id / request_id`；Google 另传 `purchase_token`，Apple 另传 `transaction_id / signed_transaction`。`base_plan_id` 已按用户确认从请求中去掉；无缓存恢复的 `plan_code` 是否可省略尚待确认。不再发送 `guest_id`、`claim_token`，UID 从登录 session 获取。

如果用户要求整个请求体只有 UUID，需要先调整服务端认领授权设计及契约，再实施该分支；当前文档不能支持这种调用。

### 1.2 Android 无缓存恢复仍需确认 plan_code 规则

Google 客户端订单提供商品 ID、purchaseToken 和购买时的账号标识，但没有已购买订单的 `base_plan_id`。项目里的月、年会员共用 Google 商品 ID，现有恢复代码也明确在缺少原订单时不能推断套餐。查询在售商品只能知道有哪些套餐，不能证明历史订单买了哪一个。

用户已确认服务端验单获取 base plan，客户端不再提交 `base_plan_id`。但目前尚未确认无缓存恢复是否允许省略 `plan_code`；它同样区分月/年套餐，因此仅移除 base plan 还不足以完成当前客户端的无缓存恢复路径。

剩余需要对齐的契约：

1. 确认 report、restore 和 claim 在缺失本地套餐时是否允许省略 `plan_code`。`base_plan_id` 的去除已经确认，不再作为待实施项。
2. 服务端用有效购买凭据向平台验单，依据官方商品及基础方案映射内部套餐；不能按客户端当前选中的套餐补值。
3. 正常新购买仍提交完整字段；只要客户端提交了套餐字段，服务端仍校验其与官方结果一致。
4. 同步修改两个接口共用的请求模型和校验规则，明确幂等比较按官方确认的交易身份处理。首次恢复生成并保存 request_id，重试保持一致；不能补齐套餐后意外生成另一笔业务操作。

base plan 由服务端验单取得的调整以用户确认为准；`plan_code` 省略规则尚未确认。Google 官方依据：[客户端 Purchase](https://developer.android.com/reference/com/android/billingclient/api/Purchase)、[服务端 SubscriptionPurchaseV2 的 lineItems.offerDetails.basePlanId](https://developers.google.com/android-publisher/api-ref/rest/v3/purchases.subscriptionsv2)。

## 2. 购买前为什么保存，以及失败后怎么处理

需要在调用商店购买前保存，否则系统付款过程中 App 被杀，重启后可能失去这笔购买对应的 UUID 和请求幂等键。但这时保存的是“购买尝试”，不能直接成为强制登录的依据。

数据分成三个独立概念：

| 数据 | 保存时机 | 是否触发强制登录 |
| --- | --- | --- |
| 购买尝试 | prepare 返回 UUID 后、调起系统购买前，持久化成功才继续 | 否 |
| 已付款、待确认交易 | 商店返回已购买时，先保存平台凭据或可恢复的交易标识，再发 report | 否，先等服务端确认 |
| 已确认、待绑定任务 | report completed，或 check 返回 true 后 | 本次购买按成功弹窗 → OK → 登录；重启时先重新 check |

游客身份对象只有 `account_uuid`，订单仍要保存 request_id、平台、商品身份、交易标识、处理状态及关联关系。不能把“去掉 guest_id”理解成订单也只存一个 UUID。

| 情况 | 本地处理 | 用户可见行为 |
| --- | --- | --- |
| prepare 失败 | 不生成可支付订单，不调用商店购买 | 沿用购买失败反馈 |
| UUID 或购买尝试写入失败 | 不调用商店购买，保留可重试的内部状态 | 不假装已进入支付 |
| 明确未发起支付的失败，或用户明确取消且无已付款/待付款凭据 | 关闭并清理当前未付款尝试；不得删其他订单 | 不强制登录 |
| 商店已打开后超时、断网、App 被杀，无法确认是否扣款 | 保留尝试，通过商店查询和回调补齐结果 | 不按取消清理，也不显示成功 |
| 平台 PENDING / 待付款 | 保留记录，等待转为 PURCHASED | 不当作已付款，不强制登录 |
| 已付款，report 失败或 accepted | 保留 UUID、交易身份、凭据及同一 request_id，继续确认 | 显示既有处理中反馈，不显示购买成功 |
| report completed | 先持久化待绑定任务，再弹成功提示 | 点击 OK 后弹不可关闭登录弹窗 |
| report rejected | 记录明确拒绝，停止该报告的自动确认；保留必要交易依据 | 不显示成功，不产生强制登录循环 |

取消与迟到回调并发时按真实交易更新状态；已付款证据不能被较晚到达的取消结果覆盖。不能设置一个固定超时就删除可能已扣款的记录。

## 3. accepted 的具体含义

两个接口的 accepted 所处阶段不同，必须分别处理。

| 返回结果 | 表示什么 | 下一步 |
| --- | --- | --- |
| guest report completed | 游客购买已验单并完成本次入库处理 | 保存待绑定任务；购买成功弹窗 → OK → 登录 |
| guest report accepted | 服务端已接收并持久化上报，但付款状态或后续处理尚未完成 | 保留订单，沿用 VIP 原有 report 确认/恢复及退避重试；completed 后才进入成功分支 |
| claim completed | 游客归属已绑定，当前同步已完成 | 保存 completed → 刷新 wallet → 完成缓存清理 |
| claim accepted | **游客归属已经绑定到当前账号**，后续同步仍未完成 | 固定本次 UID，保留任务，按 claim 原有退避策略继续确认；不把会员展示提前改成生效 |
| claim rejected | 后续同步明确拒绝；文档规定不会撤销已保存归属 | 停止该任务自动 claim，不伪造 VIP；保留处理记录，不能改绑其他 UID |

“accepted 继续原有确认流程”的意思是：继续处理同一笔订单，使用同一交易身份及幂等键，不再次调起支付、不重复扣款、不删除未完成数据。

没有取得合法 `data.status` 时，HTTP 200、超时或异常都不代表业务完成。真实会员状态以重新获取的 wallet.membership 为准；completed 本身也不能证明一笔已过期的购买仍有有效会员权益。

目前代码对 claim accepted 有一次“把已 completed 的 report 重新入队”的旧处理，用于旧接口的等待上报场景。新 claim 自带验单及补存上报能力，应移除这条旧契约分支；仍未确认的其他交易继续各自的 report 恢复，不能被一并删掉。

## 4. 未登录进入首页的执行流程

入口等待本地存储及登录状态初始化，并在首页首次可展示时触发；不在 Home 每次 build 或切 Tab 时重复执行。协调器覆盖启动、相关购买状态变化及未完成任务恢复，防止并发查询和重复弹窗。

### 4.1 有本地待绑定信息

1. 对每个待绑定 `account_uuid` 调用 `guest/purchase/check`，合并重复 UUID。
2. `has_unbound_order == true`：确认存在服务端已验单且未绑定的订单，记录本次检查结果，触发不可关闭的登录弹窗。
3. `has_unbound_order == false`：本次不据该 UUID 触发登录。**不能直接删除购买凭据，也不能认定一定已绑定。**
4. 网络或业务错误：状态是“未知”，保留数据并在现有恢复调度中重试，不把错误转成 false。建议本次不新增登录拦截，避免断网把没有可认领订单的用户锁住；这也意味着检查服务不可用期间无法保证即时拦截。
5. 只有购买尝试或 report 待确认记录时，继续订单恢复；不能因本地存在 UUID 就强制登录。

check 为 false 的原因包括：UUID 不存在、只 prepare、只有上报事件但尚未建立订阅、或者已经绑定。该接口不是“是否已绑定”的完整状态接口。

已缓存的真实付款记录如果仍未确认，false 后继续 report 补偿；如果本地已有 claim accepted/completed，保留其绑定后同步/清理状态，不能因为 check 为 false 就丢掉剩余任务。下次进入同一登录账号后继续完成。

### 4.2 没有本地待绑定信息

1. 进行一次 VIP 专用的商店订单查询，不触发支付或系统恢复登录提示，不把结果发送进 Gems 购买事件流。
2. Google 查询 SUBS；Apple 读取可恢复的订阅交易。为订阅候选提供可靠的类型识别，不能把普通 Gems 交易当成会员。
3. 从交易取原购买 UUID：Google 的 obfuscatedAccountId，Apple 的 appAccountToken。不能通过新 prepare 生成 UUID 来替代原购买身份。
4. 有已付款订阅候选及有效 UUID 时，先保存可恢复的交易标识和新恢复操作的 request_id，再按 UUID 调用 check。
5. check true：保存待绑定任务，弹强制登录；这次恢复不补弹一遍刚购买成功的弹窗。
6. check false：可能是已经绑定，也可能是付款后从未成功上报。对尚未确认上报状态的有效交易，用原凭据走 guest report 补偿，再 check；不能把 false 直接当成“处理完毕”。这一步依赖第 1.2 节的无缓存套餐恢复能力。
7. 补偿 accepted/临时失败保留恢复任务；completed 后重新 check；明确无法按游客交易接收的结果不触发登录，也不无限提交相同错误请求。为同一交易保存补偿结果和去重状态。
8. 无订单、没有有效 UUID、只有待付款订单时，不凭空创建待绑定任务。查询错误保留未知状态；不能记成“此商店账号从来没买过”。

这条发现链路不应依赖已经打开 VIP 页并加载过商品列表。当前 `MembershipStoreRestorer.query` 在商品 ID 集合为空时直接返回空，不能原样拿来实现“首次首页、无缓存恢复”。需要新增不依赖页面商品加载的会员订阅发现方法，识别后再由服务端验单及映射商品。

平台范围要如实验收：Google 客户端查询主要提供当前仍持有的购买，不保证返回所有过期或退款历史。check 文档又规定过期、退款但未绑定的已入库订单仍可返回 true；有 UUID 时能查到，无缓存且商店不再返回该交易时，不能宣称一定能发现。跨设备须使用原购买对应的商店账号，也不能承诺 Android 与 iOS 之间凭本机商店自动找回。

### 4.3 弹窗和并发约束

- 本次购买仍按成功弹窗 → OK → 不可关闭登录的顺序；首页检查不能抢先覆盖成功弹窗。
- 全局只展示一个登录弹窗，多笔 UUID 进入同一处理队列。
- 检查返回时重新核对 session 和请求代次，忽略退出、切换账号或新一次检查之前的过时结果。
- 用户登录成功后转入 claim；不因后台旧的 check=true 再弹登录。
- 保留现有 Debug 包开关，默认强制；关闭只影响登录拦截，不影响订单存储、检查和绑定。Release 不暴露该配置。

## 5. 登录绑定、重试和清理

1. 登录成功，读取全部未完成的游客任务。
2. 对当前待处理 UUID，取得其真实平台购买凭据，组装最新 claim 请求。原 report 和 claim 对同一笔购买复用 request_id；无原本地记录时，为恢复操作生成一次并持久化。
3. 在发请求前持久化目标 `ownerUid`，防止响应超时后因切换账号而把同一笔订单认领到另一个账号。
4. claim completed：先持久化完成状态，再重新拉 `/api/v1/gem/wallet`，将返回的会员信息交给现有会员展示逻辑。
5. wallet 刷新失败只重试刷新和清理，不重复提交已经 completed 的 claim。清理失败同样保留 completed 标记续做。
6. 同一交易的 claim completed 已包含上报及同步完成语义，应收敛对应的本地 report 状态；其他交易的未完成 report 单独保留。完成清理时删除待绑定游客信息及关联索引，不能提前删掉仍待处理的其他订单。
7. claim accepted 或临时请求失败，保持原来的首次请求 + 最多 5 次额外退避重试：15、30、60、120、240 秒。重复恢复回调不能绕过这一轮的次数限制。
8. 耗尽后保留任务和目标 UID，不无限循环。本轮计数沿用现有登录处理会话边界；后续 App 重启或重新进入同一账号可恢复处理。不能在切换到其他账号后改绑。
9. claim rejected 记录终态并停止自动重试；登录 session 失效先回到登录状态，未取得明确业务完成结果时保留数据。正式实现保持现有有界异常重试策略，不把所有接口都改成五次重试。

claim 后刷 wallet 是刷新现有数据来源；普通 Gems 余额仍读 wallet，会员 Blue Gems 仍读 membership，不合并或改写原 Gems 购买逻辑。

## 6. 本地模型和平台凭据

### 6.1 UUID 替换与历史付款记录

- 新身份模型仅含 `accountUuid`；Map key、任务去重、清理索引和重试 key 从 guestId 改为规范化 UUID。
- 保存商品购买身份，而非页面展示快照；价格/title/benefits 缺失不能阻断恢复。
- 给无缓存发现的交易单独建立恢复记录，允许套餐暂未知，不能伪造一个默认月/年套餐。现有登录恢复记录要求 ownerUid，也不能直接当匿名任务使用。
- 升级时读取已有本地记录内的 account_uuid，迁移关联、交易状态、ownerUid、request_id，写入成功后再删除旧字段。不能直接清空旧存储导致已付款用户丢单。
- 网络序列化、API 模型和 mock 仅保留新契约；迁移旧本地已付款记录不等于继续兼容旧服务端 API。

### 6.2 凭据保存

最新文档要求 Apple claim/report 提交完整 `signed_transaction`，且禁止将 JWS 写日志或持久化。现有 VIP 恢复适配只保留 transactionId、appAccountToken，并没有把 StoreKit 提供的签名数据传到 API 层。

因此需要新增 VIP 专用凭据适配：Apple JWS 在内存中传递；本地仅保存 UUID、交易 ID、原始交易链 ID、商品身份及任务状态，重启或重试时通过 StoreKit 重新获取对应签名交易。无法重新获取时保留任务，不拼造 JWS，也不回退为仅 UUID 认领。Google purchaseToken 按现有安全存储策略保留。

平台交易完成/确认继续按 VIP 既有服务端接管边界处理，不等用户登录后才处理商店确认；待付款交易不能提前当作已购买。游客 claim 失败不触发第二次支付。

新 check 也加入现有 membership 私密请求排除范围；禁止输出 UUID、token、JWS 原始请求体。状态诊断只记录阶段、结果、耗时和脱敏关联标识。

## 7. 实施拆分及文件范围

下面按依赖顺序实施；接口未就绪的恢复路径不能作为已经闭环验收。

| 阶段 | 工作 | 主要文件/模块 | 完成标准 |
| --- | --- | --- | --- |
| A：契约对齐 | 确认 claim 的“只保留 UUID”含义；服务端补无缓存套餐解析；修正文档 claim response 的 rejected schema 分支 | Apifox 共用请求/响应模型 | 两平台请求示例能通过真实服务端校验 |
| B：网络与存储 | 去 guest_id/claim_token；新增严格布尔 check 模型；完整 claim/report 请求；安全记录迁移 | `lib/network/models/membership_purchase.dart`、`membership_claim.dart`、`lib/network/v1/membership_api.dart`、`lib/platform/billing/membership_pending_store.dart`、`membership_guest_claim_record.dart` | 新请求无旧字段，旧已付款数据可恢复 |
| C：购买与绑定 | 分清临时尝试/已付待确认/待绑定；补 JWS；保留成功 OK 顺序；调整 accepted；保留五次重试与完成后 wallet 刷新 | `lib/app/membership/membership_purchase_service.dart`、`membership_guest_claim.dart`、`lib/components/gems/membership_purchase_presentation.dart` | 本次游客购买到绑定完整闭环 |
| D：启动检查 | 新增会员游客恢复协调器；Home ready + session ready 后 check；一次查询去重；防迟到回调 | 新 `lib/app/membership/membership_guest_recovery.dart`、`lib/app/bootstrap/service_registry.dart`、首页生命周期接入、`membership_guest_login_gate.dart` | 有缓存先查服务端，true 才按启动规则拦截 |
| E：无缓存发现 | 会员专用平台凭据 DTO；查询订阅，取原 UUID，补上报和绑定 | `lib/platform/billing/membership_store_restorer.dart`、VIP 平台适配、必要的 StoreKit 订阅类型映射 | Android/iOS 清数据后能恢复平台可查到的未绑定订单 |
| F：同步与验收 | facade/mock/接口文档/隐私排除；focused tests 和两平台真机 | `lib/network/genesis_api.dart`、`local_mock_genesis_transport.dart`、`membership_request_privacy.dart`、`docs/apifox-http-api-contract.md`、相关 test | 满足下方用例，Gems 回归通过 |

现有页面样式、会员卡样式和 Gems 业务行为保持用户既定要求；上述组件文件仅调整必要的状态接入和弹窗时序。

## 8. 验收清单

自动化覆盖：

1. prepare 只返回 UUID 可解析；所有新网络请求不含 guest_id/claim_token；check 缺字段或类型错误不能默认为 false。
2. 购买前写盘失败不拉起平台；用户取消不强制登录；已付款后超时不丢记录；迟到取消不覆盖已付款结果。
3. report accepted 不弹成功、不清理凭据；completed 先持久化，再成功提示；点击 OK 后只弹一个不可关闭登录弹窗。
4. 启动有缓存：check true/false/业务错误分别处理；check false 不删除待确认付款；只有 prepare 缓存不拦截。
5. 无缓存：平台成功空结果、查询失败、PENDING、缺 UUID、多 UUID、重复交易分别覆盖；不依赖先打开 VIP 页。
6. 付款后未 report 即清数据：使用商店凭据补上报，check true 后登录绑定；Google 不猜 basePlan，Apple 不把 JWS 落盘。
7. claim 初次失败后恰好最多额外 5 次；并发 recover 不增加次数；相同交易 request_id 不变。
8. claim accepted 后 check=false 不删除同步任务；不再重排已 completed 的旧 report；不重复支付。
9. claim completed 后 wallet 失败、进程重启、清理失败都能续做；不再次 claim；其他未完成订单不被误删。
10. claim 超时后切账号、同一 UUID 两设备并发、旧 session 回包、多个成功回调不能误绑或重复弹窗；服务端另一 UID 拒绝为最终归属裁决。
11. 旧缓存迁移中断可重试；身份字段删减不会使已有购买因页面展示字段缺失而无法恢复。
12. Debug 开关默认强制、仅 Debug 可见；会员展示与 wallet Gems 独立；既有 Gems 买入/恢复/余额/弹窗回归通过。

实施后按改动执行 `dart format`、相关文件 `flutter analyze`，以及 membership 网络/存储/购买/恢复/claim 重试/弹窗 focused tests；共享 Gems 事件边界用现有回归用例验证。mock 和单测只证明代码行为，不能替代服务端验单和商店真机结果。

真机最低验收：Android 与 iOS 各完成一次游客新购买并登录绑定、一次 report 中断恢复、一次 claim 超时重试、一次保留缓存重启拦截、一次清数据/卸载后的可恢复订单找回、一次已绑定订单不再拦截，并验证未扣款取消流程。发布前服务端同时验证订阅归属唯一、相同用户幂等及另一用户不能重复认领。

## 9. 当前结论

prepare 的 UUID 需要购买前保存，但临时记录不触发强制登录；report accepted 表示购买确认仍未完成，claim accepted 则表示已绑定但同步未完成；启动拦截改为先 check，false 不能直接用于删除交易。

主流程可以按上述阶段实施。完整无缓存恢复的前置条件是 claim 参数含义确认，以及服务端支持从有效凭据推导缺失套餐；只改 guest_id/claim_token 字段和接入 check，还不能宣称卸载重装找回已全部跑通。
