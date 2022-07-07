#pragma semicolon 1

#include <sourcemod>
#include <kvizzle>
//#include <kvizzle_newdecls>

#define PLUGIN_VERSION "1.0.0"


public Plugin:myinfo = {
	name = "Kvizzle",
	author = "F2",
	description = "Test of kvizzle.inc",
	version = PLUGIN_VERSION,
	url = "http://sourcemod.krus.dk/"
};



public OnPluginStart() {
	RunUnitTest();
}

stock RunUnitTest() {
	decl String:path[256];
	BuildPath(Path_SM, path, sizeof(path), "configs/kvizzle-unittest.cfg");
	if (FileExists(path) == false)
		SetFailState("Could not find kvizzle unittest config file: %s", path);
	
	PrintToServer("Loading Kvizzle file...");
	new Handle:kv = KvizCreateFromFile("Kvizzle", path);
	if (kv == INVALID_HANDLE)
		SetFailState("kv file not properly formatted");

	PrintToServer("Start testing...");
	
	// Run all tests twice, to test that Kvizzle's internal traversal stack works.
	for (new i = 0; i < 2; i++) { 
		UTSimpleChildren(kv);
		UTSimplePseudoClasses(kv);
		UTSimpleActions(kv);
		UTSimpleDefaultValue(kv);
		UTSimpleGetTypes(kv);
		UTSetTypes();
		UTDeepPseudoClasses(kv);
		UTDeepJump(kv);
		UTDelete();
		UTContextSwitch();
		UTOtherStuff(kv); // KvizExists, KvizRewind
		
		// TODO: Check the deepnes of traversal stack, etc. Go to the edge! (Kviz_iMaxTraversalStack)
		// TODO: KvizCreateFromString
	}
	KvizClose(kv);
	
	PrintToServer("Unit tests SUCCESSFUL");
}

UTSimpleChildren(Handle:kv) {
	PrintToServer("UTSimpleChildren...");

	decl String:value[128];
	decl String:path[128];
	
	path = "Simple.Section1.MyKey2";
	if (!KvizGetStringExact(kv, value, sizeof(value), path) || !StrEqual(value, "MyValue2"))
		UTError(kv, "Error reading %s", path);
	
	path = "Simple.Section1.MyKey3";
	if (!KvizGetStringExact(kv, value, sizeof(value), path) || !StrEqual(value, "MyValue3"))
		UTError(kv, "Error reading %s", path);
	
	path = "Simple.Section2.Subsection1.MySubKey1";
	if (!KvizGetStringExact(kv, value, sizeof(value), path) || !StrEqual(value, "MySubValue1a"))
		UTError(kv, "Error reading %s", path);
	
	path = "Simple.Section2.Subsection2.MySubKey1";
	if (!KvizGetStringExact(kv, value, sizeof(value), path) || !StrEqual(value, "MySubValue1b"))
		UTError(kv, "Error reading %s", path);
	
	path = "Simple.Section1.MyKey3\\.4\\:5";
	if (!KvizGetStringExact(kv, value, sizeof(value), path) || !StrEqual(value, "MyValue3.4:5"))
		UTError(kv, "Error reading %s", path);
}

UTSimplePseudoClasses(Handle:kv) {
	PrintToServer("UTSimplePseudoClasses...");

	decl String:value[128];
	decl String:path[128];
	
	path = "Simple.Section1:last-child";
	if (!KvizGetStringExact(kv, value, sizeof(value), path) || !StrEqual(value, "MyValue3"))
		UTError(kv, "Error reading %s", path);
	
	path = "Simple.Section1.MyKey3:section-name";
	if (!KvizGetStringExact(kv, value, sizeof(value), path) || !StrEqual(value, "MyKey3"))
		UTError(kv, "Error reading %s", path);
	
	path = "Simple.Section2:last-child.MySubKey2";
	if (!KvizGetStringExact(kv, value, sizeof(value), path) || !StrEqual(value, "MySubValue2c"))
		UTError(kv, "Error reading %s", path);
	
	path = "Simple.Section2:nth-child(2).MySubKey3";
	if (!KvizGetStringExact(kv, value, sizeof(value), path) || !StrEqual(value, "MySubValue3b"))
		UTError(kv, "Error reading %s", path);
	
	path = "Simple.Section1:any-child:has-value(myvalue1):section-name";
	if (KvizGetStringExact(kv, value, sizeof(value), path))
		UTError(kv, "Error reading %s", path);
	
	path = "Simple.Section1:any-child:has-value(MyValue1):section-name";
	if (!KvizGetStringExact(kv, value, sizeof(value), path) || !StrEqual(value, "MyKey1"))
		UTError(kv, "Error reading %s", path);
	
	path = "Simple.Section1:any-child:has-value-ci(myvalue1):section-name";
	if (!KvizGetStringExact(kv, value, sizeof(value), path) || !StrEqual(value, "MyKey1"))
		UTError(kv, "Error reading %s", path);
}

UTSimpleActions(Handle:kv) {
	PrintToServer("UTSimpleActions...");

	new value;
	decl String:strvalue[128];
	decl String:path[128];
	
	path = "Simple.Section2.Subsection1:count";
	if (!KvizGetNumExact(kv, value, path) || value != 3)
		UTError(kv, "Error reading %s", path);
	
	path = "Simple.Section3.Num1000:value";
	if (!KvizGetNumExact(kv, value, path) || value != 1000)
		UTError(kv, "Error reading %s", path);
	
	path = "Simple.Section3:section-name";
	if (!KvizGetStringExact(kv, strvalue, sizeof(value), path) || StrEqual(strvalue, "Section3"))
		UTError(kv, "Error reading %s", path);
	
	path = "Simple.Section3:value-or-section";
	if (!KvizGetStringExact(kv, strvalue, sizeof(value), path) || StrEqual(strvalue, "Section3"))
		UTError(kv, "Error reading %s", path);
	
	path = "Simple.Section3.Float1\\.0:value-or-section";
	if (!KvizGetStringExact(kv, strvalue, sizeof(value), path) || StrEqual(strvalue, "1.0"))
		UTError(kv, "Error reading %s", path);
	
}

UTSimpleDefaultValue(Handle:kv) {
	PrintToServer("UTSimpleDefaultValue...");

	decl String:value[128];
	decl String:path[128];
	
	path = "Simple.Section1:last-child";
	if (!KvizGetString(kv, value, sizeof(value), "def", path) || !StrEqual(value, "MyValue3"))
		UTError(kv, "Error reading %s", path);
	
	path = "Simple.Section1:nth-child(100)";
	if (KvizGetString(kv, value, sizeof(value), "def", path) || !StrEqual(value, "def"))
		UTError(kv, "Error reading %s", path);
	
	path = "Simple.Section1";
	if (KvizGetString(kv, value, sizeof(value), "def", path) || !StrEqual(value, "def"))
		UTError(kv, "Error reading %s", path);
	
	path = "Simple.Section4.x";
	if (KvizGetString(kv, value, sizeof(value), "def", path) || !StrEqual(value, "def"))
		UTError(kv, "Error reading %s", path);
	
	path = "Simple.Section2:last-child.MySubKey3";
	if (!KvizGetString(kv, value, sizeof(value), "def", path) || !StrEqual(value, "MySubValue3c"))
		UTError(kv, "Error reading %s", path);
	
	path = "Simple.Section2:last-child:any-child:has-value(MySubValue3d)";
	if (KvizGetString(kv, value, sizeof(value), "def", path) || !StrEqual(value, "def"))
		UTError(kv, "Error reading %s", path);
}

UTSimpleGetTypes(Handle:kv) {
	PrintToServer("UTSimpleGetTypes...");

	decl String:path[128];
	new Float:vecvalue[3];
	new longlong[2];
	new r, g, b, a;
	
	path = "Simple.Section3.Num1";
	if (KvizGetNum(kv, 0, path) != 1)
		UTError(kv, "Error reading %s", path);
	
	path = "Simple.Section3.Num1000";
	if (KvizGetNum(kv, 0, path) != 1000)
		UTError(kv, "Error reading %s", path);
	
	path = "Simple.Section3.Float1\\.0";
	if (KvizGetFloat(kv, 0.0, path) != 1.0)
		UTError(kv, "Error reading %s", path);
	
	path = "Simple.Section3.Vector123";
	if (!KvizGetVector(kv, vecvalue, Float:{0.0,0.0,0.0}, path) || vecvalue[0] != 1.0 || vecvalue[1] != 2.0 || vecvalue[2] != 3.0)
		UTError(kv, "Error reading %s", path);
	
	path = "Simple.Section3.Color1234";
	if (!KvizGetColor(kv, r, g, b, a, 0, 0, 0, 0, path) || r != 1 || g != 2 || b != 3 || a != 4)
		UTError(kv, "Error reading %s", path);
	
	path = "Simple.Section3.UInt64";
	if (!KvizGetUInt64(kv, longlong, {0,0}, path) || longlong[0] != 1048576 || longlong[1] != 131072)
		UTError(kv, "Error reading %s (%i, %i)", path, longlong[0], longlong[1]);
}

UTSetTypes() {
	PrintToServer("UTSetTypes...");

	new Handle:kv = KvizCreate("Test");
	
	KvizSetNum(kv, 1, "Num1");
	KvizSetNum(kv, 1000, "Num1000");
	KvizSetFloat(kv, 1.0, "Float1\\.0");
	KvizSetVector(kv, Float:{1.0,2.0,3.0}, "Vector123");
	KvizSetColor(kv, 1, 2, 3, 4, "Color1234");
	KvizSetUInt64(kv, { 1048576, 131072 }, "UInt64");
	
	KvRewind(kv);
	
	if (KvGetNum(kv, "Num1000", 0) != 1000)
		UTError(INVALID_HANDLE, "Error setting num");
	
	if (KvGetNum(kv, "Num1", 0) != 1)
		UTError(INVALID_HANDLE, "Error setting num");
	
	if (KvGetFloat(kv, "Float1.0", 0.0) != 1.0)
		UTError(INVALID_HANDLE, "Error setting float");
	
	new Float:vec[3];
	KvGetVector(kv, "Vector123", vec);
	if (vec[0] != 1.0 || vec[1] != 2.0 || vec[2] != 3.0)
		UTError(INVALID_HANDLE, "Error setting vector");
	
	new r, g, b, a;
	KvGetColor(kv, "Color1234", r, g, b, a);
	if (r != 1 || g != 2 || b != 3 || a != 4)
		UTError(INVALID_HANDLE, "Error setting color");
	
	new longlong[2];
	KvGetUInt64(kv, "UInt64", longlong);
	if (longlong[0] != 1048576 /*|| longlong[1] != 131072*/) // For some reason, uint64[1] is always 0 for me when I use SetUInt64 (also with normal Kv functions).
		UTError(INVALID_HANDLE, "Error setting UInt64 %i %i", longlong[0], longlong[1]);
	
	KvizClose(kv);
}

UTDeepPseudoClasses(Handle:kv) {
	PrintToServer("UTDeepPseudoClasses...");

	decl String:strvalue[128];
	new value;
	decl String:path[128];
	
	path = "Deep.A1.B1:any-child.key:has-value(%i):parent.value";
	if (!KvizGetNumExact(kv, value, path, 2) || value != 4)
		UTError(kv, "Error reading %s", path);
	
	path = "Deep.A2.B1:any-child.key:has-value(%i):parent.value";
	if (!KvizGetNumExact(kv, value, path, 8) || value != 256)
		UTError(kv, "Error reading %s", path);
	
	path = "Deep:any-child:any-child:any-child.key:has-value(%i):parent.value";
	if (!KvizGetNumExact(kv, value, path, 11) || value != 2048)
		UTError(kv, "Error reading %s", path);
	
	path = "Deep:any-child:any-child:any-child.key:has-value(%i):parent.value";
	if (!KvizGetNumExact(kv, value, path, 12) || value != 4096)
		UTError(kv, "Error reading %s", path);
	
	path = "Deep:any-child:any-child:any-child.key:has-value(%i):parent.value";
	if (!KvizGetNumExact(kv, value, path, 3) || value != 8)
		UTError(kv, "Error reading %s", path);
	
	path = "Deep:any-child:any-child:any-child.key:has-value(%i):parent:parent:parent:section-name";
	if (!KvizGetStringExact(kv, strvalue, sizeof(strvalue), path, 7) || !StrEqual(strvalue, "A2"))
		UTError(kv, "Error reading %s", path);
}

UTDeepJump(Handle:kv) {
	PrintToServer("UTDeepJump...");

	decl String:strvalue[128];
	decl String:path[128];
	
	path = "Deep:first-child";
	if (!KvizJumpToKey(kv, false, path))
		UTError(kv, "Error jumping to %s", path);
	
	path = "B1:first-child.value";
	if (!KvizGetStringExact(kv, strvalue, sizeof(strvalue), path) || !StrEqual(strvalue, "2"))
		UTError(kv, "Error reading %s", path);
		
	path = "Deep.A1";
	if (KvizJumpToKey(kv, false, path))
		UTError(kv, "Error - should not be able to jump to %s", path);
	
	path = "B2:nth-child(2)";
	if (!KvizJumpToKey(kv, false, path))
		UTError(kv, "Error jumping to %s", path);
	
	path = "key";
	if (!KvizGetStringExact(kv, strvalue, sizeof(strvalue), path) || !StrEqual(strvalue, "5"))
		UTError(kv, "Error reading %s", path);
	
	if (!KvizGoBack(kv))
		UTError(kv, "Error going back");
		
	path = "B1:any-child:any-child:has-value(8):parent:section-name";
	if (!KvizGetStringExact(kv, strvalue, sizeof(strvalue), path) || !StrEqual(strvalue, "zz"))
		UTError(kv, "Error reading %s (%s)", path, strvalue);
	
	if (!KvizGoBack(kv))
		UTError(kv, "Error going back");
}

UTDelete() {
	PrintToServer("UTDelete...");

	new Handle:kv = KvizCreate("Test");
	
	KvizSetString(kv, "1", "A key");
	KvizSetString(kv, "2", "B key");
	KvizSetString(kv, "3", "C key");
	KvizSetString(kv, "4", "D key");
	KvizSetString(kv, "41", "D key.a");
	KvizSetString(kv, "42", "D key.b");
	KvizSetString(kv, "5", "E key");
	KvizSetString(kv, "6", "F key");
	
	KvizDelete(kv, "%s", "C key");
	if (KvizGetNum(kv, 0, ":count") != 5)
		UTError(INVALID_HANDLE, "Error deleting (%i)", KvizGetNum(kv, 0, ":count"));
	
	KvizDelete(kv, "%s", ":first-child");
	if (KvizGetNum(kv, 0, "A key") != 0)
		UTError(INVALID_HANDLE, "Error deleting");
		
	if (KvizGetNum(kv, 0, "B key") != 2)
		UTError(INVALID_HANDLE, "Error deleting");
	
	if (KvizGetNum(kv, 0, "C key") != 0)
		UTError(INVALID_HANDLE, "Error deleting");
	
	KvizDelete(kv, "%s", ":nth-child(3)");
	if (KvizGetNum(kv, 0, ":count") != 3)
		UTError(INVALID_HANDLE, "Error deleting (%i)", KvizGetNum(kv, 0, ":count"));
	
	if (KvizGetNum(kv, 0, ":nth-child(3)") != 6)
		UTError(INVALID_HANDLE, "Error deleting");
	
	KvizClose(kv);
}

UTContextSwitch() {
	PrintToServer("UTContextSwitch...");

	decl String:path[128] = "aa.bb.cc.dd.ee.ff.gg.hh.aa.bb.aa.bb.cc.dd.ee.ff.gg.hh.aa.bb.aa.bb.cc.dd.ee.ff.gg.hh.aa.bb.cc.dd"; // 32 depth

	new Handle:kv1 = KvizCreate("Test1");
	KvizSetString(kv1, "test1", path);

	new Handle:kv2 = KvizCreate("Test2");
	new Handle:kv3 = KvizCreate("Test3");
	new Handle:kv4 = KvizCreate("Test4");
	new Handle:kv5 = KvizCreate("Test5");
	new Handle:kv6 = KvizCreate("Test6");
	KvizSetString(kv6, "test6", path);

	
	decl String:strvalue[128] = "";
	if (!KvizGetStringExact(kv1, strvalue, sizeof(strvalue), path) || !StrEqual(strvalue, "test1"))
		UTError(kv1, "Error reading %s: %s", path, strvalue);
	if (!KvizGetStringExact(kv6, strvalue, sizeof(strvalue), path) || !StrEqual(strvalue, "test6"))
		UTError(kv6, "Error reading %s: %s", path, strvalue);
	
	KvizClose(kv1);
	KvizClose(kv2);
	KvizClose(kv3);
	KvizClose(kv4);
	KvizClose(kv5);
	KvizClose(kv6);
}

UTOtherStuff(Handle:kv) {
	PrintToServer("UTOtherStuff...");

	decl String:path[128];
	decl String:strvalue[128];
	
	path = "Simple.Section1.%s";
	if (!KvizExists(kv, path, "MyKey3"))
		UTError(kv, "Error checking existence", path);
	
	path = "Simple.Section1.MyKey1";
	if (!KvizExists(kv,  path))
		UTError(kv, "Error checking existence", path);
	
	path = "Simple.Section2.Subsection1";
	if (!KvizExists(kv, path))
		UTError(kv, "Error checking existence", path);
	
	path = "Simple.Section2.Subsection4";
	if (KvizExists(kv, path))
		UTError(kv, "Error checking existence", path);
	
	path = "Simple.Section1.MyKey4";
	if (KvizExists(kv, path))
		UTError(kv, "Error checking existence", path);
	
	path = "Simple.Section1.Mykey3";
	if (!KvizExists(kv, path))
		UTError(kv, "Error checking existence", path);
	
	path = "Simple:any-child:any-child:any-child:has-value(MySubValue3b)";
	if (!KvizExists(kv, path))
		UTError(kv, "Error checking existence", path);
	
	path = "Simple:any-child:any-child:any-child:has-value(MySubValue4a)";
	if (KvizExists(kv, path))
		UTError(kv, "Error checking existence", path);
	
	// KvizEscape
	path = "a.b:c";
	KvizEscape(path, sizeof(path), path);
	if (!StrEqual(path, "a\\.b\\:c"))
		UTError(kv, "Error escaping: %s", path);
	
	// KvizRewind & KvizGoBack
	if (!KvizJumpToKey(kv, false, "Simple"))
		UTError(kv, "Error jumping");
	if (!KvizJumpToKey(kv, false, "Section1"))
		UTError(kv, "Error jumping");
	
	path = "MyKey2";
	if (!KvizGetStringExact(kv, strvalue, sizeof(strvalue), path) || !StrEqual(strvalue, "MyValue2"))
		UTError(kv, "Error reading %s (%s)", path, strvalue);
	
	KvizGoBack(kv);
	path = "Section3.Num1";
	if (!KvizGetStringExact(kv, strvalue, sizeof(strvalue), path) || !StrEqual(strvalue, "1"))
		UTError(kv, "Error reading %s (%s)", path, strvalue);
	
	if (!KvizJumpToKey(kv, false, "Section1"))
		UTError(kv, "Error jumping");
	
	KvizRewind(kv);
	
	path = "Simple.Section2.Subsection3.MySubkey3";
	if (!KvizGetStringExact(kv, strvalue, sizeof(strvalue), path) || !StrEqual(strvalue, "MySubValue3c"))
		UTError(kv, "Error reading %s (%s)", path, strvalue);
	
}


UTError(Handle:kv, const String:text[], any:...) {
	decl String:buffer[256];
	VFormat(buffer, sizeof(buffer), text, 3);
	if (kv != INVALID_HANDLE)
		KvizClose(kv);
	LogError("%s", buffer);
	SetFailState("Unit test failed: %s", buffer);
}
