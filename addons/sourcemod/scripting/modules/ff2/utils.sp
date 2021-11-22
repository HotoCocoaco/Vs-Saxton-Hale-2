#define INVALID_FF2_BOSS_ID      -1
#define INVALID_FF2PLAYER        view_as< FF2Player >(-1)

#define ToFF2Player(%0)          view_as< FF2Player >(%0)
#define ClientToBossIndex(%0)    view_as< int >(%0)

#define IsClientValid(%1)        ( 0 < (%1) && (%1) <= MaxClients && IsClientInGame((%1)) )

#define	PATH_TO_CHAR_CFG    	"data/freak_fortress_2/characters.cfg"
	
#define FF2_CHARACTER_KEY		"character"


enum FF2CallType_t {
	CT_NONE          = 0b000000000, /// Inactive, default to CT_RAGE
	CT_LIFE_LOSS     = 0b000000001,
	CT_RAGE          = 0b000000010,
	CT_CHARGE        = 0b000000100,
	CT_UNUSED_DEMO   = 0b000001000, /// UNUSED
	CT_INACTIVE		 = CT_UNUSED_DEMO,
	CT_WEIGHDOWN     = 0b000010000,
	CT_PLAYER_KILLED = 0b000100000,
	CT_BOSS_KILLED   = 0b001000000,
	CT_BOSS_STABBED  = 0b010000000,
	CT_BOSS_MG       = 0b100000000,
};

enum FF2RageType_t {
	RT_RAGE = 0,
	RT_WEIGHDOWN,
	RT_CHARGE
};

enum { FF2_MAX_SUBPLUGINS = 16 };

enum {
	FF2_MAX_PLUGIN_NAME  = 64,   /// sizeof plugin_name
	FF2_MAX_ABILITY_NAME = 64,   /// sizeof ability_name
	FF2_MAX_ABILITY_KEY  = 64,   /// sizeof "ability*" key
};

enum { FF2_MAX_LIST_KEY = FF2_MAX_PLUGIN_NAME + FF2_MAX_ABILITY_NAME + 2 };		/// sizeof key in FF2AbilityList

enum { FF2_MAX_BOSS_NAME_SIZE = MAX_BOSS_NAME_SIZE - 5 };	///	MAX_BOSS_NAME_SIZE - (sizeof("_FF2") - NULL_TERMINATOR)

enum { FF2_MAX_RANDOM_SOUNDS = 15 };

#include "modules/ff2/sound_list.sp"
#include "modules/ff2/character.sp"
#include "modules/ff2/player.sp"

stock FF2Player ZeroBossToFF2Player()
{
	FF2Player[] players = new FF2Player[MaxClients];
	if( VSH2GameMode.GetBosses(players, false) < 1 )
		return( INVALID_FF2PLAYER );
	
	return( players[0] );
}

stock ConfigMap JumpToAbility(const FF2Player player, const char[] plugin_name, const char[] ability_name)
{
	FF2AbilityList list = player.HookedAbilities;
	ConfigMap ability = null;
	
	if( list ) {
		ability = list.GetAbility(plugin_name, ability_name).Config;
	}
	
	return( ability );
}

stock int GetArgNamedB(FF2Player player, const char[] plugin_name, const char[] ability_name, const char[] argument, bool defval = false)
{
	ConfigMap section = JumpToAbility(player, plugin_name, ability_name);
	if( section==null ) {
		return( defval );
	}
	
	bool result;
	return( section.GetBool(argument, result, false) ? result:defval );
}

stock int GetArgNamedI(FF2Player player, const char[] plugin_name, const char[] ability_name, const char[] argument, int defval = 0)
{
	ConfigMap section = JumpToAbility(player, plugin_name, ability_name);
	if( section==null ) {
		return( defval );
	}
	
	int result;
	return( section.GetInt(argument, result) ? result:defval );
}

stock float GetArgNamedF(FF2Player player, const char[] plugin_name, const char[] ability_name, const char[] argument, float defval = 0.0)
{
	ConfigMap section = JumpToAbility(player, plugin_name, ability_name);
	if( section==null ) {
		return( defval );
	}
	
	float result;
	return( section.GetFloat(argument, result) ? result:defval );
}

stock int GetArgNamedS(FF2Player player, const char[] plugin_name, const char[] ability_name, const char[] argument, char[] result, int size)
{
	ConfigMap section = JumpToAbility(player, plugin_name, ability_name);
	if( section==null ) {
		return 0;
	}
	return( section.Get(argument, result, size) );
}

stock void FPrintToChat(int client, const char[] message, any ...)
{
	SetGlobalTransTarget(client);
	char buffer[192];
	VFormat(buffer, sizeof(buffer), message, 3);
	CPrintToChat(client, "{olive}[VSH2/FF2]{default} %s",  buffer);
}

stock int FF2_RegisterFakeBoss(const char[] name)
{
	if( strlen(name) >= FF2_MAX_BOSS_NAME_SIZE )
		return( INVALID_FF2_BOSS_ID );
	char final_name[MAX_BOSS_NAME_SIZE];
	FormatEx(final_name, sizeof(final_name), "%s_FF2", name);
	
	int id;
	if( (id=VSH2_GetBossID(final_name)) != INVALID_FF2_BOSS_ID ) {
		return( id );
	}
	
	return( VSH2_RegisterPlugin(final_name) );
}

stock void FF2_ReplaceEscapeSeq(char[] str, int size)
{
	char list[][][] = {
		{ "\t", "\\t" },
		{ "\n", "\\n" },
		{ "\r", "\\r" }
	};
	for( int i; i<sizeof(list); i++ ) {
		ReplaceString(str, size, list[i][0], list[i][1]);
	}
}

///	https://github.com/01Pollux/FF2ConfigToVSH2/blob/main/ff2_config_to_vsh2.sp#L385
stock FF2CallType_t FF2_OldNumToBitSlot(int slot)
{
	/**
	 * -2 - Invalid slot(internally used by FF2 for detecting missing "arg0" argument). Don't use!
	 * -1 - When Boss loses a life (if he has over 1)
     * 0 - Rage
     * 1 - Used by charging brave Jump. Fired every 0.2s
     * 2 - Demopan's charge of targe, projectiles etc.
     * 3 - Weighdown
     * 4 - Killed player (not used for sounds)
     * 5 - Boss killed (not used for sounds)
     * 6 - Boss backstabbed (not used for sounds)
     * 7 - Boss market gardened (not used for sounds)
     */
	switch (slot)
	{
 	case -2, 2: {
	// 2, -2 should never be used unless you're calling with FF2Player.ForceAbility
	return CT_UNUSED_DEMO;
	}
	case -1: return CT_LIFE_LOSS;
	case 1: return CT_CHARGE;
	case 0: return CT_RAGE;

//	case 3, 4, 5, 6, 7:
	default: {
		return view_as<FF2CallType_t>(1 << (1 + slot));
	}
	}
}