import 'package:flutter/material.dart';

import '../ui/genesis_ui.dart';

const double kSearchBarTopPadding = 8;

class SearchBarPlaceholder extends GenesisSearchField {
  const SearchBarPlaceholder({
    super.key,
    super.hintText,
    super.onTap,
    super.controller,
    super.focusNode,
    super.onChanged,
    super.onClear,
    super.textInputAction,
    super.readOnly,
    super.autofocus,
    super.height = 36,
    super.padding,
    super.backgroundColor = const Color(0xFFFAFAFA),
    super.borderColor = const Color(0xFFEBEBEB),
    super.borderRadius = const BorderRadius.all(Radius.circular(12)),
    super.iconColor,
    super.icon,
    super.iconSize,
    super.iconAsset,
    super.hintStyle,
    super.textStyle,
  });
}
