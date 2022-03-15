Future<String> getStringAsync() async {
  // unawaited_futures should trigger a lint warning.
  final name = getNameAsync();
  return name;
}

Future<String> getNameAsync() async {
  return Future.value('me');
}
