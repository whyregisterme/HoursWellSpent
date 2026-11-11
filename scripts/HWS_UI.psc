Scriptname HWS_UI Hidden
{Every Magelight UI call Hours Well Spent makes. Magelight is optional: when it is missing, too old or
 not ready, Available() is false, nothing below calls it, and HWS_Main falls back to message boxes.
 Kept apart from HWS_Main so that script never names Magelight at all.

 The page is Data/Magelight/HoursWellSpent/views/hws_page/index.html, created hidden at startup by that
 folder's manifest.json. Magelight keeps nothing in the save, so Setup() runs on every load, and again
 at a proposal when the last try found no page.

 Every name passed to Magelight must be one no other script or record uses. Papyrus strings are
 interned without regard to case and keep the first casing seen, while Magelight compares case
 exactly. 0.2.0 named the view "prompt": on a load order where something said "Prompt" first,
 FindView returned 0 and the mod fell back to message boxes with nothing in any log.}

string Function ModId() Global
    return "HoursWellSpent"
EndFunction

; Must match the views key in Data/Magelight/HoursWellSpent/manifest.json, case included.
string Function ViewName() Global
    return "hws_page"
EndFunction

; Magelight's SKSE plugin is loaded, usable or not.
bool Function Installed() Global
    return SKSE.GetPluginVersion("Magelight") > 0
EndFunction

; 1.3.0: the oldest host this was tested on.
bool Function Available() Global
    if !Installed()
        return false
    endif
    return Magelight.GetVersion() >= 10300 && Magelight.IsReady()
EndFunction

; Diagnostic build: Magelight's state in one line, safe to call when Magelight is missing.
string Function Describe() Global
    int plugin = SKSE.GetPluginVersion("Magelight")
    if plugin <= 0
        return "Magelight SKSE plugin not loaded (GetPluginVersion " + plugin + ")"
    endif
    return "Magelight plugin " + plugin + ", GetVersion " + Magelight.GetVersion() + " (" + Magelight.GetVersionString() \
        + "), IsReady " + Magelight.IsReady() + ", UI mode active " + Magelight.IsUIModeActive() \
        + " (view " + Magelight.GetUIModeView() + "), our view " + Magelight.FindView(ModId(), ViewName()) \
        + ", last error '" + Magelight.GetLastError(ModId()) + "'"
EndFunction

; The page's view id, or 0 when there is no usable page this session.
int Function Setup() Global
    HWS_Diag.Log("Setup: " + Describe())
    if !Available()
        ; Not installed is the ordinary case and says nothing. Installed but unusable is worth a line.
        if Installed()
            Debug.Trace("[HWS] Magelight is installed but unusable: version " + Magelight.GetVersionString() \
                + " (needs 1.3.0), ready " + Magelight.IsReady() + ". Message boxes for now.")
        endif
        HWS_Diag.Log("Setup: Available() false -> message boxes")
        return 0
    endif
    if !Magelight.RegisterMod(ModId(), "Hours Well Spent")
        Debug.Trace("[HWS] Magelight refused the mod: " + Magelight.GetLastError(ModId()))
        HWS_Diag.Log("Setup: RegisterMod refused: " + Magelight.GetLastError(ModId()))
        return 0
    endif
    int view = Magelight.FindView(ModId(), ViewName())
    if view == 0
        Debug.Trace("[HWS] Magelight has no '" + ViewName() + "' view (last error '" + Magelight.GetLastError(ModId()) \
            + "'); is Data/Magelight/HoursWellSpent installed? Message boxes for now.")
        HWS_Diag.Log("Setup: FindView(" + ViewName() + ") = 0 -> message boxes")
        return 0
    endif
    ; hwsChoice: a button's answer. hwsPlan: the planner's confirmed plan, as JSON.
    bool listening = Magelight.RegisterListener(view, "hwsChoice")
    bool planListening = Magelight.RegisterListener(view, "hwsPlan")
    HWS_Diag.Log("Setup: OK, view " + view + ", RegisterListener hwsChoice " + listening + ", hwsPlan " + planListening)
    return view
EndFunction

; Hands the page its content, shows it and takes the cursor with the game paused. False when another
; mod holds the cursor: the view is hidden again and the caller uses a message box instead.
bool Function Open(int aiView, string asFunction, string asJson) Global
    HWS_Diag.Log("Open " + asFunction + " on view " + aiView + ": before, " + Describe())
    Magelight.Call(aiView, asFunction, asJson)
    Magelight.ShowView(aiView, true)
    if !Magelight.RequestUIMode(aiView, true)
        Debug.Trace("[HWS] Magelight UI mode refused: " + Magelight.GetLastError(ModId()))
        HWS_Diag.Log("Open: RequestUIMode REFUSED: '" + Magelight.GetLastError(ModId()) + "', UI mode held by view " \
            + Magelight.GetUIModeView() + " -> message box")
        Magelight.ShowView(aiView, false)
        return false
    endif
    HWS_Diag.Log("Open: RequestUIMode granted, UI mode view now " + Magelight.GetUIModeView())
    return true
EndFunction

Function Close(int aiView) Global
    HWS_Diag.Log("Close view " + aiView)
    Magelight.ReleaseUIMode(ModId())
    Magelight.ShowView(aiView, false)
EndFunction
