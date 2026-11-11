Scriptname HWS_Diag Hidden
{Development log. Every line goes to Data/SKSE/Plugins/HoursWellSpent_diag.log through PapyrusUtil
 (already required), so it is written whether or not Papyrus logging is on, and to the Papyrus log too.
 Under MO2 the file lands in the overwrite folder: overwrite/SKSE/Plugins/HoursWellSpent_diag.log.

 This copy is compiled only into versions named "-diag". A release build compiles release/HWS_Diag.psc
 instead, where every function is empty (build.sh picks one by the version; verify_release.py checks).}

string Function Path() Global
    return "Data/SKSE/Plugins/HoursWellSpent_diag.log"
EndFunction

; Once per load. Past about 100 KB the file starts over, so it can't grow without end, yet a reload
; right after something went wrong doesn't wipe the lines that show it.
Function StartSession(string asHeader) Global
    string p = Path()
    if MiscUtil.FileExists(p) && StringUtil.GetLength(MiscUtil.ReadFromFile(p)) > 100000
        MiscUtil.WriteToFile(p, "[log started over: it had passed 100 KB]\n", false, false)
    endif
    Log(asHeader)
EndFunction

Function Log(string asText) Global
    string line = "[" + Utility.GetCurrentRealTime() + "s] " + asText
    MiscUtil.WriteToFile(Path(), line + "\n", true, true)
    Debug.Trace("[HWS diag] " + asText)
EndFunction
