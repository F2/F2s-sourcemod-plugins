/*
AnyHttp - String Builder
By F2
*/

#if defined _anyhttp_stringbuilder_included
 #endinput
#endif
#define _anyhttp_stringbuilder_included


methodmap AnyHttpStringBuilder < Handle {
    property int Health {
        public native get();
        public native set(int health);
    }
}


enum struct AnyHttpStringBuilder {
    DataPack pack;
    int length;

    void Init() {
        this.pack = new Init();
        this.length = 0;
    }
    
    void Append(const char[] str) {
        this.pack.WriteString(str);
        this.length += strlen(str);
    }

    property bool Length {
        public get() {
            return this.length;
        }
    }

    void ToString(char[] str, int maxLength) {
        int pos = 0;

        this.pack.Reset();
    }

    void Dispose() {
        delete this.pack;
        this.pack = null;
    }
}
