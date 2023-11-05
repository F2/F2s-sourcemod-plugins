/*
AnyHttp - HTTP Multipart Request Generator
By F2
*/

#if defined _anyhttp_multipart_included
 #endinput
#endif
#define _anyhttp_multipart_included

#include <anyhttp_stringbuilder>
#include <kvizzle_newdecls>
#include <f2stocks>


stock const char AnyHttp_MultiPartBoundary[] = "--------------------AnyHttp--AnyHttp--h7doWqx7m--";

typeset AnyHttp_Multipart_Result {
    function void (bool success, AnyHttpStringBuilder sb, any metadata);
};

enum struct AnyHttpMultipartData {
    KeyValues fields;
    AnyHttpStringBuilder sb;
    AnyHttp_Multipart_Result callback;
    any metadata;
    bool success;
    
    int currentField;
    File currentFile;

    DataPack Export() {
        DataPack pack = new DataPack();
        pack.WriteCell(this.fields);
        this.sb.AddToDataPack(pack);
        pack.WriteFunction(this.callback);
        pack.WriteCell(this.metadata);
        pack.WriteCell(this.success);
        pack.WriteCell(this.currentField);
        pack.WriteCell(this.currentFile);
        return pack;
    }

    void Import(DataPack pack) {
        pack.Reset();
        this.fields = pack.ReadCell();
        this.sb.ReadFromDataPack(pack);
        this.callback = view_as<AnyHttp_Multipart_Result>(pack.ReadFunction());
        this.metadata = pack.ReadCell();
        this.success = pack.ReadCell();
        this.currentField = pack.ReadCell();
        this.currentFile = pack.ReadCell();
        delete pack;
    }
}

stock void AnyHttp_CreateMultipartRequest(KeyValues fields, AnyHttp_Multipart_Result callback, any metadata = 0) {
    AnyHttpMultipartData data;
    data.fields = fields;
    data.sb.Init();
    data.callback = callback;
    data.metadata = metadata;
    data.success = false;
    data.currentField = 1;
    
    RequestFrame(AnyHttp_CreateMultipartRequest_Process, data.Export());
}

static void AnyHttp_CreateMultipartRequest_Process(DataPack pack) {
    AnyHttpMultipartData data;
    data.Import(pack);

    char type[64];
    if (!KvizGetStringExact(data.fields, type, sizeof(type), "%i.type", data.currentField)) {
        data.success = true;
        RequestFrame(AnyHttp_CreateMultipartRequest_Finish, data.Export());
        return;
    }

    if (StrEqual(type, "string")) {
        char name[1024];
        KvizGetStringExact(data.fields, name, sizeof(name), "%i.name", data.currentField);
        char contents[1024];
        KvizGetStringExact(data.fields, contents, sizeof(contents), "%i.value", data.currentField);
        AppendMultipartString(data.sb, name, contents);

        data.currentField++;
    } else if (StrEqual(type, "file")) {
        if (data.currentFile == null) {
            char name[1024];
            KvizGetStringExact(data.fields, name, sizeof(name), "%i.name", data.currentField);
            char filepath[1024];
            KvizGetStringExact(data.fields, filepath, sizeof(filepath), "%i.value", data.currentField);
            AppendMultipartFile_Init(data.sb, name, filepath);
            
            File filehandle = OpenFile(filepath, "r");
            if (filehandle == null) {
                LogError("AppendMultipartFile: Could not open file for reading %s", filepath);
                RequestFrame(AnyHttp_CreateMultipartRequest_Finish, data.Export());
                return;
            }

            data.currentFile = filehandle;
        } else {
            if (data.currentFile.EndOfFile()) {
                data.currentFile.Close();
                data.sb.Append("\n");
                data.currentFile = null;
                data.currentField++;
            } else {
                if (!AppendMultipartFile_Process(data)) {
                    data.currentFile.Close();
                    LogError("AppendMultipartFile: Could not read string from file");
                    RequestFrame(AnyHttp_CreateMultipartRequest_Finish, data.Export());
                    return;
                }
            }
        }
    } else {
        ThrowError("Unknown type");
    }

    RequestFrame(AnyHttp_CreateMultipartRequest_Process, data.Export());
}

static void AnyHttp_CreateMultipartRequest_Finish(DataPack pack) {
    AnyHttpMultipartData data;
    data.Import(pack);

    if (data.success) {
        AppendMultipartEnd(data.sb);
    }

    Call_StartFunction(null, data.callback);
    Call_PushCell(data.success);
    Call_PushArrayEx(data.sb, sizeof(data.sb), SM_PARAM_COPYBACK);
    Call_PushCell(data.metadata);
    Call_Finish();

    data.sb.Dispose();
}



static void AppendMultipartString(AnyHttpStringBuilder sb, const char[] name, const char[] contents) {
    sb.Append("--");
    sb.Append(AnyHttp_MultiPartBoundary);
    sb.Append("\nContent-Disposition: form-data; name=\"");
    sb.Append(name);
    sb.Append("\"\n\n");
    sb.Append(contents);
    sb.Append("\n");
}

static void AppendMultipartFile_Init(AnyHttpStringBuilder sb, const char[] name, const char[] filepath) {
    char filename[PLATFORM_MAX_PATH];
    F2_GetFileName(filename, sizeof(filename), filepath);
        
    sb.Append("--");
    sb.Append(AnyHttp_MultiPartBoundary);
    
    sb.Append("\nContent-Disposition: form-data; name=\"");
    sb.Append(name);
    sb.Append("\"; filename=\"");
    sb.Append(filename);
    sb.Append("\"\n\n");
}

static bool AppendMultipartFile_Process(AnyHttpMultipartData data) {
    char buffer[100 * 1024];
    if (data.currentFile.ReadString(buffer, sizeof(buffer)) == -1) {
        return false;
    }
    
    data.sb.Append(buffer);
    return true;
}

static void AppendMultipartEnd(AnyHttpStringBuilder sb) {
    sb.Append("--");
    sb.Append(AnyHttp_MultiPartBoundary);
    sb.Append("--");
}
