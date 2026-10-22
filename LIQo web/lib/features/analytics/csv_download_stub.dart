/// Used when there is no browser (tests on the VM).
void downloadText(String filename, String text, {String mime = 'text/csv;charset=utf-8'}) {
  throw UnsupportedError('Downloads are only available in the browser.');
}
