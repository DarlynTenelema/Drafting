import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models/dodge_models.dart';
export '../core/models/dodge_models.dart';

/// Motor del juego desacoplado del árbol de Widgets (Zero-Rebuild Game Loop).
class DodgeGameEngine extends ChangeNotifier {
  DodgeDifficulty difficulty = DodgeDifficulty.easy;

  // Filtro de campeones activos (todos activos por defecto)
  final Set<SimChampion> enabledChampions = {
    SimChampion.lux,
    SimChampion.ezreal,
    SimChampion.chogath,
    SimChampion.ziggs,
    SimChampion.malphite,
  };

  // Modo Práctica Infinita (Inmortal: la vida no baja de 50 HP)
  bool immortalPracticeMode = false;

  // Sensibilidad del Joystick
  double joystickSensitivity = 1.0;

  // Conservamos el campo amplio y estético que te gustó (2800 x 1750, cámara en 2150)
  static const double worldWidth = 2800.0;
  static const double worldHeight = 1750.0;

  // Tamaño compacto del jugador (44u)
  static const double playerHitboxRadius = 44.0;
  static const double baseMoveSpeed = 405.0;

  Offset playerPos = Offset.zero;
  Offset joystickVector = Offset.zero;
  Offset lastFacingDir = const Offset(1, 0);

  double maxHp = 1000.0;
  double currentHp = 1000.0;

  // Estados alterados
  double knockupTimer = 0.0;
  double slowTimer = 0.0;
  double sprintTimer = 0.0;
  double hitFlashTimer = 0.0;

  // Cooldown del FLASH (Destello): 10.0 segundos o 5 habilidades esquivadas
  static const double flashMaxCooldown = 10.0;
  static const double sprintMaxCooldown = 7.5;
  double flashCooldown = 0.0;
  double sprintCooldown = 0.0;
  int dodgesSinceLastFlash = 0;

  int _totalSpawnedCount = 0;

  // Efecto visual de Flash
  Offset? lastFlashOrigin;
  double flashVfxTimer = 0.0;

  // Métricas de la partida actual
  double survivalTime = 0.0;
  int dodgedCount = 0;
  int hitsTaken = 0;
  int currentStreak = 0;
  int bestStreak = 0;
  final List<double> reactionTimesMs = [];

  // Récords históricos guardados en SharedPreferences por dificultad
  double recordSurvivalTime = 0.0;
  int recordDodgedCount = 0;
  int recordBestStreak = 0;
  int recordBestReactionMs = 0;
  bool achievedNewRecord = false;

  // Control del Spawner
  double spawnTimer = 0.45;
  bool isRunning = true;
  bool isPaused = false;
  bool isGameOver = false;

  final List<ActiveSkillshot> skillshots = [];
  final List<QueuedComboAttack> _comboQueue = [];
  final List<FloatingCombatText> floatingTexts = [];
  final math.Random _rng = math.Random();

  Offset _prevJoystickDir = Offset.zero;

  /// Intervalo entre apariciones de ataques (emocionante y constante):
  double get spawnInterval {
    switch (difficulty) {
      case DodgeDifficulty.easy:
        return 1.85; // Cada 1.85s un ataque preciso buscando al jugador
      case DodgeDifficulty.medium:
        return 1.35; // Más rápido + Combos Dobles
      case DodgeDifficulty.hard:
        return 0.95; // Intenso + Crossfire
    }
  }

  /// Multiplicador de velocidad de proyectiles (rápidos y peligrosos si no reaccionas)
  double get projectileSpeedMultiplier {
    switch (difficulty) {
      case DodgeDifficulty.easy:
        return 1.02;
      case DodgeDifficulty.medium:
        return 1.15;
      case DodgeDifficulty.hard:
        return 1.28;
    }
  }

  int get averageReactionMs {
    if (reactionTimesMs.isEmpty) return 0;
    final sum = reactionTimesMs.fold<double>(0.0, (a, b) => a + b);
    return (sum / reactionTimesMs.length).round();
  }

  String get _diffKey => difficulty.name;

  Future<void> loadRecords() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      recordSurvivalTime = prefs.getDouble('dodge_best_time_$_diffKey') ?? 0.0;
      recordDodgedCount = prefs.getInt('dodge_best_dodges_$_diffKey') ?? 0;
      recordBestStreak = prefs.getInt('dodge_best_streak_$_diffKey') ?? 0;
      recordBestReactionMs = prefs.getInt('dodge_best_ms_$_diffKey') ?? 0;
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveRecordsIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      bool isNew = false;

      if (survivalTime > recordSurvivalTime) {
        recordSurvivalTime = survivalTime;
        await prefs.setDouble('dodge_best_time_$_diffKey', recordSurvivalTime);
        isNew = true;
      }
      if (dodgedCount > recordDodgedCount) {
        recordDodgedCount = dodgedCount;
        await prefs.setInt('dodge_best_dodges_$_diffKey', recordDodgedCount);
        isNew = true;
      }
      if (bestStreak > recordBestStreak) {
        recordBestStreak = bestStreak;
        await prefs.setInt('dodge_best_streak_$_diffKey', recordBestStreak);
      }
      final int avgMs = averageReactionMs;
      if (avgMs > 0 && (recordBestReactionMs == 0 || avgMs < recordBestReactionMs)) {
        recordBestReactionMs = avgMs;
        await prefs.setInt('dodge_best_ms_$_diffKey', recordBestReactionMs);
      }
      if (isNew) {
        achievedNewRecord = true;
        notifyListeners();
      }
    } catch (_) {}
  }

  void togglePause() {
    if (isGameOver) return;
    isPaused = !isPaused;
    notifyListeners();
  }

  void toggleChampionFilter(SimChampion champ) {
    if (enabledChampions.contains(champ)) {
      if (enabledChampions.length > 1) {
        enabledChampions.remove(champ);
      }
    } else {
      enabledChampions.add(champ);
    }
    notifyListeners();
  }

  void resetGame({DodgeDifficulty? newDifficulty}) {
    if (newDifficulty != null) {
      difficulty = newDifficulty;
      loadRecords();
    }
    playerPos = Offset.zero;
    joystickVector = Offset.zero;
    lastFacingDir = const Offset(1, 0);
    currentHp = maxHp;
    knockupTimer = 0.0;
    slowTimer = 0.0;
    sprintTimer = 0.0;
    hitFlashTimer = 0.0;
    flashCooldown = 0.0;
    sprintCooldown = 0.0;
    dodgesSinceLastFlash = 0;
    _totalSpawnedCount = 0;
    lastFlashOrigin = null;
    flashVfxTimer = 0.0;

    survivalTime = 0.0;
    dodgedCount = 0;
    hitsTaken = 0;
    currentStreak = 0;
    bestStreak = 0;
    achievedNewRecord = false;
    reactionTimesMs.clear();

    skillshots.clear();
    _comboQueue.clear();
    floatingTexts.clear();
    spawnTimer = 0.45;
    isGameOver = false;
    isPaused = false;
    isRunning = true;
    notifyListeners();
  }

  void setJoystick(Offset deltaNormalized) {
    final Offset scaled = Offset(
      (deltaNormalized.dx * joystickSensitivity).clamp(-1.0, 1.0),
      (deltaNormalized.dy * joystickSensitivity).clamp(-1.0, 1.0),
    );
    final double mag = scaled.distance;
    final Offset finalVec = mag > 1.0 ? (scaled / mag) : scaled;

    if (finalVec.distance > 0.25) {
      final dir = finalVec / finalVec.distance;
      final dot = dir.dx * _prevJoystickDir.dx + dir.dy * _prevJoystickDir.dy;
      if (_prevJoystickDir == Offset.zero || dot < 0.7) {
        for (final s in skillshots) {
          if (!s.isApproaching &&
              s.playerReactionMs == null &&
              s.activeAbilityElapsed > 0.04 &&
              s.activeAbilityElapsed < 0.95) {
            s.playerReactionMs = s.activeAbilityElapsed * 1000.0;
            reactionTimesMs.add(s.playerReactionMs!);
            if (reactionTimesMs.length > 35) {
              reactionTimesMs.removeAt(0);
            }
          }
        }
        _prevJoystickDir = dir;
      }
      lastFacingDir = dir;
    } else {
      _prevJoystickDir = Offset.zero;
    }
    joystickVector = finalVec;
  }

  /// Hechizo Principal: FLASH (Destello) - Enfriamiento de 10 segundos o 5 habilidades esquivadas.
  bool castFlash() {
    if (isGameOver || isPaused || !isRunning || flashCooldown > 0 || knockupTimer > 0) {
      return false;
    }
    HapticFeedback.lightImpact();
    flashCooldown = flashMaxCooldown;
    dodgesSinceLastFlash = 0;
    lastFlashOrigin = playerPos;
    flashVfxTimer = 0.45;

    final Offset dir = joystickVector.distance > 0.15
        ? (joystickVector / joystickVector.distance)
        : lastFacingDir;

    const double flashDistance = 350.0;
    final Offset next = playerPos + dir * flashDistance;
    playerPos = Offset(
      next.dx.clamp(-worldWidth / 2 + 80, worldWidth / 2 - 80),
      next.dy.clamp(-worldHeight / 2 + 80, worldHeight / 2 - 80),
    );

    for (final s in skillshots) {
      if (!s.isApproaching && s.playerReactionMs == null && s.activeAbilityElapsed > 0.03) {
        s.playerReactionMs = s.activeAbilityElapsed * 1000.0;
        reactionTimesMs.add(s.playerReactionMs!);
      }
    }

    floatingTexts.add(
      FloatingCombatText(
        text: '¡FLASH!',
        position: playerPos + const Offset(0, -65),
        color: const Color(0xFFFDE047),
      ),
    );
    notifyListeners();
    return true;
  }

  /// Hechizo 2: Sprint (+35% Velocidad por 3s)
  bool castSprint() {
    if (isGameOver || isPaused || !isRunning || sprintCooldown > 0) {
      return false;
    }
    HapticFeedback.selectionClick();
    sprintCooldown = sprintMaxCooldown;
    sprintTimer = 3.0;
    floatingTexts.add(
      FloatingCombatText(
        text: '+35% VELOCIDAD',
        position: playerPos + const Offset(0, -65),
        color: const Color(0xFF38BDF8),
      ),
    );
    notifyListeners();
    return true;
  }

  void update(double dt) {
    if (!isRunning || isPaused || isGameOver) return;

    final double safeDt = dt.clamp(0.0, 0.05);
    survivalTime += safeDt;

    // 1. Actualizar temporizadores de estado y cooldowns
    if (knockupTimer > 0) knockupTimer = math.max(0.0, knockupTimer - safeDt);
    if (slowTimer > 0) slowTimer = math.max(0.0, slowTimer - safeDt);
    if (sprintTimer > 0) sprintTimer = math.max(0.0, sprintTimer - safeDt);
    if (hitFlashTimer > 0) hitFlashTimer = math.max(0.0, hitFlashTimer - safeDt);
    if (flashVfxTimer > 0) flashVfxTimer = math.max(0.0, flashVfxTimer - safeDt);
    if (flashCooldown > 0) flashCooldown = math.max(0.0, flashCooldown - safeDt);
    if (sprintCooldown > 0) sprintCooldown = math.max(0.0, sprintCooldown - safeDt);

    // 2. Movimiento del jugador
    double currentMoveSpeed = baseMoveSpeed;
    if (sprintTimer > 0) currentMoveSpeed *= 1.35;
    if (slowTimer > 0) currentMoveSpeed *= 0.70;

    if (knockupTimer <= 0 && joystickVector.distance > 0.05) {
      final Offset velocity = joystickVector * currentMoveSpeed;
      final Offset nextPos = playerPos + velocity * safeDt;
      playerPos = Offset(
        nextPos.dx.clamp(-worldWidth / 2 + 70, worldWidth / 2 - 70),
        nextPos.dy.clamp(-worldHeight / 2 + 70, worldHeight / 2 - 70),
      );
    }

    // 3. Cola de ataques secundarios en combo (para Medio y Difícil)
    for (int i = _comboQueue.length - 1; i >= 0; i--) {
      final q = _comboQueue[i];
      q.delayRemaining -= safeDt;
      if (q.delayRemaining <= 0) {
        _spawnSingleAttack(
          currentMoveSpeed,
          forcedType: q.forcedType,
          angleOffsetRad: q.angleOffsetRad,
        );
        _comboQueue.removeAt(i);
      }
    }

    // 4. Spawner principal de campeones enemigos
    spawnTimer -= safeDt;
    if (spawnTimer <= 0) {
      spawnTimer = spawnInterval;
      _triggerAttackWave(currentMoveSpeed);
    }

    // 5. Actualizar cada habilidad activa
    for (int i = skillshots.length - 1; i >= 0; i--) {
      final s = skillshots[i];
      s.elapsed += safeDt;

      // FASE 1: PERSECUCIÓN ACTIVA
      // Mientras el campeón se acerca, NO se queda atrás donde estabas antes:
      // se mueve activamente persiguiendo tu posición actual (`playerPos`) hasta ponerse a rango (`engageDistance`).
      if (s.isApproaching) {
        _updateActiveChase(s, safeDt);
        continue;
      }

      // Al terminar el acercamiento, el campeón ya está encima/cerca de ti y dispara de inmediato
      // calculando hacia dónde te estás moviendo (con límite fijo `maxCastRange`).
      if (!s.hasLockedAim) {
        s.hasLockedAim = true;
        _lockPrecisionAimWithFixedMaxRange(s, currentMoveSpeed);
      }

      final bool shouldRemove = _updateAndCheckActiveSkillshot(s, safeDt);
      if (shouldRemove) {
        if (!s.hasDealtDamage && !s.countedAsDodged) {
          s.countedAsDodged = true;
          dodgedCount++;
          currentStreak++;
          if (currentStreak > bestStreak) bestStreak = currentStreak;

          if (flashCooldown > 0) {
            dodgesSinceLastFlash++;
            if (dodgesSinceLastFlash >= 5) {
              flashCooldown = 0.0;
              dodgesSinceLastFlash = 0;
              floatingTexts.add(
                FloatingCombatText(
                  text: '¡FLASH LISTO!',
                  position: playerPos + const Offset(0, -90),
                  color: const Color(0xFFFACC15),
                ),
              );
            }
          }

          floatingTexts.add(
            FloatingCombatText(
              text: currentStreak > 2 ? '¡ESQUIVADO x$currentStreak!' : '¡ESQUIVADO!',
              position: playerPos + const Offset(0, -60),
              color: const Color(0xFF10B981),
            ),
          );
        }
        skillshots.removeAt(i);
      }
    }

    // 6. Actualizar textos flotantes
    for (int i = floatingTexts.length - 1; i >= 0; i--) {
      final ft = floatingTexts[i];
      ft.elapsed += safeDt;
      ft.position = ft.position.translate(0, -45 * safeDt);
      if (ft.elapsed >= ft.duration) {
        floatingTexts.removeAt(i);
      }
    }

    // 7. Regeneración moderada de vida
    if (currentHp < maxHp && currentHp > 0) {
      final double regenPerSec = difficulty == DodgeDifficulty.easy
          ? 8.0
          : (difficulty == DodgeDifficulty.medium ? 4.5 : 2.0);
      currentHp = math.min(maxHp, currentHp + regenPerSec * safeDt);
    }

    notifyListeners();
  }

  /// Hace que el campeón enemigo (ej. Malphite o Cho'Gath) o el Pin de Ubicación
  /// persiga activamente al jugador durante la fase de acercamiento para que nunca dispare lejos.
  void _updateActiveChase(ActiveSkillshot s, double dt) {
    final Offset toPlayer = playerPos - s.casterPos;
    final double dist = toPlayer.distance;
    if (dist <= 0.001) return;

    final Offset dirToPlayer = toPlayer / dist;

    if (dist > s.engageDistance) {
      // El campeón corre hacia el jugador más rápido que la velocidad base del jugador
      // para recortarle distancia y ponerse en rango real de ataque.
      final double step = math.min(dist - s.engageDistance, s.chaseSpeed * dt);
      s.casterPos = _clampToWorld(s.casterPos + dirToPlayer * step);
    } else if (!s.walksInDuringApproach && dist < s.engageDistance * 0.75) {
      // Si es un campeón de rango lejano (Ziggs/Lux R), mantiene su distancia táctica
      final double stepBack = (s.engageDistance * 0.75 - dist).clamp(0.0, s.chaseSpeed * dt);
      s.casterPos = _clampToWorld(s.casterPos - dirToPlayer * stepBack);
    }

    s.origin = s.casterPos;
    s.currentPos = s.casterPos;
    s.direction = _normalize(playerPos - s.casterPos);
  }

  List<SkillshotType> _getNonMalphitePool() {
    final List<SkillshotType> pool = [];
    if (enabledChampions.contains(SimChampion.lux)) {
      pool.addAll([SkillshotType.luxQ, SkillshotType.luxE, SkillshotType.luxR]);
    }
    if (enabledChampions.contains(SimChampion.ezreal)) {
      pool.addAll([SkillshotType.ezrealQ, SkillshotType.ezrealR]);
    }
    if (enabledChampions.contains(SimChampion.chogath)) {
      pool.add(SkillshotType.chogathQ);
    }
    if (enabledChampions.contains(SimChampion.ziggs)) {
      pool.add(SkillshotType.ziggsR);
    }
    if (pool.isEmpty) {
      pool.add(SkillshotType.malphiteR);
    }
    return pool;
  }

  void _triggerAttackWave(double playerSpeed) {
    _spawnSingleAttack(playerSpeed);

    // En Medio y Difícil, probabilidad de lanzar un segundo campeón en combo
    if (difficulty == DodgeDifficulty.easy) return;

    final double comboChance =
        difficulty == DodgeDifficulty.medium ? 0.35 : 0.55;
    if (_rng.nextDouble() < comboChance) {
      _comboQueue.add(
        QueuedComboAttack(
          delayRemaining: difficulty == DodgeDifficulty.medium ? 0.30 : 0.18,
          angleOffsetRad: math.pi / 2.2, // Ataque cruzado a ~80°
        ),
      );
    }
  }

  /// Spawnea un campeón que persigue al jugador y se lanza rápido sin perder tiempo.
  void _spawnSingleAttack(
    double playerSpeed, {
    SkillshotType? forcedType,
    double angleOffsetRad = 0.0,
  }) {
    _totalSpawnedCount++;

    SkillshotType chosen;
    if (forcedType != null) {
      chosen = forcedType;
    } else if (enabledChampions.contains(SimChampion.malphite) &&
        (_totalSpawnedCount % 5 == 0 ||
            _getNonMalphitePool().first == SkillshotType.malphiteR)) {
      chosen = SkillshotType.malphiteR;
    } else {
      final pool = _getNonMalphitePool();
      chosen = pool[_rng.nextInt(pool.length)];
    }

    // Si el jugador se está moviendo, hacemos que los campeones aparezcan preferentemente
    // por delante o en diagonal a su camino (para cortarle el paso y obligarlo a esquivar).
    double baseAngle;
    if (joystickVector.distance > 0.15) {
      final double moveAngle = math.atan2(joystickVector.dy, joystickVector.dx);
      baseAngle = moveAngle + (_rng.nextDouble() - 0.5) * 2.2;
    } else {
      baseAngle = _rng.nextDouble() * 2 * math.pi;
    }
    final double angle = baseAngle + angleOffsetRad;
    final Offset dirFromPlayer = Offset(math.cos(angle), math.sin(angle));

    skillshots.add(
      SkillshotFactory.create(
        type: chosen,
        playerPos: playerPos,
        dirFromPlayer: dirFromPlayer,
        difficulty: difficulty,
        speedMult: projectileSpeedMultiplier,
        clampToWorld: _clampToWorld,
        normalize: _normalize,
      ),
    );
  }

  /// Calcula la puntería con predicción inteligente (*Smart Lead Intercept*) en el instante
  /// en que el campeón termina de acercarse, manteniendo el límite de alcance fijo (`maxCastRange`).
  void _lockPrecisionAimWithFixedMaxRange(ActiveSkillshot s, double playerSpeed) {
    final Offset playerVel =
        joystickVector.distance > 0.05 ? joystickVector * playerSpeed : Offset.zero;
    final double currentDist = (playerPos - s.casterPos).distance;

    // Tiempo estimado en el que el golpe llegará a la posición del jugador
    double estimatedArrivalTime;
    if (s.travelSpeed > 0) {
      estimatedArrivalTime = s.castDuration + (currentDist / s.travelSpeed);
    } else {
      estimatedArrivalTime = s.castDuration;
    }

    // Factor de precisión: entre 0.45 y 0.95 del movimiento futuro del jugador,
    // de modo que si el jugador sigue caminando en línea recta o se queda quieto, ¡LE PEGA!
    // Tiene que reaccionar cambiando de dirección o usando Flash.
    final double minLead = difficulty == DodgeDifficulty.easy ? 0.35 : 0.55;
    final double maxLead = difficulty == DodgeDifficulty.easy
        ? 0.82
        : (difficulty == DodgeDifficulty.medium ? 0.96 : 1.05);
    final double leadFactor = minLead + _rng.nextDouble() * (maxLead - minLead);

    final Offset predictedPos = _clampToWorld(
      playerPos + playerVel * (estimatedArrivalTime * leadFactor),
    );

    final Offset vecToAim = predictedPos - s.casterPos;
    final double distToAim = vecToAim.distance;
    final Offset dir = _normalize(vecToAim);

    // Límite estricto del alcance máximo fijo (`maxCastRange`) desde donde el campeón se detuvo (`casterPos`)
    final double clampedDist = math.min(distToAim, s.maxCastRange);
    final Offset clampedTarget = _clampToWorld(s.casterPos + dir * clampedDist);

    s.origin = s.casterPos;
    s.currentPos = s.casterPos;
    s.direction = dir;
    s.lockAimTarget(clampedTarget, dir);
  }

  /// Actualiza polimórficamente la habilidad una vez que ya terminó la Fase 1 (acercamiento)
  bool _updateAndCheckActiveSkillshot(ActiveSkillshot s, double dt) {
    return s.updateAndCheckCollision(
      playerPos: playerPos,
      playerHitboxRadius: playerHitboxRadius,
      onApplyDamage: _applyDamageToPlayer,
      onApplySlow: (duration) => slowTimer = math.max(slowTimer, duration),
      distancePointToSegment: _distancePointToSegment,
    );
  }

  void _applyDamageToPlayer(ActiveSkillshot s, double dmg) {
    if (s.hasDealtDamage) return;
    s.hasDealtDamage = true;
    hitsTaken++;
    currentStreak = 0;

    if (immortalPracticeMode) {
      currentHp = math.max(50.0, currentHp - dmg);
    } else {
      currentHp = math.max(0.0, currentHp - dmg);
    }

    hitFlashTimer = 0.28;
    HapticFeedback.heavyImpact();

    if (s.appliesKnockup) {
      knockupTimer = 0.38;
    }
    if (s.appliesSlow) {
      slowTimer = 1.3;
    }

    floatingTexts.add(
      FloatingCombatText(
        text: '-${dmg.round()} (${s.championName} ${s.abilityKey})',
        position: playerPos + const Offset(0, -65),
        color: const Color(0xFFEF4444),
      ),
    );

    if (currentHp <= 0 && !immortalPracticeMode) {
      isGameOver = true;
      isRunning = false;
      _saveRecordsIfNeeded();
    }
  }

  Offset _clampToWorld(Offset p) {
    return Offset(
      p.dx.clamp(-worldWidth / 2 + 120, worldWidth / 2 - 120),
      p.dy.clamp(-worldHeight / 2 + 120, worldHeight / 2 - 120),
    );
  }

  Offset _normalize(Offset v) {
    final double d = v.distance;
    if (d < 0.0001) return const Offset(1, 0);
    return v / d;
  }

  double _distancePointToSegment(Offset p, Offset a, Offset b) {
    final Offset ab = b - a;
    final double lenSq = ab.dx * ab.dx + ab.dy * ab.dy;
    if (lenSq == 0) return (p - a).distance;
    final double t =
        (((p.dx - a.dx) * ab.dx + (p.dy - a.dy) * ab.dy) / lenSq).clamp(0.0, 1.0);
    final Offset projection = Offset(a.dx + t * ab.dx, a.dy + t * ab.dy);
    return (p - projection).distance;
  }
}

/// Pantalla del Simulador de Esquivo de Habilidades (Wild Rift Reflex Trainer).
class DodgeSimulatorScreen extends StatefulWidget {
  final String userName;
  final String? userPhotoUrl;
  final VoidCallback? onExit;

  const DodgeSimulatorScreen({
    super.key,
    required this.userName,
    this.userPhotoUrl,
    this.onExit,
  });

  @override
  State<DodgeSimulatorScreen> createState() => _DodgeSimulatorScreenState();
}

class _DodgeSimulatorScreenState extends State<DodgeSimulatorScreen>
    with SingleTickerProviderStateMixin {
  late final DodgeGameEngine _engine;
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  ui.Image? _avatarImage;
  final Map<SimChampion, ui.Image> _championImages = {};

  Offset? _joystickOrigin;
  Offset _joystickKnob = Offset.zero;
  static const double _joystickMaxRadius = 56.0;

  @override
  void initState() {
    super.initState();
    _engine = DodgeGameEngine();
    _engine.loadRecords();

    _loadAllChampionAssets();
    _loadUserAvatarImage();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    });

    _ticker = createTicker((Duration elapsed) {
      final double dt =
          (elapsed - _lastElapsed).inMicroseconds / Duration.microsecondsPerSecond;
      _lastElapsed = elapsed;
      if (dt > 0) {
        _engine.update(dt);
      }
    });
    _ticker.start();
  }

  Future<void> _loadAllChampionAssets() async {
    for (final champ in SimChampion.values) {
      try {
        final ByteData data = await rootBundle.load(champ.assetPath);
        final ui.Codec codec = await ui.instantiateImageCodec(
          data.buffer.asUint8List(),
          targetWidth: 128,
          targetHeight: 128,
        );
        final ui.FrameInfo frame = await codec.getNextFrame();
        if (mounted) {
          setState(() {
            _championImages[champ] = frame.image;
          });
        }
      } catch (e) {
        debugPrint('No se pudo cargar ícono ${champ.assetPath}: $e');
      }
    }
  }

  Future<void> _loadUserAvatarImage() async {
    final url = widget.userPhotoUrl;
    if (url == null || url.isEmpty) return;
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final codec = await ui.instantiateImageCodec(
          response.bodyBytes,
          targetWidth: 128,
          targetHeight: 128,
        );
        final frame = await codec.getNextFrame();
        if (mounted) {
          setState(() {
            _avatarImage = frame.image;
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _ticker.dispose();
    _engine.dispose();
    _avatarImage?.dispose();
    for (final img in _championImages.values) {
      img.dispose();
    }
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  void _onJoystickPanStart(DragStartDetails details) {
    _joystickOrigin = details.localPosition;
    _joystickKnob = details.localPosition;
    _engine.setJoystick(Offset.zero);
  }

  void _onJoystickPanUpdate(DragUpdateDetails details) {
    if (_joystickOrigin == null) return;
    final Offset delta = details.localPosition - _joystickOrigin!;
    final double dist = delta.distance;
    if (dist <= _joystickMaxRadius) {
      _joystickKnob = details.localPosition;
      _engine.setJoystick(delta / _joystickMaxRadius);
    } else {
      final Offset clamped = (delta / dist) * _joystickMaxRadius;
      _joystickKnob = _joystickOrigin! + clamped;
      _engine.setJoystick(delta / dist);
    }
  }

  void _onJoystickPanEnd(DragEndDetails details) {
    _joystickOrigin = null;
    _joystickKnob = Offset.zero;
    _engine.setJoystick(Offset.zero);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B131E),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final Size arenaSize = Size(constraints.maxWidth, constraints.maxHeight);
          return Stack(
            fit: StackFit.expand,
            children: [
              // 1. LIENZO DEL JUEGO (Conserva el tamaño estético y amplio de cámara 2150)
              RepaintBoundary(
                child: CustomPaint(
                  size: arenaSize,
                  painter: _DodgeArenaPainter(
                    engine: _engine,
                    userName: widget.userName,
                    avatarImage: _avatarImage,
                    championImages: _championImages,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),

              // 2. ZONA TÁCTIL DEL JOYSTICK (Mitad izquierda de la pantalla)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: constraints.maxWidth * 0.55,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: _onJoystickPanStart,
                  onPanUpdate: _onJoystickPanUpdate,
                  onPanEnd: _onJoystickPanEnd,
                  onPanCancel: () {
                    _joystickOrigin = null;
                    _joystickKnob = Offset.zero;
                    _engine.setJoystick(Offset.zero);
                  },
                  child: AnimatedBuilder(
                    animation: _engine,
                    builder: (context, _) {
                      return CustomPaint(
                        painter: _JoystickOverlayPainter(
                          origin: _joystickOrigin,
                          knob: _joystickKnob,
                          maxRadius: _joystickMaxRadius,
                        ),
                        child: const SizedBox.expand(),
                      );
                    },
                  ),
                ),
              ),

              // 3. HUD SUPERIOR ADAPTABLE
              Positioned(
                top: 8,
                left: 12,
                right: 12,
                child: SafeArea(
                  bottom: false,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          InkWell(
                            onTap: () {
                              if (widget.onExit != null) {
                                widget.onExit!();
                              } else {
                                Navigator.of(context).maybePop();
                              }
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F172A).withValues(alpha: 0.9),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: Colors.white24),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.arrow_back_ios_new_rounded,
                                      color: Colors.white, size: 13),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Salir',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          _buildDifficultySelector(),
                          InkWell(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              _engine.togglePause();
                            },
                            borderRadius: BorderRadius.circular(12),
                            child: AnimatedBuilder(
                              animation: _engine,
                              builder: (context, _) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                                  decoration: BoxDecoration(
                                    color: _engine.isPaused
                                        ? const Color(0xFF00E5FF).withValues(alpha: 0.25)
                                        : const Color(0xFF0F172A).withValues(alpha: 0.9),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _engine.isPaused
                                          ? const Color(0xFF00E5FF)
                                          : Colors.white24,
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        _engine.isPaused
                                            ? Icons.play_arrow_rounded
                                            : Icons.tune_rounded,
                                        color: const Color(0xFF00E5FF),
                                        size: 15,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Campeones (${_engine.enabledChampions.length}/5)',
                                        style: GoogleFonts.outfit(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 11,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),

                      AnimatedBuilder(
                        animation: _engine,
                        builder: (context, _) {
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: const Color(0xFF0F172A).withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: const Color(0xFF00E5FF).withValues(alpha: 0.35),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildHudMetric(
                                  icon: Icons.timer_outlined,
                                  color: const Color(0xFF00E5FF),
                                  label: 'TIEMPO',
                                  value: '${_engine.survivalTime.toStringAsFixed(1)}s',
                                ),
                                const SizedBox(width: 10),
                                _buildHudMetric(
                                  icon: Icons.shield_rounded,
                                  color: const Color(0xFF10B981),
                                  label: 'ESQUIVES',
                                  value: '${_engine.dodgedCount}',
                                ),
                                const SizedBox(width: 10),
                                _buildHudMetric(
                                  icon: Icons.local_fire_department_rounded,
                                  color: const Color(0xFFF59E0B),
                                  label: 'RACHA',
                                  value: 'x${_engine.currentStreak}',
                                ),
                                const SizedBox(width: 10),
                                _buildHudMetric(
                                  icon: Icons.bolt_rounded,
                                  color: const Color(0xFFA855F7),
                                  label: 'REFLEJO',
                                  value: _engine.averageReactionMs > 0
                                      ? '${_engine.averageReactionMs} ms'
                                      : '-- ms',
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),

              // 4. BOTONES DE FLASH (10s / 5 Esquives) Y SPRINT
              Positioned(
                right: 24,
                bottom: 20,
                child: SafeArea(
                  top: false,
                  child: AnimatedBuilder(
                    animation: _engine,
                    builder: (context, _) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildSummonerSpellButton(
                            label: 'Sprint',
                            icon: Icons.directions_run_rounded,
                            color: const Color(0xFF38BDF8),
                            cooldown: _engine.sprintCooldown,
                            maxCooldown: DodgeGameEngine.sprintMaxCooldown,
                            onTap: _engine.castSprint,
                            size: 54,
                          ),
                          const SizedBox(width: 16),
                          _buildSummonerSpellButton(
                            label: 'FLASH (10s)',
                            icon: Icons.flash_on_rounded,
                            color: const Color(0xFFFACC15),
                            cooldown: _engine.flashCooldown,
                            maxCooldown: DodgeGameEngine.flashMaxCooldown,
                            onTap: _engine.castFlash,
                            size: 70,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),

              // 5. MODAL DE PAUSA Y CONFIGURACIÓN
              AnimatedBuilder(
                animation: _engine,
                builder: (context, _) {
                  if (!_engine.isPaused || _engine.isGameOver) {
                    return const SizedBox.shrink();
                  }
                  return _buildPauseAndSettingsOverlay();
                },
              ),

              // 6. MODAL DE FIN DE PARTIDA
              AnimatedBuilder(
                animation: _engine,
                builder: (context, _) {
                  if (!_engine.isGameOver) return const SizedBox.shrink();
                  return _buildGameOverOverlay();
                },
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildDifficultySelector() {
    return AnimatedBuilder(
      animation: _engine,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDiffChip(
                diff: DodgeDifficulty.easy,
                label: 'Fácil',
                activeColor: const Color(0xFF10B981),
              ),
              _buildDiffChip(
                diff: DodgeDifficulty.medium,
                label: 'Medio',
                activeColor: const Color(0xFFF59E0B),
              ),
              _buildDiffChip(
                diff: DodgeDifficulty.hard,
                label: 'Difícil',
                activeColor: const Color(0xFFEF4444),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDiffChip({
    required DodgeDifficulty diff,
    required String label,
    required Color activeColor,
  }) {
    final bool selected = _engine.difficulty == diff;
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        _engine.resetGame(newDifficulty: diff);
      },
      borderRadius: BorderRadius.circular(9),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? activeColor.withValues(alpha: 0.22) : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
          border: Border.all(
            color: selected ? activeColor : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 11,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            color: selected ? Colors.white : Colors.white54,
          ),
        ),
      ),
    );
  }

  Widget _buildHudMetric({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 14),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: Colors.white54,
              ),
            ),
            Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSummonerSpellButton({
    required String label,
    required IconData icon,
    required Color color,
    required double cooldown,
    required double maxCooldown,
    required VoidCallback onTap,
    double size = 58,
  }) {
    final bool isReady = cooldown <= 0;
    return GestureDetector(
      onTapDown: (_) => onTap(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0F172A),
              border: Border.all(
                color: isReady ? color : Colors.white24,
                width: 2.8,
              ),
              boxShadow: isReady
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.5),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  icon,
                  color: isReady ? color : Colors.white24,
                  size: size * 0.48,
                ),
                if (!isReady)
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.68),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      cooldown.toStringAsFixed(1),
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: isReady ? Colors.white : Colors.white38,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPauseAndSettingsOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.72),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        child: Container(
          width: 460,
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.45), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.tune_rounded, color: Color(0xFF00E5FF), size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'CONFIGURAR ENTRENAMIENTO 2D',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    onPressed: _engine.togglePause,
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Selecciona los campeones enemigos que deseas esquivar:',
                style: GoogleFonts.inter(color: Colors.white70, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildChampFilterChip(
                    champ: SimChampion.malphite,
                    label: 'Malphite (Te persigue + R)',
                    color: const Color(0xFFD97706),
                  ),
                  _buildChampFilterChip(
                    champ: SimChampion.chogath,
                    label: "Cho'Gath (Te persigue + Q)",
                    color: const Color(0xFFA855F7),
                  ),
                  _buildChampFilterChip(
                    champ: SimChampion.ziggs,
                    label: 'Ziggs (Pin + Mega Bomba)',
                    color: const Color(0xFFF97316),
                  ),
                  _buildChampFilterChip(
                    champ: SimChampion.lux,
                    label: 'Lux (Pin + Q, E, R)',
                    color: const Color(0xFFF43F5E),
                  ),
                  _buildChampFilterChip(
                    champ: SimChampion.ezreal,
                    label: 'Ezreal (Pin + Q, R)',
                    color: const Color(0xFF38BDF8),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _engine.immortalPracticeMode = !_engine.immortalPracticeMode;
                  });
                },
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _engine.immortalPracticeMode
                        ? const Color(0xFF10B981).withValues(alpha: 0.15)
                        : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _engine.immortalPracticeMode
                          ? const Color(0xFF10B981)
                          : Colors.white12,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _engine.immortalPracticeMode
                            ? Icons.verified_user_rounded
                            : Icons.shield_outlined,
                        color: _engine.immortalPracticeMode
                            ? const Color(0xFF10B981)
                            : Colors.white54,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Modo Práctica Infinita (Inmortal)',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Switch(
                        value: _engine.immortalPracticeMode,
                        activeThumbColor: const Color(0xFF10B981),
                        onChanged: (val) {
                          setState(() {
                            _engine.immortalPracticeMode = val;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _engine.resetGame(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 16),
                      label: Text(
                        'Reiniciar',
                        style: GoogleFonts.outfit(
                            fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _engine.togglePause,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00E5FF),
                        foregroundColor: const Color(0xFF090D16),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 18),
                      label: Text(
                        'Continuar',
                        style: GoogleFonts.outfit(
                            fontWeight: FontWeight.w900, fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChampFilterChip({
    required SimChampion champ,
    required String label,
    required Color color,
  }) {
    final bool active = _engine.enabledChampions.contains(champ);
    return InkWell(
      onTap: () {
        HapticFeedback.selectionClick();
        _engine.toggleChampionFilter(champ);
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active
              ? color.withValues(alpha: 0.22)
              : Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? color : Colors.white12,
            width: 1.3,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              active ? Icons.check_circle_rounded : Icons.circle_outlined,
              color: active ? color : Colors.white38,
              size: 14,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: active ? Colors.white : Colors.white54,
                fontSize: 11.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameOverOverlay() {
    return Container(
      color: Colors.black.withValues(alpha: 0.76),
      alignment: Alignment.center,
      child: SingleChildScrollView(
        child: Container(
          width: 440,
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
                color: const Color(0xFF00E5FF).withValues(alpha: 0.45), width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'ENTRENAMIENTO FINALIZADO',
                    style: GoogleFonts.outfit(
                      color: const Color(0xFF00E5FF),
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (_engine.achievedNewRecord) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFACC15).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFFFACC15)),
                      ),
                      child: Text(
                        '¡NUEVO RÉCORD!',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFFFACC15),
                          fontSize: 10,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildSummaryStat(
                    'Tiempo',
                    '${_engine.survivalTime.toStringAsFixed(1)}s',
                    'Récord: ${_engine.recordSurvivalTime.toStringAsFixed(1)}s',
                  ),
                  _buildSummaryStat(
                    'Esquives',
                    '${_engine.dodgedCount}',
                    'Récord: ${_engine.recordDodgedCount}',
                  ),
                  _buildSummaryStat(
                    'Mejor Racha',
                    'x${_engine.bestStreak}',
                    'Récord: x${_engine.recordBestStreak}',
                  ),
                  _buildSummaryStat(
                    'Reflejo Prom.',
                    _engine.averageReactionMs > 0
                        ? '${_engine.averageReactionMs} ms'
                        : 'N/A',
                    _engine.recordBestReactionMs > 0
                        ? 'Mejor: ${_engine.recordBestReactionMs} ms'
                        : 'Mejor: --',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(
                        'Volver a Drafting',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _engine.resetGame(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 11),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.replay_rounded, size: 18),
                      label: Text(
                        'Jugar de Nuevo',
                        style: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryStat(String label, String value, String subRecord) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: GoogleFonts.inter(
            color: Colors.white70,
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subRecord,
          style: GoogleFonts.outfit(
            color: const Color(0xFF00E5FF),
            fontSize: 10,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// Renderizador 2D que conserva el campo amplio (zoom 2150) y las figuras compactas,
/// mostrando a los campeones persiguiendo activamente al jugador antes de lanzar.
class _DodgeArenaPainter extends CustomPainter {
  final DodgeGameEngine engine;
  final String userName;
  final ui.Image? avatarImage;
  final Map<SimChampion, ui.Image> championImages;

  _DodgeArenaPainter({
    required this.engine,
    required this.userName,
    required this.avatarImage,
    required this.championImages,
  }) : super(repaint: engine);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 10 || size.height <= 10) return;

    // Conservamos exactamente la escala amplia y estética que aprobaste (2150u)
    final double longerSide = math.max(size.width, size.height);
    final double scale = longerSide / 2150.0;
    final Offset screenCenter = Offset(size.width / 2, size.height / 2);

    canvas.save();
    final Offset cameraOffset = screenCenter - (engine.playerPos * scale * 0.55);
    canvas.translate(cameraOffset.dx, cameraOffset.dy);
    canvas.scale(scale, scale);

    // 1. PINTAR SUELO TÁCTICO DE LA ARENA
    _drawArenaFloor(canvas);

    // 2. PINTAR EFECTO RESIDUAL DE FLASH
    if (engine.flashVfxTimer > 0 && engine.lastFlashOrigin != null) {
      final double alpha = (engine.flashVfxTimer / 0.45).clamp(0.0, 1.0);
      canvas.drawCircle(
        engine.lastFlashOrigin!,
        DodgeGameEngine.playerHitboxRadius * (1.5 - alpha * 0.4),
        Paint()
          ..color = const Color(0xFFFDE047).withValues(alpha: alpha * 0.65)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6.0,
      );
    }

    // 3. PINTAR CAMPEONES PERSIGUIÉNDOTE Y SUS HABILIDADES
    for (final s in engine.skillshots) {
      if (s.walksInDuringApproach) {
        if (s.isApproaching || s.isCasting) {
          _drawChasingChampion(canvas, s);
        }
      } else {
        if (s.isApproaching || s.isCasting) {
          _drawLocationPinWithChampion(canvas, s);
        }
      }

      if (!s.isApproaching) {
        _drawActiveSkillshotGeometry(canvas, s);
      }
    }

    // 4. PINTAR JUGADOR
    _drawPlayer(canvas);

    // 5. PINTAR TEXTOS FLOTANTES
    for (final ft in engine.floatingTexts) {
      _drawFloatingText(canvas, ft);
    }

    canvas.restore();
  }

  /// Dibuja a Malphite o Cho'Gath acercándose activamente al jugador con su anillo de alcance fijo.
  void _drawChasingChampion(Canvas canvas, ActiveSkillshot s) {
    final Offset pos = s.casterPos;
    const double r = 45.0;
    final ui.Image? champImg = championImages[s.champion];

    // Anillo del alcance máximo fijo que se mueve con el campeón mientras te persigue
    if (s.isApproaching) {
      canvas.drawCircle(
        pos,
        s.maxCastRange,
        Paint()
          ..color = s.dangerColor.withValues(alpha: 0.16)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.8,
      );
      // Línea de persecución apuntando directo al jugador
      canvas.drawLine(
        pos,
        engine.playerPos,
        Paint()
          ..color = s.dangerColor.withValues(alpha: 0.30)
          ..strokeWidth = 3.0,
      );
    }

    final double ringScale = 1.50 - 0.50 * s.approachProgress;
    canvas.drawCircle(
      pos,
      r * ringScale,
      Paint()
        ..color = s.dangerColor.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5,
    );

    final Rect imgRect = Rect.fromCircle(center: pos, radius: r);
    canvas.save();
    canvas.clipPath(Path()..addOval(imgRect));
    if (champImg != null) {
      paintImage(
        canvas: canvas,
        rect: imgRect,
        image: champImg,
        fit: BoxFit.cover,
      );
    } else {
      canvas.drawCircle(pos, r, Paint()..color = const Color(0xFF1E293B));
    }
    canvas.restore();

    canvas.drawCircle(
      pos,
      r,
      Paint()
        ..color = s.primaryColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0,
    );

    final double remainingSec =
        math.max(0.0, s.approachDuration - s.elapsed);
    final String alertLabel = s.isApproaching
        ? '¡${s.championName} [${s.abilityKey}] (${remainingSec.toStringAsFixed(1)}s)!'
        : '¡${s.championName} [${s.abilityKey}]!';

    _drawAbilityTag(
      canvas,
      pos + const Offset(0, -r - 20),
      alertLabel,
      color: const Color(0xFFFDE047),
    );
  }

  /// Dibuja el Pin Rojo 3D de Ubicación (compacto) que sigue al jugador a distancia de tiro
  void _drawLocationPinWithChampion(Canvas canvas, ActiveSkillshot s) {
    final Offset pinTipPos = s.casterPos;
    final Offset headCenter = pinTipPos + const Offset(0, -56);
    const double headRadius = 38.0;

    // Línea de puntería tenue durante los últimos instantes del aviso
    if (s.isApproaching && s.approachProgress > 0.5) {
      canvas.drawLine(
        pinTipPos,
        engine.playerPos,
        Paint()
          ..color = s.dangerColor.withValues(alpha: 0.22)
          ..strokeWidth = 2.5,
      );
    }

    final Path pinPath = Path()
      ..moveTo(pinTipPos.dx, pinTipPos.dy)
      ..quadraticBezierTo(
        headCenter.dx - headRadius * 1.05,
        headCenter.dy + headRadius * 0.55,
        headCenter.dx - headRadius,
        headCenter.dy,
      )
      ..arcToPoint(
        Offset(headCenter.dx + headRadius, headCenter.dy),
        radius: const Radius.circular(headRadius),
        clockwise: true,
      )
      ..quadraticBezierTo(
        headCenter.dx + headRadius * 1.05,
        headCenter.dy + headRadius * 0.55,
        pinTipPos.dx,
        pinTipPos.dy,
      )
      ..close();

    canvas.drawPath(
      pinPath.shift(const Offset(0, 5)),
      Paint()..color = Colors.black.withValues(alpha: 0.45),
    );
    canvas.drawPath(
      pinPath,
      Paint()..color = const Color(0xFFF45B5B),
    );
    canvas.drawPath(
      pinPath,
      Paint()
        ..color = const Color(0xFFFF9494)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.0,
    );

    final Rect innerRect =
        Rect.fromCircle(center: headCenter, radius: headRadius * 0.74);
    final ui.Image? champImg = championImages[s.champion];

    canvas.save();
    canvas.clipPath(Path()..addOval(innerRect));
    if (champImg != null) {
      paintImage(
        canvas: canvas,
        rect: innerRect,
        image: champImg,
        fit: BoxFit.cover,
      );
    } else {
      canvas.drawCircle(
          headCenter, headRadius * 0.74, Paint()..color = const Color(0xFF0F172A));
    }
    canvas.restore();

    canvas.drawArc(
      Rect.fromCircle(center: headCenter, radius: headRadius * 0.82),
      -math.pi / 2,
      2 * math.pi * (s.isApproaching ? s.approachProgress : 1.0),
      false,
      Paint()
        ..color = const Color(0xFFFDE047)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5,
    );

    final double rem = math.max(0.0, s.approachDuration - s.elapsed);
    final String pinText = s.isApproaching
        ? '${s.championName} [${s.abilityKey}] ${rem.toStringAsFixed(1)}s'
        : '¡${s.championName} [${s.abilityKey}]!';
    _drawAbilityTag(
      canvas,
      headCenter + const Offset(0, -headRadius - 18),
      pinText,
      color: const Color(0xFFFFB4B4),
    );
  }

  void _drawArenaFloor(Canvas canvas) {
    const Rect arenaRect = Rect.fromLTWH(
      -DodgeGameEngine.worldWidth / 2,
      -DodgeGameEngine.worldHeight / 2,
      DodgeGameEngine.worldWidth,
      DodgeGameEngine.worldHeight,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(arenaRect, const Radius.circular(36)),
      Paint()..color = const Color(0xFF0E1726),
    );

    final Paint gridPaint = Paint()
      ..color = const Color(0xFF1E293B).withValues(alpha: 0.75)
      ..strokeWidth = 2.0;

    for (double x = -DodgeGameEngine.worldWidth / 2;
        x <= DodgeGameEngine.worldWidth / 2;
        x += 200) {
      canvas.drawLine(
        Offset(x, -DodgeGameEngine.worldHeight / 2),
        Offset(x, DodgeGameEngine.worldHeight / 2),
        gridPaint,
      );
    }
    for (double y = -DodgeGameEngine.worldHeight / 2;
        y <= DodgeGameEngine.worldHeight / 2;
        y += 200) {
      canvas.drawLine(
        Offset(-DodgeGameEngine.worldWidth / 2, y),
        Offset(DodgeGameEngine.worldWidth / 2, y),
        gridPaint,
      );
    }

    canvas.drawCircle(
      Offset.zero,
      360,
      Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(arenaRect, const Radius.circular(36)),
      Paint()
        ..color = const Color(0xFF00E5FF).withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0,
    );
  }

  void _drawActiveSkillshotGeometry(Canvas canvas, ActiveSkillshot s) {
    switch (s.type) {
      case SkillshotType.chogathQ:
        final double progress = s.castProgress;
        canvas.drawCircle(
          s.target,
          s.radius * progress,
          Paint()
            ..color = s.dangerColor.withValues(alpha: 0.18 + 0.25 * progress)
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          s.target,
          s.radius,
          Paint()
            ..color = s.hasImpacted ? Colors.white : s.dangerColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = s.hasImpacted ? 8.0 : 4.5,
        );
        _drawAbilityTag(canvas, s.target, "Cho'Gath Q");
        break;

      case SkillshotType.ziggsR:
        final double progress = s.castProgress;
        canvas.drawCircle(
          s.target,
          s.outerRadius,
          Paint()
            ..color = s.primaryColor.withValues(alpha: 0.14 + 0.12 * progress)
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          s.target,
          s.outerRadius,
          Paint()
            ..color = s.primaryColor.withValues(alpha: 0.85)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 3.5,
        );
        canvas.drawCircle(
          s.target,
          s.radius * progress,
          Paint()
            ..color = s.dangerColor.withValues(alpha: 0.28 + 0.32 * progress)
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          s.target,
          s.radius,
          Paint()
            ..color = s.hasImpacted ? Colors.white : s.dangerColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = s.hasImpacted ? 10.0 : 4.5,
        );
        _drawAbilityTag(canvas, s.target, 'Ziggs R');
        break;

      case SkillshotType.luxR:
        final double angle = math.atan2(s.direction.dy, s.direction.dx);
        canvas.save();
        canvas.translate(s.origin.dx, s.origin.dy);
        canvas.rotate(angle);

        if (!s.hasImpacted) {
          final double progress = s.castProgress;
          final Rect hitboxRect = Rect.fromLTWH(
            0,
            -s.radius,
            s.actualFlightDistance,
            s.radius * 2,
          );
          canvas.drawRect(
            hitboxRect,
            Paint()..color = s.dangerColor.withValues(alpha: 0.16),
          );
          canvas.drawRect(
            hitboxRect,
            Paint()
              ..color = s.dangerColor.withValues(alpha: 0.55)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.2,
          );
          canvas.drawLine(
            Offset.zero,
            Offset(s.actualFlightDistance, 0),
            Paint()
              ..color = Colors.white.withValues(alpha: 0.5 + 0.5 * progress)
              ..strokeWidth = 3.5 + 6.5 * progress,
          );
        } else {
          final Rect beamRect = Rect.fromLTWH(
            0,
            -s.radius,
            s.actualFlightDistance,
            s.radius * 2,
          );
          canvas.drawRect(
            beamRect,
            Paint()..color = s.primaryColor.withValues(alpha: 0.82),
          );
          canvas.drawRect(
            Rect.fromLTWH(
              0,
              -s.radius * 0.45,
              s.actualFlightDistance,
              s.radius * 0.9,
            ),
            Paint()..color = Colors.white,
          );
        }
        canvas.restore();
        break;

      case SkillshotType.luxE:
        canvas.drawCircle(
          s.target,
          s.radius,
          Paint()
            ..color = s.dangerColor.withValues(alpha: 0.16)
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          s.target,
          s.radius,
          Paint()
            ..color = s.hasImpacted ? Colors.white : s.dangerColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = s.hasImpacted ? 8.0 : 4.0,
        );
        canvas.drawCircle(
          s.currentPos,
          28.0,
          Paint()..color = s.primaryColor,
        );
        break;

      case SkillshotType.luxQ:
      case SkillshotType.ezrealQ:
        if (!s.isCasting) {
          final double angle = math.atan2(s.direction.dy, s.direction.dx);
          canvas.save();
          canvas.translate(s.currentPos.dx, s.currentPos.dy);
          canvas.rotate(angle);

          final RRect capsule = RRect.fromRectAndRadius(
            Rect.fromCenter(
              center: Offset.zero,
              width: s.radius * 2.3,
              height: s.radius * 1.9,
            ),
            Radius.circular(s.radius),
          );
          canvas.drawRRect(capsule, Paint()..color = s.primaryColor);
          canvas.drawRRect(
            capsule,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.0,
          );
          canvas.restore();
        }
        break;

      case SkillshotType.ezrealR:
        final double angle = math.atan2(s.direction.dy, s.direction.dx);
        if (!s.isCasting) {
          canvas.save();
          canvas.translate(s.currentPos.dx, s.currentPos.dy);
          canvas.rotate(angle);

          final Path crescent = Path()
            ..addArc(
              Rect.fromCircle(center: Offset.zero, radius: s.radius),
              -math.pi / 2,
              math.pi,
            )
            ..arcTo(
              Rect.fromCircle(
                  center: const Offset(-32, 0), radius: s.radius * 0.82),
              math.pi / 2,
              -math.pi,
              false,
            )
            ..close();

          canvas.drawPath(crescent, Paint()..color = s.primaryColor);
          canvas.drawPath(
            crescent,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.5,
          );
          canvas.restore();
        }
        break;

      case SkillshotType.malphiteR:
        canvas.drawCircle(
          s.target,
          s.radius,
          Paint()
            ..color = s.dangerColor.withValues(alpha: 0.28)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4.0,
        );
        final ui.Image? malphImg = championImages[SimChampion.malphite];
        final Rect mRect = Rect.fromCircle(center: s.currentPos, radius: 50);
        canvas.save();
        canvas.clipPath(Path()..addOval(mRect));
        if (malphImg != null) {
          paintImage(canvas: canvas, rect: mRect, image: malphImg, fit: BoxFit.cover);
        } else {
          canvas.drawCircle(s.currentPos, 50, Paint()..color = s.primaryColor);
        }
        canvas.restore();
        canvas.drawCircle(
          s.currentPos,
          s.radius,
          Paint()
            ..color = s.dangerColor.withValues(alpha: 0.6)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 5.5,
        );
        break;
    }
  }

  void _drawPlayer(Canvas canvas) {
    final Offset pos = engine.playerPos;
    const double r = DodgeGameEngine.playerHitboxRadius; // 44u compacto

    final Color ringColor = engine.hitFlashTimer > 0
        ? const Color(0xFFEF4444)
        : (engine.sprintTimer > 0
            ? const Color(0xFF38BDF8)
            : const Color(0xFF00E5FF));

    canvas.drawCircle(
      pos,
      r,
      Paint()
        ..color = ringColor.withValues(alpha: 0.22)
        ..style = PaintingStyle.fill,
    );

    final Rect avatarRect = Rect.fromCircle(center: pos, radius: r * 0.86);
    canvas.save();
    canvas.clipPath(Path()..addOval(avatarRect));
    if (avatarImage != null) {
      paintImage(
        canvas: canvas,
        rect: avatarRect,
        image: avatarImage!,
        fit: BoxFit.cover,
      );
    } else {
      canvas.drawCircle(pos, r * 0.86, Paint()..color = const Color(0xFF1E293B));
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: userName.isNotEmpty ? userName[0].toUpperCase() : 'D',
          style: const TextStyle(
            color: Color(0xFF00E5FF),
            fontSize: 32,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
    canvas.restore();

    canvas.drawCircle(
      pos,
      r,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.0,
    );

    const double barWidth = 115.0;
    const double barHeight = 13.0;
    final Offset barTopLeft = pos + const Offset(-barWidth / 2, -r - 26);

    final TextPainter namePainter = TextPainter(
      text: TextSpan(
        text: engine.knockupTimer > 0 ? '¡INMOVILIZADO!' : userName,
        style: TextStyle(
          color: engine.knockupTimer > 0 ? const Color(0xFFFDE047) : Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w800,
          shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    namePainter.paint(
      canvas,
      Offset(pos.dx - namePainter.width / 2, barTopLeft.dy - 20),
    );

    final RRect barBg = RRect.fromRectAndRadius(
      Rect.fromLTWH(barTopLeft.dx, barTopLeft.dy, barWidth, barHeight),
      const Radius.circular(4),
    );
    canvas.drawRRect(barBg, Paint()..color = const Color(0xFF090D16));

    final double hpRatio = (engine.currentHp / engine.maxHp).clamp(0.0, 1.0);
    final Color hpColor = hpRatio > 0.5
        ? const Color(0xFF22C55E)
        : (hpRatio > 0.25 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(barTopLeft.dx, barTopLeft.dy, barWidth * hpRatio, barHeight),
        const Radius.circular(4),
      ),
      Paint()..color = hpColor,
    );

    canvas.drawRRect(
      barBg,
      Paint()
        ..color = const Color(0xFFC89B3C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );
  }

  void _drawAbilityTag(
    Canvas canvas,
    Offset pos,
    String label, {
    Color color = Colors.white,
  }) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: color,
          fontSize: 15.5,
          fontWeight: FontWeight.w900,
          shadows: const [Shadow(color: Colors.black, blurRadius: 6)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  void _drawFloatingText(Canvas canvas, FloatingCombatText ft) {
    final double alpha = (1.0 - (ft.elapsed / ft.duration)).clamp(0.0, 1.0);
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: ft.text,
        style: TextStyle(
          color: ft.color.withValues(alpha: alpha),
          fontSize: 20,
          fontWeight: FontWeight.w900,
          shadows: [
            Shadow(
              color: Colors.black.withValues(alpha: alpha),
              blurRadius: 6,
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, ft.position - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _DodgeArenaPainter oldDelegate) => true;
}

/// Dibuja el Joystick virtual en la esquina inferior izquierda
class _JoystickOverlayPainter extends CustomPainter {
  final Offset? origin;
  final Offset knob;
  final double maxRadius;

  _JoystickOverlayPainter({
    required this.origin,
    required this.knob,
    required this.maxRadius,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final Offset baseCenter = origin ?? Offset(110, size.height - 95);
    final Offset knobCenter = origin != null ? knob : baseCenter;

    canvas.drawCircle(
      baseCenter,
      maxRadius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      baseCenter,
      maxRadius,
      Paint()
        ..color = const Color(0xFFC89B3C).withValues(alpha: 0.65)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    canvas.drawCircle(
      knobCenter,
      24,
      Paint()
        ..color = origin != null
            ? const Color(0xFF00E5FF).withValues(alpha: 0.88)
            : Colors.white.withValues(alpha: 0.5),
    );
  }

  @override
  bool shouldRepaint(covariant _JoystickOverlayPainter oldDelegate) => true;
}
