#pragma semicolon 1
#pragma newdecls required

#define DEBUG

#define PLUGIN_DESCRIPTION "Automatically takes custom files and precaches them and adds them to the downloads table."
#define PLUGIN_VERSION "1.0.0"

#include <sourcemod>
#include <sdktools>

ConVar cvar_Status;
ConVar cvar_Exclusions;

ArrayList array_Exclusions;

enum eLoad
{
	Load_Materials,
	Load_Models,
	Load_Sounds
}

public Plugin myinfo =
{
	name = "Auto File Loader",
	author = "Keith Warren (Drixevel)",
	description = PLUGIN_DESCRIPTION,
	version = PLUGIN_VERSION,
	url = "http://www.drixevel.com/"
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
}

public void OnConfigsExecuted()
{
	if (!GetConVarBool(cvar_Status))
	{
		return;
	}

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

	//Load the base directory's files.
	AutoLoadDirectory(".");

	//Load all the folders inside of the custom folder and load their files.
	DirectoryListing dir = OpenDirectory("custom");
	FileType fType;

	while (ReadDirEntry(dir, sPath, sizeof(sPath), fType))
	{
		//Exclude these paths since they're invalid.
		if (StrEqual(sPath, "workshop") || StrEqual(sPath, "readme.txt") || StrEqual(sPath, "..") || StrEqual(sPath, "."))
		{
			continue;
		}

		char sBuffer[PLATFORM_MAX_PATH];
		Format(sBuffer, sizeof(sBuffer), "custom/%s", sPath);

		AutoLoadDirectory(sBuffer);
	}

	delete dir;
}

bool AutoLoadDirectory(const char[] path)
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
		//From here, we only need to parse directories so if it's a file, skip it.
		if (fType != FileType_Directory)
		{
			continue;
		}

		char sBuffer[PLATFORM_MAX_PATH];
		Format(sBuffer, sizeof(sBuffer), "%s/%s", path, sPath);

		if (StrEqual(sPath, "materials"))
		{
			AutoLoadFiles(sBuffer, path, Load_Materials);
		}
		else if (StrEqual(sPath, "models"))
		{
			AutoLoadFiles(sBuffer, path, Load_Models);
		}
		else if (StrEqual(sPath, "sound"))
		{
			AutoLoadFiles(sBuffer, path, Load_Sounds);
		}
	}

	delete dir;
	return true;
}

bool AutoLoadFiles(const char[] path, const char[] remove, eLoad load)
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

		if (fType == FileType_Directory)
		{
			//This is a directory so we should recursively auto load its files the same way.
			AutoLoadFiles(sBuffer, remove, load);
		}
		else if (fType == FileType_File)
		{
			//Random file, lets skip it.
			if (StrEqual(sBuffer, "sound.cache"))
			{
				continue;
			}

			ReplaceString(sBuffer, sizeof(sBuffer), remove, "");
			RemoveFrontString(sBuffer, sizeof(sBuffer), 1);

			//Add this file to the downloads table.
			AddFileToDownloadsTable(sBuffer);

			#if defined DEBUG
			LogToFileEx("addons/sourcemod/logs/autofileloader.debug.log", "Adding To Downloads Table: %s", sBuffer);
			#endif

			switch (load)
			{
				case Load_Materials:
				{
					//TODO: Figure out IF material files should be precached as decals.
					//PrecacheDecal(sBuffer);
				}

				case Load_Models:
				{
					//We only need to precache the MDL file itself.
					if (StrContains(sPath, ".mdl") != -1)
					{
						PrecacheModel(sBuffer);

						#if defined DEBUG
						LogToFileEx("addons/sourcemod/logs/autofileloader.debug.log", "Precaching Model: %s", sBuffer);
						#endif
					}
				}

				case Load_Sounds:
				{
					ReplaceString(sBuffer, sizeof(sBuffer), "sound/", "");
					PrecacheSound(sBuffer);

					#if defined DEBUG
					LogToFileEx("addons/sourcemod/logs/autofileloader.debug.log", "Precaching Sound: %s", sBuffer);
					#endif
				}
			}
		}
	}

	delete dir;
	return true;
}

stock void RemoveFrontString(char[] strInput, int iSize, int iVar)
{
	strcopy(strInput, iSize, strInput[iVar]);
}
