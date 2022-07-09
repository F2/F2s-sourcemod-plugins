/*
AnyHttp
By F2


Features:
- Download the response of a GET request to memory
- Download the response of a POST request (multipart data) to memory  

Public functions:
- bool AnyHttp.Init(): Returns false if no HTTP extension is loaded 
- void AnyHttp.Require(): Calls ThrowError if no HTTP extension is loaded
- void AnyHttp.Get(const char[] url, AnyHttp_Result callback, int metadata = 0)
- AnyHttpForm form = AnyHttp.CreatePost(const char[] url)
- form.PutFile(const char[] name, const char[] filepath)
- form.PutString(const char[] name, const char[] value)
- form.Send(AnyHttp_Result callback)

Callbacks:
- AnyHttp_Result: public void HttpRequestDone(bool success, const char[] contents, int metadata) { }


TODO:
- Expose functions that can download to a file
*/

#if defined _anyhttp2_included
 #endinput
#endif
#define _anyhttp2_included

#if defined REQUIRE_EXTENSIONS
    #define ANYHTTP_REQUIRE_EXTENSIONS
#endif

#undef REQUIRE_EXTENSIONS
#include <cURL>
#include <SteamWorks>
#if defined ANYHTTP_REQUIRE_EXTENSIONS
    #define REQUIRE_EXTENSIONS
#endif

#include <kvizzle>

#define ANYHTTP_VERSION		     "2.0.0"
#define SimultaneousConnections  16
#define MaxFilenameLength        128

#pragma dynamic 20971520 // Make sure we can allocate enough space for uploading files. Here's 20MB.
#pragma newdecls required

enum AnyHttp_Extension {
    AnyHttpUnknown,
    UseCURL,
    UseSteamWorks,
};


//typedef AnyHttp_Result = function void (bool success, const char[] contents);
typedef AnyHttp_Result = function void (bool success, const char[] contents, int httpCode, int metadata);


static AnyHttp_Extension CurrentExtension = AnyHttpUnknown;


enum struct AnyHttpRequest {
    Handle extensionHandle;
    bool initialized;
    AnyHttp_Result callback;
    any metadata;
    char filename[128];
    Handle filehandle;

    Handle fields;
    /*  - type (string / file)
        - name
        - value
    */
}

static AnyHttpRequest requests[SimultaneousConnections];
static int nextConnection = 0;

methodmap AnyHttpForm {
    property int Id {
        public get() {
            return view_as<int>(this);
        }
    }

    property bool IsValid {
        public get() {
            return this.Id >= 0;
        }
    }

    property Handle ExtensionHandle {
        public get() {
            return requests[this.Id].extensionHandle;
        }
        public set(Handle extensionHandle) {
            requests[this.Id].extensionHandle = extensionHandle;
        }
    }

    property bool Initialized {
        public get() {
            return requests[this.Id].initialized;
        }
        public set(bool initialized) {
            requests[this.Id].initialized = initialized;
        }
    }

    property AnyHttp_Result Callback {
        public get() {
            return requests[this.Id].callback;
        }
        public set(AnyHttp_Result callback) {
            requests[this.Id].callback = callback;
        }
    }

    property any MetaData {
        public get() {
            return requests[this.Id].metadata;
        }
        public set(any metadata) {
            requests[this.Id].metadata = metadata;
        }
    }

    property Handle Fields {
        public get() {
            return requests[this.Id].fields;
        }
        public set(Handle fields) {
            requests[this.Id].fields = fields;
        }
    }

    property Handle FileHandle {
        public get() {
            return requests[this.Id].filehandle;
        }
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

    public void PutFile(const char[] name, const char[] filepath) {
        Handle kv = this.Fields;
    
        int id = KvizGetNum(kv, 0, ":count") + 1;
        KvizSetString(kv, name, "%i.name", id);
        KvizSetString(kv, "file", "%i.type",  id);
        KvizSetString(kv, filepath, "%i.value", id);
    }
    
    public void PutString(const char[] name, const char[] value) {
        Handle kv = this.Fields;

        int id = KvizGetNum(kv, 0, ":count") + 1;
        KvizSetString(kv, name, "%i.name", id);
        KvizSetString(kv, "string", "%i.type", id);
        KvizSetString(kv, value, "%i.value", id);
    }
    
    public bool Send(AnyHttp_Result callback) {
        this.Callback = callback;

        if (CurrentExtension == UseSteamWorks) {
            return AnyHttp_SteamWorks_SendPostForm(this);
        } else if (CurrentExtension == UseCURL) {
            return AnyHttp_cURL_SendPostForm(this);
        } else {
            ThrowError("Unknown extension");
            return false; // Avoid compiler warning
        }
    }
};
static AnyHttpForm InvalidForm = view_as<AnyHttpForm>(-1);

methodmap AnyHttpClass {
    public bool Init() {
        return AnyHttp_Initialize();
    }
    
    public void Require() {
        if (!this.Init())
            ThrowError("Missing HTTP extension");
    }
    
    public bool Get(const char[] url, AnyHttp_Result callback, int metadata = 0) {
        return AnyHttp_Get(url, callback, metadata);
    }
    
    public AnyHttpForm CreatePost(const char[] url) {
        return AnyHttp_CreatePostForm(url);
    }
    
    property AnyHttp_Extension Extension {
        public get() { return CurrentExtension; }
        public set(AnyHttp_Extension value) { CurrentExtension = value; }
    }
};
stock AnyHttpClass AnyHttp;



static bool IsInitialized = false;
static char MultiPartBoundary[] = "--------------------AnyHttp--AnyHttp--h7doWqx7m--";




// Public functions

static bool AnyHttp_Initialize() {
    if (IsInitialized)
        return true;
    
    if (CurrentExtension == AnyHttpUnknown) {
        if (LibraryExists("SteamWorks")) {
            CurrentExtension = UseSteamWorks;
        }
#if SOURCEMOD_V_MAJOR == 1 && SOURCEMOD_V_MINOR <= 10
        // Initializing cURL options doesn't work on SM 1.11 at the moment. /F2, 09/07/2022
        else if (GetFeatureStatus(FeatureType_Native, "curl_easy_init") == FeatureStatus_Available) {
            CurrentExtension = UseCURL;
#endif
        } else {
            return false;
        }
    }
    
    IsInitialized = true;
    return true;
}

static bool AnyHttp_Get(const char[] url, AnyHttp_Result callback, int metadata = 0) {
    if (!AnyHttp_Initialize())
        return false;
    
    if (CurrentExtension == UseSteamWorks) {
        return AnyHttp_SteamWorks_Get(url, callback, metadata);
    } else if (CurrentExtension == UseCURL) {
        return AnyHttp_cURL_Get(url, callback, metadata);
    } else {
        ThrowError("Unknown extension");
        return false; // Avoid compiler warning
    }
}

static AnyHttpForm AnyHttp_CreatePostForm(const char[] url) {
    if (!AnyHttp_Initialize())
        return InvalidForm;
    
    if (CurrentExtension == UseSteamWorks) {
        return AnyHttp_SteamWorks_CreatePostForm(url);
    } else if (CurrentExtension == UseCURL) {
        return AnyHttp_cURL_CreatePostForm(url);
    } else {
        ThrowError("Unknown extension");
        return InvalidForm; // Avoid compiler warning
    }
}


// Common private functions

static AnyHttpForm AnyHttp_NewRequest() {
    int id = (nextConnection++) % SimultaneousConnections;
    AnyHttpForm request = view_as<AnyHttpForm>(id);

    if (request.Initialized) {
        if (request.ExtensionHandle != null)
            CloseHandle(request.ExtensionHandle);
        KvizClose(request.Fields);
    }

    request.ExtensionHandle = null;
    request.Initialized = true;
    //request.Callback = null;
    request.MetaData = 0;
    request.Fields = KvizCreate("field");
    request.SetFileName("");
    request.FileHandle = null;

    return request;
}

static void AnyHttp_CleanUp(AnyHttpForm request) {
    request.Initialized = false;
    if (request.ExtensionHandle != null) {
        CloseHandle(request.ExtensionHandle);
        request.ExtensionHandle = null;
    }
    if (request.FileHandle != null) {
        CloseHandle(request.FileHandle);
        request.FileHandle = null;
    }
    KvizClose(request.Fields);
}

static bool FindRequestByHandle(Handle handle, AnyHttpForm &request) {
    for (int i = 0; i < SimultaneousConnections; i++) {
        if (requests[i].initialized) {
            if (requests[i].extensionHandle == handle) {
                request = view_as<AnyHttpForm>(i);
                return true;
            }
        }
    }

    return false;
}

static void AnyHttp_GetFileName(char[] filename, int maxsize, const char[] filepath) {
    int lastBackSlash = FindCharInString(filepath, '\\', true);
    int lastForwardSlash = FindCharInString(filepath, '/', true);
    if (lastBackSlash == -1 && lastForwardSlash == -1) {
        strcopy(filename, maxsize, filepath);
    } else {
        int pos = lastBackSlash > lastForwardSlash ? lastBackSlash : lastForwardSlash;
        strcopy(filename, maxsize, filepath[pos + 1]);
    }
}

static void AnyHttp_AppendMultipartString(char[] buffer, int &bufferPos, int maxsize, const char[] name, const char[] contents, bool computeLength) {
    bufferPos += AnyHttp_CopyBytes(buffer, maxsize, "--", bufferPos, 0, computeLength);
    bufferPos += AnyHttp_CopyBytes(buffer, maxsize, MultiPartBoundary, bufferPos, 0, computeLength);
    
    bufferPos += AnyHttp_CopyBytes(buffer, maxsize, "\nContent-Disposition: form-data; name=\"", bufferPos, 0, computeLength);
    bufferPos += AnyHttp_CopyBytes(buffer, maxsize, name, bufferPos, 0, computeLength);
    bufferPos += AnyHttp_CopyBytes(buffer, maxsize, "\"\n\n", bufferPos, 0, computeLength);
    bufferPos += AnyHttp_CopyBytes(buffer, maxsize, contents, bufferPos, 0, computeLength);
    bufferPos += AnyHttp_CopyBytes(buffer, maxsize, "\n", bufferPos, 0, computeLength);
}

static bool AnyHttp_AppendMultipartFile(char[] buffer, int &bufferPos, int maxsize, const char[] name, const char[] filepath, bool computeLength) {
    char filename[PLATFORM_MAX_PATH];
    AnyHttp_GetFileName(filename, sizeof(filename), filepath);
        
    bufferPos += AnyHttp_CopyBytes(buffer, maxsize, "--", bufferPos, 0, computeLength);
    bufferPos += AnyHttp_CopyBytes(buffer, maxsize, MultiPartBoundary, bufferPos, 0, computeLength);
    
    bufferPos += AnyHttp_CopyBytes(buffer, maxsize, "\nContent-Disposition: form-data; name=\"", bufferPos, 0, computeLength);
    bufferPos += AnyHttp_CopyBytes(buffer, maxsize, name, bufferPos, 0, computeLength);
    bufferPos += AnyHttp_CopyBytes(buffer, maxsize, "\"; filename=\"", bufferPos, 0, computeLength);
    bufferPos += AnyHttp_CopyBytes(buffer, maxsize, filename, bufferPos, 0, computeLength);
    bufferPos += AnyHttp_CopyBytes(buffer, maxsize, "\"\n\n", bufferPos, 0, computeLength);
    
    int filesize = FileSize(filepath);
    if (computeLength) {
        bufferPos += filesize;
    } else {
        File filehandle = OpenFile(filepath, "rb");
        if (filehandle == null)
            return false;
        for (int i = 0; i < filesize; i++) {
            int byte;
            if (!filehandle.ReadUint8(byte))
                return false;
            buffer[bufferPos++] = view_as<char>(byte);
        }
        filehandle.Close();
    }
    
    bufferPos += AnyHttp_CopyBytes(buffer, maxsize, "\n", bufferPos, 0, computeLength);
    return true;
}

static void AppendMultipartEnd(char[] buffer, int &bufferPos, int maxsize, bool computeLength) {
    bufferPos += AnyHttp_CopyBytes(buffer, maxsize, "--", bufferPos, 0, computeLength);
    bufferPos += AnyHttp_CopyBytes(buffer, maxsize, MultiPartBoundary, bufferPos, 0, computeLength);
    bufferPos += AnyHttp_CopyBytes(buffer, maxsize, "--", bufferPos, 0, computeLength);
}

static int AnyHttp_CopyBytes(char[] dest, int destSize, const char[] src, int destPos, int srcPos, bool computeLength, int bytes = -1) {
    int bytesCopied = 0;
    if (bytes == -1)
        bytes = strlen(src);
    if (computeLength)
        return bytes;
    while (destPos < destSize && bytesCopied < bytes) {
        dest[destPos++] = src[srcPos++];
        bytesCopied++;
    }
    if (bytesCopied < bytes)
        ThrowError("AnyHttp: Not enough space allocated");
    return bytesCopied;
}

static void AnyHttp_GenerateUniqueFilename(char[] filename, int maxsize) {
    GetPluginFilename(GetMyHandle(), filename, maxsize);
    Format(filename, maxsize, "%s.%i.%i.txt", filename, GetSysTickCount(), GetRandomInt(0, 100000));
}






// =========== SteamWorks ============

static bool AnyHttp_SteamWorks_Get(const char[] url, AnyHttp_Result callback, int metadata = 0) {
    Handle handle = SteamWorks_CreateHTTPRequest(k_EHTTPMethodGET, url);
    
    AnyHttpForm request = AnyHttp_NewRequest();
    request.ExtensionHandle = handle;
    request.Callback = callback;
    request.MetaData = metadata;

    if (!SteamWorks_SetHTTPCallbacks(handle, AnyHttp_SteamWorks_Done) || !SteamWorks_SendHTTPRequest(handle)) {
        CloseHandle(handle);
        return false;
    }

    return true;
}


static AnyHttpForm AnyHttp_SteamWorks_CreatePostForm(const char[] url) {
    AnyHttpForm request = AnyHttp_NewRequest();
    request.ExtensionHandle = SteamWorks_CreateHTTPRequest(k_EHTTPMethodPOST, url);
    return request;
}

static bool AnyHttp_SteamWorks_SendPostForm(AnyHttpForm request) {
    int length = AnyHttp_SteamWorks_SendPostForm_Internal(request, 0);
    if (length < 0 || AnyHttp_SteamWorks_SendPostForm_Internal(request, length) < 0) { 
        AnyHttp_CleanUp(request);
        return false;
    }
    return true;
}

static int AnyHttp_SteamWorks_SendPostForm_Internal(AnyHttpForm request, int bufferSize) {
    char type[64];
    char[] buffer = new char[bufferSize];
    int bufferPos = 0;
    
    for (int i = 1; KvizGetStringExact(request.Fields, type, sizeof(type), "%i.type", i); i++) {
        if (StrEqual(type, "string")) {
            char name[1024];
            KvizGetStringExact(request.Fields, name, sizeof(name), "%i.name", i);
            char contents[1024];
            KvizGetStringExact(request.Fields, contents, sizeof(contents), "%i.value", i);
            AnyHttp_AppendMultipartString(buffer, bufferPos, bufferSize, name, contents, bufferSize == 0);
        } else if (StrEqual(type, "file")) {
            char name[1024];
            KvizGetStringExact(request.Fields, name, sizeof(name), "%i.name", i);
            char filepath[1024];
            KvizGetStringExact(request.Fields, filepath, sizeof(filepath), "%i.value", i);
            if (!AnyHttp_AppendMultipartFile(buffer, bufferPos, bufferSize, name, filepath, bufferSize == 0))
                return -1;
        } else {
            ThrowError("Unknown type");
        }
    }
    AppendMultipartEnd(buffer, bufferPos, bufferSize, bufferSize == 0);
    
    if (bufferSize == 0) {
        return bufferPos;
    }
    
    char contentType[256] = "multipart/form-data; boundary=";
    StrCat(contentType, sizeof(contentType), MultiPartBoundary);
    
    SteamWorks_SetHTTPRequestRawPostBody(request.ExtensionHandle, contentType, buffer, bufferPos);
    
    if (!SteamWorks_SetHTTPCallbacks(request.ExtensionHandle, AnyHttp_SteamWorks_Done) || !SteamWorks_SendHTTPRequest(request.ExtensionHandle)) {
        return -1;
    }
    
    return bufferPos;
}

public void AnyHttp_SteamWorks_Done(Handle HTTPRequest, bool bFailure, bool requestSuccessful, EHTTPStatusCode statusCode) {
    AnyHttpForm request;
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
    AnyHttp_CleanUp(request);
    Call_Finish();
}












// // =========== CURL ============

static int CURL_Default_Opts[][2] = {
    {view_as<int>(CURLOPT_NOSIGNAL),1},
    {view_as<int>(CURLOPT_NOPROGRESS),1},
    {view_as<int>(CURLOPT_TIMEOUT),30},
    {view_as<int>(CURLOPT_CONNECTTIMEOUT),60},
    {view_as<int>(CURLOPT_USE_SSL),CURLUSESSL_TRY},
    {view_as<int>(CURLOPT_SSL_VERIFYPEER),0},
    {view_as<int>(CURLOPT_SSL_VERIFYHOST),0},
    {view_as<int>(CURLOPT_VERBOSE),0}
};
// int CURL_Default_Opts[][2] = {
// 	{_:CURLOPT_NOSIGNAL,1},
// 	{_:CURLOPT_NOPROGRESS,1},
// 	{_:CURLOPT_TIMEOUT,30},
// 	{_:CURLOPT_CONNECTTIMEOUT,60},
// 	{_:CURLOPT_USE_SSL,CURLUSESSL_TRY},
// 	{_:CURLOPT_SSL_VERIFYPEER,0},
// 	{_:CURLOPT_SSL_VERIFYHOST,0},
// 	{_:CURLOPT_VERBOSE,0}
// };

stock bool AnyHttp_cURL_Get(const char[] url, AnyHttp_Result callback, int metadata = 0) {
    Handle curl = curl_easy_init();
    if (curl == null)
        return false;
    if (!curl_easy_setopt_int_array(curl, CURL_Default_Opts, sizeof(CURL_Default_Opts))) {
        LogError("Couldn't set cURL options");
        CloseHandle(curl);
        return false;
    }

    AnyHttpForm request = AnyHttp_NewRequest();
    request.ExtensionHandle = curl;
    request.Callback = callback;
    request.MetaData = metadata;
    
    char filename[128];
    AnyHttp_GenerateUniqueFilename(filename, sizeof(filename));
    request.SetFileName(filename);
    
    Handle filehandle = curl_OpenFile(filename, "wb");
    if (filehandle == null) {
        AnyHttp_CleanUp(request);
        return false;
    }

    if (!curl_easy_setopt_handle(curl, CURLOPT_WRITEDATA, filehandle)) {
        AnyHttp_CleanUp(request);
        return false;
    }

    request.FileHandle = filehandle;
    if (!curl_easy_setopt_string(curl, CURLOPT_URL, url)) {
        AnyHttp_CleanUp(request);
        return false;
    }

    curl_easy_perform_thread(curl, AnyHttp_cURL_Done);
    return true;
}



stock AnyHttpForm AnyHttp_cURL_CreatePostForm(const char[] url) {
    Handle handle = curl_easy_init();
    if (handle == null)
        return InvalidForm;
    if (!curl_easy_setopt_int_array(handle, CURL_Default_Opts, sizeof(CURL_Default_Opts))) {
        LogError("Couldn't set cURL options");
        CloseHandle(handle);
        return InvalidForm;
    }
    if (!curl_easy_setopt_string(handle, CURLOPT_URL, url)) {
        CloseHandle(handle);
        return InvalidForm;
    }
    
    AnyHttpForm request = AnyHttp_NewRequest();
    request.ExtensionHandle = handle;
    
    return request;
}

stock bool AnyHttp_cURL_SendPostForm(AnyHttpForm request) {
    Handle hCurlForm = curl_httppost();
    char type[64];
    
    for (int i = 1; KvizGetStringExact(request.Fields, type, sizeof(type), "%i.type", i); i++) {
        if (StrEqual(type, "string")) {
            char name[1024];
            KvizGetStringExact(request.Fields, name, sizeof(name), "%i.name", i);
            char contents[1024];
            KvizGetStringExact(request.Fields, contents, sizeof(contents), "%i.value", i);
            if (curl_formadd(hCurlForm, CURLFORM_COPYNAME, name, CURLFORM_COPYCONTENTS, contents, CURLFORM_END) != CURL_FORMADD_OK) {
                AnyHttp_CleanUp(request);
                return false;
            }
        } else if (StrEqual(type, "file")) {
            char name[1024];
            KvizGetStringExact(request.Fields, name, sizeof(name), "%i.name", i);
            char filepath[PLATFORM_MAX_PATH];
            KvizGetStringExact(request.Fields, filepath, sizeof(filepath), "%i.value", i);
            if (curl_formadd(hCurlForm, CURLFORM_COPYNAME, name, CURLFORM_FILE, filepath, CURLFORM_END) != CURL_FORMADD_OK) {
                AnyHttp_CleanUp(request);
                return false;
            }
        } else {
            ThrowError("Unknown type");
        }
    }
    
    if (!curl_easy_setopt_handle(request.ExtensionHandle, CURLOPT_HTTPPOST, hCurlForm)) {
        AnyHttp_CleanUp(request);
        return false;
    }
    
    char filename[128];
    AnyHttp_GenerateUniqueFilename(filename, sizeof(filename));
    request.SetFileName(filename);
    
    Handle hCurlOutput = curl_OpenFile(filename, "w");
    if (hCurlOutput == null) {
        AnyHttp_CleanUp(request);
        return false;
    }
    
    request.FileHandle = hCurlOutput;

    if (!curl_easy_setopt_handle(request.ExtensionHandle, CURLOPT_WRITEDATA, hCurlOutput)) {
        AnyHttp_CleanUp(request);
        return false;
    }

    curl_easy_perform_thread(request.ExtensionHandle, AnyHttp_cURL_Done);
    
    return true;
}

public void AnyHttp_cURL_Done(Handle hndl, CURLcode code) {
    AnyHttpForm request;
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
        
        // We are currently not doing anything with the error. Perhaps we could expose it somehow.
        
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

    AnyHttp_CleanUp(request);
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