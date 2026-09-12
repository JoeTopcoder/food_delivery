import 'package:flutter_map/flutter_map.dart';

/// The one definition of the app's map tiles.
///
/// This used to be the same CARTO URL copied into fourteen widgets across ten
/// files, which is how a single change on CARTO's side — they now require an
/// API key and stamp "API KEY REQUIRED" across unkeyed tiles — broke every map
/// in the app at once, with fourteen places to fix it. There is one now.
///
/// OpenStreetMap's standard tiles need no key. Their usage policy is written
/// for modest traffic, though: it asks for a real identifying User-Agent (set
/// below), forbids bulk downloading, and expects heavy or commercial users to
/// move to a paid provider or self-host. This is the right fix for today, not
/// forever — at volume, switch the two constants here to a keyed provider
/// (MapTiler, Stadia, Thunderforest, or CARTO with a key) and every map on
/// every screen follows.
TileLayer appMapTileLayer() => TileLayer(
  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
  // Identifies the app to the tile server, as OSM's policy requires. An
  // anonymous or generic agent is what gets a client blocked.
  userAgentPackageName: 'sevendash.app',
  // OSM retired the a/b/c subdomains; requesting them now just fails.
  maxNativeZoom: 19,
);
