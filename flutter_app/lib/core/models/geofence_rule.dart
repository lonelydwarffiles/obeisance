class GeofenceRule {
  const GeofenceRule({
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.restrictedPackages,
    this.identifier = 'primary_tether',
  });

  final String identifier;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final List<String> restrictedPackages;

  Map<String, dynamic> toMap() {
    return {
      'identifier': identifier,
      'latitude': latitude,
      'longitude': longitude,
      'radius_meters': radiusMeters,
      'restricted_packages': restrictedPackages,
    };
  }
}
