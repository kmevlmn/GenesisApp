import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../routers/app_router.dart';
import '../ui/genesis_ui.dart';
import 'search_bar.dart';

const double kGenesisTopBarHeight = 50;

class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.pageName,
    this.horizontalPadding = 16,
    this.topPadding = 0,
    this.showSearchBar = true,
    this.trailing,
  });

  final String pageName;
  final double horizontalPadding;
  final double topPadding;
  final bool showSearchBar;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return GenesisTopSafeArea(
      backgroundColor: Colors.white,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          horizontalPadding,
          topPadding,
          horizontalPadding,
          0,
        ),
        child: Column(
          children: [
            SizedBox(
              height: kGenesisTopBarHeight,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Center(child: GenesisPageTitle(text: pageName)),
                  if (trailing != null)
                    Align(alignment: Alignment.centerRight, child: trailing),
                ],
              ),
            ),
            if (showSearchBar) ...[
              SearchBarPlaceholder(
                onTap: () {
                  Navigator.of(context).pushNamed(RouteNames.search);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class PageTitleText extends StatelessWidget {
  const PageTitleText({super.key, required this.pageName, this.style});

  final String pageName;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final overrideStyle = style;
    if (overrideStyle == null) return GenesisPageTitle(text: pageName);
    return Text(
      pageName,
      style: GenesisUiTheme.of(context).pageTitleStyle.merge(overrideStyle),
    );
  }
}

class GenesisBackAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GenesisBackAppBar({
    super.key,
    required this.pageName,
    this.onBack,
    this.actions,
    this.titleKey,
    this.onTitleTap,
    this.titleStyle,
    this.systemOverlayStyle,
    this.backgroundColor = Colors.white,
    this.foregroundColor = Colors.black,
  });

  final Color backgroundColor;
  final Color foregroundColor;
  final String pageName;
  final VoidCallback? onBack;
  final List<Widget>? actions;
  final Key? titleKey;
  final VoidCallback? onTitleTap;
  final TextStyle? titleStyle;
  final SystemUiOverlayStyle? systemOverlayStyle;

  @override
  Size get preferredSize => const Size.fromHeight(kGenesisTopBarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: kGenesisTopBarHeight,
      backgroundColor: backgroundColor,
      elevation: 0,
      scrolledUnderElevation: 0,
      systemOverlayStyle: systemOverlayStyle,
      centerTitle: true,
      leadingWidth: 37,
      leading: Padding(
        padding: const EdgeInsets.only(left: 20),
        child: Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            constraints: const BoxConstraints.tightFor(width: 17, height: 17),
            padding: EdgeInsets.zero,
            icon: Icon(
              Icons.arrow_back_ios_new,
              color: foregroundColor,
              size: 17,
            ),
            onPressed: onBack ?? () => Navigator.of(context).maybePop(),
          ),
        ),
      ),
      title: GestureDetector(
        key: titleKey,
        behavior: HitTestBehavior.translucent,
        onTap: onTitleTap,
        child: PageTitleText(pageName: pageName, style: titleStyle),
      ),
      actions: actions,
    );
  }
}
