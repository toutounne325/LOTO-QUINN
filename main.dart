// ============================================================================
// Protection légale pour le trading, propriété exclusive de Pirate Pips ™.
// AVERTISSEMENT LÉGAL (DISCLAIMER) : Ce logiciel est fourni à titre purement
// informatif, éducatif et expérimental. Le trading et les opérations sur
// instruments financiers ou jeux comportent un risque élevé de perte en capital.
// Les performances passées ne préjugent pas des résultats futurs. Pirate Pips ™
// décline toute responsabilité en cas de pertes financières directes ou indirectes.
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);
  runApp(const LotoQuineApp());
}

class LotoQuineApp extends StatelessWidget {
  const LotoQuineApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Loto Quine Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFD32F2F),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F6F9),
      ),
      home: const LotoHomePage(),
    );
  }
}

// ============================================================================
// MODÈLE D'UN CARTON DE LOTO QUINE (3 LIGNES x 9 COLONNES)
// ============================================================================
class LotoCarton {
  String id;
  String name;
  int colorValue;
  // Grille 3x9 : 0 = case vide, 1..90 = numéro
  List<List<int>> grid;

  LotoCarton({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.grid,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'colorValue': colorValue,
        'grid': grid,
      };

  factory LotoCarton.fromJson(Map<String, dynamic> json) {
    final rawGrid = json['grid'] as List<dynamic>;
    final parsedGrid = rawGrid
        .map((row) => (row as List<dynamic>).map((e) => e as int).toList())
        .toList();
    return LotoCarton(
      id: json['id'] as String,
      name: json['name'] as String,
      colorValue: (json['colorValue'] as int?) ?? 0xFFD32F2F,
      grid: parsedGrid,
    );
  }

  // Retourne tous les numéros non nuls du carton
  List<int> get allNumbers {
    final nums = <int>[];
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 9; c++) {
        if (grid[r][c] > 0) nums.add(grid[r][c]);
      }
    }
    return nums;
  }

  // Nombre de numéros restants sur une ligne précise (0, 1 ou 2)
  int remainingInRow(int row, Set<int> drawn) {
    int count = 0;
    for (int c = 0; c < 9; c++) {
      final val = grid[row][c];
      if (val > 0 && !drawn.contains(val)) {
        count++;
      }
    }
    return count;
  }

  // Nombre de lignes complètes
  int completedRowsCount(Set<int> drawn) {
    int completed = 0;
    for (int r = 0; r < 3; r++) {
      int totalInRow = 0;
      int hitInRow = 0;
      for (int c = 0; c < 9; c++) {
        final val = grid[r][c];
        if (val > 0) {
          totalInRow++;
          if (drawn.contains(val)) hitInRow++;
        }
      }
      if (totalInRow > 0 && hitInRow == totalInRow) {
        completed++;
      }
    }
    return completed;
  }

  // Nombre total de numéros restants sur tout le carton
  int remainingTotal(Set<int> drawn) {
    int count = 0;
    for (final n in allNumbers) {
      if (!drawn.contains(n)) count++;
    }
    return count;
  }

  // Combien de numéros manquent pour atteindre l'objectif actuel (1=1 ligne, 2=2 lignes, 3=Carton plein)
  int numbersNeededForGoal(int goalMode, Set<int> drawn) {
    final r0 = remainingInRow(0, drawn);
    final r1 = remainingInRow(1, drawn);
    final r2 = remainingInRow(2, drawn);
    final list = [r0, r1, r2]..sort();

    if (goalMode == 1) {
      return list[0]; // La ligne la plus proche
    } else if (goalMode == 2) {
      return list[0] + list[1]; // Les 2 lignes les plus proches
    } else {
      return r0 + r1 + r2; // Carton plein
    }
  }

  // Les numéros précis qui font gagner immédiatement si tirés au prochain tour
  List<int> winningNextNumbers(int goalMode, Set<int> drawn) {
    if (numbersNeededForGoal(goalMode, drawn) != 1) return [];
    final needed = <int>[];
    if (goalMode == 1) {
      for (int r = 0; r < 3; r++) {
        if (remainingInRow(r, drawn) == 1) {
          for (int c = 0; c < 9; c++) {
            final v = grid[r][c];
            if (v > 0 && !drawn.contains(v)) needed.add(v);
          }
        }
      }
    } else if (goalMode == 2 && completedRowsCount(drawn) == 1) {
      for (int r = 0; r < 3; r++) {
        if (remainingInRow(r, drawn) == 1) {
          for (int c = 0; c < 9; c++) {
            final v = grid[r][c];
            if (v > 0 && !drawn.contains(v)) needed.add(v);
          }
        }
      }
    } else if (goalMode == 3 && remainingTotal(drawn) == 1) {
      for (final v in allNumbers) {
        if (!drawn.contains(v)) needed.add(v);
      }
    }
    return needed.toSet().toList()..sort();
  }
}

// ============================================================================
// ÉCRAN PRINCIPAL AVEC LES 3 ONGLETS : CARTONS | PARTIE | TIRAGE & STATS
// ============================================================================
class LotoHomePage extends StatefulWidget {
  const LotoHomePage({super.key});

  @override
  State<LotoHomePage> createState() => _LotoHomePageState();
}

class _LotoHomePageState extends State<LotoHomePage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  List<LotoCarton> _cartons = [];
  List<int> _drawnHistory = [];
  int _goalMode = 1; // 1 = 1 Ligne, 2 = 2 Lignes, 3 = Carton Plein
  int _gamesPlayed = 1;
  int _victoriesCount = 0;
  Set<int> _everDrawnNumbers = {};
  Set<String> _alreadyCelebratedKeys = {};

  String _keypadInput = '';
  String _lastFeedback = 'Tapez un numéro tiré (1 à 90)';

  final List<int> _paletteColors = const [
    0xFFD32F2F, // Rouge Quine classique
    0xFF1976D2, // Bleu Roi
    0xFF2E7D32, // Vert Émeraude
    0xFF7B1FA2, // Violet
    0xFFE65100, // Orange
    0xFF37474F, // Anthracite
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Set<int> get _drawnSet => _drawnHistory.toSet();

  // Colonnes officielles du Loto Quine (1-9, 10-19, ..., 80-90)
  static int columnForNumber(int n) {
    if (n <= 0) return 0;
    if (n >= 80) return 8;
    return n ~/ 10;
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();
    final cartonsRaw = prefs.getString('loto_cartons_v1');
    final drawnRaw = prefs.getString('loto_drawn_v1');
    final everRaw = prefs.getString('loto_ever_drawn_v1');

    setState(() {
      if (cartonsRaw != null) {
        final list = jsonDecode(cartonsRaw) as List<dynamic>;
        _cartons = list
            .map((e) => LotoCarton.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      if (drawnRaw != null) {
        _drawnHistory =
            (jsonDecode(drawnRaw) as List<dynamic>).map((e) => e as int).toList();
      }
      if (everRaw != null) {
        _everDrawnNumbers =
            (jsonDecode(everRaw) as List<dynamic>).map((e) => e as int).toSet();
      }
      _goalMode = prefs.getInt('loto_goal_v1') ?? 1;
      _gamesPlayed = prefs.getInt('loto_games_v1') ?? 1;
      _victoriesCount = prefs.getInt('loto_wins_v1') ?? 0;
    });
  }

  Future<void> _saveData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'loto_cartons_v1',
      jsonEncode(_cartons.map((c) => c.toJson()).toList()),
    );
    await prefs.setString('loto_drawn_v1', jsonEncode(_drawnHistory));
    await prefs.setString(
      'loto_ever_drawn_v1',
      jsonEncode(_everDrawnNumbers.toList()),
    );
    await prefs.setInt('loto_goal_v1', _goalMode);
    await prefs.setInt('loto_games_v1', _gamesPlayed);
    await prefs.setInt('loto_wins_v1', _victoriesCount);
  }

  // ==========================================================================
  // TIRAGE D'UN NUMÉRO & VÉRIFICATION AUTOMATIQUE DES VICTOIRES
  // ==========================================================================
  void _submitNumber(int number) {
    if (number < 1 || number > 90) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez entrer un numéro entre 1 et 90.'),
          backgroundColor: Colors.redAccent,
          duration: Duration(seconds: 1),
        ),
      );
      return;
    }

    HapticFeedback.mediumImpact();

    if (_drawnSet.contains(number)) {
      setState(() {
        _keypadInput = '';
        _lastFeedback = '⚠️ Le numéro $number a déjà été tiré !';
      });
      return;
    }

    int hitCount = 0;
    for (final c in _cartons) {
      if (c.allNumbers.contains(number)) hitCount++;
    }

    setState(() {
      _drawnHistory.insert(0, number);
      _everDrawnNumbers.add(number);
      _keypadInput = '';
      if (hitCount > 0) {
        _lastFeedback =
            '✅ Numéro $number : présent sur $hitCount carton${hitCount > 1 ? "s" : ""} !';
      } else {
        _lastFeedback = '⚪ Numéro $number : absent de vos cartons.';
      }
    });

    _saveData();
    _checkWinningCartons();
  }

  void _toggleNumberFromGrid(int number) {
    HapticFeedback.selectionClick();
    if (_drawnSet.contains(number)) {
      setState(() {
        _drawnHistory.remove(number);
        _lastFeedback = '↩️ Numéro $number retiré du tirage.';
      });
      _saveData();
    } else {
      _submitNumber(number);
    }
  }

  void _undoLastNumber() {
    if (_drawnHistory.isEmpty) return;
    HapticFeedback.lightImpact();
    final removed = _drawnHistory.first;
    setState(() {
      _drawnHistory.removeAt(0);
      _lastFeedback = '↩️ Dernier numéro ($removed) annulé.';
    });
    _saveData();
  }

  void _confirmResetDraw() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Nouvelle partie / Vider le tirage ?'),
        content: const Text(
          'Tous les jetons seront retirés de vos cartons pour démarrer une nouvelle partie (vos cartons restent enregistrés).',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD32F2F),
              foregroundColor: Colors.white,
            ),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _drawnHistory.clear();
                _alreadyCelebratedKeys.clear();
                _goalMode = 1;
                _gamesPlayed++;
                _keypadInput = '';
                _lastFeedback = 'Nouvelle partie démarrée ! Objectif : 1 Ligne';
              });
              _saveData();
            },
            child: const Text('Nouvelle partie'),
          ),
        ],
      ),
    );
  }

  void _checkWinningCartons() {
    final drawn = _drawnSet;
    final newlyWon = <LotoCarton>[];

    for (final c in _cartons) {
      final key = '${c.id}_goal_$_goalMode';
      if (_alreadyCelebratedKeys.contains(key)) continue;

      final needed = c.numbersNeededForGoal(_goalMode, drawn);
      if (needed == 0 && c.allNumbers.isNotEmpty) {
        _alreadyCelebratedKeys.add(key);
        newlyWon.add(c);
      }
    }

    if (newlyWon.isNotEmpty) {
      HapticFeedback.heavyImpact();
      setState(() {
        _victoriesCount += newlyWon.length;
      });
      _saveData();

      final goalTitle = _goalMode == 1
          ? 'QUINE (1 LIGNE) !'
          : _goalMode == 2
              ? 'DOUBLE QUINE (2 LIGNES) !'
              : 'CARTON PLEIN ! 🏆';

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFFFFF8E1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Color(0xFFFFB300), width: 3),
          ),
          title: Column(
            children: [
              const Icon(Icons.emoji_events, size: 60, color: Color(0xFFFF8F00)),
              const SizedBox(height: 8),
              Text(
                '🎉 $goalTitle',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Color(0xFFB71C1C),
                  fontSize: 22,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Carton(s) gagnant(s) :',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const SizedBox(height: 10),
              ...newlyWon.map(
                (c) => Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Color(c.colorValue),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle, color: Colors.white),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          c.name,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            if (_goalMode < 3)
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1976D2),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.arrow_forward),
                label: Text(
                  _goalMode == 1
                      ? 'Passer aux 2 Lignes'
                      : 'Passer au Carton Plein',
                ),
                onPressed: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _goalMode++;
                  });
                  _saveData();
                },
              ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Fermer'),
            ),
          ],
        ),
      );
    }
  }

  // ==========================================================================
  // CHARGER DES CARTONS DE DÉMONSTRATION (COMME L'ÉCRAN 2 & 5)
  // ==========================================================================
  void _loadDemoCartons() {
    final demo1 = LotoCarton(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: 'Carton de Paul',
      colorValue: 0xFFD32F2F,
      grid: [
        [3, 16, 0, 35, 44, 0, 60, 0, 88],
        [8, 0, 22, 0, 0, 56, 66, 0, 87],
        [0, 0, 29, 0, 42, 54, 0, 70, 0],
      ],
    );
    // Ajustement strict 5 numéros par ligne (15 au total)
    demo1.grid[0] = [3, 16, 0, 35, 44, 0, 60, 0, 0];
    demo1.grid[1] = [8, 0, 22, 0, 0, 56, 66, 0, 88];
    demo1.grid[2] = [0, 0, 29, 0, 42, 54, 0, 70, 87];

    final demo2 = LotoCarton(
      id: (DateTime.now().millisecondsSinceEpoch + 1).toString(),
      name: 'Carton de Marie',
      colorValue: 0xFF1976D2,
      grid: [
        [5, 12, 0, 33, 45, 0, 0, 0, 89],
        [2, 14, 25, 0, 0, 0, 60, 72, 0],
        [8, 19, 0, 0, 41, 55, 0, 0, 90],
      ],
    );

    setState(() {
      _cartons.addAll([demo1, demo2]);
    });
    _saveData();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('2 cartons de démonstration ajoutés avec succès !'),
        backgroundColor: Colors.green,
      ),
    );
  }

  // ==========================================================================
  // OUVERTURE DE L'ÉDITEUR / SCANNER PHOTO DE CARTON
  // ==========================================================================
  Future<void> _openCardCreator({
    LotoCarton? existing,
    ImageSource? autoScanSource,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) => CartonEditorScreen(
          existingCarton: existing,
          defaultIndex: _cartons.length + 1,
          paletteColors: _paletteColors,
          autoScanSource: autoScanSource,
          onSave: (savedCarton, createAnother) {
            setState(() {
              final idx = _cartons.indexWhere((c) => c.id == savedCarton.id);
              if (idx >= 0) {
                _cartons[idx] = savedCarton;
              } else {
                _cartons.add(savedCarton);
              }
            });
            _saveData();
          },
        ),
      ),
    );
  }

  // ==========================================================================
  // INTERFACE PRINCIPALE
  // ==========================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF151922),
        foregroundColor: Colors.white,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFD32F2F),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'LOTO',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 1,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'TRACKER PRO',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Scanner un carton',
            icon: const Icon(Icons.camera_alt, color: Colors.amberAccent),
            onPressed: () =>
                _openCardCreator(autoScanSource: ImageSource.camera),
          ),
          IconButton(
            tooltip: 'Ajouter un carton',
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => _openCardCreator(),
          ),
          IconButton(
            tooltip: 'Nouvelle partie (vider le tirage)',
            icon: const Icon(Icons.refresh),
            onPressed: _confirmResetDraw,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFFFFC107),
          indicatorWeight: 3.5,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          labelStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 13,
          ),
          tabs: [
            Tab(text: 'CARTONS (${_cartons.length})'),
            const Tab(text: 'PARTIE EN COURS'),
            Tab(text: 'TIRAGE (${_drawnHistory.length})'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCartonsTab(),
          _buildPartieTab(),
          _buildStatsTab(),
        ],
      ),
    );
  }

  // ==========================================================================
  // ONGLET 1 : MES CARTONS (SCAN PHOTO + CRÉATION MANUELLE)
  // ==========================================================================
  Widget _buildCartonsTab() {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // Carte d'action principale : SCANNER PAR APPAREIL PHOTO
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF1565C0), Color(0xFF0D47A1)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              const Text(
                'AJOUTER VOS CARTONS PHYSIQUES',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Prenez en photo votre carton Quine classique ou saisissez vos 15 numéros manuellement.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFFC107),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.camera_alt, size: 26),
                  label: const Text(
                    'SCANNER UN CARTON (APPAREIL PHOTO)',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                  ),
                  onPressed: () =>
                      _openCardCreator(autoScanSource: ImageSource.camera),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white54),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.photo_library, size: 20),
                      label: const Text('Photo Galerie'),
                      onPressed: () =>
                          _openCardCreator(autoScanSource: ImageSource.gallery),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: const Color(0xFF0D47A1),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      icon: const Icon(Icons.keyboard, size: 20),
                      label: const Text(
                        'Saisie Manuelle',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () => _openCardCreator(),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),

        // Si aucun carton : écran d'accueil avec bouton Démo
        if (_cartons.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.black12),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.grid_on_rounded,
                  size: 56,
                  color: Color(0xFFD32F2F),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Vous ne possédez aucun carton.\nPour utiliser l\'application, créez ou scannez au moins un carton.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.black87),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black87,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Charger 2 cartons Démo'),
                  onPressed: _loadDemoCartons,
                ),
              ],
            ),
          )
        else ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Mes Cartons enregistrés (${_cartons.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.play_circle_fill, color: Colors.green),
                label: const Text(
                  'Lancer la partie',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                onPressed: () => _tabController.animateTo(1),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._cartons.map((carton) => _buildCartonCardWidget(carton, false)),
        ],
      ],
    );
  }

  // ==========================================================================
  // ONGLET 2 : PARTIE EN COURS (PAVÉ EXPRESS + SUIVI EN DIRECT)
  // ==========================================================================
  Widget _buildPartieTab() {
    final drawn = _drawnSet;

    // Tri automatique des cartons : les plus proches de gagner en haut !
    final sortedCartons = List<LotoCarton>.from(_cartons)
      ..sort((a, b) {
        final na = a.numbersNeededForGoal(_goalMode, drawn);
        final nb = b.numbersNeededForGoal(_goalMode, drawn);
        return na.compareTo(nb);
      });

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        // 1. Sélecteur de mode : [ 1 Ligne ] [ 2 Lignes ] [ Carton Plein ]
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black12),
          ),
          child: Row(
            children: [
              _buildGoalButton(1, '1 Ligne (Quine)'),
              _buildGoalButton(2, '2 Lignes'),
              _buildGoalButton(3, 'Carton Plein 🏆'),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 2. Historique horizontal des derniers numéros tirés
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Tirage en cours (${_drawnHistory.length}/90)',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                  if (_drawnHistory.isNotEmpty)
                    InkWell(
                      onTap: _undoLastNumber,
                      child: const Row(
                        children: [
                          Icon(Icons.undo, size: 16, color: Colors.redAccent),
                          SizedBox(width: 4),
                          Text(
                            'Annuler dernier',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.redAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              if (_drawnHistory.isEmpty)
                const Text(
                  'Aucun numéro tiré pour le moment.',
                  style: TextStyle(color: Colors.black45, fontSize: 12),
                )
              else
                SizedBox(
                  height: 36,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: _drawnHistory.length,
                    itemBuilder: (ctx, i) {
                      final num = _drawnHistory[i];
                      final isFirst = i == 0;
                      return Container(
                        margin: const EdgeInsets.only(right: 6),
                        width: 36,
                        height: 36,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isFirst
                              ? const Color(0xFFD32F2F)
                              : const Color(0xFFE0E0E0),
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '$num',
                          style: TextStyle(
                            color: isFirst ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.w900,
                            fontSize: 14,
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 3. PAVÉ NUMÉRIQUE EXPRESS ("TAPER UN NUMÉRO TIRÉ")
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF1565C0),
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [
              BoxShadow(
                color: Colors.black12,
                blurRadius: 6,
                offset: Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'TAPER UN NUMÉRO TIRÉ :',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Container(
                    width: 90,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      _keypadInput.isEmpty ? '--' : _keypadInput,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0D47A1),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFC107),
                      foregroundColor: Colors.black,
                      minimumSize: const Size(70, 44),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: _keypadInput.isEmpty
                        ? null
                        : () {
                            final val = int.tryParse(_keypadInput);
                            if (val != null) _submitNumber(val);
                          },
                    child: const Text(
                      'OK',
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Pavé 0 à 9 compact en 2 lignes (ultra rapide au pouce)
              Row(
                children: [1, 2, 3, 4, 5, 6]
                    .map((d) => _buildDigitKey(d.toString()))
                    .toList(),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  ...[7, 8, 9, 0].map((d) => _buildDigitKey(d.toString())),
                  Expanded(
                    flex: 2,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.redAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        icon: const Icon(Icons.backspace_outlined, size: 18),
                        label: const Text(
                          'EFFACER',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            _keypadInput = '';
                          });
                        },
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                _lastFeedback,
                style: const TextStyle(
                  color: Colors.amberAccent,
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // 4. LISTE DES CARTONS SUIVIS EN TEMPS RÉEL
        if (sortedCartons.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Ajouter ou scanner mon premier carton'),
                onPressed: () => _tabController.animateTo(0),
              ),
            ),
          )
        else ...[
          const Text(
            'Suivi de mes cartons (triés du plus proche au plus loin) :',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 8),
          ...sortedCartons.map((c) => _buildCartonCardWidget(c, true)),
        ],
      ],
    );
  }

  Widget _buildGoalButton(int mode, String label) {
    final selected = _goalMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _goalMode = mode;
          });
          _saveData();
          _checkWinningCartons();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF1565C0) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: selected ? Colors.white : Colors.black87,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDigitKey(String digit) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E88E5),
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onPressed: () {
            HapticFeedback.selectionClick();
            setState(() {
              if (_keypadInput.length < 2) {
                _keypadInput += digit;
              } else {
                _keypadInput = digit;
              }
            });
          },
          child: Text(
            digit,
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w900),
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // WIDGET VISUEL D'UN CARTON QUINE CLASSIQUE 3x9
  // ==========================================================================
  Widget _buildCartonCardWidget(LotoCarton carton, bool isGameView) {
    final drawn = _drawnSet;
    final r0 = carton.remainingInRow(0, drawn);
    final r1 = carton.remainingInRow(1, drawn);
    final r2 = carton.remainingInRow(2, drawn);
    final totalRem = carton.remainingTotal(drawn);
    final neededForGoal = carton.numbersNeededForGoal(_goalMode, drawn);
    final hotNumbers = carton.winningNextNumbers(_goalMode, drawn);
    final cardColor = Color(carton.colorValue);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: neededForGoal == 0
              ? Colors.green
              : neededForGoal == 1
                  ? Colors.orange
                  : Colors.black12,
          width: neededForGoal <= 1 ? 2.5 : 1,
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête du carton
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 8,
                      backgroundColor: cardColor,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        carton.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (hotNumbers.isNotEmpty)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF6F00),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '🔥 Attend le : ${hotNumbers.join(", ")}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 11.5,
                    ),
                  ),
                ),
              if (!isGameView) ...[
                IconButton(
                  icon: const Icon(Icons.edit, size: 20, color: Colors.blueGrey),
                  onPressed: () => _openCardCreator(existing: carton),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline,
                      size: 20, color: Colors.redAccent),
                  onPressed: () {
                    setState(() {
                      _cartons.removeWhere((c) => c.id == carton.id);
                    });
                    _saveData();
                  },
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),

          // Grille 3x9 style Carton Quine Officiel
          Container(
            padding: const EdgeInsets.all(5),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: cardColor, width: 2),
            ),
            child: Column(
              children: List.generate(3, (r) {
                return Padding(
                  padding: EdgeInsets.only(bottom: r < 2 ? 4 : 0),
                  child: Row(
                    children: List.generate(9, (c) {
                      final val = carton.grid[r][c];
                      final isHit = val > 0 && drawn.contains(val);
                      return Expanded(
                        child: GestureDetector(
                          onTap: val > 0 && isGameView
                              ? () => _toggleNumberFromGrid(val)
                              : null,
                          child: Container(
                            height: 38,
                            margin: EdgeInsets.only(right: c < 8 ? 3.5 : 0),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: val == 0 ? cardColor : Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.85),
                                width: 1.2,
                              ),
                            ),
                            child: val == 0
                                ? const SizedBox.shrink()
                                : Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Text(
                                        '$val',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w900,
                                          fontSize: 16,
                                          color: isHit
                                              ? Colors.white
                                              : Colors.black87,
                                        ),
                                      ),
                                      if (isHit)
                                        Container(
                                          width: 30,
                                          height: 30,
                                          alignment: Alignment.center,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF2E7D32)
                                                .withOpacity(0.92),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 1.5,
                                            ),
                                          ),
                                          child: Text(
                                            '$val',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                        ),
                      );
                    }),
                  ),
                );
              }),
            ),
          ),

          // Badges de progression sous le carton (Ligne 1, Ligne 2, Ligne 3, Carton Plein)
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _buildStatusPill('Ligne 1', r0),
              _buildStatusPill('Ligne 2', r1),
              _buildStatusPill('Ligne 3', r2),
              _buildStatusPill('Carton Plein', totalRem, isFullCard: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusPill(String label, int remaining,
      {bool isFullCard = false}) {
    Color bg;
    String text;
    if (remaining == 0) {
      bg = const Color(0xFF2E7D32);
      text = '$label : Gagné ! 🎉';
    } else if (remaining == 1) {
      bg = const Color(0xFFD32F2F);
      text = '$label : Encore 1 !';
    } else {
      bg = isFullCard ? const Color(0xFF455A64) : const Color(0xFF78909C);
      text = '$label : $remaining restants';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 11.5,
        ),
      ),
    );
  }

  // ==========================================================================
  // ONGLET 3 : STATISTIQUES & GRILLE INTERACTIVE 1 À 90 (COMME L'ÉCRAN 4)
  // ==========================================================================
  Widget _buildStatsTab() {
    final drawn = _drawnSet;
    final presentOnCards = <int>{};
    for (final c in _cartons) {
      presentOnCards.addAll(c.allNumbers);
    }

    final neverDrawn = <int>[];
    for (int i = 1; i <= 90; i++) {
      if (!_everDrawnNumbers.contains(i)) neverDrawn.add(i);
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _buildStatTile('$_gamesPlayed partie(s) jouée(s)', Icons.casino),
        const SizedBox(height: 6),
        _buildStatTile(
            '${_drawnHistory.length} nombre(s) tiré(s) sur 90', Icons.ballot),
        const SizedBox(height: 6),
        _buildStatTile('$_victoriesCount victoire(s)', Icons.emoji_events),
        const SizedBox(height: 12),

        // Nombres jamais tirés
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.black12),
          ),
          child: Column(
            children: [
              Text(
                'Nombres jamais tirés (${neverDrawn.length}) :',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 36,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: neverDrawn.length,
                  itemBuilder: (ctx, i) => Container(
                    width: 34,
                    margin: const EdgeInsets.only(right: 4),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF9E9E9E),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      '${neverDrawn[i]}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Grille complète 1 à 90 interactive
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.black12),
          ),
          child: Column(
            children: [
              const Text(
                'Grille 1 à 90 (touchez une case pour cocher/décocher)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLegendDot(const Color(0xFF2E7D32), 'Tiré'),
                  const SizedBox(width: 12),
                  _buildLegendDot(
                      const Color(0xFF1565C0), 'Sur vos cartons'),
                  const SizedBox(width: 12),
                  _buildLegendDot(const Color(0xFF9E9E9E), 'Absent'),
                ],
              ),
              const SizedBox(height: 10),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: 90,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 10,
                  crossAxisSpacing: 3,
                  mainAxisSpacing: 3,
                ),
                itemBuilder: (ctx, index) {
                  final num = index + 1;
                  final isDrawn = drawn.contains(num);
                  final isPresent = presentOnCards.contains(num);

                  Color bg = const Color(0xFF9E9E9E);
                  if (isDrawn) {
                    bg = const Color(0xFF2E7D32);
                  } else if (isPresent) {
                    bg = const Color(0xFF1565C0);
                  }

                  return GestureDetector(
                    onTap: () => _toggleNumberFromGrid(num),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: bg,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '$num',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatTile(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFD32F2F), size: 22),
          const SizedBox(width: 10),
          Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendDot(Color color, String label) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 12)),
      ],
    );
  }
}

// ============================================================================
// ÉCRAN DE CRÉATION & SCANNER PHOTO OCR DES CARTONS DE LOTO QUINE
// ============================================================================
class CartonEditorScreen extends StatefulWidget {
  final LotoCarton? existingCarton;
  final int defaultIndex;
  final List<int> paletteColors;
  final ImageSource? autoScanSource;
  final void Function(LotoCarton carton, bool createAnother) onSave;

  const CartonEditorScreen({
    super.key,
    this.existingCarton,
    required this.defaultIndex,
    required this.paletteColors,
    this.autoScanSource,
    required this.onSave,
  });

  @override
  State<CartonEditorScreen> createState() => _CartonEditorScreenState();
}

class _CartonEditorScreenState extends State<CartonEditorScreen> {
  late TextEditingController _nameCtrl;
  late TextEditingController _line1Ctrl;
  late TextEditingController _line2Ctrl;
  late TextEditingController _line3Ctrl;

  late int _selectedColor;
  late List<List<int>> _grid;
  bool _isScanning = false;
  String _scanStatus = '';

  final ImagePicker _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    final ex = widget.existingCarton;
    _nameCtrl = TextEditingController(
      text: ex?.name ?? 'Carton ${widget.defaultIndex}',
    );
    _selectedColor = ex?.colorValue ?? widget.paletteColors.first;
    _grid = ex != null
        ? ex.grid.map((r) => List<int>.from(r)).toList()
        : List.generate(3, (_) => List.filled(9, 0));

    _line1Ctrl = TextEditingController(text: _rowToText(0));
    _line2Ctrl = TextEditingController(text: _rowToText(1));
    _line3Ctrl = TextEditingController(text: _rowToText(2));

    if (widget.autoScanSource != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scanCartonWithCamera(widget.autoScanSource!);
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _line1Ctrl.dispose();
    _line2Ctrl.dispose();
    _line3Ctrl.dispose();
    super.dispose();
  }

  String _rowToText(int r) {
    final nums = _grid[r].where((v) => v > 0).toList();
    return nums.join(' ');
  }

  void _syncLinesFromGrid() {
    _line1Ctrl.text = _rowToText(0);
    _line2Ctrl.text = _rowToText(1);
    _line3Ctrl.text = _rowToText(2);
  }

  // Convertit une ligne saisie ("8 16 35 44 70") vers les 9 colonnes officielles du carton
  void _parseLineIntoGrid(int row, String text) {
    final matches = RegExp(r'\d+').allMatches(text);
    final newRow = List<int>.filled(9, 0);
    for (final m in matches) {
      final n = int.tryParse(m.group(0)!);
      if (n != null && n >= 1 && n <= 90) {
        final col = _LotoHomePageState.columnForNumber(n);
        newRow[col] = n;
      }
    }
    setState(() {
      _grid[row] = newRow;
    });
  }

  // ==========================================================================
  // MOTEUR OCR DE RECONNAISSANCE DE CARTON LOTO QUINE PAR APPAREIL PHOTO
  // ==========================================================================
  Future<void> _scanCartonWithCamera(ImageSource source) async {
    try {
      final XFile? photo = await _picker.pickImage(
        source: source,
        imageQuality: 92,
      );
      if (photo == null) return;

      setState(() {
        _isScanning = true;
        _scanStatus = 'Analyse des numéros du carton en cours...';
      });

      final inputImage = InputImage.fromFile(File(photo.path));
      final textRecognizer =
          TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText recognizedText =
          await textRecognizer.processImage(inputImage);
      await textRecognizer.close();

      // Extraction de tous les nombres entre 1 et 90 avec leur position (X, Y, hauteur)
      final detectedItems = <_DetectedNumber>[];

      for (final block in recognizedText.blocks) {
        for (final line in block.lines) {
          for (final element in line.elements) {
            final rect = element.boundingBox;
            final clean = element.text.replaceAll(RegExp(r'[^0-9]'), '');
            if (clean.isEmpty) continue;

            // Si MLKit colle 2 nombres (ex: "3544" sur un carton serré), on les découpe par paires
            if (clean.length == 4) {
              final n1 = int.tryParse(clean.substring(0, 2));
              final n2 = int.tryParse(clean.substring(2, 4));
              if (n1 != null && n1 >= 1 && n1 <= 90) {
                detectedItems.add(_DetectedNumber(
                  value: n1,
                  cx: rect.left + rect.width * 0.25,
                  cy: rect.center.dy,
                  height: rect.height,
                ));
              }
              if (n2 != null && n2 >= 1 && n2 <= 90) {
                detectedItems.add(_DetectedNumber(
                  value: n2,
                  cx: rect.left + rect.width * 0.75,
                  cy: rect.center.dy,
                  height: rect.height,
                ));
              }
            } else if (clean.length <= 2) {
              final val = int.tryParse(clean);
              if (val != null && val >= 1 && val <= 90) {
                detectedItems.add(_DetectedNumber(
                  value: val,
                  cx: rect.center.dx,
                  cy: rect.center.dy,
                  height: rect.height,
                ));
              }
            }
          }
        }
      }

      if (detectedItems.isEmpty) {
        setState(() {
          _isScanning = false;
          _scanStatus =
              '⚠️ Aucun numéro détecté. Cadrez bien le carton à plat et réessayez.';
        });
        return;
      }

      // Filtrer les petits numéros doublons imprimés sous les grands chiffres des cartons Quine
      detectedItems.sort((a, b) => b.height.compareTo(a.height));
      final maxH = detectedItems.first.height;
      final bigEnough =
          detectedItems.where((e) => e.height >= maxH * 0.38).toList();

      // Dédupliquer (chaque numéro sur un carton de loto est unique) en gardant le plus grand
      final uniqueMap = <int, _DetectedNumber>{};
      for (final item in bigEnough) {
        if (!uniqueMap.containsKey(item.value)) {
          uniqueMap[item.value] = item;
        }
      }

      final uniqueList = uniqueMap.values.toList();
      // Trier verticalement (du haut vers le bas du carton)
      uniqueList.sort((a, b) => a.cy.compareTo(b.cy));

      // Répartir en 3 lignes (Ligne 1 = haut, Ligne 2 = milieu, Ligne 3 = bas)
      final newGrid = List.generate(3, (_) => List.filled(9, 0));

      if (uniqueList.isNotEmpty) {
        final minY = uniqueList.first.cy;
        final maxY = uniqueList.last.cy;
        final spanY = (maxY - minY) <= 1 ? 1.0 : (maxY - minY);

        for (final item in uniqueList) {
          int rowIdx;
          if (uniqueList.length >= 9) {
            final relY = (item.cy - minY) / spanY;
            if (relY < 0.34) {
              rowIdx = 0;
            } else if (relY < 0.67) {
              rowIdx = 1;
            } else {
              rowIdx = 2;
            }
          } else {
            rowIdx = uniqueList.indexOf(item) ~/ 5;
            if (rowIdx > 2) rowIdx = 2;
          }

          final colIdx = _LotoHomePageState.columnForNumber(item.value);
          // Si la case est déjà prise sur cette ligne, chercher une ligne libre dans la même colonne
          if (newGrid[rowIdx][colIdx] == 0) {
            newGrid[rowIdx][colIdx] = item.value;
          } else {
            for (int altR = 0; altR < 3; altR++) {
              if (newGrid[altR][colIdx] == 0) {
                newGrid[altR][colIdx] = item.value;
                break;
              }
            }
          }
        }
      }

      final totalFound = newGrid
          .expand((r) => r)
          .where((v) => v > 0)
          .length;

      setState(() {
        _grid = newGrid;
        _syncLinesFromGrid();
        _isScanning = false;
        _scanStatus =
            '✅ $totalFound numéros détectés ! Vérifiez la grille ci-dessous (touchez une case pour corriger).';
      });
    } catch (e) {
      setState(() {
        _isScanning = false;
        _scanStatus = 'Erreur lors de la lecture photo : $e';
      });
    }
  }

  // Toucher une case de la grille 3x9 pour modifier manuellement un numéro
  void _editSingleCell(int row, int col) {
    final minVal = col == 0 ? 1 : col * 10;
    final maxVal = col == 8 ? 90 : (col * 10 + 9);
    final current = _grid[row][col];
    final ctrl = TextEditingController(text: current > 0 ? '$current' : '');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Ligne ${row + 1} - Colonne ($minVal à $maxVal)'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'Numéro entre $minVal et $maxVal (ou vide)',
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              setState(() {
                _grid[row][col] = 0;
                _syncLinesFromGrid();
              });
              Navigator.pop(ctx);
            },
            child: const Text('Vider la case',
                style: TextStyle(color: Colors.redAccent)),
          ),
          ElevatedButton(
            onPressed: () {
              final v = int.tryParse(ctrl.text.trim());
              setState(() {
                if (v == null || v <= 0) {
                  _grid[row][col] = 0;
                } else if (v >= 1 && v <= 90) {
                  final targetCol = _LotoHomePageState.columnForNumber(v);
                  _grid[row][targetCol] = v;
                }
                _syncLinesFromGrid();
              });
              Navigator.pop(ctx);
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  void _saveAndClose({required bool createAnother}) {
    final totalNums = _grid.expand((r) => r).where((v) => v > 0).length;
    if (totalNums == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez saisir ou scanner au moins un numéro.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final carton = LotoCarton(
      id: widget.existingCarton?.id ??
          DateTime.now().millisecondsSinceEpoch.toString(),
      name: _nameCtrl.text.trim().isEmpty
          ? 'Carton ${widget.defaultIndex}'
          : _nameCtrl.text.trim(),
      colorValue: _selectedColor,
      grid: _grid.map((r) => List<int>.from(r)).toList(),
    );

    widget.onSave(carton, createAnother);

    if (createAnother) {
      setState(() {
        _nameCtrl.text = 'Carton ${widget.defaultIndex + 1}';
        _grid = List.generate(3, (_) => List.filled(9, 0));
        _syncLinesFromGrid();
        _scanStatus = 'Carton enregistré ! Prêt pour le carton suivant.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Carton enregistré ! Saisissez le suivant.'),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 1),
        ),
      );
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardColor = Color(_selectedColor);

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: const Text('Créez vos cartons'),
        actions: [
          IconButton(
            tooltip: 'Vider la grille',
            icon: const Icon(Icons.delete_sweep),
            onPressed: () {
              setState(() {
                _grid = List.generate(3, (_) => List.filled(9, 0));
                _syncLinesFromGrid();
              });
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          // 1. BOUTONS APPAREIL PHOTO (RECONNAISSANCE OCR)
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1565C0),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text(
                    'Prendre en photo',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: _isScanning
                      ? null
                      : () => _scanCartonWithCamera(ImageSource.camera),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Galerie photo'),
                  onPressed: _isScanning
                      ? null
                      : () => _scanCartonWithCamera(ImageSource.gallery),
                ),
              ),
            ],
          ),

          if (_isScanning) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          if (_scanStatus.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _scanStatus,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                  color: Color(0xFF0D47A1),
                ),
              ),
            ),
          ],

          const SizedBox(height: 14),

          // 2. APERÇU INTERACTIF DU CARTON QUINE CLASSIQUE (ROUGE/BLANC)
          const Text(
            'Aperçu de votre carton Quine (touchez une case pour modifier) :',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
          ),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cardColor, width: 2),
            ),
            child: Column(
              children: List.generate(3, (r) {
                return Padding(
                  padding: EdgeInsets.only(bottom: r < 2 ? 4 : 0),
                  child: Row(
                    children: List.generate(9, (c) {
                      final val = _grid[r][c];
                      return Expanded(
                        child: GestureDetector(
                          onTap: () => _editSingleCell(r, c),
                          child: Container(
                            height: 42,
                            margin: EdgeInsets.only(right: c < 8 ? 4 : 0),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: val == 0 ? cardColor : Colors.white,
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              val == 0 ? '' : '$val',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 17,
                                color: Colors.black,
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                );
              }),
            ),
          ),

          const SizedBox(height: 12),

          // Choix de la couleur du carton
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: widget.paletteColors.map((cVal) {
              final isSelected = _selectedColor == cVal;
              return GestureDetector(
                onTap: () => setState(() => _selectedColor = cVal),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: Color(cVal),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isSelected ? Colors.black : Colors.white,
                      width: isSelected ? 3 : 1.5,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 14),

          // 3. SAISIE RAPIDE PAR LIGNE (COMME SUR VOTRE CAPTURE D'ÉCRAN)
          const Text(
            'Ou saisissez directement les 5 numéros de chaque ligne (séparés par un espace) :',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 8),
          _buildLineField('Ligne 1 (5 numéros) :', 'Ex: 3 16 35 44 60',
              _line1Ctrl, (v) => _parseLineIntoGrid(0, v)),
          const SizedBox(height: 8),
          _buildLineField('Ligne 2 (5 numéros) :', 'Ex: 8 22 56 66 88',
              _line2Ctrl, (v) => _parseLineIntoGrid(1, v)),
          const SizedBox(height: 8),
          _buildLineField('Ligne 3 (5 numéros) :', 'Ex: 29 42 54 70 87',
              _line3Ctrl, (v) => _parseLineIntoGrid(2, v)),

          const SizedBox(height: 12),

          // 4. NOM DU CARTON
          Row(
            children: [
              const Text(
                'Nom de votre carton :',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Ex: Paul / Carton 1',
                    border: OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 18),

          // 5. BOUTONS "CRÉER CARTON" & "CARTON SUIVANT"
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.black,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => _saveAndClose(createAnother: false),
                  child: const Text(
                    'Créer carton',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFD32F2F),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => _saveAndClose(createAnother: true),
                  child: const Text(
                    'Carton suivant',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLineField(
    String label,
    String hint,
    TextEditingController ctrl,
    ValueChanged<String> onChanged,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          onChanged: onChanged,
          decoration: InputDecoration(
            isDense: true,
            hintText: hint,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ],
    );
  }
}

class _DetectedNumber {
  final int value;
  final double cx;
  final double cy;
  final double height;

  _DetectedNumber({
    required this.value,
    required this.cx,
    required this.cy,
    required this.height,
  });
}
