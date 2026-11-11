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
 set HWS_UseMagelight to 0. Turning it back on takes effect at the next proposal.}

Spell Property PlanPower Auto
{HWS_PlanPower, the "Plan the Hours" lesser power. Handed to the player on every load (GivePower).}

; Must equal the version in both manifest.json files; build.sh refuses to build otherwise.
string Property ModVersion = "0.3.0" AutoReadOnly

; Tuning.
int Property MinHours = 1 AutoReadOnly
int Property MaxHours = 8 AutoReadOnly
int Property DefaultHours = 2 AutoReadOnly
int Property CooldownSeconds = 90 AutoReadOnly           ; before SpendTimeTogether is offered again
float Property SceneTimeoutSeconds = 45.0 AutoReadOnly   ; no reply by then: a plain account instead
float Property LevelSharePerHour = 0.05 AutoReadOnly    ; skill practice per hour, as a share of the next level
float Property CompanionRange = 2500.0 AutoReadOnly      ; followers this close were there too

; The session being proposed or spent. Both ways in fill it the same way: an NPC's proposal
; (SpendTimeTogether: one person, origin "npc") and the planner (ReadPlan: zero or more, origin "plan").
; partner is the first person (who answers the account), or None for hours spent alone.
Actor partner = None
string activity = ""
int hours = 0
Actor[] sessionWho
int sessionWhoCount = 0
string sessionFocus = ""     ; a skill the player chose (IsSkill's names), or "" to let the account decide
string sessionOrigin = ""    ; "npc" or "plan"
bool sceneHandled = false
string startClock = ""
float sentAt = 0.0     ; real seconds when the scene prompt went out (development log only)

; Magelight page: its view id (0 = message boxes this session) and what it shows ("", "propose", "account").
int uiView = 0
bool uiFailed = false     ; the page failed to load this session: message boxes, no retry
string uiShowing = ""
string lastSummary = ""

; PractiseHours' result for the account: progress through the level before and after (0 to 1), and the
; new level when it rose (else 0).
float lastBefore = 0.0
float lastAfter = 0.0
int lastLevelAfter = 0

; The planner. candidates holds who the page offered, in the page's order; the page answers with
; positions in it, so it can never name someone Papyrus didn't offer. candidateCount of them are set.
Actor[] candidates
int candidateCount = 0

; The last plan the player confirmed: the session configuration the planner returns. ReadPlan checks it,
; copies it into the session and spends it (StartSpending), as a proposal is spent.
string planActivity = ""
int planHours = 0
Actor[] planWho          ; planWhoCount of them are set; none = the player alone
int planWhoCount = 0
string planFocus = ""    ; one of IsSkill's names, or "" to let the account decide

; States: "" (idle), "Asking" (the proposal is up), "Planning" (the planner is up), "Spending" (fade,
; time skip, waiting on the scene).

Event OnInit()
    HWS_Diag.StartSession("==== OnInit (new game or first install), HWS " + ModVersion)
    Reset()
    SetupUI()
    GivePower()
EndEvent

; HWS_PlayerAlias.OnPlayerLoadGame. A reload mid-skip never gets its scene: finish plainly.
Function OnGameLoad()
    HWS_Diag.StartSession("==== game loaded, HWS " + ModVersion + ", state '" + GetState() + "'")
    SetupUI()
    GivePower()
    if GetState() == "Asking" || GetState() == "Planning"
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
    uiFailed = false
    if !UseMagelight || UseMagelight.GetValue() <= 0
        HWS_Diag.Log("SetupUI: skipped, " + UiDetail())
        return
    endif
    uiView = HWS_UI.Setup()
    if uiView
        RegisterForModEvent("Magelight_JS_hwsChoice", "OnUiChoice")
        RegisterForModEvent("Magelight_JS_hwsPlan", "OnUiPlan")
        RegisterForModEvent("Magelight_UIModeExited", "OnUiExited")
        RegisterForModEvent("Magelight_ViewLoadFailed", "OnUiFailed")
    endif
    HWS_Diag.Log("SetupUI: done, " + UiDetail())
EndFunction

bool Function UiReady()
    return uiView != 0 && uiShowing == "" && UseMagelight && UseMagelight.GetValue() > 0
EndFunction

; Diagnostic build: every input UiReady() reads.
string Function UiDetail()
    string use = "property NOT FILLED"
    if UseMagelight
        use = "" + UseMagelight.GetValue()
    endif
    return "uiView " + uiView + ", uiShowing '" + uiShowing + "', HWS_UseMagelight " + use + ", UiReady " + UiReady()
EndFunction

; SpendTimeTogether.yaml. asActivity is the NPC's own words for it. asHours arrives as text (SkyrimNet's
; dynamic parameters are strings); anything that is not a number reads as 0 and gets the default.
Function SpendTimeTogether(Actor akSpeaker, string asActivity, string asHours)
    HWS_Diag.Log("SpendTimeTogether: speaker " + akSpeaker + ", activity '" + asActivity + "', hours '" + asHours \
        + "', state '" + GetState() + "'")
    if !PartnerAlias || !ConfirmMsg || !GameHour
        Debug.Trace("[HWS] HWS_Quest properties are not filled; is HoursWellSpent.esp enabled?", 2)
        HWS_Diag.Log("SpendTimeTogether: quit, quest properties not filled")
        return
    endif
    Actor player = Game.GetPlayer()
    if !akSpeaker || akSpeaker == player || akSpeaker.IsDead() || akSpeaker.IsInCombat() || player.IsInCombat()
        HWS_Diag.Log("SpendTimeTogether: quit, speaker missing/player/dead or someone in combat")
        return
    endif
    if GetState() != ""
        HWS_Diag.Log("SpendTimeTogether: quit, already busy in state '" + GetState() + "'")
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
    sessionWho = new Actor[12]
    sessionWho[0] = akSpeaker
    sessionWhoCount = 1
    sessionFocus = ""
    sessionOrigin = "npc"
    PartnerAlias.ForceRefTo(akSpeaker)
    ; No page yet this session (Magelight wasn't ready at load, or HWS_UseMagelight was turned back on):
    ; try again. RegisterMod is idempotent, so this is safe to repeat.
    if uiView == 0 && !uiFailed && UseMagelight && UseMagelight.GetValue() > 0
        HWS_Diag.Log("proposal: no page yet, setting up again")
        SetupUI()
        if uiView == 0 && HWS_UI.Installed()
            Debug.Trace("[HWS] no Magelight page (reason in the [HWS] line above, if any): message box")
        endif
    endif
    ; The page names who and what; the answer comes back later, through OnUiChoice.
    HWS_Diag.Log("proposal: " + UiDetail())
    if UiReady()
        uiShowing = "propose"
        ; The page can switch to the planner, prefilled with this proposal ("Change the plan"), without a
        ; round trip, so it gets the planner's data now: who could join (the proposer first, locked in),
        ; the hours as a number, and the place. A changed plan comes back through OnUiPlan.
        GatherCandidates(akSpeaker)
        string json = "{\"name\":\"" + JsonEscape(akSpeaker.GetDisplayName()) + "\"" \
            + ",\"activity\":\"" + JsonEscape(asActivity) + "\"" \
            + ",\"hours\":\"" + HoursText(h) + "\"" \
            + ",\"plan\":" + PlannerJson(h, Game.GetPlayer()) + "}"
        if HWS_UI.Open(uiView, "hwsPropose", json)
            return
        endif
        uiShowing = ""
    endif
    AskWithBox()
EndFunction

Function AskWithBox()
    HWS_Diag.Log("proposal: MESSAGE BOX, " + UiDetail())
    ; The box can't carry free text, so the proposal is shown just before it.
    Debug.Notification(partner.GetDisplayName() + ": " + activity + " (" + HoursText(hours) + ")")
    Decide(ConfirmMsg.Show())
EndFunction

; 0 spend the time, 1 not now (the partner hears it), 2 not now, quietly.
Function Decide(int aiChoice)
    HWS_Diag.Log("decide: choice " + aiChoice + " (0 spend, 1 later, 2 quiet), state '" + GetState() + "', partner " + partner)
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
    HWS_Diag.Log("skip: GameHour " + startHour + " -> " + GameHour.GetValue() + " (+" + h + " h), activity '" + asActivity + "'")
    Utility.Wait(0.5)
    Game.FadeOutGame(false, true, 0.5, 1.5)
    Game.EnablePlayerControls()

    ; Ask SkyrimNet how it went. The prompt reads bios, memories and the place itself from these ids.
    ; participantIds lists everyone who took part (none when alone); partnerFormId/partnerName are the
    ; first of them, as before. companions: followers who happened to be close, for a proposal only; a
    ; plan names exactly who was there.
    string ids = ""
    int i = 0
    while i < sessionWhoCount
        if i > 0
            ids += ","
        endif
        ids += sessionWho[i].GetFormID()
        i += 1
    endwhile
    int partnerId = 0
    string partnerName = ""
    if akSpeaker
        partnerId = akSpeaker.GetFormID()
        partnerName = akSpeaker.GetDisplayName()
    endif
    string companions = ""
    if sessionOrigin == "npc"
        companions = CompanionNames(akSpeaker)
    endif
    string focusName = ""
    if sessionFocus != ""
        focusName = SkillName(sessionFocus)
    endif
    ; 1 or 0, never true/false. A Papyrus bool prints as "True", and even a literal "false" can come back
    ; as "False" (the string pool keeps another script's casing): invalid JSON, so SkyrimNet dropped the
    ; whole context and the model invented the hours (0.3.0-diag2, measured). Numbers have no casing.
    int solo = 0
    if sessionWhoCount == 0
        solo = 1
    endif
    string ctx = "{\"partnerFormId\":" + partnerId \
        + ",\"partnerName\":\"" + JsonEscape(partnerName) + "\"" \
        + ",\"participantIds\":[" + ids + "]" \
        + ",\"participantNames\":\"" + JsonEscape(Names(sessionWho, sessionWhoCount)) + "\"" \
        + ",\"solo\":" + solo \
        + ",\"activity\":\"" + JsonEscape(asActivity) + "\"" \
        + ",\"hours\":" + h \
        + ",\"startTime\":\"" + startTime + "\"" \
        + ",\"endTime\":\"" + TimeOfDay(GameHour.GetValue()) + ", " + ClockText(GameHour.GetValue()) + "\"" \
        + ",\"location\":\"" + JsonEscape(PlaceName(player)) + "\"" \
        + ",\"companions\":\"" + JsonEscape(companions) + "\"" \
        + ",\"focus\":\"" + sessionFocus + "\",\"focusName\":\"" + focusName + "\",\"hws_check\":1}"
    ; Read our own marker back: if it doesn't come back, the context isn't valid JSON, SkyrimNet will
    ; render the prompt without it, and the model will invent the hours. Say so where it can be found.
    if SkyrimNetApi.GetJsonInt(ctx, "hws_check", 0) != 1
        Debug.Trace("[HWS] scene context is not valid JSON; the account will be invented: " + ctx, 1)
        HWS_Diag.Log("scene: CONTEXT IS NOT VALID JSON")
    endif
    sentAt = Utility.GetCurrentRealTime()
    int sent = SkyrimNetApi.SendCustomPromptToLLM("hws_scene", "", ctx, self as Quest, "HWS_Main", "OnScene")
    HWS_Diag.Log("scene: sent hws_scene, result " + sent + ", context " + ctx)
    if sent != 1
        Debug.Trace("[HWS] SendCustomPromptToLLM refused (" + sent + "): plain account")
        FinishPlain()
        return
    endif
    RegisterForSingleUpdate(SceneTimeoutSeconds)
EndFunction

; The reply from its first "{" to its last "}". Models sometimes wrap the JSON in a ```json fence or a
; sentence, and GetJsonString then finds nothing (2026-11-11: a full account lost to a fence).
string Function JsonBody(string asText)
    int first = StringUtil.Find(asText, "{")
    if first < 0
        return asText
    endif
    int last = -1
    int at = StringUtil.Find(asText, "}", first)
    while at >= 0
        last = at
        at = StringUtil.Find(asText, "}", at + 1)
    endwhile
    if last < 0
        return asText
    endif
    if first > 0 || last < StringUtil.GetLength(asText) - 1
        HWS_Diag.Log("scene: reply had text around the JSON, trimmed to it")
    endif
    return StringUtil.Substring(asText, first, last - first + 1)
EndFunction

; SendCustomPromptToLLM's callback. response is the prompt's JSON: {"hws_summary": "...", "hws_skill": "..."}.
Function OnScene(string response, int success)
    HWS_Diag.Log("scene: reply after " + (Utility.GetCurrentRealTime() - sentAt) + " s, success " + success \
        + ", state '" + GetState() + "', already handled " + sceneHandled + ", response " + response)
    if GetState() != "Spending" || sceneHandled
        return
    endif
    sceneHandled = true
    UnregisterForUpdate()
    string summary = ""
    string skill = ""
    if success == 1
        response = JsonBody(response)
        ; hws_ keys, not "summary"/"skill": a key is a Papyrus string, and a common word can come back
        ; with another script's casing ("Summary"), which the JSON lookup would then miss.
        summary = SkyrimNetApi.GetJsonString(response, "hws_summary", "")
        skill = SkyrimNetApi.GetJsonString(response, "hws_skill", "")
    else
        Debug.Trace("[HWS] scene prompt failed: " + response)
    endif
    if summary == ""
        FinishPlain()
        return
    endif
    Finish(summary, skill)
EndFunction

; Nothing differs while the proposal or the planner is up; the state itself is the guard.
State Asking
EndState

State Planning
EndState

State Spending
    ; The scene never came back: tell it plainly rather than leave the hours blank.
    Event OnUpdate()
        if !sceneHandled
            sceneHandled = true
            Debug.Trace("[HWS] scene timed out after " + SceneTimeoutSeconds + " s: plain account")
            HWS_Diag.Log("scene: TIMED OUT after " + SceneTimeoutSeconds + " s -> plain account")
            FinishPlain()
        endif
    EndEvent
EndState

Function FinishPlain()
    HWS_Diag.Log("finish: PLAIN account")
    string p = Game.GetPlayer().GetDisplayName()
    if sessionWhoCount > 0
        p += " and " + Names(sessionWho, sessionWhoCount)
    endif
    Finish(p + " spent " + HoursText(hours) + " on " + activity + ".", "")
EndFunction

Function Finish(string asSummary, string asSkill)
    Actor player = Game.GetPlayer()
    ; With company: narrated, so everyone present remembers it and the partner responds. Alone: a
    ; persistent event, remembered without some bystander being picked to react to hours they missed.
    if partner
        SkyrimNetApi.DirectNarration("*" + asSummary + "*", partner, player)
    else
        SkyrimNetApi.RegisterPersistentEvent("*" + asSummary + "*", None, player)
    endif
    ; A focus the player chose is what the hours practised, whatever the account named.
    if sessionFocus != ""
        asSkill = sessionFocus
    endif
    int pct = PractiseHours(asSkill, hours)
    HWS_Diag.Log("finish: skill '" + asSkill + "', +" + pct + "% of a level (" + lastBefore + " -> " + lastAfter \
        + ", new level " + lastLevelAfter + "), summary " + StringUtil.GetLength(asSummary) + " chars")
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
    HWS_Diag.Log("account: " + UiDetail())
    if !UiReady()
        HWS_Diag.Log("account: MESSAGE BOX")
        return false
    endif
    string skill = ""
    if aiPct >= 1
        skill = SkillName(asSkill)
    endif
    ; name: everyone who took part ("" when alone; the page then says so).
    string json = "{\"name\":\"" + JsonEscape(Names(sessionWho, sessionWhoCount)) + "\"" \
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
    sessionWho = None
    sessionWhoCount = 0
    sessionFocus = ""
    sessionOrigin = ""
    candidates = None
    candidateCount = 0
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
    HWS_Diag.Log("event hwsChoice '" + asChoice + "' from view " + afView + ", " + UiDetail())
    if uiView == 0 || afView as int != uiView
        return
    endif
    string showing = uiShowing
    uiShowing = ""
    HWS_UI.Close(uiView)
    if showing == "plan"
        ; The planner's only hwsChoice is "cancel"; a confirmed plan comes through OnUiPlan.
        CancelPlan("cancelled on the page")
    elseif showing == "propose"
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
    HWS_Diag.Log("event UIModeExited mod '" + asModId + "' view " + afView + ", " + UiDetail())
    if uiView == 0 || afView as int != uiView || uiShowing == ""
        return
    endif
    string showing = uiShowing
    uiShowing = ""
    HWS_UI.Close(uiView)
    if showing == "propose"
        Decide(2)
    elseif showing == "plan"
        CancelPlan("page closed (Escape or the host's key)")
    endif
EndFunction

; The planner's "Plan it": asPlan is the session configuration as JSON (see ReadPlan). From the power
; (uiShowing "plan") or from a proposal the player changed (uiShowing "propose").
Function OnUiPlan(string asEventName, string asPlan, float afView, Form akSender)
    HWS_Diag.Log("event hwsPlan from view " + afView + ": " + asPlan + " | " + UiDetail())
    if uiView == 0 || afView as int != uiView || (uiShowing != "plan" && uiShowing != "propose")
        return
    endif
    bool fromProposal = uiShowing == "propose"
    uiShowing = ""
    HWS_UI.Close(uiView)
    if fromProposal && (GetState() != "Asking" || !partner)
        HWS_Diag.Log("plan: from a proposal no longer open, ignored")
        return
    endif
    ReadPlan(asPlan, fromProposal)
EndFunction

; The page couldn't load: message boxes for the rest of the session, and whatever was up goes to one now.
Function OnUiFailed(string asEventName, string asDetail, float afView, Form akSender)
    HWS_Diag.Log("event ViewLoadFailed '" + asDetail + "' view " + afView + ", " + UiDetail())
    if uiView == 0 || afView as int != uiView
        return
    endif
    Debug.Trace("[HWS] Magelight page failed to load (" + asDetail + "): message boxes this session")
    HWS_UI.Close(uiView)
    uiView = 0
    uiFailed = true
    string showing = uiShowing
    uiShowing = ""
    if showing == "propose" && GetState() == "Asking"
        AskWithBox()
    elseif showing == "account"
        Debug.MessageBox(lastSummary)
    elseif showing == "plan"
        CancelPlan("page failed to load")
        Debug.Notification("The planner page didn't load; see the Papyrus log.")
    endif
EndFunction

; ---------------------------------------------------------------------------------------------
; The planner: the Plan the Hours power opens a page for What, How long, Who and an optional Focus
; skill. A confirmed plan is checked (ReadPlan) and spent the same way an NPC's proposal is.
; ---------------------------------------------------------------------------------------------

; Every load, so existing saves get the power too. AddSpell(.., false): no "spell learned" message.
Function GivePower()
    Actor player = Game.GetPlayer()
    if PlanPower && !player.HasSpell(PlanPower)
        player.AddSpell(PlanPower, false)
        HWS_Diag.Log("power: given")
    endif
EndFunction

; HWS_PlanEffect, when the power is cast.
Function OpenPlanner()
    HWS_Diag.Log("planner: power cast, state '" + GetState() + "', " + UiDetail())
    if GetState() != ""
        Debug.Notification("Some hours are already being spent.")
        return
    endif
    Actor player = Game.GetPlayer()
    if player.IsInCombat()
        Debug.Notification("Not in the middle of a fight.")
        return
    endif
    if !UseMagelight || UseMagelight.GetValue() <= 0
        Debug.Notification("Planning the hours needs the Magelight page (HWS_UseMagelight is 0).")
        return
    endif
    if uiView == 0 && !uiFailed
        SetupUI()
    endif
    if !UiReady()
        Debug.Notification("Planning the hours needs Magelight UI 1.3.0 or newer.")
        if HWS_UI.Installed()
            Debug.Trace("[HWS] planner: no Magelight page (reason in the [HWS] line above, if any)")
        endif
        return
    endif
    GoToState("Planning")
    GatherCandidates(None)
    string json = PlannerJson(DefaultHours, player)
    HWS_Diag.Log("planner: offering " + candidateCount + " candidate(s): " + json)
    uiShowing = "plan"
    if !HWS_UI.Open(uiView, "hwsPlanner", json)
        uiShowing = ""
        CancelPlan("another mod holds the screen")
        Debug.Notification("Another menu has the screen; try again in a moment.")
    endif
EndFunction

; The planner page's data: {who: [{name, tag}], hours, minHours, maxHours, place}, from candidates.
; tag: "follower", or "proposed" for a proposer at position 0 (the page locks that one in).
string Function PlannerJson(int aiHours, Actor akPlayer)
    ; lockFirst 1: position 0 is the proposer, picked and locked. A number, not a tag the page compares:
    ; a word like "proposed" can come back as "Proposed" (the string pool's casing).
    int lockFirst = 0
    if candidateCount > 0 && candidates[0] == partner && GetState() == "Asking"
        lockFirst = 1
    endif
    string who = ""
    int i = 0
    while i < candidateCount
        if who != ""
            who += ","
        endif
        string tag = ""
        if i == 0 && lockFirst == 1
            tag = "proposed this"
        elseif IsFollower(candidates[i])
            tag = "follower"
        endif
        who += "{\"name\":\"" + JsonEscape(candidates[i].GetDisplayName()) + "\",\"tag\":\"" + tag + "\"}"
        i += 1
    endwhile
    return "{\"who\":[" + who + "],\"lockFirst\":" + lockFirst + ",\"hours\":" + aiHours + ",\"minHours\":" + MinHours \
        + ",\"maxHours\":" + MaxHours + ",\"place\":\"" + JsonEscape(PlaceName(akPlayer)) + "\"}"
EndFunction

; akFirst (a proposer) at position 0 if given; then followers within CompanionRange; then the closest
; other living, non-hostile people in range, up to 12 in all. Creatures only if they follow you (a dog,
; a familiar).
Function GatherCandidates(Actor akFirst)
    candidates = new Actor[12]
    float[] dist = new float[12]
    candidateCount = 0
    Actor player = Game.GetPlayer()
    if akFirst
        candidates[0] = akFirst
        dist[0] = -2.0
        candidateCount = 1
    endif
    Actor[] followers = PO3_SKSEFunctions.GetPlayerFollowers()
    ; With no followers this is None, not an empty array.
    if followers
        int i = 0
        while i < followers.Length && candidateCount < 12
            Actor f = followers[i]
            if Offerable(f, player) && f.GetDistance(player) <= CompanionRange && candidates.Find(f) < 0
                candidates[candidateCount] = f
                dist[candidateCount] = -1.0     ; followers stay first, whatever the distance
                candidateCount += 1
            endif
            i += 1
        endwhile
    endif
    Keyword npcKw = Keyword.GetKeyword("ActorTypeNPC")
    Actor[] near = PO3_SKSEFunctions.GetActorsByProcessingLevel(0)
    if !near
        return
    endif
    int firstOther = candidateCount
    int j = 0
    while j < near.Length
        Actor a = near[j]
        if Offerable(a, player) && (!npcKw || a.HasKeyword(npcKw)) && candidates.Find(a) < 0
            float d = a.GetDistance(player)
            if d <= CompanionRange
                ; Insert by distance among the non-followers; past 12, the farthest falls off the end.
                int at = candidateCount
                while at > firstOther && dist[at - 1] > d
                    at -= 1
                endwhile
                if at < 12
                    int k = candidateCount
                    if k > 11
                        k = 11
                    endif
                    while k > at
                        candidates[k] = candidates[k - 1]
                        dist[k] = dist[k - 1]
                        k -= 1
                    endwhile
                    candidates[at] = a
                    dist[at] = d
                    if candidateCount < 12
                        candidateCount += 1
                    endif
                endif
            endif
        endif
        j += 1
    endwhile
EndFunction

bool Function Offerable(Actor a, Actor akPlayer)
    return a && a != akPlayer && !a.IsDead() && !a.IsDisabled() && !a.IsInCombat() && !a.IsHostileToActor(akPlayer) \
        && a.GetDisplayName() != ""
EndFunction

bool Function IsFollower(Actor a)
    Actor[] followers = PO3_SKSEFunctions.GetPlayerFollowers()
    return followers && followers.Find(a) >= 0
EndFunction

; The page's plan: {"hws_activity": text, "hws_hours": 1-8, "hws_who": "0,3" (positions in candidates,
; may be empty), "hws_focus": a skill name or ""}. Keys carry hws_ so no other script's casing of a
; common word ("Hours") can break the lookup. Everything is checked here, not trusted to the page.
; abProposal: the player changed an NPC's proposal. The proposer (partner) stays in, first, whatever the
; page sent, and a failure declines the proposal quietly instead of cancelling a plan.
Function ReadPlan(string asPlan, bool abProposal = false)
    string act = SkyrimNetApi.GetJsonString(asPlan, "hws_activity", "")
    int h = SkyrimNetApi.GetJsonInt(asPlan, "hws_hours", DefaultHours)
    string who = SkyrimNetApi.GetJsonString(asPlan, "hws_who", "")
    string focus = SkyrimNetApi.GetJsonString(asPlan, "hws_focus", "")
    if act == "" && abProposal
        act = activity
    endif
    if act == ""
        PlanFailed("no activity given", abProposal)
        return
    endif
    if h < MinHours
        h = MinHours
    elseif h > MaxHours
        h = MaxHours
    endif
    if focus != "" && !IsSkill(focus)
        HWS_Diag.Log("plan: unknown focus '" + focus + "' dropped")
        focus = ""
    endif
    planWho = new Actor[12]
    planWhoCount = 0
    if abProposal
        planWho[0] = partner
        planWhoCount = 1
    endif
    if who != ""
        string[] picks = StringUtil.Split(who, ",")
        int i = 0
        while i < picks.Length
            int n = picks[i] as int
            if n >= 0 && n < candidateCount && candidates[n] && !candidates[n].IsDead() && planWho.Find(candidates[n]) < 0
                planWho[planWhoCount] = candidates[n]
                planWhoCount += 1
            elseif abProposal && n == 0
                ; The proposer, already first.
            else
                HWS_Diag.Log("plan: pick '" + picks[i] + "' dropped (out of range, gone or repeated)")
            endif
            i += 1
        endwhile
    endif
    planActivity = act
    planHours = h
    planFocus = focus
    HWS_Diag.Log("plan: CONFIRMED " + PlanJson())
    candidates = None
    candidateCount = 0
    if !PartnerAlias || !GameHour
        Debug.Trace("[HWS] HWS_Quest properties are not filled; is HoursWellSpent.esp enabled?", 2)
        PlanFailed("quest properties not filled", abProposal)
        return
    endif
    if Game.GetPlayer().IsInCombat()
        Debug.Notification("Not in the middle of a fight.")
        PlanFailed("player in combat at confirm", abProposal)
        return
    endif
    ; The plan becomes the session, the same one an NPC's proposal fills, and is spent the same way.
    ; A changed proposal names exactly who comes, like a plan, so it adds no stray followers either.
    activity = planActivity
    hours = planHours
    sessionWho = planWho
    sessionWhoCount = planWhoCount
    sessionFocus = planFocus
    if abProposal
        sessionOrigin = "npc-changed"
    else
        sessionOrigin = "plan"
    endif
    partner = None
    if sessionWhoCount > 0
        partner = sessionWho[0]
        PartnerAlias.ForceRefTo(partner)
    endif
    StartSpending()
EndFunction

Function PlanFailed(string asWhy, bool abProposal)
    if abProposal
        HWS_Diag.Log("plan: changed proposal failed, " + asWhy + " -> declined quietly")
        Decide(2)
    else
        CancelPlan(asWhy)
    endif
EndFunction

Function CancelPlan(string asWhy)
    HWS_Diag.Log("plan: cancelled, " + asWhy)
    candidates = None
    candidateCount = 0
    GoToState("")
EndFunction

; The last confirmed plan as JSON, for the log and for DevBench (call HWS_Main PlanJson on HWS_Quest).
string Function PlanJson()
    string ids = ""
    int i = 0
    while i < planWhoCount
        if ids != ""
            ids += ","
        endif
        ids += "{\"name\":\"" + JsonEscape(planWho[i].GetDisplayName()) + "\",\"formId\":" + planWho[i].GetFormID() + "}"
        i += 1
    endwhile
    return "{\"activity\":\"" + JsonEscape(planActivity) + "\",\"hours\":" + planHours + ",\"who\":[" + ids \
        + "],\"focus\":\"" + planFocus + "\"}"
EndFunction

; "Ria", "Ria and Serana", "Ria, Serana and Vilkas"; "" for nobody.
string Function Names(Actor[] akWho, int aiCount)
    string out = ""
    int i = 0
    while i < aiCount
        if i > 0
            if i == aiCount - 1
                out += " and "
            else
                out += ", "
            endif
        endif
        out += akWho[i].GetDisplayName()
        i += 1
    endwhile
    return out
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
