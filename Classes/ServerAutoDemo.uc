// Records a server demo of every match: starts when the match starts (after
// warmup and countdown), stops 2 seconds after the match ends, or as soon as a
// map change starts mid-match (a map vote). Next to each demo it writes
// <demo>.json with the match info (server, map, times, scores).
// Load it as a ServerActor or as a mutator. Settings are in ServerAutoDemo.ini,
// section [Settings] (ServerAutoDemoSettings).
class ServerAutoDemo extends Mutator;

var ServerAutoDemoSettings Settings;

var bool bStarted;
var bool bStopped;
var float GameEndedTime;
var string DemoFile;   // as passed to demorec, without .dem
var string StartDate;
var float StartTime;

// Everyone who played since the match started, so players who left stay on the
// scoreboard with their last score. Refreshed once a second.
struct PlayerEntry {
	var string Name;
	var int ID, Team, Score, Deaths, Ping;
	var byte bBot, bGone;
};
var PlayerEntry Entries[64]; // ponytail: players past 64 in one match are not listed
var int NumEntries;
var float NextPlayerUpdate;

event PostBeginPlay() {
	// Outer object named after the ini, inner object named Settings: section [Settings].
	Settings = new(new(none, 'ServerAutoDemo') class'Object', 'Settings') class'ServerAutoDemoSettings';
	Settings.SaveConfig(); // writes ServerAutoDemo.ini with the defaults on first run
	if (Level.NetMode != NM_DedicatedServer && Level.NetMode != NM_ListenServer)
		Disable('Tick');
}

function bool MatchStarted() {
	local DeathMatchPlus DMP;

	DMP = DeathMatchPlus(Level.Game);
	if (DMP == none)
		return true;
	// bNetReady: waiting for players. bRequireReady with CountDown: warmup or countdown.
	return !DMP.bNetReady && !(DMP.bRequireReady && DMP.CountDown > 0);
}

event Tick(float Delta) {
	local string Result;

	if (bStopped)
		return;

	if (!bStarted) {
		if (Level.Game.bGameEnded || Level.NextURL != "" || !MatchStarted())
			return;
		bStarted = true;
		DemoFile = CreateDemoName();
		StartDate = Now();
		StartTime = Level.TimeSeconds;
		Result = ConsoleCommand("demorec" @ DemoFile);
		Log(Result, 'ServerAutoDemo');
		return;
	}

	if (Level.TimeSeconds >= NextPlayerUpdate) {
		UpdatePlayers();
		NextPlayerUpdate = Level.TimeSeconds + 1.0;
	}

	// A map vote or admin map change sets NextURL and switches about half a second
	// later. Save the scores so far and stop the demo before the level goes away.
	if (Level.NextURL != "") {
		bStopped = true;
		WriteMatchInfo();
		ConsoleCommand("stopdemo");
		Log("Demo recording stopped for a map change (match ended:" @ B(Level.Game.bGameEnded) $ ")", 'ServerAutoDemo');
		return;
	}

	if (Level.Game.bGameEnded) {
		if (GameEndedTime == 0)
			GameEndedTime = Level.TimeSeconds;
		else if (Level.TimeSeconds >= GameEndedTime + 2.0) {
			bStopped = true;
			WriteMatchInfo();
			ConsoleCommand("stopdemo");
			Log("Demo recording stopped", 'ServerAutoDemo');
		}
	}
}

function string Now() {
	return Level.Year $ "-" $ Pad2(Level.Month) $ "-" $ Pad2(Level.Day) $ " "
		$ Pad2(Level.Hour) $ ":" $ Pad2(Level.Minute) $ ":" $ Pad2(Level.Second);
}

function string B(bool b) {
	if (b)
		return "true";
	return "false";
}

// JSON string with quotes. Drops control characters.
function string J(string S) {
	local int i;
	local string C, Result;

	for (i = 0; i < Len(S); i++) {
		C = Mid(S, i, 1);
		if (C == "\\" || C == "\"")
			Result = Result $ "\\" $ C;
		else if (Asc(C) >= 32)
			Result = Result $ C;
	}
	return "\"" $ Result $ "\"";
}

// Players still on the server get their current values. Those who left keep the
// values from the last update before they left.
function UpdatePlayers() {
	local PlayerReplicationInfo PRI;
	local int i;

	for (i = 0; i < NumEntries; i++)
		Entries[i].bGone = 1;
	foreach AllActors(class'PlayerReplicationInfo', PRI) {
		if (PRI.bIsSpectator || PRI.PlayerName == "")
			continue;
		for (i = 0; i < NumEntries; i++)
			if (Entries[i].ID == PRI.PlayerID)
				break;
		if (i == NumEntries) {
			if (NumEntries == ArrayCount(Entries))
				continue;
			NumEntries++;
			Entries[i].ID = PRI.PlayerID;
		}
		Entries[i].Name = PRI.PlayerName;
		Entries[i].Team = PRI.Team;
		Entries[i].Score = int(PRI.Score);
		Entries[i].Deaths = int(PRI.Deaths);
		Entries[i].Ping = PRI.Ping;
		Entries[i].bBot = byte(PRI.bIsABot);
		Entries[i].bGone = 0;
	}
}

// One JSON player per name. A player who left and came back has two entries
// (the game starts them at 0 again): their scores and deaths add up, team and ping
// come from the entry still on the server (else the last one). "left" is true
// when none of them is still on the server.
function string PlayersJson() {
	local int i, j, Last, Score, Deaths;
	local bool bLeft;
	local string S, Sep;

	for (i = 0; i < NumEntries; i++) {
		for (j = 0; j < i; j++)
			if (Entries[j].Name == Entries[i].Name)
				break;
		if (j < i)
			continue; // added with the first entry of this name
		Score = 0;
		Deaths = 0;
		Last = i;
		bLeft = true;
		for (j = i; j < NumEntries; j++) {
			if (Entries[j].Name != Entries[i].Name)
				continue;
			Score += Entries[j].Score;
			Deaths += Entries[j].Deaths;
			if (Entries[j].bGone == 0) {
				bLeft = false;
				Last = j;
			} else if (bLeft) {
				Last = j;
			}
		}
		S = S $ Sep $ "{\"name\":" $ J(Entries[i].Name) $ ",\"team\":" $ Entries[Last].Team
			$ ",\"score\":" $ Score $ ",\"deaths\":" $ Deaths
			$ ",\"ping\":" $ Entries[Last].Ping $ ",\"bot\":" $ B(Entries[Last].bBot == 1)
			$ ",\"left\":" $ B(bLeft) $ "}";
		Sep = ",";
	}
	return S;
}

// Writes <demo>.json next to the demo: the match as the scoreboard shows it at the end.
function WriteMatchInfo() {
	local StatLogFile F;
	local GameReplicationInfo GRI;
	local TeamGamePlus TGP;
	local DeathMatchPlus DMP;
	local string S, Sep;
	local int i;

	GRI = Level.Game.GameReplicationInfo;
	DMP = DeathMatchPlus(Level.Game);
	TGP = TeamGamePlus(Level.Game);

	S = "{\"demo\":" $ J(Mid(DemoFile, Len(Settings.DemoPath)) $ ".dem");
	S = S $ ",\"server\":" $ J(GRI.ServerName);
	S = S $ ",\"map\":" $ J(Left(string(Level), InStr(string(Level), ".")));
	S = S $ ",\"title\":" $ J(Level.Title);
	S = S $ ",\"game\":" $ J(Level.Game.GameName);
	S = S $ ",\"gameclass\":" $ J(string(Level.Game.Class));
	S = S $ ",\"start\":" $ J(StartDate);
	S = S $ ",\"end\":" $ J(Now());
	S = S $ ",\"seconds\":" $ int((Level.TimeSeconds - StartTime) / Level.TimeDilation);
	S = S $ ",\"ended\":" $ B(Level.Game.bGameEnded); // false: a map change cut the match off
	if (DMP != none)
		S = S $ ",\"timelimit\":" $ DMP.TimeLimit $ ",\"fraglimit\":" $ DMP.FragLimit;
	if (TGP != none) {
		S = S $ ",\"goalteamscore\":" $ int(TGP.GoalTeamScore) $ ",\"teams\":[";
		for (i = 0; i < TGP.MaxTeams && i < 4; i++) {
			if (TGP.Teams[i] == none)
				continue;
			S = S $ Sep $ "{\"team\":" $ i $ ",\"name\":" $ J(TGP.Teams[i].TeamName) $ ",\"score\":" $ int(TGP.Teams[i].Score) $ "}";
			Sep = ",";
		}
		S = S $ "]";
	}
	UpdatePlayers();
	S = S $ ",\"players\":[" $ PlayersJson() $ "]}";

	F = Spawn(class'StatLogFile');
	F.Encoding = FILE_ENCODING_UTF8;
	F.StatLogFile = DemoFile $ ".json.tmp";
	F.StatLogFinal = DemoFile $ ".json";
	F.OpenLog();
	F.FileLog(S);
	F.CloseLog();
	F.Destroy();
}

function string CreateDemoName() {
	local string Mask, S, Result;
	local int i;

	Mask = Settings.DemoMask;
	if (Mask == "")
		Mask = class'ServerAutoDemoSettings'.default.DemoMask;

	while (true) {
		i = InStr(Mask, "%");
		if (i < 0)
			break;

		S = Mid(Mask, i + 1, 1);
		switch (Caps(S)) {
			case "E":
				S = string(Level);
				S = Left(S, InStr(S, "."));
				break;
			case "F":
				S = Level.Title;
				break;
			case "D":
				S = Pad2(Level.Day);
				break;
			case "M":
				S = Pad2(Level.Month);
				break;
			case "Y":
				S = string(Level.Year);
				break;
			case "H":
				S = Pad2(Level.Hour);
				break;
			case "N":
				S = Pad2(Level.Minute);
				break;
			case "S":
				S = Pad2(Level.Second);
				break;
			case "T":
				S = Pad2(Level.Hour) $ Pad2(Level.Minute);
				break;
			case "C":
				S = FindClanTags();
				break;
			case "%":
				break;
			default:
				S = "%" $ S;
				break;
		}
		Result = Result $ Left(Mask, i) $ S;
		Mask = Mid(Mask, i + 2);
	}

	return Settings.DemoPath $ FixFileName(Result $ Mask);
}

function string Pad2(int Val) {
	if (Val < 10)
		return "0" $ Val;
	return string(Val);
}

function string FixFileName(string S) {
	local int i;
	local string C, Result;

	for (i = 0; i < Len(S); i++) {
		C = Mid(S, i, 1);
		if (Asc(C) < 32 || Asc(C) > 127 || Asc(C) == 34 || InStr("|.:%\\/*?<>()`'& ", C) >= 0)
			C = Settings.DemoChar;
		Result = Result $ C;
	}
	return Result;
}

// Same as IG+ client demos: the common start or end of the player names in
// each team, "Mix" if there is none, "FFA" outside team games.
function string FindClanTags() {
	local PlayerReplicationInfo PRI;
	local string Prefix[4], Suffix[4], Tags[4];
	local int TeamSize[4];
	local int Teams, Team, MixCount;
	local string Result;

	if (!Level.Game.GameReplicationInfo.bTeamGame)
		return "FFA";

	foreach AllActors(class'PlayerReplicationInfo', PRI) {
		if (PRI.bIsSpectator || PRI.bIsABot || PRI.Team > 3)
			continue;
		if (TeamSize[PRI.Team] == 0) {
			Prefix[PRI.Team] = PRI.PlayerName;
			Suffix[PRI.Team] = PRI.PlayerName;
		} else {
			Prefix[PRI.Team] = CommonPrefix(Prefix[PRI.Team], PRI.PlayerName);
			Suffix[PRI.Team] = CommonSuffix(Suffix[PRI.Team], PRI.PlayerName);
		}
		++TeamSize[PRI.Team];
	}

	for (Teams = 0; Teams < 4; ++Teams)
		if (TeamSize[Teams] == 0)
			break;

	for (Team = 0; Team < Teams; ++Team) {
		if (Prefix[Team] == Suffix[Team])
			Tags[Team] = Prefix[Team];
		else
			Tags[Team] = Prefix[Team] $ Suffix[Team];
		if (Tags[Team] == "") {
			Tags[Team] = "Mix";
			++MixCount;
		}
	}

	if (Teams <= 1 || MixCount > 1)
		return "Unknown";

	Result = Tags[0];
	for (Team = 1; Team < Teams; ++Team)
		Result = Result $ "_" $ Tags[Team];
	return Result;
}

function string CommonPrefix(string A, string B) {
	local int i, Length;

	Length = Min(Len(A), Len(B));
	for (i = 0; i < Length; ++i)
		if (Mid(A, i, 1) != Mid(B, i, 1))
			break;
	return Left(A, i);
}

function string CommonSuffix(string A, string B) {
	local int i, Length;

	Length = Min(Len(A), Len(B));
	for (i = 0; i < Length; ++i)
		if (Mid(A, Len(A) - i - 1, 1) != Mid(B, Len(B) - i - 1, 1))
			break;
	return Right(A, i);
}

defaultproperties {
	RemoteRole=ROLE_None
	// Tick while the game is paused too: VoteSys still votes and changes the map then.
	bAlwaysTick=True
}
