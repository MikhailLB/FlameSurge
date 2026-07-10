// Top-level MaterialApp. Owns the singleton service references so every
// screen down the tree pulls from the same instance.

import 'package:flutter/material.dart';

import '../core/attribution_pipeline.dart';
import '../core/config_beacon.dart';
import '../core/net_sensor.dart';
import '../core/push_hub.dart';
import '../core/vault.dart';
import '../features/ignition/ignition_stage.dart';

class FlameSurgeRoot extends StatelessWidget {
  const FlameSurgeRoot({
    super.key,
    required this.vault,
    required this.netSensor,
    required this.attribution,
    required this.configBeacon,
    required this.pushHub,
  });

  final Vault vault;
  final NetSensor netSensor;
  final AttributionPipeline attribution;
  final ConfigBeacon configBeacon;
  final PushHub pushHub;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flame Surge',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF120704),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFFF7A1F),
          secondary: Color(0xFFFFB020),
          surface: Color(0xFF120704),
        ),
        fontFamily: 'Roboto',
      ),
      home: IgnitionStage(
        vault: vault,
        netSensor: netSensor,
        attribution: attribution,
        configBeacon: configBeacon,
        pushHub: pushHub,
      ),
    );
  }
}
