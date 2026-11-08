# מוסיף הרשאות ושם לאפליקציית האנדרואיד אחרי flutter create
import re, pathlib
p = pathlib.Path('android/app/src/main/AndroidManifest.xml')
s = p.read_text(encoding='utf-8')
perms = ['android.permission.INTERNET', 'android.permission.ACCESS_FINE_LOCATION', 'android.permission.ACCESS_COARSE_LOCATION']
add = ''.join(f'    <uses-permission android:name="{x}"/>\n' for x in perms if x not in s)
s = s.replace('<application', add + '    <application', 1) if add else s
s = re.sub(r'android:label="[^"]*"', 'android:label="Grave Marker"', s, count=1)
if '<queries>' in s and 'android.intent.action.VIEW' not in s.split('<queries>')[1]:
    s = s.replace('<queries>', '<queries>\n        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>', 1)
elif '<queries>' not in s:
    s = s.replace('</manifest>', '    <queries>\n        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>\n    </queries>\n</manifest>')
p.write_text(s, encoding='utf-8')
print(s)

# אייקון האפליקציה
import shutil
for folder, n in {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}.items():
    shutil.copy(f'assets/launcher/{n}.png', f'android/app/src/main/res/mipmap-{folder}/ic_launcher.png')
print('icons copied')
