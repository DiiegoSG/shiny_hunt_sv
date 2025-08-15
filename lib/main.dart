import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ShinyHuntApp());
}

class ShinyHuntApp extends StatelessWidget {
  const ShinyHuntApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Shiny Hunt Companion (SV)',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF7C4DFF)),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}

enum HuntMethod { wild, outbreak, masuda }

extension HuntMethodX on HuntMethod {
  String get label => switch (this) {
        HuntMethod.wild => 'Encuentros salvajes',
        HuntMethod.outbreak => 'Brotes masivos',
        HuntMethod.masuda => 'Huevos (Método Masuda)'
      };

  String get key => toString().split('.').last;

  static HuntMethod fromKey(String key) => HuntMethod.values.firstWhere(
        (e) => e.key == key,
        orElse: () => HuntMethod.wild,
      );
}

class HuntSettings {
  HuntMethod method;
  bool shinyCharm; // Afecta a todos los métodos
  bool sparklingPower; // Sólo útil para salvajes y brotes
  int outbreakKOs; // 0, 30, 60

  HuntSettings({
    this.method = HuntMethod.wild,
    this.shinyCharm = false,
    this.sparklingPower = false,
    this.outbreakKOs = 0,
  });

  Map<String, dynamic> toJson() => {
        'method': method.key,
        'shinyCharm': shinyCharm,
        'sparklingPower': sparklingPower,
        'outbreakKOs': outbreakKOs,
      };

  factory HuntSettings.fromJson(Map<String, dynamic> json) {
    return HuntSettings(
      method: HuntMethodX.fromKey(json['method'] ?? 'wild'),
      shinyCharm: json['shinyCharm'] ?? false,
      sparklingPower: json['sparklingPower'] ?? false,
      outbreakKOs: (json['outbreakKOs'] ?? 0) as int,
    );
  }
}

class HuntSession {
  String id; // simple unique id
  String title; // nombre opcional del objetivo
  int counter; // encuentros / huevos
  DateTime createdAt;
  HuntSettings settings;
  bool completed;

  HuntSession({
    required this.id,
    required this.title,
    required this.counter,
    required this.createdAt,
    required this.settings,
    this.completed = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'counter': counter,
        'createdAt': createdAt.toIso8601String(),
        'completed': completed,
        'settings': settings.toJson(),
      };

  factory HuntSession.fromJson(Map<String, dynamic> json) {
    return HuntSession(
      id: json['id'],
      title: json['title'] ?? 'Sin título',
      counter: (json['counter'] ?? 0) as int,
      createdAt: DateTime.tryParse(json['createdAt'] ?? '') ?? DateTime.now(),
      completed: json['completed'] ?? false,
      settings: HuntSettings.fromJson(json['settings'] ?? {}),
    );
  }
}

class AppState extends ChangeNotifier {
  static const String sessionsKey = 'sv_shiny_sessions_v1';
  static const String currentKey = 'sv_shiny_current_v1';

  final List<HuntSession> _sessions = [];
  HuntSession? _current;

  List<HuntSession> get sessions => List.unmodifiable(_sessions);
  HuntSession? get current => _current;

  AppState() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getString(sessionsKey);
    if (list != null) {
      final decoded = (jsonDecode(list) as List)
          .map((e) => HuntSession.fromJson(e))
          .toList();
      _sessions.clear();
      _sessions.addAll(decoded);
    }
    final cur = prefs.getString(currentKey);
    if (cur != null) {
      _current = HuntSession.fromJson(jsonDecode(cur));
    } else {
      _current = HuntSession(
        id: _genId(),
        title: 'Nuevo objetivo',
        counter: 0,
        createdAt: DateTime.now(),
        settings: HuntSettings(),
      );
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      sessionsKey,
      jsonEncode(_sessions.map((e) => e.toJson()).toList()),
    );
    if (_current != null) {
      await prefs.setString(currentKey, jsonEncode(_current!.toJson()));
    }
  }

  void updateCurrent(void Function(HuntSession) updater) {
    if (_current == null) return;
    updater(_current!);
    notifyListeners();
    _persist();
  }

  void resetCounter() {
    if (_current == null) return;
    _current!.counter = 0;
    notifyListeners();
    _persist();
  }

  void increment([int by = 1]) {
    if (_current == null) return;
    _current!.counter = math.max(0, _current!.counter + by);
    notifyListeners();
    _persist();
  }

  void decrement([int by = 1]) => increment(-by);

  void completeCurrent() {
    if (_current == null) return;
    _current!.completed = true;
    _sessions.insert(0, _current!);
    _current = HuntSession(
      id: _genId(),
      title: 'Nuevo objetivo',
      counter: 0,
      createdAt: DateTime.now(),
      settings: HuntSettings(),
    );
    notifyListeners();
    _persist();
  }

  void deleteSession(String id) {
    _sessions.removeWhere((e) => e.id == id);
    notifyListeners();
    _persist();
  }

  static String _genId() =>
      DateTime.now().millisecondsSinceEpoch.toString() +
      '-' +
      math.Random().nextInt(1 << 32).toString();
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 3, vsync: this);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AppState(),
      child: Builder(builder: (context) {
        final cs = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Shiny Hunt Companion (SV)'),
            bottom: TabBar(
              controller: _tabs,
              tabs: const [
                Tab(text: 'Cazar'),
                Tab(text: 'Sesiones'),
                Tab(text: 'Ayuda'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabs,
            children: const [
              HuntTab(),
              SessionsTab(),
              HelpTab(),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {
              final app = context.read<AppState>();
              app.completeCurrent();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('¡Sesión guardada como completada!')),
              );
            },
            label: const Text('¡Shiny! Guardar'),
            icon: const Icon(Icons.star),
          ),
        );
      }),
    );
  }
}

class HuntTab extends StatelessWidget {
  const HuntTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final cur = app.current!;
    final cs = Theme.of(context).colorScheme;

    final odds = _computeOdds(cur.settings);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: TextEditingController(text: cur.title)
              ..selection = TextSelection.fromPosition(
                TextPosition(offset: cur.title.length),
              ),
            decoration: const InputDecoration(
              labelText: 'Objetivo (opcional) — p.ej., "Fuéton", "Eevee"',
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => app.updateCurrent((s) => s.title = v),
          ),
          const SizedBox(height: 12),
          _MethodPicker(settings: cur.settings),
          const SizedBox(height: 12),
          _SettingsSection(settings: cur.settings),
          const SizedBox(height: 8),
          _OddsCard(odds: odds),
          const SizedBox(height: 16),
          _CounterCard(
            count: cur.counter,
            onInc: () => app.increment(1),
            onDec: () => app.decrement(1),
            onReset: app.resetCounter,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => app.completeCurrent(),
            icon: const Icon(Icons.star),
            label: const Text('Marcar como conseguido y guardar sesión'),
          ),
        ],
      ),
    );
  }
}

class _MethodPicker extends StatelessWidget {
  final HuntSettings settings;
  const _MethodPicker({required this.settings});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    return Row(
      children: [
        const Text('Método:'),
        const SizedBox(width: 12),
        DropdownButton<HuntMethod>(
          value: settings.method,
          items: HuntMethod.values
              .map((m) => DropdownMenuItem(
                    value: m,
                    child: Text(m.label),
                  ))
              .toList(),
          onChanged: (m) {
            if (m == null) return;
            app.updateCurrent((s) => s.settings.method = m);
          },
        ),
      ],
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final HuntSettings settings;
  const _SettingsSection({required this.settings});

  @override
  Widget build(BuildContext context) {
    final app = context.read<AppState>();
    final isMasuda = settings.method == HuntMethod.masuda;
    final isOutbreak = settings.method == HuntMethod.outbreak;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: const Text('Amuleto Iris (Shiny Charm)'),
          value: settings.shinyCharm,
          onChanged: (v) => app.updateCurrent((s) => s.settings.shinyCharm = v),
        ),
        if (!isMasuda)
          SwitchListTile(
            title: const Text('Bocadillo Brillante L3 (Sparkling Power)'),
            subtitle: const Text('Afecta a encuentros salvajes/brotes'),
            value: settings.sparklingPower,
            onChanged: (v) => app.updateCurrent((s) => s.settings.sparklingPower = v),
          ),
        if (isOutbreak)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              const Text('KOs en el brote'),
              const SizedBox(height: 6),
              SegmentedButton<int>(
                segments: const [
                  ButtonSegment(value: 0, label: Text('0+')),
                  ButtonSegment(value: 30, label: Text('30+')),
                  ButtonSegment(value: 60, label: Text('60+')),
                ],
                selected: {settings.outbreakKOs},
                onSelectionChanged: (sel) => app.updateCurrent(
                    (s) => s.settings.outbreakKOs = sel.first),
              ),
            ],
          ),
      ],
    );
  }
}

class _OddsCard extends StatelessWidget {
  final OddsResult odds; 
  const _OddsCard({required this.odds});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Probabilidades estimadas',
                style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                _Kpi(
                  label: '1 en',
                  value: odds.oneIn.toStringAsFixed(0),
                ),
                _Kpi(
                  label: 'Porcentaje',
                  value: '${(odds.percentage * 100).toStringAsFixed(3)}%',
                ),
                _Kpi(
                  label: 'Encuentros esperados',
                  value: odds.expectedEncounters.toStringAsFixed(0),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              odds.notes,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            )
          ],
        ),
      ),
    );
  }
}

class _Kpi extends StatelessWidget {
  final String label;
  final String value;
  const _Kpi({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 2),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge,
          ),
        ],
      ),
    );
  }
}

class _CounterCard extends StatelessWidget {
  final int count;
  final VoidCallback onInc;
  final VoidCallback onDec;
  final VoidCallback onReset;
  const _CounterCard({
    required this.count,
    required this.onInc,
    required this.onDec,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Text(
                '$count',
                style: Theme.of(context)
                    .textTheme
                    .displayLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDec,
                    icon: const Icon(Icons.remove),
                    label: const Text('Restar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onInc,
                    icon: const Icon(Icons.add),
                    label: const Text('Sumar'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reiniciar contador'),
            ),
          ],
        ),
      ),
    );
  }
}

class SessionsTab extends StatelessWidget {
  const SessionsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final sessions = app.sessions;

    if (sessions.isEmpty) {
      return const Center(
        child: Text('Aún no hay sesiones guardadas.'),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: sessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final s = sessions[i];
        return Dismissible(
          key: ValueKey(s.id),
          background: Container(
            color: Colors.red,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: const Icon(Icons.delete, color: Colors.white),
          ),
          direction: DismissDirection.startToEnd,
          onDismissed: (_) => app.deleteSession(s.id),
          child: ListTile(
            leading: Icon(
              s.settings.method == HuntMethod.masuda
                  ? Icons.egg
                  : s.settings.method == HuntMethod.outbreak
                      ? Icons.group
                      : Icons.nature_people,
            ),
            title: Text(s.title.isEmpty ? 'Objetivo sin nombre' : s.title),
            subtitle: Text(
                '${s.settings.method.label} · ${s.counter} ${(s.settings.method == HuntMethod.masuda) ? 'huevos' : 'encuentros'} · ${_dateFmt(s.createdAt)}'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final replace = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Cargar sesión'),
                  content: const Text(
                      '¿Cargar esta sesión como actual? Se sobreescribirá la sesión actual no guardada.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancelar')),
                    FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Cargar')),
                  ],
                ),
              );
              if (replace == true) {
                context.read<AppState>().updateCurrent((cur) {
                  cur.title = s.title;
                  cur.counter = s.counter;
                  cur.settings = HuntSettings(
                    method: s.settings.method,
                    shinyCharm: s.settings.shinyCharm,
                    sparklingPower: s.settings.sparklingPower,
                    outbreakKOs: s.settings.outbreakKOs,
                  );
                });
              }
            },
          ),
        );
      },
    );
  }
}

class HelpTab extends StatelessWidget {
  const HelpTab({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Consejos rápidos', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        _HelpItem(
          title: 'Encuentros salvajes',
          body:
              'Activa Sparkling Power L3 del tipo objetivo y usa filtros de aparición. Este contador te ayuda a llevar registro manual por cada aparición comprobada.',
        ),
        _HelpItem(
          title: 'Brotes masivos',
          body:
              'Derrota 30 y luego 60 para aumentar tus probabilidades. Ajusta el selector de KOs para ver el efecto estimado en el cálculo.',
        ),
        _HelpItem(
          title: 'Método Masuda (huevos)',
          body:
              'Cruza dos Pokémon de idiomas diferentes. Con Amuleto Iris las probabilidades mejoran aún más. Usa el contador por cada huevo abierto.',
        ),
        const SizedBox(height: 16),
        Text('Notas de probabilidad', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'En general, el juego usa "tiradas" adicionales para mejorar la probabilidad de 1/4096 por aparición. Aquí mostramos una estimación práctica: para salvajes/brotes aplicamos tiradas por Amuleto (+2), Bocadillo Brillante L3 (+3) y brote (30+ = +1, 60+ = +2). Para huevos, usamos atajos comunes: Masuda ≈ 1/683; Masuda + Amuleto ≈ 1/512; solo Amuleto ≈ 1/1365; sin bonus 1/4096.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _HelpItem extends StatelessWidget {
  final String title;
  final String body;
  const _HelpItem({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(body),
          ],
        ),
      ),
    );
  }
}

// ---- Odds logic ----
class OddsResult {
  final double oneIn; // e.g., 512.0
  final double percentage; // e.g., 0.195% => 0.00195
  final double expectedEncounters; // 1 / percentage
  final String notes;
  OddsResult(
      {required this.oneIn,
      required this.percentage,
      required this.expectedEncounters,
      required this.notes});
}

OddsResult _computeOdds(HuntSettings s) {
  if (s.method == HuntMethod.masuda) {
    // Valores prácticos y ampliamente usados para huevos
    late int denom;
    String notes;
    if (s.shinyCharm) {
      denom = 512; // Masuda + Charm
      notes = 'Masuda + Amuleto Iris ≈ 1/512.';
    } else {
      denom = 683; // Masuda sin Charm
      notes = 'Masuda sin Amuleto Iris ≈ 1/683.';
    }
    final p = 1.0 / denom;
    return OddsResult(
      oneIn: denom.toDouble(),
      percentage: p,
      expectedEncounters: 1.0 / p,
      notes: notes,
    );
  } else {
    // Salvajes y brotes con "rolls" adicionales sobre 1/4096
    int rolls = 1;
    if (s.shinyCharm) rolls += 2;
    if (! (s.method == HuntMethod.masuda) && s.sparklingPower) rolls += 3;
    if (s.method == HuntMethod.outbreak) {
      if (s.outbreakKOs >= 60) {
        rolls += 2;
      } else if (s.outbreakKOs >= 30) {
        rolls += 1;
      }
    }
    final base = 4096.0;
    final miss = (base - 1.0) / base; // 4095/4096
    final p = 1.0 - math.pow(miss, rolls).toDouble();
    final oneIn = 1.0 / p;
    return OddsResult(
      oneIn: oneIn,
      percentage: p,
      expectedEncounters: oneIn,
      notes:
          'Tiradas: $rolls sobre 1/4096. Estimación: 1 - (4095/4096)^$rolls.',
    );
  }
}

// ---- Minimal ChangeNotifierProvider (no 3rd-party state mgmt) ----
// Lightweight provider pattern to avoid extra dependencies beyond shared_preferences.

typedef Create<T> = T Function(BuildContext);

typedef ReadContext = BuildContext; // semantic alias

class ChangeNotifierProvider<T extends ChangeNotifier> extends StatefulWidget {
  final Create<T> create;
  final Widget child;
  const ChangeNotifierProvider({super.key, required this.create, required this.child});

  @override
  State<ChangeNotifierProvider<T>> createState() => _ChangeNotifierProviderState<T>();

  static T of<T extends ChangeNotifier>(BuildContext context) {
    final _InheritedProvider<T>? provider =
        context.dependOnInheritedWidgetOfExactType<_InheritedProvider<T>>();
    assert(provider != null, 'No ChangeNotifierProvider<$T> found in context');
    return provider!.notifier;
  }
}

class _ChangeNotifierProviderState<T extends ChangeNotifier>
    extends State<ChangeNotifierProvider<T>> {
  late T notifier;

  @override
  void initState() {
    super.initState();
    notifier = widget.create(context);
    notifier.addListener(_onChange);
  }

  void _onChange() => setState(() {});

  @override
  void dispose() {
    notifier.removeListener(_onChange);
    notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _InheritedProvider<T>(
      notifier: notifier,
      child: widget.child,
    );
  }
}

class _InheritedProvider<T extends ChangeNotifier> extends InheritedWidget {
  final T notifier;
  const _InheritedProvider({required this.notifier, required super.child});

  @override
  bool updateShouldNotify(covariant _InheritedProvider<T> oldWidget) =>
      notifier != oldWidget.notifier;
}

extension ProviderX on BuildContext {
  T watch<T extends ChangeNotifier>() => ChangeNotifierProvider.of<T>(this);
  T read<T extends ChangeNotifier>() => ChangeNotifierProvider.of<T>(this);
}

String _dateFmt(DateTime d) {
  final months = [
    'ene', 'feb', 'mar', 'abr', 'may', 'jun',
    'jul', 'ago', 'sep', 'oct', 'nov', 'dic'
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}
