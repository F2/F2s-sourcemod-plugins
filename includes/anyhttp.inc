/*
AnyHttp
By F2


Features:
- Download the response of a GET request to memory
- Download the response of a POST request (multipart data) to memory  

Public functions:
- bool AnyHttp.Init(): Returns false if no HTTP extension is loaded 
- void AnyHttp.Require(): Calls ThrowError if no HTTP extension is loaded
- bool AnyHttp.Get(const char[] url, AnyHttp_Result callback, any metadata = 0)
- AnyHttpRequest request = AnyHttp.CreatePost(const char[] url, any metadata = 0)
- request.PutFile(const char[] name, const char[] filepath)
- request.PutString(const char[] name, const char[] value)
- bool AnyHttp.Send(AnyHttpRequest request, AnyHttp_Result callback)

Callbacks:
- AnyHttp_Result: 
    public void HttpRequestDone(bool success, const char[] contents, int httpCode, int metadata) { }
    public void HttpRequestDone(bool success, const char[] contents, int httpCode) { }
    public void HttpRequestDone(bool success, const char[] contents) { }


TODO:
- Expose functions that can download to a file
*/

#if defined _anyhttp_included
 #endinput
#endif
#define _anyhttp_included

#if defined REQUIRE_EXTENSIONS
    #define ANYHTTP_REQUIRE_EXTENSIONS
#endif
#undef REQUIRE_EXTENSIONS
#include <cURL>
#include <SteamWorks>
#if defined ANYHTTP_REQUIRE_EXTENSIONS
    #define REQUIRE_EXTENSIONS
#endif

#include <kvizzle_newdecls>
#include <f2stocks>
#include <anyhttp_file>
#include <anyhttp_stringbuilder>
#include <anyhttp_multipart>

#define ANYHTTP_VERSION		     "3.0.0"
#define SimultaneousConnections  16

#pragma dynamic 5242880 // Make sure we can allocate enough space for uploading files. Here's 20MB.

enum AnyHttp_Extension {
    AnyHttpUnknown,
    UseCURL,
    UseSteamWorks,
};

typeset AnyHttp_Result {
    function void (bool success, const char[] contents, int httpCode, int metadata);
    function void (bool success, const char[] contents, int httpCode);
    function void (bool success, const char[] contents);
};



enum struct AnyHttpRequestData {
    Handle extensionHandle;
    bool initialized;
    AnyHttp_Result callback;
    any metadata;
    char filename[128];
    Handle filehandle;
    AnyHttpStringBuilder httpBody;

    KeyValues fields;
    /*  - type (string / file)
        - name
        - value
    */
}

static AnyHttpRequestData requests[SimultaneousConnections];
static int nextConnection = 0;

methodmap AnyHttpRequest {
    property int Id {
        public get() { return view_as<int>(this); }
    }

    property bool IsValid {
        public get() { return this.Id >= 0; }
    }

    property Handle ExtensionHandle {
        public get() { return requests[this.Id].extensionHandle; }
        public set(Handle extensionHandle) {
            requests[this.Id].extensionHandle = extensionHandle;
        }
    }

    property bool Initialized {
        public get() { return requests[this.Id].initialized; }
        public set(bool initialized) {
            requests[this.Id].initialized = initialized;
        }
    }

    property AnyHttp_Result Callback {
        public get() { return requests[this.Id].callback; }
        public set(AnyHttp_Result callback) {
            requests[this.Id].callback = callback;
        }
    }

    property any MetaData {
        public get() { return requests[this.Id].metadata; }
        public set(any metadata) {
            requests[this.Id].metadata = metadata;
        }
    }

    property KeyValues Fields {
        public get() { return requests[this.Id].fields; }
        public set(KeyValues fields) {
            requests[this.Id].fields = fields;
        }
    }

    property Handle FileHandle {
        public get() { return requests[this.Id].filehandle; }
        public set(Handle filehandle) {
            requests[this.Id].filehandle = filehandle;
        }
    }

    public void SetFileName(const char[] filename) {
        strcopy(requests[this.Id].filename, sizeof(requests[].filename), filename);
    }

    public void GetFileName(char[] filename, int size) {
        strcopy(filename, size, requests[this.Id].filename);
    }
    
    public void PutString(const char[] name, const char[] value) {
        KeyValues kv = this.Fields;

        int id = KvizGetNum(kv, 0, ":count") + 1;
        KvizSetString(kv, name, "%i.name", id);
        KvizSetString(kv, "string", "%i.type", id);
        KvizSetString(kv, value, "%i.value", id);
    }

    public void PutFile(const char[] name, const char[] filepath) {
        KeyValues kv = this.Fields;

        int id = KvizGetNum(kv, 0, ":count") + 1;
        KvizSetString(kv, name, "%i.name", id);
        KvizSetString(kv, "file", "%i.type",  id);
        KvizSetString(kv, "true", "%i.cleanup",  id);

        // To avoid locking the file, we copy it to a temporary location.
        // Put the temp file in the same directory as the file to be uploaded
        char tempFilepath[128];
        strcopy(tempFilepath, sizeof(tempFilepath), filepath);
        int posOfDirSeparator = FindCharInString(tempFilepath, '/', true);
        if (posOfDirSeparator == -1)
            posOfDirSeparator = FindCharInString(tempFilepath, '\\', true);
        if (posOfDirSeparator == -1) {
            tempFilepath = "";
        } else {
            tempFilepath[posOfDirSeparator + 1] = '\0';
        }

        char tempFilename[128];
        GenerateUniqueFilename(tempFilename, sizeof(tempFilename));
        StrCat(tempFilepath, sizeof(tempFilepath), tempFilename);

        KvizSetString(kv, tempFilepath, "%i.value", id);
        KvizSetNum(kv, 0, "%i.ready", id);
        KvizSetString(kv, filepath, "%i.originalPath", id);

        // We copy the file in the background. 
        // Copying files directly lags the server, which reveals a round-end to SourceTV viewers.

        DataPack pack = new DataPack();
        pack.WriteCell(kv);
        pack.WriteCell(id);
        AnyHttp_CopyFile(filepath, tempFilepath, AnyHttp_PutFile_Finished, pack);
    }

    public bool IsReadyToSend() {
        // Checks that all files are ready to be sent.

        if (this.Fields != null) {
            char type[64];
            for (int i = 1; KvizGetStringExact(this.Fields, type, sizeof(type), "%i.type", i); i++) {
                if (StrEqual(type, "file")) {
                    int ready = 0;
                    if (!KvizGetNumExact(this.Fields, ready, "%i.ready", i))
                        ThrowError("'ready' should always be present - %i", i);
                    
                    if (ready == 0)
                        return false;
                }
            }
        }

        return true;
    }
};
static AnyHttpRequest InvalidRequest = view_as<AnyHttpRequest>(-1);


public void AnyHttp_PutFile_Finished(bool success, DataPack pack) {
    pack.Reset();
    KeyValues kv = pack.ReadCell();
    int id = pack.ReadCell();
    delete pack;

    if (!success) {
        char originalFilepath[128], tempFilepath[128];
        KvizGetStringExact(kv, originalFilepath, sizeof(originalFilepath), "%i.originalPath", id);
        KvizGetStringExact(kv, tempFilepath, sizeof(tempFilepath), "%i.value", id);
        KvizSetString(kv, originalFilepath, "%i.value", id);
        KvizSetString(kv, "false", "%i.cleanup", id);

        LogError("Could not copy file from %s to %s", originalFilepath, tempFilepath);
    }

    KvizSetNum(kv, 1, "%i.ready", id);
}


enum struct AnyHttpClass {
    AnyHttp_Extension Extension;
    bool IsInitialized;

    bool Init() {
        if (this.IsInitialized)
            return true;
        
        if (this.Extension == AnyHttpUnknown) {
            if (LibraryExists("SteamWorks")) {
                this.Extension = UseSteamWorks;
#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR <= 10
            } else if (GetFeatureStatus(FeatureType_Native, "curl_easy_init") == FeatureStatus_Available) {
                // Initializing cURL options doesn't work on SM 1.11 at the moment. /F2, 09/07/2022
                this.Extension = UseCURL;
#endif
            } else {
                return false;
            }
        }
        
        this.IsInitialized = true;
        return true;
    }
    
    void Require() {
        if (!this.Init())
            ThrowError("Missing HTTP extension (e.g. SteamWorks)");
    }
    
    bool Get(const char[] url, AnyHttp_Result callback, any metadata = 0) {
        if (!this.Init())
            return false;
        
        if (this.Extension == UseSteamWorks) {
            return SteamWorks_Get(url, callback, metadata);
        } else if (this.Extension == UseCURL) {
            return cURL_Get(url, callback, metadata);
        } else {
            ThrowError("Unknown extension");
            return false; // Avoid compiler warning
        }
    }
    
    AnyHttpRequest CreatePost(const char[] url, any metadata = 0) {
        if (!this.Init())
            return InvalidRequest;
    
        if (this.Extension == UseSteamWorks) {
            return SteamWorks_CreatePostForm(url, metadata);
        } else if (this.Extension == UseCURL) {
            return cURL_CreatePostForm(url, metadata);
        } else {
            ThrowError("Unknown extension");
            return InvalidRequest; // Avoid compiler warning
        }
    }
    
    void Send(AnyHttpRequest request, AnyHttp_Result callback) {
        request.Callback = callback;

        AnyHttp_SendWhenReady(null, request);
    }
}
stock AnyHttpClass AnyHttp;

public Action AnyHttp_SendWhenReady(Handle timer, AnyHttpRequest request) {
    if (!request.IsReadyToSend()) {
        CreateTimer(0.5, AnyHttp_SendWhenReady, request);
        return Plugin_Stop;
    }

    bool success = false;
    if (AnyHttp.Extension == UseSteamWorks) {
        SteamWorks_SendPostForm(request);
        success = true;
    } else if (AnyHttp.Extension == UseCURL) {
        success = cURL_SendPostForm(request);
    } else {
        ThrowError("Unknown extension");
    }

    if (!success) {
        Call_StartFunction(null, request.Callback);
        Call_PushCell(false);
        Call_PushString("");
        Call_PushCell(0);
        Call_PushCell(request.MetaData);
        CleanUpRequest(request);
        Call_Finish();
    }
    return Plugin_Stop;
}



// Common private functions

static AnyHttpRequest NewRequest() {
    int id = (nextConnection++) % SimultaneousConnections;
    AnyHttpRequest request = view_as<AnyHttpRequest>(id);

    if (request.Initialized) {
        CleanUpRequest(request);
    }

    request.ExtensionHandle = null;
    request.Initialized = true;
    //request.Callback = null;
    request.MetaData = 0;
    request.Fields = KvizCreate("field");
    request.SetFileName("");
    request.FileHandle = null;
    requests[request.Id].httpBody.Init();

    return request;
}

static void CleanUpRequest(AnyHttpRequest request) {
    if (!request.Initialized)
        return;
    
    request.Initialized = false;
    if (request.ExtensionHandle != null) {
        CloseHandle(request.ExtensionHandle);
        request.ExtensionHandle = null;
    }
    if (request.FileHandle != null) {
        CloseHandle(request.FileHandle);
        request.FileHandle = null;
    }
    if (request.Fields != null) {
        char type[64];
        for (int i = 1; KvizGetStringExact(request.Fields, type, sizeof(type), "%i.type", i); i++) {
            if (StrEqual(type, "file")) {
                char cleanup[16];
                KvizGetStringExact(request.Fields, cleanup, sizeof(cleanup), "%i.cleanup", i);
                if (StrEqual(cleanup, "true")) {
                    char filepath[1024];
                    KvizGetStringExact(request.Fields, filepath, sizeof(filepath), "%i.value", i);
                    if (!DeleteFile(filepath, false))
                        LogError("Could not delete %s", filepath);
                }
            }
        }

        KvizClose(request.Fields);
        request.Fields = null;
    }
    requests[request.Id].httpBody.Dispose();
}

static bool FindRequestByHandle(Handle handle, AnyHttpRequest &request) {
    for (int i = 0; i < SimultaneousConnections; i++) {
        if (requests[i].initialized) {
            if (requests[i].extensionHandle == handle) {
                request = view_as<AnyHttpRequest>(i);
                return true;
            }
        }
    }

    return false;
}


static void GenerateUniqueFilename(char[] filename, int maxsize) {
    char pluginFilepath[PLATFORM_MAX_PATH];
    GetPluginFilename(GetMyHandle(), pluginFilepath, sizeof(pluginFilepath));
    char pluginFilename[PLATFORM_MAX_PATH];
    F2_GetFileName(pluginFilename, sizeof(pluginFilename), pluginFilepath);
    Format(filename, maxsize, "%s.%i.%i.txt", pluginFilename, GetSysTickCount(), GetRandomInt(0, 100000));
}






// =========== SteamWorks ============

static bool SteamWorks_Get(const char[] url, AnyHttp_Result callback, any metadata = 0) {
    Handle handle = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, url);
    
    AnyHttpRequest request = NewRequest();
    request.ExtensionHandle = handle;
    request.Callback = callback;
    request.MetaData = metadata;

    if (!SteamWorks_SetHTTPCallbacks(handle, SteamWorks_Done) || !SteamWorks_SendHTTPRequest(handle)) {
        CleanUpRequest(request);
        return false;
    }

    return true;
}


static AnyHttpRequest SteamWorks_CreatePostForm(const char[] url, any metadata = 0) {
    AnyHttpRequest request = NewRequest();
    request.ExtensionHandle = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, url);
    request.MetaData = metadata;
    return request;
}

static void SteamWorks_SendPostForm(AnyHttpRequest request) {
    AnyHttp_CreateMultipartRequest(request.Fields, SteamWorks_SendPostForm_RequestCreated, request);
}

static void SteamWorks_SendPostForm_RequestCreated(bool success, AnyHttpStringBuilder sb, AnyHttpRequest request) {
    char contentType[256] = "multipart/form-data; boundary=";
    StrCat(contentType, sizeof(contentType), AnyHttp_MultiPartBoundary);

    int len = sb.Length();
    char[] buffer = new char[len + 1];
    sb.CopyToString(buffer, len + 1);
    sb.Dispose();
    
    if (!SteamWorks_SetHTTPRequestRawPostBody(request.ExtensionHandle, contentType, buffer, len) ||
        !SteamWorks_SetHTTPCallbacks(request.ExtensionHandle, SteamWorks_Done) || 
        !SteamWorks_SendHTTPRequest(request.ExtensionHandle)) 
    {
        SteamWorks_Done(request.ExtensionHandle, true, false, k_EHTTPStatusCodeInvalid);
    }
}

static void SteamWorks_Done(Handle HTTPRequest, bool bFailure, bool requestSuccessful, EHTTPStatusCode statusCode) {
    AnyHttpRequest request;
    if (!FindRequestByHandle(HTTPRequest, request)) {
        return;
    }

    int size = 0;
    if (requestSuccessful)
        SteamWorks_GetHTTPResponseBodySize(HTTPRequest, size);
    
    char[] buffer = new char[size];
    
    Call_StartFunction(null, request.Callback);
    Call_PushCell(requestSuccessful);
    
    if (requestSuccessful) {
        SteamWorks_GetHTTPResponseBodyData(HTTPRequest, buffer, size);
        Call_PushString(buffer);
    } else {
        Call_PushString("");
    }

    Call_PushCell(statusCode);
    Call_PushCell(request.MetaData);
    CleanUpRequest(request);
    Call_Finish();
}







// =========== CURL ============

static int CURL_Default_Opts[][2] = {
    {view_as<int>(CURLOPT_NOSIGNAL), 1},
    {view_as<int>(CURLOPT_NOPROGRESS), 1},
    {view_as<int>(CURLOPT_TIMEOUT), 30},
    {view_as<int>(CURLOPT_CONNECTTIMEOUT), 60},
    {view_as<int>(CURLOPT_USE_SSL), CURLUSESSL_TRY},
    {view_as<int>(CURLOPT_SSL_VERIFYPEER), 0},
    {view_as<int>(CURLOPT_SSL_VERIFYHOST), 0},
    {view_as<int>(CURLOPT_VERBOSE), 0}
};

static bool cURL_Get(const char[] url, AnyHttp_Result callback, any metadata = 0) {
    Handle curl = curl_easy_init();
    if (curl == null)
        return false;
    if (!curl_easy_setopt_int_array(curl, CURL_Default_Opts, sizeof(CURL_Default_Opts))) {
        LogError("Couldn't set cURL options");
        CloseHandle(curl);
        return false;
    }

    AnyHttpRequest request = NewRequest();
    request.ExtensionHandle = curl;
    request.Callback = callback;
    request.MetaData = metadata;
    
    char filename[128];
    GenerateUniqueFilename(filename, sizeof(filename));
    request.SetFileName(filename);
    
    Handle filehandle = curl_OpenFile(filename, "wb");
    if (filehandle == null) {
        CleanUpRequest(request);
        return false;
    }

    if (!curl_easy_setopt_handle(curl, CURLOPT_WRITEDATA, filehandle)) {
        CleanUpRequest(request);
        return false;
    }

    request.FileHandle = filehandle;
    if (!curl_easy_setopt_string(curl, CURLOPT_URL, url)) {
        CleanUpRequest(request);
        return false;
    }

    curl_easy_perform_thread(curl, cURL_Done);
    return true;
}



static AnyHttpRequest cURL_CreatePostForm(const char[] url, any metadata = 0) {
    Handle handle = curl_easy_init();
    if (handle == null)
        return InvalidRequest;
    if (!curl_easy_setopt_int_array(handle, CURL_Default_Opts, sizeof(CURL_Default_Opts))) {
        LogError("Couldn't set cURL options");
        CloseHandle(handle);
        return InvalidRequest;
    }
    if (!curl_easy_setopt_string(handle, CURLOPT_URL, url)) {
        CloseHandle(handle);
        return InvalidRequest;
    }
    
    AnyHttpRequest request = NewRequest();
    request.ExtensionHandle = handle;
    request.MetaData = metadata;
    
    return request;
}

static bool cURL_SendPostForm(AnyHttpRequest request) {
    Handle hCurlForm = curl_httppost();
    char type[64];
    
    for (int i = 1; KvizGetStringExact(request.Fields, type, sizeof(type), "%i.type", i); i++) {
        if (StrEqual(type, "string")) {
            char name[1024];
            KvizGetStringExact(request.Fields, name, sizeof(name), "%i.name", i);
            char contents[1024];
            KvizGetStringExact(request.Fields, contents, sizeof(contents), "%i.value", i);
            if (curl_formadd(hCurlForm, CURLFORM_COPYNAME, name, CURLFORM_COPYCONTENTS, contents, CURLFORM_END) != CURL_FORMADD_OK) {
                CleanUpRequest(request);
                return false;
            }
        } else if (StrEqual(type, "file")) {
            char name[1024];
            KvizGetStringExact(request.Fields, name, sizeof(name), "%i.name", i);
            char filepath[PLATFORM_MAX_PATH];
            KvizGetStringExact(request.Fields, filepath, sizeof(filepath), "%i.value", i);
            if (curl_formadd(hCurlForm, CURLFORM_COPYNAME, name, CURLFORM_FILE, filepath, CURLFORM_END) != CURL_FORMADD_OK) {
                CleanUpRequest(request);
                return false;
            }
        } else {
            ThrowError("Unknown type");
        }
    }
    
    if (!curl_easy_setopt_handle(request.ExtensionHandle, CURLOPT_HTTPPOST, hCurlForm)) {
        CleanUpRequest(request);
        return false;
    }
    
    char filename[128];
    GenerateUniqueFilename(filename, sizeof(filename));
    request.SetFileName(filename);
    
    Handle filehandle = curl_OpenFile(filename, "w");
    if (filehandle == null) {
        CleanUpRequest(request);
        return false;
    }
    
    request.FileHandle = filehandle;

    if (!curl_easy_setopt_handle(request.ExtensionHandle, CURLOPT_WRITEDATA, filehandle)) {
        CleanUpRequest(request);
        return false;
    }

    curl_easy_perform_thread(request.ExtensionHandle, cURL_Done);
    return true;
}

static void cURL_Done(Handle hndl, CURLcode code) {
    AnyHttpRequest request;
    if (!FindRequestByHandle(hndl, request)) {
        return;
    }

    Handle filehandle = request.FileHandle;
    char filename[128];
    request.GetFileName(filename, sizeof(filename));
    
    int responseCode = 0;
    bool success;
    int size = 0;
    if (code != CURLE_OK) {
        char error_buffer[256];
        curl_easy_strerror(code, error_buffer, sizeof(error_buffer));
        CloseHandle(filehandle);
        request.FileHandle = null;
        
        LogError("cURL error: %s", error_buffer);
        
        success = false;
     } else {
        CloseHandle(filehandle); // Must be closed so it is flushed.
        request.FileHandle = null;

        curl_easy_getinfo_int(hndl, CURLINFO_RESPONSE_CODE, responseCode);

        success = true;
        size = FileSize(filename);
    }
    
    char[] buffer = new char[size + 1];
    buffer[0] = '\0';
    
    Call_StartFunction(null, request.Callback);
    Call_PushCell(success);
    
    if (success) {
        File fileHandle = OpenFile(filename, "r");
        if (fileHandle != null) { 
            ReadFileString(fileHandle, buffer, size + 1);
            CloseHandle(fileHandle);
        }
        
        Call_PushString(buffer);
    } else {
        Call_PushString("");
    }
    DeleteFile(filename);
    
    Call_PushCell(responseCode);
    Call_PushCell(request.MetaData);

    CleanUpRequest(request);
    Call_Finish();
}


// Mark HTTP extensions as optional

public void __ext_curl_SetNTVOptional()
{
    MarkNativeAsOptional("curl_easy_init");
    MarkNativeAsOptional("curl_easy_setopt_string");
    MarkNativeAsOptional("curl_easy_setopt_int");
    MarkNativeAsOptional("curl_easy_setopt_int_array");
    MarkNativeAsOptional("curl_easy_setopt_int64");
    MarkNativeAsOptional("curl_easy_setopt_handle");
    MarkNativeAsOptional("curl_easy_setopt_function");
    MarkNativeAsOptional("curl_load_opt");
    MarkNativeAsOptional("curl_easy_perform");
    MarkNativeAsOptional("curl_easy_perform_thread");
    MarkNativeAsOptional("curl_easy_send_recv");
    MarkNativeAsOptional("curl_send_recv_Signal");
    MarkNativeAsOptional("curl_send_recv_IsWaiting");
    MarkNativeAsOptional("curl_set_send_buffer");
    MarkNativeAsOptional("curl_set_receive_size");
    MarkNativeAsOptional("curl_set_send_timeout");
    MarkNativeAsOptional("curl_set_recv_timeout");
    MarkNativeAsOptional("curl_get_error_buffer");
    MarkNativeAsOptional("curl_easy_getinfo_string");
    MarkNativeAsOptional("curl_easy_getinfo_int");
    MarkNativeAsOptional("curl_easy_escape");
    MarkNativeAsOptional("curl_easy_unescape");
    MarkNativeAsOptional("curl_easy_strerror");
    MarkNativeAsOptional("curl_version");
    MarkNativeAsOptional("curl_protocols");
    MarkNativeAsOptional("curl_features");
    MarkNativeAsOptional("curl_OpenFile");
    MarkNativeAsOptional("curl_httppost");
    MarkNativeAsOptional("curl_formadd");
    MarkNativeAsOptional("curl_slist");
    MarkNativeAsOptional("curl_slist_append");
    MarkNativeAsOptional("curl_hash_file");
    MarkNativeAsOptional("curl_hash_string");
}