# jcifs-ng (SMB) и его зависимости: ничего не вырезать и не ругаться на отсутствующие классы
-keep class jcifs.** { *; }
-keep class org.bouncycastle.** { *; }
-dontwarn jcifs.**
-dontwarn org.bouncycastle.**
-dontwarn org.slf4j.**
-dontwarn javax.servlet.**
-dontwarn javax.naming.**
-dontwarn org.ietf.jgss.**
-dontwarn javax.security.**
