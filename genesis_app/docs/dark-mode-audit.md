# 合并后深色、颜色 Token 与公共组件复查

检查日期：2026-09-10。基线：`main_ui_black` 合并提交 `37af674d`，包含本轮 Private Chat 修正。此文件替换之前基于旧合并提交的检查结论。

当前状态：全局入口已改为 `GenesisTheme.dark()`；开发全页／Sheet和解锁密码用局部 `GenesisLightTheme` 保持浅色。已删除未使用的 createFormDanger 与角色头像 showStar 链路，World 操作按钮／未读红点已引用 redPrimary。此前“尚未切换”条目为历史记录，最新实施见第10节。

范围：`lib/routers` 的命名路由，页面直接 push，Sheet / Dialog / OverlayEntry 入口，公共组件和页面的初始、分页、错误、等待状态。逐项追踪正式调用与条件；以下是代码检查，未做逐页真机截图验收，也没有真实扣款。

## 1. 本轮已落地

- **Private Chat**：页面、Header、输入栏及安全区使用 darkBackground。Header 改用 GenesisBackAppBar（20 / W600、左对齐），输入框复用 ChatComposer，填充 darkFaintFill、正文及光标 darkTextPrimary、Placeholder darkInputPlaceholder。
- 私信继续复用 ChatMessageRow / ChatMessageBubble：对方气泡 darkFaintFill，自己气泡 redPrimary 的 40% 填充，正文一级白；日期和发送失败说明三级白，发送中的圆环二级白。保留头像、消息间距、气泡几何、草稿、发送和未读定位逻辑。
- 私信发送按钮可用态 redPrimary，禁用态 darkFaintFill；这是聊天发送按钮，不套用底部大提交按钮的禁用底色。初始及历史加载使用 GenesisLoadingIndicator。
- 私信的“新消息”浮标使用不透明 darkRaisedBackground、darkFaintFill 细边和一级白，保留点击跳转到新消息的交互。登录守卫继续调用已有深色 Login Sheet。
- 私信命名路由改用 GenesisDarkPageRoute；没有更改根节点的浅色主题，也没有改变 Location Chat 的布局、气泡和颜色配置。共享配置只新增可选的日期／状态样式覆盖能力。
- 会员有效订阅按钮 `Subscripting` 改为 **Subscribed**。正式判断是 `purchaseBlockReason == already_subscribed`；没有改变购买资格和点击处理。

## 2. 用户明确保留的独立界面（不列为待改）

| 界面 / 入口 | 实际情况 | 代码 |
| --- | --- | --- |
| Developer 全页及底部 Sheet | 仍使用浅色默认主题；信息、开关、按钮、HTTP / WebSocket 列表与详情、自定义会员设置表单含浅底黑字。从不同主题打开时也可能出现深浅混合 | `lib/pages/me/developer_page.dart:109`、`:136`；`developer_components.dart`、`developer_network_tab.dart`、`developer_websocket_tab.dart`、`developer_membership_set_form.dart` |
| **正式包的调试解锁密码弹窗** | Settings／未登录 Me 长按入口，非 debug 构建会显示；奶白底 `#FFFCF7`、金色边框、黑字，独立 Dialog，尚未深色化。这是此前漏掉的浮层 | `lib/app/debug_floating_button_unlock.dart:20`、`:70`；入口在 `settings_page.dart:119`、`signed_out_me_view.dart:91` |
| 地图设置浮动面板、图片流参数编辑器 | 经 Developer 开启地图设置按钮后可见。深色地图下有暗色实现，但仍是独立黄灰底／纯白／68% 白；切到 Light 时仍显示浅色面板。地图默认模式已是 Dark，这不是普通页面初始白底 | `lib/components/tilemap/tilemap_library.dart:2422`、`tilemap_settings_panel.dart:121`、`tilemap_image_flow_editor.dart:308` |
| World 内容更新推送 Banner | 已用深色文字 token 和 Blur 14，但底板仍为独立的 **20% 白**，不是 darkOverlayBackground；用户确认这是独立样式，保留，不属于遗漏 | `lib/pages/world/world_update_push_banner.dart:418` |

用户最新确认：World 更新 Banner 为独立设计，地图设置为开发用途，密码解锁与 Developer 界面均不需要修改。上述四项全部从待改范围移除，表格仅记录现状。常规业务页面没有再查到整页硬编码白底；“未发现”只表示当前调用链的静态检查结果，不能代替设备验收。

## 3. 浮层逐类核对

| 浮层类型 / 场景 | 结论 |
| --- | --- |
| 公共操作框：退出、删除、保存离开确认、完成提示、取消关注等 | GenesisActionBox 自带局部深色；40% darkOverlayBackground、Blur 14、浅白描边。浅色调用页也不会让面板回白 |
| 签到、签到成功、任务成功 | 共用深色 ActionBox；奖励说明二级白，普通动作一级白，红色动作 redSecondary，禁用三级白 |
| 会员／Gems 购买处理中、成功；游客购买后的强制登录 | 购买结果走 GemBillingPurchaseDialog → ActionBox；游客登录走现有深色 Login Sheet。复核新增恢复／异常处理调用链没有另建白色结果框 |
| 会员／充值 Sheet，包括会话资格恢复时的等待状态 | PurchaseOptionsSheet、GemPurchaseBottomSheet、PurchaseSessionBuilder 均有深色配置；普通 Sheet 是 raised，不是半透明操作框 |
| Create / Publishing / World Progressing 等待及 Developer Creating 预览 | OriginGenerationWaitOverlay / GenesisGenerationWaitOverlay 的实际调用明确指定 dark；40% 共享浮层色、Blur 14 |
| 登录 Sheet | 自带 GenesisDarkTheme、深色面板与公共关闭按钮 |
| Discuss / Post Detail 发帖回复弹层 | 已深色；独立编辑器布局和 darkFaintSurface 保留。所有正式入口未启用图片添加，附件删除仅保留代码，不列为可见遗漏 |
| Me 修改昵称、Feedback、Report 输入弹窗 | ActionBox 与输入正文已深色；昵称输入仍是下划线式布局，未按标准填充输入框统一，不能称为所有输入完全一致 |
| Notifications 申请详情、Approve / Reject | ActionBox 和自定义详情内容使用三级文字 token |
| Launch → Setup Your Role | 深色 Preset / Custom，公共 Sheet / 关闭／主按钮；Playing 已移除 |
| World Detail / Locations / Events / Status；Worldo Detail | 深色背景、关闭按钮、Handle 已适配；部分骨架仍重复写 fill 色，见 Token 清单 |
| Opening 选择地点、Locations L3 编辑与角色选择 | 入口局部深色；L3 编辑使用 raised，字段填充已深色；角色选择列表的基础背景属于当前明确覆盖值 |
| Location Chat / Worldo 的 @ 提及面板 | 深色列表／文字与关闭操作；局部头像填充仍硬编码 fill token 的同色值 |
| Report 与消息长按菜单 | 保留专项规定的 #666666 和白字，不按浅色遗漏处理 |
| 图片查看器／裁剪页、上传进度 | 黑色媒体背景或遮罩，属于专用样式；原生图片选择器由系统管理 |
| Toast | 统一 showGenesisToast，深色 #424244 是独立 token；不改成操作弹窗的半透明底 |
| World 更新 Banner；Private Chat 新消息浮标 | 前者是用户确认保留的独立 20% 白表面；后者本轮改为暗色浮动入口 |
| Developer 主 Sheet、网络详情／WebSocket 筛选、密码解锁 | 仍有浅色，用户确认保留，不列为待改 |
| 地图设置／渲染加载浮层 | 跟随地图自身 visualMode；默认 dark，加载动画默认 disabled。Light 地图模式和开发可选加载效果单列，不误算成正式列表骨架闪烁 |

## 4. 同色 Token 扫描快照（替换前）

本轮替换前，全 `lib` 精确扫描（包括多行 Color 字面量，排除唯一色值定义文件）找到 **37 处、22 个文件**：20 处品牌红、6 处一级白、3 处二级白、3 处三级白、5 处 fill。没有再查到基础背景／抬升背景／placeholder／redSecondary／redTertiary 的重复精确字面量。

以下是扫描完整清单，包含公共默认和旧代码；不是 37 个页面，也不代表每一处都有当前可见入口。本轮未批量替换。

按当前调用与用户排除项细分：正式调用／共享样式为 **26 处、14 文件**；开发及解锁区域 **8 处、5 文件**（用户要求保留）；另 **3 处、3 文件** 属于没有当前生产入口或被关闭的旧分支：CharactersList、WorldTickEventItem 旧数值变化颜色、OriginDiscussCommentRow 的旧操作区。后者正式 Worldo 预览明确 showActions=false。

| 文件 | 行号 → 应引用 Token |
| --- | --- |
| `lib/app/debug_floating_button_unlock.dart` | 68 → `redPrimary`；111 → `redPrimary` |
| `lib/components/chat/shared/chat_scene_plate_tokens.dart` | 13 → `redPrimary` |
| `lib/components/chat/shared/chat_ui_library.dart` | 198 → `redPrimary`；203 → `darkFaintFill` |
| `lib/components/chat/shared/chat_ui_style_config.dart` | 359 → `redPrimary`；365 → `redPrimary` |
| `lib/components/developer_debug_floating_button.dart` | 167 → `redPrimary` |
| `lib/components/discuss/origin_discuss_comment_row.dart` | 287 → `redPrimary` |
| `lib/components/gems/profile_membership_card.dart` | 113 → `darkFaintFill`；122 → `darkTextSecondary`；140 → `darkTextSecondary`；173 → `darkTextSecondary`；211 → `darkTextPrimary` |
| `lib/components/me/user_profile_shell.dart` | 753 → `darkTextPrimary` |
| `lib/components/origin/characters_list.dart` | 168 → `redPrimary` |
| `lib/components/world_tick_event_item.dart` | 458 → `redPrimary` |
| `lib/features/location_chat_reply/shared/reply_feature_button.dart` | 44 → `darkTextTertiary`；45 → `darkTextPrimary` |
| `lib/pages/chat/location_chat_mentions.dart` | 816 → `darkFaintFill`；1138 → `redPrimary` |
| `lib/pages/chat/location_chat_reply_actions.dart` | 126 → `darkTextPrimary`；127 → `darkTextTertiary`；136 → `darkTextPrimary`；149 → `darkTextPrimary`；150 → `darkTextTertiary` |
| `lib/pages/create/create_form_library.dart` | 40 → `redPrimary` |
| `lib/pages/discuss/discuss_page.dart` | 458 → `darkFaintFill` |
| `lib/pages/me/developer_capture_components.dart` | 64 → `redPrimary`；109 → `redPrimary`；119 → `redPrimary` |
| `lib/pages/me/developer_network_tab.dart` | 463 → `redPrimary` |
| `lib/pages/me/developer_websocket_tab.dart` | 609 → `redPrimary` |
| `lib/pages/origin/origin_world_map_shell.dart` | 277 → `darkFaintFill` |
| `lib/pages/world/world_bottom_sheet.dart` | 159 → `redPrimary` |
| `lib/pages/world/world_header.dart` | 432 → `redPrimary` |
| `lib/ui/components/genesis_character_avatar.dart` | 17 → `redPrimary` |

补充边界：

- `chat_ui_bubbles.dart:145`、`origin_world_role_setup.dart:860` 还有 `Colors.white.withValues(alpha: 0.12)`，用途是淡白填充，可另行评估改用 darkFaintFill；这类浮点不透明度写法没有混进上述精确 Color 字面量计数。
- 聊天旧渲染分支中有从 `textColor` 派生 72% 的写法，需要按实际基础色判断；当前 Scene Plate 的事件正文／Global 等已使用对应 token，不应把其他基色的 72% 自动替成白色。
- 73% narrator、20% 白 Banner、会员金色、地图调色、Report 灰色等不是标准 token 的同色，不能强行替换。
- `CharactersList` 没有生产调用；WorldTickEventItem 的旧浅色分支当前调用选择 `useChatEventStyle: true`。这些代码中即使存在同色字面量，也不等于用户正在看到浅色页面。

## 5. 公共组件与样式复用缺口

| 位置 | 现状 / 应复用 |
| --- | --- |
| World Events 分页圆环 | `world_sections_tick_cards.dart:439` 自建 CircularProgressIndicator，已经是二级白，但应复用 GenesisLoadingIndicator |
| Location Chat 历史加载 | `location_chat_scroll_coordinator.dart:1118` 自建圆环；可复用 GenesisLoadingIndicator 并保留其 ChatUiStyleConfig 覆盖与尺寸 |
| Discuss 初次加载 | `discuss_page_comment_list.dart:41` 自建圆环，通过 DiscussDarkTheme 得到正确颜色；仍未复用 GenesisLoadingIndicator |
| Worldo 讨论预览初次加载 | `origin_discuss_list_view.dart:75` 仍为原生圆环且没有显式深色颜色；`origin_world_sections.dart:155` 明确在 isInitialLoading 时显示列表，所以初始加载分支可见。应改为共享加载组件并确认调用主题 |
| Me 昵称输入 | `me_page_nickname.dart:75` 仍是独立下划线输入样式；Feedback / Report 已用标准填充，昵称未拉齐 |
| Edit Message 光标 | `chat_ui_message_editor.dart:90` 从正文 style.color 取值；narrator 使用73%白，和输入光标一级白的规范不一致。应只改编辑光标，不改正文及正常聊天 |
| 页面错误重试操作 | Home、Worldo、World、Edit、Search、Me、Profile、Follows 多处仍直接用 FilledButton。可评估提取共享错误态／Retry，现有尺寸和禁用语义与底部大提交按钮不同，不能直接算作同款大按钮遗漏 |

公共 Header、普通深色面板关闭、创建／编辑删除、主提交按钮、所有下拉刷新已经有统一入口。ChatComposer 的发送控制、关注请求按钮、系统登录厂商按钮、裁剪工具、胶囊移除按钮有独立行为，不因内部仍含 FilledButton／spinner／× 就强行合并。

### 本次复核撤回的可见遗漏

- Discuss 图片添加：`DiscussPostInput` 和 `showDiscussPostComposer` 默认 `showImagePickerButton=false`，全 lib 没有正式调用传 true；图片列表初始为空，只能从图片选择回调添加。`discuss_composer_panel.dart:87` 要 hasImages 才渲染附件条。所以 `discuss_image_strip.dart` 的删除 × 是保留代码，当前用户流程不可见。
- Create 图片占位：`create_upload_preview.dart:126`、`:154` 两个调用均传 `showSpinner:false`，其内部的自建圆环不是当前可见遗漏。
- 昵称输入已有深色文字和光标；“下划线”描述的是输入框形状，不能把它表述成白底遗漏。Edit Message 光标则是颜色继承问题：正文73%白带到了光标，而标准输入光标应是95%白；不涉及气泡边框或正文需要变色。

## 6. 保留的旧分支、路由与验证边界

- 根节点仍使用 GenesisTheme.light()，按此前要求保留；尚未适配的开发页不会被本轮意外变色。
- 普通业务深色命名路由已使用 GenesisDarkPageRoute；World / Worldo 使用专用地图路由。Me 和 Create 的图片裁剪仍是普通 MaterialPageRoute，裁剪内容是黑底；转场是否需要专用黑色路由应在设备验证，不归为“裁剪页未改深色”。
- `confirmCreateFormDelete` 的 AlertDialog 没有当前调用；WorldTick1WaitDialog 需要 waitForTick1=true，当前生产入口未传 true；旧 LegacyWorldMap 白色 pointsList 分支当前入口固定 pointMode=false。不能把这些残留当成正在使用的白色弹窗／页面。
- OriginDiscussRepliesList 的浅色回复预览仍存在，但正式 Worldo 预览明确 showReplies=false，Discuss 正式页用另一个已深色的 DiscussPageCommentList；旧预览不是当前 Discuss 缩进回复底色。

## 7. 本轮验证

- `flutter test --no-pub test/components/chat_ui_test.dart test/routers/app_router_test.dart`：**111 项通过**，覆盖共享聊天渲染与路由；包含现有 Location Chat 气泡相关测试。
- `flutter test --no-pub test/widget_test.dart --plain-name 'private chat stays dark inside a light app theme'`：**1 项通过**；验证浅色根主题中私信页面背景、局部深色、公共 Header、输入正文／光标／placeholder。
- `flutter test test/components/pro_subscription_content_test.dart`：**20 项通过**，包含 Subscribed 文案和购买交互不变。
- `flutter test --no-pub test/widget_test.dart --name '^chat page'`：旧的13项私信集成测试失败，涉及消息同步断言和网络 deadline 的待清理计时器。在独立 worktree 的未修改 `37af674d` 上运行同一命令，**同样13项失败**；本轮未扩大修改消息服务或旧测试异步设施。不能据此声称私信端到端测试已全部通过。
- 修改文件已执行 Dart 格式化与静态检查，最终结果见本次回复。未进行逐页真机验收。

## 8. 全局深色的后续方案（尚未实施）

当前根节点 `lib/app/genesis_app.dart:32` 仍是 `GenesisTheme.light()`，且 GenesisTheme 尚无 dark() 工厂。现在可以将正式应用默认改为深色，以覆盖漏配主题的 Scaffold、Material 和路由默认表面。

实现需同时提供 ThemeData 与 GenesisUiTheme 的深色默认：基础面用 darkBackground，面板面用 darkRaisedBackground，三级文字／placeholder／光标／Tab／按钮禁用态／加载色引用当前 token。根 builder 的 DefaultTextStyle 和状态栏图标也要同步，不能只修改 ThemeMode 或 brightness。

Developer 全页与 Sheet、解锁密码等用户要求保持原貌的开发入口需保留局部 GenesisTheme.light()，不改变其设计。地图设置和 World 更新 Banner 继续保持自身配置。全局深色只能兜底继承主题的部分，无法覆盖硬编码白底、旧色值或不复用组件的问题。

本次仅修正检查结论并说明方案，未切换全局主题、未修改上述排除区域。

## 9. 用户确认后的 Token 替换与用途复核

已落实19处精确同色替换（8个文件），不改变颜色、透明度或几何：聊天共享配置5处、Location Chat 回复／提及9处、Me会员卡／Gems文字5处，均改为对应 GenesisColors token。开发区域、昵称输入与全局 Theme 未修改。

待解释项目的核实结果：

- Me会员卡剩余的 fill 是 `Expired` 小标签底色（12%白），不是会员大卡片的底色；本轮按用户要求只替换一级／二级白文字。
- `createFormDanger` 是 #FF2442 的旧名称，全 lib 只有定义、没有调用。不是某个正在显示的“危险状态”，从可见遗漏中排除。
- Discuss / Worldo 骨架有专项静态设计规范；公共 `GenesisListLoadingSkeleton` / `GenesisListLoadingBone` 已存在，但这两处仍是页面私有 `_DiscussSkeletonBone` / `_OriginLoadingBone`，不是都已复用一个控件。它们使用的12%白与fill同色，不意味着要改成输入框样式；本轮保持其实现。
- `world_header.dart` 的品牌红属于 `world-header-action-button`：根据关系状态显示 Tick now、Launch、Request 等。`world_bottom_sheet.dart` 的品牌红是入口右上角7px未读红点，不是整个Sheet底色。
- `GenesisCharacterAvatar.showStar` 默认false。地图路径虽然转发 UserAvatar.showStar，但生产 UserAvatar 构造没有开启此标记，其他页面也未传true。因此旧星标默认色不应列为当前可见遗漏，本轮不恢复星标、不改该组件。
- 昵称下划线输入用户确认保留，不列为待统一；全局入口仍是 GenesisTheme.light()，尚未切换。

精确字面量剩余18处：开发／解锁8处；旧或不生效的定义／分支5处（包含 createFormDanger 与角色星标）；本轮仅核实用途、暂未替换的5处（Expired fill、两处骨架fill、World操作按钮与未读红点）。第4节37处为替换前快照，不是当前剩余计数。

本次Token迁移验证：8个修改文件格式化、相关库文件dart analyze、git diff --check通过。运行 `flutter test --no-pub test/components/profile_membership_card_test.dart test/pages/chat/location_chat_reply_actions_test.dart test/components/chat_ui_test.dart`：109项通过、1项失败。失败为未修改的购买Sheet关闭按钮几何断言：测试仍期待24px，公共深色关闭按钮现为28px。本次没有调整购买Sheet或关闭按钮布局，也没有修改该测试。

## 10. 全局深色与废弃星标清理已落地

- 根 MaterialApp 使用 GenesisTheme.dark()；Root DefaultTextStyle 继承深色 bodyMedium，状态栏默认浅色图标。全局 ThemeData 和现有 GenesisDarkTheme 共用 GenesisTheme.asDark，覆盖基础／抬升表面、三级文字、Placeholder、光标、Tab、禁用按钮与加载圆环。已有输入外层填充不重复叠加。
- DeveloperPage / DeveloperPageSheet 与正式包调试密码弹窗用 GenesisLightTheme 隔离，保持原设计；开发详情在面板内展开，筛选Sheet继承局部主题。地图设置、昵称输入及 World 更新 Banner 不改设计。
- 删除 createFormDanger 无调用定义。
- World 主操作仍为 GenesisPrimaryButton，所有既有尺寸分支保持原值：常规140×35、紧凑92×34。主操作底色和入口7px未读红点均用 redPrimary。所谓“两个”颜色位置中，只有前者是操作按钮，后者是状态标记。
- 删除 GenesisCharacterAvatar 的 showStar / starSize / starColor 及绘制代码、UserAvatar.showStar、地图转发／缓存签名／旧灰色标记边框分支，以及按废弃标记拆组的列表逻辑。保留玩家角色红边框和原来的新旧内容排序。聊天专用 ChatAiBadge 仍在世界聊天加载分支被调用，属于独立组件，本轮不删除其图标字体或加载展示。
- 相应测试改为确认头像没有旧星标，并保留阴影、红边框、头像布局和地点层级断言。废弃标记导致的两组角色列表测试现在断言单组，符合生产数据从未开启该标记的现状。
- AGENTS.md 已更新全局深色默认、开发界面例外和头像无星标规则。

验证：

- 文件级 dart analyze（主题、根App、Developer、World／地图／头像、创建表单与修改测试）无问题；dart format 和 git diff --check 通过。
- 初轮主题／头像／地图／开发Sheet／World Header测试后，修正新测试的 ThemeData 闭包比较方式和移除星标后的旧分组断言。复跑主题、开发Sheet与地图测试：67通过，5项地图失败。
- 同一未修改37af674d独立worktree运行 world_map_test：60通过，同样5项失败（中文标签字号、地图背景／预加载、进入下级地图及三级地点）。未扩大修改这些旧地图行为。
- GenesisAvatar、Tilemap头像、World地图数据、World角色列表、World Header相关初轮测试均通过；全局默认改变未调整主操作按钮尺寸。
- 扩展公共UI／聊天／强制升级测试：134通过，2项旧公共UI断言失败；初次命令另包含一个写错名称、不存在的测试路径，已改跑实际的 genesis_action_box_dark_test，2项通过。
- 未修改37af674d复跑同两项公共UI断言，同样失败（旧Header颜色继承、ActionBox红色层级），不是本轮引入。
- 根App实测 `flutter test --no-pub test/widget_test.dart --plain-name 'app text uses Inter across root overlay and main pages'` 通过；新增断言验证真正MaterialApp的默认深色和根Overlay的一级白字，并切换Inbox／Me／Worldo／Create验证字体。
- 未进行真机逐页截图验收。本轮不自动commit或push。
