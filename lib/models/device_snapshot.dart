class DeviceSnapshot {
  final int co2;
  final int pm25Avg;
  final int aqi;
  final String aqiCategory;
  final int aqiTrend;
  final double gasIndex;
  final int fanLevel;
  final bool mist;
  final String mode;
  final double humidity;
  final double temperature;

  const DeviceSnapshot({
    required this.co2,
    required this.pm25Avg,
    required this.aqi,
    required this.aqiCategory,
    required this.aqiTrend,
    required this.gasIndex,
    required this.fanLevel,
    required this.mist,
    required this.mode,
    required this.humidity,
    required this.temperature,
  });

  DeviceSnapshot copyWith({
    int? co2,
    int? pm25Avg,
    int? aqi,
    String? aqiCategory,
    int? aqiTrend,
    double? gasIndex,
    int? fanLevel,
    bool? mist,
    String? mode,
    double? humidity,
    double? temperature,
  }) {
    return DeviceSnapshot(
      co2: co2 ?? this.co2,
      pm25Avg: pm25Avg ?? this.pm25Avg,
      aqi: aqi ?? this.aqi,
      aqiCategory: aqiCategory ?? this.aqiCategory,
      aqiTrend: aqiTrend ?? this.aqiTrend,
      gasIndex: gasIndex ?? this.gasIndex,
      fanLevel: fanLevel ?? this.fanLevel,
      mist: mist ?? this.mist,
      mode: mode ?? this.mode,
      humidity: humidity ?? this.humidity,
      temperature: temperature ?? this.temperature,
    );
  }
}
