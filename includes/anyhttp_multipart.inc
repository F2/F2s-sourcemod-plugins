/*
AnyHttp - HTTP Multipart Request Generator
By F2
*/

#if defined _anyhttp_multipart_included
 #endinput
#endif
#define _anyhttp_multipart_included

#include <anyhttp_stringbuilder>
#include <f2stocks>


stock const char AnyHttp_MultiPartBoundary[] = "--------------------AnyHttp--AnyHttp--h7doWqx7m--";

typeset AnyHttp_Multipart_Result {
    function void (bool success, AnyHttpStringBuilder sb, any metadata);
};

enum struct AnyHttpField {
    char name[1024];
    bool isFile;
    char value[1024]; // The string contents, or the path of the file to upload
    char originalPath[PLATFORM_MAX_PATH]; // Files only: The path the file was copied from
    bool ready; // Files only: Whether the file has finished copying
    bool cleanup; // Files only: Whether the file should be deleted afterwards
}

enum struct AnyHttpMultipartData {
    ArrayList fields; // AnyHttpField
    AnyHttpStringBuilder sb;
    Function callback;
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
        this.callback = pack.ReadFunction();
        this.metadata = pack.ReadCell();
        this.success = pack.ReadCell();
        this.currentField = pack.ReadCell();
        this.currentFile = pack.ReadCell();
        delete pack;
    }
}

stock void AnyHttp_CreateMultipartRequest(ArrayList fields, AnyHttp_Multipart_Result callback, any metadata = 0) {
    AnyHttpMultipartData data;
    data.fields = fields;
    data.sb.Init();
    data.callback = callback;
    data.metadata = metadata;
    data.success = false;
    data.currentField = 0;
    
    RequestFrame(AnyHttp_CreateMultipartRequest_Process, data.Export());
}

static void AnyHttp_CreateMultipartRequest_Process(DataPack pack) {
    AnyHttpMultipartData data;
    data.Import(pack);

    if (data.currentField >= data.fields.Length) {
        data.success = true;
        RequestFrame(AnyHttp_CreateMultipartRequest_Finish, data.Export());
        return;
    }

    AnyHttpField field;
    data.fields.GetArray(data.currentField, field);

    if (!field.isFile) {
        AppendMultipartString(data.sb, field.name, field.value);

        data.currentField++;
    } else {
        if (data.currentFile == null) {
            AppendMultipartFile_Init(data.sb, field.name, field.value);

            File filehandle = OpenFile(field.value, "r");
            if (filehandle == null) {
                LogError("AppendMultipartFile: Could not open file for reading %s", field.value);
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
    int bytesRead = data.currentFile.ReadString(buffer, sizeof(buffer), sizeof(buffer) - 1);
    if (bytesRead == -1) {
        return false;
    }
    buffer[bytesRead] = '\0';

    data.sb.Append(buffer);
    return true;
}

static void AppendMultipartEnd(AnyHttpStringBuilder sb) {
    sb.Append("--");
    sb.Append(AnyHttp_MultiPartBoundary);
    sb.Append("--");
}
