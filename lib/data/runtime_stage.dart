// Enum describing the three possible lifetime states of the app after the
// first successful config request:
//  - [fresh]  – never contacted the backend (or the last contact failed);
//               splash should run the full pending flow.
//  - [portal] – backend previously returned an URL; splash routes into the
//               WebView shell.
//  - [arena]  – backend previously refused (organic / no-data); splash goes
//               straight to the volcanic puzzle. Never re-asks the backend.
enum RuntimeStage {
  fresh,
  portal,
  arena;

  String encode() {
    switch (this) {
      case RuntimeStage.portal:
        return 'portal';
      case RuntimeStage.arena:
        return 'arena';
      case RuntimeStage.fresh:
        return 'fresh';
    }
  }

  static RuntimeStage decode(String? raw) {
    switch (raw) {
      case 'portal':
        return RuntimeStage.portal;
      case 'arena':
        return RuntimeStage.arena;
      default:
        return RuntimeStage.fresh;
    }
  }
}
