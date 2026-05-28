import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PersonaProfile {
  const PersonaProfile({
    required this.terminologyMap,
    required this.enabledModules,
  });

  final Map<String, String> terminologyMap;
  final List<String> enabledModules;

  factory PersonaProfile.fromJson(Map<String, dynamic> json) {
    return PersonaProfile(
      terminologyMap: Map<String, String>.from(
        (json['terminology_map'] as Map?)?.cast<String, String>() ?? const {},
      ),
      enabledModules: List<String>.from(json['enabled_modules'] ?? const []),
    );
  }

  static PersonaProfile get defaults => const PersonaProfile(
        terminologyMap: {
          'sub_label': 'Pet',
          'domme_label': 'Mistress',
          'task_label': 'Chore',
          'currency_label': 'Credits',
        },
        enabledModules: ['ledger', 'knot', 'proof_upload', 'sensory'],
      );
}

class PersonaLabels {
  const PersonaLabels(this._map);

  final Map<String, String> _map;

  String get subLabel => _map['sub_label'] ?? 'Sub';
  String get dommeLabel => _map['domme_label'] ?? 'Domme';
  String get taskLabel => _map['task_label'] ?? 'Task';
  String get currencyLabel => _map['currency_label'] ?? 'Credits';
  String get confessionalTitle => _map['confessional_title'] ?? 'Confessional';
}

final _dioForPersonaProvider = Provider<Dio>((ref) {
  return Dio(BaseOptions(baseUrl: 'http://<backend-url>'));
});

class PersonaNotifier extends AsyncNotifier<PersonaProfile> {
  @override
  Future<PersonaProfile> build() async {
    final dio = ref.read(_dioForPersonaProvider);
    try {
      final res = await dio.get<Map<String, dynamic>>('/api/persona/me');
      return PersonaProfile.fromJson(res.data ?? const {});
    } catch (_) {
      return PersonaProfile.defaults;
    }
  }
}

final personaProvider =
    AsyncNotifierProvider<PersonaNotifier, PersonaProfile>(PersonaNotifier.new);

final personaLabelsProvider = Provider<PersonaLabels>((ref) {
  final map = ref.watch(personaProvider).maybeWhen(
        data: (p) => p.terminologyMap,
        orElse: () => const <String, String>{},
      );
  return PersonaLabels(map);
});

final featureGateProvider = Provider<FeatureGate>((ref) {
  final modules = ref.watch(personaProvider).maybeWhen(
        data: (p) => p.enabledModules,
        orElse: () => const <String>[],
      );
  return FeatureGate(modules.toSet());
});

class FeatureGate {
  const FeatureGate(this._enabled);
  final Set<String> _enabled;

  bool isEnabled(String module) => _enabled.contains(module);
}

extension PersonaLabelsContextX on BuildContext {
  PersonaLabels get labels =>
      ProviderScope.containerOf(this, listen: true).read(personaLabelsProvider);

  bool moduleEnabled(String module) =>
      ProviderScope.containerOf(this, listen: true).read(featureGateProvider).isEnabled(module);
}
