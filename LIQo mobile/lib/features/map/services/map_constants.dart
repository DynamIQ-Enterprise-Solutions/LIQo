// What the map drawing and the map screen need: heights of the drawn shapes,
// the camera's limits, and the demo phone canvas the screen offsets were laid
// out on (from the demo's core/constants.dart).
import 'dart:math' as math;

const double slabH = 2.6, boxH = 3.8, wallH = 3.2, coreH = 4.6, railH = 1.2, plateT = 1.4;
const double routeZ = 0.5;
const double yaw = -12 * math.pi / 180;

const double siteZoomMax = 1.55, zoomMin = 0.85, zoomMax = 16;
const double lodPinsZoom = 3, lodNamesZoom = 6;

// The demo's phone canvas was 370 x 824 with a 40 px fake status bar.
const double mockW = 370, mockH = 824, mockStatusBar = 40;
const double mapTop = 125;

const double coneSpread = 28 * math.pi / 180, coneRadiusM = 14;

/// The other ways are drawn until the walk is this far along (metres).
const double altVisibleUntilM = 8;
