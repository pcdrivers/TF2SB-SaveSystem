////////////////////////
// Table of contents: // 
//		Main Menu	  //
//					  //
//		1.Load...     //
//		2.Save...	  //
//		3.Delete...	  //
//		  		      //
////////////////////////

#pragma semicolon 1

#define DEBUG

#define PLUGIN_AUTHOR "Battlefield Duck"
#define PLUGIN_VERSION "1.5"

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#include <build>

#pragma newdecls required

public Plugin myinfo = 
{
	name = "[TF2] SandBox - SaveSystem",
	author = PLUGIN_AUTHOR,
	description = "Save System for TF2SB",
	version = PLUGIN_VERSION,
	url = "http://steamcommunity.com/id/battlefieldduck/"
};

Handle g_hFileEditting[MAXPLAYERS + 1] = INVALID_HANDLE;
Handle cviCoolDownsec;
Handle cviStoreSlot;
char CurrentMap[64];

bool bEnabled = true;
int iCoolDown[MAXPLAYERS + 1] = 0;

bool bPermission[MAXPLAYERS + 1][100]; //client, slot
int iSelectedClient[MAXPLAYERS + 1];

/*******************************************************************************************
	Start
*******************************************************************************************/
public void OnPluginStart()
{
	CreateConVar("sm_tf2sb_ss_version", PLUGIN_VERSION, "", FCVAR_SPONLY|FCVAR_NOTIFY);
        
	cviCoolDownsec = CreateConVar("sm_tf2sb_ss_cooldownsec", "2", "Set CoolDown seconds to prevent flooding.", 0, true, 0.0, true, 50.0);
	cviStoreSlot = CreateConVar("sm_tf2sb_ss_storeslots", "4", "How many slots for client to save", 0, true, 1.0, true, 100.0);
	RegAdminCmd("sm_ss", Command_MainMenu, 0, "Open SaveSystem menu");
	RegAdminCmd("sm_ssload", Command_LoadDataFromDatabase, ADMFLAG_GENERIC, "Usage: sm_ssload <targetname|steamid64> <slot>");
	
	char cCheckPath[128];
	BuildPath(Path_SM, cCheckPath, sizeof(cCheckPath), "data/TF2SBSaveSystem");
	if(!DirExists(cCheckPath))
	{
		CreateDirectory(cCheckPath, 511);
		
		if(DirExists(cCheckPath))
			PrintToServer("[TF2SB] Folder TF2SBSaveSystem created under addons/sourcemod/data/ sucessfully!");
		else
			SetFailState("[TF2SB] Failed to create directory at addons/sourcemod/data/TF2SBSaveSystem/ - Please manually create that path and reload this plugin.");
	}
}

public Action Command_LoadDataFromDatabase(int client, int args)
{
	if(Build_IsClientValid(client, client))
	{
		if(iCoolDown[client] != 0)
		{
			Build_PrintToChat(client, "Load Function is currently cooling down, please wait \x04%i\x01 seconds.", iCoolDown[client]);
		}
		else if(args == 2)
		{
			char cArg[64], szBuffer[3][255], cTarget[20], cSlot[8];
			GetCmdArgString(cArg, sizeof(cArg));
			ExplodeString(cArg, " ", szBuffer, args, 255);
			
			Format(cTarget, sizeof(cTarget), "%s", szBuffer[0]);
			Format(cSlot, sizeof(cSlot), "%s", szBuffer[1]);
			
			int targets[1]; // When not target multiple players, COMMAND_FILTER_NO_MULTI 
			char target_name[MAX_TARGET_LENGTH]; 
			bool tn_is_ml; 
			int targets_found = ProcessTargetString(cTarget, client, targets, sizeof(targets), COMMAND_FILTER_NO_IMMUNITY|COMMAND_FILTER_NO_MULTI, target_name, sizeof(target_name), tn_is_ml);
			
			if(targets_found <= COMMAND_TARGET_AMBIGUOUS)
			{
				Build_PrintToChat(client, "Error: More then one client have the name : \x04%s\x01", cTarget);
			}
			else if (targets_found <= COMMAND_TARGET_NONE) 
			{ 
				Build_PrintToChat(client, "Searching steamid(\x04%s\x01)... Searching file slot\x04%i\x01...", cTarget, StringToInt(cSlot));
				
				char cFileName[255];
				BuildPath(Path_SM, cFileName, sizeof(cFileName), "data/TF2SBSaveSystem/%s&%s@%i.tf2sb", CurrentMap, cTarget, StringToInt(cSlot));
				
				if(FileExists(cFileName))
				{
					LoadDataSteamID(client, cTarget, StringToInt(cSlot));
				}
				else
					Build_PrintToChat(client, "Error: Fail to find the Data File...");
		    } 
			else
		    { 
				Build_PrintToChat(client, "Found target(\x04%N\x01)... Searching file slot\x04%i\x01...", targets[0], StringToInt(cSlot));
				if(DataFileExist(targets[0], StringToInt(cSlot)))
					LoadData(client, targets[0], StringToInt(cSlot));
				else
					Build_PrintToChat(client, "Error: Fail to find the Data File...");
		    } 
			iCoolDown[client] = GetConVarInt(cviCoolDownsec);
			CreateTimer(0.05, Timer_CoolDownFunction, client);
		}
		else
		{
			Build_PrintToChat(client, "Usage: sm_ssload <\x04targetname\x01|\x04steamid\x01> <\x04slot\x01>");
		}
	}
	return;
}

public void OnMapStart()
{
	for(int i = 1; i < MAXPLAYERS; i++)
	{
		OnClientPutInServer(i);
	}
	
	CreateTimer(10.0, Timer_Ads, 0);
	
	GetCurrentMap(CurrentMap, sizeof(CurrentMap));
}

public void OnClientPutInServer(int client)
{
	iCoolDown[client] = 0;
	for(int j = 0; j < 100; j++)
	{	
		bPermission[client][j] = false;
	}
}

/*******************************************************************************************
	Timer
*******************************************************************************************/
public Action Timer_CoolDownFunction(Handle timer, int client)
{
	iCoolDown[client] -= 1;
	
	if(iCoolDown[client] >= 1)
		CreateTimer(1.0, Timer_CoolDownFunction, client);
	else
		iCoolDown[client] = 0;
}

public Action Timer_Ads(Handle timer, int LoopNumber)
{
	switch(LoopNumber)
	{
		case(0):
		{
			Build_PrintToAll(" Type \x04/ss\x01 to SAVE or LOAD your buildings!");
		}
		case(1):
		{
			Build_PrintToAll(" Remember to SAVE your buildings! Type \x04/ss\x01 in chat box to save.");
		}
	}
	LoopNumber++;
	
	if(LoopNumber > 1)
		LoopNumber = 0;
		
	CreateTimer(25.0, Timer_Ads, LoopNumber);
}

/*******************************************************************************************
	Main Menu
*******************************************************************************************/
public Action Command_MainMenu(int client, int args) 
{
	if (bEnabled)
	{	
		char menuinfo[1024];
		Menu menu = new Menu(Handler_MainMenu);
			
		Format(menuinfo, sizeof(menuinfo), "TF2 Sandbox - Save System Main Menu %s \nCurrent Map: %s \n ", PLUGIN_VERSION, CurrentMap);
		menu.SetTitle(menuinfo);
		
		Format(menuinfo, sizeof(menuinfo), " Load... ", client);	
		menu.AddItem("LOAD", menuinfo);
		
		Format(menuinfo, sizeof(menuinfo), " Save... ", client);	
		menu.AddItem("SAVE", menuinfo);
		
		Format(menuinfo, sizeof(menuinfo), " Delete... ", client);	
		menu.AddItem("DELETE", menuinfo);
		
		Format(menuinfo, sizeof(menuinfo), " Set Permission... ", client);	
		menu.AddItem("PERMISSION", menuinfo);
		
		Format(menuinfo, sizeof(menuinfo), " Load other's projects... ", client);	
		if(GetClientInGame() > 1)
			menu.AddItem("LOADOTHERS", menuinfo);
		else
			menu.AddItem("LOADOTHERS", menuinfo, ITEMDRAW_DISABLED);
			
		menu.ExitBackButton = true;
		menu.ExitButton = true;
		menu.Display(client, MENU_TIME_FOREVER);
	}
	return Plugin_Handled;
}

public int Handler_MainMenu(Menu menu, MenuAction action, int client, int selection)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(selection, info, sizeof(info));
		
		if (StrEqual(info, "LOAD"))
		{
			Command_LoadMenu(client, -1);
		}
		else if (StrEqual(info, "SAVE"))
		{
			Command_SaveMenu(client, -1);
		}
		else if (StrEqual(info, "DELETE"))
		{
			Command_DeleteMenu(client, -1);
		}
		else if (StrEqual(info, "PERMISSION"))
		{
			Command_PermissionMenu(client, -1);
		}
		else if (StrEqual(info, "LOADOTHERS"))
		{
			Command_LoadOthersMenu(client, -1);
		}
	}
	else if (action == MenuAction_Cancel)
	{
		if (selection == MenuCancel_ExitBack) 
		{
			FakeClientCommand(client, "sm_build");
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

/*******************************************************************************************
	 Load Menu
*******************************************************************************************/
public Action Command_LoadMenu(int client, int args) 
{
	if (bEnabled)
	{	
		char menuinfo[255];
		Menu menu = new Menu(Handler_LoadMenu);
			
		Format(menuinfo, sizeof(menuinfo), "TF2 Sandbox - Save System Main Menu %s \nCurrent Map: %s \n \nSelect a Slot to LOAD....", PLUGIN_VERSION, CurrentMap);
		menu.SetTitle(menuinfo);
		
		char cSlot[6];
		char cDate[11];
		for(int iSlot = 1; iSlot <= GetConVarInt(cviStoreSlot); iSlot++)
		{
			IntToString(iSlot, cSlot, sizeof(cSlot));
			if(DataFileExist(client, iSlot))
			{
				GetDataDate(client, iSlot, cDate, sizeof(cDate));
				Format(menuinfo, sizeof(menuinfo), " Slot %i (Stored %s, %i Props)", iSlot, cDate, GetDataProps(client, iSlot));	
				menu.AddItem(cSlot, menuinfo);
			}
			else
			{
				Format(menuinfo, sizeof(menuinfo), " Slot %i (No Data)", iSlot);	
				menu.AddItem(cSlot, menuinfo, ITEMDRAW_DISABLED);
			}
		}
		
		menu.ExitBackButton = true;
		menu.ExitButton = false;
		menu.Display(client, MENU_TIME_FOREVER);
	}
	return Plugin_Handled;
}

public int Handler_LoadMenu(Menu menu, MenuAction action, int client, int selection)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(selection, info, sizeof(info));
		
		int iSlot = StringToInt(info);
		
		if(iCoolDown[client] == 0)
		{
			LoadData(client, client, iSlot);
			iCoolDown[client] = GetConVarInt(cviCoolDownsec);
			CreateTimer(0.05, Timer_CoolDownFunction, client);
		}
		else
		{
			Build_PrintToChat(client, "Load Function is currently cooling down, please wait \x04%i\x01 seconds.", iCoolDown[client]);
		}
		
		Command_LoadMenu(client, -1);
	}
	else if (action == MenuAction_Cancel)
	{
		if (selection == MenuCancel_ExitBack) 
		{
			Command_MainMenu(client, -1);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

/*******************************************************************************************
	 Save Menu
*******************************************************************************************/
public Action Command_SaveMenu(int client, int args) 
{	
	if (bEnabled)
	{	
		char menuinfo[255];
		Menu menu = new Menu(Handler_SaveMenu);
			
		Format(menuinfo, sizeof(menuinfo), "TF2 Sandbox - Save System Main Menu %s \nCurrent Map: %s \n \nSelect a Slot to SAVE....", PLUGIN_VERSION, CurrentMap);
		menu.SetTitle(menuinfo);
		
		char cSlot[6];
		char cDate[11];
		for(int iSlot = 1; iSlot <= GetConVarInt(cviStoreSlot); iSlot++)
		{
			IntToString(iSlot, cSlot, sizeof(cSlot));
			if(DataFileExist(client, iSlot))
			{
				GetDataDate(client, iSlot, cDate, sizeof(cDate));
				Format(menuinfo, sizeof(menuinfo), " Slot %i (Stored %s, %i Props)", iSlot, cDate, GetDataProps(client, iSlot));	
				menu.AddItem(cSlot, menuinfo, ITEMDRAW_DISABLED);
			}
			else
			{
				Format(menuinfo, sizeof(menuinfo), " Slot %i (No Data)", iSlot);	
				menu.AddItem(cSlot, menuinfo);
			}
		}
		
		
		menu.ExitBackButton = true;
		menu.ExitButton = false;
		menu.Display(client, MENU_TIME_FOREVER);
	}
	return Plugin_Handled;
}

public int Handler_SaveMenu(Menu menu, MenuAction action, int client, int selection)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(selection, info, sizeof(info));
		
		int iSlot = StringToInt(info);
		
		if(iCoolDown[client] == 0)
		{
			SaveData(client, iSlot);
			iCoolDown[client] = GetConVarInt(cviCoolDownsec);
			CreateTimer(0.05, Timer_CoolDownFunction, client);
		}
		else
			Build_PrintToChat(client, "Save Function is currently cooling down, please wait \x04%i\x01 seconds.", iCoolDown[client]);
		
		Command_SaveMenu(client, -1);
	}
	else if (action == MenuAction_Cancel)
	{
		if (selection == MenuCancel_ExitBack) 
		{
			Command_MainMenu(client, -1);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

/*******************************************************************************************
	 Delete Menu
*******************************************************************************************/
public Action Command_DeleteMenu(int client, int args) 
{	
	if (bEnabled)
	{	
		char menuinfo[255];
		Menu menu = new Menu(Handler_DeleteMenu);
			
		Format(menuinfo, sizeof(menuinfo), "TF2 Sandbox - Save System Main Menu %s \nCurrent Map: %s \n \nSelect a Slot to DELETE....", PLUGIN_VERSION, CurrentMap);
		menu.SetTitle(menuinfo);
		
		char cSlot[6];
		char cDate[11];
		for(int iSlot = 1; iSlot <= GetConVarInt(cviStoreSlot); iSlot++)
		{
			IntToString(iSlot, cSlot, sizeof(cSlot));
			if(DataFileExist(client, iSlot))
			{
				GetDataDate(client, iSlot, cDate, sizeof(cDate));
				Format(menuinfo, sizeof(menuinfo), " Slot %i (Stored %s, %i Props)", iSlot, cDate, GetDataProps(client, iSlot));	
				menu.AddItem(cSlot, menuinfo);
			}
			else
			{
				Format(menuinfo, sizeof(menuinfo), " Slot %i (No Data)", iSlot);	
				menu.AddItem(cSlot, menuinfo, ITEMDRAW_DISABLED);
			}
		}
		
		menu.ExitBackButton = true;
		menu.ExitButton = false;
		menu.Display(client, MENU_TIME_FOREVER);
	}
	return Plugin_Handled;
}

public int Handler_DeleteMenu(Menu menu, MenuAction action, int client, int selection)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(selection, info, sizeof(info));
		
		int iSlot = StringToInt(info);
		
		Command_DeleteConfirmMenu(client, iSlot);
	}
	else if (action == MenuAction_Cancel)
	{
		if (selection == MenuCancel_ExitBack) 
		{
			Command_MainMenu(client, -1);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

/*******************************************************************************************
	 Delete Confirm (2) Menu
*******************************************************************************************/
public Action Command_DeleteConfirmMenu(int client, int iSlot) 
{	
	if (bEnabled)
	{	
		char menuinfo[255];
		Menu menu = new Menu(Handler_DeleteConfirmMenu);
			
		Format(menuinfo, sizeof(menuinfo), "TF2 Sandbox - Save System Main Menu %s \nCurrent Map: %s \n \n Are you sure to DELETE slot %i?", PLUGIN_VERSION, CurrentMap, iSlot);
		menu.SetTitle(menuinfo);
		
		char cSlot[8];
		IntToString(iSlot, cSlot, sizeof(cSlot));
		Format(menuinfo, sizeof(menuinfo), " Yes, Delete it.");	
		menu.AddItem(cSlot, menuinfo);
		
		Format(menuinfo, sizeof(menuinfo), " No, go back!");	
		menu.AddItem("NO", menuinfo);
		
		menu.ExitBackButton = true;
		menu.ExitButton = false;
		menu.Display(client, MENU_TIME_FOREVER);
	}
	return Plugin_Handled;
}

public int Handler_DeleteConfirmMenu(Menu menu, MenuAction action, int client, int selection)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(selection, info, sizeof(info));
		
		if (!StrEqual(info, "NO"))
		{
			DeleteData(client, StringToInt(info));
		}
		Command_DeleteMenu(client, -1);
	}
	else if (action == MenuAction_Cancel)
	{
		if (selection == MenuCancel_ExitBack) 
		{
			Command_DeleteMenu(client, -1);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

/*******************************************************************************************
	 Permission Menu
*******************************************************************************************/
public Action Command_PermissionMenu(int client, int args) 
{
	if (bEnabled)
	{	
		char menuinfo[255];
		Menu menu = new Menu(Handler_PermissionMenu);
			
		Format(menuinfo, sizeof(menuinfo), "TF2 Sandbox - Save System Main Menu %s\nCurrent Map: %s\n \nSet Permission on project:\n [Private]: Only you can load the project (Default)\n [Public]: Let others to load your project\n ", PLUGIN_VERSION, CurrentMap);
		menu.SetTitle(menuinfo);
		
		char cSlot[6];
		char cDate[11];
		char cPermission[8] = "Private";
		for(int iSlot = 1; iSlot <= GetConVarInt(cviStoreSlot); iSlot++)
		{
			IntToString(iSlot, cSlot, sizeof(cSlot));
			if(DataFileExist(client, iSlot))
			{
				GetDataDate(client, iSlot, cDate, sizeof(cDate));
				
				if(bPermission[client][iSlot])
					cPermission = "Public";
				else
					cPermission = "Private";
				
				Format(menuinfo, sizeof(menuinfo), " Slot %i (Stored %s, %i Props) : [%s]", iSlot, cDate, GetDataProps(client, iSlot), cPermission);	
				menu.AddItem(cSlot, menuinfo);
			}
			else
			{
				Format(menuinfo, sizeof(menuinfo), " Slot %i (No Data) : [Private]", iSlot);	
				menu.AddItem(cSlot, menuinfo, ITEMDRAW_DISABLED);
			}
		}
		
		menu.ExitBackButton = true;
		menu.ExitButton = false;
		menu.Display(client, MENU_TIME_FOREVER);
	}
	return Plugin_Handled;
}

public int Handler_PermissionMenu(Menu menu, MenuAction action, int client, int selection)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(selection, info, sizeof(info));
		
		int iSlot = StringToInt(info);
		
		if(iCoolDown[client] == 0)
		{
			if(bPermission[client][iSlot])
			{
				bPermission[client][iSlot] = false;
				Build_PrintToChat(client, "Slot\x04%i\x01 Permission have set to \x04Private\x01.", iSlot);
			}
			else
			{
				bPermission[client][iSlot] = true;
				Build_PrintToChat(client, "Slot\x04%i\x01 Permission have set to \x04Public\x01.", iSlot);
			}
			iCoolDown[client] = GetConVarInt(cviCoolDownsec);
			CreateTimer(0.05, Timer_CoolDownFunction, client);
		}
		else
		{
			Build_PrintToChat(client, "Permission Function is currently cooling down, please wait \x04%i\x01 seconds.", iCoolDown[client]);
		}
			
		Command_PermissionMenu(client, -1);
	}
	else if (action == MenuAction_Cancel)
	{
		if (selection == MenuCancel_ExitBack) 
		{
			Command_MainMenu(client, -1);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

/*******************************************************************************************
	 LoadOthers Menu
*******************************************************************************************/
public Action Command_LoadOthersMenu(int client, int args) 
{
	if (bEnabled)
	{	
		char menuinfo[255];
		Menu menu = new Menu(Handler_LoadOthersMenu);
			
		Format(menuinfo, sizeof(menuinfo), "TF2 Sandbox - Save System Main Menu %s\nCurrent Map: %s\n \nLoad others project,\nPlease select a Player:\n ", PLUGIN_VERSION, CurrentMap);
		menu.SetTitle(menuinfo);
		
		char cClient[4];
		char cName[48];
		for(int i = 1; i < MAXPLAYERS; i++)
		{
			if(IsValidClient(i) && i != client && !IsFakeClient(i))
			{	
				IntToString(i, cClient, sizeof(cClient));
				GetClientName(i, cName, sizeof(cName));
				
				Format(menuinfo, sizeof(menuinfo), " %s", cName);	
				menu.AddItem(cClient, menuinfo);
			}
		}

		menu.ExitBackButton = true;
		menu.ExitButton = false;
		menu.Display(client, MENU_TIME_FOREVER);
	}
	return Plugin_Handled;
}

public int Handler_LoadOthersMenu(Menu menu, MenuAction action, int client, int selection)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(selection, info, sizeof(info));
		
		int iClient = StringToInt(info);
		
		if(IsValidClient(iClient))
		{
			Command_LoadOthersProjectsMenu(client, iClient);
			iSelectedClient[client] = iClient;
		}
		else
		{
			Build_PrintToChat(client, "Error: Client %i not found", iClient);
			Command_LoadOthersMenu(client, -1);
		}
	}
	else if (action == MenuAction_Cancel)
	{
		if (selection == MenuCancel_ExitBack) 
		{
			Command_MainMenu(client, -1);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}

/*******************************************************************************************
	 LoadOthersProjects Menu
*******************************************************************************************/
public Action Command_LoadOthersProjectsMenu(int client, int selectedclient) //client, selected client
{
	if (bEnabled)
	{	
		char menuinfo[255];
		Menu menu = new Menu(Handler_LoadOthersProjectsMenu);
			
		char cSelectedclentName[48];
		if(IsValidClient(selectedclient))		
			GetClientName(selectedclient, cSelectedclentName, sizeof(cSelectedclentName));
		else
		{
			Build_PrintToChat(client, "Error: Client %i not found", selectedclient);
			Command_LoadOthersMenu(client, -1);
		}
			
		Format(menuinfo, sizeof(menuinfo), "TF2 Sandbox - Save System Main Menu %s\nCurrent Map: %s\n \nSelected Player: %s\n \nSelect a Slot to LOAD....", PLUGIN_VERSION, CurrentMap, cSelectedclentName);
		menu.SetTitle(menuinfo);
		
		char cSlot[6];
		char cDate[11];
		char cPermission[8] = "Private";
		for(int iSlot = 1; iSlot <= GetConVarInt(cviStoreSlot); iSlot++)
		{
			IntToString(iSlot, cSlot, sizeof(cSlot));
			if(DataFileExist(selectedclient, iSlot))
			{
				GetDataDate(selectedclient, iSlot, cDate, sizeof(cDate));
				
				if(bPermission[selectedclient][iSlot])
				{
					cPermission = "Public";
					Format(menuinfo, sizeof(menuinfo), " Slot %i (Stored %s, %i Props) : [%s]", iSlot, cDate, GetDataProps(selectedclient, iSlot), cPermission);
					menu.AddItem(cSlot, menuinfo);					
				}
				else
				{
					cPermission = "Private";
					Format(menuinfo, sizeof(menuinfo), " Slot %i (Stored %s, %i Props) : [%s]", iSlot, cDate, GetDataProps(selectedclient, iSlot), cPermission);	
					menu.AddItem(cSlot, menuinfo, ITEMDRAW_DISABLED);
				}
			}
			else
			{
				Format(menuinfo, sizeof(menuinfo), " Slot %i (No Data) : [Private]", iSlot);	
				menu.AddItem(cSlot, menuinfo, ITEMDRAW_DISABLED);
			}
		}
		
		menu.ExitBackButton = true;
		menu.ExitButton = false;
		menu.Display(client, MENU_TIME_FOREVER);
	}
	return Plugin_Handled;
}

public int Handler_LoadOthersProjectsMenu(Menu menu, MenuAction action, int client, int selection)
{
	if (action == MenuAction_Select)
	{
		char info[32];
		menu.GetItem(selection, info, sizeof(info));
		
		int iSlot = StringToInt(info);
		
		if(IsValidClient(iSelectedClient[client]))
		{
			if(iCoolDown[client] == 0)
			{
				
				LoadData(client, iSelectedClient[client], iSlot);
				
				char cName[48];
				GetClientName(client, cName, sizeof(cName));
				Build_PrintToChat(iSelectedClient[client], "Player \x04%s\x01 have load your Slot\x04%i\x01!", cName, iSlot);
				PrintCenterText(iSelectedClient[client], "Player %s have load your Slot %i!", cName, iSlot);
				iCoolDown[client] = GetConVarInt(cviCoolDownsec);
				CreateTimer(0.05, Timer_CoolDownFunction, client);
			}
			else
			{
				Build_PrintToChat(client, "Load Function is currently cooling down, please wait \x04%i\x01 seconds.", iCoolDown[client]);
			}
		}
		
		Command_LoadOthersProjectsMenu(client, iSelectedClient[client]);
	}
	else if (action == MenuAction_Cancel)
	{
		if (selection == MenuCancel_ExitBack) 
		{
			Command_LoadOthersMenu(client, -1);
		}
	}
	else if (action == MenuAction_End)
	{
		delete menu;
	}
}


/*******************************************************************************************
	 Stock
*******************************************************************************************/
//-----------[ Load data Function ]--------------------------------------------------------------------------------------
void LoadData(int loader, int client, int slot)  // Load Data from data file (loader, client in data file, slot number)
{
	char cFileName[255];
	GetBuildPath(client, slot, cFileName);
		
	LoadFunction(loader, slot, cFileName);
}

void LoadDataSteamID(int loader, char[] SteamID64, int slot)  // Load Data from data file (loader, client steamid64 in data file, slot number)
{
	char cFileName[255];
	BuildPath(Path_SM, cFileName, sizeof(cFileName), "data/TF2SBSaveSystem/%s&%s@%i.tf2sb", CurrentMap, SteamID64, slot);
	
	LoadFunction(loader, slot, cFileName);
}

void LoadFunction(int loader, int slot, char[] cFileName)
{
	if(DataFileExist(loader, slot))
	{
		if(g_hFileEditting[loader] == INVALID_HANDLE)
		{
			g_hFileEditting[loader] = OpenFile(cFileName, "r");
			
			float fOrigin[3], fAngles[3];
			char szModel[128], szClass[64], szBuffer[18][255];
			int g_iCountEntity = 0;
			int g_iCountLoop = 0;
			int Obj_LoadEntity = -1; 
			
			char szLoadString[255];
			int max = GetMaxEntities();
			for(int i = MaxClients; i < max; i++)
			{
				if (ReadFileLine(g_hFileEditting[loader], szLoadString, sizeof(szLoadString))) 
				{
					if (StrContains(szLoadString, "ent") != -1 && StrContains(szLoadString, ";") == -1) //Map name have ent sytax??? Holy
					{
						ExplodeString(szLoadString, " ", szBuffer, 10, 255);
						Format(szClass, sizeof(szClass), "%s", szBuffer[1]);
						Format(szModel, sizeof(szModel), "%s", szBuffer[2]);
						fOrigin[0] = StringToFloat(szBuffer[3]);
						fOrigin[1] = StringToFloat(szBuffer[4]);
						fOrigin[2] = StringToFloat(szBuffer[5]);
						fAngles[0] = StringToFloat(szBuffer[6]);
						fAngles[1] = StringToFloat(szBuffer[7]);
						fAngles[2] = StringToFloat(szBuffer[8]);
						//iHealth = StringToInt(szBuffer[9]);
						//if (iHealth == 2)
						//	iHealth = 999999999;
						//if (iHealth == 1)
						//	iHealth = 50;
						if (StrContains(szClass, "prop_dynamic") >= 0) 
						{
							Obj_LoadEntity = CreateEntityByName("prop_dynamic_override");
							SetEntProp(Obj_LoadEntity, Prop_Send, "m_nSolidType", 6);
							SetEntProp(Obj_LoadEntity, Prop_Data, "m_nSolidType", 6);
						} 
						else if (StrEqual(szClass, "prop_physics"))
							Obj_LoadEntity = CreateEntityByName("prop_physics_override");
						else if (StrContains(szClass, "prop_physics") >= 0)
							Obj_LoadEntity = CreateEntityByName(szClass);
						
						if (Obj_LoadEntity != -1) 
						{
							if (Build_RegisterEntityOwner(Obj_LoadEntity, loader)) 
							{
								if (!IsModelPrecached(szModel))
									PrecacheModel(szModel);
								
								
								
								DispatchKeyValue(Obj_LoadEntity, "model", szModel);
								TeleportEntity(Obj_LoadEntity, fOrigin, fAngles, NULL_VECTOR);
								DispatchSpawn(Obj_LoadEntity);
								//SetVariantInt(iHealth);
								//AcceptEntityInput(Obj_LoadEntity, "sethealth", -1);
								//AcceptEntityInput(Obj_LoadEntity, "disablemotion", -1);
								g_iCountEntity++;
								
								//light bulb
								if(StrEqual(szModel, "models/props_2fort/lightbulb001.mdl"))
								{
									//char 
									//fAngles[1] = StringToFloat(szBuffer[9]); //brightness
									//fAngles[2] = StringToFloat(szBuffer[10]); //Red
									//fAngles[2] = StringToFloat(szBuffer[10]); //Green
									//fAngles[2] = StringToFloat(szBuffer[10]); //Blue

									int Obj_LightDynamic = CreateEntityByName("light_dynamic");
									
									char szColor[32];
									Format(szColor, sizeof(szColor), "255 255 255");
									
									SetVariantString("500");
									AcceptEntityInput(Obj_LightDynamic, "distance", -1);
									SetVariantString("7");
									AcceptEntityInput(Obj_LightDynamic, "brightness", -1);
									SetVariantString("2");
									AcceptEntityInput(Obj_LightDynamic, "style", -1);
									SetVariantString(szColor);
									AcceptEntityInput(Obj_LightDynamic, "color", -1);
									
									if (Obj_LightDynamic != -1) 
									{
										DispatchSpawn(Obj_LightDynamic);
										TeleportEntity(Obj_LightDynamic, fOrigin, fAngles, NULL_VECTOR);
										
										char szNameMelon[64];
										Format(szNameMelon, sizeof(szNameMelon), "Obj_LoadEntity%i", GetRandomInt(1000, 5000));
										DispatchKeyValue(Obj_LoadEntity, "targetname", szNameMelon);
										SetVariantString(szNameMelon);
										AcceptEntityInput(Obj_LightDynamic, "setparent", -1);
										AcceptEntityInput(Obj_LightDynamic, "turnon", loader, loader);
									}	
								}
							} 
							else 
							{
								RemoveEdict(Obj_LoadEntity);
							}
						}
						g_iCountLoop++;
					}
					if(IsEndOfFile(g_hFileEditting[loader]))
					{
						break;
					}
				}
			}
			int g_iErrorEntity = g_iCountLoop -g_iCountEntity;
			Build_PrintToChat(loader, "Load Result >> Loaded: \x04%i\x01, Error: \x04%i\x01 >> Loaded Slot\x04%i\x01", g_iCountEntity, g_iErrorEntity, slot);
			CloseHandle(g_hFileEditting[loader]);
			g_hFileEditting[loader] = INVALID_HANDLE;
		}
	}
}


//-----------[ Save data Function ]-------------------------------------
void SaveData(int client, int slot)  // Save Data from data file
{
	char SteamID64[64];
	GetClientAuthId(client, AuthId_SteamID64, SteamID64, sizeof(SteamID64), true);
	
	char cFileName[255];
	BuildPath(Path_SM, cFileName, sizeof(cFileName), "data/TF2SBSaveSystem/%s&%s@%i.tf2sb", CurrentMap, SteamID64, slot);
	
	int g_iCountEntity = -1;
	if(g_hFileEditting[client] == INVALID_HANDLE)
	{
		g_iCountEntity = 0;
		//----------------------------------------------------Open file and start write--------------------------------------------------------------
		g_hFileEditting[client] = OpenFile(cFileName, "w");
		
		float fOrigin[3], fAngles[3];
		char szModel[64], szClass[64];
		int iOrigin[3], iAngles[3];
		
		char szTime[64];
		FormatTime(szTime, sizeof(szTime), "%Y/%m/%d");
		
		char cName[64];
		GetClientName(client, cName, sizeof(cName));
		
		WriteFileLine(g_hFileEditting[client], ";--- Saved Map: %s", CurrentMap);
		WriteFileLine(g_hFileEditting[client], ";--- SteamID64: %s (%s)", SteamID64 , cName);
		WriteFileLine(g_hFileEditting[client], ";--- Data Slot: %i", slot);
		WriteFileLine(g_hFileEditting[client], ";--- Saved on : %s", szTime);
		for (int i = 0; i < MAX_HOOK_ENTITIES; i++) 
		{
			if (IsValidEdict(i))
			{
				GetEdictClassname(i, szClass, sizeof(szClass));
				if ((StrContains(szClass, "prop_dynamic") >= 0 || StrContains(szClass, "prop_physics") >= 0) && !StrEqual(szClass, "prop_ragdoll") && Build_ReturnEntityOwner(i) == client) 
				{
					GetEntPropString(i, Prop_Data, "m_ModelName", szModel, sizeof(szModel));
					GetEntPropVector(i, Prop_Send, "m_vecOrigin", fOrigin);
					GetEntPropVector(i, Prop_Data, "m_angRotation", fAngles);
					for (int j = 0; j < 3; j++) 
					{
						iOrigin[j] = RoundToNearest(fOrigin[j]);
						iAngles[j] = RoundToNearest(fAngles[j]);
					}
					/*
					iHealth = GetEntProp(i, Prop_Data, "m_iHealth", 4);
					if (iHealth > 100000000)
						iHealth = 2;
					else if (iHealth > 0)
						iHealth = 1;
					else
						iHealth = 0;
					*/
					g_iCountEntity++;
					//if(StrEqual(szModel, "models/props_2fort/lightbulb001.mdl"))
					//{
					//	WriteFileLine(g_hFileEditting[client], "ent%i %s %s %f %f %f %f %f %f"
					//	, g_iCountEntity, szClass, szModel, fOrigin[0], fOrigin[1], fOrigin[2], fAngles[0], fAngles[1], fAngles[2]);
					//}
					//else
					WriteFileLine(g_hFileEditting[client], "ent%i %s %s %f %f %f %f %f %f", g_iCountEntity, szClass, szModel, fOrigin[0], fOrigin[1], fOrigin[2], fAngles[0], fAngles[1], fAngles[2]);
				}
			}
		}
		WriteFileLine(g_hFileEditting[client], ";--- Data File End | %i Props Saved", g_iCountEntity);
		WriteFileLine(g_hFileEditting[client], ";--- File Generated By TF2SB-SaveSystem.smx v%s", g_iCountEntity, PLUGIN_VERSION);
		
		FlushFile(g_hFileEditting[client]);
		//-------------------------------------------------------------Close file-------------------------------------------------------------------
		CloseHandle(g_hFileEditting[client]);
		g_hFileEditting[client] = INVALID_HANDLE;
		
		if(DataFileExist(client, slot) && g_iCountEntity == 0)
		{
			Build_PrintToChat(client, "Save Result >> ERROR!!!. You didnt build anything, please build something and save again.");
			DeleteFile(cFileName);
		}
		else
		{
			Build_PrintToChat(client, "Save Result >> Saved: \x04%i\x01, Error:\x04 0\x01 >> Saved in Slot\x04%i\x01", g_iCountEntity, slot);
		}
	}
	if(g_iCountEntity == -1)
		Build_PrintToChat(client, "Save Result >> ERROR!!! >> Error in Slot\x04%i\x01, please contact server admin.", slot);
}


//-----------[ Delete data Function ]-----------------------------------
void DeleteData(int client, int slot) // Delete Data from data file
{
	char cFileName[255];
	GetBuildPath(client, slot, cFileName);
	
	if(DataFileExist(client, slot))
	{
		DeleteFile(cFileName);
		
		if(DataFileExist(client, slot))
			Build_PrintToChat(client, "Fail to deleted Slot\x04%i\x01 Data, please contact server admin.", slot);
		else
			Build_PrintToChat(client, "Deleted Slot\x04%i\x01 Data successfully", slot);
	}
}


//-----------[ Get data Function ]----------------------------------------------------------------------------------
void GetDataDate(int client, int slot, char[] data, int maxlength) //Get the date inside the data file
{
	char cFileName[255];
	GetBuildPath(client, slot, cFileName);	
	
	if(DataFileExist(client, slot))
	{
		if(g_hFileEditting[client] == INVALID_HANDLE)
		{
			char cDate[11], szBuffer[6][255];
			char szLoadString[255];
			g_hFileEditting[client] = OpenFile(cFileName, "r");
			for(int i = 1; i < MAX_HOOK_ENTITIES; i++)
			{
				if (ReadFileLine(g_hFileEditting[client], szLoadString, sizeof(szLoadString))) 
				{
					if (StrContains(szLoadString, "Saved on :") != -1)
					{
						ExplodeString(szLoadString, " ", szBuffer, 6, 255);
						Format(cDate, sizeof(cDate), "%s", szBuffer[4]);
						strcopy(data, maxlength, cDate);
						break;
					}
				}
			}
			CloseHandle(g_hFileEditting[client]);
			g_hFileEditting[client] = INVALID_HANDLE;
		}
	}
}

int GetDataProps(int client, int slot) //Get how many props inside data file
{
	char cFileName[255];
	GetBuildPath(client, slot, cFileName);		

	if(DataFileExist(client, slot))
	{
		if(g_hFileEditting[client] == INVALID_HANDLE)
		{
			int iProps;
			char szBuffer[9][255];
			char szLoadString[255];
			g_hFileEditting[client] = OpenFile(cFileName, "r");
			for(int i = 1; i < MAX_HOOK_ENTITIES; i++)
			{
				if (ReadFileLine(g_hFileEditting[client], szLoadString, sizeof(szLoadString))) 
				{
					if (StrContains(szLoadString, "Data File End |") != -1)
					{
						ExplodeString(szLoadString, " ", szBuffer, 9, 255);
						
						iProps = StringToInt(szBuffer[5]);
						break;
					}
				}
			}
			CloseHandle(g_hFileEditting[client]);
			g_hFileEditting[client] = INVALID_HANDLE;
			return iProps;
		}
	}
	return -1;
}

void GetBuildPath(int client, int slot, char[] cFileNameout) //Get the sourcemod Build path
{
	char SteamID64[64];
	GetClientAuthId( client, AuthId_SteamID64, SteamID64, sizeof(SteamID64), true);
	
	char cFileName[255];
	BuildPath(Path_SM, cFileName, sizeof(cFileName), "data/TF2SBSaveSystem/%s&%s@%i.tf2sb", CurrentMap, SteamID64, slot);
	
	strcopy(cFileNameout, sizeof(cFileName), cFileName);
}


//-----------[ Check Function ]--------------------------------------------------------
bool DataFileExist(int client, int slot) //Is the data file exist? true : false 
{
	char cFileName[255];
	GetBuildPath(client, slot, cFileName);
	
 	if(FileExists(cFileName))
 	{
 		return true;
 	}
 	return false;
} 

stock bool IsValidClient(int client) 
{ 
    if(client <= 0 ) return false; 
    if(client > MaxClients) return false; 
    if(!IsClientConnected(client)) return false; 
    return IsClientInGame(client); 
}

int GetClientInGame()
{ 
	int iCount = 0;
	for(int i = 1; i < MAXPLAYERS; i++)
	{
		if(IsValidClient(i) && !IsFakeClient(i))
		{	
			iCount++;
		}
	}
	return iCount;
}
