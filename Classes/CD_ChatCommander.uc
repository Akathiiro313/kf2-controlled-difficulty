class CD_ChatCommander extends Object
	within CD_Survival
	DependsOn(CD_Survival);

`include(CD_BuildInfo.uci)
`include(CD_Log.uci)

struct StructChatCommand
{
	var array<string> Names; 
	var array<string> ParamHints; 
	var delegate<ChatCommandNullaryImpl> NullaryImpl;
	var delegate<ChatCommandParamsImpl> ParamsImpl;
	var string Description;
	var CDAuthLevel AuthLevel;
	var bool ModifiesConfig;
};

var array<StructChatCommand> ChatCommands;

delegate string ChatCommandNullaryImpl();
delegate string ChatCommandParamsImpl( const out array<string> params );

function PrintCDChatHelp()
{
	local string HelpString;
	local int CCIndex, NameIndex, ParamIndex;

	GameInfo_CDCP.Print("Controlled Difficulty Chat Commands", false);
	GameInfo_CDCP.Print("----------------------------------------------------", false);
	GameInfo_CDCP.Print("CD knows the following chat commands.  Type any command in global chat.", false);
	GameInfo_CDCP.Print("Commands typed in team chat are ignored.  Commands marked CDAUTH_READ ", false);
	GameInfo_CDCP.Print("are usable by anyone.  Dedicated server admins may optionally restrict ", false);
	GameInfo_CDCP.Print("access to commands marked CDAUTH_WRITE.", false);

	for ( CCIndex = 0; CCIndex < ChatCommands.Length; CCIndex++ )
	{
		HelpString = "  " $ ChatCommands[CCIndex].Names[0];

		for ( ParamIndex = 0; ParamIndex < ChatCommands[CCIndex].ParamHints.Length; ParamIndex++ )
		{
			HelpString $= " <" $ ChatCommands[CCIndex].ParamHints[ParamIndex] $ ">";
		}

		if ( 1 < ChatCommands[CCIndex].Names.Length )
		{
			HelpString $= " (alternate name(s): ";

			for ( NameIndex = 1; NameIndex < ChatCommands[CCIndex].Names.Length; NameIndex++ )
			{
				if ( 1 < NameIndex )
				{
					HelpString $= ", ";
				}
				HelpString $= ChatCommands[CCIndex].Names[NameIndex];
			}

			HelpString $= ")";
		}

		HelpString $= " [" $ ChatCommands[CCIndex].AuthLevel $ "]";

		GameInfo_CDCP.Print(HelpString, false);
		GameInfo_CDCP.Print("    " $ ChatCommands[CCIndex].Description, false);
	}
}

function RunCDChatCommandIfAuthorized( Actor Sender, string CommandString )
{
	local CDAuthLevel AuthLevel;
	local string ResponseMessage;
	local array<string> CommandTokens;
	local name GameStateName;
	local StructChatCommand Cmd;

	local bool SkipStagedConfigApplication;

	local delegate<ChatCommandNullaryImpl> CNDeleg;
	local delegate<ChatCommandParamsImpl> CPDeleg;

	SkipStagedConfigApplication = false;

	// First, see if this chat message looks even remotely like a CD command
	if ( 3 > Len( CommandString ) || !( Left( CommandString, 3 ) ~= "!cd" ) )
	{
		return;
	}

	AuthLevel = GetAuthorizationLevelForUser( Sender );

	// Chat commands are case-insensitive.  Lowercase the command now
	// so that we can do safely do string comparisons with lowercase
	// operands below.
	CommandString = Locs( CommandString );

	// Split the chat command on spaces, dropping empty parts.
	ParseStringIntoArray( CommandString, CommandTokens, " ", true );

	ResponseMessage = "";

	`cdlog("CommandTokens.Length: "$ CommandTokens.Length);

	if ( MatchChatCommand( CommandTokens[0], Cmd, AuthLevel, CommandTokens.Length - 1 ) )
	{
		`cdlog("Invoking chat command via table match");
		CNDeleg = Cmd.NullaryImpl;
		CPDeleg = Cmd.ParamsImpl;
		if ( Cmd.ParamHints.Length == 0 )
		{
			`cdlog("Invoking nullary chat command: "$ CommandString, bLogControlledDifficulty);
			ResponseMessage = CNDeleg();
		}
		else
		{
			`cdlog("Invoking chat command with parameters: "$ CommandString, bLogControlledDifficulty);
			CommandTokens.Remove( 0, 1 );
			ResponseMessage = CPDeleg( CommandTokens );
		}

		if ( Cmd.ModifiesConfig )
		{
			// Check whether we're allowed to modify settings right now.
			// If so, change settings immediately and let ApplyStagedSettings()
			// format an appropriate notification message.
			GameStateName = GetStateName();
			if ( !SkipStagedConfigApplication && ( GameStateName == 'PendingMatch' || GameStateName == 'MatchEnded' || GameStateName == 'TraderOpen' ) )
			{
				ApplyStagedConfig( ResponseMessage, "" );
			}
		}
	}
	else
	{
		`cdlog("Discarding unknown or unauthorized command: "$ CommandString, bLogControlledDifficulty);
	}

	// An authorized command match was found; the command may or may not
	// have succeeded, but something was executed and a chat reply should
	// be sent to all connected clients
	if ( "" != ResponseMessage )
	{
		DirectBroadcast(None, ResponseMessage, 'CDEcho');
		return;
	}
}

private function bool MatchChatCommand( const string CmdName, out StructChatCommand Cmd, const CDAuthLevel AuthLevel, const int ParamCount )
{
	local int CCIndex;
	local int NameIndex;

	for ( CCIndex = 0; CCIndex < ChatCommands.length; CCIndex++ )
	{
		if ( AuthLevel < ChatCommands[CCIndex].AuthLevel )
		{
			continue;
		}

		if ( ParamCount != ChatCommands[CCIndex].ParamHints.Length )
		{
			continue;
		}

		for ( NameIndex = 0; NameIndex < ChatCommands[CCIndex].Names.Length; NameIndex++ )
		{
			if ( ChatCommands[CCIndex].Names[NameIndex] == CmdName )
			{
				Cmd = ChatCommands[CCIndex];
				return true;
				`cdlog("MatchChatCommand["$ CCIndex $"]: found Name="$ CmdName $" ParamCount="$ ParamCount $" AuthLevel="$ AuthLevel, bLogControlledDifficulty);
			}
		}
	}

	return false;
}


private function SetupSimpleReadCommand( out StructChatCommand scc, const string CmdName, const string Desc, const delegate<ChatCommandNullaryImpl> Impl )
{
	local array<string> n;
	local array<string> empty;

	empty.length = 0;
	n.Length = 1;
	n[0] = CmdName;

	scc.Names = n;
	scc.ParamHints = empty;
	scc.NullaryImpl = Impl;
	scc.ParamsImpl = None;
	scc.Description = Desc;
	scc.AuthLevel = CDAUTH_READ;
	scc.ModifiesConfig = false;

	ChatCommands.AddItem( scc );
}

private function SetupSimpleWriteCommand( out StructChatCommand scc, const string CmdName, const string Desc, const string Hint, const delegate<ChatCommandParamsImpl> Impl )
{
	local array<string> n;
	local array<string> hints;

	n.Length = 1;
	n[0] = CmdName;

	hints.Length = 1;
	hints[0] = Hint;

	scc.Names = n;
	scc.ParamHints = hints;
	scc.NullaryImpl = None;
	scc.ParamsImpl = Impl;
	scc.Description = Desc;
	scc.AuthLevel = CDAUTH_WRITE;
	scc.ModifiesConfig = true;

	ChatCommands.AddItem( scc );
}

function SetupChatCommands()
{
	local array<string> n;
	local array<string> h;
	local StructChatCommand scc;

	ChatCommands.Length = 0;

	// Setup pause commands
	n.Length = 2;
	h.Length = 0;
	n[0] = "!cdpausetrader";
	n[1] = "!cdpt";
	scc.Names = n;
	scc.ParamHints = h;
	scc.NullaryImpl = PauseTraderTime;
	scc.ParamsImpl = None;
	scc.Description = "Pause TraderTime countdown";
	scc.AuthLevel = CDAUTH_WRITE;
	scc.ModifiesConfig = false;
	ChatCommands.AddItem( scc );

	n.Length = 2;
	h.Length = 0;
	n[0] = "!cdunpausetrader";
	n[1] = "!cdupt";
	scc.Names = n;
	scc.ParamHints = h;
	scc.NullaryImpl = UnpauseTraderTime;
	scc.ParamsImpl = None;
	scc.Description = "Unpause TraderTime countdown";
	scc.AuthLevel = CDAUTH_WRITE;
	scc.ModifiesConfig = false;
	ChatCommands.AddItem( scc );

	// Setup info commands
	n.Length = 1;
	h.Length = 0;
	n[0] = "!cdinfo";
	scc.Names = n;
	scc.ParamHints = h;
	scc.NullaryImpl = GetCDInfoChatStringDefault;
	scc.ParamsImpl = None;
	scc.Description = "Display CD config summary";
	scc.AuthLevel = CDAUTH_READ;
	scc.ModifiesConfig = false;
	ChatCommands.AddItem( scc );

	n.Length = 1;
	h.Length = 1;
	n[0] = "!cdinfo";
	h[0] = "full|abbrev";
	scc.Names = n;
	scc.ParamHints = h;
	scc.NullaryImpl = None;
	scc.ParamsImpl = GetCDInfoChatStringCommand;
	scc.Description = "Display full CD config";
	scc.AuthLevel = CDAUTH_READ;
	scc.ModifiesConfig = false;
	ChatCommands.AddItem( scc );

	SetupSimpleReadCommand( scc, "!cdalbinoalphas", "Display AlbinoAlphas setting", GetAlbinoAlphasChatString );
	SetupSimpleReadCommand( scc, "!cdalbinocrawlers", "Display AlbinoCrawlers setting", GetAlbinoCrawlersChatString );
	SetupSimpleReadCommand( scc, "!cdalbinogorefasts", "Display AlbinoGorefasts setting", GetAlbinoGorefastsChatString );
	SetupSimpleReadCommand( scc, "!cdboss", "Display Boss override", GetBossChatString );
	SetupSimpleReadCommand( scc, "!cdcohortsize", "Display spawning cohort size in zeds", GetCohortSizeChatString );
	SetupSimpleReadCommand( scc, "!cdhelp", "Information about CD's chat commands", GetCDChatHelpReferralString );
	SetupSimpleReadCommand( scc, "!cdfakeplayers", "Display FakePlayers count", GetFakePlayersChatString );
//	SetupSimpleReadCommand( scc, "!cdinfo", "Display a summary of CD settings", GetCDInfoChatStringDefault );
	SetupSimpleReadCommand( scc, "!cdmaxmonsters", "Display MaxMonsters count", GetMaxMonstersChatString );
	SetupSimpleReadCommand( scc, "!cdminspawninterval", "Display MinSpawnInterval value", GetMinSpawnIntervalChatString );
	SetupSimpleReadCommand( scc, "!cdspawncycle", "Display SpawnCycle name", GetSpawnCycleChatString );
	SetupSimpleReadCommand( scc, "!cdspawnmod", "Display SpawnMod value", GetSpawnModChatString );
	SetupSimpleReadCommand( scc, "!cdtradertime", "Display TraderTime in seconds", GetTraderTimeChatString );
	SetupSimpleReadCommand( scc, "!cdversion", "Display mod version", GetCDVersionChatString );
	SetupSimpleReadCommand( scc, "!cdweapontimeout", "Display WeaponTimeout in seconds", GetWeaponTimeoutChatString );
	SetupSimpleReadCommand( scc, "!cdzedsteleportcloser", "Display ZedsTeleportCloser setting", GetZedsTeleportCloserChatString );
	SetupSimpleReadCommand( scc, "!cdztspawnslowdown", "Display ZTSpawnSlowdown value", GetZTSpawnSlowdownChatString );
	SetupSimpleReadCommand( scc, "!cdztspawnmode", "Display ZTSpawnMode", GetZTSpawnModeChatString );

	SetupSimpleWriteCommand( scc, "!cdalbinoalphas", "Set AlbinoAlphas", "true|false", SetAlbinoAlphasChatCommand );
	SetupSimpleWriteCommand( scc, "!cdalbinocrawlers", "Set AlbinoCrawlers", "true|false", SetAlbinoCrawlersChatCommand );
	SetupSimpleWriteCommand( scc, "!cdalbinogorefasts", "Set AlbinoGorefasts", "true|false", SetAlbinoGorefastsChatCommand );
	SetupSimpleWriteCommand( scc, "!cdboss", "Choose which boss spawns on the final wave", "volter|patriarch|unmodded", SetBossChatCommand );
	SetupSimpleWriteCommand( scc, "!cdcohortsize", "Set CohortSize", "int", SetCohortSizeChatCommand );
	SetupSimpleWriteCommand( scc, "!cdfakeplayers", "Set FakePlayers", "int|ini|bilinear:...", SetFakePlayersChatCommand );
	SetupSimpleWriteCommand( scc, "!cdmaxmonsters", "Set MaxMonsters", "int", SetMaxMonstersChatCommand );
	SetupSimpleWriteCommand( scc, "!cdminspawninterval", "Set MinSpawnInterval", "float", SetMinSpawnIntervalChatCommand );
	SetupSimpleWriteCommand( scc, "!cdspawncycle", "Set SpawnCycle", "name_of_spawncycle|unmodded", SetSpawnCycleChatCommand );
	SetupSimpleWriteCommand( scc, "!cdspawnmod", "Set SpawnMod", "float", SetSpawnModChatCommand );
	SetupSimpleWriteCommand( scc, "!cdweapontimeout", "Set WeaponTimeout", "int|max", SetWeaponTimeoutChatCommand );
	SetupSimpleWriteCommand( scc, "!cdzedsteleportcloser", "Set ZedsTeleportCloser", "true|false", SetZedsTeleportCloserChatCommand );
	SetupSimpleWriteCommand( scc, "!cdztspawnslowdown", "Set ZTSpawnSlowdown", "float", SetZTSpawnSlowdownChatCommand );
	SetupSimpleWriteCommand( scc, "!cdztspawnmode", "Set ZTSpawnMode", "unmodded|clockwork", SetZTSpawnModeChatCommand );
}

private function string SetZedsTeleportCloserChatCommand( const out array<string> params )
{
	StagedConfig.ZedsTeleportCloser = bool( params[0] );

	if ( ZedsTeleportCloser != StagedConfig.ZedsTeleportCloser )
	{
		return "Staged: ZedsTeleportCloser=" $ StagedConfig.ZedsTeleportCloser $
			"\nEffective after current wave"; 
	}
	else
	{
		return "ZedsTeleportCloser is already " $ ZedsTeleportCloser;
	}
}

private function string SetAlbinoAlphasChatCommand( const out array<string> params )
{
	StagedConfig.AlbinoAlphas = bool( params[0] );

	if ( AlbinoAlphas != StagedConfig.AlbinoAlphas )
	{
		return "Staged: AlbinoAlphas=" $ StagedConfig.AlbinoAlphas $
			"\nEffective after current wave"; 
	}
	else
	{
		return "AlbinoAlphas is already " $ AlbinoAlphas;
	}
}

private function string SetAlbinoCrawlersChatCommand( const out array<string> params )
{
	StagedConfig.AlbinoCrawlers = bool( params[0] );

	if ( AlbinoCrawlers != StagedConfig.AlbinoCrawlers )
	{
		return "Staged: AlbinoCrawlers=" $ StagedConfig.AlbinoCrawlers $
			"\nEffective after current wave"; 
	}
	else
	{
		return "AlbinoCrawlers is already " $ AlbinoCrawlers;
	}
}

private function string SetAlbinoGorefastsChatCommand( const out array<string> params )
{
	StagedConfig.AlbinoGorefasts = bool( params[0] );

	if ( AlbinoGorefasts != StagedConfig.AlbinoGorefasts )
	{
		return "Staged: AlbinoGorefasts=" $ StagedConfig.AlbinoGorefasts $
			"\nEffective after current wave"; 
	}
	else
	{
		return "AlbinoGorefasts is already " $ AlbinoGorefasts;
	}
}

private function string SetCohortSizeChatCommand( const out array<string> params )
{
	local int TempInt;

	TempInt = int( params[0] );
	TempInt = ClampCohortSize( TempInt );
	StagedConfig.CohortSize = TempInt;
	if ( CohortSize != StagedConfig.CohortSize )
	{
		return "Staged: CohortSize=" $ StagedConfig.CohortSize $
			"\nEffective after current wave"; 
	}
	else
	{
		return "CohortSize is already " $ CohortSize;
	}
}

private function string SetZTSpawnModeChatCommand( const out array<string> params )
{
	local string TempString;

	TempString = Locs( params[0] );

	if ( TempString == ZTSpawnMode )
	{
		return "ZTSpawnMode is already " $ ZTSpawnMode;
	}

	else if ( IsValidZTSpawnModeString( TempString ) )
	{
		StagedConfig.ZTSpawnMode = TempString;
		return "Staged: ZTSpawnMode=" $ StagedConfig.ZTSpawnMode $
			"\nEffective after current wave"; 
	}
	else
	{
		return "Not a valid ZTSpawnMode string\n" $
			"Try unmodded or clockwork"; 
	}
}


private function string SetBossChatCommand( const out array<string> params )
{
	local string TempString;

	TempString = Locs( params[0] );

	if ( TempString == Boss )
	{
		return "Boss is already " $ Boss;
	}
	// I could check for pointless changes here
	// (e.g. "unmodded" -> "random", equivalent but different strings)
	// but it is hard to describe the associated subtlety in a chat response
	else if ( IsValidBossString( TempString ) )
	{
		StagedConfig.Boss = TempString;
		return "Staged: Boss=" $ StagedConfig.Boss $
			"\nEffective after current wave"; 
	}
	else
	{
		return "Not a valid boss string\n" $
			"Try hans, pat, or unmodded"; 
	}
}

private function string SetFakePlayersChatCommand( const out array<string> params )
{
	StagedConfig.FakePlayers = params[0];

	if ( FakePlayers != StagedConfig.FakePlayers )
	{
		return "Staged: FakePlayers=" $ StagedConfig.FakePlayers $
			"\nEffective after current wave"; 
	}
	else
	{
		return "FakePlayers is already " $ FakePlayers;
	}
}

private function string SetWeaponTimeoutChatCommand( const out array<string> params )
{
	StagedConfig.WeaponTimeout = ClampWeaponTimeout( params[0] );

	if ( WeaponTimeout != StagedConfig.WeaponTimeout )
	{
		return "Staged: WeaponTimeout=" $ GetWeaponTimeoutStringForArg( StagedConfig.WeaponTimeout ) $
			"\nEffective after current wave"; 
	}
	else
	{
		return "WeaponTimeout is already " $ WeaponTimeout;
	}
}

private function string SetMaxMonstersChatCommand( const out array<string> params )
{
	local int TempInt;

	TempInt = int( params[0] );
	if ( TempInt < 0 )
	{
		TempInt = 0;
	} 
	StagedConfig.MaxMonsters = TempInt;

	if ( MaxMonsters != StagedConfig.MaxMonsters )
	{
		return "Staged: MaxMonsters=" $ GetMaxMonstersStringForArg( StagedConfig.MaxMonsters ) $
			"\nEffective after current wave"; 
	}
	else
	{
		return "MaxMonsters is already " $ MaxMonsters;
	}
}

private function string SetMinSpawnIntervalChatCommand( const out array<string> params )
{
	local float TempFloat;

	TempFloat = float( params[0] );
	TempFloat = ClampMinSpawnInterval( TempFloat );
	StagedConfig.MinSpawnIntervalFloat = TempFloat;
	if ( !EpsilonClose( MinSpawnIntervalFloat, StagedConfig.MinSpawnIntervalFloat, MinSpawnIntervalEpsilon ) )
	{
		return "Staged: MinSpawnInterval=" $ StagedConfig.MinSpawnIntervalFloat $
			"\nEffective after current wave"; 
	}
	else
	{
		return "MinSpawnInterval is already " $ MinSpawnInterval;
	}
}


private function string SetSpawnCycleChatCommand( const out array<string> params )
{
	StagedConfig.SpawnCycle = params[0];
	if ( SpawnCycle != StagedConfig.SpawnCycle )
	{
		return "Staged: SpawnCycle=" $ StagedConfig.SpawnCycle $
			"\nEffective after current wave"; 
	}
	else
	{
		return "SpawnCycle is already " $ SpawnCycle;
	}
}

private function string SetSpawnModChatCommand( const out array<string> params )
{
	local float TempFloat;

	TempFloat = float( params[0] );
	TempFloat = ClampSpawnMod( TempFloat );
	StagedConfig.SpawnModFloat = TempFloat;
	if ( !EpsilonClose( SpawnModFloat, StagedConfig.SpawnModFloat, SpawnModEpsilon ) )
	{
		return "Staged: SpawnMod=" $ StagedConfig.SpawnModFloat $
			"\nEffective after current wave"; 
	}
	else
	{
		return "SpawnMod is already " $ SpawnMod;
	}
}

private function string SetZTSpawnSlowdownChatCommand( const out array<string> params )
{
	local float TempFloat;

	TempFloat = float( params[0] );
	TempFloat = ClampZTSpawnSlowdown( TempFloat );
	StagedConfig.ZTSpawnSlowdownFloat = TempFloat;
	if ( !EpsilonClose( ZTSpawnSlowdownFloat, StagedConfig.ZTSpawnSlowdownFloat, ZTSpawnSlowdownEpsilon ) )
	{
		return "Staged: ZTSpawnSlowdown=" $ StagedConfig.ZTSpawnSlowdownFloat $
			"\nEffective after current wave"; 
	}
	else
	{
		return "ZTSpawnSlowdown is already " $ ZTSpawnSlowdown;
	}
}


private function string GetCDChatHelpReferralString() {
	return "Type CDChatHelp in console for chat command info";
}

private function string GetCDInfoChatStringDefault()
{
	return GetCDInfoChatString( "brief" );
}

private function string GetCDInfoChatStringCommand( const out array<string> params)
{
	return GetCDInfoChatString( params[0] );
}

function string GetCDInfoChatString( const string Verbosity )
{
	if ( Verbosity == "full" )
	{
		return GetAlbinoAlphasChatString() $ "\n" $
		       GetAlbinoCrawlersChatString() $ "\n" $
		       GetAlbinoGorefastsChatString() $ "\n" $
		       GetBossChatString() $ "\n" $
		       GetCohortSizeChatString() $ "\n" $
		       GetFakePlayersChatString() $ "\n" $
		       GetMaxMonstersChatString() $ "\n" $
		       GetMinSpawnIntervalChatString() $ "\n" $
		       GetSpawnCycleChatString() $ "\n" $
		       GetSpawnModChatString() $ "\n" $
		       GetTraderTimeChatString() $ "\n" $
		       GetWeaponTimeoutChatString() $ "\n" $
		       GetZTSpawnSlowdownChatString() $ "\n" $
		       GetZTSpawnModeChatString();
	}
	else
	{
		return GetFakePlayersChatString() $ "\n" $
		       GetMaxMonstersChatString() $ "\n" $
		       GetSpawnModChatString() $ "\n" $
		       GetCohortSizeChatString() $ "\n" $
		       GetSpawnCycleChatString();
	}
}

private function string GetZedsTeleportCloserChatString()
{
	local string ZedsTeleportCloserLatchedString;

	if ( StagedConfig.ZedsTeleportCloser != ZedsTeleportCloser )
	{
		ZedsTeleportCloserLatchedString = " (staged: " $ StagedConfig.ZedsTeleportCloser $ ")";
	}

	return "ZedsTeleportCloser=" $ ZedsTeleportCloser $ ZedsTeleportCloserLatchedString;
}

private function string GetAlbinoAlphasChatString()
{
	local string AlbinoAlphasLatchedString;

	if ( StagedConfig.AlbinoAlphas != AlbinoAlphas )
	{
		AlbinoAlphasLatchedString = " (staged: " $ StagedConfig.AlbinoAlphas $ ")";
	}

	return "AlbinoAlphas=" $ AlbinoAlphas $ AlbinoAlphasLatchedString;
}

private function string GetAlbinoCrawlersChatString()
{
	local string AlbinoCrawlersLatchedString;

	if ( StagedConfig.AlbinoCrawlers != AlbinoCrawlers )
	{
		AlbinoCrawlersLatchedString = " (staged: " $ StagedConfig.AlbinoCrawlers $ ")";
	}

	return "AlbinoCrawlers=" $ AlbinoCrawlers $ AlbinoCrawlersLatchedString;
}

private function string GetAlbinoGorefastsChatString()
{
	local string AlbinoGorefastsLatchedString;

	if ( StagedConfig.AlbinoGorefasts != AlbinoGorefasts )
	{
		AlbinoGorefastsLatchedString = " (staged: " $ StagedConfig.AlbinoGorefasts $ ")";
	}

	return "AlbinoGorefasts=" $ AlbinoGorefasts $ AlbinoGorefastsLatchedString;
}

private function string GetZTSpawnModeChatString()
{
	local string ZTSpawnModeLatchedString;

	if ( StagedConfig.ZTSpawnMode != ZTSpawnMode )
	{
		ZTSpawnModeLatchedString = " (staged: " $ StagedConfig.ZTSpawnMode $ ")";
	}

	return "ZTSpawnMode=" $ ZTSpawnMode $ ZTSpawnModeLatchedString;
}

private function string GetBossChatString()
{
	local string BossLatchedString;

	if ( StagedConfig.Boss != Boss )
	{
		BossLatchedString = " (staged: " $ StagedConfig.Boss $ ")";
	}

	return "Boss=" $ Boss $ BossLatchedString;
}

private function string GetCohortSizeChatString()
{
	local string CohortSizeLatchedString;

	if ( StagedConfig.CohortSize != CohortSize )
	{
		CohortSizeLatchedString = " (staged: " $ StagedConfig.CohortSize $ ")";
	}

	return "CohortSize=" $ CohortSize $ CohortSizeLatchedString;
}

private function string GetFakePlayersChatString()
{
	local string FakePlayersLatchedString;

	if ( StagedConfig.FakePlayers != FakePlayers )
	{
		FakePlayersLatchedString = " (staged: " $ StagedConfig.FakePlayers $ ")";
	}

	return "FakePlayers=" $ FakePlayers $ FakePlayersLatchedString;
}

private function string GetMaxMonstersChatString()
{
	local string MaxMonstersLatchedString;

	if ( StagedConfig.MaxMonsters != MaxMonsters )
	{
		MaxMonstersLatchedString = " (staged: " $ GetMaxMonstersStringForArg(StagedConfig.MaxMonsters) $ ")";
	}

	return "MaxMonsters="$ GetMaxMonstersString() $ MaxMonstersLatchedString;
}

private function string GetMinSpawnIntervalChatString()
{
	local string MinSpawnIntervalLatchedString;

	if ( !EpsilonClose( StagedConfig.MinSpawnIntervalFloat, MinSpawnIntervalFloat, MinSpawnIntervalEpsilon ) )
	{
		MinSpawnIntervalLatchedString = " (staged: " $ StagedConfig.MinSpawnIntervalFloat $ ")";
	}

	return "MinSpawnInterval="$ MinSpawnIntervalFloat $ MinSpawnIntervalLatchedString;
}

private function string GetWeaponTimeoutChatString()
{
	local string WeaponTimeoutLatchedString;

	if ( StagedConfig.WeaponTimeout != WeaponTimeout )
	{
		WeaponTimeoutLatchedString = " (staged: " $ GetWeaponTimeoutStringForArg(StagedConfig.WeaponTimeout) $ ")";
	}

	return "WeaponTimeout="$ GetWeaponTimeoutString() $ WeaponTimeoutLatchedString;
}

private function string GetSpawnCycleChatString()
{
	local string SpawnCycleLatchedString;

	if ( StagedConfig.SpawnCycle != SpawnCycle )
	{
		SpawnCycleLatchedString = " (staged: " $ StagedConfig.SpawnCycle $ ")";
	}

	return "SpawnCycle=" $ SpawnCycle $ SpawnCycleLatchedString;
}

private function string GetSpawnModChatString()
{
	local string SpawnModLatchedString;

	if ( !EpsilonClose( StagedConfig.SpawnModFloat, SpawnModFloat, SpawnModEpsilon ) )
	{
		SpawnModLatchedString = " (staged: " $ StagedConfig.SpawnModFloat $ ")";
	}

	return "SpawnMod="$ SpawnModFloat $ SpawnModLatchedString;
}

private function string GetZTSpawnSlowdownChatString()
{
	local string ZTSpawnSlowdownLatchedString;

	if ( !EpsilonClose( StagedConfig.ZTSpawnSlowdownFloat, ZTSpawnSlowdownFloat, ZTSpawnSlowdownEpsilon ) )
	{
		ZTSpawnSlowdownLatchedString = " (staged: " $ StagedConfig.ZTSpawnSlowdownFloat $ ")";
	}

	return "ZTSpawnSlowdown="$ ZTSpawnSlowdownFloat $ ZTSpawnSlowdownLatchedString;
}


private function string GetTraderTimeChatString()
{
	local string TraderTimeLatchedString;

//	if ( StagedConfig.TraderTime != TraderTime )
//	{
//		TraderTimeLatchedString = " (staged: " $ StagedConfig.TraderTime $ ")";
//	}

	TraderTimeLatchedString = "";

	return "TraderTime=" $ TraderTime $ TraderTimeLatchedString;
}

private function string GetCDVersionChatString()
{
	return "Ver=" $ `CD_COMMIT_HASH $ "\nDate=" $ `CD_AUTHOR_TIMESTAMP;
}
