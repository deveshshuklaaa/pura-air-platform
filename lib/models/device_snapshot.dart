class DeviceSnapshot {
  final double? co2, pm25Avg, pm10, gasIndex, humidity, temperature;
  final int? aqi, aqiTrend, forecast10, forecast30;
  final String aqiCategory;
  final int fanLevel;
  final bool mist, isTestData, loading;
  final String mode;
  final String? eventId, error;
  final DateTime? measuredAt, receivedAt, forecastAt;
  const DeviceSnapshot(
      {required this.co2,
      required this.pm25Avg,
      this.pm10,
      required this.aqi,
      required this.aqiCategory,
      required this.aqiTrend,
      required this.gasIndex,
      required this.fanLevel,
      required this.mist,
      required this.mode,
      required this.humidity,
      required this.temperature,
      this.forecast10,
      this.forecast30,
      this.forecastAt,
      this.eventId,
      this.measuredAt,
      this.receivedAt,
      this.error,
      this.loading = false,
      this.isTestData = false});

  DeviceSnapshot copyWith(
          {double? co2,
          double? pm25Avg,
          int? aqi,
          String? aqiCategory,
          int? aqiTrend,
          double? gasIndex,
          int? fanLevel,
          bool? mist,
          String? mode,
          double? humidity,
          double? temperature}) =>
      DeviceSnapshot(
          co2: co2 ?? this.co2,
          pm25Avg: pm25Avg ?? this.pm25Avg,
          pm10: pm10,
          aqi: aqi ?? this.aqi,
          aqiCategory: aqiCategory ?? this.aqiCategory,
          aqiTrend: aqiTrend ?? this.aqiTrend,
          gasIndex: gasIndex ?? this.gasIndex,
          fanLevel: fanLevel ?? this.fanLevel,
          mist: mist ?? this.mist,
          mode: mode ?? this.mode,
          humidity: humidity ?? this.humidity,
          temperature: temperature ?? this.temperature,
          forecast10: forecast10,
          forecast30: forecast30,
          forecastAt: forecastAt,
          eventId: eventId,
          measuredAt: measuredAt,
          receivedAt: receivedAt,
          error: error,
          loading: loading,
          isTestData: isTestData);
}
