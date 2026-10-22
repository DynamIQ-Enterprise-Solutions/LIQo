// Seeded random (mulberry32), so the mall is the same every time.
// A bit-exact port of the mock-up's JS `rng(seed)`: every step keeps JS's
// 32-bit integer semantics, so the same seed gives the same sequence.

int _i32(int x) => x.toSigned(32);
int _u32(int x) => x.toUnsigned(32);
int _imul(int a, int b) => (_i32(a) * _i32(b)).toSigned(32);

double Function() rng(int seed) {
  var s = seed;
  return () {
    s = _i32(s);
    s = _i32(s + 0x6D2B79F5);
    var t = _imul(s ^ (_u32(s) >> 15), 1 | s);
    t = _i32((t + _imul(t ^ (_u32(t) >> 7), 61 | t)) ^ t);
    return _u32(t ^ (_u32(t) >> 14)) / 4294967296;
  };
}
