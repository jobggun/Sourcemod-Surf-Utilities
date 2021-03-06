Handle g_surfTimerHandle[MAXPLAYERS + 1];

Handle g_syncHud = null;

//DataPack must be int:ClientSerial int:ClientHintMode

public Action SurfPrepareAdvisor(Handle timer, any data)
{
	DataPack pack = view_as<DataPack>(data);
	pack.Reset();
	
	int client = GetClientFromSerial(pack.ReadCell());
	int clientHintMode = pack.ReadCell();
	
	if(client == 0)
	{
		return Plugin_Stop;
	}
	
	if(!IsPlayerAlive(client))
		return Plugin_Continue;
	
	if(clientHintMode == 1)
	{
		PrintHintText(client, "...");
		g_surfTimerHandle[client] = CreateTimer(1.0, SurfShowHintBefore, GetClientSerial(client));
	}
	else 
	{
		g_surfTimerHandle[client] = CreateTimer(0.2, SurfShowHud, GetClientSerial(client), TIMER_REPEAT);
	}
	
	return Plugin_Stop;
}

//data must be int:ClientSerial

public Action SurfShowHud(Handle timer, any serial)
{
	int client = GetClientFromSerial(serial);
	
	if(client == 0)
	{
		return Plugin_Stop;
	}
	
	SetHudTextParams(0.46, 0.1, 3.0, 255,255,255,255, 0, 0.0, 0.0, 0.0);
	
	if(g_surfTimerEnabled[client] == 2)
	{
		ShowSyncHudText(client, g_syncHud, "\nStart Zone");
		return Plugin_Continue;
	}
	else if (g_surfTimerEnabled[client] == 3)
	{
		ShowSyncHudText(client, g_syncHud, "\nEnd Zone");
		return Plugin_Continue;
	}
	
	char buffer[256];
	float vecVelocity[3];
	float velocity;
	float second;
	int minute;
	
	GetClientName(client, buffer, sizeof(buffer));
	GetCurrentElapsedTime(client, minute, second);
	
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vecVelocity);
	velocity = SquareRoot(Pow(vecVelocity[0], 2.0) + Pow(vecVelocity[1], 2.0));
	
	if (g_surfPersonalBest[client] != 0.0)
	{
		ShowSyncHudText(client, g_syncHud, "%T", "SurfHudPB", client, minute, second, g_surfPersonalBestMinute[client], g_surfPersonalBestSecond[client], velocity, buffer);
	}
	else
	{
		ShowSyncHudText(client, g_syncHud, "%T", "SurfHud", client, minute, second, velocity, buffer);
	}
	
	return Plugin_Continue;
}

public Action SurfShowHintBefore(Handle timer, any serial)
{
	int client = GetClientFromSerial(serial);
	
	if(client == 0)
	{
		return Plugin_Stop;
	}

	g_surfTimerHandle[client] = CreateTimer(0.2, SurfShowHint, serial, TIMER_REPEAT);
	
	return Plugin_Continue;
}

public Action SurfShowHint(Handle timer, any serial)
{
	int client = GetClientFromSerial(serial);
	
	if(client == 0)
	{
		return Plugin_Stop;
	}
	
	if(g_surfTimerEnabled[client] == 2)
	{
		PrintHintText(client, "Start Zone");
		return Plugin_Continue;
	}
	else if (g_surfTimerEnabled[client] == 3)
	{
		PrintHintText(client, "End Zone");
		return Plugin_Continue;
	}
	
	char buffer[256];
	float vecVelocity[3];
	float velocity;
	float second;
	int minute;
	
	GetClientName(client, buffer, sizeof(buffer));
	GetCurrentElapsedTime(client, minute, second);
	
	GetEntPropVector(client, Prop_Data, "m_vecVelocity", vecVelocity);
	velocity = SquareRoot(Pow(vecVelocity[0], 2.0) + Pow(vecVelocity[1], 2.0));
	
	if (g_surfPersonalBest[client] != 0.0)
	{
		PrintHintText(client, "%T", "SurfHudPB", client, minute, second, g_surfPersonalBestMinute[client], g_surfPersonalBestSecond[client], velocity, buffer);
	}
	else
	{
		PrintHintText(client, "%T", "SurfHud", client, minute, second, velocity, buffer);
	}
	
	return Plugin_Continue;
}