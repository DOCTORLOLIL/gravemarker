import 'dart:math' as math;
import 'package:latlong2/latlong.dart';

const _dist = Distance();

double meters(LatLng a, LatLng b) => _dist.as(LengthUnit.Meter, a, b);

double bearing(LatLng a, LatLng b) {
  final r = math.pi / 180;
  final y = math.sin((b.longitude - a.longitude) * r) * math.cos(b.latitude * r);
  final x = math.cos(a.latitude * r) * math.sin(b.latitude * r) -
      math.sin(a.latitude * r) * math.cos(b.latitude * r) * math.cos((b.longitude - a.longitude) * r);
  return (math.atan2(y, x) / r + 360) % 360;
}

bool inPolygon(LatLng p, List<LatLng> ring) {
  var c = false;
  for (var i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    final a = ring[i], b = ring[j];
    if ((a.latitude > p.latitude) != (b.latitude > p.latitude) &&
        p.longitude <
            (b.longitude - a.longitude) * (p.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude) {
      c = !c;
    }
  }
  return c;
}

LatLng centroid(List<LatLng> ring) {
  double la = 0, lo = 0;
  final pts = ring.length > 1 && ring.first == ring.last ? ring.sublist(0, ring.length - 1) : ring;
  for (final p in pts) {
    la += p.latitude;
    lo += p.longitude;
  }
  return LatLng(la / pts.length, lo / pts.length);
}

/// מיקום משוער של קבר: שורות מימין לשמאל (מזרח→מערב), קברים בשורה מלמעלה למטה (צפון→דרום),
/// לפי הכיוון של החלקה עצמה (מלבן חוסם מינימלי).
LatLng? estimateGrave(List<LatLng> ring, int row, int grave, int nRows, int nGraves) {
  if (ring.length < 3 || row < 1 || grave < 1) return null;
  final o = ring.first;
  final kx = 111320 * math.cos(o.latitude * math.pi / 180), ky = 111320.0;
  final p = ring.map((q) => [(q.longitude - o.longitude) * kx, (q.latitude - o.latitude) * ky]).toList();
  List<double>? bu, bv;
  double? bestArea;
  for (var i = 0; i < p.length; i++) {
    final a = p[i], b = p[(i + 1) % p.length];
    final th = math.atan2(b[1] - a[1], b[0] - a[0]);
    final u = [math.cos(th), math.sin(th)], v = [-math.sin(th), math.cos(th)];
    final pu = p.map((x) => x[0] * u[0] + x[1] * u[1]), pv = p.map((x) => x[0] * v[0] + x[1] * v[1]);
    final area = (pu.reduce(math.max) - pu.reduce(math.min)) * (pv.reduce(math.max) - pv.reduce(math.min));
    if (bestArea == null || area < bestArea) {
      bestArea = area;
      bu = u;
      bv = v;
    }
  }
  var e = bu![0].abs() >= bv![0].abs() ? bu : bv;
  var n = identical(e, bu) ? bv : bu;
  if (e[0] < 0) e = [-e[0], -e[1]];
  if (n[1] < 0) n = [-n[0], -n[1]];
  final pe = p.map((x) => x[0] * e[0] + x[1] * e[1]), pn = p.map((x) => x[0] * n[0] + x[1] * n[1]);
  final maxE = pe.reduce(math.max), minE = pe.reduce(math.min), maxN = pn.reduce(math.max), minN = pn.reduce(math.min);
  final eV = maxE - (math.min(row, nRows) - 0.5) / nRows * (maxE - minE);
  final nV = maxN - (math.min(grave, nGraves) - 0.5) / nGraves * (maxN - minN);
  final x = eV * e[0] + nV * n[0], y = eV * e[1] + nV * n[1];
  return LatLng(o.latitude + y / ky, o.longitude + x / kx);
}
