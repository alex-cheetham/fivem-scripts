# statewide_police - Statewide PD

A full police toolkit for Statewide Roleplay. Standalone (no ESX/QBCore), OneSync.

## Install
1. Upload `statewide_police` to your resources.
2. Update `duty-sync` (it now tells other scripts who's on duty) and `statewide_shops` (seized guns stay seized).
3. server.cfg (after duty-sync, statewide_economy, statewide_items, statewide_shops and statewide_drivingschool):
   ```
   ensure statewide_police
   add_ace group.admin statewide.police.admin allow
   ```
4. In `config.lua`, check `Config.PoliceDepts` matches your police department keys on the staff panel (LSPD, BCSO, SASP...).

## Who can use it
Anyone clocked on with `/onduty` for a police department. Staff with `statewide.police.admin` can always use it.

## Police menu - F7
**Person** (pick someone nearby):
- **Restrain:** handcuff (cuffs prop, paired cuffing animation) or zip-tie, remove, escort, put in / take out of a vehicle.
- **Search:** pat down (weapons only) or full search (needs them restrained or their consent). A full search shows weapons, bag items and cash, and you can seize any of it.
- **Check ID:** photo, licences, warrants, unpaid fines, previous arrests.
- **Tests:**
  - breathalyser (reading in %, legal limit 0.08)
  - drug swab (8 substances)
  - GSR (gunshot residue, 30 minutes)
  - DNA swab (puts their DNA on file)
- **Justice:** write a ticket (penal code, can revoke licences), book into Bolingbroke jail (at a station), community service at Legion Square, release.

**Vehicle:** run plate, search vehicle, dust for fingerprints, impound, take someone out, radar.

**Scene:** spike strips (burst tyres), cones, lit cones, barriers, road closed sign, arrow board, numbered evidence markers, evidence mode, pick up.

**Records & Evidence (MDT):**
- look anyone up, issue and clear warrants, add notes, see fines and arrests
- the shared evidence locker
- lab analysis at a station

Every action has a prop and an animation. Tackle: sprint at someone and press **E**.

## Statewide PD - AI patrol
When there's nobody to police, police the AI. Works on AI people only - real players still use the F7 menu.

**Patrol computer - F10** (or `/patrol`): AI patrol on/off, dispatch, radio (10-8 / 10-6 / 10-23 / Code 4...), units, **Cases**, **Reports & court**, your stats, rank & XP, leaderboard.

**Callouts** (press **Y** to accept), 58 types (see *More calls & dispatch* below): stolen vehicle, drunk driver, reckless driver, shots fired, domestic, fight, shoplifter, intoxicated person, suspicious person, crash, hit and run, armed robbery, wanted person, abandoned vehicle, road rage, trespasser, armed gang, **hostage situation**, robbery in progress, drug deal, missing person, person in crisis, and four **investigations** (burglary, assault, vehicle theft, store robbery). Between callouts you'll witness **on-view incidents**. Close a callout with Code 4 or `/code4`.

**Stops:** **Left Shift** in a police car with lights on pulls over the car in front. **Hold E** to stop someone on foot, **tap E** to talk.

**Interviews:** pick a **Friendly** or **Firm** approach. Watch their **nervousness** and **rapport** - pressure makes guilty people slip up (and run), rapport gets confessions. Questions open follow-ups ("How many exactly?", "Who's the owner?"). Ask "Anything you want to tell me?" or "Be straight with me" to get admissions.

**Lies:** people lie about drinking, drugs, weapons, what's in the car, who owns it, their name - and passengers tell different stories. Evidence catches them out (breath test, swab, search, plate, fingerprints) and you can **confront** them.

**Field sobriety tests:** eye test (HGN), walk and turn, one leg stand - impaired people stumble. Plus breathalyser, drug swab, GSR, DNA, pat down, full search, vehicle search.

**Felony stop:** aim at a stopped car and tap **E** (up to 35m): engine off & keys out, hands out the windows, then each occupant out, walk back, kneel. Backup takes cover behind your car.

**Hostages:** stay back and negotiate (listen, calm, time, family, promise, demand). Rush in and they snap.

**Runners** throw away evidence (bag it with E) and hide when they lose you - search, or use K9 / the air unit.

**Units** (Units tab, or the commands): backup `/callbackup`, **SWAT** `/callswat`, **K9** `/callk9`, **partner** `/callpartner`, prisoner transport `/calltransport`, **roadblock** `/callroadblock`, **spike strips** `/callspikes`, air unit `/callair`, ambulance `/callems`, tow `/calltow`, coroner `/callcoroner`. `/dismissunits` sends them away.
- Backup drives the **2023 SLR sheriff cars** (`2023slrpackallblue` must be started *before* statewide_police - if none of the cars are streamed it falls back to the GTA sheriff cars and prints a warning in F8).
- Units spawn out of sight, drive in code 3, park behind your car with lights on and sirens off, reverse out if stuck (and only teleport when nobody can see), follow you if you drive off, and chase/fight/cover your stops.
- **Pursuits:** backup joins and takes roles - primary (can **PIT**), rolling roadblock from the front, support. **You can PIT** too (hit their back corner at a sensible speed, 20s into the pursuit). Two cars on a slow suspect = **boxed in**. Spike strips and roadblocks are set up on the road *ahead* of the suspect. The supervisor tells you to call it off after 7 minutes - `/terminate` or the Units tab.
- **Partner:** a deputy who rides with you, gets in and out with you, covers your stops and fights with you. Orders in the stop menu (Orders > Partner): watch them, pat down, search, cuff, put in my car, run the plate.
- **K9 division:** your partner is a dog - sniff a vehicle, track a runner, article search (finds thrown-away evidence), bite, heel.
- **Divisions** (Units tab): Patrol, Traffic, Highway, K9, Detectives, SWAT - you get more of your division's callouts.
- **Uniforms (staff):** wear the outfit, open Units > Unit uniforms and press *Save what I'm wearing* for a unit (or "All units"). Save a few (male + female) and they pick at random. Preview spawns one next to you. Saved in `data/uniforms.json`.
- **Real officers:** when you call backup (or accept a shots fired / armed robbery / gang / hostage call) every other on-duty officer gets a popup - **Y** to respond, with a route that follows you.
- **RemoveAICopsEMS:** use the updated version - it now leaves scripted units (and anything a player is in) alone and stops the game's own dispatch instead of wiping every cop in 400m.

**Real places:** callouts go to real locations - armed robberies happen *inside* 24/7s, LTDs and liquor stores (gun on the cashier, getaway car at the kerb, sometimes a getaway driver; they may grab a customer when you arrive), shoplifters walk out of stores, domestics happen on the doorstep of real houses, bar fights at bars, deals in lots and trailer parks. Shops come from statewide_shops, gas stations from statewide_fuel, and **empty houses from statewide_housing** become suspects' addresses. Staff add more places in game: patrol computer > **Places** (stand there, pick a type, save). Map: `Config.AI.CalloutPlaces` in config_ai.lua.

**Wanted people at home / warrants:** go to the front door and press **E** to knock and announce. They might come to the door, run out the back, hide inside, or barricade themselves armed. **E** again to force entry - statewide_housing opens the house for you (update statewide_housing too). Walk-in houses: they're really inside; teleport houses: they're behind the door.

**People:** they **remember you** (repeat offenders come back and recognise you), have **fear and anger** as well as nervousness and rapport, show **body language** you can read ("keeps touching their waistband"), may **reach for something** (you get 2 seconds - aim at them, or let them: it could be a gun or their wallet), may **not speak English** (call the language line from the Talk tab), may have a **child in the car** (arrest the parent and you must call Child & Family Services or a relative), angry **passengers get out and interfere** (Orders > Back off), **bystanders film** your stops, and people can be on **probation, parole or bail** with conditions you can catch them breaking.

**Person in crisis callouts:** talk them down (Talk them down tab), request the **mental health team** (Units), and finish with a voluntary assessment - no force needed. Earns a commendation.

**Conduct (Internal Affairs):** complaints for force on people who weren't a threat, searches without consent or cause, rudeness, wrongful arrests and neglect. Bystander video makes them stick. Write your statement in patrol computer > **Conduct** before IA decide (about 10 minutes). Sustained complaints cost XP; staff can decide complaints themselves. Commendations for good work.

**Investigations (Cases tab):** take statements, examine evidence (blue markers), build a suspect description, issue a **BOLO** (the suspect is somewhere in a search area), or apply for a **warrant** (a judge decides on your evidence) and serve it at their address.

**Reports & court:** every arrest creates an arrest report with the timeline filled in. File it, and a few minutes later court decides **each charge** on your evidence (breath/field tests for DUI, seized drugs, recovered weapons, fleeing...). Convictions earn XP.

**Ranks:** Probationary Officer > Officer > Senior Officer > Corporal > Sergeant > Lieutenant > Captain > Commander.

## More calls & dispatch (Phase 3)
**32 new calls**, each with its own scene:
- **Major incidents / SWAT:** active shooter (gunman still shooting, victims down, people running - SWAT and EMS roll automatically), barricaded armed subject (fires from the house now and then - perimeter and negotiate, rush the door and he shoots), high-risk warrant with SWAT (armed suspect at home, lookouts outside), bank robbery (armed crew at a Fleeca / Blaine County Savings, getaway car with a driver, they may take the teller hostage), **11-99 officer down** (a deputy shot at a stop, suspects using his car for cover).
- **Violent crime:** drive-by (victims at the scene, the car is out there and the passengers shoot back), kidnapping (find the van - the victim is inside and gets out once it's stopped), carjacking, stabbing, man with a gun.
- **In progress:** burglary in progress (crowbar at the back door, sometimes a lookout car), escaped prisoner in orange, large bar fight, arson (burning car and the person who lit it watching), drug lab (chemicals, armed cooks), card fraud at the counter, vandalism / tagging, prowler, restraining order violation, gas drive-off, poacher with a rifle.
- **Traffic:** street racing (two cars), wrong-way driver, unsafe commercial vehicle (log book, load), **pursuit - agency assist** (an LSPD car chasing a stolen car straight at you), pedestrian on the highway, cattle on the road.
- **Community:** welfare check (fine, fallen, or passed away), loud party, dog attack, suspicious package (move people back, wait for the bomb squad), body found.

**Real dispatch:** every call gets a CAD **incident number** (SW261009-0042), a **nature code** (211 PC, 23152 VC, 5150 WIC...) and a **priority** (P1-P3). Dispatch sends **caller updates** over the radio while you drive ("Callers say the shooter has a rifle..."), and the units the call needs (SWAT, EMS, air) roll automatically when you arrive.

**CAD board** (patrol computer > CAD board): every call in the county - pending, en route, on scene, closed - with the other units (2-LINCOLN-7, BCSO 3S21...) picking up what nobody takes. **Self-assign** any pending call. Calls you decline go back on the board.

**Time, weather and area:** calls fit the moment. Bar fights, DUIs, burglaries, loud parties and prowlers at night; shoplifting and bank jobs in the day; crashes in the rain; drive-bys and gang calls in Los Santos; drug labs, poachers and cattle on the road in Blaine County. Each call's `night` / `day` / `rain` / `city` / `county` multipliers are in `config_calls.lua`.

**Divisions** get the new calls too (SWAT gets the major incidents, Traffic/Highway the road calls, Detectives bodies, fraud, arson and kidnappings).

**wk_wars2x (Wraith ARS 2X):** start `wk_wars2x` and the plate reader is checked against the records - stolen cars, wanted owners, no insurance / expired registration and BOLO plates from your cases. A hit **locks the camera with the BOLO tone**, flashes the car on your map and tells you why. Locking a plate yourself **runs it** (10-28) automatically. Settings: `Config.AI.ALPR` in `config_calls.lua`.

**New charges** in the penal code: carjacking, arson, shooting from a vehicle, escape from custody, manufacturing, restraining order violation, street racing, wrong way, fraud, poaching... and court weighs your evidence for each one.

**Staff:** `/aicallout [type]` forces a callout (e.g. `/aicallout active_shooter`). Everything (keys, ranks, XP, court timing, callouts, people's lines, investigations) is in `config_ai.lua`; the Phase 3 calls, dispatch, weighting and wk_wars2x settings are in `config_calls.lua`.

**Saved:** `data/patrol.json` (officer stats, XP & division), `data/uniforms.json` (unit uniforms), `data/known.json` (people remembered between sessions), `data/ia.json` (complaints & commendations), `data/ai_places.json` (places staff added). AI people live in `data/records.json` with everyone else.

## Readings are real
- **Drinks:** drinks from the Job Bag (beer, wine, spirits, cocktails) really raise your alcohol level. Above the limit you stagger, and it wears off over about 40 minutes.
- **Roleplay:** anyone can add roleplay drinks or drugs with `/rpstatus drink [amount]`, `/rpstatus cocaine [minutes]` or `/rpstatus clear`.
- **Gunshot residue:** firing a gun leaves GSR on your hands (wash it off at water with `/washhands`, or swim).
- **Scene evidence:** firing drops a casing. Getting hurt leaves blood. Driving leaves fingerprints on the car.

## Evidence
Evidence mode (torch in hand) shows casings and blood within 30m. Press E to bag them. At a station lab (MDT → Evidence locker):
- **Casings:** show the weapon type, and whether it matches a legally owned gun (and whose).
- **Blood and prints:** match a name once that person's DNA / prints are on file. Booking someone takes both; a DNA swab takes DNA.

## Civilian commands
`/showid` · `/fines` (see & pay) · `/rpstatus` · `/washhands` · `/jailtime`

## Police commands (all also in the F7 menu)
`/cuff /zip /uncuff /escort /seat /unseat /frisk /search /checkid /breath /drugtest /gsr /dna /ticket /arrest /comserv /unjail <id> /runplate [plate] /vehsearch /impound /radar /spikes /evidence /mdt /badge`. Add a player ID to target someone specific, e.g. `/cuff 12`. Radar lock: **Numpad 5**.

Rebind: F7 menu, E tackle, quick-cuff / quick-escort (unbound by default), radar lock - Settings > Key Bindings > FiveM.

## Staff commands
| Command | What it does |
|---|---|
| `/policeaddstation <label>` | Add a booking desk + evidence lab where you stand (Mission Row, Vespucci, Sandy, Paleto and Bolingbroke are there already) |
| `/policeremovestation` | Remove the nearest station |
| `/policeaddchore` · `/policeaddcomserv` · `/policeaddjailspawn` | Add prison chore / community service / jail spawn points |
| `/policesetrelease` | Prison release point |
| `/policeclearpoints <chores\|comserv\|jailspawns>` | Remove all of that type |
| `/policeclearprops` | Remove every cone / barrier / spike on the map |
| `/policeresetpoints` | Back to config.lua |

## Props
All vanilla GTA models. The breathalyser uses `prop_inhaler_01`. Any "Alcolizer / breathalyser" mod that replaces that prop will show a proper breathalyser. You can swap any prop in `Config.Props`.

## Saved data
`data/` keeps records (fines, arrests, warrants, notes), jail sentences (they carry on after a restart / relog), plates and the evidence locker. Don't overwrite it when updating.
