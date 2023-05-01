/*
AnyHttp - File Operations
By F2
*/

#if defined _anyhttp_file_included
 #endinput
#endif
#define _anyhttp_file_included

typeset AnyHttp_CopyFile_Result {
    function void (bool success, any metadata);
};

enum struct AnyHttpCopyFileData {
    File source;
    File target;
    AnyHttp_CopyFile_Result callback;
    any metadata;
    bool success;

    DataPack Export() {
        DataPack pack = new DataPack();
        pack.WriteCell(this.source);
        pack.WriteCell(this.target);
        pack.WriteFunction(this.callback);
        pack.WriteCell(this.metadata);
        pack.WriteCell(this.success);
        return pack;
    }

    void Import(DataPack pack) {
        pack.Reset();
        this.source = pack.ReadCell();
        this.target = pack.ReadCell();
        this.callback = view_as<AnyHttp_CopyFile_Result>(pack.ReadFunction());
        this.metadata = pack.ReadCell();
        this.success = pack.ReadCell();
        delete pack;
    }
}

stock void AnyHttp_CopyFile(const char[] sourceFile, const char[] targetFile, AnyHttp_CopyFile_Result callback, any metadata = 0) {
    AnyHttpCopyFileData data;
    data.callback = callback;
    data.metadata = metadata;
    data.success = false;
    
    data.source = OpenFile(sourceFile, "r", false);	
    if (data.source == null) {
        RequestFrame(AnyHttp_CopyFile_Finish, data.Export());
        return;
    }

    data.target = OpenFile(targetFile, "w", false);	
    if (data.target == null) {
        data.source.Close();
        RequestFrame(AnyHttp_CopyFile_Finish, data.Export());
        return;
    }
    
    RequestFrame(AnyHttp_CopyFile_Process, data.Export());
}

static void AnyHttp_CopyFile_Process(DataPack pack) {
    AnyHttpCopyFileData data;
    data.Import(pack);

    if (data.source.EndOfFile()) {
        data.source.Close();
        data.target.Close();
        data.success = true;
        RequestFrame(AnyHttp_CopyFile_Finish, data.Export());
        return;
    }

    int bytesRead;
    char buff[100 * 1024];
    bytesRead = data.source.ReadString(buff, sizeof(buff));
    if (bytesRead == -1 || !data.target.WriteString(buff, false)) {
        data.source.Close();
        data.target.Close();
        RequestFrame(AnyHttp_CopyFile_Finish, data.Export());
        return;
    }

    RequestFrame(AnyHttp_CopyFile_Process, data.Export());
}

static void AnyHttp_CopyFile_Finish(DataPack pack) {
    AnyHttpCopyFileData data;
    data.Import(pack);

    Call_StartFunction(null, data.callback);
    Call_PushCell(data.success);
    Call_PushCell(data.metadata);
    Call_Finish();
}
