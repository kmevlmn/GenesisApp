// ignore_for_file: use_key_in_widget_constructors

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../ui/tokens/genesis_colors.dart';
import 'package:flutter/services.dart';

import '../../app/debug/world_new_content_debug_settings.dart';
import '../../components/ai_content_disclaimer.dart';
import '../../components/chat/shared/chat_scene_plate_tokens.dart';
import '../../components/common/copyable_id_label.dart';
import '../../components/common/genesis_center_toast.dart';
import '../../components/common/genesis_image_viewer_overlay.dart';
import '../../components/common/genesis_report_actions.dart';
import '../../components/world_tick_event_item.dart';
import '../../components/world_new_badge.dart';
import '../../network/models/world.dart';
import '../../network/json_utils.dart';
import '../../routers/app_router.dart';
import '../../ui/components/genesis_character_avatar.dart';
import '../../ui/components/genesis_primary_button.dart';
import '../../ui/components/genesis_static_network_image.dart';
import '../../ui/tokens/genesis_image_radii.dart';
import '../../utils/entity_deleted.dart';
import '../../utils/genesis_image_resource.dart';
import '../../utils/genesis_timestamp_formatter.dart';
import 'world_constants.dart';
import 'world_header.dart';
import 'world_models.dart';
import 'world_value_helpers.dart';

part 'world_sections_loading_detail.dart';
part 'world_sections_events.dart';
part 'world_sections_tick_cards.dart';
part 'world_sections_characters.dart';
