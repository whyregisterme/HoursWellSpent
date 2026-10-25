Scriptname HWS_PlayerAlias extends ReferenceAlias
{On the PlayerAlias of HWS_Quest. Quest scripts get no load event, so this passes it on.}

Event OnPlayerLoadGame()
    HWS_Main main = GetOwningQuest() as HWS_Main
    if main
        main.OnGameLoad()
    endif
EndEvent
