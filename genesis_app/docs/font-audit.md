# 字体检查记录

检查日期：2026-09-10。范围为 `lib/` 下 567 个 Dart 文件、字体资源及 `pubspec.yaml` 注册，并检查原生端是否另有应用文字字体设置。

## 结论与边界

应用拉丁字母和数字统一使用 `GenesisTypography.fontFamily`（Inter）。中文等 Inter 不含的字形继续使用公共 fallback；图标字体、图片内文字、WebView 网页内容及操作系统原生界面不转换为 Inter。

普通 `Text` 没写 `fontFamily` 不代表字体遗漏：它会合并 `DefaultTextStyle`。此前 Inbox 未读角标同样继承全局字体，其分平台位移问题不能作为漏换字体的证据。

本次发现并修正了绕过继承的文字与测量代码。代码扫描未发现剩余的应用文字字体覆盖；这不等同于已在所有真机、所有业务状态下逐屏验证字形。

## 检查与修正

| 路径 | 检查结果 / 处理 |
| --- | --- |
| 全局主题、深色主题、CreateFormTheme | `GenesisTheme` 已注册 Inter；局部主题保留字体继承，不需给全部普通 Text 重复加字体 |
| App builder / 根 Overlay | 增加公共 DefaultTextStyle，覆盖页面 Material 之外的装饰与浮层 |
| 4 处原始 RichText | Create 说明已正确；补齐 Launch 成功标题、Create/Publish 成功标题、World 玩家加入提示的根 TextSpan 字体 |
| WorldBottomTags | 替换式 DefaultTextStyle 显式使用公共字体，防止切断继承 |
| ButtonStyle.textStyle 覆盖 | 实际渲染测试发现公共主按钮字体为空；补齐公共主次按钮、Memory Model 操作、Discuss 发送、调试解锁 OK。自定义 textStyle 会替换主题样式，不能按普通 Text 的合并逻辑判断 |
| 13 处 TextPainter | 逐一追踪输入样式；修正地图雾效曲线的两处百分比、Gems 商品标签、Memory Model 入口、Locations 角色标签测量、搜索摘要测量、公共浮动菜单测量；地图气泡的默认样式也补齐字体 |
| 搜索/个人主页 Tab 数字、两套地图地点标签测量 | 已使用继承后或显式指定的字体，保留 |
| 6 处 inherit:false 样式 | 地图标签、Toast、New 标签、公共数字角标均明确指定 Inter 和 fallback |
| 3 处 DefaultTextStyle.merge | 公共操作弹窗保留父级字体，未发现覆盖 |
| 开发页抓包日志 | 移除独立 monospace，改用公共 Inter 和 fallback |
| 字体资源 | InterVariable.ttf 为 Regular、InterVariable-Italic.ttf 为 Italic，均为可变字体；pubspec 中 family 为 Inter，斜体已注册 |

浮动菜单、商品标签、Memory Model 入口和搜索摘要的测量与实际显示共用字体，避免用系统默认字体估宽、用 Inter 绘制时产生截断差异。

## 验证

新增 `test/support/font_expectations.dart`，检查实际 RichText 的根样式和子 TextSpan 合并后的字体，明确区分图标字体。回归覆盖主页面与根 Overlay、双平台 World 标签和加入提示、Launch/Create/Publish 成功标题以及浮动菜单。

执行命令（Flutter 工程目录）：

```sh
dart format <本次修改的 Dart 文件>
dart analyze <本次修改的入口文件及字体测试>
flutter analyze --no-pub
flutter test --no-pub test/pages/origin/origin_launch_coordinator_test.dart test/pages/origin_pending_submission_coordinator_test.dart test/components/genesis_report_actions_test.dart test/components/gem_purchase_catalog_test.dart test/components/world_event_count_badge_test.dart
flutter test --no-pub test/ui/genesis_font_inheritance_test.dart test/pages/search/search_page_test.dart
flutter test --no-pub test/widget_test.dart --plain-name 'app text uses Inter across root overlay and main pages'
flutter test --no-pub test/ui/genesis_font_inheritance_test.dart test/pages/gems/memory_model_page_test.dart test/components/discuss_post_input_test.dart
```

定向静态检查通过。全工程静态检查仍有现存问题，包括 `test/pages/origin/origin_world_page_test.dart` 引用不存在的 `originWorldDetailSheetAccentSoftColor`，以及未使用参数、弃用接口等警告；未为字体检查改动这些无关项。

最终上述回归测试均通过，合计 87 个不同用例（World 字体用例在两组命令中重复执行）。主页面测试实际进入 Home、Inbox、Me、Worldo、Create，并验证无 Material 包裹的根 Overlay 文字；双平台用例验证按钮启用/禁用态、World 标签和加入提示。验证检查字体配置和继承，不代替全页面真机逐屏视觉验收。
