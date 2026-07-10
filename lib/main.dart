// Entry point.
//
// Order of initialisation is deliberate:
//   1. Firebase + AppCheck first — must be alive before any push callbacks
//      fire and before FirebaseMessaging.getToken() is called.
//   2. Orientation locked to portrait initially. The IgnitionStage widget
//      relaxes the lock as soon as the loading screen paints so landscape
//      loading images have a chance to appear on tablets.
//   3. DeviceAgent.ignite() builds the real-device UA so the very first HTTP
//      request to the config endpoint already has the right fingerprint.
//   4. All service singletons are created here and injected downward via
//      constructor arguments — nothing uses a global service locator.

import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'boot/flame_surge_root.dart';
import 'core/attribution_pipeline.dart';
import 'core/config_beacon.dart';
import 'core/device_agent.dart';
import 'core/net_sensor.dart';
import 'core/push_hub.dart';
import 'core/vault.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase may fail (no google-services.json yet) — the gray flow tolerates
  // that path and simply omits `firebase_project_id` from the config payload.
  try {
    await Firebase.initializeApp();
    await FirebaseAppCheck.instance.activate(
      androidProvider:
          kDebugMode ? AndroidProvider.debug : AndroidProvider.playIntegrity,
    );
  } catch (_) {}

  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      statusBarBrightness: Brightness.dark,
      systemNavigationBarColor: Color(0xFF120704),
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  await deviceAgent.ignite();

  final vault = Vault();
  await vault.awaken();

  final netSensor = NetSensor();
  final attribution = AttributionPipeline();
  final configBeacon = ConfigBeacon(vault);
  final pushHub = PushHub(vault);
  // Kick off push init early — the FCM token is likely ready by the time the
  // splash router has to compose the config request body.
  unawaited(pushHub.awaken());

  runApp(FlameSurgeRoot(
    vault: vault,
    netSensor: netSensor,
    attribution: attribution,
    configBeacon: configBeacon,
    pushHub: pushHub,
  ));
}
