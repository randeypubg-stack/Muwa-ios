# Dependencies supply their own consumer rules. Keep stack line numbers for local crash reports.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute Muwa
# Diagnostics filters app frames by package; class and member names remain obfuscated.
-keeppackagenames app.muwa.nasheeds.**
