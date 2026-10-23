// Everyday Tagalog for the app's wording (from the demo; LIQo mobile's own text added). The app composes its
// English sentence first; `tagalog()` turns it into Tagalog with an exact
// dictionary and, for sentences with names and numbers in them, templates.
// Anything unknown stays English, so nothing is ever blank. Shop names, level
// names and level names are left as they are.

/// Exact phrases.
const Map<String, String> _exact = {
  // the map and its controls
  // downloading malls (owner decisions 2026-10-23)
  'Connect once to download your mall': 'Kumonekta nang isang beses para ma-download ang mall mo',
  'LIQo needs the internet once to download a mall\'s map. After that, directions work without signal.':
      'Kailangan ng LIQo ng internet nang isang beses para ma-download ang mapa ng mall. Pagkatapos, gumagana ang direksyon kahit walang signal.',
  'It also tries again by itself.': 'Kusa rin itong susubok ulit.', 'Try again': 'Subukan ulit', 'Trying…': 'Sinusubukan…',
  'Pick your mall. It downloads once, then works without signal.': 'Piliin ang mall mo. Isang beses itong ida-download, saka gagana kahit walang signal.',
  'Offline: showing the malls from your last connection.': 'Offline: ipinapakita ang mga mall mula sa huling koneksyon mo.',
  'Search malls by name or place': 'Maghanap ng mall ayon sa pangalan o lugar', 'No malls are on LIQo yet.': 'Wala pang mall sa LIQo.',
  'Download': 'I-download', 'Downloading…': 'Dina-download…', 'On this phone': 'Nasa phone na ito', 'No longer updated by LIQo': 'Hindi na ina-update ng LIQo',
  'Download on mobile data?': 'I-download gamit ang mobile data?', 'Not now': 'Hindi muna', 'More malls': 'Iba pang mall', 'Map updated': 'Na-update ang mapa',
  'Download this mall': 'I-download ang mall na ito', 'Download this mall to use it': 'I-download ang mall para magamit ito',
  'This mall is not on your phone any more.': 'Wala na sa phone mo ang mall na ito.', 'No longer on the map': 'Wala na sa mapa',
  'No connection. Try again when you\'re online.': 'Walang koneksyon. Subukan ulit kapag online ka na.', 'Not downloaded.': 'Hindi na-download.',
  'The download didn\'t work. Please try again.': 'Hindi gumana ang pag-download. Pakisubukan ulit.',
  'Update LIQo to get this mall\'s map.': 'I-update ang LIQo para makuha ang mapa ng mall na ito.',
  'Not enough space on your phone for this map.': 'Kulang ang espasyo sa phone mo para sa mapang ito.',
  // posts (owner decisions 2026-10-23)
  'Heart': 'Puso', 'Comment': 'Komento', 'More posts': 'Iba pang post', 'No posts right now.': 'Walang post sa ngayon.',
  'Sign in to react and comment · Accounts are coming soon': 'Mag-sign in para mag-react at mag-komento · Paparating na ang mga account',
  // live store info (owner decisions 2026-10-23)
  'Temporarily closed': 'Pansamantalang sarado', 'Closed today': 'Sarado ngayong araw', 'Closed now': 'Sarado ngayon',
  'Not on the map yet': 'Wala pa sa mapa', 'Directions come with the next map update': 'Darating ang direksyon sa susunod na update ng mapa',
  'Update now': 'I-update ngayon',
  'Saved malls': 'Mga naka-save na mall', 'Malls on this phone, updates, storage': 'Mga mall sa phone na ito, update, espasyo',
  'These malls work without signal. Maps update by themselves on Wi-Fi.': 'Gumagana ang mga mall na ito kahit walang signal. Kusang nag-a-update ang mapa kapag naka-Wi-Fi.',
  'No malls on this phone yet.': 'Wala pang mall sa phone na ito.', 'Add a mall': 'Magdagdag ng mall', 'Delete': 'Burahin', 'Update': 'I-update',
  'Its map leaves this phone. Your saved places there stay, greyed, and work again when you download it.':
      'Mabubura ang mapa nito sa phone na ito. Mananatili ang mga naka-save mong lugar doon, naka-abo, at gagana ulit kapag na-download mo ito.',
  'Map update ready: it switches in after your trip.': 'Handa na ang update ng mapa: papalitan ito pagkatapos ng biyahe mo.',
  'Update LIQo to get this mall\'s new map.': 'I-update ang LIQo para makuha ang bagong mapa ng mall na ito.', 'Hide for today': 'Itago muna ngayong araw',
  'Please update LIQo': 'Pakiupdate ang LIQo',
  'This version of LIQo can no longer be used. Get the latest version from your app store.': 'Hindi na magagamit ang bersyong ito ng LIQo. Kunin ang pinakabagong bersyon sa app store mo.',
  'Map': 'Mapa', 'Whole site': 'Buong lugar', 'All levels': 'Lahat ng palapag', 'Level': 'Palapag',
  'Layers': 'Mga layer', 'Map view': 'Itsura ng mapa', 'All floors': 'Lahat ng palapag', 'Go to': 'Pumunta sa',
  'Change my location': 'Palitan ang lokasyon ko', 'My location': 'Lokasyon ko', 'The map faces the way I walk': 'Nakaharap ang mapa sa dinadaanan ko',
  'End': 'Tapusin', 'End the route': 'Tapusin ang ruta', 'Show the details': 'Ipakita ang detalye', 'Hide the details': 'Itago ang detalye',
  'you are here': 'nandito ka', 'on your route': 'nasa ruta mo', 'Show': 'Ipakita', 'Cancel': 'Kanselahin', 'Close': 'Isara', 'Done': 'Tapos', 'Stop': 'Itigil',
  'Show more': 'Ipakita pa', 'Show less': 'Bawasan', '3D view': '3D view',
  'Back': 'Bumalik',
  
  'Favourite': 'Paborito', 'Go this way': 'Dito dumaan',
  'All levels · tap one to open it': 'Lahat ng palapag · i-tap ang isa para buksan',
  'Whole site · tap the mall to go in': 'Buong lugar · i-tap ang mall para pumasok',
  'Approximate · tap the map where you are': 'Tantiya lang · i-tap sa mapa kung nasaan ka',
  'Use the stairs, not the lifts': 'Gamitin ang hagdan, hindi ang elevator',
  'Clear the search': 'Burahin ang hinahanap',
  'Nothing found': 'Walang nahanap', 'None found': 'Walang nahanap',
  // nearby chips and categories
  'Restroom': 'CR', 'ATM': 'ATM', 'Food': 'Pagkain', 'Lift': 'Elevator', 'Exit': 'Labasan', 'EV charging': 'EV charging', 'Parking': 'Parking',
  'restroom': 'CR', 'atm': 'ATM', 'food': 'pagkain', 'lift': 'elevator', 'exit': 'labasan', 'ev charging': 'EV charging', 'parking': 'parking',
  'Food and drink': 'Pagkain at inumin', 'Fashion': 'Fashion', 'Gadgets and tech': 'Gadgets at tech', 'Books and gifts': 'Libro at regalo', 'Services': 'Serbisyo',
  'Other shops': 'Iba pang tindahan', 'Cinema': 'Sinehan', 'Arena': 'Arena', 'Garden': 'Hardin', 'Restrooms': 'Mga CR', 'ATMs': 'Mga ATM',
  'Information desks': 'Information desk', 'Entrances and exits': 'Mga pasukan at labasan', 'Other places': 'Iba pang lugar', 'To other floors': 'Papunta sa ibang palapag',
  'Open': 'Bukas', 'Closed': 'Sarado', 'Being repaired': 'Inaayos', 'Opening soon': 'Magbubukas na', 'closest': 'pinakamalapit',
  // the route sheet
  'No way there': 'Walang daan papunta roon', 'Starting from': 'Simula sa', 'Where I am now': 'Kung nasaan ako ngayon',
  'There is no other way to get there.': 'Wala nang ibang daan papunta roon.',
  'The dotted amber line on the map is the other way.': 'Ang putol-putol na kulay-kahel na linya sa mapa ang ibang daan.',
  'Wheelchair route (lifts only)': 'Wheelchair route (elevator lang)', 'Wheelchair route': 'Wheelchair route', 'Turn off wheelchair route': 'I-off ang wheelchair route',
  "I've arrived": 'Nakarating na ako', 'You are outside': 'Nasa labas ka',
  'This way needs stairs: no lift or ramp reaches this floor.': 'Kailangan ng hagdan sa daang ito: walang elevator o rampa papunta sa palapag na ito.',
  'This way needs an escalator: nothing else reaches this floor.': 'Kailangan ng escalator sa daang ito: wala nang ibang daan papunta sa palapag na ito.',
  'By walking distance from you': 'Ayon sa layo ng lakad mula sa iyo', 'Details': 'Mga detalye', 'Open the panel': 'Buksan ang panel',
  'Find another way': 'Humanap ng ibang daan', 'Choosing another way': 'Pumipili ng ibang daan',
  'Staff at the information desk can help you. Any member of staff in uniform can help too.': 'Makakatulong sa iyo ang staff sa information desk. Puwede ring tumulong ang kahit sinong naka-uniporme.',
  // other ways
  'Pick the way that suits you': 'Piliin ang daang bagay sa iyo', 'Your current way': 'Kasalukuyang daan mo',
  'Same length': 'Parehong haba', 'Goes outside': 'Dadaan sa labas', 'under 1 min more': 'wala pang 1 min dagdag', 'Or go somewhere similar': 'O pumunta sa katulad na lugar',
  'Tips': 'Mga tip', 'Get help': 'Humingi ng tulong',
  
  'There is no other way there right now. Try somewhere similar below, or ask for help.': 'Wala nang ibang daan papunta roon ngayon. Subukan ang katulad na lugar sa ibaba, o humingi ng tulong.',
  'The other ways go around the stretch just ahead of you. Your current way is still here too.': 'Umiiwas ang ibang daan sa bahaging nasa unahan mo. Nandito pa rin ang kasalukuyang daan mo.',
  "If a store's door is locked or closed, the other ways go around the store.": 'Kung naka-lock o sarado ang pinto ng tindahan, umiikot ang ibang daan sa tindahan.',
  'If it is only busy, waiting a few minutes can be quicker than a long way round.': 'Kung matao lang, mas mabilis minsan ang maghintay ng ilang minuto kaysa umikot nang malayo.',
  'If a lift or escalator has stopped, stairs or another lift are usually close by.': 'Kung tumigil ang elevator o escalator, malapit lang kadalasan ang hagdan o ibang elevator.',
  'Not sure? Staff at the information desk can help.': 'Hindi sigurado? Makakatulong ang staff sa information desk.',
  // the emergency
  'Emergency': 'Emergency', 'Emergency evacuation': 'Emergency evacuation', 'Emergency: get out by the nearest exit': 'Emergency: lumabas sa pinakamalapit na exit',
  'Emergency. Get out by the nearest exit. Use the stairs, not the lifts.': 'Emergency. Lumabas sa pinakamalapit na exit. Gamitin ang hagdan, hindi ang elevator.',
  'Tell any member of staff where you are. Staff are trained to help everyone get out.': 'Sabihin sa kahit sinong staff kung nasaan ka. Sanay ang staff na tulungan ang lahat na makalabas.',
  'Stop evacuation': 'Itigil ang evacuation',
  'You are outside. Move away from the building and follow staff.': 'Nasa labas ka na. Lumayo sa gusali at sumunod sa staff.',
  'You are out. Keep clear of the doors and follow staff.': 'Nakalabas ka na. Lumayo sa mga pinto at sumunod sa staff.',
  'No way out can be found from here. Stay where you are, keep calm and call for help.': 'Walang mahanap na labasan mula rito. Manatili sa kinaroroonan mo, kumalma, at humingi ng tulong.',
  'the stairs (a safe place to wait)': 'ang hagdan (ligtas na hintayan)',
  'Lifts must not be used in an emergency. Go to the stairs and wait there: staff will help you down.': 'Bawal gamitin ang elevator sa emergency. Pumunta sa hagdan at maghintay doon: tutulungan ka ng staff pababa.',
  'No exit can be reached from here. Go to the stairs and wait for staff.': 'Walang maabot na exit mula rito. Pumunta sa hagdan at hintayin ang staff.',
  'Wait here at the stairs. Staff will come and help you down.': 'Maghintay dito sa hagdan. Darating ang staff para tulungan kang bumaba.',
  // where are you
  'Where are you?': 'Nasaan ka?', 'Indoor positioning can be off, so tell us: a shop near you, or your floor.': 'Minsan mali ang indoor positioning, kaya sabihin mo: tindahang malapit sa iyo, o ang palapag mo.',
  "I'm near here": 'Malapit ako rito',
  'Nothing found. Try another name, or pick your floor.': 'Walang nahanap. Subukan ang ibang pangalan, o piliin ang palapag mo.', 'OR PICK YOUR FLOOR': 'O PILIIN ANG PALAPAG MO',
  'Skip · keep my last spot': 'Laktawan · panatilihin ang huling kinalalagyan ko',
  // tabs and screens
  
  'Language': 'Wika', 'Text and display': 'Teksto at display', 'Text size': 'Laki ng teksto', 'Look': 'Itsura', 'High contrast': 'High contrast',
  'Getting around': 'Paglilibot', 'Walking pace (for the minutes shown)': 'Bilis ng lakad (para sa minutong ipinapakita)',
  'Avoid stairs': 'Iwasan ang hagdan', 'Avoid escalators': 'Iwasan ang escalator',
  'Stairs and escalators are only used when nothing else reaches a place, and the route says so.': 'Gagamitin lang ang hagdan at escalator kung wala nang ibang daan papunta sa lugar, at sasabihin ito ng ruta.',
  
  
  // settings values
  'Normal': 'Normal', 'Larger': 'Mas malaki', 'Largest': 'Pinakamalaki', 'Off': 'Off', 'On': 'On', 'Relaxed': 'Relaks', 'Slow': 'Mabagal',
  'On (lifts only)': 'On (elevator lang)', 'Light': 'Maliwanag', 'Dark': 'Madilim',
  'English': 'English', 'Tagalog': 'Tagalog',
  // the picker
  'building': 'gusali', 'buildings': 'gusali', 'levels': 'palapag', 'shops': 'tindahan', 'parking zones': 'parking zone',
  // the site
  'Grand Entrance': 'Grand Entrance',
  // favourites and recents
  'Favourites': 'Mga paborito', 'Recent': 'Kamakailan', 'Nearby': 'Malapit', 'Add to favourites': 'Idagdag sa paborito', 'Remove from favourites': 'Alisin sa paborito',
  'OK': 'OK',
  // directions
  'left': 'kaliwa', 'right': 'kanan', 'now': 'ngayon', ' outside': ' sa labas', 'Turn left': 'Kumaliwa', 'Turn right': 'Kumanan',
  'Bear left': 'Kumaliwa nang bahagya', 'Bear right': 'Kumanan nang bahagya', 'Turn sharp left': 'Kumaliwa nang husto', 'Turn sharp right': 'Kumanan nang husto',
  ', on your left': ', sa kaliwa mo', ', on your right': ', sa kanan mo',
  // spoken like a person: the clauses and their joins
  ', then ': ', tapos ', ' and ': ' at ', 'go in': 'pumasok', 'go out': 'lumabas', 'go through it': 'dumaan sa loob nito', 'cross it': 'tumawid dito',
  'the escalator': 'ang escalator', 'the lift': 'ang elevator', 'the stairs': 'ang hagdan', 'the ramp': 'ang rampa',
  // never stated as fact: expectations, then the real next step
  'go in through its doors': 'pumasok sa pintuan nito', 'this should be it': 'eto na siguro', 'This should be it': 'Eto na siguro',
  "If that's right, ": 'Kung tama iyan, ', 'Keep straight': 'Dumiretso lang',
  'Keep going up': 'Tuloy pa pataas', 'Keep going down': 'Tuloy pa pababa',
  'Almost there.': 'Malapit na.', 'Almost there': 'Malapit na', 'Getting close': 'Medyo malapit na',
  // pause and the position check
  'Pause': 'I-pause', 'Resume': 'Ituloy', 'Pause the walk': 'I-pause ang lakad', 'Resume the walk': 'Ituloy ang lakad',
  'Paused': 'Naka-pause', 'Paused · tap Resume to go on': 'Naka-pause · i-tap ang Ituloy para magpatuloy',
  'Are you here?': 'Nandito ka ba?', "Yes, that's right": 'Oo, tama', "Yes, I'm here": 'Oo, nandito ako', "No, I'm somewhere else": 'Hindi, nasa iba ako',
  'Have you arrived?': 'Nakarating ka na ba?',
  // not where the app expected: suggestive, never blaming
  "Looks like you've drifted off the way. Let's start again from here.": 'Mukhang nalihis ka ng daan. Simulan natin ulit mula rito.',
  'Type a shop, or describe where you are': 'I-type ang tindahan, o ilarawan kung nasaan ka',
  // stairs
  'Stairs': 'Hagdan', 'stairs': 'hagdan', 'to': 'hanggang',
  // ----- LIQo mobile (2026-10-22); please have a fluent speaker review -----
  // the shell and Home
  'Search this list': 'Maghanap sa listahang ito',
  'Brisk': 'Mabilis-bilis', 'Fast': 'Mabilis',
  'Walking pace (the minutes shown and the walk on the map)': 'Bilis ng lakad (ang minutong ipinapakita at ang lakad sa mapa)',
  'Home': 'Home', 'Places': 'Mga lugar', 'Saved': 'Naka-save', 'More': 'Iba pa', 'Categories': 'Mga kategorya', 'Posts': 'Mga post', 'Sample': 'Sample', 'Sample post': 'Sample na post',
  'Where do you want to go?': 'Saan mo gustong pumunta?', 'Shops': 'Mga tindahan', 'Food & Dining': 'Pagkain at Kainan', 'Elevators': 'Mga elevator',
  'Mall': 'Mall', 'Store': 'Tindahan', 'Mall management': 'Pamunuan ng mall', 'Post': 'Post', 'This post is no longer here.': 'Wala na rito ang post na ito.',
  'This is a sample post. Posts from stores, malls and mall management will appear here later.': 'Sample na post ito. Lalabas dito mamaya ang mga post mula sa mga tindahan, mall at pamunuan ng mall.',
  // splash and onboarding
  'Smart Way Forward': 'Smart Way Forward', 'Skip': 'Laktawan', 'Next': 'Susunod', 'Get started': 'Magsimula',
  'Find your way inside the mall': 'Hanapin ang daan sa loob ng mall', 'Explore. Discover. Shop. Effortlessly.': 'Maglibot. Tumuklas. Mamili. Nang madali.',
  'Everything in one place': 'Lahat sa iisang lugar', 'Browse stores, dining and services by category.': 'Tingnan ang mga tindahan, kainan at serbisyo ayon sa kategorya.',
  'Never get lost': 'Hindi na maliligaw', 'Clear turn-by-turn guidance across every level.': 'Malinaw na gabay sa bawat liko, sa bawat palapag.',
  // the mall picker and switcher
  'Choose a mall': 'Pumili ng mall', 'Change mall': 'Palitan ang mall', 'Current': 'Kasalukuyan',
  'Three sample malls to find your way around, until your mall is on LIQo.': 'Tatlong sample na mall para malibot, hangga\'t wala pa sa LIQo ang mall mo.',
  'Search malls, e.g. "tower", "bridge"': 'Maghanap ng mall, hal. "tower", "tulay"',
  // places, kinds and status
  'All': 'Lahat', 'Information desk': 'Information desk', 'Entrance': 'Pasukan', 'Escalator': 'Escalator', 'Ramp': 'Rampa', 'Escalators': 'Mga escalator',
  'Open 24 hours': 'Bukas 24 oras', 'Nothing here yet': 'Wala pang laman dito', 'Place': 'Lugar', 'This place is no longer on the map.': 'Wala na sa mapa ang lugar na ito.',
  'Tell us where you are on the map to see how far each place is.': 'Sabihin kung nasaan ka sa mapa para makita kung gaano kalayo ang bawat lugar.',
  'Get directions': 'Kunin ang direksyon', 'Directions': 'Direksyon', 'Where to?': 'Saan pupunta?', 'Show all floors': 'Ipakita lahat ng palapag', 'Hide the floors': 'Itago ang mga palapag', 'Tap one to see the way there': 'I-tap ang isa para makita ang daan', 'You can still get directions.': 'Makakakuha ka pa rin ng direksyon.', 'Call': 'Tumawag', 'Website': 'Website', 'Share': 'Ibahagi',
  'About': 'Tungkol dito', 'Phone': 'Telepono',
  'Sample details: the hours, phone and website are made up until the mall adds its own.': 'Sample na detalye: gawa-gawa lang ang oras, telepono at website hangga\'t hindi pa naglalagay ang mall ng sarili nila.',
  // search
  'Search for a store, a category or a place': 'Maghanap ng tindahan, kategorya o lugar', 'Recent searches': 'Mga kamakailang hinanap', 'Most visited': 'Madalas puntahan', 'Results': 'Mga resulta',
  'Search for a store, a kind of place or a level, like "food" or "level 2".': 'Maghanap ng tindahan, uri ng lugar o palapag, gaya ng "pagkain" o "level 2".',
  // the map
  'Whole site · tap a building to go in': 'Buong lugar · i-tap ang isang gusali para pumasok', 'Skip for now': 'Laktawan muna',
  'Tell us where you are to see what is nearest.': 'Sabihin kung nasaan ka para makita ang pinakamalapit.',
  'Tell us where you are, and the way out will show.': 'Sabihin kung nasaan ka, at lalabas ang daan palabas.',
  'Tell us where you are, and the way there will show.': 'Sabihin kung nasaan ka, at lalabas ang daan papunta roon.',
  'All the steps': 'Lahat ng hakbang', 'Start': 'Simulan', 'Start the walk': 'Simulan ang lakad', 'Route options': 'Mga opsyon sa ruta',
  // your route and route options
  'Your route': 'Ang ruta mo', 'Start where you are now': 'Magsimula kung nasaan ka ngayon', 'Ways there': 'Mga daan papunta roon', 'End navigation': 'Tapusin ang nabigasyon',
  'Back to the map': 'Bumalik sa mapa', 'Save this route': 'I-save ang rutang ito', 'Remove this saved route': 'Alisin ang naka-save na rutang ito',
  'There is no route right now. Pick a place and press Directions.': 'Walang ruta ngayon. Pumili ng lugar at pindutin ang Direksyon.',
  'The dashed blue line on the map is the other way.': 'Ang putol-putol na asul na linya sa mapa ang ibang daan.',
  'Fastest': 'Pinakamabilis', 'Shortest': 'Pinakamaikli', 'Avoid': 'Iwasan', 'Apply': 'Ilapat', 'No stairs': 'Walang hagdan', 'No escalators': 'Walang escalator',
  'Recommended · the least time, waits for lifts and escalators included': 'Inirerekomenda · pinakamaikling oras, kasama ang paghihintay sa elevator at escalator',
  'Less walking · rides on lifts and escalators hardly count': 'Mas kaunting lakad · halos hindi binibilang ang sakay sa elevator at escalator',
  // saved
  'Routes': 'Mga ruta', 'History': 'Kasaysayan', 'Arrived': 'Nakarating', 'Stopped': 'Itinigil', 'In progress': 'Kasalukuyan pa',
  'A saved route starts from wherever you are when you open it.': 'Nagsisimula ang naka-save na ruta kung nasaan ka pagbukas mo nito.',
  'No saved places yet. Tap the heart on a place to save it.': 'Wala pang naka-save na lugar. I-tap ang puso sa isang lugar para i-save ito.',
  'No saved routes yet. Save one from Your route.': 'Wala pang naka-save na ruta. Mag-save mula sa Ang ruta mo.',
  'No trips yet. Trips you start appear here.': 'Wala pang biyahe. Lalabas dito ang mga biyaheng sinimulan mo.',
  // more, settings, help, about
  'Settings': 'Mga setting', 'Help & Support': 'Tulong at Suporta', 'About LIQo': 'Tungkol sa LIQo', 'Licences': 'Mga lisensya',
  'Sign in (optional)': 'Mag-sign in (opsyonal)', 'LIQo works without an account.': 'Gumagana ang LIQo kahit walang account.',
  'Language, look, text size, getting around': 'Wika, itsura, laki ng teksto, paglilibot', 'Emergency evacuation is on': 'Naka-on ang emergency evacuation',
  'The way out by the nearest exit, stairs only': 'Ang daan palabas sa pinakamalapit na exit, hagdan lang',
  'Phone setting': 'Setting ng phone', 'Reduce motion': 'Bawasan ang galaw', 'No confetti, no colour fades, a still map': 'Walang confetti, walang pagkupas ng kulay, hindi gumagalaw ang mapa',
  'Black and white, with stronger lines': 'Itim at puti, may mas makakapal na linya', 'Alerts': 'Mga alerto', 'Vibration': 'Pag-vibrate',
  'Before each turn, when you may be off the way, and on arrival': 'Bago ang bawat liko, kapag maaaring nalihis ka, at pagdating',
  'Lifts, ramps and wide corridors only': 'Elevator, rampa at maluluwag na pasilyo lang', 'Fastest or shortest; avoid stairs or escalators': 'Pinakamabilis o pinakamaikli; iwasan ang hagdan o escalator',
  'LIQo finds your way inside the mall: search for a store, see whether it is open, and follow the directions floor by floor. The three malls in the app are samples until your mall is on LIQo.':
      'Tinutulungan ka ng LIQo na mahanap ang daan sa loob ng mall: maghanap ng tindahan, tingnan kung bukas ito, at sundan ang direksyon kada palapag. Mga sample ang tatlong mall sa app hangga\'t wala pa sa LIQo ang mall mo.',
  'Find a place': 'Maghanap ng lugar', 'Say where you are': 'Sabihin kung nasaan ka',
  'Search for a store, a kind of place or a level, or open a category on Home. Each result shows whether it is open.': 'Maghanap ng tindahan, uri ng lugar o palapag, o magbukas ng kategorya sa Home. Makikita sa bawat resulta kung bukas ito.',
  'Until the mall has beacons, tell LIQo where you are: pick a shop near you, or your floor and then tap the map.': 'Hangga\'t wala pang beacon ang mall, sabihin sa LIQo kung nasaan ka: pumili ng tindahang malapit sa iyo, o ang palapag mo at saka i-tap ang mapa.',
  'Open a place and press Directions (or the bent-arrow button on the map), then Start. The walk stops at each lift, escalator or stairs to check you are there.': 'Buksan ang isang lugar at pindutin ang Direksyon (o ang nakabaluktot na arrow sa mapa), saka Simulan. Humihinto ang lakad sa bawat elevator, escalator o hagdan para tiyaking nandoon ka.',
  'While walking, Find another way shows ways around the stretch just ahead, places like the one you are going to, and the way to the information desk.': 'Habang naglalakad, ipinapakita ng Humanap ng ibang daan ang mga daan paikot sa bahaging nasa unahan, mga lugar na katulad ng pupuntahan mo, at ang daan papunta sa information desk.',
  'Choose Fastest or Shortest, and avoid stairs or escalators. A wheelchair route uses lifts, ramps and wide corridors only.': 'Piliin ang Pinakamabilis o Pinakamaikli, at iwasan ang hagdan o escalator. Elevator, rampa at maluluwag na pasilyo lang ang ginagamit ng wheelchair route.',
  'In More, Emergency evacuation shows the way to the nearest exit by stairs, never lifts. Wheelchair users are shown a safe place to wait for staff.': 'Sa Iba pa, ipinapakita ng Emergency evacuation ang daan papunta sa pinakamalapit na exit gamit ang hagdan, hindi kailanman ang elevator. Ipinapakita sa mga naka-wheelchair ang ligtas na lugar para hintayin ang staff.',
  'Save places with the heart and routes from Your route. History keeps the trips you started.': 'I-save ang mga lugar gamit ang puso at ang mga ruta mula sa Ang ruta mo. Nasa Kasaysayan ang mga biyaheng sinimulan mo.',
  // sign in and sign up (look-only)
  'Accounts are coming soon': 'Malapit nang magkaroon ng account', 'Welcome back!': 'Maligayang pagbabalik!', 'Sign in to continue your journey.': 'Mag-sign in para ituloy ang iyong lakad.',
  'Email or username': 'Email o username', 'Password': 'Password', 'Enter your password': 'Ilagay ang iyong password', 'Forgot password?': 'Nakalimutan ang password?',
  'Sign in': 'Mag-sign in', 'Sign up': 'Mag-sign up', 'or continue with': 'o magpatuloy gamit ang', "Don't have an account?": 'Wala ka pang account?',
  'Already have an account?': 'May account ka na?', 'Create your account': 'Gumawa ng iyong account', 'Start your mall journey today.': 'Simulan ang iyong lakad sa mall ngayon.',
  'Full name': 'Buong pangalan', 'Email': 'Email', 'Create a password': 'Gumawa ng password', 'Confirm password': 'Kumpirmahin ang password',
  'Confirm your password': 'Kumpirmahin ang iyong password', 'I agree to the ': 'Sumasang-ayon ako sa ', 'Terms & Conditions': 'Mga Tuntunin at Kondisyon',
  'Privacy Policy': 'Patakaran sa Privacy', 'Show password': 'Ipakita ang password', 'Hide password': 'Itago ang password',
};

/// Words inside templates.
const Map<String, String> _words = {
  'escalator': 'escalator', 'lift': 'elevator', 'stairs': 'hagdan', 'ramp': 'rampa', ' and ': ' at ', ' along the ': ' sa ', ' outside': ' sa labas', ', past ': ', lampas sa ',
};

String _w(String s) {
  var out = s;
  _words.forEach((k, v) => out = out.replaceAll(k, v));
  return out;
}

/// A name after "sa": English "the" has no place there ("sa Grand Entrance").
String _name(String s) => s.startsWith('the ') ? s.substring(4) : s;
String _hand(String s) => s == 'left' ? 'kaliwa' : 'kanan';

/// Sentences with names or numbers in them, in order of trial.
final List<(RegExp, String Function(Match))> _rules = [
  // ----- LIQo mobile -----
  (RegExp(r'^Open · Closes (.+)$'), (m) => 'Bukas · Magsasara nang ${m[1]}'),
  (RegExp(r'^Until (.+)$'), (m) => 'Hanggang ${m[1]}'),
  (RegExp(r"^You're offline · showing posts from (.+)$"), (m) => 'Offline ka · ipinapakita ang mga post mula ${m[1]}'),
  (RegExp(r'^See (.+)$'), (m) => 'Tingnan ang ${m[1]}'),
  (RegExp(r'^Closed now · Opens tomorrow (.+)$'), (m) => 'Sarado ngayon · Magbubukas bukas nang ${m[1]}'),
  (RegExp(r'^Closed now · Opens (.+)$'), (m) => 'Sarado ngayon · Magbubukas nang ${m[1]}'),
  (RegExp(r'^(.+): out of service$'), (m) => '${m[1]}: hindi gumagana'),
  (RegExp(r'^Best way \((.+)\)$'), (m) => 'Pinakamagandang daan (${m[1]})'),
  (RegExp(r'^Mall: (.+)\. Change mall$'), (m) => 'Mall: ${m[1]}. Palitan ang mall'),
  (RegExp(r'^Search in (.+)$'), (m) => 'Maghanap sa ${m[1]}'),
  (RegExp(r'^Directions to (.+)$'), (m) => 'Direksyon papunta sa ${m[1]}'),
  (RegExp(r'^Delete (.+)\?$'), (m) => 'Burahin ang ${m[1]}?'),
  (RegExp(r'^Updated (.+)$'), (m) => 'Na-update noong ${m[1]}'),
  (RegExp(r'^Update · (.+)$'), (m) => 'I-update · ${m[1]}'),
  (RegExp(r'^Map update available · (.+)$'), (m) => 'May update ang mapa · ${m[1]}'),
  (RegExp(r'^A newer map of (.+) needs the latest LIQo\. Update LIQo from your app store\.$'),
      (m) => 'Kailangan ng pinakabagong LIQo para sa bagong mapa ng ${m[1]}. I-update ang LIQo mula sa app store mo.'),
  (RegExp(r"^This mall's map is (.+)\. You're on mobile data, not Wi-Fi\.$"), (m) => '${m[1]} ang mapa ng mall na ito. Naka-mobile data ka, hindi Wi-Fi.'),
  (RegExp(r'^There is no way to (.+) from here\.$'), (m) => 'Walang daan papunta sa ${m[1]} mula rito.'),
  (RegExp(r'^Page (\d+) of (\d+)$'), (m) => 'Pahina ${m[1]} ng ${m[2]}'),
  (RegExp(r'^Version (.+)$'), (m) => 'Bersyon ${m[1]}'),
  (RegExp(r'^A drawing of (.+)$'), (m) => 'Larawan ng ${m[1]}'),
  (RegExp(r'^No mall matches "(.+)"\.$'), (m) => 'Walang mall na tumutugma sa "${m[1]}".'),
  (RegExp(r'^About (.+) to walk$'), (m) => 'Mga ${m[1]} na lakad'),
  // spoken directions, clause by clause
  (RegExp(r'^Walk straight towards (.+)$'), (m) => 'Dumiretso papunta sa ${_name(m[1]!)}'),
  (RegExp(r'^Walk past (.+) towards (.+)$'), (m) => 'Dumaan sa ${_w(m[1]!)} papunta sa ${_name(m[2]!)}'),
  (RegExp(r'^Walk straight past (.+)$'), (m) => 'Dumiretso lampas sa ${_w(m[1]!)}'),
  (RegExp(r'^Walk straight for about (\d+ m)( outside)?$'), (m) => 'Dumiretso nang mga ${m[1]}${m[2] == null ? '' : ' sa labas'}'),
  (RegExp(r'^take it (up|down) to (.+)$'), (m) => 'sumakay pa${m[1] == 'up' ? 'taas' : 'baba'} papuntang ${m[2]}'),
  // stairs and a ramp are climbed, not ridden
  (RegExp(r'^go (up|down) (them|it) to (.+)$'), (m) => '${m[1] == 'up' ? 'umakyat' : 'bumaba'} papuntang ${m[3]}'),
  // expectations, never statements of fact
  (RegExp(r'^You should see (.+) on your (left|right)$'), (m) => 'Dapat makita mo na ang ${m[1]} sa ${_hand(m[2]!)} mo'),
  (RegExp(r'^You should see (.+)$'), (m) => 'Dapat makita mo ang ${m[1]}'),
  (RegExp(r'^You should be right by (.+)$'), (m) => 'Dapat nasa tabi ka na ng ${m[1]}'),
  (RegExp(r'^This should be it, on your (left|right)$'), (m) => 'Eto na siguro, sa ${_hand(m[1]!)} mo'),
  (RegExp(r"^If you see (.+), you're in the right place$"), (m) => 'Kung nakikita mo ang ${m[1]}, tama ang lugar mo'),
  (RegExp(r'^, with (.+)$'), (m) => ', at malapit ang ${m[1]}'),
  (RegExp(r"^You should be at (.+) now\. Tap I've arrived if you are\.$"), (m) => 'Dapat nasa ${m[1]} ka na. I-tap ang Nakarating na ako kung oo.'),
  (RegExp(r'^(.+) · should be on your (left|right)$'), (m) => '${m[1]} · dapat nasa ${_hand(m[2]!)} mo'),
  (RegExp(r'^Getting close now, about (\d+ m)$'), (m) => 'Medyo malapit na, mga ${m[1]} pa'),
  (RegExp(r'^You should be passing (.+) on your (left|right) about now$'), (m) => 'Dapat nadadaanan mo na ang ${m[1]} sa ${_hand(m[2]!)} mo ngayon'),
  (RegExp(r'^You should be passing (.+) about now$'), (m) => 'Dapat nadadaanan mo na ang ${m[1]} ngayon'),
  (RegExp(r'^next look for (.+) on your (left|right)$'), (m) => 'sunod, hanapin ang ${m[1]} sa ${_hand(m[2]!)} mo'),
  (RegExp(r'^next look for (.+)$'), (m) => 'sunod, hanapin ang ${_name(m[1]!)}'),
  (RegExp(r'^(.+) should be about (\d+ m) ahead$'), (m) => 'dapat nasa unahan ang ${_name(m[1]!)}, mga ${m[2]} pa'),
  // whole ("Keep straight for about 50 m more.") or after a passing clause ("...; keep straight for about 50 m more")
  (RegExp(r'^([Kk])eep straight for about (\d+ m) more$'), (m) => '${m[1] == 'K' ? 'D' : 'd'}umiretso pa nang mga ${m[2]}'),
  (RegExp(r'^(.+) coming up on your (left|right)$'), (m) => 'Malapit na ang ${m[1]} sa ${_hand(m[2]!)} mo'),
  (RegExp(r'^(.+) · keep going (up|down) to (.+)$'), (m) => '${m[1]} · tuloy pa pa${m[2] == 'up' ? 'taas' : 'baba'} papuntang ${m[3]}'),
  (RegExp(r'^You should now be on (.+)$'), (m) => 'Dapat nasa ${m[1]} ka na ngayon'),
  (RegExp(r'^Are you at (.+)\?$'), (m) => 'Nasa ${_name(m[1]!)} ka na ba?'),
  (RegExp(r'^You should be on (.+)$'), (m) => 'Dapat nasa ${m[1]} ka'),
  (RegExp(r'^(.+) ahead$'), (m) => '${m[1]} sa unahan'),
  (RegExp(r'^(.+) behind you$'), (m) => '${m[1]} sa likuran mo'),
  // a thing by hand ("Zen Gifts on your left"), never a statement ("Zen Gifts is on your left" stays as it is: the app does not say that)
  (RegExp(r'^((?!.*\bis\b).+) on your (left|right)$'), (m) => '${m[1]} sa ${m[2] == 'left' ? 'kaliwa' : 'kanan'} mo'),
  (RegExp(r'^near (.+)$'), (m) => 'malapit sa ${m[1]}'),
  (RegExp(r'^Nearest (.+): (.+)$'), (m) => 'Pinakamalapit na ${_exact[m[1]] ?? m[1]}: ${m[2]}'),
  (RegExp(r'^Walk through (.+?)( \(.+\))?$'), (m) => 'Dumaan sa loob ng ${m[1]}${m[2] ?? ''}'),
  (RegExp(r'^Walk (\d+ m) along the covered walkway$'), (m) => 'Maglakad ng ${m[1]} sa covered walkway'),
  (RegExp(r'^Walk (\d+ m)(.*)$'), (m) => 'Maglakad ng ${m[1]}${_w(m[2]!)}'),
  // stairs and a ramp are climbed; a lift or escalator is ridden
  (RegExp(r'^Take the (stairs|ramp) (up|down) to (.+)$'), (m) => '${m[2] == 'up' ? 'Umakyat' : 'Bumaba'} sa ${_w(m[1]!)} papuntang ${m[3]}'),
  (RegExp(r'^Take the (\w+) (up|down) to (.+)$'), (m) => 'Sumakay sa ${_w(m[1]!)} pa${m[2] == 'up' ? 'taas' : 'baba'} papuntang ${m[3]}'),
  (RegExp(r'^Riding the (stairs|ramp) to (.+)$'), (m) => 'Nasa ${_w(m[1]!)} papuntang ${m[2]}'),
  (RegExp(r'^Riding the (\w+) to (.+)$'), (m) => 'Sakay sa ${_w(m[1]!)} papuntang ${m[2]}'),
  (RegExp(r'^Cross (.+)$'), (m) => 'Tumawid sa ${_name(m[1]!)}'),
  (RegExp(r'^Go in through (.+)$'), (m) => 'Pumasok sa ${_name(m[1]!)}'),
  (RegExp(r'^Go out through (.+)$'), (m) => 'Lumabas sa ${_name(m[1]!)}'),
  (RegExp(r'^Go to (.+)$'), (m) => 'Pumunta sa ${m[1]}'),
  (RegExp(r'^You have arrived at (.+?)(\.?)$'), (m) => 'Nakarating ka na sa ${m[1]}${m[2]}'),
  (RegExp(r'^In (\d+ m), (.+)$'), (m) => '${m[1]} pa, ${m[2]}'),
  // at the turn: "Kumanan na sa Atlas Bank", not "Kumanan sa Atlas Bank na" (the turn was composed in Tagalog already)
  (RegExp(r'^(Kumaliwa|Kumanan)( nang bahagya| nang husto)?( sa .+)? now$'), (m) => '${m[1]} na${m[2] ?? ''}${m[3] ?? ''}'),
  (RegExp(r'^(.+) now$'), (m) => '${m[1]} na'),
  (RegExp(r'^in (\d+ m)$'), (m) => '${m[1]} pa'),
  (RegExp(r'^past (.+)$'), (m) => 'lampas sa ${_w(m[1]!)}'),
  (RegExp(r'^ along the (.+)$'), (m) => ' sa ${m[1]}'),
  (RegExp(r'^(Kumaliwa|Kumanan)( nang bahagya| nang husto)? at (.+)$'), (m) => '${m[1]}${m[2] ?? ''} sa ${m[3]}'),
  (RegExp(r'^(Turn|Bear|Turn sharp) (left|right) at (.+)$'), (m) => '${m[2] == 'left' ? 'Kumaliwa' : 'Kumanan'}${m[1] == 'Bear' ? ' nang bahagya' : m[1] == 'Turn sharp' ? ' nang husto' : ''} sa ${m[3]}'),
  (RegExp(r'^Arrive at (.+)$'), (m) => 'Nakarating sa ${m[1]}'),
  (RegExp(r'^Showing (.+)$'), (m) => 'Ipinapakita ang ${m[1]}'),
  (RegExp(r'^You are on ([^,]+)(, outside)?$'), (m) => 'Nasa ${m[1]} ka${m[2] == null ? '' : ', sa labas'}'),
  (RegExp(r'^Route to (.+), (\d+ m) to go$'), (m) => 'Ruta papunta sa ${m[1]}, ${m[2]} pa'),
  (RegExp(r'^Next: $'), (m) => 'Susunod: '),
  (RegExp(r'^There is no wheelchair route to (.+)\.$'), (m) => 'Walang wheelchair route papunta sa ${m[1]}.'),
  (RegExp(r'^On (.+)$'), (m) => 'Nasa ${m[1]}'),
  (RegExp(r'^To (.+)$'), (m) => 'Papunta sa ${m[1]}'),
  (RegExp(r'^Shortest \((.+)\)$'), (m) => 'Pinakamaikli (${m[1]})'),
  (RegExp(r'^Other way (\d+) \((.+)\)$'), (m) => 'Ibang daan ${m[1]} (${m[2]})'),
  (RegExp(r'^Other ways to (.+)$'), (m) => 'Ibang daan papunta sa ${m[1]}'),
  (RegExp(r'^Way around (\d+)$'), (m) => 'Ikot ${m[1]}'),
  (RegExp(r'^Nearest: (.+)$'), (m) => 'Pinakamalapit: ${m[1]}'),
  (RegExp(r'^Nearest (.+)$'), (m) => 'Pinakamalapit na ${_exact[m[1]] ?? m[1]}'),
  (RegExp(r'^(\d+ m) to the exit$'), (m) => '${m[1]} papunta sa exit'),
  (RegExp(r'^(\d+) more level changes?$'), (m) => '${m[1]} pang palit ng palapag'),
  (RegExp(r'^(\d+) fewer level changes?$'), (m) => '${m[1]} na mas kaunting palit ng palapag'),
  (RegExp(r'^(.+) · (\d+)$'), (m) => '${tagalog(m[1]!)} · ${m[2]}'),
  (RegExp(r'^(\d+) (building|buildings|levels|shops|parking zones)$'), (m) => '${m[1]} ${_exact[m[2]]}'),
];

/// Everyday Tagalog for an English phrase the app composed; English when unknown.
String tagalog(String en) {
  final hit = _exact[en];
  if (hit != null) return hit;
  for (final (re, f) in _rules) {
    final m = re.firstMatch(en);
    if (m != null) return f(m);
  }
  // a clause in the middle of a sentence ("turn left", "take the lift up to level 2"): the
  // capitalised phrase, lower-cased back
  final cap = _capFirst(en);
  if (cap != en) {
    final t = tagalog(cap);
    if (t != cap) return t[0].toLowerCase() + t.substring(1);
  }
  return en;
}

String _capFirst(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// Is this phrase one the app can say in Tagalog?
bool hasTagalog(String en) {
  if (_exact.containsKey(en) || _rules.any((r) => r.$1.hasMatch(en))) return true;
  final cap = _capFirst(en);
  return cap != en && hasTagalog(cap);
}
