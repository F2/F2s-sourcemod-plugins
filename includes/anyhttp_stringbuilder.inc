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
        
        int pos = 0;
        this.pack.Reset();
        str[0] = '\0';

        char[] buffer = new char[this.length + 1];
        while (this.pack.IsReadable()) {
            this.pack.ReadString(buffer, this.length + 1);    
            StrCat(str, maxLength, buffer);
        }

        return true;
    }

    void Dispose() {
        delete this.pack;
        this.pack = null;
    }
}

