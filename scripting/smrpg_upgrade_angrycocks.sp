#include <sourcemod>
#include <sdkhooks>
#include <sdktools>
#include <smrpg>
#include <cstrike>

#pragma newdecls required
#pragma semicolon 1

#define UPGRADE_SHORTNAME "ANGRYCOCKS"

ConVar explosiveCockRadius, angryCockRadius;
ConVar explosionRadius, explosionDamage;

int cocksSpawned[MAXPLAYERS+1];

public Plugin myinfo = 
{
	name = "SM:RPG Upgrade > Mercenary Explosive Cocks",
	author = "Dysphie",
	description = "Mercenary Explosive Cocks upgrade for SM:RPG.",
	version = "1.0.0",
	url = "steamcommunity.com/id/dysphie"
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

	SMRPG_RegisterUpgradeType("Mercenary Explosive Cocks", UPGRADE_SHORTNAME,
	"Spawn an explosive chicken.", /* description */
	5, /* maxlevelbarrier */
	true, /* bDefaultEnable */
	5, /* iDefaultMaxLevel */
	15, /* iDefaultStartCost */
	10); /* iDefaultCostInc */
		
	explosiveCockRadius = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "sm_cock_explode_radius", "200",
		"Distance from a player at which cocks explode.");

	angryCockRadius = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "sm_cock_aggro_radius", "700",
		"Distance from a player at which cocks become aggro.");

	explosionRadius = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "sm_cock_explosion_radius", "250",
		"Damage of cock explosion.");

	explosionDamage = SMRPG_CreateUpgradeConVar(UPGRADE_SHORTNAME, "sm_cock_explosion_dmg", "1000",
		"Range of cock explosion.");
}

public void OnPluginStart()
{
	HookEvent("round_start", OnRoundStart, EventHookMode_PostNoCopy);
	HookEvent("round_end", OnRoundEnd, EventHookMode_PostNoCopy);
	RegConsoleCmd("sm_cock", OnCmdBoomChicken);
}

public Action OnRoundEnd(Event event, const char[] name, bool dontBroadcast)
{
	int ent = -1;
	while ((ent = FindEntityByClassname(ent, "chicken")) != -1)
		RemoveEntity(ent);
}

public Action OnCmdBoomChicken(int client, int args)
{
	if(!IsPlayerAlive(client))
	{
		ReplyToCommand(client, "You must be alive to use your cock");
		return Plugin_Handled;
	}

	if(!SMRPG_CanRunEffectOnClient(client))
	{
		ReplyToCommand(client, "You don't own this perk!");
		return Plugin_Handled;
	}

	int level = SMRPG_GetClientUpgradeLevel(client, UPGRADE_SHORTNAME);
	if(cocksSpawned[client] >= GetChickenLimitForLevel(level))
	{
		ReplyToCommand(client, "Cock limit reached for this round");
		return Plugin_Handled;
	}

	float clientPos[3];
	GetClientAbsOrigin(client, clientPos);

	int cock = CreateEntityByName("chicken");
	if(cock == -1)
		return Plugin_Handled;

	DispatchSpawn(cock);
	TeleportEntity(cock, clientPos, NULL_VECTOR, NULL_VECTOR);

	int clientTeam = GetClientTeam(client);
	SetEntProp(cock, Prop_Send, "m_iTeamNum", clientTeam);

	// int enemy = GetRandomEnemy(client);
	// if(enemy != -1)
	//	SetEntPropEnt(cock, Prop_Send, "m_leader", enemy);

	SetEntPropFloat(cock, Prop_Data, "m_explodeDamage", explosionDamage.FloatValue);
	SetEntPropFloat(cock, Prop_Data, "m_explodeRadius", explosionRadius.FloatValue);

	int cockHp = GetChickenHealthForLevel(level);
	SetEntProp(cock, Prop_Data, "m_iMaxHealth", cockHp);
	SetEntProp(cock, Prop_Data, "m_iHealth", cockHp);

	// AttachC4ToCock(cock);
	ColorMyCock(cock, clientTeam);
	SDKHook(cock, SDKHook_Think, OnCockThink);
	cocksSpawned[client]++;
	ReplyToCommand(client, "Explosive cock spawned!");
	return Plugin_Handled;
}

void ColorMyCock(int cock, int team)
{
	if(team == CS_TEAM_T)
		SetEntityRenderColor(cock, 255, 0, 0);
	else if(team == CS_TEAM_CT)
		SetEntityRenderColor(cock, 0, 255, 0);
}

public void OnRoundStart(Event event, const char[] name, bool dontBroadcast)
{
	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i))
			continue;

		cocksSpawned[i] = 0;
	}
}

public void OnClientConnected(int client)
{
	cocksSpawned[client] = 0;
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
	int cockTeam = GetEntProp(cock, Prop_Send, "m_iTeamNum");
	int player = GetClosestCockTarget(cock, cockTeam, angryCockRadius.FloatValue);
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

int GetClosestCockTarget(int cock, int cockTeam, float maxDistance = 0.0)
{
	float entPos[3], playerPos[3];
	GetEntPropVector(cock, Prop_Send, "m_vecOrigin", entPos);

	float distance, minDistance;
	int minPlayer = -1;

	for(int i = 1; i <= MaxClients; i++)
	{
		if(!IsClientInGame(i) || !IsPlayerAlive(i))
			continue;

		if(GetClientTeam(i) == cockTeam)
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
	int c4 = CreateEntityByName("weapon_c4");
	if(c4 == -1)
		return;

	DispatchKeyValue(c4, "solid", "0");
	DispatchSpawn(c4);

	SetVariantString("!activator");
	AcceptEntityInput(c4, "SetParent", cock);

	SetVariantString("beak");
	AcceptEntityInput(c4, "SetParentAttachment");
}

stock int GetRandomEnemy(int client)
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

	int enemy = candidates.Get(GetRandomInt(0, enemyCount-1));
	delete candidates;
	return enemy;
}

int GetChickenHealthForLevel(int level)
{
	if(!level) return 1;
	return 100 * level;
}

// TODO: This properly
int GetChickenLimitForLevel(int level)
{
	if (!level) return 0;
	if (level < 3) return 1;
	if (level < 6) return 2;
	if (level < 9) return 3;
	return 0;
}
