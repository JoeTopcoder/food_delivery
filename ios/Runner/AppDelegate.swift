import Firebase
import Flutter
import UIKit
import PushKit
import AVFoundation
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, PKPushRegistryDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()

    // ── Register for PushKit VoIP pushes ────────────────────────────────────
    // This is what lets iOS wake the app and ring (via CallKit) on an incoming
    // call even when the app is backgrounded or the phone is locked.
    let voipRegistry = PKPushRegistry(queue: DispatchQueue.main)
    voipRegistry.delegate = self
    voipRegistry.desiredPushTypes = [PKPushType.voIP]

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // ── Call audio session channel ──────────────────────────────────────────
    // iOS will stay SILENT on an Agora voice call unless the shared
    // AVAudioSession is put into .playAndRecord and activated. Agora's own
    // management is not reliable here (especially alongside the voip background
    // mode / CallKit), so Dart explicitly activates the session when a call
    // connects and deactivates it when the call ends.
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "HotBiteCallAudio") {
      let channel = FlutterMethodChannel(
        name: "hotbite/call_audio", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "activate":
          let speaker = (call.arguments as? [String: Any])?["speaker"] as? Bool ?? true
          self?.configureCallAudio(active: true, speaker: speaker)
          result(true)
        case "setSpeaker":
          let speaker = (call.arguments as? [String: Any])?["speaker"] as? Bool ?? true
          self?.setSpeakerRoute(speaker)
          result(true)
        case "deactivate":
          self?.configureCallAudio(active: false, speaker: false)
          result(true)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
  }

  // Put the shared audio session into a VoIP-ready state (or tear it down).
  private func configureCallAudio(active: Bool, speaker: Bool) {
    let session = AVAudioSession.sharedInstance()
    do {
      if active {
        try session.setCategory(
          .playAndRecord,
          mode: .voiceChat,
          options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker])
        try session.setActive(true, options: [])
        setSpeakerRoute(speaker)
      } else {
        try session.setActive(false, options: [.notifyOthersOnDeactivation])
      }
    } catch {
      NSLog("HotBiteCallAudio: session error \(error)")
    }
  }

  private func setSpeakerRoute(_ speaker: Bool) {
    let session = AVAudioSession.sharedInstance()
    do {
      try session.overrideOutputAudioPort(speaker ? .speaker : .none)
    } catch {
      NSLog("HotBiteCallAudio: route error \(error)")
    }
  }

  // ── PushKit: VoIP token updated ───────────────────────────────────────────
  // flutter_callkit_incoming stores the token and surfaces it to Dart via its
  // onEvent stream (Event.actionDidUpdateDevicePushTokenVoip), so the Dart side
  // can save it to the DB (users.voip_token). The backend sends the VoIP push
  // to THIS token (not the FCM token).
  func pushRegistry(_ registry: PKPushRegistry,
                    didUpdate pushCredentials: PKPushCredentials,
                    for type: PKPushType) {
    let deviceToken = pushCredentials.token.map { String(format: "%02x", $0) }.joined()
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(deviceToken)
  }

  func pushRegistry(_ registry: PKPushRegistry,
                    didInvalidatePushTokenFor type: PKPushType) {
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  // ── PushKit: incoming VoIP push → show the CallKit ring ───────────────────
  // iOS REQUIRES that a received VoIP push reports an incoming call to CallKit
  // (almost immediately) or it will terminate the app. The payload keys below
  // are what the backend's send-call-voip function must put in the VoIP push.
  func pushRegistry(_ registry: PKPushRegistry,
                    didReceiveIncomingPushWith payload: PKPushPayload,
                    for type: PKPushType,
                    completion: @escaping () -> Void) {
    let p = payload.dictionaryPayload
    let id          = (p["call_id"] as? String) ?? UUID().uuidString
    let nameCaller  = (p["caller_name"] as? String) ?? "HotBite"
    let handle      = (p["handle"] as? String) ?? "HotBite"
    let channelName = (p["channel_name"] as? String) ?? ""
    let callerId    = (p["caller_id"] as? String) ?? ""
    let orderId     = (p["order_id"] as? String) ?? ""

    let data = flutter_callkit_incoming.Data(
      id: id,
      nameCaller: nameCaller,
      handle: handle,
      type: 0 // 0 = audio call
    )
    data.extra = [
      "channel_name": channelName,
      "caller_id": callerId,
      "order_id": orderId,
      "call_id": id,
    ]
    // fromPushKit: true tells the plugin this came from a VoIP push so it reports
    // to CallKit right away (satisfying iOS's requirement).
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(data, fromPushKit: true)
    completion()
  }
}
