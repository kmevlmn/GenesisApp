# 合并后深色与公共组件检查

检查日期：2026-09-10。基于 `main_ui_black` 合并提交 `354cf8ef` 及本轮修正。范围为生产 lib 路由、页面、Sheet / Dialog、加载与错误分支、公共组件和颜色调用。此为代码与调用链检查，未逐页运行截图或复现转场闪白。

## 仍为浅色或混合样式的页面

| 页面 / 入口 | 尚未适配内容 | 位置 |
| --- | --- | --- |
| 私信 Chat | #EDEDED 页面与自定义 Header，浅色 Composer、白色输入及对方气泡，深色正文；初始与历史加载也依赖默认主题 | `lib/pages/chat/chat_page.dart`、`lib/components/chat/shared/chat_ui_library.dart` 的 kPrivateChatStyle |
| Developer 页面 / Sheet | Basic、Switch、Button、HTTP、WebSocket、详情及筛选仍有浅色背景 / 深色文字；新增会员手工设置表单同样依赖浅色主题 | `lib/pages/me/developer_page.dart`、`developer_components.dart`、`developer_membership_set_form.dart`、`developer_network_tab.dart`、`developer_websocket_tab.dart` |

Subscription / Buy Gems、会员／充值 Sheet 和 Gem Records 已在后续确认方案后统一为深色。

## 公共组件调用缺口

| 位置 | 现状 | 对应公共实现 / 处理建议 |
| --- | --- | --- |
| Edit Message 输入光标 | `_ChatMessageTextEditor` 使用 widget.style.color，narrator 正文字色可能为 73% 白 | 深色光标按规范直接用 darkTextPrimary；正文样式无需跟着改 |

当前 Header、普通面板关闭按钮、公共删除按钮、操作弹窗均已有公共实现。Edit Message 删除按钮已在合并时迁移 GenesisDeleteButton。Location Chat / 地图专用 Header、图片裁剪和胶囊移除按钮不应强行换成标准 Header / Sheet 关闭按钮。

## 同色值尚未引用标准 token 的实际调用

| 范围 | 具体调用 | 应引用 |
| --- | --- | --- |
| 新增回复操作按钮 | `lib/features/location_chat_reply/shared/reply_feature_button.dart:44` 的 45% / 95% 白 | darkTextTertiary / darkTextPrimary |
| Location Chat 操作区 | `lib/pages/chat/location_chat_reply_actions.dart:126` 等图标与文字的 45% / 95% 白 | darkTextTertiary / darkTextPrimary |
| Me 会员卡 | `lib/components/gems/profile_membership_card.dart:122`、`:140`、`:173`、`:211` 的 72% / 95% 白 | darkTextSecondary / darkTextPrimary |
| Me Gems 卡文字 | `lib/components/me/user_profile_shell.dart:753` 的 95% 白 | darkTextPrimary |
| Create 表单危险色别名 | `lib/pages/create/create_form_library.dart:40` 重复定义 #FF2442 | createFormDanger 映射 redPrimary |
| World header / tabs | `lib/pages/world/world_header.dart:432`、`world_bottom_sheet.dart:159` 的品牌红 | redPrimary |
| 聊天角色边框与强调 | `chat_scene_plate_tokens.dart:13`、`chat_ui_style_config.dart:359`、`chat_ui_library.dart:175`、`location_chat_mentions.dart:1138` 等品牌红 | redPrimary |
| Discuss 已赞强调 | `lib/components/discuss/origin_discuss_comment_row.dart:287` 的品牌红 | redPrimary |
| Developer 图标与状态 | `developer_capture_components.dart`、`developer_network_tab.dart`、`developer_websocket_tab.dart`、`developer_debug_floating_button.dart` 的 #FF2442 | redPrimary |

会员金色 / 酒红配色已集中在 `pro_colors.dart`，与五个标准深色 token 不同，不应强行替换。73%、60% 等有意不同的聊天文字透明度同样不归并到 72% / 45%。本轮只列出上述迁移点，没有批量替换。

## 路由和默认主题

- 根节点仍是 `GenesisTheme.light()`，按用户要求保留，以便分辨尚未迁移页面。
- Edit Message（含参数无效的 PageNotFound 分支）、Notifications / New followers / Comments / Profile / Follows 及 Home / Worldo / Inbox / Me / Shell 别名已使用 GenesisDarkPageRoute，明确 Android 转场的基础深色背景。Inbox 内直接打开通知分类的入口同步迁移；保留原有通知刷新回调。
- 本轮未进行设备转场截图验收；私信的普通路由不在此次迁移范围；购买主页面 gemWallet 和 gemRecords 路由均已使用 GenesisDarkPageRoute。
- 地图与 Location Chat 的专用路由及返回几何应单独保留，不能无差别替换。

## 本轮已修正

1. Edit Message narrator 编辑态添加 1px、6% 白边框，与 Create Opening 复用 `chatNarratorEditorBorder`。只有存在对应消息编辑控制器时添加，普通聊天 narrator 保持无边框。
2. 签到弹窗合并时完整接入远端，留下副标题和第二操作黑字。本轮奖励副标题改为 darkTextSecondary，Check in 用 darkTextPrimary，Get 100 / Claim 用 redSecondary，已领取用 darkTextTertiary。共用奖励组件的成功弹窗同步修正；订阅和签到行为保留。
3. 新增编辑态有边框 / 普通聊天无边框验证，并保留签到订阅导航、签到成功与禁用态验证。
4. Edit Message 移除地点背景图片，页面改为 darkBackground 并包裹 GenesisDarkTheme。Save 继续复用 GenesisPrimaryButton，与 Model 对齐为 64×32、14px / W600、品牌红底与一级白字、右侧留白 16；禁用态使用公共深色 token。状态说明引用 darkTextSecondary。
5. Home / Worldo 加载更多、Discuss / Post Detail 分页和回复加载改用 GenesisLoadingIndicator，保留原来的尺寸与分页逻辑。

### 本轮验证

- 已执行 `dart format` 与 `git diff --check`，通过。
- 已执行文件级 `dart analyze`：Location Chat（包含 Edit Message part）、路由、Home、Worldo、Discuss、Post Detail、Inbox 与修改的编辑 / 路由测试，均无问题。
- `flutter test --no-pub test/pages/chat/location_chat_edit_page_test.dart test/routers/app_router_test.dart test/components/discuss_page_test.dart test/components/origin_discuss_list_test.dart`：60 项通过、6 项失败。前三个文件的 39 项均通过；6 项失败全部在未修改的 origin_discuss_list_test，涉及网络计时器残留与进度数字断言。Discuss 分页测试改用末尾附近的真实拖动，匹配现有分页手势条件。
- `flutter test --no-pub test/widget_test.dart --plain-name 'messages action button navigates to list page'`：通知页面内容断言通过，但测试结束时 GenesisTelemetry._safeAppVersion 的计时器残留导致用例失败。未扩大修改遥测或网络逻辑。

## 已完成或不应误报

- Home、Worldo、Me、Profile、Follows、Inbox 通知、Search、Discuss、Post Detail、Settings、Create / Edit 各步骤、Model、角色选择和 World 四个 Sheet 已有深色实现。
- Model、强制升级、PageNotFound 及公共 Header 深色默认已完成；Gem Records 和购买主页面均已使用公共 Header 的深色默认值。
- Creating / Publishing / Progressing 已复用 40% darkOverlayBackground 和二级 Blur 14；Developer Creating 已与正式流程对齐，不再有滚动字幕。
- 支付处理中 / 成功、会员购买结果复用深色公共操作弹窗；购买商品页与 Sheet 现已同步完成深色适配。
- 旧 WorldTick1WaitDialog 只有残留条件入口，需要 waitForTick1=true；生产业务没有传 true，不列为当前实际可见遗漏。Worldo Launch Preview 已删除。
- Report / 消息菜单 #666666、媒体工具黑底及会员配色为专用设计；无生产调用的旧浅色组件不列入页面遗漏。

## 购买页面与 Sheet 深色统一

- GemWalletPage 使用 GenesisDarkTheme、darkBackground 和公共深色 Header；Records 图标一级白。PurchaseOptionsSheet 与独立 Gems Sheet 使用公共深色面板、darkRaisedBackground 和公共圆底关闭按钮。
- WalletPurchaseTabs、ProSubscriptionContent、GemBalancePanel、GemProductGrid 继续由两个入口共用；普通卡片使用 darkCardBackground（抬升色 80%）和 darkCardBorder（6% 白描边），正文按一级／二级／三级白 token 分层。
- 会员套餐选中底色使用 proGold 的 12% 不透明度，描边引用 proGold；金色购买按钮、铜色权益与优惠标识保留。会员专属颜色继续集中在 pro_colors.dart。
- Gems 价格操作复用 GenesisPrimaryButton，保留 24px 高度和胶囊圆角，使用 redPrimary 底色与描边、darkTextPrimary 文字和加载圆环；售罄使用 darkTextTertiary 和 darkFaintFill 描边。购买中不改变底色，保留原有防重复点击和交易流程。
- 新增购买模块共享 gem_purchase_state.dart：GemPurchaseLoading、GemProductGridSkeleton、GemPurchaseState。页面与 Sheet 共用商品骨架、空态及重试；刷新与圆环复用 GenesisRefreshIndicator / GenesisLoadingIndicator。骨架静止，无闪动。
- PurchaseSessionBuilder 的登录状态等待阶段同样深色：页面使用 darkBackground，Sheet 显式传 darkRaisedBackground，避免正文显示前白底。
- 验证：已执行购买页面、商品卡、会员内容、购买 Sheet、余额提示、登录状态等待和路由测试；更新旧浅色断言并验证浅色根主题下的局部深色、Tab 状态保留、购买拦截与任务行为。未进行真实扣款或设备截图验收。

## Records 与 Wallet 签到任务后续修正

- Records 使用 GenesisDarkTheme、darkBackground、公共深色 Header 和 GenesisDarkPageRoute；Tab 选中一级白、未选中二级白，品牌红下划线。无底色列表左右 16px，标题与支出一级白，收入 redSecondary，时间／World ID 三级白；World ID 复制保留。
- Records 刷新与加载统一公共组件，移除品牌红圆环覆盖；空态、错误提示三级白，Retry 二级白。
- Wallet 的 daily_checkin 任务先打开 showDailyCheckInDialog，再根据确认结果执行原有签到／领取流程；关闭或转到订阅不会自动领取。弹窗打开期间阻止重复触发，已领取任务保持禁用。成功后继续刷新任务与余额。
- Follow 任务 Discord 图标改为 14×14，保留官方透明底白色图形。
- 验证：`flutter test --no-pub test/pages/gems/gem_wallet_page_test.dart test/pages/gems/gem_records_page_test.dart test/components/daily_check_in_dialog_test.dart test/routers/app_router_test.dart`，60 项通过；格式和文件级静态检查通过。

- 文字 Tab 核查：Records 与 Subscription / Buy Gems 未选中态已纠正为 darkTextSecondary，与 Worldo、Search、Me／Profile、Follows、@ 提及一致；GenesisDarkTheme 同步提供一级白选中、二级白未选中、品牌红下划线的公共默认值。
