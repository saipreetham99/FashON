import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'data/app_settings.dart';
import 'data/database.dart';
import 'data/image_store.dart';
import 'data/item_repository.dart';
import 'data/look_repository.dart';
import 'data/score_repository.dart';
import 'services/api_key_service.dart';
import 'services/backfill_service.dart';
import 'services/gemini_service.dart';
import 'services/pair_scoring_service.dart';
import 'theme/app_theme.dart';
import 'viewmodels/closet_viewmodel.dart';
import 'viewmodels/combinations_viewmodel.dart';
import 'viewmodels/looks_viewmodel.dart';
import 'viewmodels/match_viewmodel.dart';
import 'views/root_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Ink0.raised,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );

  // Resolved before the first frame for two reasons: grid tiles need
  // synchronous image paths, and the UI should never flash "no API key" at a
  // user who has one.
  final images = ImageStore();
  await images.warmUp();

  final apiKeys = ApiKeyService();
  await apiKeys.load();

  // Settings need the database, so this is also what forces the schema
  // migration to run before any screen queries a table that may not exist yet.
  final database = AppDatabase();
  final settings = AppSettings(database: database);
  await settings.load();

  runApp(
    FashonApp(
      images: images,
      apiKeys: apiKeys,
      database: database,
      settings: settings,
    ),
  );
}

class FashonApp extends StatelessWidget {
  final ImageStore images;
  final ApiKeyService apiKeys;
  final AppDatabase database;
  final AppSettings settings;

  const FashonApp({
    super.key,
    required this.images,
    required this.apiKeys,
    required this.database,
    required this.settings,
  });

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // --- Infrastructure ---
        Provider<AppDatabase>.value(value: database),
        Provider<ImageStore>.value(value: images),
        ChangeNotifierProvider<ApiKeyService>.value(value: apiKeys),
        ChangeNotifierProvider<AppSettings>.value(value: settings),

        // --- Repositories ---
        Provider<ItemRepository>(
          create: (_) => ItemRepository(database: database, images: images),
        ),
        Provider<ScoreRepository>(
          create: (_) => ScoreRepository(database: database),
        ),
        Provider<LookRepository>(
          create: (_) => LookRepository(database: database, images: images),
        ),

        // --- Services ---
        Provider<GeminiService>(
          create: (_) => GeminiService(apiKeys: apiKeys, images: images),
          dispose: (_, service) => service.dispose(),
        ),
        Provider<PairScoringService>(
          create:
              (ctx) => PairScoringService(
                gemini: ctx.read<GeminiService>(),
                scores: ctx.read<ScoreRepository>(),
              ),
        ),

        // --- View models ---
        // Closet comes first: Match and Combinations both resolve item ids
        // through it, so it is the source of truth for what exists.
        ChangeNotifierProvider<ClosetViewModel>(
          create: (ctx) => ClosetViewModel(items: ctx.read<ItemRepository>()),
        ),
        ChangeNotifierProvider<LooksViewModel>(
          create: (ctx) => LooksViewModel(looks: ctx.read<LookRepository>()),
        ),
        ChangeNotifierProvider<CombinationsViewModel>(
          create:
              (ctx) => CombinationsViewModel(
                scores: ctx.read<ScoreRepository>(),
                closet: ctx.read<ClosetViewModel>(),
              ),
        ),
        ChangeNotifierProvider<MatchViewModel>(
          create:
              (ctx) => MatchViewModel(
                closet: ctx.read<ClosetViewModel>(),
                scoring: ctx.read<PairScoringService>(),
                scores: ctx.read<ScoreRepository>(),
                looks: ctx.read<LookRepository>(),
                gemini: ctx.read<GeminiService>(),
              ),
        ),

        // Last, because it attaches itself to the closet's change hook.
        // `lazy: false` so that wiring happens at startup rather than whenever
        // some widget first reads it — otherwise adding a garment before ever
        // opening Combos would go unnoticed.
        ChangeNotifierProvider<BackfillService>(
          lazy: false,
          create: (ctx) {
            final closet = ctx.read<ClosetViewModel>();
            final backfill = BackfillService(
              scoring: ctx.read<PairScoringService>(),
              scores: ctx.read<ScoreRepository>(),
              apiKeys: apiKeys,
              settings: settings,
            );
            closet.onClosetChanged = backfill.onClosetChanged;

            // The closet starts loading in its own constructor, which runs
            // before this provider is built. If it already finished, the hook
            // missed its notification, so catch up explicitly.
            if (closet.status == ClosetStatus.ready) {
              backfill.onClosetChanged(closet.all).ignore();
            }

            return backfill;
          },
        ),
      ],
      child: MaterialApp(
        title: 'FashON',
        debugShowCheckedModeBanner: false,
        theme: buildFashonTheme(),
        home: const RootScreen(),
      ),
    );
  }
}
