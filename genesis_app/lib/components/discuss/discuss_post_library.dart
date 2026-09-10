import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../ui/tokens/genesis_typography.dart';
import 'package:flutter/services.dart';

import '../../app/bootstrap/app_services_scope.dart';
import '../auth/login_guard.dart';
import '../common/genesis_bottom_sheet_panel.dart';
import '../common/genesis_center_toast.dart';
import '../common/genesis_modal_routes.dart';
import '../common/genesis_upload_progress_overlay.dart';
import '../../platform/native_image_picker.dart';
import '../../ui/components/genesis_edge_swipe_back.dart';
import '../../ui/tokens/genesis_colors.dart';
import '../../ui/tokens/genesis_image_radii.dart';
import '../../utils/genesis_image_resource.dart';
import '../../utils/genesis_ugc_text.dart';
import '../../utils/image_format_guards.dart';
import '../../utils/image_upload_processing.dart';

export '../../platform/native_image_picker.dart'
    show DiscussPickedImage, GenesisImagePickResult;

part 'discuss_post_facade.dart';
part 'discuss_composer_sheet.dart';
part 'discuss_composer_panel.dart';
part 'discuss_image_strip.dart';

typedef DiscussPostSubmitter =
    Future<Map<String, dynamic>> Function(String content, List<String> images);
typedef DiscussComposerSubmitter =
    Future<void> Function(String content, List<String> images);
typedef DiscussImagePicker =
    Future<List<DiscussPickedImage>> Function(int limit);
typedef DiscussImageResultPicker =
    Future<GenesisImagePickResult> Function(int limit);
typedef DiscussImageUploader =
    Future<String> Function(DiscussPickedImage image);
typedef DiscussImageProgressUploader =
    Future<String> Function(
      DiscussPickedImage image, {
      void Function(int sentBytes, int totalBytes)? onSendProgress,
    });
typedef DiscussImageProcessorForTesting =
    Future<Map<String, Object>> Function(Map<String, Object> request);

@visibleForTesting
DiscussImageProcessorForTesting? debugDiscussImageProcessorOverride;

const Color _discussComposerSurface = GenesisColors.darkFaintSurface;
const Color _discussComposerPrimary = GenesisColors.darkTextPrimary;
const Color _discussComposerSecondary = GenesisColors.darkTextSecondary;
const Color _discussComposerMuted = GenesisColors.darkTextTertiary;
const Color _discussComposerBorder = Color(0x24FFFFFF);

const int discussPostMaxImages = 6;
const int _discussComposerMinTextLines = 3;
const int _discussComposerMaxTextLines = 6;
const double _discussComposerFontSize = 14;
const double _discussComposerLineHeight = 1.25;
const Duration _discussComposerScrimFadeDuration = Duration(milliseconds: 180);
const Duration _discussComposerSheetDismissDuration = Duration(
  milliseconds: 160,
);
const Duration _discussUploadProgressTick = Duration(milliseconds: 270);
const int _discussCompressionProgressBytesPerSecond = 2 * 1024 * 1024;
const int _discussUploadProgressBytesPerSecond = 50 * 1024;
const double _discussCompressionProgress = 0.10;
const double _discussEstimatedUploadProgressCap = 0.98;
const int _discussUploadMaxWidth = 800;
const Duration _discussCompressionProgressMinDuration = Duration(
  milliseconds: 450,
);
const Duration _discussCompressionProgressMaxDuration = Duration(
  milliseconds: 2600,
);
