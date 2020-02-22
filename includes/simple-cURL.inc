#if defined _simple_curl_included
 #endinput
#endif
#define _simple_curl_included

#include <cURL>







new SC_CURL_Default_Opts[][2] = {
	{_:CURLOPT_NOSIGNAL,1},
	{_:CURLOPT_NOPROGRESS,1},
	{_:CURLOPT_TIMEOUT,30},
	{_:CURLOPT_CONNECTTIMEOUT,60},
	{_:CURLOPT_USE_SSL,CURLUSESSL_TRY},
	{_:CURLOPT_SSL_VERIFYPEER,0},
	{_:CURLOPT_SSL_VERIFYHOST,0},
	{_:CURLOPT_VERBOSE,0}
};

functag cURL_Result public(bool:success, const String:filename[]);

new Handle:SC_kvData = INVALID_HANDLE;

stock cURL_Get(const String:url[], cURL_Result:callback) {
	if (SC_kvData == INVALID_HANDLE) {
		SC_kvData = KvizCreate("Data");
	}
	
	new Handle:curl = curl_easy_init();
	curl_easy_setopt_int_array(curl, SC_CURL_Default_Opts, sizeof(SC_CURL_Default_Opts));
	
	KvizSetNum(SC_kvData, _:callback, "%i.callback", _:curl);
	
	// Create a unique filename
	decl String:filename[128];
	GetPluginFilename(GetMyHandle(), filename, sizeof(filename));
	Format(filename, sizeof(filename), "%s.%i.%i.txt", filename, GetSysTickCount(), GetRandomInt(0, 100000));
	
	KvizSetString(SC_kvData, filename, "%i.filename", _:curl);
	
    new Handle:filehandle = curl_OpenFile(filename, "w");
    curl_easy_setopt_handle(curl, CURLOPT_WRITEDATA, filehandle);
	KvizSetNum(SC_kvData, _:filehandle, "%i.filehandle", _:curl);
	curl_easy_setopt_string(curl, CURLOPT_URL, view_as<any>(url));
    curl_easy_perform_thread(curl, SC_cURL_Done);
}


public SC_cURL_Done(Handle:hndl, CURLcode:code) {
	new cURL_Result:callback = cURL_Result:KvizGetNum(SC_kvData, 0, "%i.callback", _:hndl);
	new Handle:filehandle = Handle:KvizGetNum(SC_kvData, 0, "%i.filehandle", _:hndl);
	decl String:filename[128];
	KvizGetString(SC_kvData, filename, sizeof(filename), "", "%i.filename", _:hndl);
	KvizDelete(SC_kvData, "%i", _:hndl);
	
	new bool:success;
	if (code != CURLE_OK) {
		new String:error_buffer[256];
		curl_easy_strerror(code, error_buffer, sizeof(error_buffer));
		CloseHandle(filehandle);
		
		success = false;
 	} else {
		CloseHandle(filehandle); // Must be closed so it is flushed.
		
		success = true;
	}
	CloseHandle(hndl);
	
	Call_StartFunction(INVALID_HANDLE, callback);
	Call_PushCell(_:success);
	Call_PushString(filename);
	Call_Finish();
	
	DeleteFile(filename);
}

