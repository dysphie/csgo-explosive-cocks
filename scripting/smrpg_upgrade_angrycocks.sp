#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <smrpg>

#pragma newdecls required
#pragma semicolon 1

#define UPGRADE_SHORTNAME "ANGRYCOCKS"

ConVar explosiveCockRadius, angryCockRadius;
ConVar explosionRadius, explosionDamage;

bool spawnedCockThisRound[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Mercenary Explosive Cocks",
	author = "Dysphie",
	description = "Mercenary Explosive Cocks upgrade for SM:RPG.",
	version = "1.0.0",
	url = "steamcommunity.com/id/dysphie"
}

public void OnPluginStart()
{

	HookEvent("round_start", OnRoundStart, EventHookMode_PostNoCopy);
}

public void OnPluginEnd()
{
	if(SMRPG_UpgradeExists(UPGRADE_SHORTNAME))
		SMRPG_UnregisterUpgradeType(UPGRADE_SHORTNAME);
}

public void OnAllPluginsLoaded()
{
	OnLibraryAdded("smrpg");
}

public void OnLibraryAdded(const char[] name)
{
	if(!StrEqual(name, "smrpg"))
		return;

	SMRPG_RegisterUpgradeType("Mercenary Explosive Cocks", UPGRADE_SHORTNAME, "Does something.", 10, true, 5, 15, 10);
		
	explosiveCockRadius = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "sm_cock_explode_radius", "100",
		"Distance from a player at which cocks explode.");

	angryCockRadius = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "sm_cock_aggro_radius", "700",
		"Distance from a player at which cocks become aggro.");

	explosionRadius = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "sm_cock_explosion_radius", "700",
		"Damage of cock explosion.");

	explosionDamage = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "sm_cock_explosion_dmg", "300",
		"Range of cock explosion.");
}

public Action OnCmdBoomChicken(int client, int args)
{
	if(!SMRPG_CanRunEffectOnClient(client))
	{
		ReplyToCommand(client, "You don't own this perk");
		return Plugin_Handled;
	}

	if(spawnedCockThisRound[client])
	{
		ReplyToCommand(client, "You already spawned a cock this round");
		return Plugin_Handled;
	}

	int enemy = GetRandomEnemy(client);
	if(enemy == -1)
		return Plugin_Handled;

	float clientPos[3];
	GetClientAbsOrigin(client, clientPos);

	int cock = CreateEntityByName("chicken");
	if(cock == -1)
		return Plugin_Handled;

	DispatchSpawn(cock);
	TeleportEntity(cock, clientPos, NULL_VECTOR, NULL_VECTOR);

	SetEntPropEnt(cock, Prop_Send, "m_leader", enemy);
	SetEntPropFloat(cock, Prop_Data, "m_explodeDamage", explosionDamage.FloatValue);
	SetEntPropFloat(cock, Prop_Data, "m_explodeRadius", explosionRadius.FloatValue);

	SDKHook(cock, SDKHook_Think, OnCockThink);

	return Plugin_Handled;
}

public void OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i))
			continue;

		spawnedCockThisRound[i] = false;
	}
}

public void OnClientConnected(int client)
{
	spawnedCockThisRound[client] = false;
}

stock bool SMRPG_CanRunEffectOnClient(int client)
{
	if(!SMRPG_IsEnabled())
		return false;
	
	int upgrade[UpgradeInfo];
	SMRPG_GetUpgradeInfo(UPGRADE_SHORTNAME, upgrade);
	if(!upgrade[UI_enabled])
		return false;
	
	if(IsFakeClient(client) && SMRPG_IgnoreBots())
		return false;
	
	int iLevel = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(iLevel <= 0)
		return false;
	
	return true;
}

void OnCockThink(int cock)
{
	// Explode if we are close enough to our leader
	int leader = GetCockLeader(cock);
	if(leader != -1 && !VibeCheck(cock, leader))
		return;

	// We are still alive, recalculate target
	int player = GetClosestPlayer(cock, angryCockRadius.FloatValue);
	if(player != -1)
		SetEntPropEnt(cock, Prop_Send, "m_leader", player);
}

// Returns false if our cock exploded
bool VibeCheck(int cock, int leader)
{
	float cockPos[3], leaderPos[3];
	GetEntPropVector(cock, Prop_Send, "m_vecOrigin", cockPos);
	GetClientAbsOrigin(leader, leaderPos);

	// Leader is too far
	if(GetVectorDistance(leaderPos, cockPos) > explosiveCockRadius.FloatValue)
		return true;

	// Leader is in range
	AcceptEntityInput(cock, "Break");
	return false;
}

int GetCockLeader(int cock)
{
	return GetEntPropEnt(cock, Prop_Send, "m_leader");
}

int GetClosestPlayer(int entity, float maxDistance = 0.0)
{
	float entPos[3], playerPos[3];
	GetEntPropVector(entity, Prop_Send, "m_vecOrigin", entPos);

	float distance, minDistance;
	int minPlayer = -1;

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || !IsPlayerAlive(i))
			continue;

		GetClientAbsOrigin(i, playerPos);
		distance = GetVectorDistance(entPos, playerPos);

		// Player is out of bounds
		if(maxDistance && distance > maxDistance)
			continue;

		if(!minDistance || distance < minDistance)
		{
			minDistance = distance;
			minPlayer = i;
		}
	}

	return minPlayer;
}

void AttachC4ToCock(int cock)
{
	int c4 = CreateEntityByName("planted_c4");
	if(c4 == -1)
		return;

	SetVariantString("!activator");
	AcceptEntityInput(c4, "SetParent", cock);
}

int GetRandomEnemy(int client)
{
	int team = GetClientTeam(client);

	ArrayList candidates = new ArrayList();

	for(int i = 1; i <= MaxClients; i++)
	{
		// Ignore dead and disconnected
		if(!IsClientInGame(i) || !IsPlayerAlive(i))
			continue;

		// Ignore teammates
		if(GetClientTeam(i) == team)
			continue;

		candidates.Push(i);
	}

	int enemyCount = candidates.Length;

	// No alive enemies, bail
	if(!enemyCount)
	{
		delete candidates;
		return -1;
	}

	int enemy = candidates.Get(GetRandomInt(0, enemyCount));
	delete candidates;
	return enemy;
}
