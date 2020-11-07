void LoadFF2Plugins()
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "plugins/freaks");
	
	DirectoryListing hDir = OpenDirectory(path);
	FileType fileType;
	
	while ( hDir.GetNext(path, sizeof(path), fileType) ) {
		if ( fileType == FileType_File && StrContains(path, ".ff2") != -1 ) {
			ServerCommand("sm plugins load freaks\\%s", path);
		}
	}
	
	delete hDir;
}

void UnloadFF2Plugins()
{
	char path[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, path, sizeof(path), "plugins/freaks");
	
	DirectoryListing hDir = OpenDirectory(path);
	FileType fileType;
	
	while ( hDir.GetNext(path, sizeof(path), fileType) ) {
		if ( fileType == FileType_File && StrContains(path, ".ff2") != -1 ) {
			ServerCommand("sm plugins unload freaks\\%s", path);
		}
	}
	
	delete hDir;
}

void ProcessOnCallDownload()
{
	///	Precache Sounds
	{
		StringMapSnapshot snap = ff2_cfgmgr.Snapshot();
		StringMapSnapshot snap_list;
		
		FF2SoundList list;
		FF2Identity identity;
		FF2SoundIdentity snd_id;
		ConfigMap model_precache;
		
		char _key[32];
		char model_path[PLATFORM_MAX_PATH];
		
		for (int i = snap.Length - 1; i >= 0; i--) {
			snap.GetKey(i, _key, sizeof(_key));
			ff2_cfgmgr.GetIdentity(_key, identity);
			
			/// Precache SoundList
			{
				snap_list = identity.sndHash.Snapshot();
			
				for (int j = snap_list.Length - 1; j >= 0; j--) {
					snap_list.GetKey(j, _key, sizeof(_key));
					list = identity.sndHash.GetList(_key);
					
					for (int k = list.Length - 1; k >= 0; k--) {
						list.At(k, snd_id);
						if (snd_id.path[0]) {
							PrecacheSound(snd_id.path);
						}
					}
				}
				
				delete snap_list;
			}
			
			/// Precache Models
			if( (model_precache = identity.hCfg.GetSection("mod_precache")) ) {
				int pos = model_precache.Size - 1;
				for( ; pos >= 0; pos-- ) {
					IntToString(pos, _key, sizeof(_key));
					if( model_precache.Get(_key, model_path, sizeof(model_path)) && model_path[0] )
						PrecacheModel(model_path);
				}
			}
			
		}
		
		delete snap;
	}
}

void Call_FF2OnAbility(const FF2Player player, FF2CallType_t call_type)
{
	static char cfg_key[64];
	static char curKey[64];
	static char pl_ab[2][MAX_SUBPLUGIN_NAME];
	
	ConfigMap cfg = player.iCfg;
	
	FF2CallType_t cur_type;
	
	static FF2AbilityList list; list = player.HookedAbilities;
	if( !list ) return;
	
	StringMapSnapshot snap = list.Snapshot();
	for ( int i = 0; i < snap.Length; i++ ) {
	
		snap.GetKey(i, curKey, sizeof(curKey));
		list.GetString(curKey, cfg_key, sizeof(cfg_key));
		
		cur_type = CT_NONE;
		FormatEx(pl_ab[0], sizeof(pl_ab[]), "%s.slot", cfg_key);
		if( !cfg.GetInt(pl_ab[0], view_as<int>(cur_type)) ) {
			FormatEx(pl_ab[0], sizeof(pl_ab[]), "%s.arg0", cfg_key);
			if ( !cfg.GetInt(pl_ab[0], view_as<int>(cur_type)) )
				cur_type = CT_RAGE;
		}
		
		if( !(cur_type & call_type) )
			continue;
		
		FF2AbilityList.GetKeyVal(curKey, pl_ab);
		
		Call_StartForward(ff2.m_forwards[FF2OnPreAbility]);
		Call_PushCell(player);
		Call_PushString(pl_ab[0]);
		Call_PushString(pl_ab[1]);
		Call_PushCell(call_type);
		bool enabled = true;
		Call_PushCellRef(enabled);
		Call_Finish();
		
		if(!enabled) {
			continue;
		}
		
		Call_StartForward(ff2.m_forwards[FF2OnAbility]);
		Call_PushCell(player);
		Call_PushString(pl_ab[0]);
		Call_PushString(pl_ab[1]);
		Call_PushCell(call_type);
		Call_Finish();
	}
	
	delete snap;
}

bool RandomAbilitySound(FF2SoundList list, FF2CallType_t slot, char[] res, int maxlen)
{
	if ( !list ) return false;
	
	int[] slots = new int[15];
	int count;
	FF2CallType_t cur_slot;
	
	char name[6]; FormatEx(name, sizeof(name), "slot%i", slot);
	FF2SoundIdentity curEntry;
	
	for (int i = list.Length - 1; i >= 0 && count < 15; i--) {
		list.At(i, curEntry);
		
		int pos = FindCharInString(curEntry.name, '_', true);
		cur_slot = view_as<FF2CallType_t>(StringToInt(curEntry.name[pos + 1]));
		
		if ( cur_slot & slot ) {
			slots[count++] = i;
		}
	}
	
	if ( !count ) return false;
	
	list.At(slots[GetRandomInt(0, count - 1)], curEntry);
	FormatEx(res, maxlen, "%s", curEntry.path);
	
	return true;
}
