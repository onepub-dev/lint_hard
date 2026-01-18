/* Copyright (C) Brett Sutton - All Rights Reserved
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 * Written by Brett Sutton <bsutton@onepub.dev>, Jan 2022
 */

Future<String> getStringAsync() async {
  // unawaited_futures should trigger a lint warning.
  final name = getNameAsync();
  return name;
}

Future<String> getNameAsync() async {
  return Future.value('me');
}
