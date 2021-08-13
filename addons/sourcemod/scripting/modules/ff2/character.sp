methodmap FF2Character {
	public FF2Character(ConfigMap cfg) {
		return view_as<FF2Character>(cfg.GetSection(FF2_CHARACTER_KEY));
	}

	property ConfigMap Config {
		public get() { return( view_as<ConfigMap>(this) ); }
	}

	property ConfigMap InfoSection {
		public get() { return( this.Config.GetSection("info") ); }
	}

	property ConfigMap WeaponSection {
		public get() { return( this.Config.GetSection("info") ); }
	}

	property ConfigMap MapExcludeSection {
		public get() { return( this.Config.GetSection("map_exclude") ); }
	}

	public void ResolveBackwardCompatibility() {
		_ResolveBackwardCompatibility(this);
	}
}

methodmap FF2Ability {
	public FF2Ability(ConfigMap current) {
		return( view_as< FF2Ability >(current) );
	}

	property ConfigMap Config {
		public get() { return view_as<ConfigMap>(this); }
	}

	public void GetPlugin(char[] buffer) {
		this.Config.Get("plugin_name", buffer, FF2_MAX_PLUGIN_NAME);
	}

	public void GetAbility(char[] buffer) {
		this.Config.Get("name", buffer, FF2_MAX_ABILITY_NAME);
	}

	public void GetPluginAndAbility(char[] pl_name, char[] ab_name) {
		this.GetPlugin(pl_name);
		this.GetAbility(ab_name);
	}

	public void GetId(char[] id, int id_size) {
		this.Config.Get("_id", id, id_size);
	}

	public FF2CallType_t GetSlot() {
		int s;
		return( this.Config.GetInt("slot", s, 2) ? view_as<FF2CallType_t>(s) : CT_RAGE );
	}

	public bool ContainsBitSlot(FF2CallType_t bitslot) {
		return( ( this.GetSlot() & bitslot ) == bitslot );
	}
}

// using ArrayList to allow access of multiple FF2AbilityList
methodmap FF2AbilityList < ArrayList {
	public FF2AbilityList() {
		return( view_as< FF2AbilityList >(new ArrayList()));
	}
	
	public void Insert(ConfigMap cfg) {
		this.Push(cfg);
	}

	public FF2Ability GetAbility(const char[] plugin_name, const char[] ability_name, int start_index = 0) {
		int size = this.Length;
		char buffer[FF2_MAX_PLUGIN_NAME];
		for( int i=start_index; i<size; i++ ) {
			FF2Ability cur = this.Get(i);

			cur.GetPlugin(buffer);
			if( !strcmp(buffer, plugin_name) ) {

				cur.GetAbility(buffer);
				if( !strcmp(buffer, ability_name) ) 
					return cur;
			}
		}
		return FF2Ability(null);
	}
}


/**
 * Boss identity struct
 *
 * VSH2ID = iBossType
 * soundMap = map of precached sounds to use instead of iterating through ConfigMap.Snapshot()
 * abilityList = list of 'ConfigMap' that points to the ability section
 * name = boss config name in character.cfg
 */
enum struct FF2Identity {
	int				VSH2ID;
	ConfigMap		hCfg;
	FF2SoundMap		soundMap;
	FF2AbilityList	abilityList;
	char			name[FF2_MAX_BOSS_NAME_SIZE];
	bool			isNewAPI;

	void Release() {
		delete this.soundMap;
		delete this.abilityList;
		DeleteCfg(this.hCfg);
	}
}

static bool FF2_LoadCharacter(FF2Identity identity, char[] path)
{
	char key_name[PLATFORM_MAX_PATH];

	FormatEx(key_name, PLATFORM_MAX_PATH, "configs/freak_fortress_2/%s.cfg", identity.name);
	BuildPath(Path_SM, path, PLATFORM_MAX_PATH, "%s", key_name);
	if( !FileExists(path) ) {
		LogError("[VSH2/FF2] Unable to find \"%s\"!", identity.name);
		return false;
	}

	ConfigMap cfg = new ConfigMap(key_name);
	if( !cfg ) {
		LogError("[VSH2/FF2] Failed to find \"%s\" character!", identity.name);
		return false;
	}
	
	FF2Character this_char = FF2Character(cfg);
	
	/// Check if our boss support the current map
	{
		ConfigMap exclude = this_char.MapExcludeSection;
		if( exclude ) {
			GetCurrentMap(path, PLATFORM_MAX_PATH);
			for( int i=exclude.Size-1; i>=0; i-- ) {
				if( exclude.GetIntKey(i, key_name, sizeof(key_name)) && !StrContains(key_name, path) ) {
					DeleteCfg(cfg);
					return false;
				}
			}
		}
	}

	///	Failed to register the boss, possible duplicate
	{
		identity.VSH2ID = FF2_RegisterFakeBoss(identity.name);
		if( identity.VSH2ID == INVALID_FF2_BOSS_ID ) {
			DeleteCfg(cfg);
			return false;
		}
	}
	
	identity.hCfg = cfg;
	identity.abilityList = new FF2AbilityList();

	{
		identity.isNewAPI = this_char.Config.GetSection("info") ? true : false;
		if( !identity.isNewAPI )
			FF2_ResolveBackwardCompatibility(this_char.Config);

		FF2Character_RegisterAbilities(this_char, identity.isNewAPI, identity.name, identity.abilityList);

		FF2Character_ProcessDownloads(this_char, identity.isNewAPI, identity.name);

		FF2Character_ProcessToSoundMap(this_char, identity.name, identity.soundMap);
	}

	return true;
}

/**
 * a hash map that holds boss' identities
 */
methodmap FF2BossManager < StringMap {
	public bool GetIdentity(const char[] name, FF2Identity identity) {
		return( this.GetArray(name, identity, sizeof(FF2Identity)) ? true:false );
	}

	public FF2BossManager(const char[] pack_name) {
		/// Parse Boss CFG with pack name
		ConfigMap cfg = ff2.m_charcfg.GetSection(pack_name);
		if( !cfg )
			ThrowError("Failed to find Section for characters.cfg: \"%s\"", pack_name);

		StringMap map = new StringMap();
		char[] name = new char[PLATFORM_MAX_PATH];

		/// Iterate through the Pack, copy and verify boss path
		for( int i = cfg.Size - 1; i >= 0; i-- ) {
			if( !cfg.GetIntKey(i, name, PLATFORM_MAX_PATH) )
				continue;

			FF2Identity cur_id;
			strcopy(cur_id.name, sizeof(FF2Identity::name), name);
			if( FF2_LoadCharacter(cur_id, name) ) {
				map.SetArray(cur_id.name, cur_id, sizeof(FF2Identity));
			}
		}
		return( view_as< FF2BossManager >(map) );
	}

	public bool Delete(const char[] name) {
		FF2Identity identity;
		if( this.GetArray(name, identity, sizeof(FF2Identity)) ) {
			identity.Release();
			this.Remove(name);
			return true;
		}
		return false;
	}

	public void DeleteAll() {
		StringMapSnapshot snap = this.Snapshot();
		char name[48];
		FF2Identity identity;
		for( int i = snap.Length - 1; i >= 0; i-- ) {
			snap.GetKey(i, name, sizeof(name));
			if( this.GetIdentity(name, identity) ) {
				identity.Release();
			}
		}
		this.Clear();
		delete snap;
	}

	public bool FindIdentity(const int ID, FF2Identity identity) {
		StringMapSnapshot snap = this.Snapshot();
		char name[48];
		bool res;
		for( int i = snap.Length - 1; i >= 0; i-- ) {
			snap.GetKey(i, name, sizeof(name));
			if( this.GetIdentity(name, identity) && identity.VSH2ID == ID ) {
				res = true;
				break;
			}
		}
		delete snap;
		return res;
	}

	public bool FindIdentityByCfg(const ConfigMap cfg, FF2Identity identity) {
		StringMapSnapshot snap = this.Snapshot();
		char name[48];
		bool res;
		for( int i = snap.Length - 1; i >= 0; i-- ) {
			snap.GetKey(i, name, sizeof(name));
			if( this.GetIdentity(name, identity) && identity.hCfg == cfg ) {
				res = true;
				break;
			}
		}
		delete snap;
		return res;
	}

	public bool FindIdentityByName(const char[] name, FF2Identity identity) {
		StringMapSnapshot snap = this.Snapshot();
		char key_name[48];
		bool res;
		for( int i = snap.Length - 1; i >= 0 && !res; i-- ) {
			snap.GetKey(i, key_name, sizeof(key_name));
			if( this.GetIdentity(key_name, identity) && !strcmp(name, identity.name) ) {
				res = true;
			}
		}
		delete snap;
		return res;
	}
}

FF2BossManager ff2_cfgmgr;


static void FF2Character_RegisterAbilities(FF2Character this_char, bool new_api, const char[] boss_name, FF2AbilityList& outablist)
{
	///	using "abilities" section for new api, and "character" for old api
	ConfigMap abilities_section = new_api ? this_char.Config.GetSection("abilities") : this_char.Config;
	if( !abilities_section )
		return;
	///	using "<enum>" keyword for new api, and snapshot with key that start with "ability"
	StringMapSnapshot snap;
	if( !new_api )
		snap = abilities_section.Snapshot();
	int iter_size 				= new_api ? abilities_section.Size : snap.Length;
	int free_abilities 			= FF2_MAX_SUBPLUGINS - outablist.Length;

	/**
	 * new api:
	 *	"abilities" {
	 *		"<enum>" {
	 *			"_id"		"My Ability Id"
	 *			"_hidden"	"true"	// same as slot == '0b1000'
	 *		///	"slot"		"1000"	// <unused> flag	///	https://github.com/01Pollux/FF2-Library/wiki/Important-Changes
	 *		///	"arg0"		"-2"	// default, unused slot
	 *
	 *			"name"		"rage_stunsg"
	 *			"plugin_name"	"default_abilities"
	 *			
	 *			"something arg" "100.0"
	 *		
	 *			// boss won't be registered without the required subplugins / abilities
	 *			"requires" {
	 *				"<enum>"	"MySubpluginName1"
	 *				"<enum>"	"MySubpluginName2"
	 *				"<enum>"	"ff2vsh2_defaults"
	 *			}
	 *
	 *			"call" {
	 *				// next 10 sec, call this ability
	 *				"timer"		"10.0"
	 *				// Recursive call every 10.0 sec
	 *				"name"		"My Ability Id"
	 *			}
	 *		}
	 *	}
	 *
	 * old api:
	 *	/// unlike the actual default api, i'll still allow insertion of multiple abilities with same key, and remove the strict enumeration for it
	 *	///
	 *	///	"ability: My Custom Name"
	 *	///	"AbiLITY_zeaeallalllxxww"
	 *	///	"AbiLITY41151561515115"
	 *	///	"ability1" spammed across every ability
	 *	"ability1" {
	 *		"name"		"rage_stunsg"
	 *		"plugin_name"	"default_abilities" 
	 *
	 *		"slot"		"0"	///	Batfoxkid's api
	 *		/// "arg0"	"0"	///	default
	 *
	 *		"something arg" "100.0"	/// Batfoxkid's api
	 *		/// "arg1"		"100.0"	///	default
	 *	}
	 *
	 */

	char path[PLATFORM_MAX_PATH], plugin_name[FF2_MAX_PLUGIN_NAME];
	for( int i; i<iter_size && free_abilities>0; i++ ) {
		ConfigMap cur_section;
		if( new_api ) {
			cur_section = abilities_section.GetIntSection(i);
		}
		else {
			snap.GetKey(i, path, FF2_MAX_ABILITY_KEY);
			if( strncmp(path, "ability", 7) )
				continue;
			cur_section = abilities_section.GetSection(path);
		}

		if( !cur_section || !cur_section.Get("plugin_name", plugin_name, sizeof(plugin_name)) )
			continue;
		
		if( !strcmp(plugin_name, "ffbat_defaults") || !strcmp(plugin_name, "default_abilities") ) {
			LogError("[VSH2/FF2] Character \"%s.cfg\" is using a non supported subplugin \"%s\"!, switching to \"ff2_vsh2defaults\"", boss_name, plugin_name);
			plugin_name = "ff2_vsh2defaults";
		}

		BuildPath(Path_SM, path, sizeof(path), "plugins\\freaks\\%s.smx", plugin_name);

		if( !FileExists(path) ) {
			LogError("[VSH2/FF2] Character \"%s.cfg\" is missing \"%s\" subplugin!", boss_name, plugin_name);
			continue;
		} else {
			bool hide;
			if( new_api && cur_section.GetBool("_hidden", hide) )
				cur_section.SetInt("slot", view_as<int>(CT_INACTIVE));

			outablist.Insert(cur_section);
			--free_abilities;
		}

		///	Resolve the 'arg0' and the old 'slot'
		if( !new_api ) {
			int slot;
			if( !cur_section.GetInt("arg0", slot) )
				cur_section.GetInt("slot", slot);
			cur_section.SetInt("slot", view_as<int>(FF2_OldNumToBitSlot(slot)));	///	defaulted to CT_RAGE in case of rage
		}
	}

	delete snap;
}

static void FF2Character_ProcessDownloads(FF2Character this_char, bool new_api, char[] boss_name)
{
	char path[PLATFORM_MAX_PATH], key_name[PLATFORM_MAX_PATH];
	ConfigMap stacks;
	ConfigMap downloads_section = new_api ? this_char.Config.GetSection("downloads") : this_char.Config;
	int extra = new_api ? 0 : 1;

	/**
	 *	
	 * new api:
	 *	"downloads"
	 *	{
	 *		"any" {
	 *			"<enum>"	"..."
	 *		}
	 *		"materials" {
	 *			"<enum>"	"..."
	 *		}
	 *		"models" {
	 *			"<enum>"	"..."
	 *		}
	 *	}
	 *
	 *
	 * old api:
	 *	"download" {
	 *		"<enum>"		"..."
	 *		"<enum>"		"...."
	 *		"<enum>"		".."
	 *	}
	 *
	 *	"mat_download" {	///	"mod_download"
	 *		"<enum>"		"..."
	 *		"<enum>"		"...."
	 *		"<enum>"		".."
	 *	}
	 */
	
	/// download any
	{
		if( (stacks = downloads_section.GetSection(new_api ? "any" : "download")) ) {
			for( int i = stacks.Size - 1; i >= 0; i-- ) {
				if( !stacks.GetIntKey(i+extra, path, sizeof(path)) )
					continue;

				if( !FileExists(path, true) ) {
					LogError("[VSH2/FF2] Character \"%s\" is missing file \"%s\"!", boss_name, path);
				} else {
					AddFileToDownloadsTable(path);
				}
			}
		}
	}

	{
		char model_ext[][] = {
			".mdl",
			".dx80.vtx", ".dx90.vtx",
			".sw.vtx",
			".vvd",
			".phy"
		};
		/// models only
		if( (stacks = downloads_section.GetSection(new_api ? "models" : "mod_download")) ) {
			for( int i = stacks.Size - 1; i >= 0; i-- ) {
				if( !stacks.GetIntKey(i+extra, path, PLATFORM_MAX_PATH) )
					continue;

				for( int j = 0; j < sizeof(model_ext); j++ ) {
					FormatEx(key_name, sizeof(key_name), "%s%s", path, model_ext[j]);
					if( FileExists(key_name, true) ) {
						AddFileToDownloadsTable(key_name);
					} else if( StrContains(key_name, ".phy") == -1 ) {
						LogError("[VSH2/FF2] Character \"%s.cfg\" is missing file \"%s\"!", boss_name, key_name);
					}
				}
			}
		}

		char mat_ext[][] = {
			".vmt",
			".vtf"
		};
		/// materials only
		if( (stacks = downloads_section.GetSection(new_api ? "materials" : "mat_download")) ) {
			for( int i = stacks.Size - 1; i >= 0; i-- ) {
				if( !stacks.GetIntKey(i+extra, path, PLATFORM_MAX_PATH) )
					continue;

				for( int j = 0; j < sizeof(mat_ext); j++ ) {
					FormatEx(key_name, sizeof(key_name), "%s%s", path, mat_ext[j]);
					if( FileExists(key_name, true) ) {
						AddFileToDownloadsTable(key_name);
					} else if( StrContains(key_name, ".phy") == -1 ) {
						LogError("[VSH2/FF2] Character \"%s.cfg\" is missing file \"%s\"!", boss_name, key_name);
					}
				}
			}
		}
	}
}

static void FF2Character_ProcessToSoundMap(FF2Character this_char, const char[] boss_name, FF2SoundMap& out_soundmap)
{
	out_soundmap = new FF2SoundMap();

	ConfigMap sounds = this_char.Config.GetSection("sounds");
	StringMapSnapshot snap = sounds.Snapshot();
	int snap_size = snap.Length;

	for( int i=snap_size-1; i>=0; i-- ) {
		int len = snap.KeyBufferSize(i);
		char[] sec_key = new char[len];
		snap.GetKey(i, sec_key, len);
		if( !out_soundmap.SetSection(sec_key, sounds.GetSection(sec_key)) ) {
			LogError("[VSH2/FF2] Character \"%s\" has a duplicate section \"%s\"!", boss_name, sec_key);
		}
	}

	delete snap;
}

///	Instead of checking for literary each time if we should use info section or anything new, why not reparse the config to the new format
static void _ResolveBackwardCompatibility(FF2Character boss_cfg)
{
	bool skip;
	if( this.Config.GetBool("using.VSH2/FF2 new API", skip) && skip )
		return;

	ConfigMap cfg = boss_cfg.Config;
	StringMapSnapshot snap = cfg.Snapshot();
	int snap_size = snap.Size;

	char import_to_info__new_key[][] = {
		/// { KEY, NEW_KEY }, don't change for empty new key
		{ "name", 				"" },
		{ "model", 				"" },
		
		{ "class", 				"" },
		{ "lives",				"" },
		
		{ "health_formula",		"health" },
		
		{ "nofirst",			"" },
		{ "permission",			"" },
		{ "blocked",			"" },
		
		{ "speed",				"speed.min" },
		{ "minspeed",			"speed.min" },
		{ "maxspeed",			"speed.max" },
		
		{ "companion",			"companion.1" },	//	"companion.<enum>"
		
		{ "sound_block_vo",		"mute" },
		{ "version",			"" },
	};
	
	bool skip_imports[sizeof(import_to_info__new_key)];
	int skips;
	PackVal datapack;
	
	for( int i; i<snap_size; i++ ) {
		int len = snap.KeyBufferSize(i);
		char[] key = new char[len];
		snap.GetKey(i, key, len);
		
		if( skips!=sizeeof(skip_imports) ) {
			for( int j; j<sizeof(skip_imports); j++ ) {
				if( skip_imports[j] )
					continue;
				if( strcmp(import_to_info__new_key[i][0], key) )
					continue;

				skips++;
				if( cfg.GetVal(key, datapack) ) {
					cfg.SetArray(import_to_info__new_key[i][1], datapack);
					cfg.Remove(key);
				}
			}
		}
	}
	
	char import_to_info__description[] = {
		
	};
}
