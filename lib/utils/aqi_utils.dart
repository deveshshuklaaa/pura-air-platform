import 'package:flutter/material.dart';

Color aqiColor(int aqi) {
  if (aqi <= 50) return const Color(0xFF4CFF88);
  if (aqi <= 100) return const Color(0xFFB6FF5C);
  if (aqi <= 150) return const Color(0xFFFFB74D);
  if (aqi <= 200) return const Color(0xFFFF5C5C);
  if (aqi <= 300) return const Color(0xFFB84DFF);
  return const Color(0xFF7E0023);
}

String trendLabel(int delta) {
  if (delta > 5) return 'Rising';
  if (delta < -5) return 'Improving';
  return 'Stable';
}
