// The keys things are saved under (see store.dart).
abstract final class Keys {
  static const settings = 'settings';
  static const routeOptions = 'routeOptions';
  static const onboardingSeen = 'onboardingSeen';
  static const mall = 'mall';
  static const favourites = 'favourites';
  static const savedRoutes = 'savedRoutes';
  static const history = 'history';

  /// Places picked from search, per mall.
  static String recent(String mallId) => 'recent:$mallId';

  /// How often each place was opened or navigated to on this phone, per mall.
  static String visits(String mallId) => 'visits:$mallId';
}
