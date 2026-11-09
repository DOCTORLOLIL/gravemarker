# מחבר את מפתח החתימה הקבוע (android/key.properties) לבניית השחרור
import pathlib, re
kts = pathlib.Path('android/app/build.gradle.kts')
groovy = pathlib.Path('android/app/build.gradle')
if kts.exists():
    s = kts.read_text(encoding='utf-8')
    head = ('import java.util.Properties\nimport java.io.FileInputStream\n\n'
            'val keystoreProperties = Properties()\n'
            'val keystorePropertiesFile = rootProject.file("key.properties")\n'
            'if (keystorePropertiesFile.exists()) { keystoreProperties.load(FileInputStream(keystorePropertiesFile)) }\n\n')
    s = head + s
    s = s.replace('android {', '''android {
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }''', 1)
    s = s.replace('signingConfig = signingConfigs.getByName("debug")', 'signingConfig = signingConfigs.getByName("release")')
    kts.write_text(s, encoding='utf-8')
    print('kts signing patched', 'getByName("release")' in s)
elif groovy.exists():
    s = groovy.read_text(encoding='utf-8')
    s = ("def keystoreProperties = new Properties()\n"
         "def keystorePropertiesFile = rootProject.file('key.properties')\n"
         "if (keystorePropertiesFile.exists()) { keystoreProperties.load(new FileInputStream(keystorePropertiesFile)) }\n\n") + s
    s = s.replace('android {', '''android {
    signingConfigs {
        release {
            keyAlias keystoreProperties['keyAlias']
            keyPassword keystoreProperties['keyPassword']
            storeFile file(keystoreProperties['storeFile'])
            storePassword keystoreProperties['storePassword']
        }
    }''', 1)
    s = s.replace('signingConfig signingConfigs.debug', 'signingConfig signingConfigs.release')
    groovy.write_text(s, encoding='utf-8')
    print('groovy signing patched')
