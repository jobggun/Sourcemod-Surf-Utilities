#pragma semicolon 1
#include <sourcemod>
#include <clientprefs>
#include <devzones>
#include <sdktools>
#undef REQUIRE_PLUGIN
#include <updater>

#define VERSION "1.4.0"
#define UPDATE_URL "http://fastdl.jobggun.top:8080/updater/updatefile.txt"

#pragma newdecls required


//SQL Locking System

int g_sequence = 0;								// Global unique sequence number
int g_connectLock = 0;	
Database g_hDatabase;

//SQL Queries

char sql_createTables1[] = "CREATE TABLE IF NOT EXISTS `rankings` ( \
  `ID` int(11) NOT NULL AUTO_INCREMENT, \
  `TimeStamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, \
  `MapName` varchar(32) NOT NULL, \
  `UserName` varchar(32) DEFAULT NULL, \
  `UserID` int(11) NOT NULL, \
  `Score` float NOT NULL, \
  PRIMARY KEY (`ID`) \
);";

char sql_createTables2[] = "CREATE TABLE IF NOT EXISTS `spawnpoint` ( \
  `ID` int(11) NOT NULL AUTO_INCREMENT, \
  `TimeStamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP, \
  `MapName` char(32) NOT NULL, \
  `Pos0_X` float, \
  `Pos0_Y` float, \
  `Pos0_Z` float, \
  `Pos1_X` float, \
  `Pos1_Y` float, \
  `Pos1_Z` float, \
PRIMARY KEY (`ID`) \
);";
//char sql_selectPlayerScore[] = "SELECT `TimeStamp`, `Score` FROM `rankings` WHERE `UserID`='%d';"; // Arg: String:UserID
char sql_selectPlayerScoreByMap[] = "SELECT `TimeStamp`, `Score` FROM `rankings` WHERE `UserID`='%d' AND `MapName`='%s' ORDER BY `Score` ASC;"; // Arg: int32:UserID String:MapName(Must be escaped)
char sql_selectPersonalBestByMap[] = "SELECT `Score` FROM `rankings` WHERE `UserID`='%d' AND `MapName`='%s' ORDER BY `Score` ASC LIMIT 1;"; // Arg: int32:UserID String:MapName(Must be escaped)
char sql_selectScore[] = "SELECT `rankings1`.`ID`, `rankings2`.`UserID`, `rankings1`.`UserName`, `rankings2`.`MinScore` FROM ( SELECT `UserID`, Min(`Score`) as `MinScore` FROM `rankings` WHERE `MapName`='%s' GROUP BY `UserID` ) as `rankings2` JOIN `rankings` as `rankings1` ON `rankings1`.`Score` = `rankings2`.`MinScore` WHERE `MapName`='%s' GROUP BY `UserID`;"; // Arg: String:Map
char sql_selectScoreByID[] = "SELECT `UserName`, `UserID`, `MapName`, `Score`, `TimeStamp` FROM `rankings` WHERE `ID`='%d';"; // Arg int32:ID
char sql_insertScore[] = "INSERT INTO `rankings` SET `MapName`='%s', `UserName`= '%s', `UserID`='%d', `Score`='%.3f';"; // Arg: int32:UserID, float32:Score

char sql_selectSpawnPointByMapName[] = "SELECT `ID`, `Pos0_X`, `Pos0_Y`, `Pos0_Z`, `Pos1_X`, `Pos1_Y`, `Pos1_Z` FROM `spawnpoint` WHERE `MapName`='%s';";
char sql_insertSpawnPointByMapName[] = "INSERT INTO `spawnpoint` SET `MapName`='%s', `Pos0_X`='%.3f', `Pos0_Y`='%.3f', `Pos0_Z`='%.3f', `Pos1_X`='%.3f', `Pos1_Y`='%.3f', `Pos1_Z`='%.3f';";
char sql_insertSpawnPointByMapNameNull[] = "INSERT INTO `spawnpoint` SET `MapName`='%s';";
char sql_updateSpawnPointByMapName[] = "UPDATE `spawnpoint` SET `Pos%1d_X`='%.3f', `Pos%1d_Y`='%.3f', `Pos%1d_Z`='%.3f' WHERE `MapName`='%s';"; // Arg int:index float:Vector[0] int:index float:Vector[1] int:index float:Vector[2] MapName
char sql_updateToNullSpawnPointByMapName[] = "UPDATE `spawnpoint` SET `Pos%1d_X`='', `Pos%1d_Y`='', `Pos%1d_Z`='' WHERE `MapName`='%s';"; // Arg int:index int:index int:index string:MapName

//Plugin cvars and cookies

Handle g_cvarVersion = null;
Handle g_cvarMode = null;
Handle g_cookieHintMode = null;
char g_cookieClientHintMode[MAXPLAYERS + 1] = { 0 };


//Surf Timer Time ticking Process Variable

float g_surfPersonalBest[MAXPLAYERS + 1];
int g_surfPersonalBestMinute[MAXPLAYERS + 1];
float g_surfPersonalBestSecond[MAXPLAYERS + 1];
float g_surfTimerPoint[MAXPLAYERS + 1][2];
char g_surfTimerEnabled[MAXPLAYERS + 1] = { 0 }; // 0 on Surfing 1 on after reaching end zone 2 on being at start zone 3 on being at end zone

//Surf Spawn Point Variable

bool g_surfSpawnPointEnabled[2] = { false };
float g_surfSpawnPointPos[2][3];

#include "surf-utilities/newmenu.sp"
#include "surf-utilities/hud.sp"

public Plugin myinfo =
{
	name = "Surf Utilities with DEV Zones",
	author = "Jobggun",
	description = "Surf Timer for TF2(or any) with Custom Zones",
	version = VERSION,
	url = "Not Specified"
};


//Forwards

public void OnPluginStart()
{
	if (LibraryExists("updater"))
    {
        Updater_AddPlugin(UPDATE_URL);
    }
	
	LoadTranslations("surf-utilities.phrases.txt");
	
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("player_death", Event_PlayerDeath);
	
	g_cvarVersion = CreateConVar("sm_surfutil_version", VERSION, "Surf Utilities Plugin's Version", FCVAR_NOTIFY | FCVAR_REPLICATED);
	g_cvarMode = CreateConVar("sm_surfutil_hudmode", "1", "Whether the surf timer shows on hint message or not globally.");
	
	g_cookieHintMode = RegClientCookie("sm_surfutil_hint_mode", "Whether the surf timer shows on hint message or not.", CookieAccess_Protected);
	SetCookiePrefabMenu(g_cookieHintMode, CookieMenu_YesNo_Int, "Surf Hint Mode");
	
	RegConsoleCmd("sm_myrank", MenuMyRank, "A panel shows your record on this map.");
	RegConsoleCmd("sm_mr", MenuMyRank, "A panel shows your record on this map.");
	RegConsoleCmd("sm_rank", MenuWorldRank, "A panel shows server top record on this map.");
	RegConsoleCmd("sm_wr", MenuWorldRank, "A panel shows server top record on this map.");
	
	RegConsoleCmd("sm_setspawnpoint", CommandSetSpawnPoint, "A Command which sets your position to SpawnPoint (Removal should be done manually)");
	RegConsoleCmd("sm_resetspawnpoint", CommandResetSpawnPoint, "A command which resets your spawnpoint.");
	
	g_syncHud = CreateHudSynchronizer();
}

public void OnLibraryAdded(const char[] name)
{
    if (StrEqual(name, "updater"))
    {
        Updater_AddPlugin(UPDATE_URL);
    }
}

public void OnClientPutInServer(int client)
{
	if(IsInvalidClient(client)) 
		return;
	
	g_surfPersonalBest[client] = 0.0;
	g_surfPersonalBestMinute[client] = 0;
	g_surfPersonalBestSecond[client] = 0.0;
	g_surfTimerEnabled[client] = 2;
	g_surfTimerPoint[client][0] = 0.0;
	g_surfTimerPoint[client][1] = 0.0;
	SurfGetPersonalBest(client);
}

public void OnClientDisconnect(int client)
{
	if (g_surfTimerHandle[client] != null)
		{
			delete g_surfTimerHandle[client];
		}
	ClearSyncHud(client, g_syncHud);
}

public void OnMapStart()
{
	RequestDatabaseConnection();
	CreateTimer(1.0, TimerRequestDatabaseConnection, _, TIMER_REPEAT);
}
public void OnMapEnd()
{
	/**
	 * Clean up on map end just so we can start a fresh connection when we need it later.
	 */
	delete g_hDatabase;
}

///////////////////
//  Event Hook Functions

public void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if(IsInvalidClient(client)) 
		return;
	
	if(AreClientCookiesCached(client))
	{
		char buffer[5];
		GetClientCookie(client, g_cookieHintMode, buffer, sizeof(buffer));
		if(buffer[0] == '\0')
		{
			g_cookieClientHintMode[client] = GetConVarInt(g_cvarMode);
		}
		else
		{
			g_cookieClientHintMode[client] = StringToInt(buffer);
		}
	}
	
	if(g_surfSpawnPointEnabled[0])
	{
		if(g_surfSpawnPointEnabled[1])
		{
			int clientTeam = GetClientTeam(client);
			
			if(clientTeam == 2)
			{
				TeleportEntity(client, g_surfSpawnPointPos[0], NULL_VECTOR, NULL_VECTOR);
			}
			else if(clientTeam == 3)
			{
				TeleportEntity(client, g_surfSpawnPointPos[1], NULL_VECTOR, NULL_VECTOR);
			}
		}
		else
		{
			TeleportEntity(client, g_surfSpawnPointPos[0], NULL_VECTOR, NULL_VECTOR);
		}
	}
	
	g_surfTimerEnabled[client] = 2;
	
	SurfGetPersonalBest(client);
	
	DataPack pack;
	
	if (g_surfTimerHandle[client] != null)
		CloseHandle(g_surfTimerHandle[client]);
	
	g_surfTimerHandle[client] = CreateDataTimer(0.33, SurfPrepareAdvisor, pack, TIMER_REPEAT);
	
	pack.WriteCell(GetClientSerial(client));
	pack.WriteCell(g_cookieClientHintMode[client]);
}

public void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	
	if(IsInvalidClient(client)) 
		return;
	
	g_surfTimerEnabled[client] = 2;
}

public void Zone_OnClientEntry(int client, const char[] zone)
{
	if(IsInvalidClient(client)) 
		return;
	
	if(StrContains(zone, "surf_start", true) == 0)
	{
		g_surfTimerEnabled[client] = 2;
		
		return;
	}
	else if(StrContains(zone, "surf_stop", true) == 0)
	{
		if(g_surfTimerEnabled[client] == 0)
		{
			g_surfTimerPoint[client][1] = GetGameTime();
			float scoredTime = g_surfTimerPoint[client][1] - g_surfTimerPoint[client][0];
			PrintToChat(client, "You've reached to End Zone in %.3fs", scoredTime);
			SurfSetRecord(client, scoredTime);
			SurfGetPersonalBest(client);
		}
		g_surfTimerEnabled[client] = 3;
		
		return;
	}
	else if(StrContains(zone, "surf_checkpoint", false) == 0)
	{
		
	}
}

public void Zone_OnClientLeave(int client, const char[] zone)
{
	if(IsInvalidClient(client)) 
		return;
	
	if(StrContains(zone, "surf_start", false) == 0)
	{
		g_surfTimerPoint[client][0] = GetGameTime();
		g_surfTimerEnabled[client] = 0;
		
		return;
	}
	else if(StrContains(zone, "surf_stop", false) == 0)
	{
		g_surfTimerEnabled[client] = 1;
		
		return;
	}
	else if(StrContains(zone, "surf_checkpoint", false) == 0)
	{
		
	}
}


///////////////////////
// Own Functions

bool IsInvalidClient(int client)
{
	if(client < 1 || client > MaxClients || !IsClientInGame(client) || IsFakeClient(client)) 
		return true;
	else 
		return false;
}

void GetCurrentElapsedTime(int client, int &minute, float &second)
{
	if(g_surfTimerEnabled[client] != 0)
	{
		minute = 0;
		second = 0.0;
		
		return;
	}
	float delta = GetGameTime() - g_surfTimerPoint[client][0];
	
	GetSecondToMinute(delta, minute, second);
	
	return;
}

void GetSecondToMinute(float input, int &minute, float &second)
{	
	minute = RoundToFloor(input) / 60;
	second = input - minute * 60.0;
	
	return;
}

public Action CommandSetSpawnPoint(int client, int args)
{
	if(IsInvalidClient(client))
	{
		ReplyToCommand(client, "[SM] This command is for ingame usage.");
		return Plugin_Handled;
	}
	
	if(args != 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_setspawnpoint [0-1] (0 for RED&T, 1 for BLU&CT)");
		return Plugin_Handled;
	}
	
	char buffer[16];
	int index;
	float Pos[3];
	
	GetCmdArg(1, buffer, sizeof(buffer));
	index = StringToInt(buffer);
	
	if(index < 0 || index > 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_setspawnpoint [0-1] (0 for RED&T, 1 for BLU&CT)");
		return Plugin_Handled;
	}
	
	GetClientAbsOrigin(client, Pos);
	
	SurfSetSpawnPoint(index, Pos);
	SurfGetSpawnPoint();
	
	ReplyToCommand(client, "[SM] It has been set successfully.");
	
	return Plugin_Handled;
}

public Action CommandResetSpawnPoint(int client, int args)
{
	if(args != 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_resetspawnpoint [0-1] (0 for RED&T, 1 for BLU&CT)");
		return Plugin_Handled;
	}
	
	char buffer[16];
	int index;
	
	GetCmdArg(1, buffer, sizeof(buffer));
	index = StringToInt(buffer);
	
	if(index < 0 || index > 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_resetspawnpoint [0-1] (0 for RED&T, 1 for BLU&CT)");
		return Plugin_Handled;
	}
	
	SurfResetSpawnPoint(index);
	SurfGetSpawnPoint();
	
	ReplyToCommand(client, "[SM] It has been resetted successfully.");
	
	return Plugin_Handled;
}

///////////////////////////
// Database Functions

public Action TimerRequestDatabaseConnection(Handle timer)
{
	if(g_hDatabase == null)
	{
		RequestDatabaseConnection();
		
		return Plugin_Continue;
	}
	else
	{
		return Plugin_Stop;
	}
}

void RequestDatabaseConnection()
{
	g_connectLock = ++g_sequence;
	
	if(SQL_CheckConfig("surf"))
	{
		Database.Connect(OnDatabaseConnect, "surf", g_connectLock);
	} else {
		Database.Connect(OnDatabaseConnect, "default", g_connectLock);
	}
	
	return;
}

public void OnDatabaseConnect(Database db, const char[] error, any data)
{
	/**
	 * If there is difference between data(old connectLock) and connectLock, It might be replaced by other thread.
	 * If g_hDatabase is not null, Threaded job is running now.
	 */
	if(data != g_connectLock || g_hDatabase != null)
	{
		delete db;
		return;
	}
	
	g_connectLock = 0;

	/**
	 * See if the connection is valid.  If not, don't un-mark the caches
	 * as needing rebuilding, in case the next connection request works.
	 */
	if(db == null)
	{
		LogError("Database failure: %s", error);
	}
	else 
	{
		g_hDatabase = db;
	}
	db.Query(T_CreateTable, sql_createTables1, _, DBPrio_High);
	db.Query(T_CreateTable, sql_createTables2, _, DBPrio_High);
	
	SurfGetSpawnPoint();
	
	return;
}

public void T_CreateTable(Database db, DBResultSet results, const char[] error, any data)
{
	if(db == null || results == null || error[0] != '\0')
	{
		LogError("Query failed! %s", error);
		if(results != null)
			delete results;
		return;
	}
	
	delete results;
	
	return;
}

void SurfSetRecord(int client, float timeScored)
{
	char query[255];
	char unescapedName[32], unescapedMap[32];
	char Name[65], Map[65];
	
	GetClientName(client, unescapedName, sizeof(unescapedName));
	GetCurrentMap(unescapedMap, sizeof(unescapedMap));
	
	if(!(SQL_EscapeString(g_hDatabase, unescapedName, Name, sizeof(Name)) && SQL_EscapeString(g_hDatabase, unescapedMap, Map, sizeof(Map))))
	{
		LogError("Escape Error");
		return;
	}
	
	FormatEx(query, sizeof(query), sql_insertScore, Map, Name, GetSteamAccountID(client), timeScored);
	g_hDatabase.Query(T_SurfSetRecord, query, GetClientSerial(client));
	
	return;
}

public void T_SurfSetRecord(Database db, DBResultSet results, const char[] error, any data)
{
	if(GetClientFromSerial(data) == 0)
		return;
	
	if(db == null || results == null || error[0] != '\0')
	{
		LogError("Query failed! %s", error);
		if(results != null)
			delete results;
		return;
	}
	
	delete results;
	
	return;
}

void SurfGetPersonalBest(int client)
{
	char query[255];
	char unescapedMap[32], Map[65];
	
	GetCurrentMap(unescapedMap, sizeof(unescapedMap));
	
	if(!(SQL_EscapeString(g_hDatabase, unescapedMap, Map, sizeof(Map))))
	{
		LogError("Escape Error");
		return;
	}
	
	FormatEx(query, sizeof(query), sql_selectPersonalBestByMap, GetSteamAccountID(client), Map);
	g_hDatabase.Query(T_SurfGetPersonalBest, query, GetClientSerial(client));
	
	return;
}

public void T_SurfGetPersonalBest(Database db, DBResultSet results, const char[] error, any data)
{
	int client = GetClientFromSerial(data);
	
	if(client == 0)
	{
		return;
	}
	
	if(db == null || results == null || error[0] != '\0')
	{
		LogError("Query failed! %s", error);
		if(results != null)
			delete results;
		return;
	}
	
	if(SQL_HasResultSet(results) && SQL_FetchRow(results))
	{
		g_surfPersonalBest[client] = SQL_FetchFloat(results, 0);
		GetSecondToMinute(g_surfPersonalBest[client], g_surfPersonalBestMinute[client], g_surfPersonalBestSecond[client]);
	}
	
	delete results;
	
	return;
}

void SurfAddSpawnPointRecord()
{
	char query[256];
	char unescapedMap[32];
	char Map[65];
	
	GetCurrentMap(unescapedMap, sizeof(unescapedMap));
	if(!SQL_EscapeString(g_hDatabase, unescapedMap, Map, sizeof(Map)))
	{
		LogError("Escape Error");
		return;
	}
	
	FormatEx(query, sizeof(query), sql_insertSpawnPointByMapNameNull, Map);
	
	g_hDatabase.Query(T_SurfGetSpawnPoint, query);
	
	return;
}

public void T_SurfAddSpawnPointRecord(Database db, DBResultSet results, const char[] error, any data)
{
	if (db == null || results == null || error[0] != '\0')
	{
		LogError("Query failed! %s", error);
		if(results != null)
			delete results;
		return;
	}
	
	delete results;
	
	
}

void SurfGetSpawnPoint()
{
	char query[256];
	char unescapedMap[32];
	char Map[65];
	
	GetCurrentMap(unescapedMap, sizeof(unescapedMap));
	if(!SQL_EscapeString(g_hDatabase, unescapedMap, Map, sizeof(Map)))
	{
		LogError("Escape Error");
		return;
	}
	
	FormatEx(query, sizeof(query), sql_selectSpawnPointByMapName, Map);
	
	g_hDatabase.Query(T_SurfGetSpawnPoint, query);
	
	return;
}

public void T_SurfGetSpawnPoint(Database db, DBResultSet results, const char[] error, any data)
{
	if (db == null || results == null || error[0] != '\0')
	{
		LogError("Query failed! %s", error);
		if(results != null)
			delete results;
		return;
	}
	
	if(SQL_FetchRow(results) && SQL_HasResultSet(results))
	{
		if(!(SQL_IsFieldNull(results, 1) || SQL_IsFieldNull(results, 2) || SQL_IsFieldNull(results, 3)))
		{
			g_surfSpawnPointEnabled[0] = true;
			g_surfSpawnPointPos[0][0] = SQL_FetchFloat(results, 1);
			g_surfSpawnPointPos[0][1] = SQL_FetchFloat(results, 2);
			g_surfSpawnPointPos[0][2] = SQL_FetchFloat(results, 3);
		}
		else
		{
			g_surfSpawnPointEnabled[0] = false;
		}
		if(!(SQL_IsFieldNull(results, 4) || SQL_IsFieldNull(results, 5) || SQL_IsFieldNull(results, 6)))
		{
			g_surfSpawnPointEnabled[1] = true;
			g_surfSpawnPointPos[1][0] = SQL_FetchFloat(results, 4);
			g_surfSpawnPointPos[1][1] = SQL_FetchFloat(results, 5);
			g_surfSpawnPointPos[1][2] = SQL_FetchFloat(results, 6);
		}
		else
		{
			g_surfSpawnPointEnabled[1] = false;
		}
	}
	else
	{
		SurfAddSpawnPointRecord();
	}
	
	delete results;
	
	return;
}

void SurfSetSpawnPoint(int index, const float Pos[3])
{
	if(index < 0 || index > 1)
		return;
	
	char query[256];
	char unescapedMap[32];
	char Map[65];
	
	GetCurrentMap(unescapedMap, sizeof(unescapedMap));
	if(!SQL_EscapeString(g_hDatabase, unescapedMap, Map, sizeof(Map)))
	{
		LogError("Escape Error");
		return;
	}
	
	FormatEx(query, sizeof(query), sql_updateSpawnPointByMapName, index, Pos[0], index, Pos[1], index, Pos[2], Map);
	
	g_hDatabase.Query(T_SurfSetSpawnPoint, query);
	
	return;
}

public void T_SurfSetSpawnPoint(Database db, DBResultSet results, const char[] error, any data)
{
	if (db == null || results == null || error[0] != '\0')
	{
		LogError("Query failed! %s", error);
		if(results != null)
			delete results;
		return;
	}
	
	delete results;
	
	return;
}

void SurfResetSpawnPoint(int index)
{
	if(index < 0 || index > 1)
		return;
	
	char query[256];
	char unescapedMap[32];
	char Map[65];
	
	GetCurrentMap(unescapedMap, sizeof(unescapedMap));
	if(!SQL_EscapeString(g_hDatabase, unescapedMap, Map, sizeof(Map)))
	{
		LogError("Escape Error");
		return;
	}
	
	FormatEx(query, sizeof(query), sql_updateToNullSpawnPointByMapName, index, index, index, Map);
	
	g_hDatabase.Query(T_SurfResetSpawnPoint, query);
	
	return;
}

public void T_SurfResetSpawnPoint(Database db, DBResultSet results, const char[] error, any data)
{
	if (db == null || results == null || error[0] != '\0')
	{
		LogError("Query failed! %s", error);
		if(results != null)
			delete results;
		return;
	}
	
	delete results;
	
	return;
}