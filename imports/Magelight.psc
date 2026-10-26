Scriptname Magelight Hidden
{Magelight UI - Papyrus tier. Every function is Global; the host DLL supplies them.
 A mod is a slug (modId). Views are integer ids (0 = none). See docs/PAPYRUS.md.

 Scripts act only on script-owned mods: a mod registered by a script, or declared
 by a manifest.json that no plugin (DLL) adopted, whose storage jar is its own (not
 "default", not a plugin's session). A slug or view a plugin owns is refused
 (false / 0 / nothing, one log line per function and target); FindView, IsVisible,
 IsUIModeActive, GetUIModeView, GetLastError, GetVersion* and IsReady work for any
 mod. Every script can drive every script-owned mod's views, so keep secrets out of
 page storage.

 Host events arrive as ModEvents (SKSE ModCallbackEvent), e.g.
   RegisterForModEvent("Magelight_ViewDomReady", "OnMlDomReady")
   Event OnMlDomReady(string eventName, string strArg, float numArg, Form sender)
 strArg = your modId, or modId|detail where the event carries text; numArg = view id.
 Registrations last for the current game session only: redo them on every load.
 Events: ViewDomReady, ViewLoadFailed, ViewReloaded, ViewDestroyed, UIModeEntered,
 UIModeExited, FocusDenied, DisplayResized, RenderDead, UIModeRefused.

 JS -> Papyrus: RegisterListener(view, "save") then in the page window.save("payload");
 arrives as ModEvent "Magelight_JS_save" (strArg = payload, numArg = view id).
 Papyrus -> JS: Call(view, "setState", json) invokes window.setState(json).}

; Packed host version MAJOR*10000 + MINOR*100 + PATCH (0 = Magelight not installed:
; the call errors in the log and returns 0 when the DLL is absent).
int Function GetVersion() Global Native
string Function GetVersionString() Global Native
; False when the overlay disabled itself for this session.
bool Function IsReady() Global Native

; Register (or adopt a manifest mod with the same slug). Idempotent.
bool Function RegisterMod(string modId, string displayName = "") Global Native

; htmlPath: relative to Data/Magelight/<modId>/ (the manifest layout; a page that is not
; there is refused), or absolute inside the game folder.
; w = h = 0 -> fullscreen. layer: hud | panel | popup | system.
; anchor: top-left | top-right | bottom-left | bottom-right (x/y offset from it).
int Function CreateView(string modId, string name, string htmlPath, int x, int y, int w, int h, \
    string layer = "panel", string anchor = "top-left", bool clickThrough = false, bool startVisible = false) Global Native
; A view created by the mod's manifest.json (or an earlier CreateView), by name.
int Function FindView(string modId, string name) Global Native
Function DestroyView(int view) Global Native
Function ShowView(int view, bool show) Global Native
bool Function IsVisible(int view) Global Native

; Cursor up, game controls suspended, keyboard to the page. One holder at a time:
; false = someone else holds it (see GetLastError). Escape exits unless the page has
; taken Escape; the host's toggle key (PageUp by default) always does.
bool Function RequestUIMode(int view, bool pauseGame = false) Global Native
bool Function ReleaseUIMode(string modId) Global Native
bool Function IsUIModeActive() Global Native
int Function GetUIModeView() Global Native

Function ReloadView(int view) Global Native
; window.<function>(argument) on the page.
Function Call(int view, string functionName, string argument = "") Global Native
; Evaluate raw JavaScript on the page (fire and forget; exceptions only reach the log).
Function Eval(int view, string script) Global Native
; Evaluate and get the value back: ModEvent Magelight_JSResult (strArg = token|result) or
; Magelight_JSError (strArg = token|exception), numArg = view id. token is yours to match.
Function EvalAsync(int view, string script, string token = "") Global Native
; action: 1 toggle UI mode, 2 toggle UI mode (paused), 3 toggle visible, 0 unbind.
; dxScancode is the DirectInput code (Home = 199). The host's toggle key (PageUp = 201 by
; default) is refused. Busy/denied -> false + GetLastError.
bool Function BindHotkey(int view, int dxScancode, int action) Global Native
; Punch a see-through rectangle (view pixels) in the page so the game shows there; w or h = 0 clears.
Function SetCutout(int view, int x, int y, int w, int h) Global Native
; A view hidden longer than idleMs frees its texture; showing it reloads the page (ViewDomReady
; fires again). 0 = never. Good for popups that spend most of the game hidden.
Function SetHibernate(int view, int idleMs) Global Native
; While the view holds UI mode with pauseGame, the game skips its 3D world render behind it (a
; frozen frame shows instead): for an opaque fullscreen page. Kept until changed. False on VR, when
; the player turned it off in Magelight.json, or for a view the script may not drive. Host 0.31.0+.
bool Function SetFreezeWorld(int view, bool freeze) Global Native
; Your own cursor over the view, one page state at a time: cursorState "arrow", "pointer" (over a clickable
; element) or "text". imagePath: a PNG or DDS up to 256x256, relative to the mod folder
; (Data/Magelight/<Mod>/ for a page there, else the page's own folder); "" clears
; the state; "none" (arrow) hides the host cursor over the view because the page draws its own. hotX/hotY
; = the pointer pixel in image pixels, height = px at 1080p (0 = the image's own), press = shrink on a
; click. The player may override it in Magelight.json. Host 0.31.1+ (guard with GetVersion() >= 3101: unreleased 0.31.0 builds lack it).
bool Function SetCursor(int view, string cursorState, string imagePath, float hotX = 0.0, float hotY = 0.0, \
    int height = 0, bool press = false) Global Native
; Every state cleared: back to the manifest's default cursor or the host cursor. Host 0.31.0+.
Function ClearCursor(int view) Global Native
; Expose window.<name>(payload) on the page; each call raises ModEvent Magelight_JS_<name>.
; "magelight" and names starting "__" belong to the host's page script: false.
bool Function RegisterListener(int view, string name) Global Native
string Function GetLastError(string modId) Global Native
; Play a UI sound through the game's audio (a page cannot: Ultralight has no media stack). Names:
; "ok"/"click", "cancel", "prevnext", "focus"/"hover", "open", "close", "inactive" (the vanilla
; UIMenu* sounds), or "Plugin.esp|0xFormID" of any SNDR. Unknown = silent (logged once). Host 0.29.0+.
Function PlaySound(int view, string name) Global Native
; What the mod's pages may reach: "file" (the default: nothing over the network) or
; "loopback" (also http(s) and ws(s) to localhost or 127.0.0.1). Registers the mod if needed. "any",
; other words and a plugin's mod return false; internet reach is a plugin's call. Host 0.30.0+.
bool Function SetNetworkPolicy(string modId, string policy) Global Native
; Write Ultralight's memory figures and its full memory report to Magelight.log on the next frame, at most once
; every 10 seconds (a call sooner is dropped). For the console: cgf "Magelight.LogMemoryUsage". Host 1.5.0+.
Function LogMemoryUsage() Global Native
