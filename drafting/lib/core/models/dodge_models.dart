import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Nivel de dificultad del simulador:
/// - [easy]: Emocionante y preciso (cada 1.85s), los campeones te buscan activamente.
/// - [medium]: Cadencia alta (1.35s) + 35% de Combos Dobles coordinados.
/// - [hard]: Intenso (0.95s) + 55% de ataques cruzados (Crossfire) y predicción letal.
enum DodgeDifficulty {
  easy,
  medium,
  hard,
}

/// Campeones disponibles en el simulador con sus íconos en `assets/campeones/`.
enum SimChampion {
  lux,
  ezreal,
  chogath,
  ziggs,
  malphite,
}

extension SimChampionAssets on SimChampion {
  String get assetPath {
    switch (this) {
      case SimChampion.chogath:
        return 'assets/campeones/Chogat.png';
      case SimChampion.ezreal:
        return 'assets/campeones/Ezreal.png';
      case SimChampion.lux:
        return 'assets/campeones/Lux.png';
      case SimChampion.malphite:
        return 'assets/campeones/Malphite.png';
      case SimChampion.ziggs:
        return 'assets/campeones/Ziggs.png';
    }
  }

  String get displayName {
    switch (this) {
      case SimChampion.chogath:
        return "Cho'Gath";
      case SimChampion.ezreal:
        return 'Ezreal';
      case SimChampion.lux:
        return 'Lux';
      case SimChampion.malphite:
        return 'Malphite';
      case SimChampion.ziggs:
        return 'Ziggs';
    }
  }
}

/// Tipos de habilidades basadas en los campeones definidos en Nuevas_mejoras_2027.md
enum SkillshotType {
  chogathQ, // Se acerca persiguiéndote y lanza círculo preciso a tus pies
  ziggsR, // Pin de ubicación que te sigue y suelta la Mega Bomba sobre tu trayectoria
  luxQ, // Disparo lineal preciso a tu trayectoria
  luxE, // Zona circular con slow lanzada directo a tu paso
  luxR, // Láser guía de 1.0s apuntado directo a ti -> rayo ancho instantáneo
  ezrealQ, // Proyectil lineal veloz y preciso
  ezrealR, // Boomerang / media luna veloz apuntada a tu posición
  malphiteR, // Se acerca rápido persiguiéndote y se lanza al instante con alcance fijo
}

/// Clase base abstracta (POO / Polimorfismo) que representa una habilidad enemiga activa.
/// Cada subclase implementa su propia geometría de fijación de blanco (`lockAimTarget`)
/// y su propia física de vuelo/colisión (`updateAndCheckCollision`), eliminando bloques `switch` gigantes.
abstract class ActiveSkillshot {
  final SkillshotType type;
  final SimChampion champion;
  final String championName;
  final String abilityKey;
  final Color primaryColor;
  final Color dangerColor;

  /// Si es true, el campeón aparece en el mapa y te persigue caminando rápido para ponerse a rango.
  /// Si es false, muestra el Pin Rojo 3D de Ubicación siguiéndote a distancia de disparo.
  final bool walksInDuringApproach;

  /// Posición actual del campeón enemigo mientras te persigue / lanza
  Offset casterPos;

  /// Distancia ideal a la que el campeón busca ponerse respecto al jugador antes de disparar
  final double engageDistance;

  /// Velocidad a la que el campeón enemigo te persigue durante la fase de acercamiento
  final double chaseSpeed;

  /// Alcance máximo FIJO de la habilidad desde `casterPos` en el momento de disparar.
  final double maxCastRange;

  /// Distancia real que recorrerá este disparo (siempre `<= maxCastRange`)
  double actualFlightDistance;

  /// Posición de origen del proyectil y destino (limitado por `maxCastRange`)
  Offset origin;
  Offset target;
  Offset direction;

  /// Duración máxima de la fase de acercamiento antes de lanzar
  final double approachDuration;

  /// Tiempos y dimensiones (compactos para el campo amplio)
  final double castDuration;
  final double travelSpeed;
  final double radius;
  final double outerRadius;
  final double lingerDuration;
  final double damage;
  final bool appliesKnockup;
  final bool appliesSlow;

  double elapsed = 0.0;
  Offset currentPos;
  bool hasLockedAim = false;
  bool hasImpacted = false;
  bool hasDealtDamage = false;
  bool countedAsDodged = false;

  double? playerReactionMs;

  ActiveSkillshot({
    required this.type,
    required this.champion,
    required this.championName,
    required this.abilityKey,
    required this.primaryColor,
    required this.dangerColor,
    required this.walksInDuringApproach,
    required this.casterPos,
    required this.engageDistance,
    required this.chaseSpeed,
    required this.maxCastRange,
    required this.origin,
    required this.target,
    required this.direction,
    required this.approachDuration,
    required this.castDuration,
    required this.travelSpeed,
    required this.radius,
    this.outerRadius = 0.0,
    this.lingerDuration = 0.24,
    required this.damage,
    this.appliesKnockup = false,
    this.appliesSlow = false,
  })  : currentPos = origin,
        actualFlightDistance = maxCastRange;

  /// Fase 1: El campeón se está acercando activamente hacia ti
  bool get isApproaching => elapsed < approachDuration;

  double get approachProgress =>
      approachDuration <= 0 ? 1.0 : (elapsed / approachDuration).clamp(0.0, 1.0);

  /// Tiempo transcurrido desde que terminó de acercarse y empezó a castear la habilidad
  double get activeAbilityElapsed => math.max(0.0, elapsed - approachDuration);

  /// Fase 2: Canalizando la habilidad
  bool get isCasting =>
      !isApproaching && activeAbilityElapsed < castDuration;

  double get castProgress =>
      castDuration <= 0 ? 1.0 : (activeAbilityElapsed / castDuration).clamp(0.0, 1.0);

  /// Define polimórficamente cómo se fijan `origin`, `target` y `actualFlightDistance`
  /// cuando concluye la fase de acercamiento.
  void lockAimTarget(Offset clampedTarget, Offset dir);

  /// Actualiza la posición/impacto de la habilidad y devuelve `true` cuando debe eliminarse.
  bool updateAndCheckCollision({
    required Offset playerPos,
    required double playerHitboxRadius,
    required void Function(ActiveSkillshot skillshot, double damageAmount) onApplyDamage,
    required void Function(double durationSeconds) onApplySlow,
    required double Function(Offset p, Offset a, Offset b) distancePointToSegment,
  });
}

/// Subclase 1: Habilidad AoE circular en el suelo (ej. Cho'Gath Q, Ziggs R).
class GroundAoeSkillshot extends ActiveSkillshot {
  GroundAoeSkillshot({
    required super.type,
    required super.champion,
    required super.championName,
    required super.abilityKey,
    required super.primaryColor,
    required super.dangerColor,
    required super.walksInDuringApproach,
    required super.casterPos,
    required super.engageDistance,
    required super.chaseSpeed,
    required super.maxCastRange,
    required super.origin,
    required super.target,
    required super.direction,
    required super.approachDuration,
    required super.castDuration,
    required super.radius,
    super.outerRadius = 0.0,
    super.lingerDuration = 0.24,
    required super.damage,
    super.appliesKnockup = false,
  }) : super(travelSpeed: 0);

  @override
  void lockAimTarget(Offset clampedTarget, Offset dir) {
    origin = clampedTarget;
    target = clampedTarget;
    actualFlightDistance = 0;
  }

  @override
  bool updateAndCheckCollision({
    required Offset playerPos,
    required double playerHitboxRadius,
    required void Function(ActiveSkillshot skillshot, double damageAmount) onApplyDamage,
    required void Function(double durationSeconds) onApplySlow,
    required double Function(Offset p, Offset a, Offset b) distancePointToSegment,
  }) {
    final double activeTime = activeAbilityElapsed;
    if (activeTime >= castDuration && !hasImpacted) {
      hasImpacted = true;
      final double dist = (playerPos - target).distance;
      if (dist <= (radius + playerHitboxRadius * 0.62)) {
        onApplyDamage(this, damage);
      } else if (outerRadius > 0 && dist <= (outerRadius + playerHitboxRadius * 0.55)) {
        onApplyDamage(this, (damage * 0.65).roundToDouble());
      }
    }
    return activeTime >= (castDuration + lingerDuration);
  }
}

/// Subclase 2: Rayo láser lineal instantáneo tras canalización (ej. Lux R).
class LaserBeamSkillshot extends ActiveSkillshot {
  LaserBeamSkillshot({
    required super.type,
    required super.champion,
    required super.championName,
    required super.abilityKey,
    required super.primaryColor,
    required super.dangerColor,
    required super.walksInDuringApproach,
    required super.casterPos,
    required super.engageDistance,
    required super.chaseSpeed,
    required super.maxCastRange,
    required super.origin,
    required super.target,
    required super.direction,
    required super.approachDuration,
    required super.castDuration,
    required super.radius,
    super.lingerDuration = 0.25,
    required super.damage,
  }) : super(travelSpeed: 0);

  @override
  void lockAimTarget(Offset clampedTarget, Offset dir) {
    target = casterPos + dir * maxCastRange;
    actualFlightDistance = maxCastRange;
  }

  @override
  bool updateAndCheckCollision({
    required Offset playerPos,
    required double playerHitboxRadius,
    required void Function(ActiveSkillshot skillshot, double damageAmount) onApplyDamage,
    required void Function(double durationSeconds) onApplySlow,
    required double Function(Offset p, Offset a, Offset b) distancePointToSegment,
  }) {
    final double activeTime = activeAbilityElapsed;
    if (activeTime >= castDuration && !hasImpacted) {
      hasImpacted = true;
      final double perpDist = distancePointToSegment(playerPos, origin, target);
      if (perpDist <= (radius + playerHitboxRadius * 0.62)) {
        onApplyDamage(this, damage);
      }
    }
    return activeTime >= (castDuration + lingerDuration);
  }
}

/// Subclase 3: Proyectil que vuela hasta una zona objetivo, ralentiza y explota (ej. Lux E).
class ZoneProjectileSkillshot extends ActiveSkillshot {
  ZoneProjectileSkillshot({
    required super.type,
    required super.champion,
    required super.championName,
    required super.abilityKey,
    required super.primaryColor,
    required super.dangerColor,
    required super.walksInDuringApproach,
    required super.casterPos,
    required super.engageDistance,
    required super.chaseSpeed,
    required super.maxCastRange,
    required super.origin,
    required super.target,
    required super.direction,
    required super.approachDuration,
    required super.castDuration,
    required super.travelSpeed,
    required super.radius,
    super.lingerDuration = 0.35,
    required super.damage,
    super.appliesSlow = true,
  });

  @override
  void lockAimTarget(Offset clampedTarget, Offset dir) {
    target = clampedTarget;
    actualFlightDistance = math.max(40.0, (clampedTarget - casterPos).distance);
  }

  @override
  bool updateAndCheckCollision({
    required Offset playerPos,
    required double playerHitboxRadius,
    required void Function(ActiveSkillshot skillshot, double damageAmount) onApplyDamage,
    required void Function(double durationSeconds) onApplySlow,
    required double Function(Offset p, Offset a, Offset b) distancePointToSegment,
  }) {
    final double activeTime = activeAbilityElapsed;
    if (activeTime < castDuration) return false;
    final double flightTime = activeTime - castDuration;
    final double flightDuration =
        travelSpeed > 0 ? (actualFlightDistance / travelSpeed) : 0.0;

    if (flightTime < flightDuration) {
      currentPos = origin + direction * (travelSpeed * flightTime);
    } else {
      currentPos = target;
      final double dist = (playerPos - target).distance;
      if (dist <= radius + playerHitboxRadius * 0.55) {
        onApplySlow(0.25);
      }
      if (flightTime >= flightDuration + lingerDuration && !hasImpacted) {
        hasImpacted = true;
        if (dist <= (radius + playerHitboxRadius * 0.62)) {
          onApplyDamage(this, damage);
        }
        return true;
      }
    }
    return false;
  }
}

/// Subclase 4: Proyectil lineal directo (ej. Lux Q, Ezreal Q, Ezreal R).
class LinearProjectileSkillshot extends ActiveSkillshot {
  final bool piercesTargets;

  LinearProjectileSkillshot({
    required super.type,
    required super.champion,
    required super.championName,
    required super.abilityKey,
    required super.primaryColor,
    required super.dangerColor,
    required super.walksInDuringApproach,
    required super.casterPos,
    required super.engageDistance,
    required super.chaseSpeed,
    required super.maxCastRange,
    required super.origin,
    required super.target,
    required super.direction,
    required super.approachDuration,
    required super.castDuration,
    required super.travelSpeed,
    required super.radius,
    required super.damage,
    super.appliesKnockup = false,
    this.piercesTargets = false,
  });

  @override
  void lockAimTarget(Offset clampedTarget, Offset dir) {
    target = casterPos + dir * maxCastRange;
    actualFlightDistance = maxCastRange;
  }

  @override
  bool updateAndCheckCollision({
    required Offset playerPos,
    required double playerHitboxRadius,
    required void Function(ActiveSkillshot skillshot, double damageAmount) onApplyDamage,
    required void Function(double durationSeconds) onApplySlow,
    required double Function(Offset p, Offset a, Offset b) distancePointToSegment,
  }) {
    final double activeTime = activeAbilityElapsed;
    if (activeTime < castDuration) return false;
    final double flightTime = activeTime - castDuration;
    final double travelled = travelSpeed * flightTime;
    currentPos = origin + direction * travelled;

    if (!hasDealtDamage) {
      final double dist = (playerPos - currentPos).distance;
      if (dist <= (radius + playerHitboxRadius * 0.62)) {
        hasImpacted = true;
        onApplyDamage(this, damage);
        if (!piercesTargets) {
          return true;
        }
      }
    }
    return travelled >= actualFlightDistance;
  }
}

/// Subclase 5: Embestida imparable de cuerpo entero hacia un punto (ej. Malphite R).
class DashImpactSkillshot extends ActiveSkillshot {
  DashImpactSkillshot({
    required super.type,
    required super.champion,
    required super.championName,
    required super.abilityKey,
    required super.primaryColor,
    required super.dangerColor,
    required super.walksInDuringApproach,
    required super.casterPos,
    required super.engageDistance,
    required super.chaseSpeed,
    required super.maxCastRange,
    required super.origin,
    required super.target,
    required super.direction,
    required super.approachDuration,
    required super.castDuration,
    required super.travelSpeed,
    required super.radius,
    super.lingerDuration = 0.24,
    required super.damage,
    super.appliesKnockup = true,
  });

  @override
  void lockAimTarget(Offset clampedTarget, Offset dir) {
    target = clampedTarget;
    actualFlightDistance = math.max(40.0, (clampedTarget - casterPos).distance);
  }

  @override
  bool updateAndCheckCollision({
    required Offset playerPos,
    required double playerHitboxRadius,
    required void Function(ActiveSkillshot skillshot, double damageAmount) onApplyDamage,
    required void Function(double durationSeconds) onApplySlow,
    required double Function(Offset p, Offset a, Offset b) distancePointToSegment,
  }) {
    final double activeTime = activeAbilityElapsed;
    if (activeTime < castDuration) return false;
    final double flightTime = activeTime - castDuration;
    final double travelled = travelSpeed * flightTime;

    if (travelled < actualFlightDistance) {
      currentPos = origin + direction * travelled;
      // Malphite también impacta si te arrolla en medio de su salto
      if (!hasDealtDamage) {
        final double distInFlight = (playerPos - currentPos).distance;
        if (distInFlight <= (radius * 0.75 + playerHitboxRadius * 0.5)) {
          hasImpacted = true;
          onApplyDamage(this, damage);
        }
      }
    } else {
      currentPos = target;
      if (!hasImpacted) {
        hasImpacted = true;
        final double dist = (playerPos - target).distance;
        if (dist <= (radius + playerHitboxRadius * 0.62)) {
          onApplyDamage(this, damage);
        }
      }
    }

    final double totalFlight =
        travelSpeed > 0 ? (actualFlightDistance / travelSpeed) : 0.0;
    return flightTime >= (totalFlight + lingerDuration);
  }
}

/// Fábrica Orientada a Objetos (Factory Pattern) que instancia la subclase correcta de `ActiveSkillshot`.
class SkillshotFactory {
  SkillshotFactory._();

  static ActiveSkillshot create({
    required SkillshotType type,
    required Offset playerPos,
    required Offset dirFromPlayer,
    required DodgeDifficulty difficulty,
    required double speedMult,
    required Offset Function(Offset) clampToWorld,
    required Offset Function(Offset) normalize,
  }) {
    final bool isEasy = difficulty == DodgeDifficulty.easy;

    switch (type) {
      case SkillshotType.malphiteR:
        final Offset spawnPos = clampToWorld(playerPos + dirFromPlayer * 470.0);
        return DashImpactSkillshot(
          type: SkillshotType.malphiteR,
          champion: SimChampion.malphite,
          championName: 'Malphite',
          abilityKey: 'R',
          primaryColor: const Color(0xFFD97706),
          dangerColor: const Color(0xFFEF4444),
          walksInDuringApproach: true,
          casterPos: spawnPos,
          engageDistance: 255.0,
          chaseSpeed: 580.0,
          maxCastRange: 380.0,
          origin: spawnPos,
          target: playerPos,
          direction: normalize(playerPos - spawnPos),
          approachDuration: isEasy ? 0.88 : 0.68,
          castDuration: 0.07,
          travelSpeed: 1580.0 * speedMult,
          radius: 148.0,
          lingerDuration: 0.24,
          damage: 225,
          appliesKnockup: true,
        );

      case SkillshotType.chogathQ:
        final Offset spawnPos = clampToWorld(playerPos + dirFromPlayer * 480.0);
        return GroundAoeSkillshot(
          type: SkillshotType.chogathQ,
          champion: SimChampion.chogath,
          championName: "Cho'Gath",
          abilityKey: 'Q',
          primaryColor: const Color(0xFFA855F7),
          dangerColor: const Color(0xFFEF4444),
          walksInDuringApproach: true,
          casterPos: spawnPos,
          engageDistance: 280.0,
          chaseSpeed: 540.0,
          maxCastRange: 390.0,
          origin: playerPos,
          target: playerPos,
          direction: normalize(playerPos - spawnPos),
          approachDuration: isEasy ? 0.90 : 0.70,
          castDuration: 0.88,
          radius: 145.0,
          damage: 185,
          appliesKnockup: true,
        );

      case SkillshotType.ziggsR:
        final Offset spawnPos = clampToWorld(playerPos + dirFromPlayer * 520.0);
        return GroundAoeSkillshot(
          type: SkillshotType.ziggsR,
          champion: SimChampion.ziggs,
          championName: 'Ziggs',
          abilityKey: 'R',
          primaryColor: const Color(0xFFF97316),
          dangerColor: const Color(0xFFEF4444),
          walksInDuringApproach: false,
          casterPos: spawnPos,
          engageDistance: 380.0,
          chaseSpeed: 550.0,
          maxCastRange: 580.0,
          origin: playerPos,
          target: playerPos,
          direction: normalize(playerPos - spawnPos),
          approachDuration: isEasy ? 0.85 : 0.65,
          castDuration: 1.15,
          radius: 140.0,
          outerRadius: 260.0,
          damage: 215,
        );

      case SkillshotType.luxQ:
        final Offset spawnPos = clampToWorld(playerPos + dirFromPlayer * 480.0);
        return LinearProjectileSkillshot(
          type: SkillshotType.luxQ,
          champion: SimChampion.lux,
          championName: 'Lux',
          abilityKey: 'Q',
          primaryColor: const Color(0xFFFDE047),
          dangerColor: const Color(0xFFF59E0B),
          walksInDuringApproach: false,
          casterPos: spawnPos,
          engageDistance: 340.0,
          chaseSpeed: 540.0,
          maxCastRange: 820.0,
          origin: spawnPos,
          target: playerPos,
          direction: normalize(playerPos - spawnPos),
          approachDuration: isEasy ? 0.80 : 0.60,
          castDuration: 0.18,
          travelSpeed: 1220.0 * speedMult,
          radius: 48.0,
          damage: 165,
          appliesKnockup: true,
          piercesTargets: false,
        );

      case SkillshotType.luxE:
        final Offset spawnPos = clampToWorld(playerPos + dirFromPlayer * 470.0);
        return ZoneProjectileSkillshot(
          type: SkillshotType.luxE,
          champion: SimChampion.lux,
          championName: 'Lux',
          abilityKey: 'E',
          primaryColor: const Color(0xFFFFEF8A),
          dangerColor: const Color(0xFFEC4899),
          walksInDuringApproach: false,
          casterPos: spawnPos,
          engageDistance: 310.0,
          chaseSpeed: 550.0,
          maxCastRange: 440.0,
          origin: spawnPos,
          target: playerPos,
          direction: normalize(playerPos - spawnPos),
          approachDuration: isEasy ? 0.80 : 0.60,
          castDuration: 0.16,
          travelSpeed: 1280.0 * speedMult,
          radius: 165.0,
          lingerDuration: 0.35,
          damage: 175,
          appliesSlow: true,
        );

      case SkillshotType.luxR:
        final Offset spawnPos = clampToWorld(playerPos + dirFromPlayer * 520.0);
        return LaserBeamSkillshot(
          type: SkillshotType.luxR,
          champion: SimChampion.lux,
          championName: 'Lux',
          abilityKey: 'R',
          primaryColor: const Color(0xFFF43F5E),
          dangerColor: const Color(0xFFFF0055),
          walksInDuringApproach: false,
          casterPos: spawnPos,
          engageDistance: 400.0,
          chaseSpeed: 540.0,
          maxCastRange: 1300.0,
          origin: spawnPos,
          target: playerPos,
          direction: normalize(playerPos - spawnPos),
          approachDuration: isEasy ? 0.75 : 0.55,
          castDuration: 0.88,
          radius: 68.0,
          lingerDuration: 0.25,
          damage: 235,
        );

      case SkillshotType.ezrealQ:
        final Offset spawnPos = clampToWorld(playerPos + dirFromPlayer * 480.0);
        return LinearProjectileSkillshot(
          type: SkillshotType.ezrealQ,
          champion: SimChampion.ezreal,
          championName: 'Ezreal',
          abilityKey: 'Q',
          primaryColor: const Color(0xFF38BDF8),
          dangerColor: const Color(0xFF0284C7),
          walksInDuringApproach: false,
          casterPos: spawnPos,
          engageDistance: 350.0,
          chaseSpeed: 560.0,
          maxCastRange: 800.0,
          origin: spawnPos,
          target: playerPos,
          direction: normalize(playerPos - spawnPos),
          approachDuration: isEasy ? 0.78 : 0.58,
          castDuration: 0.16,
          travelSpeed: 1720.0 * speedMult,
          radius: 44.0,
          damage: 160,
          piercesTargets: false,
        );

      case SkillshotType.ezrealR:
        final Offset spawnPos = clampToWorld(playerPos + dirFromPlayer * 520.0);
        return LinearProjectileSkillshot(
          type: SkillshotType.ezrealR,
          champion: SimChampion.ezreal,
          championName: 'Ezreal',
          abilityKey: 'R',
          primaryColor: const Color(0xFFFACC15),
          dangerColor: const Color(0xFFF97316),
          walksInDuringApproach: false,
          casterPos: spawnPos,
          engageDistance: 410.0,
          chaseSpeed: 540.0,
          maxCastRange: 1400.0,
          origin: spawnPos,
          target: playerPos,
          direction: normalize(playerPos - spawnPos),
          approachDuration: isEasy ? 0.75 : 0.55,
          castDuration: 0.85,
          travelSpeed: 1680.0 * speedMult,
          radius: 108.0,
          damage: 210,
          piercesTargets: true,
        );
    }
  }
}

/// Ataque secundario en cola para Combos en niveles Medio y Difícil
class QueuedComboAttack {
  double delayRemaining;
  final SkillshotType? forcedType;
  final double angleOffsetRad;

  QueuedComboAttack({
    required this.delayRemaining,
    this.forcedType,
    required this.angleOffsetRad,
  });
}

/// Efecto visual flotante
class FloatingCombatText {
  String text;
  Offset position;
  Color color;
  double elapsed = 0.0;
  final double duration;

  FloatingCombatText({
    required this.text,
    required this.position,
    required this.color,
    this.duration = 0.9,
  });
}
