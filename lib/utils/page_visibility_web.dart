import 'dart:html' as html;

void initPageVisibilityListener(Function(bool) onVisibilityChange) {
  html.document.addEventListener('visibilitychange', (event) {
    final isHidden = html.document.hidden ?? false;
    onVisibilityChange(isHidden);
  });
  
  // Também escutar eventos de blur/focus da janela (fallback)
  html.window.onBlur.listen((event) {
    onVisibilityChange(true);
  });
  
  html.window.onFocus.listen((event) {
    onVisibilityChange(false);
  });
}
