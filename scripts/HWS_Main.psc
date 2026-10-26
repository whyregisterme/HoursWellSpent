Scriptname HWS_Main extends Quest
{Hours Well Spent: an NPC proposes spending the next hours on something together (review the ledgers,
 walk the battlements, spar in the yard); the player confirms; time passes behind a fade; SkyrimNet
 writes how it went, and the NPC, the player and anyone along remember it.

 SkyrimNet calls SpendTimeTogether (layer actions/SpendTimeTogether.yaml). The scene is written by the
 layer's prompts/hws_scene.prompt through SendCustomPromptToLLM; OnScene receives it.

 Nothing here knows who the player is: names, bios and places all come from SkyrimNet at run time.

 The proposal and the account show on a Magelight UI page when Magelight is installed (HWS_UI), and
 as message boxes otherwise, or whenever the page can't be used: another mod holds the cursor, the page
 failed to load, or HWS_UseMagelight is 0.

 StorageUtil keys:
     HWS_Active   int, global (None)   1 while time is being spent (the action is hidden meanwhile)

 Stuck? From the console: stopquest HWS_Quest, then startquest HWS_Quest.}

ReferenceAlias Property PartnerAlias Auto
{Alias 1, Optional. Holds the NPC while the time is spent.}

Message Property ConfirmMsg Auto
{"Spend the next while together?" Spend the time / Not now / Not now (silently). The box names nobody: an
 <Alias=Partner> tag printed "[...]" in game, so the notification before it carries the name.}

GlobalVariable Property GameHour Auto
{Skyrim.esm GameHour (0x38). Hours are added to it, as the vanilla wait and Pass the Time do.}

GlobalVariable Property UseMagelight Auto
{HWS_UseMagelight, default 1. 0 = always message boxes (say, for a controller). Console:
 set HWS_UseMagelight to 0. Turning it back on takes effect at the next load.}

; Tuning.
int Property MinHours = 1 AutoReadOnly
int Property MaxHours = 8 AutoReadOnly
int Property DefaultHours = 2 AutoReadOnly
int Property CooldownSeconds = 90 AutoReadOnly           ; before SpendTimeTogether is offered again
float Property SceneTimeoutSeconds = 45.0 AutoReadOnly   ; no reply by then: a plain account instead
float Property LevelSharePerHour = 0.05 AutoReadOnly    ; skill practice per hour, as a share of the next level
float Property CompanionRange = 2500.0 AutoReadOnly      ; followers this close were there too

Actor partner = None
string activity = ""
int hours = 0
bool sceneHandled = false
string startClock = ""

; Magelight page: its view id (0 = message boxes this session) and what it shows ("", "propose", "account").
int uiView = 0
string uiShowing = ""
string lastSummary = ""

; PractiseHours' result for the account: progress through the level before and after (0 to 1), and the
; new level when it rose (else 0).
float lastBefore = 0.0
float lastAfter = 0.0
int lastLevelAfter = 0

; States: "" (idle), "Asking" (the proposal is up), "Spending" (fade, time skip, waiting on the scene).

Event OnInit()
    Reset()
    SetupUI()
EndEvent

; HWS_PlayerAlias.OnPlayerLoadGame. A reload mid-skip never gets its scene: finish plainly.
Function OnGameLoad()
    SetupUI()
    if GetState() == "Asking"
        Reset()
    elseif GetState() == "Spending"
        Game.EnablePlayerControls()
        Game.FadeOutGame(false, true, 0.0, 0.5)
        FinishPlain()
    endif
EndFunction

; Magelight forgets mods, views and listeners between sessions, and mod event registrations last one
; load, so this runs on every load.
Function SetupUI()
    uiView = 0
    uiShowing = ""
    if !UseMagelight || UseMagelight.GetValue() <= 0
        return
    endif
    uiView = HWS_UI.Setup()
    if uiView
        RegisterForModEvent("Magelight_JS_hwsChoice", "OnUiChoice")
        RegisterForModEvent("Magelight_UIModeExited", "OnUiExited")
        RegisterForModEvent("Magelight_ViewLoadFailed", "OnUiFailed")
    endif
EndFunction

bool Function UiReady()
    return uiView != 0 && uiShowing == "" && UseMagelight && UseMagelight.GetValue() > 0
EndFunction

; SpendTimeTogether.yaml. asActivity is the NPC's own words for it. asHours arrives as text (SkyrimNet's
; dynamic parameters are strings); anything that is not a number reads as 0 and gets the default.
Function SpendTimeTogether(Actor akSpeaker, string asActivity, string asHours)
    if !PartnerAlias || !ConfirmMsg || !GameHour
        Debug.Trace("[HWS] HWS_Quest properties are not filled; is HoursWellSpent.esp enabled?", 2)
        return
    endif
    Actor player = Game.GetPlayer()
    if !akSpeaker || akSpeaker == player || akSpeaker.IsDead() || akSpeaker.IsInCombat() || player.IsInCombat()
        return
    endif
    if GetState() != ""
        return
    endif
    if asActivity == ""
        asActivity = "some time together"
    endif
    int h = asHours as int
    if h <= 0
        h = DefaultHours
    elseif h < MinHours
        h = MinHours
    elseif h > MaxHours
        h = MaxHours
    endif

    GoToState("Asking")
    partner = akSpeaker
    activity = asActivity
    hours = h
    PartnerAlias.ForceRefTo(akSpeaker)
    ; The page names who and what; the answer comes back later, through OnUiChoice.
    if UiReady()
        uiShowing = "propose"
        string json = "{\"name\":\"" + JsonEscape(akSpeaker.GetDisplayName()) + "\"" \
            + ",\"activity\":\"" + JsonEscape(asActivity) + "\"" \
            + ",\"hours\":\"" + HoursText(h) + "\"}"
        if HWS_UI.Open(uiView, "hwsPropose", json)
            return
        endif
        uiShowing = ""
    endif
    AskWithBox()
EndFunction

Function AskWithBox()
    ; The box can't carry free text, so the proposal is shown just before it.
    Debug.Notification(partner.GetDisplayName() + ": " + activity + " (" + HoursText(hours) + ")")
    Decide(ConfirmMsg.Show())
EndFunction

; 0 spend the time, 1 not now (the partner hears it), 2 not now, quietly.
Function Decide(int aiChoice)
    if GetState() != "Asking" || !partner
        return
    endif
    if aiChoice != 0
        if aiChoice == 1
            Actor player = Game.GetPlayer()
            SkyrimNetApi.DirectNarration("*" + player.GetDisplayName() + " puts off " + activity + " with " + partner.GetDisplayName() + " for now.*", partner, player)
        endif
        Reset()
        SkyrimNetApi.SetActionCooldown("SpendTimeTogether", CooldownSeconds)
        return
    endif
    StartSpending()
EndFunction

Function StartSpending()
    GoToState("Spending")
    Actor player = Game.GetPlayer()
    Actor akSpeaker = partner
    string asActivity = activity
    int h = hours
    sceneHandled = false
    StorageUtil.SetIntValue(None, "HWS_Active", 1)
    float startHour = GameHour.GetValue()
    string startTime = TimeOfDay(startHour) + ", " + ClockText(startHour)
    startClock = ClockText(startHour)

    ; The hours pass behind black, controls off, as the vanilla wait does.
    Game.DisablePlayerControls()
    Game.FadeOutGame(true, true, 0.0, 1.5)
    Utility.Wait(1.6)
    GameHour.SetValue(GameHour.GetValue() + h)
    Utility.Wait(0.5)
    Game.FadeOutGame(false, true, 0.5, 1.5)
    Game.EnablePlayerControls()

    ; Ask SkyrimNet how it went. The prompt reads bios, memories and the place itself from these ids.
    string ctx = "{\"partnerFormId\":" + akSpeaker.GetFormID() \
        + ",\"partnerName\":\"" + JsonEscape(akSpeaker.GetDisplayName()) + "\"" \
        + ",\"activity\":\"" + JsonEscape(asActivity) + "\"" \
        + ",\"hours\":" + h \
        + ",\"startTime\":\"" + startTime + "\"" \
        + ",\"endTime\":\"" + TimeOfDay(GameHour.GetValue()) + ", " + ClockText(GameHour.GetValue()) + "\"" \
        + ",\"location\":\"" + JsonEscape(PlaceName(player)) + "\"" \
        + ",\"companions\":\"" + JsonEscape(CompanionNames(akSpeaker)) + "\"}"
    int sent = SkyrimNetApi.SendCustomPromptToLLM("hws_scene", "", ctx, self as Quest, "HWS_Main", "OnScene")
    if sent != 1
        Debug.Trace("[HWS] SendCustomPromptToLLM refused (" + sent + "): plain account")
        FinishPlain()
        return
    endif
    RegisterForSingleUpdate(SceneTimeoutSeconds)
EndFunction

; SendCustomPromptToLLM's callback. response is the prompt's JSON: {"summary": "...", "skill": "..."}.
Function OnScene(string response, int success)
    if GetState() != "Spending" || sceneHandled
        return
    endif
    sceneHandled = true
    UnregisterForUpdate()
    string summary = ""
    string skill = ""
    if success == 1
        summary = SkyrimNetApi.GetJsonString(response, "summary", "")
        skill = SkyrimNetApi.GetJsonString(response, "skill", "")
    else
        Debug.Trace("[HWS] scene prompt failed: " + response)
    endif
    if summary == ""
        FinishPlain()
        return
    endif
    Finish(summary, skill)
EndFunction

; Nothing differs while the proposal is up; the state itself is the guard.
State Asking
EndState

State Spending
    ; The scene never came back: tell it plainly rather than leave the hours blank.
    Event OnUpdate()
        if !sceneHandled
            sceneHandled = true
            Debug.Trace("[HWS] scene timed out after " + SceneTimeoutSeconds + " s: plain account")
            FinishPlain()
        endif
    EndEvent
EndState

Function FinishPlain()
    string p = Game.GetPlayer().GetDisplayName()
    string n = "their companion"
    if partner
        n = partner.GetDisplayName()
    endif
    Finish(p + " and " + n + " spent " + HoursText(hours) + " on " + activity + ".", "")
EndFunction

Function Finish(string asSummary, string asSkill)
    Actor player = Game.GetPlayer()
    ; Narrated, so it is remembered by everyone present and the partner responds to it.
    if partner
        SkyrimNetApi.DirectNarration("*" + asSummary + "*", partner, player)
    endif
    int pct = PractiseHours(asSkill, hours)
    if !ShowAccount(asSummary, asSkill, pct)
        Debug.MessageBox(asSummary)
        if pct >= 1
            Debug.Notification("Practised " + SkillName(asSkill) + " (+" + pct + "% of a level)")
        endif
    endif
    SkyrimNetApi.SetActionCooldown("SpendTimeTogether", CooldownSeconds)
    Reset()
EndFunction

; The account on the page, with the skill gained under it. False: use the message box.
bool Function ShowAccount(string asSummary, string asSkill, int aiPct)
    if !UiReady()
        return false
    endif
    string skill = ""
    if aiPct >= 1
        skill = SkillName(asSkill)
    endif
    string name = "your companion"
    if partner
        name = partner.GetDisplayName()
    endif
    string json = "{\"name\":\"" + JsonEscape(name) + "\"" \
        + ",\"hours\":\"" + HoursText(hours) + "\"" \
        + ",\"start\":\"" + startClock + "\"" \
        + ",\"end\":\"" + ClockText(GameHour.GetValue()) + "\"" \
        + ",\"place\":\"" + JsonEscape(PlaceName(Game.GetPlayer())) + "\"" \
        + ",\"summary\":\"" + JsonEscape(asSummary) + "\"" \
        + ",\"skill\":\"" + skill + "\"" \
        + ",\"pct\":" + aiPct \
        + ",\"before\":" + lastBefore \
        + ",\"after\":" + lastAfter \
        + ",\"newLevel\":" + lastLevelAfter + "}"
    lastSummary = asSummary
    uiShowing = "account"
    if HWS_UI.Open(uiView, "hwsAccount", json)
        return true
    endif
    uiShowing = ""
    return false
EndFunction

Function Reset()
    UnregisterForUpdate()
    if PartnerAlias
        PartnerAlias.Clear()
    endif
    StorageUtil.UnsetIntValue(None, "HWS_Active")
    partner = None
    activity = ""
    hours = 0
    startClock = ""
    GoToState("")
EndFunction

; ---------------------------------------------------------------------------------------------
; Magelight page events. Every mod hears every Magelight event, so each checks the view id first.
; Functions, not Events: Caprica refuses new event names on a non-native script, and in a Skyrim .pex an
; event is only a function; SKSE calls the handler by name either way.
; ---------------------------------------------------------------------------------------------

; The page's buttons: "spend", "later", "quiet" on the proposal, "continue" on the account.
Function OnUiChoice(string asEventName, string asChoice, float afView, Form akSender)
    if uiView == 0 || afView as int != uiView
        return
    endif
    string showing = uiShowing
    uiShowing = ""
    HWS_UI.Close(uiView)
    if showing == "propose"
        if asChoice == "spend"
            Decide(0)
        elseif asChoice == "later"
            Decide(1)
        else
            Decide(2)
        endif
    endif
EndFunction

; Escape or the host's toggle key closed the page: a proposal left that way is declined quietly.
; HWS_UI.Close raises this too, after uiShowing is already cleared, so that one is ignored.
Function OnUiExited(string asEventName, string asModId, float afView, Form akSender)
    if uiView == 0 || afView as int != uiView || uiShowing == ""
        return
    endif
    string showing = uiShowing
    uiShowing = ""
    HWS_UI.Close(uiView)
    if showing == "propose"
        Decide(2)
    endif
EndFunction

; The page couldn't load: message boxes for the rest of the session, and whatever was up goes to one now.
Function OnUiFailed(string asEventName, string asDetail, float afView, Form akSender)
    if uiView == 0 || afView as int != uiView
        return
    endif
    Debug.Trace("[HWS] Magelight page failed to load (" + asDetail + "): message boxes this session")
    HWS_UI.Close(uiView)
    uiView = 0
    string showing = uiShowing
    uiShowing = ""
    if showing == "propose" && GetState() == "Asking"
        AskWithBox()
    elseif showing == "account"
        Debug.MessageBox(lastSummary)
    endif
EndFunction

; ---------------------------------------------------------------------------------------------
; Helpers
; ---------------------------------------------------------------------------------------------

; Practice as a share of the skill's next level, so the hours count the same at skill 20 or 80.
; A fixed AdvanceSkill amount was invisible at character level 40 (tested).
; Also the live test: call HWS_Main.PractiseHours on HWS_Quest through DevBench and read the [HWS] line.
; AddSkillExperience takes skill USE, not experience: the engine multiplies it by the skill's use mult
; (One-Handed 6.3, Alchemy 0.75) and by the player's own bonuses (stones, perks, mods). Measured: asking
; for 5% of a One-Handed level gave 35%, 10% of an Alchemy level gave 6.3%. So divide by the use mult,
; let the player's bonuses apply as they would to any practice, and report what was actually gained.
; Returns the gain as a whole percent of a level (0 = none worth telling).
int Function PractiseHours(string asSkill, int aiHours)
    lastBefore = 0.0
    lastAfter = 0.0
    lastLevelAfter = 0
    if !IsSkill(asSkill)
        return 0
    endif
    ActorValueInfo info = ActorValueInfo.GetActorValueInfoByName(asSkill)
    if !info
        return 0
    endif
    float useMult = info.GetSkillUseMult()
    if useMult <= 0.0
        return 0
    endif
    Actor player = Game.GetPlayer()
    int level = player.GetBaseActorValue(asSkill) as int
    float need = info.GetExperienceForLevel(level)
    float before = info.GetSkillExperience()
    float target = need * LevelSharePerHour * aiHours
    info.AddSkillExperience(target / useMult)
    int levelAfter = player.GetBaseActorValue(asSkill) as int
    float after = info.GetSkillExperience()
    ; Gained, counting across level-ups: the rest of the first level, every whole level, then what is in the new one.
    float gained = after - before
    int l = level
    while l < levelAfter
        gained += info.GetExperienceForLevel(l)
        l += 1
    endwhile
    Debug.Trace("[HWS] practise " + asSkill + " " + aiHours + " h: level " + level + " -> " + levelAfter \
        + ", xp " + before + " -> " + after + " of " + need + ", target +" + target + ", gained +" + gained)
    lastBefore = before / need
    lastAfter = after / need
    if levelAfter > level
        lastLevelAfter = levelAfter
        float needNow = info.GetExperienceForLevel(levelAfter)
        if needNow > 0.0
            lastAfter = after / needNow
        endif
    endif
    int pct = ((gained / need) * 100.0 + 0.5) as int
    if pct < 1
        return 0
    endif
    return pct
EndFunction

string Function SkillName(string s)
    if s == "OneHanded"
        return "One-Handed"
    elseif s == "TwoHanded"
        return "Two-Handed"
    elseif s == "Marksman"
        return "Archery"
    elseif s == "HeavyArmor"
        return "Heavy Armor"
    elseif s == "LightArmor"
        return "Light Armor"
    elseif s == "Speechcraft"
        return "Speech"
    endif
    return s
EndFunction

string Function HoursText(int aiHours)
    if aiHours == 1
        return "an hour"
    endif
    return aiHours + " hours"
EndFunction

; The followers who were close enough to have been there, as a comma-separated list.
string Function CompanionNames(Actor akPartner)
    Actor[] followers = PO3_SKSEFunctions.GetPlayerFollowers()
    ; With no followers this is None, not an empty array: test the array itself before .Length.
    if !followers
        return ""
    endif
    Actor player = Game.GetPlayer()
    string out = ""
    int i = 0
    while i < followers.Length
        Actor f = followers[i]
        if f && f != akPartner && !f.IsDead() && f.GetDistance(player) <= CompanionRange
            if out != ""
                out += ", "
            endif
            out += f.GetDisplayName()
        endif
        i += 1
    endwhile
    return out
EndFunction

string Function PlaceName(Actor akPlayer)
    Location loc = akPlayer.GetCurrentLocation()
    if loc && loc.GetName() != ""
        return loc.GetName()
    endif
    Cell c = akPlayer.GetParentCell()
    if c && c.GetName() != ""
        return c.GetName()
    endif
    return "the wilds"
EndFunction

; "2 pm", "11 am", "midnight": the model was given only "afternoon to afternoon" for an hour's work and
; wrote it up as the whole afternoon, so it gets the clock too.
string Function ClockText(float afHour)
    int h = (afHour as int) % 24
    if h == 0
        return "midnight"
    elseif h == 12
        return "noon"
    elseif h < 12
        return h + " am"
    endif
    return (h - 12) + " pm"
EndFunction

string Function TimeOfDay(float afHour)
    float h = afHour
    while h >= 24.0
        h -= 24.0
    endwhile
    if h < 5.0
        return "deep night"
    elseif h < 8.0
        return "early morning"
    elseif h < 12.0
        return "morning"
    elseif h < 14.0
        return "midday"
    elseif h < 18.0
        return "afternoon"
    elseif h < 21.0
        return "evening"
    endif
    return "night"
EndFunction

; Only the prompt's own list may raise a skill, so a stray answer can never call AdvanceSkill badly.
bool Function IsSkill(string s)
    return s == "OneHanded" || s == "TwoHanded" || s == "Marksman" || s == "Block" || s == "Smithing" \
        || s == "HeavyArmor" || s == "LightArmor" || s == "Pickpocket" || s == "Lockpicking" || s == "Sneak" \
        || s == "Alchemy" || s == "Speechcraft" || s == "Alteration" || s == "Conjuration" || s == "Destruction" \
        || s == "Illusion" || s == "Restoration" || s == "Enchanting"
EndFunction

; Text goes into a JSON string, so quotes and backslashes in it must be escaped, and line breaks (the
; model's account can have them) written as \n: a raw one makes the whole string invalid JSON.
string Function JsonEscape(string asText)
    string newline = StringUtil.AsChar(10)
    string cr = StringUtil.AsChar(13)
    string out = ""
    int len = StringUtil.GetLength(asText)
    int i = 0
    while i < len
        string c = StringUtil.GetNthChar(asText, i)
        if c == "\"" || c == "\\"
            out += "\\" + c
        elseif c == newline
            out += "\\n"
        elseif c != cr
            out += c
        endif
        i += 1
    endwhile
    return out
EndFunction
