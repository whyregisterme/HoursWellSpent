Scriptname HWS_PlanEffect extends ActiveMagicEffect
{HWS_PlanEffect, on the Plan the Hours lesser power: opens the planner. HWS_Main hands the power out on
 every load. Modelled on Spellwork's Soul Study power.}

HWS_Main Property MainQuest Auto
{HWS_Quest.}

Event OnEffectStart(Actor akTarget, Actor akCaster)
    if MainQuest
        MainQuest.OpenPlanner()
    endif
EndEvent
