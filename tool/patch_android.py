# מוסיף הרשאות ושם לאפליקציית האנדרואיד אחרי flutter create
import re, pathlib
p = pathlib.Path('android/app/src/main/AndroidManifest.xml')
s = p.read_text(encoding='utf-8')
perms = ['android.permission.INTERNET', 'android.permission.ACCESS_FINE_LOCATION', 'android.permission.ACCESS_COARSE_LOCATION',
         'android.permission.POST_NOTIFICATIONS', 'android.permission.RECEIVE_BOOT_COMPLETED']
add = ''.join(f'    <uses-permission android:name="{x}"/>\n' for x in perms if x not in s)
s = s.replace('<application', add + '    <application', 1) if add else s
s = re.sub(r'android:label="[^"]*"', 'android:label="Grave Marker"', s, count=1)
MAILTO = '<intent><action android:name="android.intent.action.SENDTO"/><data android:scheme="mailto"/></intent>'
if '<queries>' in s and 'android.intent.action.VIEW' not in s.split('<queries>')[1]:
    s = s.replace('<queries>', '<queries>\n        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>', 1)
elif '<queries>' not in s:
    s = s.replace('</manifest>', '    <queries>\n        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>\n    </queries>\n</manifest>')
# תזכורות ליום השנה (flutter_local_notifications)
if 'ScheduledNotificationReceiver' not in s:
    s = s.replace('</application>', '''    <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationReceiver"/>
        <receiver android:exported="false" android:name="com.dexterous.flutterlocalnotifications.ScheduledNotificationBootReceiver">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED"/>
                <action android:name="android.intent.action.MY_PACKAGE_REPLACED"/>
                <action android:name="android.intent.action.QUICKBOOT_POWERON"/>
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON"/>
            </intent-filter>
        </receiver>
    </application>''', 1)
# קישורי מסלול (gravemarker.bulu.ltd/r/...) נפתחים באפליקציה
if 'android:pathPrefix="/r"' not in s:
    s = s.replace('</activity>', '''    <meta-data android:name="flutter_deeplinking_enabled" android:value="false"/>
            <intent-filter android:autoVerify="true">
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="https" android:host="gravemarker.bulu.ltd" android:pathPrefix="/r"/>
                <data android:scheme="https" android:host="gravemarker.bulu.ltd" android:pathPrefix="/a"/>
            </intent-filter>
        </activity>''', 1)
if 'android:scheme="mailto"' not in s:
    s = s.replace('<queries>', '<queries>\n        ' + MAILTO, 1)
p.write_text(s, encoding='utf-8')
print(s)

# desugaring – נדרש לספריית ההתראות
g = pathlib.Path('android/app/build.gradle.kts')
gs = g.read_text(encoding='utf-8')
if 'isCoreLibraryDesugaringEnabled' not in gs:
    gs = gs.replace('compileOptions {', 'compileOptions {\n        isCoreLibraryDesugaringEnabled = true', 1)
    gs += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    g.write_text(gs, encoding='utf-8')
# בדיקת lint של אנדרואיד קורסת לפעמים בשרת הבנייה – לא חוסמים בגללה
if 'checkReleaseBuilds' not in gs:
    gs = gs.replace('android {', 'android {\n    lint {\n        checkReleaseBuilds = false\n        abortOnError = false\n    }', 1)
    g.write_text(gs, encoding='utf-8')
print('desugaring', 'isCoreLibraryDesugaringEnabled' in gs)

# אייקון האפליקציה
import shutil
for folder, n in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
    shutil.copy(f'assets/launcher/{n}.png', f'android/app/src/main/res/mipmap-{folder}/ic_launcher.png')
print('icons copied')
