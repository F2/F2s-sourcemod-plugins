/*
AnyHttp - String Builder
By F2
*/

#if defined _anyhttp_stringbuilder_included
 #endinput
#endif
#define _anyhttp_stringbuilder_included


enum struct AnyHttpStringBuilder {
    DataPack pack;
    int length;

    void Init() {
        this.Dispose();

        this.pack = new DataPack();
        this.length = 0;
    }
    
    void Append(const char[] str) {
        this.pack.WriteString(str);
        this.length += strlen(str);
    }

    int Length() {
        return this.length;
    }

    bool CopyToString(char[] str, int maxLength) {
        if (maxLength <= this.length)
            return false;
        
        this.pack.Reset();
        str[0] = '\0';

        while (this.pack.IsReadable()) {
            int len = strlen(str);
            this.pack.ReadString(str[len], maxLength - len);
        }

        return true;
    }

    void Dispose() {
        if (this.pack != null) {
            delete this.pack;
            this.pack = null;
        }
    }

    void AddToDataPack(DataPack pack) {
        pack.WriteCell(this.pack);
        pack.WriteCell(this.length);
    }

    void ReadFromDataPack(DataPack pack) {
        this.pack = pack.ReadCell();
        this.length = pack.ReadCell();
    }
}

