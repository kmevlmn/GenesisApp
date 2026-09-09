part of 'me_page.dart';

extension _MePageActions on _MePageState {
  Future<void> _login(IdentityProvider provider) async {
    if (_loggingInProvider != null) return;
    final login = widget.onLogin;
    if (login == null) {
      showGenesisToast(context, 'Sign-in unavailable');
      return;
    }
    final sessionRevisionBeforeLogin = _sessionRevisionListenable?.value;
    _updateState(() => _loggingInProvider = provider);
    try {
      final ok = await login(provider);
      if (!mounted) return;
      if (ok) {
        if (_sessionRevisionListenable?.value == sessionRevisionBeforeLogin) {
          _updateState(() {
            _future = _loadData();
          });
        }
        final onLoginCompleted = widget.onLoginCompleted;
        if (onLoginCompleted != null) {
          unawaited(_runPostLoginFlow(onLoginCompleted));
        }
      } else {
        showGenesisToast(context, 'Sign-in failed');
      }
    } on AuthCancelledException {
      // User cancelled provider UI.
    } catch (e, st) {
      debugPrint('[Auth][MePage] login failed: $e');
      debugPrint('[Auth][MePage] stacktrace:\n$st');
      if (!mounted) return;
      final message = e.toString().trim();
      showGenesisToast(context, message.isEmpty ? 'Sign-in failed' : message);
    } finally {
      if (mounted) _updateState(() => _loggingInProvider = null);
    }
  }

  Future<void> _runPostLoginFlow(Future<void> Function() flow) async {
    try {
      await flow();
    } catch (e, st) {
      debugPrint('[Auth][MePage] post-login flow failed: $e');
      debugPrint('[Auth][MePage] stacktrace:\n$st');
    }
  }

  Future<void> _openSettings() async {
    final loggedOut = await Navigator.of(context).push<bool>(
      GenesisDarkPageRoute<bool>(builder: (_) => const SettingsPage()),
    );
    if (loggedOut == true) {
      widget.onLoggedOut?.call();
    }
  }

  Future<void> _openDiscord() async {
    try {
      final launched = await launchUrl(
        _MePageState._discordUri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        showGenesisToast(context, 'Could not open Discord');
      }
    } catch (_) {
      if (mounted) {
        showGenesisToast(context, 'Could not open Discord');
      }
    }
  }

  Future<void> _editAvatar() async {
    final Uint8List bytes;
    try {
      final image = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (image == null) return;
      bytes = await image.readAsBytes();
      throwIfGifImage(
        bytes: bytes,
        filename: image.name,
        contentType: image.mimeType ?? '',
      );
    } on UnsupportedGifImageException {
      if (!mounted) return;
      showGenesisToast(context, unsupportedGifImageMessage);
      return;
    } catch (_) {
      if (!mounted) return;
      showGenesisToast(context, 'Image pick failed');
      return;
    }
    if (!mounted) return;
    final services = AppServicesScope.read(context);
    final avatarUrl = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => LocalImageCropPage(
          imageBytes: bytes,
          cropSize: meProfileAvatarUploadSize,
          maxOutputSize: meProfileAvatarUploadSize,
          filename: 'avatar.png',
          contentType: 'image/png',
          onUpload: (result) async {
            final uploaded = await services.api.v1.upload.image(
              bytes: result.bytes,
              filename: result.filename,
              contentType: result.contentType,
            );
            return asResolvedImageUrl(uploaded, resolveAssetUrl);
          },
        ),
      ),
    );
    if (avatarUrl == null || avatarUrl.trim().isEmpty || !mounted) return;

    await _updateAvatar(
      update: () => services.api.v1.user.update(avatar: avatarUrl),
      apply: (updatedUser) {
        final updatedAvatar = asResolvedImageUrl(
          updatedUser['avatar'],
          resolveAssetUrl,
          fallback: avatarUrl,
        );
        return updatedAvatar;
      },
    );
  }

  Future<void> _editNickName() async {
    final currentDisplayName = _displayName.value.trim();
    final nickName = await showGenesisDialog<String>(
      context: context,
      builder: (_) => _NickNameDialog(initialValue: currentDisplayName),
    );

    final trimmedName = nickName?.trim() ?? '';
    if (trimmedName.isEmpty || trimmedName == currentDisplayName) return;
    if (!mounted) return;

    final services = AppServicesScope.read(context);
    await _updateDisplayName(
      update: () => services.api.v1.user.update(name: trimmedName),
      apply: (updatedUser) {
        final updatedName = _mapString(
          updatedUser,
          'name',
          fallback: trimmedName,
        );
        return updatedName;
      },
    );
  }

  Future<void> _updateDisplayName({
    required Future<Map<String, dynamic>> Function() update,
    required String Function(Map<dynamic, dynamic> updatedUser) apply,
  }) async {
    _isUpdatingProfile.value = true;
    try {
      final response = await update();
      final updatedUser = response['user'] is Map
          ? response['user'] as Map
          : response;
      await _cacheUpdatedUserInfo(updatedUser);
      final updatedDisplayName = apply(updatedUser);
      if (!mounted) return;
      _displayName.value = updatedDisplayName;
    } catch (_) {
      if (!mounted) return;
      showGenesisToast(context, 'Update failed');
    } finally {
      if (mounted) _isUpdatingProfile.value = false;
    }
  }

  Future<void> _updateAvatar({
    required Future<Map<String, dynamic>> Function() update,
    required String Function(Map<dynamic, dynamic> updatedUser) apply,
  }) async {
    _isUpdatingProfile.value = true;
    try {
      final response = await update();
      final updatedUser = response['user'] is Map
          ? response['user'] as Map
          : response;
      await _cacheUpdatedUserInfo(updatedUser);
      final updatedAvatarUrl = apply(updatedUser);
      if (!mounted) return;
      _avatarUrl.value = updatedAvatarUrl;
    } catch (_) {
      if (!mounted) return;
      showGenesisToast(context, 'Update failed');
    } finally {
      if (mounted) _isUpdatingProfile.value = false;
    }
  }

  Future<void> _cacheUpdatedUserInfo(Map<dynamic, dynamic> updatedUser) async {
    final services = AppServicesScope.read(context);
    final current = await services.sessionStore.readUserInfo();
    final merged = <String, dynamic>{
      if (current != null) ...current,
      for (final entry in updatedUser.entries)
        if (entry.key is String) (entry.key as String): entry.value,
    };
    final uid = (await services.sessionStore.readUid())?.trim() ?? '';
    if (uid.isNotEmpty) {
      merged.putIfAbsent('uid', () => uid);
    }
    await services.sessionStore.saveUserInfo(merged);
  }
}
