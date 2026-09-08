import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Default system UI for light Genesis surfaces.
///
/// The system status bar stays transparent for the whole Flutter activity.
/// Pages only override the icon brightness when their top surface is dark.
const SystemUiOverlayStyle kGenesisDefaultSystemUiOverlayStyle =
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarIconBrightness: Brightness.dark,
    );

/// System UI for maps, media, and other dark top surfaces.
const SystemUiOverlayStyle kGenesisLightStatusIconsSystemUiOverlayStyle =
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarIconBrightness: Brightness.dark,
    );

/// System UI for full-screen dark surfaces such as the image viewer and cropper.
const SystemUiOverlayStyle kGenesisLightSystemUiOverlayStyle =
    SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemStatusBarContrastEnforced: false,
      systemNavigationBarIconBrightness: Brightness.light,
    );

abstract final class GenesisSystemUi {
  static Future<void> initialize() async {
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    // Match the native dark launch screen until the first page takes over.
    SystemChrome.setSystemUIOverlayStyle(kGenesisLightSystemUiOverlayStyle);
  }
}
