import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:uilastgen/utils.dart';

import 'package:vector_math/vector_math_64.dart' as v64;

import 'package:provider/provider.dart';

class OrbShaderWidget extends StatefulWidget {
  const OrbShaderWidget({
    super.key,
    required this.config,
    this.onUpdate,
    required this.mousePos,
    required this.minEnergy,
  });

  final double minEnergy;
  final OrbShaderConfig config;
  final Offset mousePos;
  final void Function(double energy)? onUpdate;

  @override
  State<OrbShaderWidget> createState() => OrbShaderWidgetState();
}

class OrbShaderWidgetState extends State<OrbShaderWidget>
    with SingleTickerProviderStateMixin {
  final _heartbeatSequence = TweenSequence(
    [
      TweenSequenceItem(tween: ConstantTween(0), weight: 40),
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 1.0)
              .chain(CurveTween(curve: Curves.easeInOutCubic)),
          weight: 8),
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.2)
              .chain(CurveTween(curve: Curves.easeInOutCubic)),
          weight: 12),
      TweenSequenceItem(
          tween: Tween(begin: 0.2, end: 0.8)
              .chain(CurveTween(curve: Curves.easeInOutCubic)),
          weight: 6),
      TweenSequenceItem(
          tween: Tween(begin: 0.8, end: 0.0)
              .chain(CurveTween(curve: Curves.easeInOutCubic)),
          weight: 10),
    ],
  );

  late final _heartbeatAnim =
      AnimationController(vsync: this, duration: 3000.ms)..repeat();

  @override
  Widget build(BuildContext context) => Consumer<FragmentPrograms?>(
        builder: (context, fragmentPrograms, _) {
          if (fragmentPrograms == null) return const SizedBox.expand();
          return ListenableBuilder(
            listenable: _heartbeatAnim,
            builder: (_, __) {
              final heartbeatEnergy =
                  _heartbeatAnim.drive(_heartbeatSequence).value;
              return TweenAnimationBuilder(
                tween: Tween<double>(
                    begin: widget.minEnergy, end: widget.minEnergy),
                duration: 300.ms,
                curve: Curves.easeOutCubic,
                builder: (context, minEnergy, child) {
                  return ReactiveWidget(
                    builder: (context, time, size) {
                      double energyLevel = 0;
                      if (size.shortestSide != 0) {
                        final d = (Offset(size.width, size.height) / 2 -
                                widget.mousePos)
                            .distance;
                        final hitSize = size.shortestSide * .5;
                        energyLevel = 1 - min(1, (d / hitSize));
                        scheduleMicrotask(
                            () => widget.onUpdate?.call(energyLevel));
                      }
                      energyLevel +=
                          (1.3 - energyLevel) * heartbeatEnergy * 0.1;
                      energyLevel = lerpDouble(minEnergy, 1, energyLevel)!;
                      return CustomPaint(
                        size: size,
                        painter: OrbShaderPainter(
                          fragmentPrograms.orb.fragmentShader(),
                          config: widget.config,
                          time: time,
                          mousePos: widget.mousePos,
                          energy: energyLevel,
                        ),
                      );
                    },
                  );
                },
              );
            },
          );
        },
      );
}

class OrbShaderPainter extends CustomPainter {
  OrbShaderPainter(
    this.shader, {
    required this.config,
    required this.time,
    required this.mousePos,
    required this.energy,
  });
  final FragmentShader shader;
  final OrbShaderConfig config;
  final double time;
  final Offset mousePos;
  final double energy;

  @override
  void paint(Canvas canvas, Size size) {
    double fov = v64.mix(pi / 4.3, pi / 2.0, config.zoom.clamp(0.0, 1.0));

    v64.Vector3 colorToVector3(Color c) =>
        v64.Vector3(
          c.red.toDouble(),
          c.green.toDouble(),
          c.blue.toDouble(),
        ) /
        255.0;

    v64.Vector3 lightLumP = colorToVector3(config.lightColor).normalized() *
        max(0.0, config.lightBrightness);
    v64.Vector3 albedo = colorToVector3(config.materialColor);

    v64.Vector3 ambientLight = colorToVector3(config.ambientLightColor) *
        max(0.0, config.ambientLightBrightness);

    shader.setFloat(0, size.width);
    shader.setFloat(1, size.height);
    shader.setFloat(2, time);
    shader.setFloat(3, max(0.0, config.exposure));
    shader.setFloat(4, fov);
    shader.setFloat(5, config.roughness.clamp(0.0, 1.0));
    shader.setFloat(6, config.metalness.clamp(0.0, 1.0));
    shader.setFloat(7, config.lightOffsetX);
    shader.setFloat(8, config.lightOffsetY);
    shader.setFloat(9, config.lightOffsetZ);
    shader.setFloat(10, config.lightRadius);
    shader.setFloat(11, lightLumP.x);
    shader.setFloat(12, lightLumP.y);
    shader.setFloat(13, lightLumP.z);
    shader.setFloat(14, albedo.x);
    shader.setFloat(15, albedo.y);
    shader.setFloat(16, albedo.z);
    shader.setFloat(17, config.ior.clamp(0.0, 2.0));
    shader.setFloat(18, config.lightAttenuation.clamp(0.0, 1.0));
    shader.setFloat(19, ambientLight.x);
    shader.setFloat(20, ambientLight.y);
    shader.setFloat(21, ambientLight.z);
    shader.setFloat(22, config.ambientLightDepthFactor.clamp(0.0, 1.0));
    shader.setFloat(23, energy);

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = shader,
    );
  }

  @override
  bool shouldRepaint(covariant OrbShaderPainter oldDelegate) {
    return oldDelegate.shader != shader ||
        oldDelegate.config != config ||
        oldDelegate.time != time ||
        oldDelegate.mousePos != mousePos ||
        oldDelegate.energy != energy;
  }
}

class OrbShaderConfig {
  const OrbShaderConfig({
    this.zoom = 0.3,
    this.exposure = 0.4,
    this.roughness = 0.3,
    this.metalness = 0.3,
    this.materialColor = const Color.fromARGB(255, 242, 163, 138),
    this.lightRadius = 0.75,
    this.lightColor = const Color(0xFFFFFFFF),
    this.lightBrightness = 15.00,
    this.ior = 0.5,
    this.lightAttenuation = 0.5,
    this.ambientLightColor = const Color(0xFFFFFFFF),
    this.ambientLightBrightness = 0.2,
    this.ambientLightDepthFactor = 0.3,
    this.lightOffsetX = 0,
    this.lightOffsetY = 0.1,
    this.lightOffsetZ = -0.66,
  })  : assert(zoom >= 0 && zoom <= 1),
        assert(exposure >= 0),
        assert(metalness >= 0 && metalness <= 1),
        assert(lightRadius >= 0),
        assert(lightBrightness >= 1),
        assert(ior >= 0 && ior <= 2),
        assert(lightAttenuation >= 0 && lightAttenuation <= 1),
        assert(ambientLightBrightness >= 0);

  final double zoom;

  /// Camera exposure value, higher is brighter, 0 is black
  final double exposure;

  /// How rough the surface is, somewhat translates to the intensity/radius
  /// of specular highlights
  final double roughness;

  /// 0 for a dielectric material (plastic, wood, grass, water, etc...),
  /// 1 for a metal (iron, copper, aluminum, gold, etc...), a value in between
  /// blends the two materials (not really physically accurate, has minor
  /// artistic value)
  final double metalness;

  /// any color, alpha ignored, for metal materials doesn't correspond to
  /// surface color but to a reflectivity index based off of a 0 degree viewing
  /// angle (can look these values up online for various actual metals)
  final Color materialColor;

  /// The following light properties model a disk shaped light pointing
  /// at the sphere
  final double lightRadius;

  /// alpha ignored
  final Color lightColor;

  /// Light Brightness measured in luminous power (perceived total
  /// brightness of light, the larger the radius the more diffused the light
  /// power is for a given area)
  final double lightBrightness;

  /// 0..2, Index of refraction, higher value = more refraction,
  final double ior;

  /// Light attenuation factor, 0 for no attenuation, 1 is very fast attenuation
  final double lightAttenuation;

  /// alpha ignored
  final Color ambientLightColor;

  final double ambientLightBrightness;

  /// Modulates the ambient light brightness based off of the depth of the
  /// pixel. 1 means the ambient brightness factor at the front of the orb is 0,
  /// brightness factor at the back is 1. 0 means there's no change to the
  /// brightness factor based on depth
  final double ambientLightDepthFactor;

  /// Offset of the light relative to the center of the orb, +x is to the right
  final double lightOffsetX;

  /// Offset of the light relative to the center of the orb, +y is up
  final double lightOffsetY;

  /// Offset of the light relative to the center of the orb, +z is facing the camera
  final double lightOffsetZ;

  OrbShaderConfig copyWith({
    double? zoom,
    double? exposure,
    double? roughness,
    double? metalness,
    Color? materialColor,
    double? lightRadius,
    Color? lightColor,
    double? lightBrightness,
    double? ior,
    double? lightAttenuation,
    Color? ambientLightColor,
    double? ambientLightBrightness,
    double? ambientLightDepthFactor,
    double? lightOffsetX,
    double? lightOffsetY,
    double? lightOffsetZ,
  }) {
    return OrbShaderConfig(
      zoom: zoom ?? this.zoom,
      exposure: exposure ?? this.exposure,
      roughness: roughness ?? this.roughness,
      metalness: metalness ?? this.metalness,
      materialColor: materialColor ?? this.materialColor,
      lightRadius: lightRadius ?? this.lightRadius,
      lightColor: lightColor ?? this.lightColor,
      lightBrightness: lightBrightness ?? this.lightBrightness,
      ior: ior ?? this.ior,
      lightAttenuation: lightAttenuation ?? this.lightAttenuation,
      ambientLightColor: ambientLightColor ?? this.ambientLightColor,
      ambientLightBrightness:
          ambientLightBrightness ?? this.ambientLightBrightness,
      ambientLightDepthFactor:
          ambientLightDepthFactor ?? this.ambientLightDepthFactor,
      lightOffsetX: lightOffsetX ?? this.lightOffsetX,
      lightOffsetY: lightOffsetY ?? this.lightOffsetY,
      lightOffsetZ: lightOffsetZ ?? this.lightOffsetZ,
    );
  }
}
