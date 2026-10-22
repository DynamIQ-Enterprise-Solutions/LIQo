// Five sample posts per offline mall, from the mall, its stores and its
// management. Made up, and shown with a "Sample" label.
import '../../places/models/place_info.dart';
import '../models/sample_post.dart';

const samplePosts = <SamplePost>[
  // ----- Bayview Grand -----
  SamplePost(
    id: 'bay-1', mallId: 'bayview', author: PostAuthor.mall, authorName: 'Bayview Grand', motif: 'garden',
    title: Bilingual('Sunset by the bay', 'Paglubog ng araw sa tabi ng look'),
    body: Bilingual('Catch the sunset on the Promenade. The mall is open until 10:00 PM every night.', 'Panoorin ang paglubog ng araw sa Promenade. Bukas ang mall hanggang 10:00 PM gabi-gabi.'),
  ),
  SamplePost(
    id: 'bay-2', mallId: 'bayview', author: PostAuthor.store, authorName: 'Bayview Department Store', placeId: 'G-WDS', motif: 'fashion',
    title: Bilingual('New season styles', 'Mga bagong istilo ngayong season'),
    body: Bilingual('The new season is in. Visit us on the ground floor of the Main Mall.', 'Dumating na ang bagong season. Bisitahin kami sa ground floor ng Main Mall.'),
  ),
  SamplePost(
    id: 'bay-3', mallId: 'bayview', author: PostAuthor.management, authorName: 'Bayview Grand Management', motif: 'parking',
    title: Bilingual('North Parking repainting', 'Pagpipinta sa North Parking'),
    body: Bilingual('Level 5 of North Parking is being repainted this week. Please use South Parking.', 'Pinipinturahan ngayong linggo ang Level 5 ng North Parking. Pakigamit ang South Parking.'),
  ),
  SamplePost(
    id: 'bay-4', mallId: 'bayview', author: PostAuthor.store, authorName: 'Bayview Ice Rink', placeId: 'G-RNK', motif: 'arena',
    title: Bilingual('Public skating', 'Skating para sa lahat'),
    body: Bilingual('Skating sessions start every hour from 10:00 AM. Skates are available for hire.', 'May skating session bawat oras simula 10:00 AM. May skates na puwedeng arkilahin.'),
  ),
  SamplePost(
    id: 'bay-5', mallId: 'bayview', author: PostAuthor.store, authorName: 'Bayview Food Hall', placeId: '3-EHM', motif: 'food',
    title: Bilingual('Taste of the bay', 'Lasa ng look'),
    body: Bilingual('Try the new seafood stalls at the Food Hall on level 3.', 'Tikman ang mga bagong seafood stall sa Food Hall sa level 3.'),
  ),
  // ----- Meridian Twin Malls -----
  SamplePost(
    id: 'mer-1', mallId: 'meridian', author: PostAuthor.mall, authorName: 'Meridian Twin Malls', motif: 'other',
    title: Bilingual('Two malls, one trip', 'Dalawang mall, isang lakad'),
    body: Bilingual('Cross between Building A and Building B on the bridges on levels 2, 4 and 5.', 'Tumawid sa pagitan ng Building A at Building B sa mga tulay sa level 2, 4 at 5.'),
  ),
  SamplePost(
    id: 'mer-2', mallId: 'meridian', author: PostAuthor.store, authorName: 'FreshMart', placeId: 'G-BAN', motif: 'food',
    title: Bilingual('Fresh every morning', 'Sariwa tuwing umaga'),
    body: Bilingual('Fruit and vegetables arrive every day. Find us on the ground floor of Building B.', 'Dumarating araw-araw ang prutas at gulay. Nasa ground floor kami ng Building B.'),
  ),
  SamplePost(
    id: 'mer-3', mallId: 'meridian', author: PostAuthor.management, authorName: 'Meridian Management', motif: 'exit',
    title: Bilingual('Station link hours', 'Oras ng daan papunta sa istasyon'),
    body: Bilingual('The level 3 link to the train station is open from 6:00 AM to midnight.', 'Bukas ang daan sa level 3 papunta sa istasyon ng tren mula 6:00 AM hanggang hatinggabi.'),
  ),
  SamplePost(
    id: 'mer-4', mallId: 'meridian', author: PostAuthor.store, authorName: 'Meridian Bowling', placeId: '4-BAN', motif: 'cinema',
    title: Bilingual('Bowling nights', 'Gabi ng bowling'),
    body: Bilingual('Bring friends for league nights every Friday on level 4 of Building B.', 'Isama ang mga kaibigan sa league night tuwing Biyernes sa level 4 ng Building B.'),
  ),
  SamplePost(
    id: 'mer-5', mallId: 'meridian', author: PostAuthor.store, authorName: 'Meridian Department Store', placeId: 'G-ADS', motif: 'fashion',
    title: Bilingual('Back to school', 'Balik-eskwela'),
    body: Bilingual('Bags, shoes and uniforms for the new school year, on the ground floor of Building A.', 'Bag, sapatos at uniporme para sa bagong taon ng pasukan, nasa ground floor ng Building A.'),
  ),
  // ----- Skyline Spire -----
  SamplePost(
    id: 'spi-1', mallId: 'spire', author: PostAuthor.mall, authorName: 'Skyline Spire', motif: 'garden',
    title: Bilingual('Up to the Sky Garden', 'Akyat sa Sky Garden'),
    body: Bilingual('Take the express escalators to the rooftop garden for the best view in the city.', 'Sumakay sa express escalator papunta sa hardin sa bubong para sa pinakamagandang tanawin ng lungsod.'),
  ),
  SamplePost(
    id: 'spi-2', mallId: 'spire', author: PostAuthor.store, authorName: 'Spire Cinemas', placeId: '9-CIN', motif: 'cinema',
    title: Bilingual('Now showing', 'Palabas ngayon'),
    body: Bilingual('New films every Friday on level 9. Book at the counter or just walk in.', 'May bagong pelikula tuwing Biyernes sa level 9. Mag-book sa counter o pumasok na lang.'),
  ),
  SamplePost(
    id: 'spi-3', mallId: 'spire', author: PostAuthor.management, authorName: 'Skyline Spire Management', motif: 'lift',
    title: Bilingual('Lift servicing', 'Pag-aayos ng elevator'),
    body: Bilingual('One high-rise lift is serviced on weekday mornings. The other lifts run as usual.', 'May isang high-rise na elevator na inaayos tuwing umaga sa weekday. Tuloy ang ibang elevator.'),
  ),
  SamplePost(
    id: 'spi-4', mallId: 'spire', author: PostAuthor.store, authorName: 'Spire Food Court', placeId: '11-FC', motif: 'food',
    title: Bilingual('Lunch with a view', 'Tanghalian na may tanawin'),
    body: Bilingual('Food stalls on level 11, open until 10:00 PM.', 'Mga food stall sa level 11, bukas hanggang 10:00 PM.'),
  ),
  SamplePost(
    id: 'spi-5', mallId: 'spire', author: PostAuthor.store, authorName: 'Spire Department Store', placeId: '2-DS', motif: 'fashion',
    title: Bilingual('Home week', 'Linggo ng gamit-bahay'),
    body: Bilingual('Everything for the home this week, on our Home floor on level 3.', 'Lahat ng gamit sa bahay ngayong linggo, sa aming Home floor sa level 3.'),
  ),
];

List<SamplePost> postsFor(String mallId) => [for (final p in samplePosts) if (p.mallId == mallId) p];

SamplePost? postById(String id) => samplePosts.where((p) => p.id == id).firstOrNull;
