import 'dart:math' as math;

/// WGS-84 ⇄ GCJ-02 coordinate conversion + China-mainland detection.
///
/// All inputs/outputs are in degrees (latitude, longitude).
/// Algorithm: standard "火星坐标系" offset used by AMap / Baidu / Tencent maps
/// inside Chinese mainland borders. Outside the mainland the conversion is a
/// no-op (returns the input unchanged), matching what the official Chinese
/// map SDKs do.
class CoordTransform {
  CoordTransform._();

  // Krasovsky 1940 ellipsoid (Chinese geodetic datum reference).
  static const double _a = 6378245.0;
  static const double _ee = 0.00669342162296594323;

  /// Convert a WGS-84 coordinate to GCJ-02 (used by AMap / Tencent inside China).
  static ({double lat, double lng}) wgs84ToGcj02(double lat, double lng) {
    if (!isInChinaMainland(lat, lng)) return (lat: lat, lng: lng);
    final d = _delta(lat, lng);
    return (lat: lat + d.dLat, lng: lng + d.dLng);
  }

  /// Convert GCJ-02 back to WGS-84 (iterative; <1m residual).
  static ({double lat, double lng}) gcj02ToWgs84(double lat, double lng) {
    if (!isInChinaMainland(lat, lng)) return (lat: lat, lng: lng);
    var wgsLat = lat;
    var wgsLng = lng;
    for (var i = 0; i < 3; i++) {
      final d = _delta(wgsLat, wgsLng);
      wgsLat = lat - d.dLat;
      wgsLng = lng - d.dLng;
    }
    return (lat: wgsLat, lng: wgsLng);
  }

  /// Rough bounding-box check for Chinese mainland, EXCLUDING Hong Kong,
  /// Macao and Taiwan (those regions use WGS-84 in commercial map services).
  static bool isInChinaMainland(double lat, double lng) {
    // Outer mainland bbox
    if (lat < 17.755 || lat > 53.56) return false;
    if (lng < 73.5 || lng > 134.77) return false;
    // Exclude Taiwan island (approx)
    if (lat >= 21.8 && lat <= 25.3 && lng >= 119.2 && lng <= 122.05) {
      return false;
    }
    // Exclude Hong Kong + Macao (approx)
    if (lat >= 22.1 && lat <= 22.6 && lng >= 113.5 && lng <= 114.5) {
      return false;
    }
    return true;
  }

  static ({double dLat, double dLng}) _delta(double lat, double lng) {
    final dLat0 = _transformLat(lng - 105.0, lat - 35.0);
    final dLng0 = _transformLng(lng - 105.0, lat - 35.0);
    final radLat = lat / 180.0 * math.pi;
    var magic = math.sin(radLat);
    magic = 1 - _ee * magic * magic;
    final sqrtMagic = math.sqrt(magic);
    final dLat = (dLat0 * 180.0) / ((_a * (1 - _ee)) / (magic * sqrtMagic) * math.pi);
    final dLng = (dLng0 * 180.0) / (_a / sqrtMagic * math.cos(radLat) * math.pi);
    return (dLat: dLat, dLng: dLng);
  }

  static double _transformLat(double x, double y) {
    var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y +
        0.2 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * math.pi) +
            20.0 * math.sin(2.0 * x * math.pi)) *
        2.0 /
        3.0;
    ret += (20.0 * math.sin(y * math.pi) +
            40.0 * math.sin(y / 3.0 * math.pi)) *
        2.0 /
        3.0;
    ret += (160.0 * math.sin(y / 12.0 * math.pi) +
            320.0 * math.sin(y * math.pi / 30.0)) *
        2.0 /
        3.0;
    return ret;
  }

  static double _transformLng(double x, double y) {
    var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y +
        0.1 * math.sqrt(x.abs());
    ret += (20.0 * math.sin(6.0 * x * math.pi) +
            20.0 * math.sin(2.0 * x * math.pi)) *
        2.0 /
        3.0;
    ret += (20.0 * math.sin(x * math.pi) +
            40.0 * math.sin(x / 3.0 * math.pi)) *
        2.0 /
        3.0;
    ret += (150.0 * math.sin(x / 12.0 * math.pi) +
            300.0 * math.sin(x / 30.0 * math.pi)) *
        2.0 /
        3.0;
    return ret;
  }
}
