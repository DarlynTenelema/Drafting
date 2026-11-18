import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Nivel de dificultad del simulador:
/// - [easy]: Cada 2.0s, 1 habilidad a la vez, predicción moderada, regeneración suave.
/// - [medium]: Cada 1.35s, 30% probabilidad de Combo Táctico doble, predicción media-alta.
/// - [hard]: Cada 0.90s, 50% probabilidad de Crossfire (2 habilidades en ángulos cruzados), predicción máxima.
enum DodgeDifficulty {
  easy,
  medium,
  hard,
}

/// Campeones disponibles en el simulador para poder filtrarlos en el menú de entrenamiento.
enum SimChampion {
  lux,
  ezreal,
  chogath,
  ziggs,
  malphite,
}

/// Tipos de habilidades basadas en los campeones definidos en Nuevas_mejoras_2027.md
enum SkillshotType {
  chogathQ, // Círculo en el suelo con cast 0.5s + delay 0.625s (1.125s total, radio 250u)
  ziggsR, // Círculo grande concéntrico (epicentro 240u + borde exterior 450u, 1.5s)
  luxQ, // Esfera lineal moderada (0.25s cast + 1200 u/s, radio 70u)
  luxE, // Zona circular con slow y detonación (0.25s cast + vuelo 1200 u/s + zona 300u)
  luxR, // Línea fina de casteo (1.0s exacto) -> rayo ancho instantáneo (200u)
  ezrealQ, // Proyectil lineal rápido (0.25s cast + 2000 u/s, radio 60u)
  ezrealR, // Boomerang / media luna ancha (1.0s cast + 2000 u/s, radio 160u)
  malphiteR, // Embate circular ultrarrápido hacia el jugador (radio 275u)
}

/// Representa una instancia activa de habilidad enemiga en el mapa 2D,
/// incluyendo la posición del "Tótem / Campeón Enemigo" que la lanza.
class ActiveSkillshot {
  final SkillshotType type;
  final SimChampion champion;
  final String championName;
  final String abilityKey;
  final Color primaryColor;
  final Color dangerColor;

  /// Posición donde aparece el círculo del campeón enemigo casteando la habilidad
  final Offset casterPos;

  /// Posición de origen del proyectil y destino en unidades del motor (escala LoL)
  final Offset origin;
  final Offset target;
  final Offset direction;

  /// Tiempos (en segundos)
  final double castDuration; // Tiempo de telegrafiado / canalización inicial
  final double travelSpeed; // Unidades por segundo (0 si es aparición en área)
  final double maxRange;
  final double radius; // Radio o mitad del ancho del hitbox
  final double outerRadius; // Usado por Ziggs R
  final double lingerDuration; // Tiempo extra tras llegar (ej. Lux E o explosión visual)
  final double damage;
  final bool appliesKnockup;
  final bool appliesSlow;

  double elapsed = 0.0;
  Offset currentPos;
  bool hasImpacted = false;
  bool hasDealtDamage = false;
  bool countedAsDodged = false;

  /// Para medir reflejos del jugador: instante en que el jugador cambió de dirección o usó Destello
  double? playerReactionMs;

  ActiveSkillshot({
    required this.type,
    required this.champion,
    required this.championName,
    required this.abilityKey,
    required this.primaryColor,
    required this.dangerColor,
    required this.casterPos,
    required this.origin,
    required this.target,
    required this.direction,
    required this.castDuration,
    required this.travelSpeed,
    required this.maxRange,
    required this.radius,
    this.outerRadius = 0.0,
    this.lingerDuration = 0.24,
    required this.damage,
    this.appliesKnockup = false,
    this.appliesSlow = false,
  }) : currentPos = origin;

  bool get isCasting => elapsed < castDuration;

  double get castProgress =>
      castDuration <= 0 ? 1.0 : (elapsed / castDuration).clamp(0.0, 1.0);

  /// El tótem del campeón enemigo es visible durante el casteo y 0.35s después de disparar
  bool get showCasterTotem => elapsed <= (castDuration + 0.38);
}

/// Ataque programado con un pequeño retardo para combos en niveles Medio y Difícil
class _QueuedComboAttack {
  double delayRemaining;
  final SkillshotType forcedType;
  final double? angleOffsetRad;

  _QueuedComboAttack({
    required this.delayRemaining,
    required this.forcedType,
    this.angleOffsetRad,
  });
}

/// Efecto visual flotante (texto de "¡ESQUIVADO!", daño o partículas de Flash)
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
    this.duration = 0.85,
  });
}

/// Motor del juego desacoplado del árbol de Widgets (Zero-Rebuild Game Loop).
/// Al extender ChangeNotifier y conectarse directamente al CustomPainter(repaint: engine),
/// Flutter NO reconstruye ningún Widget en cada frame: solo redibuja el Canvas en GPU.
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

  // Modo Práctica Infinita (Inmortal: la vida no baja de 1 HP para practicar sin interrupciones)
  bool immortalPracticeMode = false;

  // Sensibilidad del Joystick (1.0 = estándar Wild Rift)
  double joystickSensitivity = 1.0;

  // Dimensiones del mundo virtual en unidades de League of Legends (cámara centrada)
  static const double worldWidth = 2200.0;
  static const double worldHeight = 1300.0;

  // Estadísticas del jugador (proporciones reales de LoL / Wild Rift)
  static const double playerHitboxRadius = 65.0; // Hitbox estándar campeón
  static const double baseMoveSpeed = 385.0; // Velocidad con botas tier 1-2

  Offset playerPos = Offset.zero;
  Offset joystickVector = Offset.zero; // Vector normalizado (dx, dy) de -1 a 1
  Offset lastFacingDir = const Offset(1, 0);

  double maxHp = 1000.0;
  double currentHp = 1000.0;

  // Estados alterados
  double knockupTimer = 0.0; // Si > 0, Cho'Gath Q, Lux Q o Malphite R inmovilizó al jugador
  double slowTimer = 0.0; // Si > 0, Lux E ralentiza un 30%
  double sprintTimer = 0.0; // Si > 0, Sprint activo (+35% velocidad)
  double hitFlashTimer = 0.0; // Feedback visual al recibir daño

  // Cooldowns de hechizos de invocador (estilo Wild Rift)
  static const double flashMaxCooldown = 12.0;
  static const double sprintMaxCooldown = 8.0;
  double flashCooldown = 0.0;
  double sprintCooldown = 0.0;

  // Efecto visual de Flash (sombra en posición anterior)
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
  double spawnTimer = 0.6;
  bool isRunning = true;
  bool isPaused = false;
  bool isGameOver = false;

  final List<ActiveSkillshot> skillshots = [];
  final List<_QueuedComboAttack> _comboQueue = [];
  final List<FloatingCombatText> floatingTexts = [];
  final math.Random _rng = math.Random();

  // Seguimiento de cambio de dirección para medir reflejo en ms
  Offset _prevJoystickDir = Offset.zero;

  double get spawnInterval {
    switch (difficulty) {
      case DodgeDifficulty.easy:
        return 2.0; // Cada 2.0 segundos exactos (especificación MVP)
      case DodgeDifficulty.medium:
        return 1.35; // Más fluido + Combos Tácticos
      case DodgeDifficulty.hard:
        return 0.90; // Alta intensidad + Crossfire
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
      // Garantizar que al menos 1 campeón esté siempre activo
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
    spawnTimer = 0.75;
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

    // Medición de reflejos: si el jugador cambia bruscamente de dirección (> 45 grados)
    // mientras hay una habilidad recién casteada, registramos su tiempo de reacción en ms.
    if (finalVec.distance > 0.25) {
      final dir = finalVec / finalVec.distance;
      final dot = dir.dx * _prevJoystickDir.dx + dir.dy * _prevJoystickDir.dy;
      if (_prevJoystickDir == Offset.zero || dot < 0.7) {
        for (final s in skillshots) {
          if (s.playerReactionMs == null && s.elapsed > 0.07 && s.elapsed < 0.95) {
            s.playerReactionMs = s.elapsed * 1000.0;
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

  /// Hechizo de Invocador 1: Destello (Flash) - Teletransporte instantáneo de 400 unidades
  bool castFlash() {
    if (isGameOver || isPaused || !isRunning || flashCooldown > 0 || knockupTimer > 0) {
      return false;
    }
    HapticFeedback.mediumImpact();
    flashCooldown = flashMaxCooldown;
    lastFlashOrigin = playerPos;
    flashVfxTimer = 0.45;

    final Offset dir = joystickVector.distance > 0.15
        ? (joystickVector / joystickVector.distance)
        : lastFacingDir;

    const double flashDistance = 400.0;
    final Offset next = playerPos + dir * flashDistance;
    playerPos = Offset(
      next.dx.clamp(-worldWidth / 2 + 90, worldWidth / 2 - 90),
      next.dy.clamp(-worldHeight / 2 + 90, worldHeight / 2 - 90),
    );

    // Registrar reflejo si esquivó con Flash una habilidad activa
    for (final s in skillshots) {
      if (s.playerReactionMs == null && s.elapsed > 0.05) {
        s.playerReactionMs = s.elapsed * 1000.0;
        reactionTimesMs.add(s.playerReactionMs!);
      }
    }

    floatingTexts.add(
      FloatingCombatText(
        text: '¡DESTELLO!',
        position: playerPos + const Offset(0, -85),
        color: const Color(0xFFFDE047),
      ),
    );
    notifyListeners();
    return true;
  }

  /// Hechizo de Invocador 2: Sprint / Fantasma (+35% Velocidad por 3s)
  bool castSprint() {
    if (isGameOver || isPaused || !isRunning || sprintCooldown > 0) {
      return false;
    }
    HapticFeedback.lightImpact();
    sprintCooldown = sprintMaxCooldown;
    sprintTimer = 3.0;
    floatingTexts.add(
      FloatingCombatText(
        text: '+35% VELOCIDAD',
        position: playerPos + const Offset(0, -85),
        color: const Color(0xFF38BDF8),
      ),
    );
    notifyListeners();
    return true;
  }

  /// Actualización principal llamada por el Ticker de alta prioridad en cada frame
  void update(double dt) {
    if (!isRunning || isPaused || isGameOver) return;

    // Limitar dt por si hubo pausa del SO para evitar saltos bruscos de física
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

    // 2. Movimiento del jugador (bloqueado si está en Knockup/Root)
    double currentMoveSpeed = baseMoveSpeed;
    if (sprintTimer > 0) currentMoveSpeed *= 1.35;
    if (slowTimer > 0) currentMoveSpeed *= 0.70;

    if (knockupTimer <= 0 && joystickVector.distance > 0.05) {
      final Offset velocity = joystickVector * currentMoveSpeed;
      final Offset nextPos = playerPos + velocity * safeDt;
      playerPos = Offset(
        nextPos.dx.clamp(-worldWidth / 2 + 80, worldWidth / 2 - 80),
        nextPos.dy.clamp(-worldHeight / 2 + 80, worldHeight / 2 - 80),
      );
    }

    // 3. Procesar cola de Combos (para niveles Medio y Difícil)
    for (int i = _comboQueue.length - 1; i >= 0; i--) {
      final q = _comboQueue[i];
      q.delayRemaining -= safeDt;
      if (q.delayRemaining <= 0) {
        _spawnSingleSkillshot(
          currentMoveSpeed,
          forcedType: q.forcedType,
          forcedAngleOffset: q.angleOffsetRad,
        );
        _comboQueue.removeAt(i);
      }
    }

    // 4. Spawner principal de habilidades enemigas
    spawnTimer -= safeDt;
    if (spawnTimer <= 0) {
      spawnTimer = spawnInterval;
      _triggerWaveSpawn(currentMoveSpeed);
    }

    // 5. Actualizar física y colisiones de cada habilidad activa
    for (int i = skillshots.length - 1; i >= 0; i--) {
      final s = skillshots[i];
      s.elapsed += safeDt;

      final bool shouldRemove = _updateAndCheckSkillshot(s, safeDt);
      if (shouldRemove) {
        if (!s.hasDealtDamage && !s.countedAsDodged) {
          s.countedAsDodged = true;
          dodgedCount++;
          currentStreak++;
          if (currentStreak > bestStreak) bestStreak = currentStreak;

          floatingTexts.add(
            FloatingCombatText(
              text: currentStreak > 2 ? '¡ESQUIVADO x$currentStreak!' : '¡ESQUIVADO!',
              position: playerPos + const Offset(0, -75),
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

    // 7. Regeneración de vida según dificultad
    if (currentHp < maxHp && currentHp > 0) {
      final double regenPerSec = difficulty == DodgeDifficulty.easy
          ? 10.0
          : (difficulty == DodgeDifficulty.medium ? 5.0 : 2.0);
      currentHp = math.min(maxHp, currentHp + regenPerSec * safeDt);
    }

    notifyListeners();
  }

  List<SkillshotType> _getAllowedSkillshotPool() {
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
    if (enabledChampions.contains(SimChampion.malphite)) {
      pool.add(SkillshotType.malphiteR);
    }
    if (pool.isEmpty) {
      pool.add(SkillshotType.ezrealQ);
    }
    return pool;
  }

  /// Gestiona la aparición según el nivel:
  /// - Fácil: 1 habilidad limpia cada 2.0s.
  /// - Medio: 30% de probabilidad de Combo Táctico (2 habilidades encadenadas).
  /// - Difícil: 50% de probabilidad de Crossfire (2 habilidades desde ángulos perpendiculares).
  void _triggerWaveSpawn(double playerSpeed) {
    final pool = _getAllowedSkillshotPool();
    final SkillshotType primary = pool[_rng.nextInt(pool.length)];
    _spawnSingleSkillshot(playerSpeed, forcedType: primary);

    if (difficulty == DodgeDifficulty.easy) {
      return;
    }

    final double comboChance = difficulty == DodgeDifficulty.medium ? 0.30 : 0.52;
    if (_rng.nextDouble() < comboChance) {
      // Elegir una segunda habilidad que complemente el combo (ej. área + proyectil lineal)
      final SkillshotType secondary = _pickComplementaryComboSkill(primary, pool);
      final double delay = difficulty == DodgeDifficulty.medium ? 0.32 : 0.18;
      // En Difícil forzamos un ángulo cruzado (~90 grados) para entrenar esquive diagonal
      final double? crossAngle =
          difficulty == DodgeDifficulty.hard ? (math.pi / 2.1) : null;

      _comboQueue.add(
        _QueuedComboAttack(
          delayRemaining: delay,
          forcedType: secondary,
          angleOffsetRad: crossAngle,
        ),
      );
    }
  }

  SkillshotType _pickComplementaryComboSkill(
    SkillshotType primary,
    List<SkillshotType> pool,
  ) {
    // Si el primero fue Lux Q o Lux E, encadenar con Lux R si Lux está activa
    if ((primary == SkillshotType.luxQ || primary == SkillshotType.luxE) &&
        pool.contains(SkillshotType.luxR)) {
      return SkillshotType.luxR;
    }
    // Si el primero fue Cho'Gath Q, encadenar con Ezreal Q o Ziggs R
    if (primary == SkillshotType.chogathQ && pool.contains(SkillshotType.ezrealQ)) {
      return SkillshotType.ezrealQ;
    }
    return pool[_rng.nextInt(pool.length)];
  }

  /// Crea una habilidad individual y posiciona el Tótem del Campeón Enemigo en el borde de lanzamiento.
  void _spawnSingleSkillshot(
    double playerSpeed, {
    SkillshotType? forcedType,
    double? forcedAngleOffset,
  }) {
    final pool = _getAllowedSkillshotPool();
    final SkillshotType chosen = forcedType ?? pool[_rng.nextInt(pool.length)];

    // Factor de predicción (Lead Targeting):
    final double maxLead = difficulty == DodgeDifficulty.easy
        ? 0.55
        : (difficulty == DodgeDifficulty.medium ? 0.85 : 1.05);
    final double minLead = difficulty == DodgeDifficulty.hard ? 0.25 : 0.0;
    final double predictionFactor =
        minLead + _rng.nextDouble() * (maxLead - minLead);

    // Vector de velocidad actual del jugador
    final Offset playerVel =
        joystickVector.distance > 0.05 ? joystickVector * playerSpeed : Offset.zero;

    // Punto donde se ubica el campeón enemigo (a 720 - 880 unidades del jugador)
    final double baseAngle = _rng.nextDouble() * 2 * math.pi;
    final double spawnAngle = baseAngle + (forcedAngleOffset ?? 0.0);
    final double spawnDist = 720.0 + _rng.nextDouble() * 150.0;
    final Offset rawCasterOrigin = _clampToWorld(
      playerPos +
          Offset(
            math.cos(spawnAngle) * spawnDist,
            math.sin(spawnAngle) * spawnDist,
          ),
    );

    switch (chosen) {
      case SkillshotType.chogathQ:
        // Cho'Gath Q: 0.5s casteo + 0.625s delay = 1.125s total. Radio: 235 unidades.
        const double castTime = 1.125;
        final Offset predictedTarget =
            _clampToWorld(playerPos + playerVel * (castTime * predictionFactor));
        skillshots.add(
          ActiveSkillshot(
            type: SkillshotType.chogathQ,
            champion: SimChampion.chogath,
            championName: "Cho'Gath",
            abilityKey: 'Q',
            primaryColor: const Color(0xFFA855F7),
            dangerColor: const Color(0xFFEF4444),
            casterPos: rawCasterOrigin,
            origin: predictedTarget,
            target: predictedTarget,
            direction: _normalize(predictedTarget - rawCasterOrigin),
            castDuration: castTime,
            travelSpeed: 0,
            maxRange: 0,
            radius: 235.0,
            damage: 210,
            appliesKnockup: true,
          ),
        );
        break;

      case SkillshotType.ziggsR:
        // Ziggs R: Bomba Mega Infernal. ~1.5s de aviso en suelo.
        const double castTime = 1.55;
        final Offset predictedTarget =
            _clampToWorld(playerPos + playerVel * (castTime * predictionFactor * 0.7));
        skillshots.add(
          ActiveSkillshot(
            type: SkillshotType.ziggsR,
            champion: SimChampion.ziggs,
            championName: 'Ziggs',
            abilityKey: 'R',
            primaryColor: const Color(0xFFF97316),
            dangerColor: const Color(0xFFEF4444),
            casterPos: rawCasterOrigin,
            origin: predictedTarget,
            target: predictedTarget,
            direction: _normalize(predictedTarget - rawCasterOrigin),
            castDuration: castTime,
            travelSpeed: 0,
            maxRange: 0,
            radius: 230.0, // Epicentro
            outerRadius: 430.0, // Onda expansiva exterior
            damage: 260,
          ),
        );
        break;

      case SkillshotType.luxQ:
        // Lux Q: 0.25s casteo, 1200 u/s velocidad, 1300u rango, radio 70u (ancho 140u)
        const double castTime = 0.25;
        const double speed = 1200.0;
        final double actualDist = (playerPos - rawCasterOrigin).distance;
        final double estTravel = actualDist / speed;
        final Offset aimPoint =
            playerPos + playerVel * ((castTime + estTravel) * predictionFactor);
        final Offset dir = _normalize(aimPoint - rawCasterOrigin);
        skillshots.add(
          ActiveSkillshot(
            type: SkillshotType.luxQ,
            champion: SimChampion.lux,
            championName: 'Lux',
            abilityKey: 'Q',
            primaryColor: const Color(0xFFFDE047),
            dangerColor: const Color(0xFFF59E0B),
            casterPos: rawCasterOrigin,
            origin: rawCasterOrigin,
            target: rawCasterOrigin + dir * 1350.0,
            direction: dir,
            castDuration: castTime,
            travelSpeed: speed,
            maxRange: 1350.0,
            radius: 70.0,
            damage: 170,
            appliesKnockup: true, // Inmovilización (Root)
          ),
        );
        break;

      case SkillshotType.luxE:
        // Lux E: 0.25s casteo, viaja a 1200 u/s hasta el punto destino y explota tras 0.45s en radio 295u
        const double castTime = 0.25;
        const double speed = 1200.0;
        final Offset predictedTarget =
            _clampToWorld(playerPos + playerVel * (0.65 * predictionFactor));
        final Offset dir = _normalize(predictedTarget - rawCasterOrigin);
        final double dist = (predictedTarget - rawCasterOrigin).distance;
        skillshots.add(
          ActiveSkillshot(
            type: SkillshotType.luxE,
            champion: SimChampion.lux,
            championName: 'Lux',
            abilityKey: 'E',
            primaryColor: const Color(0xFFFFEF8A),
            dangerColor: const Color(0xFFEC4899),
            casterPos: rawCasterOrigin,
            origin: rawCasterOrigin,
            target: predictedTarget,
            direction: dir,
            castDuration: castTime,
            travelSpeed: speed,
            maxRange: dist,
            radius: 295.0,
            lingerDuration: 0.45,
            damage: 180,
            appliesSlow: true,
          ),
        );
        break;

      case SkillshotType.luxR:
        // Lux R: Chispa Final. 1.0s exacto de línea guía fina -> disparo instantáneo de 200u de ancho
        const double castTime = 1.0;
        final Offset aimPoint =
            playerPos + playerVel * (castTime * predictionFactor * 0.65);
        final Offset dir = _normalize(aimPoint - rawCasterOrigin);
        skillshots.add(
          ActiveSkillshot(
            type: SkillshotType.luxR,
            champion: SimChampion.lux,
            championName: 'Lux',
            abilityKey: 'R',
            primaryColor: const Color(0xFFF43F5E),
            dangerColor: const Color(0xFFFF0055),
            casterPos: rawCasterOrigin,
            origin: rawCasterOrigin,
            target: rawCasterOrigin + dir * 2400.0,
            direction: dir,
            castDuration: castTime,
            travelSpeed: 0, // Hitscan al terminar 1.0s
            maxRange: 2400.0,
            radius: 100.0, // 200u de ancho total
            lingerDuration: 0.30,
            damage: 280,
          ),
        );
        break;

      case SkillshotType.ezrealQ:
        // Ezreal Q: 0.25s casteo, 1950 u/s velocidad, 1250u rango, ancho 120u (radio 60u)
        const double castTime = 0.25;
        final double speed = difficulty == DodgeDifficulty.hard ? 2050.0 : 1900.0;
        final double actualDist = (playerPos - rawCasterOrigin).distance;
        final double estTravel = actualDist / speed;
        final Offset aimPoint =
            playerPos + playerVel * ((castTime + estTravel) * predictionFactor);
        final Offset dir = _normalize(aimPoint - rawCasterOrigin);
        skillshots.add(
          ActiveSkillshot(
            type: SkillshotType.ezrealQ,
            champion: SimChampion.ezreal,
            championName: 'Ezreal',
            abilityKey: 'Q',
            primaryColor: const Color(0xFF38BDF8),
            dangerColor: const Color(0xFF0284C7),
            casterPos: rawCasterOrigin,
            origin: rawCasterOrigin,
            target: rawCasterOrigin + dir * 1300.0,
            direction: dir,
            castDuration: castTime,
            travelSpeed: speed,
            maxRange: 1300.0,
            radius: 60.0,
            damage: 165,
          ),
        );
        break;

      case SkillshotType.ezrealR:
        // Ezreal R: 1.0s casteo exacto, 1900 u/s velocidad, boomerang/arco de 320u de ancho (radio 160u)
        const double castTime = 1.0;
        final double speed = difficulty == DodgeDifficulty.hard ? 2000.0 : 1850.0;
        final Offset aimPoint =
            playerPos + playerVel * (castTime * predictionFactor * 0.75);
        final Offset dir = _normalize(aimPoint - rawCasterOrigin);
        skillshots.add(
          ActiveSkillshot(
            type: SkillshotType.ezrealR,
            champion: SimChampion.ezreal,
            championName: 'Ezreal',
            abilityKey: 'R',
            primaryColor: const Color(0xFFFACC15),
            dangerColor: const Color(0xFFF97316),
            casterPos: rawCasterOrigin,
            origin: rawCasterOrigin,
            target: rawCasterOrigin + dir * 2200.0,
            direction: dir,
            castDuration: castTime,
            travelSpeed: speed,
            maxRange: 2200.0,
            radius: 160.0,
            damage: 240,
          ),
        );
        break;

      case SkillshotType.malphiteR:
        // Malphite R: Fuerza Imparable. Embate circular ultrarrápido hacia el jugador
        final double castTime = difficulty == DodgeDifficulty.easy
            ? 0.30
            : (difficulty == DodgeDifficulty.medium ? 0.20 : 0.10);
        final double speed = difficulty == DodgeDifficulty.easy
            ? 1550.0
            : (difficulty == DodgeDifficulty.medium ? 1720.0 : 1850.0);
        final Offset predictedTarget =
            _clampToWorld(playerPos + playerVel * (0.45 * predictionFactor));
        final Offset dir = _normalize(predictedTarget - rawCasterOrigin);
        final double dist = (predictedTarget - rawCasterOrigin).distance;
        skillshots.add(
          ActiveSkillshot(
            type: SkillshotType.malphiteR,
            champion: SimChampion.malphite,
            championName: 'Malphite',
            abilityKey: 'R',
            primaryColor: const Color(0xFFD97706),
            dangerColor: const Color(0xFFEF4444),
            casterPos: rawCasterOrigin,
            origin: rawCasterOrigin,
            target: predictedTarget,
            direction: dir,
            castDuration: castTime,
            travelSpeed: speed,
            maxRange: dist,
            radius: 270.0,
            lingerDuration: 0.28,
            damage: 250,
            appliesKnockup: true,
          ),
        );
        break;
    }
  }

  /// Actualiza una habilidad y devuelve `true` cuando su ciclo de vida ha terminado.
  bool _updateAndCheckSkillshot(ActiveSkillshot s, double dt) {
    switch (s.type) {
      case SkillshotType.chogathQ:
        if (s.elapsed >= s.castDuration && !s.hasImpacted) {
          s.hasImpacted = true;
          final double dist = (playerPos - s.target).distance;
          if (dist <= (s.radius + playerHitboxRadius * 0.65)) {
            _applyDamageToPlayer(s, s.damage);
          }
        }
        return s.elapsed >= (s.castDuration + s.lingerDuration);

      case SkillshotType.ziggsR:
        if (s.elapsed >= s.castDuration && !s.hasImpacted) {
          s.hasImpacted = true;
          final double dist = (playerPos - s.target).distance;
          if (dist <= (s.radius + playerHitboxRadius * 0.65)) {
            _applyDamageToPlayer(s, s.damage);
          } else if (dist <= (s.outerRadius + playerHitboxRadius * 0.55)) {
            _applyDamageToPlayer(s, (s.damage * 0.65).roundToDouble());
          }
        }
        return s.elapsed >= (s.castDuration + s.lingerDuration);

      case SkillshotType.luxR:
        if (s.elapsed >= s.castDuration && !s.hasImpacted) {
          s.hasImpacted = true;
          final double perpDist =
              _distancePointToSegment(playerPos, s.origin, s.target);
          if (perpDist <= (s.radius + playerHitboxRadius * 0.6)) {
            _applyDamageToPlayer(s, s.damage);
          }
        }
        return s.elapsed >= (s.castDuration + s.lingerDuration);

      case SkillshotType.luxE:
        if (s.elapsed < s.castDuration) return false;
        final double flightTime = s.elapsed - s.castDuration;
        final double flightDuration =
            s.travelSpeed > 0 ? (s.maxRange / s.travelSpeed) : 0.0;

        if (flightTime < flightDuration) {
          s.currentPos = s.origin + s.direction * (s.travelSpeed * flightTime);
        } else {
          s.currentPos = s.target;
          final double dist = (playerPos - s.target).distance;
          if (dist <= s.radius + playerHitboxRadius * 0.5) {
            slowTimer = math.max(slowTimer, 0.25);
          }
          if (flightTime >= flightDuration + s.lingerDuration && !s.hasImpacted) {
            s.hasImpacted = true;
            if (dist <= (s.radius + playerHitboxRadius * 0.6)) {
              _applyDamageToPlayer(s, s.damage);
            }
            return true;
          }
        }
        return false;

      case SkillshotType.luxQ:
      case SkillshotType.ezrealQ:
      case SkillshotType.ezrealR:
        if (s.elapsed < s.castDuration) return false;
        final double flightTime = s.elapsed - s.castDuration;
        final double travelled = s.travelSpeed * flightTime;
        s.currentPos = s.origin + s.direction * travelled;

        if (!s.hasDealtDamage) {
          final double dist = (playerPos - s.currentPos).distance;
          if (dist <= (s.radius + playerHitboxRadius * 0.65)) {
            s.hasImpacted = true;
            _applyDamageToPlayer(s, s.damage);
            if (s.type != SkillshotType.ezrealR) {
              return true;
            }
          }
        }
        return travelled >= s.maxRange;

      case SkillshotType.malphiteR:
        if (s.elapsed < s.castDuration) return false;
        final double flightTime = s.elapsed - s.castDuration;
        final double travelled = s.travelSpeed * flightTime;
        if (travelled < s.maxRange) {
          s.currentPos = s.origin + s.direction * travelled;
        } else {
          s.currentPos = s.target;
          if (!s.hasImpacted) {
            s.hasImpacted = true;
            final double dist = (playerPos - s.target).distance;
            if (dist <= (s.radius + playerHitboxRadius * 0.65)) {
              _applyDamageToPlayer(s, s.damage);
            }
          }
        }
        final double totalFlight =
            s.travelSpeed > 0 ? (s.maxRange / s.travelSpeed) : 0.0;
        return flightTime >= (totalFlight + s.lingerDuration);
    }
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
      knockupTimer = 0.45;
    }
    if (s.appliesSlow) {
      slowTimer = 1.5;
    }

    floatingTexts.add(
      FloatingCombatText(
        text: '-${dmg.round()} (${s.championName} ${s.abilityKey})',
        position: playerPos + const Offset(0, -80),
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
      p.dx.clamp(-worldWidth / 2 + 160, worldWidth / 2 - 160),
      p.dy.clamp(-worldHeight / 2 + 160, worldHeight / 2 - 160),
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
/// Se ejecuta en un entorno de alta prioridad (Landscape + Immersive Sticky + RepaintBoundary)
/// mientras el resto de pantallas de la app quedan hibernadas.
class DodgeSimulatorScreen extends StatefulWidget {
  final String userName;
  final String? userPhotoUrl;

  const DodgeSimulatorScreen({
    super.key,
    required this.userName,
    this.userPhotoUrl,
  });

  @override
  State<DodgeSimulatorScreen> createState() => _DodgeSimulatorScreenState();
}

class _DodgeSimulatorScreenState extends State<DodgeSimulatorScreen>
    with SingleTickerProviderStateMixin {
  late final DodgeGameEngine _engine;
  late final Ticker _ticker;
  Duration _lastElapsed = Duration.zero;

  // Imagen decodificada en GPU para dibujarla directamente en el Canvas a 120 FPS
  ui.Image? _avatarImage;

  // Estado del Joystick virtual estilo Wild Rift (mitad izquierda de la pantalla)
  Offset? _joystickOrigin;
  Offset _joystickKnob = Offset.zero;
  static const double _joystickMaxRadius = 56.0;

  @override
  void initState() {
    super.initState();
    _engine = DodgeGameEngine();
    _engine.loadRecords();

    // Priorización a nivel de Sistema Operativo:
    // Forzamos modo Horizontal (Landscape) e inmersivo para eliminar barras del sistema
    // y dar la misma ergonomía de pulgares que Wild Rift.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

    _loadUserAvatarImage();

    // Ticker de alta prioridad sincronizado con VSync (60Hz / 90Hz / 120Hz)
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
    } catch (_) {
      // Si falla la red, el Canvas dibuja automáticamente el avatar Hextech con la inicial del usuario
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _engine.dispose();
    _avatarImage?.dispose();
    // Restauramos la orientación vertical original de Drafting al salir del simulador
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
      backgroundColor: const Color(0xFF070B12),
      body: Stack(
        children: [
          // 1. LIENZO DEL JUEGO AISLADO EN GPU (RepaintBoundary evita que cualquier widget externo se repinte)
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _DodgeArenaPainter(
                  engine: _engine,
                  userName: widget.userName,
                  avatarImage: _avatarImage,
                ),
                size: Size.infinite,
              ),
            ),
          ),

          // 2. ZONA TÁCTIL DEL JOYSTICK (Mitad izquierda de la pantalla, igual a Wild Rift)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: MediaQuery.of(context).size.width * 0.55,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
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
                  );
                },
              ),
            ),
          ),

          // 3. HUD SUPERIOR: Salir, Selector de Dificultad (Fácil / Medio / Difícil), Ajustes y Estadísticas
          Positioned(
            top: 10,
            left: 14,
            right: 14,
            child: SafeArea(
              bottom: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Botón de salir + Selector de Nivel + Botón Pausa/Filtro Campeones
                  Row(
                    children: [
                      InkWell(
                        onTap: () => Navigator.of(context).pop(),
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F172A).withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 14),
                              const SizedBox(width: 4),
                              Text(
                                'Salir',
                                style: GoogleFonts.outfit(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildDifficultySelector(),
                      const SizedBox(width: 8),
                      // Botón para Pausar y Configurar Campeones / Modo Inmortal
                      InkWell(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          _engine.togglePause();
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: AnimatedBuilder(
                          animation: _engine,
                          builder: (context, _) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                              decoration: BoxDecoration(
                                color: _engine.isPaused
                                    ? const Color(0xFF00E5FF).withValues(alpha: 0.25)
                                    : const Color(0xFF0F172A).withValues(alpha: 0.88),
                                borderRadius: BorderRadius.circular(14),
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
                                    _engine.isPaused ? Icons.play_arrow_rounded : Icons.tune_rounded,
                                    color: const Color(0xFF00E5FF),
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'Campeones (${_engine.enabledChampions.length}/5)',
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11.5,
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

                  // Estadísticas en tiempo real (Tiempo, Esquives, Racha, Reflejo en ms)
                  AnimatedBuilder(
                    animation: _engine,
                    builder: (context, _) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.88),
                          borderRadius: BorderRadius.circular(16),
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
                            const SizedBox(width: 12),
                            _buildHudMetric(
                              icon: Icons.shield_rounded,
                              color: const Color(0xFF10B981),
                              label: 'ESQUIVES',
                              value: '${_engine.dodgedCount}',
                            ),
                            const SizedBox(width: 12),
                            _buildHudMetric(
                              icon: Icons.local_fire_department_rounded,
                              color: const Color(0xFFF59E0B),
                              label: 'RACHA',
                              value: 'x${_engine.currentStreak}',
                            ),
                            const SizedBox(width: 12),
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

          // 4. BOTONES DE HECHIZOS DE INVOCADOR (Abajo a la derecha, igual a Wild Rift)
          Positioned(
            right: 28,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: AnimatedBuilder(
                animation: _engine,
                builder: (context, _) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Botón Sprint / Fantasma
                      _buildSummonerSpellButton(
                        label: 'Sprint',
                        icon: Icons.directions_run_rounded,
                        color: const Color(0xFF38BDF8),
                        cooldown: _engine.sprintCooldown,
                        maxCooldown: DodgeGameEngine.sprintMaxCooldown,
                        onTap: _engine.castSprint,
                      ),
                      const SizedBox(width: 18),
                      // Botón Destello (Flash)
                      _buildSummonerSpellButton(
                        label: 'Destello',
                        icon: Icons.flash_on_rounded,
                        color: const Color(0xFFFACC15),
                        cooldown: _engine.flashCooldown,
                        maxCooldown: DodgeGameEngine.flashMaxCooldown,
                        onTap: _engine.castFlash,
                        size: 68,
                      ),
                    ],
                  );
                },
              ),
            ),
          ),

          // 5. MODAL DE PAUSA Y CONFIGURACIÓN TÁCTICA (Filtro de Campeones + Modo Inmortal)
          AnimatedBuilder(
            animation: _engine,
            builder: (context, _) {
              if (!_engine.isPaused || _engine.isGameOver) {
                return const SizedBox.shrink();
              }
              return _buildPauseAndSettingsOverlay();
            },
          ),

          // 6. MODAL DE FIN DE PARTIDA (Cuando HP llega a 0)
          AnimatedBuilder(
            animation: _engine,
            builder: (context, _) {
              if (!_engine.isGameOver) return const SizedBox.shrink();
              return _buildGameOverOverlay();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDifficultySelector() {
    return AnimatedBuilder(
      animation: _engine,
      builder: (context, _) {
        return Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A).withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDiffChip(
                diff: DodgeDifficulty.easy,
                label: 'Fácil (2.0s)',
                activeColor: const Color(0xFF10B981),
              ),
              _buildDiffChip(
                diff: DodgeDifficulty.medium,
                label: 'Medio (Combos)',
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
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? activeColor.withValues(alpha: 0.22) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? activeColor : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 11.5,
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
        Icon(icon, color: color, size: 15),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                color: Colors.white54,
                letterSpacing: 0.5,
              ),
            ),
            Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 13,
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
                width: 2.5,
              ),
              boxShadow: isReady
                  ? [
                      BoxShadow(
                        color: color.withValues(alpha: 0.45),
                        blurRadius: 14,
                        spreadRadius: 1,
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
                      color: Colors.black.withValues(alpha: 0.65),
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
              fontSize: 11,
              fontWeight: FontWeight.w700,
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
      child: Container(
        width: 480,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.45), width: 1.5),
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
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
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
            const SizedBox(height: 10),
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
                  champ: SimChampion.lux,
                  label: 'Lux (Q, E, R 1.0s)',
                  color: const Color(0xFFF43F5E),
                ),
                _buildChampFilterChip(
                  champ: SimChampion.ezreal,
                  label: 'Ezreal (Q, R Arco)',
                  color: const Color(0xFF38BDF8),
                ),
                _buildChampFilterChip(
                  champ: SimChampion.chogath,
                  label: "Cho'Gath (Q 1.12s)",
                  color: const Color(0xFFA855F7),
                ),
                _buildChampFilterChip(
                  champ: SimChampion.ziggs,
                  label: 'Ziggs (R Mega Bomba)',
                  color: const Color(0xFFF97316),
                ),
                _buildChampFilterChip(
                  champ: SimChampion.malphite,
                  label: 'Malphite (R Flash Test)',
                  color: const Color(0xFFD97706),
                ),
              ],
            ),
            const SizedBox(height: 14),
            // Switch de Modo Práctica Inmortal
            InkWell(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _engine.immortalPracticeMode = !_engine.immortalPracticeMode;
                });
              },
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
                        'Modo Práctica Infinita (Sin morir al llegar a 0 HP)',
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
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _engine.resetGame(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: Text(
                      'Reiniciar Partida',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.bold, fontSize: 13),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                    label: Text(
                      'Continuar Entrenamiento',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w900, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ],
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
          color: active ? color.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.04),
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
                fontSize: 12,
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
      child: Container(
        width: 450,
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: const Color(0xFF0F172A),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFF00E5FF).withValues(alpha: 0.45), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00E5FF).withValues(alpha: 0.2),
              blurRadius: 28,
            ),
          ],
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
                    fontSize: 19,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
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
                  _engine.averageReactionMs > 0 ? '${_engine.averageReactionMs} ms' : 'N/A',
                  _engine.recordBestReactionMs > 0
                      ? 'Mejor: ${_engine.recordBestReactionMs} ms'
                      : 'Mejor: --',
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: const BorderSide(color: Colors.white24),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
    );
  }

  Widget _buildSummaryStat(String label, String value, String subRecord) {
    return Column(
      children: [
        Text(
          value,
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 19,
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

/// Renderizador 2D de alta velocidad para la arena, los Tótems de los Campeones Enemigos,
/// los indicadores de casteo, proyectiles y el campeón del jugador con su avatar OAuth.
class _DodgeArenaPainter extends CustomPainter {
  final DodgeGameEngine engine;
  final String userName;
  final ui.Image? avatarImage;

  _DodgeArenaPainter({
    required this.engine,
    required this.userName,
    required this.avatarImage,
  }) : super(repaint: engine);

  @override
  void paint(Canvas canvas, Size size) {
    // Escala: 1550 unidades del motor de LoL equivalen al ancho de la pantalla en Landscape
    final double scale = size.width / 1550.0;
    final Offset screenCenter = Offset(size.width / 2, size.height / 2);

    canvas.save();
    // Cámara suave centrada en el jugador (estilo Wild Rift)
    final Offset cameraOffset = screenCenter - (engine.playerPos * scale * 0.45);
    canvas.translate(cameraOffset.dx, cameraOffset.dy);
    canvas.scale(scale, scale);

    // 1. PINTAR SUELO TÁCTICO DE LA ARENA (Cuadrícula Hextech + Límites del mapa)
    _drawArenaFloor(canvas);

    // 2. PINTAR EFECTO RESIDUAL DE DESTELLO (FLASH)
    if (engine.flashVfxTimer > 0 && engine.lastFlashOrigin != null) {
      final double alpha = (engine.flashVfxTimer / 0.45).clamp(0.0, 1.0);
      final Paint flashPaint = Paint()
        ..color = const Color(0xFFFDE047).withValues(alpha: alpha * 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6.0;
      canvas.drawCircle(
        engine.lastFlashOrigin!,
        DodgeGameEngine.playerHitboxRadius * (1.5 - alpha * 0.4),
        flashPaint,
      );
    }

    // 3. PINTAR TÓTEMS DE LOS CAMPEONES ENEMIGOS Y SUS HABILIDADES (Telegrafiado + Proyectiles)
    for (final s in engine.skillshots) {
      if (s.showCasterTotem && s.type != SkillshotType.malphiteR) {
        _drawEnemyCasterTotem(canvas, s);
      }
      _drawSkillshot(canvas, s);
    }

    // 4. PINTAR JUGADOR (Avatar Google OAuth + Hitbox 2D + Barra de vida estilo Wild Rift)
    _drawPlayer(canvas);

    // 5. PINTAR TEXTOS FLOTANTES DE COMBATE
    for (final ft in engine.floatingTexts) {
      _drawFloatingText(canvas, ft);
    }

    canvas.restore();
  }

  /// Dibuja el círculo 2D del campeón enemigo en el borde desde donde lanza el ataque,
  /// con su barra de vida roja y su barra de canalización (Cast Time) para entrenar lectura periférica.
  void _drawEnemyCasterTotem(Canvas canvas, ActiveSkillshot s) {
    final Offset pos = s.casterPos;
    const double r = 56.0;

    // Sombra/halo rojo enemigo
    canvas.drawCircle(
      pos,
      r * 1.15,
      Paint()..color = s.dangerColor.withValues(alpha: 0.18),
    );
    // Cuerpo circular 2D del enemigo
    canvas.drawCircle(
      pos,
      r,
      Paint()..color = const Color(0xFF1E1B2E),
    );
    canvas.drawCircle(
      pos,
      r,
      Paint()
        ..color = s.primaryColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4.5,
    );

    // Iniciales del campeón enemigo dentro de su círculo
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: '${s.championName.substring(0, math.min(3, s.championName.length)).toUpperCase()}\n[${s.abilityKey}]',
        style: TextStyle(
          color: s.primaryColor,
          fontSize: 20,
          fontWeight: FontWeight.w900,
          height: 1.05,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));

    // Barra de casteo debajo del campeón enemigo (muestra visualmente el tiempo de casteo real)
    if (s.isCasting) {
      const double castBarW = 110.0;
      const double castBarH = 11.0;
      final Offset barPos = pos + const Offset(-castBarW / 2, r + 10);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(barPos.dx, barPos.dy, castBarW, castBarH),
          const Radius.circular(4),
        ),
        Paint()..color = Colors.black87,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(barPos.dx, barPos.dy, castBarW * s.castProgress, castBarH),
          const Radius.circular(4),
        ),
        Paint()..color = s.primaryColor,
      );
    }
  }

  void _drawArenaFloor(Canvas canvas) {
    const Rect arenaRect = Rect.fromLTWH(
      -DodgeGameEngine.worldWidth / 2,
      -DodgeGameEngine.worldHeight / 2,
      DodgeGameEngine.worldWidth,
      DodgeGameEngine.worldHeight,
    );

    final Paint bgPaint = Paint()..color = const Color(0xFF0B131E);
    canvas.drawRRect(
      RRect.fromRectAndRadius(arenaRect, const Radius.circular(36)),
      bgPaint,
    );

    // Líneas de cuadrícula cada 200 unidades LoL (ayuda a medir distancias como el Flash de 400u)
    final Paint gridPaint = Paint()
      ..color = const Color(0xFF1E293B).withValues(alpha: 0.65)
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

    // Anillo central decorativo tipo Grieta
    final Paint centerRing = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5.0;
    canvas.drawCircle(Offset.zero, 320, centerRing);

    // Borde brillante del mapa
    final Paint borderPaint = Paint()
      ..color = const Color(0xFF00E5FF).withValues(alpha: 0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6.0;
    canvas.drawRRect(
      RRect.fromRectAndRadius(arenaRect, const Radius.circular(36)),
      borderPaint,
    );
  }

  void _drawSkillshot(Canvas canvas, ActiveSkillshot s) {
    switch (s.type) {
      case SkillshotType.chogathQ:
        // Cho'Gath Q: Círculo de radio 235u que se llena durante 1.125s y estalla al 100%
        final double progress = s.castProgress;
        final Paint fillPaint = Paint()
          ..color = s.dangerColor.withValues(alpha: 0.14 + 0.22 * progress)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(s.target, s.radius * progress, fillPaint);

        final Paint borderPaint = Paint()
          ..color = s.hasImpacted ? Colors.white : s.dangerColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.hasImpacted ? 10.0 : 5.0;
        canvas.drawCircle(s.target, s.radius, borderPaint);

        _drawAbilityTag(canvas, s.target, "${s.championName} ${s.abilityKey}");
        break;

      case SkillshotType.ziggsR:
        // Ziggs R: Círculo grande exterior (430u) + epicentro crítico (230u)
        final double progress = s.castProgress;
        canvas.drawCircle(
          s.target,
          s.outerRadius,
          Paint()
            ..color = s.primaryColor.withValues(alpha: 0.10 + 0.12 * progress)
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          s.target,
          s.outerRadius,
          Paint()
            ..color = s.primaryColor.withValues(alpha: 0.75)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4.0,
        );

        // Círculo interior (epicentro 100% daño)
        canvas.drawCircle(
          s.target,
          s.radius * progress,
          Paint()
            ..color = s.dangerColor.withValues(alpha: 0.25 + 0.30 * progress)
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          s.target,
          s.radius,
          Paint()
            ..color = s.hasImpacted ? Colors.white : s.dangerColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = s.hasImpacted ? 12.0 : 5.5,
        );

        _drawAbilityTag(canvas, s.target, 'Ziggs R (Epicentro)');
        break;

      case SkillshotType.luxR:
        // Lux R: Durante 1.0s es una línea láser fina con bordes laterales cerrándose.
        // Al llegar a 1.0s se ensancha a 200u (radio 100u) con destello intenso.
        final double angle = math.atan2(s.direction.dy, s.direction.dx);
        canvas.save();
        canvas.translate(s.origin.dx, s.origin.dy);
        canvas.rotate(angle);

        if (!s.hasImpacted) {
          final double progress = s.castProgress;
          final Rect hitboxRect =
              Rect.fromLTWH(0, -s.radius, s.maxRange, s.radius * 2);
          canvas.drawRect(
            hitboxRect,
            Paint()..color = s.dangerColor.withValues(alpha: 0.12),
          );
          canvas.drawRect(
            hitboxRect,
            Paint()
              ..color = s.dangerColor.withValues(alpha: 0.45)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5,
          );

          // Línea central láser de advertencia que crece en intensidad
          canvas.drawLine(
            Offset.zero,
            Offset(s.maxRange, 0),
            Paint()
              ..color = Colors.white.withValues(alpha: 0.5 + 0.5 * progress)
              ..strokeWidth = 4.0 + 8.0 * progress,
          );
        } else {
          // ¡Disparo del láser de Lux R! Se ensancha a todo el hitbox
          final Rect beamRect =
              Rect.fromLTWH(0, -s.radius, s.maxRange, s.radius * 2);
          canvas.drawRect(
            beamRect,
            Paint()..color = s.primaryColor.withValues(alpha: 0.75),
          );
          canvas.drawRect(
            Rect.fromLTWH(0, -s.radius * 0.45, s.maxRange, s.radius * 0.9),
            Paint()..color = Colors.white,
          );
        }
        canvas.restore();
        _drawAbilityTag(
          canvas,
          s.origin + s.direction * 360,
          'Lux R (1.0s Láser)',
        );
        break;

      case SkillshotType.luxE:
        canvas.drawCircle(
          s.target,
          s.radius,
          Paint()
            ..color = s.dangerColor.withValues(alpha: 0.14)
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(
          s.target,
          s.radius,
          Paint()
            ..color = s.hasImpacted ? Colors.white : s.dangerColor
            ..style = PaintingStyle.stroke
            ..strokeWidth = s.hasImpacted ? 10.0 : 4.0,
        );
        canvas.drawCircle(
          s.currentPos,
          36.0,
          Paint()..color = s.primaryColor,
        );
        _drawAbilityTag(canvas, s.target, 'Lux E (Zona Slow)');
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
              width: s.radius * 2.4,
              height: s.radius * 2.0,
            ),
            Radius.circular(s.radius),
          );
          canvas.drawRRect(capsule, Paint()..color = s.primaryColor);
          canvas.drawRRect(
            capsule,
            Paint()
              ..color = Colors.white
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.5,
          );
          canvas.restore();
          _drawAbilityTag(
            canvas,
            s.currentPos + const Offset(0, -65),
            '${s.championName} ${s.abilityKey}',
          );
        }
        break;

      case SkillshotType.ezrealR:
        final double angle = math.atan2(s.direction.dy, s.direction.dx);
        if (s.isCasting) {
          // Línea tenue de dirección mientras Ezreal canaliza durante 1.0s
          canvas.drawLine(
            s.origin,
            s.origin + s.direction * 380,
            Paint()
              ..color = s.primaryColor.withValues(alpha: 0.45)
              ..strokeWidth = 6.0,
          );
        } else {
          canvas.save();
          canvas.translate(s.currentPos.dx, s.currentPos.dy);
          canvas.rotate(angle);

          // Dibujar arco semicircular / boomerang de radio 160u
          final Path crescent = Path()
            ..addArc(
              Rect.fromCircle(center: Offset.zero, radius: s.radius),
              -math.pi / 2,
              math.pi,
            )
            ..arcTo(
              Rect.fromCircle(
                  center: const Offset(-45, 0), radius: s.radius * 0.82),
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
              ..strokeWidth = 4.0,
          );
          canvas.restore();
          _drawAbilityTag(
            canvas,
            s.currentPos + const Offset(0, -175),
            'Ezreal R',
          );
        }
        break;

      case SkillshotType.malphiteR:
        canvas.drawCircle(
          s.target,
          s.radius,
          Paint()
            ..color = s.dangerColor.withValues(alpha: 0.22)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 4.5,
        );
        // El propio Malphite es el proyectil circular gigante que viaja hacia el jugador
        canvas.drawCircle(
          s.currentPos,
          s.radius * 0.55,
          Paint()..color = s.primaryColor,
        );
        canvas.drawCircle(
          s.currentPos,
          s.radius,
          Paint()
            ..color = s.dangerColor.withValues(alpha: 0.45)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7.0,
        );
        _drawAbilityTag(canvas, s.currentPos, '¡Malphite R!');
        break;
    }
  }

  void _drawPlayer(Canvas canvas) {
    final Offset pos = engine.playerPos;
    const double r = DodgeGameEngine.playerHitboxRadius;

    // 1. Anillo de Hitbox en el suelo (exactamente 65 unidades)
    final Color ringColor = engine.hitFlashTimer > 0
        ? const Color(0xFFEF4444)
        : (engine.sprintTimer > 0
            ? const Color(0xFF38BDF8)
            : const Color(0xFF00E5FF));

    canvas.drawCircle(
      pos,
      r,
      Paint()
        ..color = ringColor.withValues(alpha: 0.20)
        ..style = PaintingStyle.fill,
    );

    // 2. Avatar circular del usuario (Google OAuth) dentro del círculo del personaje
    final Rect avatarRect = Rect.fromCircle(center: pos, radius: r * 0.85);
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
      canvas.drawCircle(pos, r * 0.85, Paint()..color = const Color(0xFF1E293B));
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: userName.isNotEmpty ? userName[0].toUpperCase() : 'D',
          style: const TextStyle(
            color: Color(0xFF00E5FF),
            fontSize: 44,
            fontWeight: FontWeight.w900,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
    }
    canvas.restore();

    // Borde exterior del campeón
    canvas.drawCircle(
      pos,
      r,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5.0,
    );

    // 3. Barra de vida estilo Wild Rift (como la captura de Sett o no Zed)
    const double barWidth = 150.0;
    const double barHeight = 16.0;
    final Offset barTopLeft = pos + const Offset(-barWidth / 2, -r - 36);

    // Nombre del jugador encima de la barra
    final TextPainter namePainter = TextPainter(
      text: TextSpan(
        text: engine.knockupTimer > 0 ? '¡INMOVILIZADO!' : userName,
        style: TextStyle(
          color: engine.knockupTimer > 0 ? const Color(0xFFFDE047) : Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.w800,
          shadows: const [Shadow(color: Colors.black, blurRadius: 4)],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    namePainter.paint(
      canvas,
      Offset(pos.dx - namePainter.width / 2, barTopLeft.dy - 24),
    );

    // Fondo negro de la barra
    final RRect barBg = RRect.fromRectAndRadius(
      Rect.fromLTWH(barTopLeft.dx, barTopLeft.dy, barWidth, barHeight),
      const Radius.circular(5),
    );
    canvas.drawRRect(barBg, Paint()..color = const Color(0xFF090D16));

    // Vida actual en verde Wild Rift
    final double hpRatio = (engine.currentHp / engine.maxHp).clamp(0.0, 1.0);
    final Color hpColor = hpRatio > 0.5
        ? const Color(0xFF22C55E)
        : (hpRatio > 0.25 ? const Color(0xFFF59E0B) : const Color(0xFFEF4444));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(barTopLeft.dx, barTopLeft.dy, barWidth * hpRatio, barHeight),
        const Radius.circular(5),
      ),
      Paint()..color = hpColor,
    );

    // Borde metálico de la barra
    canvas.drawRRect(
      barBg,
      Paint()
        ..color = const Color(0xFFC89B3C)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0,
    );
  }

  void _drawAbilityTag(Canvas canvas, Offset pos, String label) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: label,
        style: const TextStyle(
          color: Colors.white70,
          fontSize: 18,
          fontWeight: FontWeight.bold,
          shadows: [Shadow(color: Colors.black, blurRadius: 4)],
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
          fontSize: 24,
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
  bool shouldRepaint(covariant _DodgeArenaPainter oldDelegate) => false;
}

/// Dibuja el Joystick virtual en la esquina inferior izquierda (o donde el pulgar toque)
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
    final Offset baseCenter = origin ?? Offset(110, size.height - 95);
    final Offset knobCenter = origin != null ? knob : baseCenter;

    canvas.drawCircle(
      baseCenter,
      maxRadius,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.32)
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(
      baseCenter,
      maxRadius,
      Paint()
        ..color = const Color(0xFFC89B3C).withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    canvas.drawCircle(
      knobCenter,
      24,
      Paint()
        ..color = origin != null
            ? const Color(0xFF00E5FF).withValues(alpha: 0.85)
            : Colors.white.withValues(alpha: 0.45),
    );
  }

  @override
  bool shouldRepaint(covariant _JoystickOverlayPainter oldDelegate) {
    return oldDelegate.origin != origin || oldDelegate.knob != knob;
  }
}
