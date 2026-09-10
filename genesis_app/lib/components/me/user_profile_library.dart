import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../app/bootstrap/app_services_scope.dart';
import '../../app/gems/gem_wallet_store.dart';
import '../../app/telemetry/genesis_telemetry.dart';
import '../../components/auth/login_guard.dart';
import '../../components/common/copyable_id_label.dart';
import '../../components/common/genesis_center_toast.dart';
import '../../icons/custom_icon_assets.dart';
import '../../icons/my_flutter_app_icons.dart';
import '../../pages/world/world_page_result.dart';
import '../../routers/app_router.dart';
import '../../ui/genesis_ui.dart';
import '../../ui/tokens/genesis_avatar_radii.dart';
import '../../utils/api_error_message.dart';
import '../../utils/display_name_formatter.dart';
import '../../utils/entity_deleted.dart';
import '../../utils/stat_count_formatter.dart';
import '../gems/gem_assets.dart';
import '../gems/gem_balance_text.dart';
import '../gems/pro_colors.dart';
import '../gems/profile_membership_card.dart';
import 'profile_collection_list.dart';

part 'user_profile_shell.dart';
part 'user_profile_models.dart';
part 'user_profile_origin_collection.dart';
part 'user_profile_world_collection.dart';
part 'user_profile_actions.dart';
