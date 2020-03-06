public SharedPlugin:__pl_afk = 
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
public __pl_afk_SetNTVOptional()
{
	MarkNativeAsOptional("IsPlayerAFK");
}
#endif

native bool:IsPlayerAFK(client);

forward OnAfkStateChanged(client, bool:afk);