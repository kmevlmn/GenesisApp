import AppTrackingTransparency
import CryptoKit
import Darwin
import FirebaseAnalytics
import Flutter
import ImageIO
import PhotosUI
import Security
import StoreKit
import UIKit
import UniformTypeIdentifiers

private struct DeviceIdResolution {
  let value: String
  let source: String
  let readStatus: OSStatus
  let writeStatus: OSStatus?
}

private final class GenesisKeyboardAnimationStreamHandler: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var observer: NSObjectProtocol?
  private var latestEvent: [String: Any]?
  private var generation = 0

  override init() {
    super.init()
    observer = NotificationCenter.default.addObserver(
      forName: UIResponder.keyboardWillChangeFrameNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      self?.handleKeyboardFrameChange(notification)
    }
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    if let latestEvent = latestEvent { events(latestEvent) }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  deinit {
    if let observer = observer {
      NotificationCenter.default.removeObserver(observer)
    }
  }

  private func handleKeyboardFrameChange(_ notification: Notification) {
    guard
      let userInfo = notification.userInfo,
      let beginFrame = userInfo[UIResponder.keyboardFrameBeginUserInfoKey] as? CGRect,
      let endFrame = userInfo[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
      let window = activeWindow()
    else { return }

    let startInset = keyboardInset(for: beginFrame, in: window)
    let endInset = keyboardInset(for: endFrame, in: window)
    let phase: String
    if startInset > 0.5 && endInset > 0.5 {
      phase = "changing"
    } else if endInset > startInset {
      phase = "opening"
    } else {
      phase = "closing"
    }
    let duration = (userInfo[UIResponder.keyboardAnimationDurationUserInfoKey]
      as? NSNumber)?.doubleValue ?? 0
    generation += 1
    let event: [String: Any] = [
      "generation": generation,
      "phase": phase,
      "startInset": startInset,
      "endInset": endInset,
      "durationMillis": duration * 1000,
    ]
    latestEvent = event
    eventSink?(event)
  }

  private func activeWindow() -> UIWindow? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return scenes
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)
      ?? scenes.flatMap(\.windows).first
  }

  private func keyboardInset(for screenFrame: CGRect, in window: UIWindow) -> CGFloat {
    let frame = window.convert(screenFrame, from: nil)
    guard frame.maxY >= window.bounds.maxY - 0.5 else { return 0 }
    return max(0, min(window.bounds.height, window.bounds.maxY - frame.minY))
  }
}

final class GenesisAppLifecycleStreamHandler: NSObject, FlutterStreamHandler {
  static let shared = GenesisAppLifecycleStreamHandler()

  private enum Visibility {
    case unknown
    case foreground
    case background
  }

  private let maximumPendingEventCount = 8
  private var eventSink: FlutterEventSink?
  private var pendingEvents: [String] = []
  private var visibility = Visibility.unknown
  private var backgroundEventEmitted = false

  private override init() {
    super.init()
  }

  func onListen(
    withArguments arguments: Any?,
    eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    eventSink = events
    let eventsToDeliver = pendingEvents
    pendingEvents.removeAll(keepingCapacity: true)
    eventsToDeliver.forEach(events)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }

  func sceneDidEnterBackground() {
    switch visibility {
    case .unknown:
      // A scene can connect in the background without ever becoming visible.
      // Establish a baseline without reporting a user-visible transition.
      visibility = .background
    case .foreground:
      visibility = .background
      backgroundEventEmitted = true
      emit("background")
    case .background:
      break
    }
  }

  func sceneDidBecomeActive() {
    switch visibility {
    case .unknown:
      // Cold start establishes the foreground baseline without reporting it.
      visibility = .foreground
    case .background:
      visibility = .foreground
      if backgroundEventEmitted {
        backgroundEventEmitted = false
        emit("foreground")
      }
    case .foreground:
      break
    }
  }

  private func emit(_ event: String) {
    if let eventSink = eventSink {
      eventSink(event)
      return
    }

    pendingEvents.append(event)
    if pendingEvents.count > maximumPendingEventCount {
      pendingEvents.removeFirst(pendingEvents.count - maximumPendingEventCount)
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PHPickerViewControllerDelegate {
  private let channelName = "com.worldo.ai/device"
  private let discussImagePickerChannelName = "com.worldo.ai/discuss_image_picker"
  private let keyboardAnimationChannelName = "com.worldo.ai/keyboard_animation"
  private let appLifecycleChannelName = "com.worldo.ai/app_lifecycle"
  private let firebaseAnalyticsChannelName = "com.worldo.ai/firebase_analytics"
  private let uidKey = "uid"
  private let authTokenKey = "auth_token"
  private let userInfoKey = "user_info"
  private let deviceIdKey = "genesis_device_id"
  private let deviceIdKeychainService = "com.worldo.ai.device-id"
  private let gatewayKeyTag = "com.worldo.ai.gateway-device-key.v1".data(using: .utf8)!
  private let loggedStoreKit2TransactionIdsKey = "firebase_analytics_storekit2_transaction_ids"
  private let normalizedDiscussImageMaxDimension = 4096
  private let normalizedDiscussImageMaxPixels = 16_000_000.0
  private let prefs = UserDefaults.standard
  private var pendingDiscussImagePickerResult: FlutterResult?
  private var pendingDiscussImagePickerNormalizeForUpload = false
  private var storeKit2AnalyticsInFlightIds = Set<UInt64>()
  private var cachedDeviceIdResolution: DeviceIdResolution?
  private var keyboardAnimationStreamHandler: GenesisKeyboardAnimationStreamHandler?
  private var appLifecycleEventChannel: FlutterEventChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    configureGenesisMethodChannel(messenger: engineBridge.applicationRegistrar.messenger())
    configureDiscussImagePickerChannel(messenger: engineBridge.applicationRegistrar.messenger())
    configureFirebaseAnalyticsChannel(messenger: engineBridge.applicationRegistrar.messenger())
    configureKeyboardAnimationChannel(messenger: engineBridge.applicationRegistrar.messenger())
    configureAppLifecycleChannel(messenger: engineBridge.applicationRegistrar.messenger())
  }

  private func configureAppLifecycleChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterEventChannel(
      name: appLifecycleChannelName,
      binaryMessenger: messenger
    )
    channel.setStreamHandler(GenesisAppLifecycleStreamHandler.shared)
    appLifecycleEventChannel = channel
  }

  private func configureKeyboardAnimationChannel(messenger: FlutterBinaryMessenger) {
    let handler = GenesisKeyboardAnimationStreamHandler()
    keyboardAnimationStreamHandler = handler
    FlutterEventChannel(
      name: keyboardAnimationChannelName,
      binaryMessenger: messenger
    ).setStreamHandler(handler)
  }

  private func configureFirebaseAnalyticsChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: firebaseAnalyticsChannelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "AppDelegate released", details: nil))
        return
      }
      guard call.method == "logStoreKit2Transaction" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let args = call.arguments as? [String: Any]
      let rawId = (args?["transactionId"] as? String ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      guard let transactionId = UInt64(rawId), transactionId > 0 else {
        result(FlutterError(code: "invalid_transaction_id", message: "A numeric StoreKit transaction ID is required.", details: nil))
        return
      }
      if self.hasLoggedStoreKit2Transaction(rawId) || self.storeKit2AnalyticsInFlightIds.contains(transactionId) {
        result(true)
        return
      }

      self.storeKit2AnalyticsInFlightIds.insert(transactionId)
      Task { [weak self] in
        guard let self = self else { return }
        let transaction = await self.verifiedStoreKit2Transaction(id: transactionId)
        await MainActor.run {
          self.storeKit2AnalyticsInFlightIds.remove(transactionId)
          guard let transaction = transaction else {
            result(FlutterError(code: "transaction_not_verified", message: "The StoreKit transaction could not be found and verified.", details: nil))
            return
          }
          Analytics.logTransaction(transaction)
          self.markStoreKit2TransactionLogged(rawId)
          result(true)
        }
      }
    }
  }

  @available(iOS 15.0, *)
  private func verifiedStoreKit2Transaction(id: UInt64) async -> StoreKit.Transaction? {
    for await verificationResult in StoreKit.Transaction.unfinished {
      switch verificationResult {
      case .verified(let transaction) where transaction.id == id:
        return transaction
      case .unverified(let transaction, _) where transaction.id == id:
        return nil
      default:
        continue
      }
    }
    for await verificationResult in StoreKit.Transaction.all {
      switch verificationResult {
      case .verified(let transaction) where transaction.id == id:
        return transaction
      case .unverified(let transaction, _) where transaction.id == id:
        return nil
      default:
        continue
      }
    }
    return nil
  }

  private func hasLoggedStoreKit2Transaction(_ transactionId: String) -> Bool {
    let loggedIds = prefs.stringArray(forKey: loggedStoreKit2TransactionIdsKey) ?? []
    return loggedIds.contains(transactionId)
  }

  private func markStoreKit2TransactionLogged(_ transactionId: String) {
    var loggedIds = Set(prefs.stringArray(forKey: loggedStoreKit2TransactionIdsKey) ?? [])
    guard loggedIds.insert(transactionId).inserted else { return }
    prefs.set(loggedIds.sorted(), forKey: loggedStoreKit2TransactionIdsKey)
  }

  private func configureGenesisMethodChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: channelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "AppDelegate released", details: nil))
        return
      }
      switch call.method {
      case "getDeviceId", "getAndroidId":
        result(self.deviceId())
      case "getDeviceIdentitySnapshot":
        result(self.deviceIdentitySnapshot())
      case "setUid":
        let args = call.arguments as? [String: Any]
        let uid = (args?["uid"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.prefs.set(uid, forKey: self.uidKey)
        result(nil)
      case "getUid":
        result(self.prefs.string(forKey: self.uidKey) ?? "")
      case "setAuthToken":
        let args = call.arguments as? [String: Any]
        let token = (args?["token"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.prefs.set(token, forKey: self.authTokenKey)
        result(nil)
      case "getAuthToken":
        result(self.prefs.string(forKey: self.authTokenKey) ?? "")
      case "setUserInfo":
        let args = call.arguments as? [String: Any]
        let userInfo = (args?["userInfo"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        self.prefs.set(userInfo, forKey: self.userInfoKey)
        result(nil)
      case "getUserInfo":
        result(self.prefs.string(forKey: self.userInfoKey) ?? "")
      case "clearUid":
        self.prefs.removeObject(forKey: self.uidKey)
        self.prefs.removeObject(forKey: self.authTokenKey)
        self.prefs.removeObject(forKey: self.userInfoKey)
        result(nil)
      case "getSignInDiagnostics":
        result(self.signInDiagnostics())
      case "getAppName":
        let info = Bundle.main.infoDictionary
        let displayName = info?["CFBundleDisplayName"] as? String
        let bundleName = info?["CFBundleName"] as? String
        result(displayName ?? bundleName ?? "")
      case "getAppVersion":
        result(self.appVersionInfo())
      case "getSystemUserAgent":
        result("\(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
      case "getTimeZone":
        result(TimeZone.current.identifier)
      case "requestTrackingAuthorization":
        self.requestTrackingAuthorization(result: result)
      case "trackingAuthorizationStatus":
        result(self.currentTrackingAuthorizationStatus())
      case "openExternalUrl":
        let args = call.arguments as? [String: Any]
        let value = (args?["url"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: value), !value.isEmpty else {
          result(false)
          return
        }
        UIApplication.shared.open(url, options: [:]) { success in
          result(success)
        }
      case "gatewayPublicKey":
        do {
          result(try self.gatewayPublicKeyBase64Url())
        } catch {
          result(FlutterError(code: "gateway_public_key_failed", message: error.localizedDescription, details: nil))
        }
      case "signGatewayCanonical":
        let args = call.arguments as? [String: Any]
        let canonical = args?["canonical"] as? String ?? ""
        do {
          result(try self.signGatewayCanonical(canonical))
        } catch {
          result(FlutterError(code: "gateway_signature_failed", message: error.localizedDescription, details: nil))
        }
      case "resetGatewayKey":
        self.resetGatewayKey()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func requestTrackingAuthorization(result: @escaping FlutterResult) {
    guard #available(iOS 14, *) else {
      result("notSupported")
      return
    }

    DispatchQueue.main.async {
      ATTrackingManager.requestTrackingAuthorization { status in
        DispatchQueue.main.async {
          result(self.trackingAuthorizationStatusValue(status))
        }
      }
    }
  }

  private func currentTrackingAuthorizationStatus() -> String {
    guard #available(iOS 14, *) else {
      return "notSupported"
    }
    return trackingAuthorizationStatusValue(ATTrackingManager.trackingAuthorizationStatus)
  }

  @available(iOS 14, *)
  private func trackingAuthorizationStatusValue(_ status: ATTrackingManager.AuthorizationStatus) -> String {
    switch status {
    case .notDetermined:
      return "notDetermined"
    case .restricted:
      return "restricted"
    case .denied:
      return "denied"
    case .authorized:
      return "authorized"
    @unknown default:
      return "unknown"
    }
  }

  private func appVersionInfo() -> [String: Any] {
    let info = Bundle.main.infoDictionary
    return [
      "versionName": info?["CFBundleShortVersionString"] as? String ?? "",
      "versionCode": info?["CFBundleVersion"] as? String ?? "",
      "packageName": Bundle.main.bundleIdentifier ?? ""
    ]
  }

  private func configureDiscussImagePickerChannel(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: discussImagePickerChannelName,
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else {
        result(FlutterError(code: "unavailable", message: "AppDelegate released", details: nil))
        return
      }
      switch call.method {
      case "pickImages":
        let args = call.arguments as? [String: Any]
        let limit = max(1, args?["limit"] as? Int ?? 6)
        let normalizeForUpload = args?["normalizeForUpload"] as? Bool ?? false
        self.pickDiscussImages(
          limit: limit,
          normalizeForUpload: normalizeForUpload,
          result: result
        )
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func pickDiscussImages(
    limit: Int,
    normalizeForUpload: Bool,
    result: @escaping FlutterResult
  ) {
    guard #available(iOS 14, *) else {
      result(FlutterError(code: "unsupported_ios", message: "PHPicker requires iOS 14 or later.", details: nil))
      return
    }
    guard pendingDiscussImagePickerResult == nil else {
      result(FlutterError(code: "picker_active", message: "An image picker is already active.", details: nil))
      return
    }
    guard let presenter = topViewController() else {
      result(FlutterError(code: "no_presenter", message: "Cannot find a view controller to present image picker.", details: nil))
      return
    }

    pendingDiscussImagePickerResult = result
    pendingDiscussImagePickerNormalizeForUpload = normalizeForUpload

    var config = PHPickerConfiguration(photoLibrary: .shared())
    config.filter = .images
    config.selectionLimit = limit
    config.preferredAssetRepresentationMode = .automatic

    let picker = PHPickerViewController(configuration: config)
    // The default adaptive sheet presentation scales and translates the
    // presenting Flutter view. Keep the page underneath in its exact screen
    // coordinates while the system picker covers it.
    picker.modalPresentationStyle = .overFullScreen
    picker.modalTransitionStyle = .coverVertical
    picker.delegate = self
    presenter.present(picker, animated: true)
  }

  @available(iOS 14, *)
  func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
    // Keep Flutter in its picker-paused state until the native dismissal has
    // actually finished. Completing the method call before this animation
    // ends lets Flutter restore focus and move content behind the picker.
    picker.dismiss(animated: true) { [weak self] in
      self?.completeDiscussImagePicking(results)
    }
  }

  @available(iOS 14, *)
  private func completeDiscussImagePicking(_ results: [PHPickerResult]) {
    guard let result = pendingDiscussImagePickerResult else {
      return
    }
    let normalizeForUpload = pendingDiscussImagePickerNormalizeForUpload
    pendingDiscussImagePickerResult = nil
    pendingDiscussImagePickerNormalizeForUpload = false

    guard !results.isEmpty else {
      result([])
      return
    }

    var paths = Array<String?>(repeating: nil, count: results.count)
    var failures: [String] = []

    func finish() {
      DispatchQueue.main.async {
        let loadedPaths = paths.compactMap { $0 }
        if loadedPaths.isEmpty, let firstFailure = failures.first {
          result(FlutterError(code: "invalid_image", message: firstFailure, details: failures))
        } else {
          result(loadedPaths)
        }
      }
    }

    func processItem(at index: Int) {
      guard index < results.count else {
        finish()
        return
      }
      let item = results[index]
      saveDiscussPickedImage(
        item.itemProvider,
        normalizeForUpload: normalizeForUpload
      ) { path, error in
        if let path = path {
          paths[index] = path
        } else if let error = error {
          failures.append(error)
          NSLog("Discuss image selection failed for item \(index): \(error)")
        }
        processItem(at: index + 1)
      }
    }

    processItem(at: 0)
  }

  @available(iOS 14, *)
  private func saveDiscussPickedImage(
    _ provider: NSItemProvider,
    normalizeForUpload: Bool,
    completion: @escaping (String?, String?) -> Void
  ) {
    if normalizeForUpload,
       provider.hasItemConformingToTypeIdentifier(UTType.gif.identifier) {
      completion(nil, "GIF images are not supported.")
      return
    }

    loadNormalizedDiscussImageRepresentation(
      provider,
      allowGif: !normalizeForUpload,
      completion: completion
    )
  }

  @available(iOS 14, *)
  private func loadNormalizedDiscussImageRepresentation(
    _ provider: NSItemProvider,
    allowGif: Bool = false,
    completion: @escaping (String?, String?) -> Void
  ) {
    let identifiers = provider.registeredTypeIdentifiers.filter { identifier in
      guard let type = UTType(identifier) else {
        return false
      }
      return type.conforms(to: .image)
        && (allowGif || !type.conforms(to: .gif))
    }

    func tryData(at index: Int, lastError: String?) {
      guard index < identifiers.count else {
        completion(nil, lastError ?? "Provider has no supported image representation.")
        return
      }

      let identifier = identifiers[index]
      provider.loadDataRepresentation(forTypeIdentifier: identifier) { [weak self] data, error in
        guard let self = self else {
          completion(nil, "Image processor is unavailable.")
          return
        }
        if let data = data,
           let source = CGImageSourceCreateWithData(data as CFData, nil),
           let path = self.writeNormalizedDiscussImage(source) {
          completion(path, nil)
          return
        }
        let message = error?.localizedDescription
          ?? "Cannot decode data representation of type \(identifier)."
        NSLog("Discuss normalized image data representation failed: \(message)")
        tryData(at: index + 1, lastError: message)
      }
    }

    func tryFile(at index: Int, lastError: String?) {
      guard index < identifiers.count else {
        tryData(at: 0, lastError: lastError)
        return
      }

      let identifier = identifiers[index]
      provider.loadFileRepresentation(forTypeIdentifier: identifier) { [weak self] url, error in
        guard let self = self else {
          completion(nil, "Image processor is unavailable.")
          return
        }
        if let url = url,
           let source = CGImageSourceCreateWithURL(url as CFURL, nil),
           let path = self.writeNormalizedDiscussImage(source) {
          completion(path, nil)
          return
        }
        let message = error?.localizedDescription
          ?? "Cannot decode file representation of type \(identifier)."
        NSLog("Discuss normalized image file representation failed: \(message)")
        tryFile(at: index + 1, lastError: message)
      }
    }

    tryFile(at: 0, lastError: nil)
  }

  private func writeNormalizedDiscussImage(_ source: CGImageSource) -> String? {
    guard let maxPixelSize = normalizedDiscussImageMaxPixelSize(source) else {
      return nil
    }
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceCreateThumbnailWithTransform: true,
      kCGImageSourceShouldCacheImmediately: true,
      kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
    ]
    guard let image = CGImageSourceCreateThumbnailAtIndex(
      source,
      0,
      options as CFDictionary
    ) else {
      return nil
    }
    return writeNormalizedDiscussCGImage(image)
  }

  private func normalizedDiscussImageMaxPixelSize(_ source: CGImageSource) -> Int? {
    guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
      as? [CFString: Any],
      let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue,
      let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue,
      width.isFinite,
      height.isFinite,
      width > 0,
      height > 0 else {
      return nil
    }

    let longestEdge = max(width, height)
    let dimensionScale = Double(normalizedDiscussImageMaxDimension) / longestEdge
    let pixelScale = sqrt(normalizedDiscussImageMaxPixels / (width * height))
    let scale = min(1.0, dimensionScale, pixelScale)
    return max(1, Int(floor(longestEdge * scale)))
  }

  private func writeNormalizedDiscussCGImage(_ image: CGImage) -> String? {
    let hasTransparency = discussImageHasTransparentPixels(image)
    let fileExtension = hasTransparency ? "png" : "jpg"
    let destinationType = hasTransparency ? UTType.png.identifier : UTType.jpeg.identifier
    let destinationURL = discussPickerTempURL(fileExtension: fileExtension)
    guard let destination = CGImageDestinationCreateWithURL(
      destinationURL as CFURL,
      destinationType as CFString,
      1,
      nil
    ) else {
      return nil
    }

    let properties: CFDictionary? = hasTransparency
      ? nil
      : [kCGImageDestinationLossyCompressionQuality: 0.90] as CFDictionary
    CGImageDestinationAddImage(destination, image, properties)
    guard CGImageDestinationFinalize(destination) else {
      try? FileManager.default.removeItem(at: destinationURL)
      return nil
    }
    return destinationURL.path
  }

  private func discussImageHasTransparentPixels(_ image: CGImage) -> Bool {
    switch image.alphaInfo {
    case .none, .noneSkipFirst, .noneSkipLast:
      return false
    default:
      break
    }

    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else {
      return false
    }
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue
      | CGImageAlphaInfo.premultipliedLast.rawValue
    let rowsPerChunk = 64

    var startY = 0
    while startY < height {
      let chunkHeight = min(rowsPerChunk, height - startY)
      guard let chunk = image.cropping(
        to: CGRect(
          x: 0,
          y: CGFloat(startY),
          width: CGFloat(width),
          height: CGFloat(chunkHeight)
        )
      ) else {
        return true
      }
      var pixels = [UInt8](repeating: 0, count: width * chunkHeight * 4)
      let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
        guard let context = CGContext(
          data: buffer.baseAddress,
          width: width,
          height: chunkHeight,
          bitsPerComponent: 8,
          bytesPerRow: width * 4,
          space: colorSpace,
          bitmapInfo: bitmapInfo
        ) else {
          return false
        }
        context.draw(
          chunk,
          in: CGRect(
            x: 0,
            y: 0,
            width: CGFloat(width),
            height: CGFloat(chunkHeight)
          )
        )
        return true
      }
      if !rendered {
        return true
      }
      var alphaIndex = 3
      while alphaIndex < pixels.count {
        if pixels[alphaIndex] < 255 {
          return true
        }
        alphaIndex += 4
      }
      startY += chunkHeight
    }
    return false
  }

  private func writeDiscussImageData(_ data: Data, extension fileExtension: String) -> String? {
    let destination = discussPickerTempURL(fileExtension: fileExtension)
    do {
      try data.write(to: destination, options: .atomic)
      return destination.path
    } catch {
      NSLog("Discuss image data write failed: \(error)")
      return nil
    }
  }

  private func discussPickerTempURL(fileExtension: String) -> URL {
    let filename = "\(UUID().uuidString).\(fileExtension)"
    return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent(filename)
  }

  private func topViewController() -> UIViewController? {
    let activeScene = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    let root = activeScene?.windows.first { $0.isKeyWindow }?.rootViewController
      ?? UIApplication.shared.windows.first { $0.isKeyWindow }?.rootViewController
    return topViewController(from: root)
  }

  private func topViewController(from controller: UIViewController?) -> UIViewController? {
    if let navigationController = controller as? UINavigationController {
      return topViewController(from: navigationController.visibleViewController)
    }
    if let tabBarController = controller as? UITabBarController {
      return topViewController(from: tabBarController.selectedViewController)
    }
    if let presented = controller?.presentedViewController {
      return topViewController(from: presented)
    }
    return controller
  }

  private func deviceId() -> String {
    return resolveDeviceId().value
  }

  private func resolveDeviceId() -> DeviceIdResolution {
    if let cached = cachedDeviceIdResolution {
      return cached
    }

    let keychainRead = readKeychainDeviceId()
    let resolution: DeviceIdResolution
    if let existing = keychainRead.value {
      let normalized = normalizeDeviceId(existing)
      let writeStatus = normalized == existing ? nil : saveKeychainDeviceId(normalized)
      resolution = DeviceIdResolution(
        value: normalized,
        source: "keychain_existing",
        readStatus: keychainRead.status,
        writeStatus: writeStatus
      )
    } else {
      let legacy = prefs.string(forKey: deviceIdKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let hasLegacy = !legacy.isEmpty
      let value = hasLegacy ? normalizeDeviceId(legacy) : UUID().uuidString
      let source: String
      if keychainRead.status != errSecItemNotFound {
        source = "keychain_error"
      } else if hasLegacy {
        source = "user_defaults_migration"
      } else {
        source = "generated_uuid"
      }
      resolution = DeviceIdResolution(
        value: value,
        source: source,
        readStatus: keychainRead.status,
        writeStatus: saveKeychainDeviceId(value)
      )
    }
    cachedDeviceIdResolution = resolution
    return resolution
  }

  private func deviceIdentitySnapshot() -> [String: Any] {
    let resolution = resolveDeviceId()
    let bundleId = Bundle.main.bundleIdentifier ?? ""
    let prefix = appIdPrefix()
    let accessGroup = prefix.isEmpty || bundleId.isEmpty ? "" : "\(prefix).\(bundleId)"
    var snapshot: [String: Any] = [
      "platform": "ios",
      "device_id": resolution.value,
      "device_id_source": resolution.source,
      "keychain_read_status": Int(resolution.readStatus),
      "bundle_id": bundleId,
      "app_id_prefix": prefix,
      "keychain_access_group_hash": sha256Hex(accessGroup),
      "gateway_public_key_hash": (try? gatewayPublicKeySha256()) ?? "",
      "idfv_hash": sha256Hex(UIDevice.current.identifierForVendor?.uuidString ?? ""),
      "device_model": hardwareModel(),
      "os_build": operatingSystemBuild()
    ]
    if let writeStatus = resolution.writeStatus {
      snapshot["keychain_write_status"] = Int(writeStatus)
    } else {
      snapshot["keychain_write_status"] = NSNull()
    }
    return snapshot
  }

  private func normalizeDeviceId(_ value: String) -> String {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if normalized.lowercased().hasPrefix("ios:") {
      return String(normalized.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return normalized
  }

  private func readKeychainDeviceId() -> (value: String?, status: OSStatus) {
    var query = keychainDeviceIdQuery()
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess else {
      return (nil, status)
    }
    guard let data = item as? Data,
          let value = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
          !value.isEmpty else {
      return (nil, errSecDecode)
    }
    return (value, status)
  }

  @discardableResult
  private func saveKeychainDeviceId(_ value: String) -> OSStatus {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !normalized.isEmpty, let data = normalized.data(using: .utf8) else {
      return errSecParam
    }

    SecItemDelete(keychainDeviceIdQuery() as CFDictionary)

    var item = keychainDeviceIdQuery()
    item[kSecValueData as String] = data
    item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(item as CFDictionary, nil)
  }

  private func keychainDeviceIdQuery() -> [String: Any] {
    return [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: deviceIdKeychainService,
      kSecAttrAccount as String: deviceIdKey,
    ]
  }

  private func gatewayPublicKeyBase64Url() throws -> String {
    return base64Url(try gatewayPublicKeySpkiData())
  }

  private func gatewayPublicKeySha256() throws -> String {
    return sha256Hex(try gatewayPublicKeySpkiData())
  }

  private func gatewayPublicKeySpkiData() throws -> Data {
    let privateKey = try ensureGatewayPrivateKey()
    guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
      throw NSError(domain: "GatewayKey", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing public key"])
    }
    var error: Unmanaged<CFError>?
    guard let publicData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
      throw error?.takeRetainedValue() as Error? ??
        NSError(domain: "GatewayKey", code: 2, userInfo: [NSLocalizedDescriptionKey: "Public key export failed"])
    }
    return spkiDerForP256PublicKey(publicData)
  }

  private func signGatewayCanonical(_ canonical: String) throws -> String {
    let privateKey = try ensureGatewayPrivateKey()
    let data = Data(canonical.utf8)
    var error: Unmanaged<CFError>?
    guard let signature = SecKeyCreateSignature(
      privateKey,
      .ecdsaSignatureMessageX962SHA256,
      data as CFData,
      &error
    ) as Data? else {
      throw error?.takeRetainedValue() as Error? ??
        NSError(domain: "GatewayKey", code: 3, userInfo: [NSLocalizedDescriptionKey: "Signature failed"])
    }
    return base64Url(signature)
  }

  private func ensureGatewayPrivateKey() throws -> SecKey {
    if let existing = readGatewayPrivateKey() {
      return existing
    }

    let attributes: [String: Any] = [
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrKeySizeInBits as String: 256,
      kSecPrivateKeyAttrs as String: [
        kSecAttrIsPermanent as String: true,
        kSecAttrApplicationTag as String: gatewayKeyTag,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
      ]
    ]
    var error: Unmanaged<CFError>?
    guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
      throw error?.takeRetainedValue() as Error? ??
        NSError(domain: "GatewayKey", code: 4, userInfo: [NSLocalizedDescriptionKey: "Key generation failed"])
    }
    return key
  }

  private func readGatewayPrivateKey() -> SecKey? {
    var query = gatewayPrivateKeyQuery()
    query[kSecReturnRef as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess else {
      return nil
    }
    guard let item = item,
          CFGetTypeID(item) == SecKeyGetTypeID() else {
      NSLog("Gateway private key had an unexpected Keychain type; regenerating it.")
      SecItemDelete(gatewayPrivateKeyQuery() as CFDictionary)
      return nil
    }
    return item as! SecKey
  }

  private func resetGatewayKey() {
    SecItemDelete(gatewayPrivateKeyQuery() as CFDictionary)
  }

  private func gatewayPrivateKeyQuery() -> [String: Any] {
    return [
      kSecClass as String: kSecClassKey,
      kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
      kSecAttrApplicationTag as String: gatewayKeyTag
    ]
  }

  private func spkiDerForP256PublicKey(_ x963PublicKey: Data) -> Data {
    let prefix: [UInt8] = [
      0x30, 0x59, 0x30, 0x13, 0x06, 0x07, 0x2A, 0x86,
      0x48, 0xCE, 0x3D, 0x02, 0x01, 0x06, 0x08, 0x2A,
      0x86, 0x48, 0xCE, 0x3D, 0x03, 0x01, 0x07, 0x03,
      0x42, 0x00
    ]
    return Data(prefix) + x963PublicKey
  }

  private func base64Url(_ data: Data) -> String {
    return data
      .base64EncodedString()
      .replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_")
      .replacingOccurrences(of: "=", with: "")
  }

  private func sha256Hex(_ value: String) -> String {
    guard !value.isEmpty else { return "" }
    return sha256Hex(Data(value.utf8))
  }

  private func sha256Hex(_ data: Data) -> String {
    return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func appIdPrefix() -> String {
    let raw = normalizedString(Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix"))
    guard !raw.contains("$(") else { return "" }
    return raw.trimmingCharacters(in: CharacterSet(charactersIn: "."))
  }

  private func hardwareModel() -> String {
    var systemInfo = utsname()
    uname(&systemInfo)
    return withUnsafePointer(to: &systemInfo.machine) {
      $0.withMemoryRebound(to: CChar.self, capacity: 1) {
        String(cString: $0)
      }
    }
  }

  private func operatingSystemBuild() -> String {
    var size = 0
    guard sysctlbyname("kern.osversion", nil, &size, nil, 0) == 0, size > 0 else {
      return ""
    }
    var value = [CChar](repeating: 0, count: size)
    guard sysctlbyname("kern.osversion", &value, &size, nil, 0) == 0 else {
      return ""
    }
    return String(cString: value)
  }

  private func signInDiagnostics() -> [String: Any] {
    let info = Bundle.main.infoDictionary ?? [:]
    let googleServiceInfo = googleServiceInfoPlist()
    return [
      "platform": "ios",
      "bundleIdentifier": Bundle.main.bundleIdentifier ?? "",
      "systemVersion": UIDevice.current.systemVersion,
      "gidClientId": normalizedString(info["GIDClientID"]),
      "gidServerClientId": normalizedString(info["GIDServerClientID"]),
      "googleServiceClientId": normalizedString(googleServiceInfo["CLIENT_ID"]),
      "googleServiceServerClientId": normalizedString(googleServiceInfo["SERVER_CLIENT_ID"]),
    ]
  }

  private func googleServiceInfoPlist() -> [String: Any] {
    guard let url = Bundle.main.url(forResource: "GoogleService-Info", withExtension: "plist"),
          let data = NSDictionary(contentsOf: url) as? [String: Any] else {
      return [:]
    }
    return data
  }

  private func normalizedString(_ value: Any?) -> String {
    return (value as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
