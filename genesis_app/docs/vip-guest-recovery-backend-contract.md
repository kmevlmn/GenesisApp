# Android / iOS 重装后的游客认领

2026-09-10 按用户最新要求：Android / iOS 登录 report、游客 report、claim 均不发送 plan_code、request_id，包含新购买、已有套餐缓存、重装恢复和失败重试。最新 Apifox 已允许省略套餐，但仍要求 request_id；本次客户端按明确要求先完成删除，后端兼容情况仍需联调确认。

## 客户端行为

未登录且本地没有游客缓存时，只读查询 Google SUBS / Apple 有效订阅取得原 UUID 和购买证明。按 UUID 调用 check，true 且证明唯一时保存独立游客认领状态；登录后直接 claim，不创建旧订单或 report 重试记录。

- Android：使用原 obfuscatedAccountId、store_product_id、purchase_token。claim 不传 plan_code、request_id，不根据当前目录或页面选项判断月/年，由后端验单确定。
- iOS：使用原 appAccountToken、商品 ID、transaction_id 和对应 signed_transaction。claim 不传 plan_code、request_id，也不请求商品目录解析套餐；JWS 只留内存，重启后按原交易 ID、商品及 UUID 重新获取。没有取得对应 JWS 时保留凭据重试。
- checkout 使用商品目录的套餐及平台商品标识选择购买方案；MembershipPurchaseRequest 与 MembershipClaimRequest 的 HTTP body 均不含 plan_code、request_id。两种请求模型已删除 requestId 字段及校验，本地缓存编号不传入请求。原有缓存中的 claim 套餐字段读取时忽略，再次保存时移除，原证明和本地记录编号保留。
- 首次 claim 前保存 owner_uid 和购买证明；失败/accepted 使用相同证明，按 15/30/60/120/240 秒最多额外重试 5 次。本地编号仅用于队列、回调和清理；另一个账号不接管认领。
- completed 后刷新当前账号 wallet、清理购买证明，保留已绑定 UUID 供以后未登录时 check。清理失败仅重试清理，不重新 claim。
- check=false 不创建认领记录，也不删除已有 UUID。相同 UUID 返回多份不同证明时，不随意选择其中一条覆盖会员。

## 验证边界

当前在线 schema 仍要求 request_id，尚不能确认服务器接受本次无编号请求。后端需要同步参数校验并依据原购买证明处理重复上报、重复认领和续费；本次删除不代表服务器幂等记录或真实订单已修复。

客户端测试覆盖 两端已知月/年套餐及无缓存恢复均不含 plan_code 的 HTTP body、iOS 完整证明、两端重装/重启后 claim、失败与 accepted 退避、账号切换和清理。商店真实查询、后端官方验单及最终会员到账仍需 Android / iOS 真机联调确认。
