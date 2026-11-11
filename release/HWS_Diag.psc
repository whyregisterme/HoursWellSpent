Scriptname HWS_Diag Hidden
{Release build: the development log is off, so every function here does nothing. The development copy
 is scripts/HWS_Diag.psc; build.sh compiles that one only into versions named "-diag". Keep the two
 copies' functions and signatures the same. Don't name the log file here: verify_release.py treats a
 release HWS_Diag that names it as the development log shipped by mistake.}

Function StartSession(string asHeader) Global
EndFunction

Function Log(string asText) Global
EndFunction
