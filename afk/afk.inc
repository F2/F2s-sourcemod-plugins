public SharedPlugin __pl_afk = 
{
	name = "afk",
	file = "afk.smx",
#if defined REQUIRE_PLUGIN
	required = 1,
#else
	required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public void __pl_afk_SetNTVOptional()
{
	MarkNativeAsOptional("IsPlayerAFK");
}
#endif

native bool IsPlayerAFK(int client);

forward void OnAfkStateChanged(int client, bool afk);