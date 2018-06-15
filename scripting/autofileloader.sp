//Pragma
#pragma semicolon 1
#pragma newdecls required

//Defines
//#define DEBUG
#define PLUGIN_DESCRIPTION "Automatically takes custom files and precaches them and adds them to the downloads table."
#define PLUGIN_VERSION "1.0.3"

//Sourcemod Includes
#include <sourcemod>
#include <sdktools>

//Globals
ConVar cvar_Status;
ConVar cvar_Exclusions;

ArrayList array_Exclusions;
ArrayList array_Downloadables;

enum eLoad
{
	Load_Materials,
	Load_Models,
	Load_Sounds
}

public Plugin myinfo =
{
	name = "Auto File Loader",
	author = "Keith Warren (Shaders Allen)",
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = "http://www.shadersallen.com/"
};

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	//LoadTranslations("_.phrases");

	CreateConVar("sm_autofileloader_version", PLUGIN_VERSION, PLUGIN_DESCRIPTION, FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_SPONLY | FCVAR_DONTRECORD);
	cvar_Status = CreateConVar("sm_autofileloader_status", "1", "Status of the plugin.", FCVAR_NOTIFY, true, 0.0, true, 1.0);
	cvar_Exclusions = CreateConVar("sm_autofileloader_exclusions_file", "configs/afl_exclusions.cfg", "File location to use for the exclusions config.", FCVAR_NOTIFY);

	//AutoExecConfig();

	array_Exclusions = CreateArray(ByteCountToCells(PLATFORM_MAX_PATH));

	array_Downloadables = CreateArray(ByteCountToCells(6));
	PushArrayString(array_Downloadables, ".vmt");
	PushArrayString(array_Downloadables, ".vtf");
	PushArrayString(array_Downloadables, ".vtx");
	PushArrayString(array_Downloadables, ".mdl");
	PushArrayString(array_Downloadables, ".phy");
	PushArrayString(array_Downloadables, ".vvd");
	PushArrayString(array_Downloadables, ".wav");
	PushArrayString(array_Downloadables, ".mp3");

	RegAdminCmd("sm_generateexternals", Command_GenerateExternals, ADMFLAG_ROOT);
	RegAdminCmd("sm_ge", Command_GenerateExternals, ADMFLAG_ROOT);
}

public void OnMapStart()
{
	if (!GetConVarBool(cvar_Status))
	{
		return;
	}

	PullExclusions();
	StartProcess();
}

void StartProcess(bool print = false)
{
	//Load the base directory's files.
	AutoLoadDirectory(".", print);

	//Load all the folders inside of the custom folder and load their files.
	DirectoryListing dir = OpenDirectory("custom");
	if (dir != null)
	{
		FileType fType;
		char sPath[PLATFORM_MAX_PATH];

		while (ReadDirEntry(dir, sPath, sizeof(sPath), fType))
		{
			//We only need to parse through directories here.
			if (fType != FileType_Directory)
			{
				continue;
			}

			//Exclude these paths since they're invalid.
			if (StrEqual(sPath, "workshop") || StrEqual(sPath, ".") || StrEqual(sPath, ".."))
			{
				continue;
			}

			char sBuffer[PLATFORM_MAX_PATH];
			Format(sBuffer, sizeof(sBuffer), "custom/%s", sPath);

			AutoLoadDirectory(sBuffer, print);
		}

		delete dir;
	}
}

bool AutoLoadDirectory(const char[] path, bool print = false)
{
	DirectoryListing dir = OpenDirectory(path);

	if (dir == null)
	{
		return false;
	}

	char sPath[PLATFORM_MAX_PATH];
	FileType fType;

	while (ReadDirEntry(dir, sPath, sizeof(sPath), fType))
	{
		//We only need to parse through directories here.
		if (fType != FileType_Directory)
		{
			continue;
		}

		char sBuffer[PLATFORM_MAX_PATH];
		Format(sBuffer, sizeof(sBuffer), "%s/%s", path, sPath);

		if (StrEqual(sPath, "materials"))
		{
			AutoLoadFiles(sBuffer, path, Load_Materials, print);
		}
		else if (StrEqual(sPath, "models"))
		{
			AutoLoadFiles(sBuffer, path, Load_Models, print);
		}
		else if (StrEqual(sPath, "sound"))
		{
			AutoLoadFiles(sBuffer, path, Load_Sounds, print);
		}
	}

	delete dir;
	return true;
}

bool AutoLoadFiles(const char[] path, const char[] remove, eLoad load, bool print = false)
{
	#if defined DEBUG
	LogToFileEx("addons/sourcemod/logs/autofileloader.debug.log", "Loading Directory: %s - %s - %i", path, remove, load);
	#endif

	DirectoryListing dir = OpenDirectory(path);

	if (dir == null)
	{
		return false;
	}

	char sPath[PLATFORM_MAX_PATH];
	FileType fType;

	while (ReadDirEntry(dir, sPath, sizeof(sPath), fType))
	{
		//Exclude these paths since they're invalid.
		if (StrEqual(sPath, "..") || StrEqual(sPath, "."))
		{
			continue;
		}

		char sBuffer[PLATFORM_MAX_PATH];
		Format(sBuffer, sizeof(sBuffer), "%s/%s", path, sPath);

		//Check if we're on the exclusion list and if we are, skip us.
		if (FindStringInArray(array_Exclusions, sBuffer) != -1)
		{
			continue;
		}

		switch (fType)
		{
			case FileType_Directory:
			{
				//This is a directory so we should recursively auto load its files the same way.
				AutoLoadFiles(sBuffer, remove, load, print);
			}

			case FileType_File:
			{
				//Some paths don't need to be absolute due to how precache functions work with Sourcemod.
				ReplaceString(sBuffer, sizeof(sBuffer), remove, "");
				RemoveFrontString(sBuffer, sizeof(sBuffer), 1);
				
				#if defined DEBUG
				LogToFileEx("addons/sourcemod/logs/autofileloader.debug.log", "Adding To Downloads Table: %s", sBuffer);
				#endif

				//Add this file to the downloads table if it has a valid extension.
				for (int i = 0; i < GetArraySize(array_Downloadables); i++)
				{
					char sExtension[6];
					GetArrayString(array_Downloadables, i, sExtension, sizeof(sExtension));

					if (StrContains(sBuffer, sExtension) != -1)
					{
						if (print)
						{
							LogToFileEx2("addons/sourcemod/logs/autofileloader.generate.log", "%s", sBuffer);
						}
						
						AddFileToDownloadsTable(sBuffer);
						break;
					}
				}

				switch (load)
				{
					case Load_Materials:
					{
						if (StrContains(sPath, "decals") != -1)
						{
							#if defined DEBUG
							LogToFileEx("addons/sourcemod/logs/autofileloader.debug.log", "Precaching Decal: %s", sBuffer);
							#endif
							
							PrecacheDecal(sBuffer);
						}
					}

					case Load_Models:
					{
						//We only need to precache the MDL file itself.
						if (StrContains(sPath, ".mdl") != -1)
						{
							#if defined DEBUG
							LogToFileEx("addons/sourcemod/logs/autofileloader.debug.log", "Precaching Model: %s", sBuffer);
							#endif
							
							PrecacheModel(sBuffer);
						}
					}

					case Load_Sounds:
					{
						if (StrContains(sPath, ".wav") != -1 || StrContains(sPath, ".mp3") != -1)
						{
							#if defined DEBUG
							LogToFileEx("addons/sourcemod/logs/autofileloader.debug.log", "Precaching Sound: %s", sBuffer);
							#endif
							
							ReplaceString(sBuffer, sizeof(sBuffer), "sound/", "");
							PrecacheSound(sBuffer);
						}
					}
				}
			}
		}
	}

	delete dir;
	return true;
}

stock void LogToFileEx2(const char[] file_location, const char[] format, any ...)
{
	char sBuffer[1024];
	VFormat(sBuffer, sizeof(sBuffer), format, 3);
	
	Handle file = OpenFile(file_location,"a");
	
	if (file != null)
	{
		WriteFileLine(file, sBuffer);
	}
	
	CloseHandle(file);
}

stock void RemoveFrontString(char[] strInput, int iSize, int iVar)
{
	strcopy(strInput, iSize, strInput[iVar]);
}

public Action Command_GenerateExternals(int client, int args)
{
	StartProcess(true);
	ReplyToCommand(client, "Generated, file should be under 'addons/sourcemod/logs/autofileloader.generate.log'.");
	return Plugin_Handled;
}

void PullExclusions()
{
	//Lets handle the excludions.
	char sExclusionPath[PLATFORM_MAX_PATH];
	GetConVarString(cvar_Exclusions, sExclusionPath, sizeof(sExclusionPath));

	char sPath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, sPath, sizeof(sPath), sExclusionPath);

	KeyValues kv = CreateKeyValues("autofileloader_exclusions");

	if (FileToKeyValues(kv, sPath))
	{
		//Config exists, lets clear the exclusions now so we can pull the new list.
		ClearArray(array_Exclusions);

		//If this returns empty, the file is empty so we don't do anything.
		if (KvGotoFirstSubKey(kv, false))
		{
			do
			{
				//The key is kind of pointless so we make it had a meaning by making it a status for enabled or disabled.
				char sEnabled[1];
				KvGetSectionName(kv, sEnabled, sizeof(sEnabled));

				if (StringToInt(sEnabled))
				{
					char sExclude[PLATFORM_MAX_PATH];
					KvGetString(kv, NULL_STRING, sExclude, sizeof(sExclude));

					if (strlen(sExclude) > 0)
					{
						PushArrayString(array_Exclusions, sExclude);
					}
				}
			}
			while(KvGotoNextKey(kv, false));
		}
	}
	else
	{
		//Config doesn't exist, lets create it.
		KeyValuesToFile(kv, sPath);
	}

	delete kv;
}
